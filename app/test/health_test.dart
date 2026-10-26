import 'package:cuaderno/features/body/body_page.dart' show bandLine, sleepText;
import 'package:cuaderno/features/body/models.dart';
import 'package:cuaderno/features/health/health_models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _t(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

void main() {
  test('resumen diario: sin duplicar fuentes, sueño al despertar y peso de la mañana', () {
    final days = dailySummaries(
      first: DateTime(2026, 10, 19),
      last: DateTime(2026, 10, 22),
      steps: {DateTime(2026, 10, 20): 9500},
      samples: [
        // Pulsera y móvil cuentan las mismas kcal: se queda la fuente que más marca, no la suma
        Sample('active_kcal', 200, _t(20, 9), _t(20, 10), source: 'Zepp'),
        Sample('active_kcal', 250, _t(20, 18), _t(20, 19), source: 'Zepp'),
        Sample('active_kcal', 300, _t(20, 9), _t(20, 19), source: 'Teléfono'),
        // Noche del 20 al 21: cuenta para el 21
        Sample('sleep', 0, _t(20, 23, 30), _t(21, 7, 15), source: 'Zepp'),
        Sample('resting_hr', 58, _t(21, 4), _t(21, 4)),
        Sample('resting_hr', 61, _t(21, 12), _t(21, 12)),
        Sample('hrv', 41.26, _t(21, 4), _t(21, 4)),
        Sample('weight', 97.83, _t(22, 20), _t(22, 20)),
        Sample('weight', 97.41, _t(22, 7, 30), _t(22, 7, 30)),
      ],
    );
    expect(days.map((d) => d['date']), ['2026-10-20', '2026-10-21', '2026-10-22']); // el 19 no tiene nada
    expect(days[0], {'date': '2026-10-20', 'steps': 9500, 'active_kcal': 450, 'sleep_minutes': null, 'resting_hr': null, 'hrv_ms': null, 'weight_kg': null});
    expect((days[1]['sleep_minutes'], days[1]['resting_hr'], days[1]['hrv_ms']), (465, 60, 41.3));
    expect(days[2]['weight_kg'], 97.4);
  });

  test('el resumen recorre los días bien en el cambio de hora', () {
    final days = dailySummaries(
      first: DateTime(2026, 10, 24),
      last: DateTime(2026, 10, 27),
      steps: {for (var d = 24; d <= 27; d++) DateTime(2026, 10, d): 1000 + d},
      samples: const [],
    );
    expect(days.map((d) => d['date']), ['2026-10-24', '2026-10-25', '2026-10-26', '2026-10-27']);
  });

  test('actividades: horas en UTC con zona y textos recortados a lo que acepta el servidor', () {
    final json = activityPayload([
      WorkoutSample(id: 'abc', kind: 'RUNNING', from: DateTime.utc(2026, 10, 20, 5), to: DateTime.utc(2026, 10, 20, 5, 35), kcal: 319.6, distanceM: 5203.4, source: 'Zepp'),
      WorkoutSample(id: 'mal', kind: 'WALKING', from: DateTime.utc(2026, 10, 20, 6), to: DateTime.utc(2026, 10, 20, 5)), // termina antes: fuera
      WorkoutSample(id: 'x' * 200, kind: 'OTHER', from: DateTime.utc(2026, 10, 21), to: DateTime.utc(2026, 10, 21, 1), source: 's' * 100),
    ]);
    expect(json.length, 2);
    expect(json[0], {
      'external_id': 'abc', 'kind': 'RUNNING', 'started_at': '2026-10-20T05:00:00.000Z', 'ended_at': '2026-10-20T05:35:00.000Z',
      'kcal': 320, 'distance_m': 5203, 'source': 'Zepp',
    });
    expect(((json[1]['external_id'] as String).length, (json[1]['source'] as String).length), (120, 80));
  });

  test('nombres de actividades y mensaje de sincronización en español', () {
    expect(activityLabel('RUNNING'), 'Correr');
    expect(activityLabel('TRADITIONAL_STRENGTH_TRAINING'), 'Fuerza');
    expect(activityLabel('MARTIAL_ARTS'), 'Martial arts');
    expect(syncMessage({'days': 30, 'activities_new': 2, 'activities_updated': 5, 'weights_set': 1, 'weights_kept_manual': 3}),
        'Sincronizado: 30 días, 2 actividades nuevas, 1 peso de la báscula. 3 pesos tuyos se quedan como lo apuntaste.');
    expect(syncMessage({'days': 1, 'activities_new': 0, 'activities_updated': 0, 'weights_set': 0, 'weights_kept_manual': 0}), 'Sincronizado: 1 día.');
  });

  test('línea de la pulsera en la semana', () {
    expect(sleepText(425), '7 h 05');
    final w = BodyWeek.fromJson({
      'monday': '2026-10-19', 'avg_weight': 97.5, 'n_weights': 3, 'avg_kcal': null, 'avg_protein': null, 'waist_cm': null,
      'delta_kg': null, 'delta_pct': null, 'pace': null,
      'avg_steps': 8950.4, 'avg_active_kcal': 420.2, 'avg_sleep_minutes': 425, 'avg_resting_hr': 58.4,
    });
    expect(bandLine(w), '8.950 pasos/día · 420 kcal activas · sueño 7 h 05 · pulso 58');
  });
}
