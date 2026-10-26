import 'dart:convert';
import 'dart:io';

import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_controller.dart';
import 'package:cuaderno/features/programs/programs_repository.dart';
import 'package:cuaderno/features/workout/models.dart';
import 'package:cuaderno/features/workout/workout_repository.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _catalog = jsonDecode(File('../backend/app/data/catalog.json').readAsStringSync()) as Map<String, dynamic>;

/// Lo mismo que devuelve GET /sync/reference, a partir del catálogo del backend.
Map<String, dynamic> _reference() {
  final alts = <String, List<String>>{};
  for (final a in [...(_catalog['alternatives'] as List)]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int))) {
    alts.putIfAbsent(a['exercise_id'] as String, () => []).add(a['alternative_id'] as String);
  }
  final p = _catalog['program'] as Map<String, dynamic>;
  return {
    'hash': 'h',
    'foods': [],
    'exercises': [
      for (final e in _catalog['exercises'] as List)
        {...e as Map<String, dynamic>, 'default_rep_min': (e['default_reps'] as List?)?[0], 'default_rep_max': (e['default_reps'] as List?)?[1], 'media': []},
    ],
    'alternatives': alts,
    'templates': [
      {'id': 'definicion-5d', 'name': p['name'], 'weeks': 1, 'days': [for (final d in p['days'] as List) {...d as Map<String, dynamic>, 'key': d['id'], 'week': 1}]},
    ],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalDb db;
  late ProviderContainer c;

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    db = LocalDb(NativeDatabase.memory());
    c = ProviderContainer(overrides: [localDbProvider.overrideWithValue(db)]);
    await db.upsertRecord(RecordsCompanion.insert(
      entity: 'profile',
      id: 'me',
      data: const Value('{"name":"","start_date":null,"start_weight_kg":null,"start_body_fat_pct":null,"kcal_target":2000,'
          '"protein_target_g":160,"program_id":"definicion-5d","program_started_on":null}'),
      serverVersion: const Value(1),
    ));
    for (final p in [catalogProvider, todayProvider(DateTime(2026, 10, 20)), programsProvider]) {
      c.listen(p, (_, __) {});
    }
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('sin datos de consulta descargados, Entreno lo dice en vez de fallar', () async {
    await settle();
    expect(c.read(catalogProvider).error.toString(), startsWith('Conecta una vez con el servidor'));
  });

  test('Entreno entero sin servidor: plan, guardar y la semana siguiente', () async {
    await db.setMeta('ref_data', jsonEncode(_reference()));
    await settle();
    final cat = c.read(catalogProvider).value!;
    expect((cat.programName, cat.days.length, cat.exercises.length), (_catalog['program']['name'], 5, 61));
    expect(c.read(todayProvider(DateTime(2026, 10, 20))).value!.dayKey, 'piernaA'); // martes

    await c.read(workoutRepositoryProvider).save(DateTime(2026, 10, 20), 'piernaA', 1, [
      (slot: 'sentadilla_smith', exercise: 'sentadilla_smith', sets: List.filled(4, const SetEntry(60, 10))),
      (slot: 'crunch_polea', exercise: 'crunch', sets: List.filled(3, const SetEntry(0, 15))),
    ]);
    expect((await db.select(db.outbox).get()).single.recordId, '2026-10-20/piernaA');

    final k = (date: DateTime(2026, 10, 27), day: 'piernaA', week: 1);
    c.listen(dayPlanProvider(k), (_, __) {});
    await settle();
    final plan = c.read(dayPlanProvider(k)).value!;
    final crunch = plan.slots.firstWhere((s) => s.slotExerciseId == 'crunch_polea');
    expect((crunch.exerciseId, crunch.hint!.kind), ('crunch', 'up'));

    // Guardar mal da el mismo mensaje que el servidor y no escribe nada
    await expectLater(
      c.read(workoutRepositoryProvider).save(DateTime(2026, 10, 21), 'brazos', 1, [(slot: 'press_banca', exercise: 'press_banca', sets: const [SetEntry(1, 1)])]),
      throwsA(predicate((e) => '$e' == '«press_banca» no es un ejercicio de este día.')),
    );
    expect((await db.select(db.outbox).get()).length, 1);
  });

  test('activar un plan propio funciona sin conexión y cambia Entreno', () async {
    await db.setMeta('ref_data', jsonEncode(_reference()));
    await db.upsertRecord(RecordsCompanion.insert(
      entity: 'program',
      id: 'u:abc',
      data: Value(jsonEncode({
        'name': 'Mío',
        'weeks': 1,
        'days': [
          {'week': 1, 'key': 'espalda', 'position': 0, 'weekday': 2, 'name': 'Espalda', 'short': '', 'focus': '', 'color': 'blue',
           'slots': [{'exercise_id': 'remo_barra', 'sets': 3, 'rep_min': 8, 'rep_max': 12, 'rest': '', 'is_core': false}]},
        ],
      })),
      serverVersion: const Value(1),
    ));
    await settle();
    expect(c.read(programsProvider).value!.map((p) => (p.id, p.mine, p.active)), [('u:abc', true, false), ('definicion-5d', false, true)]);

    await c.read(programsRepositoryProvider).activate('u:abc', DateTime(2026, 10, 19));
    await settle();
    expect(c.read(catalogProvider).value!.programName, 'Mío');
    expect(c.read(todayProvider(DateTime(2026, 10, 20))).value!.dayKey, 'espalda');
    final draft = await c.read(programsRepositoryProvider).get('definicion-5d');
    expect((draft.mine, draft.days.length), (false, 5)); // las plantillas se ven sin conexión
    expect(decodeData(await db.record('profile', 'me'))!['program_started_on'], '2026-10-19');
  });
}
