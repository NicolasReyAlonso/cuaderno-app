import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_api.dart';
import 'package:cuaderno/core/local/sync_engine.dart';
import 'package:cuaderno/features/body/body_repository.dart';
import 'package:cuaderno/features/body/models.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoServer implements SyncApi {
  @override
  Future<PullPage> pull(int since) => throw const OfflineException();
  @override
  Future<List<PushResult>> push(List<OutboxOp> ops) => throw const OfflineException();
  @override
  Future<Map<String, dynamic>?> reference(String? knownHash) => throw const OfflineException();
}

BodyEntry _w(String d, double kg) => BodyEntry(date: DateTime.parse(d), weightKg: kg);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('el resumen del móvil da lo mismo que el del servidor (test_body_summary)', () {
    final profile = Profile.fromJson({'start_date': '2026-10-19', 'start_weight_kg': 99, 'start_body_fat_pct': 30.7, 'kcal_target': 2000, 'protein_target_g': 160});
    final s = computeSummary(
      [_w('2026-10-20', 98.1), _w('2026-10-21', 97.7), _w('2026-10-22', 98.2), _w('2026-10-27', 97.4), _w('2026-10-28', 97.2)],
      profile,
      const [],
    );
    expect((s.leanMass, s.goal25Weight, s.goal20Weight), (68.6, 91.5, 85.8));
    expect(s.currentWeight, 97.6);
    expect(s.weeks.length, 2);
    expect(s.weeks[0].deltaKg, isNull); // la semana del inicio no se compara con el peso inicial
    expect(s.weeks[1].pace, 'on_track');
    expect(s.weeks[1].deltaKg, closeTo(-0.7, 1e-9));
  });

  test('semanas con datos de la pulsera (como test_weekly_summary_averages_wristband_data)', () {
    final s = computeSummary([_w('2026-10-20', 98)], null, const [
      {'date': '2026-10-19', 'steps': 8000, 'active_kcal': 400, 'sleep_minutes': 420, 'resting_hr': 60},
      {'date': '2026-10-20', 'steps': 10000, 'sleep_minutes': 360},
      {'date': '2026-10-26', 'steps': 12000},
    ]);
    final w1 = s.weeks[0];
    expect((w1.avgSteps, w1.avgActiveKcal, w1.avgSleepMinutes, w1.avgRestingHr, w1.avgWeight), (9000.0, 400.0, 390.0, 60.0, 98.0));
    expect((s.weeks[1].avgSteps, s.weeks[1].avgWeight), (12000.0, null));
    expect(s.entries.map((e) => e.date.day), [20]); // un día solo con pulsera no es un registro de peso
  });

  test('sin perfil ni pesos no se inventa nada', () {
    final s = computeSummary(const [], null, const []);
    expect((s.currentWeight, s.bodyFatEst, s.leanMass), (null, null, null));
    expect(s.weeks, isEmpty);
  });

  test('ritmo semanal con los mismos cortes que el backend', () {
    expect([-1.2, -1.1, -0.5, -0.4, -0.2, -0.15, 0.0, 0.3].map(classifyPace),
        ['fast', 'fast', 'on_track', 'on_track', 'slow', 'slow', 'stalled', 'stalled']);
  });

  group('guardar en local', () {
    late LocalDb db;
    late BodyRepository repo;
    var changes = 0;
    setUp(() {
      db = LocalDb(NativeDatabase.memory());
      changes = 0;
      repo = BodyRepository(SyncEngine(db, _NoServer()), () => changes++);
    });
    tearDown(() => db.close());

    test('un registro conserva lo que el formulario no toca y el peso cambiado pasa a manual', () async {
      // Llegó del servidor: peso de la báscula y kcal escritas a mano
      await db.upsertRecord(RecordsCompanion.insert(
        entity: 'body_entry',
        id: '2026-10-20',
        data: const Value('{"date":"2026-10-20","weight_kg":97.9,"waist_cm":null,"kcal":2100,"protein_g":150,"weight_source":"health"}'),
        serverVersion: const Value(1),
      ));
      await repo.saveEntry(DateTime(2026, 10, 20), {'weight_kg': 97.9, 'waist_cm': 104.0});
      var d = decodeData(await db.record('body_entry', '2026-10-20'))!;
      expect((d['kcal'], d['protein_g'], d['waist_cm'], d['weight_source']), (2100, 150, 104.0, 'health')); // mismo peso: sigue siendo de la báscula
      await repo.saveEntry(DateTime(2026, 10, 20), {'weight_kg': 97.5, 'waist_cm': 104.0});
      d = decodeData(await db.record('body_entry', '2026-10-20'))!;
      expect(d['weight_source'], 'manual');
      expect(changes, 2);
      expect((await db.select(db.outbox).get()).single.baseVersion, 1);
    });

    test('el perfil conserva el plan activo al cambiar los objetivos', () async {
      await db.upsertRecord(RecordsCompanion.insert(
        entity: 'profile',
        id: 'me',
        data: const Value('{"name":"Nico","start_date":null,"start_weight_kg":null,"start_body_fat_pct":null,'
            '"kcal_target":2000,"protein_target_g":160,"program_id":"u:abc","program_started_on":"2026-10-19"}'),
        serverVersion: const Value(3),
      ));
      await repo.saveProfile({'start_date': '2026-10-19', 'start_weight_kg': 99.0, 'start_body_fat_pct': 30.7, 'kcal_target': 2050, 'protein_target_g': 170});
      final d = decodeData(await db.record('profile', 'me'))!;
      expect((d['program_id'], d['name'], d['kcal_target']), ('u:abc', 'Nico', 2050));
    });
  });
}
