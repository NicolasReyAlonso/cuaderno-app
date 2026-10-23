import '../figures/figure.dart';

double? _d(dynamic v) => (v as num?)?.toDouble();

class Exercise {
  final String id, name, muscleGroup, cue, unit, loadMode;
  final bool isCompound;
  final FigureSpec figure;

  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.cue,
    required this.unit,
    required this.loadMode,
    required this.isCompound,
    required this.figure,
  });

  bool get isSeconds => unit == 'seconds';
  bool get isExtraLoad => loadMode == 'extra';

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        name: j['name'] as String,
        muscleGroup: j['muscle_group'] as String,
        cue: j['cue'] as String,
        unit: j['unit'] as String,
        loadMode: j['load_mode'] as String,
        isCompound: j['is_compound'] as bool,
        figure: FigureSpec.fromJson(j['figure'] as Map<String, dynamic>),
      );
}

class ProgramDay {
  final String key, name, short, focus, color;
  final int position;
  final int? weekday;
  const ProgramDay({required this.key, required this.name, required this.short, required this.focus, required this.color, required this.position, this.weekday});

  factory ProgramDay.fromJson(Map<String, dynamic> j) => ProgramDay(
        key: j['key'] as String,
        name: j['name'] as String,
        short: j['short'] as String,
        focus: j['focus'] as String,
        color: j['color'] as String,
        position: j['position'] as int,
        weekday: j['weekday'] as int?,
      );
}

class Catalog {
  final Map<String, Exercise> exercises;
  final List<ProgramDay> days;
  const Catalog(this.exercises, this.days);

  factory Catalog.fromJson(Map<String, dynamic> j) => Catalog(
        {for (final e in j['exercises'] as List) (e['id'] as String): Exercise.fromJson(e as Map<String, dynamic>)},
        [for (final d in (j['program'] as Map)['days'] as List) ProgramDay.fromJson(d as Map<String, dynamic>)],
      );

  /// Día que toca según el día de la semana (lunes → primer día).
  ProgramDay dayFor(DateTime date) => days.firstWhere((d) => d.weekday == date.weekday, orElse: () => days.first);
}

class SetEntry {
  final double? load;
  final int? reps;
  const SetEntry(this.load, this.reps);
  factory SetEntry.fromJson(Map<String, dynamic> j) => SetEntry(_d(j['load_kg']), j['reps'] as int?);
  Map<String, dynamic> toJson() => {'load_kg': load, 'reps': reps};
  bool get isEmpty => load == null && reps == null;
}

class Hint {
  final String kind, text; // kind: up | rep | hold | new
  const Hint(this.kind, this.text);
}

class PlannedSlot {
  final String slotExerciseId, exerciseId, rest;
  final int sets, repMin, repMax;
  final bool isCore;
  final List<String> alternatives;
  final DateTime? lastDate;
  final List<SetEntry> lastSets;
  final Hint? hint;
  final List<SetEntry> logged;

  const PlannedSlot({
    required this.slotExerciseId,
    required this.exerciseId,
    required this.rest,
    required this.sets,
    required this.repMin,
    required this.repMax,
    required this.isCore,
    required this.alternatives,
    required this.lastDate,
    required this.lastSets,
    required this.hint,
    required this.logged,
  });

  bool get swapped => exerciseId != slotExerciseId;

  factory PlannedSlot.fromJson(Map<String, dynamic> j) {
    final last = j['last'] as Map<String, dynamic>?;
    final hint = j['hint'] as Map<String, dynamic>?;
    return PlannedSlot(
      slotExerciseId: j['slot_exercise_id'] as String,
      exerciseId: j['exercise_id'] as String,
      rest: j['rest'] as String,
      sets: j['sets'] as int,
      repMin: j['rep_min'] as int,
      repMax: j['rep_max'] as int,
      isCore: j['is_core'] as bool,
      alternatives: (j['alternatives'] as List).cast<String>(),
      lastDate: last == null ? null : DateTime.parse(last['date'] as String),
      lastSets: last == null ? const [] : [for (final s in last['sets'] as List) SetEntry.fromJson(s as Map<String, dynamic>)],
      hint: hint == null ? null : Hint(hint['kind'] as String, hint['text'] as String),
      logged: [for (final s in j['logged'] as List) SetEntry.fromJson(s as Map<String, dynamic>)],
    );
  }
}

class DayPlan {
  final DateTime date;
  final String dayKey;
  final bool saved;
  final List<PlannedSlot> slots;
  const DayPlan(this.date, this.dayKey, this.saved, this.slots);

  factory DayPlan.fromJson(Map<String, dynamic> j) => DayPlan(
        DateTime.parse(j['date'] as String),
        j['day_key'] as String,
        j['saved'] as bool,
        [for (final s in j['slots'] as List) PlannedSlot.fromJson(s as Map<String, dynamic>)],
      );
}
