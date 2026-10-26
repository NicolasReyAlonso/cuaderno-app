// Entreno sin servidor: los mismos casos que backend/tests (test_api.py y test_programs.py),
// con el catálogo real del backend (app/data/catalog.json).
import 'dart:convert';
import 'dart:io';

import 'package:cuaderno/features/workout/models.dart';
import 'package:cuaderno/features/workout/planner.dart';
import 'package:flutter_test/flutter_test.dart';

final _catalog = jsonDecode(File('../backend/app/data/catalog.json').readAsStringSync()) as Map<String, dynamic>;

/// Exercises y alternativas como los da GET /sync/reference.
Map<String, Exercise> _exercises() => {
      for (final e in _catalog['exercises'] as List)
        e['id'] as String: Exercise.fromSync(e['id'] as String, {
          ...e as Map<String, dynamic>,
          'default_rep_min': (e['default_reps'] as List?)?[0],
          'default_rep_max': (e['default_reps'] as List?)?[1],
        }, mine: false),
    };

Map<String, List<String>> _alternatives() {
  final out = <String, List<String>>{};
  final rows = [...(_catalog['alternatives'] as List)]..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
  for (final a in rows) {
    out.putIfAbsent(a['exercise_id'] as String, () => []).add(a['alternative_id'] as String);
  }
  return out;
}

LocalProgram _template() {
  final p = _catalog['program'] as Map<String, dynamic>;
  return LocalProgram.fromJson('definicion-5d', {
    'name': p['name'],
    'weeks': 1,
    'days': [for (final d in p['days'] as List) {...d as Map<String, dynamic>, 'key': d['id'], 'week': 1}],
  }, mine: false);
}

Planner _planner({List<LocalSession> sessions = const [], LocalProgram? program, DateTime? startedOn}) =>
    Planner(program: program ?? _template(), exercises: _exercises(), alternatives: _alternatives(), sessions: sessions, startedOn: startedOn);

List<SetEntry> _sets(double load, int reps, int n) => List.filled(n, SetEntry(load, reps));

DateTime _d(String s) => DateTime.parse(s);

