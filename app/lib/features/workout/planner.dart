/// Entreno sin servidor: la misma lógica que backend/app/routers/workouts.py,
/// services/progression.py y services/schedule.py, sobre los datos locales.
///
/// Sin Flutter ni red: se prueba con los mismos casos que los tests del backend.
library;

import 'models.dart';

// ---------------------------------------------------------------- progresión (services/progression.py)

/// Doble progresión. [last]: series de la última vez con ese ejercicio (null = primera vez).
Hint? suggest({
  required int setsPlanned,
  required int repMin,
  required int repMax,
  required String unit,
  required String loadMode,
  required bool isCompound,
  required List<SetEntry>? last,
}) {
  final target = '$repMax ${unit == 'seconds' ? 's' : 'reps'}';
  if (last == null || last.isEmpty) {
    if (loadMode == 'extra') return Hint('new', 'Primera vez: sin peso extra, busca llegar a $target');
    return Hint('new', 'Primera vez: elige un peso con el que llegues a $target dejando 1–2 en reserva');
  }
  final done = [for (final s in last) if (s.reps != null) s];
  if (done.isEmpty) return null;
  final loads = [for (final s in done) s.load ?? 0];
  final sameLoad = loads.every((x) => x == loads.first);
  if (done.length >= setsPlanned && done.every((s) => s.reps! >= repMax) && sameLoad) {
    if (unit == 'seconds') return const Hint('up', 'Añade 10 s o lastre');
    if (loadMode == 'extra') return const Hint('up', 'Añade 2,5 kg de lastre');
    return Hint('up', isCompound ? 'Sube 2,5 kg' : 'Sube 1–2 kg');
  }
  if (done.any((s) => s.reps! < repMin)) return const Hint('hold', 'Repite el mismo peso');
  return const Hint('rep', 'Mismo peso, busca +1 rep');
}

/// Rango del ejercicio hecho: una alternativa hereda el del hueco salvo que cambie de unidad
/// (rueda en repeticiones → plancha en segundos) y tenga rango propio.
(int, int) effectiveRange(String slotUnit, int slotMin, int slotMax, String exUnit, int? exMin, int? exMax, bool isSlotExercise) {
  if (isSlotExercise || slotUnit == exUnit || exMin == null || exMax == null) return (slotMin, slotMax);
  return (exMin, exMax);
}

// ---------------------------------------------------------------- semanas (services/schedule.py)

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Semana del plan en [d]: (días desde el inicio ÷ 7) mód semanas + 1. Por fechas, no por horas
/// (los cambios de hora no la desplazan); hacia atrás también sigue el bucle.
int currentWeek(DateTime? startedOn, int weeks, DateTime d) {
  if (startedOn == null || weeks <= 1) return 1;
  final days = _daysBetween(startedOn, d);
  final weeksSince = days >= 0 ? days ~/ 7 : -((-days + 6) ~/ 7); // división entera hacia abajo, como // de Python
  return weeksSince % weeks + 1; // % de Dart con divisor positivo nunca es negativo
}

// ---------------------------------------------------------------- datos locales

class LocalSlot {
  final String exerciseId, rest;
  final int sets, repMin, repMax;
  final bool isCore;
  const LocalSlot({required this.exerciseId, required this.sets, required this.repMin, required this.repMax, this.rest = '', this.isCore = false});
  factory LocalSlot.fromJson(Map<String, dynamic> j) => LocalSlot(
        exerciseId: j['exercise_id'] as String,
        sets: j['sets'] as int,
        repMin: j['rep_min'] as int,
        repMax: j['rep_max'] as int,
        rest: j['rest'] as String? ?? '',
        isCore: j['is_core'] as bool? ?? false,
      );
}

class LocalDay {
  final ProgramDay info;
  final List<LocalSlot> slots;
  const LocalDay(this.info, this.slots);
  factory LocalDay.fromJson(Map<String, dynamic> j) => LocalDay(
        ProgramDay.fromJson(j),
        [for (final s in j['slots'] as List) LocalSlot.fromJson(s as Map<String, dynamic>)],
      );
}

/// Un plan (propio o plantilla) con el formato de la sincronización: {name, weeks, days}.
class LocalProgram {
  final String id, name;
  final int weeks;
  final bool mine;
  final List<LocalDay> days; // por semana y posición
  const LocalProgram({required this.id, required this.name, required this.weeks, required this.days, this.mine = false});
  factory LocalProgram.fromJson(String id, Map<String, dynamic> j, {required bool mine}) {
    final days = [for (final d in j['days'] as List) LocalDay.fromJson(d as Map<String, dynamic>)]
      ..sort((a, b) => a.info.week != b.info.week ? a.info.week.compareTo(b.info.week) : a.info.position.compareTo(b.info.position));
    return LocalProgram(id: id, name: j['name'] as String, weeks: j['weeks'] as int, days: days, mine: mine);
  }

