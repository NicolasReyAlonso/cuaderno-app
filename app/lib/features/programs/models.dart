/// Planes de entreno: resumen para la lista y borrador editable para el editor.
library;

const maxWeeks = 4;

class ProgramSummary {
  final String id, name;
  final int weeks, daysPerWeek;
  final bool mine, active;
  const ProgramSummary({required this.id, required this.name, required this.weeks, required this.daysPerWeek, required this.mine, required this.active});

  factory ProgramSummary.fromJson(Map<String, dynamic> j) => ProgramSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        weeks: j['weeks'] as int,
        daysPerWeek: j['days_per_week'] as int,
        mine: j['mine'] as bool,
        active: j['active'] as bool,
      );
}

class SlotDraftData {
  String exerciseId;
  int sets, repMin, repMax;
  String rest;
  bool isCore;
  SlotDraftData({required this.exerciseId, this.sets = 3, this.repMin = 8, this.repMax = 12, this.rest = '', this.isCore = false});

  factory SlotDraftData.fromJson(Map<String, dynamic> j) => SlotDraftData(
        exerciseId: j['exercise_id'] as String,
        sets: j['sets'] as int,
        repMin: j['rep_min'] as int,
        repMax: j['rep_max'] as int,
        rest: j['rest'] as String,
        isCore: j['is_core'] as bool,
      );

  SlotDraftData copy() => SlotDraftData(exerciseId: exerciseId, sets: sets, repMin: repMin, repMax: repMax, rest: rest, isCore: isCore);

  Map<String, dynamic> toJson() =>
      {'exercise_id': exerciseId, 'sets': sets, 'rep_min': repMin, 'rep_max': repMax, 'rest': rest, 'is_core': isCore};
}

class DayDraft {
  int week;
  String key, name, short, focus, color;
  int? weekday; // 1 = lunes … 7 = domingo
  final List<SlotDraftData> slots;
  DayDraft({required this.week, required this.key, required this.name, this.short = '', this.focus = '', this.color = 'grey', this.weekday, List<SlotDraftData>? slots})
      : slots = slots ?? [];

  factory DayDraft.fromJson(Map<String, dynamic> j) => DayDraft(
        week: j['week'] as int,
        key: j['key'] as String,
        name: j['name'] as String,
        short: j['short'] as String,
        focus: j['focus'] as String,
        color: j['color'] as String,
        weekday: j['weekday'] as int?,
        slots: [for (final s in j['slots'] as List) SlotDraftData.fromJson(s as Map<String, dynamic>)],
      );

  DayDraft copyTo(int week) =>
      DayDraft(week: week, key: key, name: name, short: short, focus: focus, color: color, weekday: weekday, slots: [for (final s in slots) s.copy()]);

  Map<String, dynamic> toJson() => {
        'week': week,
        'key': key,
        'name': name,
        'short': short,
        'focus': focus,
        'color': color,
        'weekday': weekday,
        'slots': [for (final s in slots) s.toJson()],
      };
}

/// Plan en edición. id == null → plan nuevo. mine == false → plantilla (solo lectura).
class PlanDraft {
  final String? id;
  final bool mine;
  String name;
  int weeks;
  final List<DayDraft> days;
  PlanDraft({this.id, this.mine = true, this.name = '', this.weeks = 1, List<DayDraft>? days}) : days = days ?? [];

  factory PlanDraft.fromJson(Map<String, dynamic> j) => PlanDraft(
        id: j['id'] as String,
        mine: j['mine'] as bool,
        name: j['name'] as String,
        weeks: j['weeks'] as int,
        days: [for (final d in j['days'] as List) DayDraft.fromJson(d as Map<String, dynamic>)],
      );

  List<DayDraft> daysOf(int week) => [for (final d in days) if (d.week == week) d];

  /// Días que se perderían al bajar a [n] semanas.
  int daysLostWith(int n) => days.where((d) => d.week > n).length;

  void setWeeks(int n) {
    weeks = n.clamp(1, maxWeeks);
    days.removeWhere((d) => d.week > weeks);
  }

  /// Añade un día al final de la semana. La clave sale del nombre y no se repite en la semana.
  DayDraft addDay(int week, String name) {
    final day = DayDraft(week: week, key: uniqueKey(week, name), name: name);
    days.add(day);
    return day;
  }

  /// Sustituye los días de [to] por una copia de los de [from]. Mismas claves: el historial
  /// y las alternativas elegidas se comparten entre semanas.
  void copyWeek(int from, int to) {
    days.removeWhere((d) => d.week == to);
    days.addAll([for (final d in daysOf(from)) d.copyTo(to)]);
  }

  String uniqueKey(int week, String name) {
    final taken = {for (final d in daysOf(week)) d.key};
    final base = slug(name).isEmpty ? 'dia' : slug(name);
    var key = base;
    for (var i = 2; taken.contains(key) || key == 'today'; i++) {
      key = '$base-$i';
    }
    return key;
  }

  /// Primer problema que impide guardar, en una frase; null si todo está bien.
  String? problem() {
    if (name.trim().isEmpty) return 'Ponle un nombre al plan.';
    for (final d in days) {
      if (d.name.trim().isEmpty) return 'Hay un día sin nombre en la semana ${d.week}.';
      final seen = <String>{};
      for (final s in d.slots) {
        if (!seen.add(s.exerciseId)) return 'Un ejercicio está dos veces en «${d.name}». Cada ejercicio, una vez por día.';
        if (s.sets < 1 || s.sets > 12) return 'En «${d.name}» hay un ejercicio sin series. Pon entre 1 y 12.';
        if (s.repMin < 1 || s.repMax < 1) return 'En «${d.name}» falta el rango de repeticiones de un ejercicio.';
        if (s.repMin > s.repMax) return 'En «${d.name}» hay un rango con el mínimo mayor que el máximo.';
      }
      if (d.weekday != null && daysOf(d.week).where((o) => o.weekday == d.weekday).length > 1) {
        return 'En la semana ${d.week} hay dos días el mismo día de la semana.';
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'weeks': weeks,
        'days': [for (final d in days) d.toJson()],
      };
}

/// «Torso A» → «torso-a». Solo letras sin tilde, cifras y guiones (lo que acepta el backend).
String slug(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñç';
  const to = 'aaaaeeeeiiiioooouuuunc';
  final b = StringBuffer();
  for (final ch in s.trim().toLowerCase().split('')) {
    final i = from.indexOf(ch);
    final c = i >= 0 ? to[i] : ch;
    b.write(RegExp(r'[a-z0-9]').hasMatch(c) ? c : '-');
  }
  final out = b.toString().replaceAll(RegExp(r'-+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return out.length > 40 ? out.substring(0, 40) : out;
}
