/// Peso y medidas: registros por día, resumen (media 7 días, grasa estimada) y semanas.
library;

double? _n(dynamic v) => (v as num?)?.toDouble();
DateTime? _date(dynamic v) => v == null ? null : DateTime.parse(v as String);

class BodyEntry {
  final DateTime date;
  final double? weightKg, waistCm, kcal, proteinG;
  final bool fromDiary; // kcal y proteína salen del diario de comidas
  const BodyEntry({required this.date, this.weightKg, this.waistCm, this.kcal, this.proteinG, this.fromDiary = false});

  factory BodyEntry.fromJson(Map<String, dynamic> j) => BodyEntry(
        date: DateTime.parse(j['date'] as String),
        weightKg: _n(j['weight_kg']),
        waistCm: _n(j['waist_cm']),
        kcal: _n(j['kcal']),
        proteinG: _n(j['protein_g']),
        fromDiary: j['from_diary'] as bool,
      );
}

/// Ritmo semanal (services/body.py): fast | on_track | slow | stalled.
const paceLabels = {'fast': 'Rápido', 'on_track': 'En ritmo', 'slow': 'Lento', 'stalled': 'Estancado'};

class BodyWeek {
  final DateTime monday;
  final double? avgWeight, avgKcal, avgProtein, waistCm, deltaKg, deltaPct;
  final int nWeights;
  final String? pace;
  const BodyWeek({required this.monday, required this.nWeights, this.avgWeight, this.avgKcal, this.avgProtein, this.waistCm, this.deltaKg, this.deltaPct, this.pace});

  factory BodyWeek.fromJson(Map<String, dynamic> j) => BodyWeek(
        monday: DateTime.parse(j['monday'] as String),
        nWeights: j['n_weights'] as int,
        avgWeight: _n(j['avg_weight']),
        avgKcal: _n(j['avg_kcal']),
        avgProtein: _n(j['avg_protein']),
        waistCm: _n(j['waist_cm']),
        deltaKg: _n(j['delta_kg']),
        deltaPct: _n(j['delta_pct']),
        pace: j['pace'] as String?,
      );
}

class BodySummary {
  final double? currentWeight, bodyFatEst, leanMass, goal25Weight, goal20Weight;
  final DateTime? currentWeightDate;
  final List<BodyWeek> weeks;
  final List<BodyEntry> entries; // por fecha ascendente
  const BodySummary({this.currentWeight, this.currentWeightDate, this.bodyFatEst, this.leanMass, this.goal25Weight, this.goal20Weight, this.weeks = const [], this.entries = const []});

  factory BodySummary.fromJson(Map<String, dynamic> j) => BodySummary(
        currentWeight: _n(j['current_weight']),
        currentWeightDate: _date(j['current_weight_date']),
        bodyFatEst: _n(j['body_fat_est']),
        leanMass: _n(j['lean_mass']),
        goal25Weight: _n(j['goal_25_weight']),
        goal20Weight: _n(j['goal_20_weight']),
        weeks: [for (final w in j['weeks'] as List) BodyWeek.fromJson(w as Map<String, dynamic>)],
        entries: [for (final e in j['entries'] as List) BodyEntry.fromJson(e as Map<String, dynamic>)],
      );