  LocalDay? day(int week, String key) {
    for (final d in days) {
      if (d.info.week == week && d.info.key == key) return d;
    }
    return null;
  }
}

class LoggedSlot {
  final String slotExerciseId, exerciseId;
  final List<SetEntry> sets;
  const LoggedSlot(this.slotExerciseId, this.exerciseId, this.sets);
}

/// Una sesión guardada (registro «workout_session», id «AAAA-MM-DD/día»).
class LocalSession {
  final DateTime date;
  final String dayKey;
  final String? programId;
  final int week;
  final List<LoggedSlot> slots;
  const LocalSession({required this.date, required this.dayKey, required this.week, required this.slots, this.programId});

  factory LocalSession.fromJson(Map<String, dynamic> j) => LocalSession(
        date: DateTime.parse(j['date'] as String),
        dayKey: j['day_key'] as String,
        programId: j['program_id'] as String?,
        week: j['week'] as int? ?? 1,
        slots: [
          for (final s in j['slots'] as List)
            LoggedSlot(s['slot_exercise_id'] as String, s['exercise_id'] as String,
                [for (final x in s['sets'] as List) SetEntry.fromJson(x as Map<String, dynamic>)]),
        ],
      );
}

/// Un error que el usuario puede corregir, con el mismo texto que daría el servidor.
class PlanError implements Exception {
  const PlanError(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class Planner {
  Planner({required this.program, required this.exercises, required this.alternatives, required List<LocalSession> sessions, this.startedOn})
      : sessions = [...sessions]..sort((a, b) => b.date.compareTo(a.date)); // la más reciente primero

  final LocalProgram program;
  final Map<String, Exercise> exercises;
  final Map<String, List<String>> alternatives;
  final List<LocalSession> sessions;
  final DateTime? startedOn;

  LocalSession? session(DateTime d, String dayKey) {
    for (final s in sessions) {
      if (_sameDay(s.date, d) && s.dayKey == dayKey) return s;
    }
    return null;
  }

  /// Semana que toca y el día con ese día de la semana (null = descanso).
  Today today(DateTime d) {
    final week = currentWeek(startedOn, program.weeks, d);
    final day = program.days.where((x) => x.info.week == week && x.info.weekday == d.weekday);
    return Today(week, program.weeks, day.isEmpty ? null : day.first.info.key);
  }

  /// Semana explícita, la de la sesión guardada ese día (si es de este plan) o la que toca por fecha.
  int resolveWeek(DateTime d, String dayKey, int? week) {
    if (week != null) {
      if (week > program.weeks) {
        throw PlanError('Tu plan tiene ${program.weeks} semana${program.weeks > 1 ? 's' : ''}. Elige una entre 1 y ${program.weeks}.');
      }
      return week;
    }
    final saved = session(d, dayKey);
    if (saved != null && saved.programId == program.id && saved.week <= program.weeks) return saved.week;
    return currentWeek(startedOn, program.weeks, d);
  }

  LocalDay dayOf(int week, String dayKey) {
    final day = program.day(week, dayKey);
    if (day == null) {
      throw PlanError('El día «$dayKey» no está en ${program.weeks > 1 ? 'la semana $week de tu plan' : 'tu plan'}.');
    }
    return day;
  }

  /// Última vez con ese ejercicio antes de [before]: fecha y series.
  (DateTime, List<SetEntry>)? lastPerformance(String exerciseId, DateTime before) {
    for (final s in sessions) {
      if (!s.date.isBefore(DateTime(before.year, before.month, before.day))) continue;
      final sets = [for (final sl in s.slots) if (sl.exerciseId == exerciseId) ...sl.sets];
      if (sets.isNotEmpty) return (s.date, sets);
    }
    return null;
  }

  PlannedSlot? _planned(DateTime d, LocalSlot slot, String exId, List<SetEntry> logged) {
    final options = alternatives[slot.exerciseId] ?? const <String>[];
    if (exId != slot.exerciseId && !options.contains(exId)) exId = slot.exerciseId;
    final slotEx = exercises[slot.exerciseId];
    final ex = exercises[exId] ?? slotEx;
    if (slotEx == null || ex == null) return null; // ejercicio que ya no existe (borrado en otro dispositivo)
    final (rmin, rmax) = effectiveRange(slotEx.unit, slot.repMin, slot.repMax, ex.unit, ex.defaultRepMin, ex.defaultRepMax, ex.id == slot.exerciseId);
    final last = lastPerformance(ex.id, d);
    final hint = suggest(
        setsPlanned: slot.sets, repMin: rmin, repMax: rmax, unit: ex.unit, loadMode: ex.loadMode, isCompound: ex.isCompound, last: last?.$2);
    return PlannedSlot(
      slotExerciseId: slot.exerciseId,
      exerciseId: ex.id,
      rest: slot.rest,
      sets: slot.sets,
      repMin: rmin,
      repMax: rmax,
      isCore: slot.isCore,
      alternatives: options,
      lastDate: last?.$1,
      lastSets: last?.$2 ?? const [],
      hint: hint,
      logged: logged,
    );
  }

  /// Lo que toca: ejercicio de cada hueco (lo guardado ese día o la alternativa que usaste la
  /// última vez en ese día), lo que hiciste la última vez y la sugerencia.
  DayPlan plan(DateTime d, String dayKey, {int? week}) {
    final w = resolveWeek(d, dayKey, week);
    final day = dayOf(w, dayKey);
    final saved = session(d, dayKey);
    final choice = <String, String>{};
    final logged = <String, List<SetEntry>>{};
    if (saved != null) {
      for (final sl in saved.slots) {
        choice[sl.slotExerciseId] = sl.exerciseId;
        logged[sl.slotExerciseId] = sl.sets;
      }
    } else {
      final prev = sessions.where((s) => s.dayKey == dayKey && s.date.isBefore(DateTime(d.year, d.month, d.day)));
      if (prev.isNotEmpty) {
        for (final sl in prev.first.slots) {
          if (sl.exerciseId != sl.slotExerciseId) choice[sl.slotExerciseId] = sl.exerciseId;
        }
      }
    }
    final slots = [
      for (final slot in day.slots) _planned(d, slot, choice[slot.exerciseId] ?? slot.exerciseId, logged[slot.exerciseId] ?? const []),
    ].whereType<PlannedSlot>().toList();
    return DayPlan(DateTime(d.year, d.month, d.day), dayKey, w, saved != null, slots);
  }

  /// Un hueco con el ejercicio indicado (al pulsar Cambiar).
  PlannedSlot slot(DateTime d, String dayKey, int week, String slotExerciseId, String exerciseId) {
    final day = dayOf(week, dayKey);
    final slot = day.slots.where((s) => s.exerciseId == slotExerciseId);
    if (slot.isEmpty) throw PlanError('«$slotExerciseId» no es un ejercicio de este día.');
    if (exerciseId != slotExerciseId && !(alternatives[slotExerciseId] ?? const []).contains(exerciseId)) {
      throw PlanError('«$exerciseId» no es una alternativa de «$slotExerciseId».');
    }
    return _planned(d, slot.first, exerciseId, const []) ?? (throw PlanError('«$exerciseId» ya no existe.'));
  }

  /// La sesión lista para guardar (JSON del registro «workout_session»), con las mismas
  /// comprobaciones que el servidor. Las series vacías no se guardan.
  Map<String, dynamic> sessionData(DateTime d, String dayKey, int week, List<({String slot, String exercise, List<SetEntry> sets})> slots) {
    final day = dayOf(week, dayKey);
    final slotIds = {for (final s in day.slots) s.exerciseId};
    final performed = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final sl in slots) {
      if (!slotIds.contains(sl.slot)) throw PlanError('«${sl.slot}» no es un ejercicio de este día.');
      if (sl.exercise != sl.slot && !(alternatives[sl.slot] ?? const []).contains(sl.exercise)) {
        throw PlanError('«${sl.exercise}» no es una alternativa de «${sl.slot}».');
      }
      if (!performed.add(sl.exercise)) throw PlanError('«${sl.exercise}» aparece dos veces en la sesión.');
      final sets = [for (final s in sl.sets) if (!s.isEmpty) s.toJson()];
      if (sets.isNotEmpty) out.add({'slot_exercise_id': sl.slot, 'exercise_id': sl.exercise, 'sets': sets});
    }
    if (out.isEmpty) throw const PlanError('Apunta al menos una serie antes de guardar.');
    final iso = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {'date': iso, 'day_key': dayKey, 'program_id': program.id, 'week': week, 'slots': out};
  }
}
