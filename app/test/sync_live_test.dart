// Prueba la sincronización contra el backend de verdad. Solo corre si se pide:
//   CUADERNO_LIVE=http://localhost:8000 flutter test test/sync_live_test.dart
// Crea una cuenta de prueba (prueba-sync-…@example.com); bórrala después si quieres.
import 'dart:io';

import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_api.dart';
import 'package:cuaderno/core/local/sync_engine.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = Platform.environment['CUADERNO_LIVE'];
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('móvil sin conexión, cambio en otro dispositivo, conflicto y «lo mío»', () async {
    final dio = Dio(BaseOptions(baseUrl: base!));
    final email = 'prueba-sync-${DateTime.now().millisecondsSinceEpoch}@example.com';
    final tok = (await dio.post<Map<String, dynamic>>('/auth/register', data: {'email': email, 'password': 'contraseña-larga'})).data!['access_token'];
    dio.options.headers['Authorization'] = 'Bearer $tok';
    final db = LocalDb(NativeDatabase.memory());
    final engine = SyncEngine(db, DioSyncApi(dio));

    await engine.sync();
    expect(decodeData(await db.record('profile', 'me'))!['kcal_target'], 2000);

    // Apuntado «sin conexión» y enviado al volver
    await engine.put('body_entry', '2026-10-20', {'date': '2026-10-20', 'weight_kg': 98.1, 'waist_cm': null, 'kcal': null, 'protein_g': null});
    var r = await engine.sync();
    expect(r.applied, 1);
    final summary = (await dio.get<Map<String, dynamic>>('/body/summary')).data!;
    expect((summary['entries'] as List).single['weight_kg'], 98.1);

    // Otro dispositivo lo cambia por la API normal mientras el móvil lo cambia sin conexión
    await engine.put('body_entry', '2026-10-20', {'date': '2026-10-20', 'weight_kg': 97.9, 'waist_cm': null, 'kcal': null, 'protein_g': null});
    await dio.put<void>('/body/2026-10-20', data: {'weight_kg': 97.5});
    r = await engine.sync();
    expect(r.conflicts, 1);
    final op = (await db.select(db.outbox).get()).single;
    expect(RemoteRecord.fromJson(decode(op.serverRecord)!).data!['weight_kg'], 97.5);

    await engine.keepMine(op);
    r = await engine.sync();
    expect((r.applied, r.conflicts), (1, 0));
    final after = (await dio.get<Map<String, dynamic>>('/body/summary')).data!;
    expect((after['entries'] as List).single['weight_kg'], 97.9);
    expect(await db.select(db.outbox).get(), isEmpty);

    // Comidas: alimento, plato y diario creados «sin conexión», enviados en una sincronización
    expect(await db.readMeta('ref_hash'), isNotNull); // catálogo de alimentos guardado para buscar
    final fid = 'u:${uuidV4().replaceAll('-', '').substring(0, 12)}';
    final did = uuidV4();
    await engine.put('food', fid, {'name': 'Skyr marca X', 'category': 'Mis alimentos', 'kcal': 63, 'protein': 11, 'carbs': 4, 'fat': 0.2, 'default_portion_g': 150});
    await engine.put('dish', did, {
      'name': 'Bol', 'servings': 2, 'cooked_weight_g': null,
      'ingredients': [{'food_id': fid, 'name': 'Skyr marca X', 'grams': 300, 'kcal': 63, 'protein': 11, 'carbs': 4, 'fat': 0.2}],
    });
    await engine.put('diary_item', uuidV4(), {
      'date': '2026-10-20', 'meal': 'desayuno', 'name': 'Bol', 'food_id': null, 'dish_id': did, 'grams': 150,
      'kcal': 94.5, 'protein': 16.5, 'carbs': 6, 'fat': 0.3, 'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    r = await engine.sync();
    expect((r.applied, r.rejected), (3, 0));
    final diary = (await dio.get<Map<String, dynamic>>('/diary/2026-10-20')).data!;
    expect((diary['items'] as List).single['kcal'], 94.5);
    final row = ((await dio.get<Map<String, dynamic>>('/body/summary')).data!['entries'] as List).single;
    expect((row['from_diary'], row['kcal'], row['weight_kg']), (true, 94, 97.9)); // el diario manda sobre lo manual
    await db.close();
  }, skip: base == null ? 'Pon CUADERNO_LIVE=http://localhost:8000 para probar contra el servidor' : null);
}
