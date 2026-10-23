import 'package:cuaderno/features/programs/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('slug: sin tildes, en minúsculas y con guiones', () {
    expect(slug('Torso A'), 'torso-a');
    expect(slug('  Pierna · glúteo (día 2) '), 'pierna-gluteo-dia-2');
    expect(slug('Ñandú'), 'nandu');
    expect(slug('¿?'), '');
  });

  test('addDay no repite clave dentro de una semana, pero sí entre semanas', () {
    final p = PlanDraft(weeks: 2);
    expect(p.addDay(1, 'Torso').key, 'torso');
    expect(p.addDay(1, 'Torso').key, 'torso-2');
    expect(p.addDay(2, 'Torso').key, 'torso');
    expect(p.addDay(1, '!!').key, 'dia');
    expect(p.addDay(1, 'today').key, 'today-2');
  });

  test('copyWeek copia días y huecos con las mismas claves y sin compartir objetos', () {
    final p = PlanDraft(weeks: 2);
    p.addDay(1, 'Torso A').slots.add(SlotDraftData(exerciseId: 'press_banca', repMin: 5, repMax: 6));
    p.addDay(2, 'Viejo');
    p.copyWeek(1, 2);
    final w2 = p.daysOf(2);
    expect(w2.map((d) => d.key), ['torso-a']);
    w2.first.slots.first.repMax = 12;
    expect(p.daysOf(1).first.slots.first.repMax, 6);
  });

  test('setWeeks quita los días de las semanas que sobran', () {
    final p = PlanDraft(weeks: 3);
    p.addDay(1, 'A');
    p.addDay(3, 'B');
    expect(p.daysLostWith(2), 1);
    p.setWeeks(2);
    expect((p.weeks, p.days.length), (2, 1));
    p.setWeeks(9);
    expect(p.weeks, maxWeeks);
  });

  test('problem avisa en una frase de lo que impide guardar', () {
    final p = PlanDraft(name: 'Mi plan');
    final d = p.addDay(1, 'Torso')..weekday = 1;
    expect(p.problem(), isNull);
    d.slots.addAll([SlotDraftData(exerciseId: 'press_banca'), SlotDraftData(exerciseId: 'press_banca')]);
    expect(p.problem(), contains('dos veces'));
    d.slots.removeLast();
    d.slots.first.repMin = 12;
    d.slots.first.repMax = 8;
    expect(p.problem(), contains('mínimo mayor que el máximo'));
    d.slots.first.repMin = 0;
    expect(p.problem(), contains('falta el rango'));
    d.slots.first
      ..repMin = 8
      ..sets = 0;
    expect(p.problem(), contains('sin series'));
    d.slots.first.sets = 3;
    p.addDay(1, 'Pierna').weekday = 1;
    expect(p.problem(), contains('mismo día de la semana'));
    p.name = ' ';
    expect(p.problem(), 'Ponle un nombre al plan.');
  });

  test('toJson y fromJson con el formato de la API', () {
    final json = {
      'id': 'u:abc',
      'name': 'Fuerza',
      'weeks': 2,
      'mine': true,
      'days': [
        {
          'week': 2,
          'key': 'torsoA',
          'position': 0,
          'weekday': 1,
          'name': 'Torso A',
          'short': 'TA',
          'focus': 'Empuje',
          'color': 'blue',
          'slots': [
            {'exercise_id': 'press_banca', 'sets': 4, 'rep_min': 5, 'rep_max': 6, 'rest': '3 min', 'is_core': false, 'alternatives': []},
          ],
        },
      ],
    };
    final p = PlanDraft.fromJson(json);
    expect(p.daysOf(2).single.slots.single.repMin, 5);
    final out = p.toJson();
    expect(out['weeks'], 2);
    expect((out['days'] as List).single, {
      'week': 2,
      'key': 'torsoA',
      'name': 'Torso A',
      'short': 'TA',
      'focus': 'Empuje',
      'color': 'blue',
      'weekday': 1,
      'slots': [
        {'exercise_id': 'press_banca', 'sets': 4, 'rep_min': 5, 'rep_max': 6, 'rest': '3 min', 'is_core': false},
      ],
    });
  });
}
