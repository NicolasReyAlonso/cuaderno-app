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

    // Entreno: catálogo para entrenar sin conexión, sesión guardada «sin conexión» y plan creado online
    final ref = decode(await db.readMeta('ref_data'))!;
    expect(((ref['exercises'] as List).length, (ref['templates'] as List).isNotEmpty), (61, true));
    await engine.put('workout_session', '2026-10-20/piernaA', {
      'date': '2026-10-20', 'day_key': 'piernaA', 'program_id': 'definicion-5d', 'week': 1,
      'slots': [{'slot_exercise_id': 'sentadilla_smith', 'exercise_id': 'sentadilla_smith', 'sets': List.filled(4, {'load_kg': 60, 'reps': 10})}],
    });
    final plan = {'name': 'Mío', 'weeks': 1, 'days': [{'key': 'espalda', 'weekday': 2, 'name': 'Espalda', 'slots': [
      {'exercise_id': 'remo_barra', 'sets': 3, 'rep_min': 8, 'rep_max': 12}]}]};
    final created = (await dio.post<Map<String, dynamic>>('/programs', data: plan)).data!;
    r = await engine.sync();
    expect(r.rejected, 0);
    final next = (await dio.get<Map<String, dynamic>>('/workouts/2026-10-27/piernaA/plan')).data!;
    expect((next['slots'] as List).firstWhere((x) => x['slot_exercise_id'] == 'sentadilla_smith')['hint']['text'], 'Sube 2,5 kg');
    expect(decodeData(await db.record('program', created['id'] as String))!['name'], 'Mío');

    // Ejercicio y plan que lo usa creados «sin conexión», y activado: llegan en orden en un envío
    final exId = 'u:${uuidV4().replaceAll('-', '').substring(0, 12)}';
    final progId = 'u:${uuidV4().replaceAll('-', '').substring(0, 12)}';
    await engine.put('exercise', exId, {'name': 'Remo en máquina', 'muscle_group': 'Espalda', 'cue': '', 'unit': 'reps', 'load_mode': 'kg',
      'is_compound': true, 'default_rep_min': null, 'default_rep_max': null, 'figure': {}, 'media': []});
    await engine.put('program', progId, {'name': 'Offline', 'weeks': 1, 'days': [{'week': 1, 'key': 'espalda', 'position': 0, 'weekday': 2,
      'name': 'Espalda', 'short': '', 'focus': '', 'color': 'blue', 'slots': [{'exercise_id': exId, 'sets': 3, 'rep_min': 8, 'rep_max': 12, 'rest': '', 'is_core': false}]}]});
    await engine.put('profile', 'me', {...decodeData(await db.record('profile', 'me'))!, 'program_id': progId, 'program_started_on': '2026-10-19'});
    r = await engine.sync();
    expect((r.applied, r.rejected, r.conflicts), (3, 0, 0));
    expect((await dio.get<Map<String, dynamic>>('/workouts/2026-10-27/today')).data!['day_key'], 'espalda');
    expect(decodeData(await db.record('exercise', exId))!['figure'], contains('a')); // la figura genérica, del servidor
    await db.close();
  }, skip: base == null ? 'Pon CUADERNO_LIVE=http://localhost:8000 para probar contra el servidor' : null);
}