  BodyEntry? entryOn(DateTime d) {
    for (final e in entries) {
      if (sameDay(e.date, d)) return e;
    }
    return null;
  }
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Días de calendario de [from] a [to]. Con Duration fallaría en los cambios de hora
/// (un día de 23 o 25 horas), por eso se cuenta sobre fechas en UTC.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// La fecha [n] días antes, sin pasar por horas.
DateTime daysBefore(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

/// Un punto de la gráfica: el peso de ese día y la media de los 7 días que acaban en él.
typedef WeightPoint = ({DateTime date, double weight, double avg7});

/// Igual que rolling_avg del backend: media de los pesos entre d − 6 y d, ambos incluidos.
List<WeightPoint> weightSeries(List<BodyEntry> entries) {
  final ws = [for (final e in entries) if (e.weightKg != null) (date: DateTime(e.date.year, e.date.month, e.date.day), w: e.weightKg!)]
    ..sort((a, b) => a.date.compareTo(b.date));
  return [
    for (final p in ws)
      (
        date: p.date,
        weight: p.w,
        avg7: () {
          final from = daysBefore(p.date, 6);
          final xs = [for (final q in ws) if (!q.date.isBefore(from) && !q.date.isAfter(p.date)) q.w];
          return xs.reduce((a, b) => a + b) / xs.length;
        }(),
      ),
  ];
}

/// Punto de partida y objetivos (GET/PATCH /me).
class Profile {
  final DateTime? startDate;
  final double? startWeightKg, startBodyFatPct;
  final int kcalTarget, proteinTargetG;
  const Profile({this.startDate, this.startWeightKg, this.startBodyFatPct, required this.kcalTarget, required this.proteinTargetG});

  bool get hasStart => startWeightKg != null && startBodyFatPct != null;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        startDate: _date(j['start_date']),
        startWeightKg: _n(j['start_weight_kg']),
        startBodyFatPct: _n(j['start_body_fat_pct']),
        kcalTarget: j['kcal_target'] as int,
        proteinTargetG: j['protein_target_g'] as int,
      );
}

double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Lo escrito en el formulario de punto de partida y objetivos → JSON para PATCH /me,
/// con los mismos límites que el backend (UserPatch). Devuelve el primer problema.
({Map<String, dynamic>? json, String? error}) profileInput({
  required DateTime? startDate,
  required String startWeight,
  required String startBodyFat,
  required String kcalTarget,
  required String proteinTarget,
}) {
  final w = startWeight.trim().isEmpty ? null : _parse(startWeight);
  final bf = startBodyFat.trim().isEmpty ? null : _parse(startBodyFat);
  final k = int.tryParse(kcalTarget.trim()), p = int.tryParse(proteinTarget.trim());
  if (startWeight.trim().isNotEmpty && (w == null || w < 30 || w > 300)) return (json: null, error: 'El peso inicial va de 30 a 300 kg.');
  if (startBodyFat.trim().isNotEmpty && (bf == null || bf < 3 || bf > 70)) return (json: null, error: 'La grasa inicial va de 3 a 70 %.');
  if (k == null || k < 800 || k > 6000) return (json: null, error: 'El objetivo de kcal va de 800 a 6000, sin decimales.');
  if (p == null || p < 20 || p > 400) return (json: null, error: 'El objetivo de proteína va de 20 a 400 g, sin decimales.');
  return (
    json: {
      'start_date': startDate == null ? null : _iso(startDate),
      'start_weight_kg': w,
      'start_body_fat_pct': bf,
      'kcal_target': k,
      'protein_target_g': p,
    },
    error: null,
  );
}

/// Peso, cintura y (si no hay diario) kcal y proteína de un día → JSON para PUT /body/{fecha}.
({Map<String, dynamic>? json, String? error}) entryInput({
  required String weight,
  required String waist,
  required String kcal,
  required String protein,
  required bool fromDiary,
}) {
  double? opt(String s) => s.trim().isEmpty ? null : _parse(s);
  final w = opt(weight), c = opt(waist), k = opt(kcal), p = opt(protein);
  if (weight.trim().isNotEmpty && (w == null || w < 30 || w > 300)) return (json: null, error: 'El peso va de 30 a 300 kg. Usa cifras, por ejemplo 97,4.');
  if (waist.trim().isNotEmpty && (c == null || c < 40 || c > 250)) return (json: null, error: 'La cintura va de 40 a 250 cm.');
  if (!fromDiary) {
    if (kcal.trim().isNotEmpty && (k == null || k < 0 || k > 10000 || k != k.roundToDouble())) {
      return (json: null, error: 'Las kcal son un número entero, de 0 a 10000.');
    }
    if (protein.trim().isNotEmpty && (p == null || p < 0 || p > 600 || p != p.roundToDouble())) {
      return (json: null, error: 'La proteína es un número entero de gramos, de 0 a 600.');
    }
  }
  if (w == null && c == null && (fromDiary || (k == null && p == null))) {
    return (json: null, error: 'Apunta al menos el peso o la cintura.');
  }
  return (
    json: {
      'weight_kg': w,
      'waist_cm': c,
      // Con diario, kcal y proteína las pone el diario: no se tocan las escritas a mano
      if (!fromDiary) 'kcal': k?.toInt(),
      if (!fromDiary) 'protein_g': p?.toInt(),
    },
    error: null,
  );
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
