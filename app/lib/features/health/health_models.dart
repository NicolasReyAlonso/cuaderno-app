/// Datos de la pulsera y la báscula: de muestras sueltas de Health Connect / Salud
/// a un resumen por día y una lista de actividades, con el formato de POST /health/sync.
///
/// Sin dependencias del paquete health, para poder probarlo con tests.
library;

/// Una medida suelta. [kind]: active_kcal | sleep | resting_hr | hrv | weight.
class Sample {
  final String kind, source;
  final double value;
  final DateTime from, to;
  const Sample(this.kind, this.value, this.from, this.to, {this.source = ''});
}

class WorkoutSample {
  final String id, kind, source;
  final DateTime from, to;
  final double? kcal, distanceM;
  const WorkoutSample({required this.id, required this.kind, required this.from, required this.to, this.kcal, this.distanceM, this.source = ''});
}

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Suma por día y por fuente y se queda con la fuente que más marca: si la pulsera y el
/// móvil cuentan lo mismo, sumarlos lo duplicaría.
Map<DateTime, double> _bestSourceSum(Iterable<Sample> xs, DateTime Function(Sample) dayOf, double Function(Sample) amount) {
  final bySource = <DateTime, Map<String, double>>{};
  for (final s in xs) {
    final m = bySource.putIfAbsent(dayOf(s), () => {});
    m[s.source] = (m[s.source] ?? 0) + amount(s);
  }
  return {for (final e in bySource.entries) e.key: e.value.values.reduce((a, b) => a > b ? a : b)};
}

Map<DateTime, double> _mean(Iterable<Sample> xs) {
  final acc = <DateTime, List<double>>{};
  for (final s in xs) {
    acc.putIfAbsent(_day(s.from), () => []).add(s.value);
  }
  return {for (final e in acc.entries) e.key: e.value.reduce((a, b) => a + b) / e.value.length};
}

/// Resúmenes por día (JSON de HealthDayIn) entre [first] y [last], ambos incluidos.
/// [steps]: total por día ya agregado por el sistema (Health Connect quita duplicados).
/// Los días sin ningún dato no se mandan.
List<Map<String, dynamic>> dailySummaries({required DateTime first, required DateTime last, required Map<DateTime, int> steps, required List<Sample> samples}) {
  Iterable<Sample> of(String k) => samples.where((s) => s.kind == k);
  final kcal = _bestSourceSum(of('active_kcal'), (s) => _day(s.from), (s) => s.value);
  // El sueño cuenta para el día en que te despiertas
  final sleep = _bestSourceSum(of('sleep'), (s) => _day(s.to), (s) => s.to.difference(s.from).inSeconds / 60);
  final rhr = _mean(of('resting_hr'));
  final hrv = _mean(of('hrv'));
  final weight = <DateTime, Sample>{}; // el primero del día: el de por la mañana
  for (final s in of('weight')) {
    final d = _day(s.from);
    if (weight[d] == null || s.from.isBefore(weight[d]!.from)) weight[d] = s;
  }

  final out = <Map<String, dynamic>>[];
  for (var d = _day(first); !d.isAfter(_day(last)); d = DateTime(d.year, d.month, d.day + 1)) {
    final day = {
      'steps': steps[d],
      'active_kcal': kcal[d]?.round(),
      'sleep_minutes': sleep[d]?.round().clamp(0, 1440),
      'resting_hr': rhr[d]?.round(),
      'hrv_ms': hrv[d] == null ? null : (hrv[d]! * 10).round() / 10,
      'weight_kg': weight[d] == null ? null : (weight[d]!.value * 10).round() / 10,
    };
    if (day.values.any((v) => v != null)) out.add({'date': _iso(d), ...day});
  }
  return out;
}

/// Actividades (JSON de ActivityIn). Las horas van en UTC con zona para que el servidor no dude.
List<Map<String, dynamic>> activityPayload(List<WorkoutSample> ws) => [
      for (final w in ws)
        if (!w.to.isBefore(w.from) && w.id.isNotEmpty)
          {
            'external_id': w.id.length > 120 ? w.id.substring(0, 120) : w.id,
            'kind': w.kind.length > 40 ? w.kind.substring(0, 40) : w.kind,
            'started_at': w.from.toUtc().toIso8601String(),
            'ended_at': w.to.toUtc().toIso8601String(),
            'kcal': w.kcal?.round(),
            'distance_m': w.distanceM?.round(),
            'source': w.source.length > 80 ? w.source.substring(0, 80) : w.source,
          },
    ];

/// Nombre en español de los tipos de actividad más comunes de Health Connect / Salud.
String activityLabel(String kind) => switch (kind) {
      'WALKING' => 'Caminar',
      'RUNNING' || 'RUNNING_TREADMILL' => 'Correr',
      'BIKING' || 'BIKING_STATIONARY' => 'Bici',
      'SWIMMING' || 'SWIMMING_POOL' || 'SWIMMING_OPEN_WATER' => 'Natación',
      'STRENGTH_TRAINING' || 'TRADITIONAL_STRENGTH_TRAINING' || 'FUNCTIONAL_STRENGTH_TRAINING' || 'WEIGHTLIFTING' => 'Fuerza',
      'HIGH_INTENSITY_INTERVAL_TRAINING' => 'HIIT',
      'ELLIPTICAL' => 'Elíptica',
      'ROWING' || 'ROWING_MACHINE' => 'Remo',
      'HIKING' => 'Senderismo',
      'YOGA' => 'Yoga',
      'PILATES' => 'Pilates',
      'STAIR_CLIMBING' || 'STAIR_CLIMBING_MACHINE' || 'STAIRS' => 'Escaleras',
      'SOCCER' => 'Fútbol',
      'BASKETBALL' => 'Baloncesto',
      'TENNIS' => 'Tenis',
      'PADEL' => 'Pádel',
      _ => kind.isEmpty ? 'Actividad' : kind[0] + kind.substring(1).toLowerCase().replaceAll('_', ' '),
    };

/// Actividad guardada en el servidor (GET /health/activities).
class ActivityRecord {
  final String id, kind, source;
  final DateTime start, end;
  final int? kcal, distanceM;
  const ActivityRecord({required this.id, required this.kind, required this.start, required this.end, this.kcal, this.distanceM, this.source = ''});

  Duration get duration => end.difference(start);

  factory ActivityRecord.fromJson(Map<String, dynamic> j) => ActivityRecord(
        id: j['id'] as String,
        kind: j['kind'] as String,
        start: DateTime.parse(j['started_at'] as String).toLocal(),
        end: DateTime.parse(j['ended_at'] as String).toLocal(),
        kcal: j['kcal'] as int?,
        distanceM: j['distance_m'] as int?,
        source: j['source'] as String? ?? '',
      );
}

/// Resultado de POST /health/sync, en una frase para el usuario.
String syncMessage(Map<String, dynamic> r) {
  final parts = <String>[
    '${r['days']} ${r['days'] == 1 ? 'día' : 'días'}',
    if ((r['activities_new'] as int) > 0) '${r['activities_new']} ${r['activities_new'] == 1 ? 'actividad nueva' : 'actividades nuevas'}',
    if ((r['weights_set'] as int) > 0) '${r['weights_set']} ${r['weights_set'] == 1 ? 'peso' : 'pesos'} de la báscula',
  ];
  final kept = r['weights_kept_manual'] as int;
  return 'Sincronizado: ${parts.join(', ')}.${kept > 0 ? ' $kept ${kept == 1 ? 'peso tuyo se queda' : 'pesos tuyos se quedan'} como lo apuntaste.' : ''}';
}