void main() {
  test('reglas de progresión (test_progression_rules)', () {
    final full = _sets(80, 8, 4);
    Hint? s(int sets, int min, int max, List<SetEntry>? last, {String unit = 'reps', String load = 'kg', bool compound = true}) =>
        suggest(setsPlanned: sets, repMin: min, repMax: max, unit: unit, loadMode: load, isCompound: compound, last: last);
    expect(s(4, 6, 8, full)!.text, 'Sube 2,5 kg');
    expect(s(3, 10, 12, _sets(77, 12, 3), compound: false)!.text, 'Sube 1–2 kg');
    expect(s(4, 6, 10, _sets(0, 10, 4), load: 'extra')!.text, 'Añade 2,5 kg de lastre');
    expect(s(4, 6, 8, const [SetEntry(80, 8), SetEntry(80, 5)])!.kind, 'hold');
    expect(s(4, 6, 8, _sets(80, 7, 4))!.kind, 'rep');
    expect(s(3, 40, 60, const [SetEntry(null, 60), SetEntry(null, 60), SetEntry(null, 60)], unit: 'seconds', load: 'extra', compound: false)!.text,
        'Añade 10 s o lastre');
    expect(s(3, 8, 10, null, compound: false)!.kind, 'new');
  });

  test('semana que toca (test_current_week), también cruzando el cambio de hora', () {
    final monday = DateTime(2026, 10, 19);
    expect(currentWeek(null, 2, DateTime(2026, 11, 30)), 1);
    expect(currentWeek(monday, 1, DateTime(2026, 11, 30)), 1);
    expect([19, 25, 26].map((n) => currentWeek(monday, 2, DateTime(2026, 10, n))), [1, 1, 2]);
    expect(currentWeek(monday, 2, DateTime(2026, 11, 2)), 1);
    expect(currentWeek(monday, 3, DateTime(2026, 11, 9)), 1);
    expect(currentWeek(monday, 2, DateTime(2026, 10, 18)), 2); // antes del inicio sigue el bucle hacia atrás
    expect(currentWeek(monday, 2, DateTime(2026, 10, 12)), 2);
    expect(currentWeek(monday, 2, DateTime(2026, 10, 11)), 1);
  });

  test('sesión con cambio de alternativa y plan de la semana siguiente (test_session_with_swap_and_plan)', () {
    var p = _planner();
    final data = p.sessionData(_d('2026-10-20'), 'piernaA', 1, [
      (slot: 'sentadilla_smith', exercise: 'sentadilla_smith', sets: _sets(60, 10, 4)),
      (slot: 'crunch_polea', exercise: 'crunch', sets: [..._sets(0, 15, 3), const SetEntry(null, null)]),
    ]);
    final crunch = (data['slots'] as List)[1] as Map;
    expect((crunch['exercise_id'], (crunch['sets'] as List).length), ('crunch', 3));

    p = _planner(sessions: [LocalSession.fromJson(data)]);
    final plan = p.plan(_d('2026-10-27'), 'piernaA');
    expect(plan.saved, isFalse);
    final bySlot = {for (final s in plan.slots) s.slotExerciseId: s};
    expect(bySlot['crunch_polea']!.exerciseId, 'crunch'); // propone la misma alternativa
    expect(bySlot['crunch_polea']!.lastDate, _d('2026-10-20'));
    expect(bySlot['crunch_polea']!.hint!.kind, 'up');
    expect(bySlot['sentadilla_smith']!.hint!.text, 'Sube 2,5 kg');
    expect(bySlot['haka']!.hint!.kind, 'new');

    final sl = p.slot(_d('2026-10-27'), 'piernaA', 1, 'crunch_polea', 'elevacion_piernas');
    expect((sl.exerciseId, sl.hint!.kind, sl.lastDate), ('elevacion_piernas', 'new', null));
    final plancha = p.slot(_d('2026-10-31'), 'piernaB', 1, 'rueda', 'plancha');
    expect((plancha.repMin, plancha.repMax), (40, 60)); // rueda (reps) → plancha (segundos): rango propio
    expect(() => p.slot(_d('2026-10-27'), 'piernaA', 1, 'crunch_polea', 'press_banca'), throwsA(isA<PlanError>()));

    final same = p.plan(_d('2026-10-20'), 'piernaA');
    expect(same.saved, isTrue);
    expect({for (final s in same.slots) s.slotExerciseId: s}['sentadilla_smith']!.logged.length, 4);
  });

  test('validación al guardar con los mismos mensajes que el servidor (test_session_validation)', () {
    final p = _planner();
    String err(String day, List<({String slot, String exercise, List<SetEntry> sets})> slots) {
      try {
        p.sessionData(_d('2026-10-19'), day, 1, slots);
        return 'sin error';
      } on PlanError catch (e) {
        return e.message;
      }
    }

    expect(err('torsoA', [(slot: 'press_banca', exercise: 'crunch', sets: [const SetEntry(1, 1)])]), '«crunch» no es una alternativa de «press_banca».');
    expect(err('torsoA', [(slot: 'haka', exercise: 'haka', sets: [const SetEntry(1, 1)])]), '«haka» no es un ejercicio de este día.');
    expect(err('torsoA', [(slot: 'press_banca', exercise: 'press_banca', sets: [const SetEntry(null, null)])]),
        'Apunta al menos una serie antes de guardar.');
    expect(() => p.plan(_d('2026-10-19'), 'nada'), throwsA(isA<PlanError>()));
  });

  test('planes de varias semanas (test_weeks_in_workouts)', () {
    Map<String, dynamic> slot(String ex, int sets, int min, int max) => {'exercise_id': ex, 'sets': sets, 'rep_min': min, 'rep_max': max, 'rest': '2 min', 'is_core': false};
    Map<String, dynamic> day(int week, String key, int weekday, String name, int pos, List<Map<String, dynamic>> slots) =>
        {'week': week, 'key': key, 'weekday': weekday, 'name': name, 'short': '', 'focus': '', 'color': 'grey', 'position': pos, 'slots': slots};
    final prog = LocalProgram.fromJson('u:abc', {
      'name': 'Fuerza y volumen',
      'weeks': 2,
      'days': [
        day(1, 'torsoA', 1, 'Torso A', 0, [slot('press_banca', 4, 5, 6), slot('remo_barra', 3, 8, 12)]),
        day(2, 'torsoA', 1, 'Torso A', 0, [slot('press_banca', 3, 10, 12), slot('remo_barra', 3, 8, 12)]),
        day(2, 'pierna', 3, 'Pierna', 1, [slot('sentadilla_smith', 3, 8, 12)]),
      ],
    }, mine: true);
    var p = _planner(program: prog, startedOn: DateTime(2026, 10, 19));

    final t = p.today(_d('2026-10-26'));
    expect((t.weeks, t.week, t.dayKey), (2, 2, 'torsoA'));
    final sunday = p.today(_d('2026-10-25'));
    expect((sunday.week, sunday.dayKey), (1, null));
    expect(p.today(_d('2026-11-02')).week, 1);

    (int, int, int) press(DayPlan plan) {
      final s = plan.slots.firstWhere((x) => x.slotExerciseId == 'press_banca');
      return (s.sets, s.repMin, s.repMax);
    }

    expect(p.plan(_d('2026-10-26'), 'torsoA').week, 2);
    expect(press(p.plan(_d('2026-10-26'), 'torsoA')), (3, 10, 12));
    expect(press(p.plan(_d('2026-10-26'), 'torsoA', week: 1)), (4, 5, 6));
    expect(() => p.plan(_d('2026-10-26'), 'torsoA', week: 3), throwsA(predicate((e) => '$e'.startsWith('Tu plan tiene 2 semanas'))));
    expect(() => p.plan(_d('2026-10-19'), 'pierna'), throwsA(isA<PlanError>())); // pierna solo está en la semana 2

    // Semana 1 hecha en una fecha de la semana 2: el plan de ese día recuerda la semana guardada
    final s27 = p.sessionData(_d('2026-10-27'), 'torsoA', 1, [(slot: 'press_banca', exercise: 'press_banca', sets: _sets(70, 10, 3))]);
    expect((s27['week'], s27['program_id']), (1, 'u:abc'));
    p = _planner(program: prog, startedOn: DateTime(2026, 10, 19), sessions: [LocalSession.fromJson(s27)]);
    final again = p.plan(_d('2026-10-27'), 'torsoA');
    expect((again.saved, again.week, press(again)), (true, 1, (4, 5, 6)));
    final sl = p.slot(_d('2026-11-02'), 'torsoA', 1, 'press_banca', 'press_banca');
    expect((sl.repMin, sl.repMax, sl.lastDate), (5, 6, _d('2026-10-27')));
  });
}
