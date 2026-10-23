import 'package:cuaderno/core/theme.dart';
import 'package:cuaderno/features/body/models.dart';
import 'package:cuaderno/features/body/weight_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BodyEntry _w(String date, double kg) => BodyEntry(date: DateTime.parse(date), weightKg: kg);

void main() {
  test('weightSeries hace la misma media de 7 días que el backend', () {
    // Mismos datos que test_body_summary: la media actual es 97,6 (98,2 · 97,4 · 97,2)
    final s = weightSeries([
      _w('2026-10-20', 98.1),
      _w('2026-10-21', 97.7),
      _w('2026-10-22', 98.2),
      BodyEntry(date: DateTime(2026, 10, 25), waistCm: 110), // sin peso: no cuenta
      _w('2026-10-27', 97.4),
      _w('2026-10-28', 97.2),
    ]);
    expect(s.length, 5);
    expect(s.first.avg7, 98.1);
    expect(s.last.avg7, closeTo(97.6, 0.001));
  });

  test('daysBetween y daysBefore cuentan días de calendario aunque cambie la hora', () {
    // 25 oct 2026 y 29 mar 2026: cambios de hora en España (días de 25 y 23 horas)
    expect(daysBetween(DateTime(2026, 10, 22), DateTime(2026, 10, 28)), 6);
    expect(daysBetween(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    expect(daysBefore(DateTime(2026, 10, 28), 6), DateTime(2026, 10, 22));
    expect(daysBefore(DateTime(2026, 10, 1), -15), DateTime(2026, 10, 16));
  });

  test('niceScale da marcas redondas que cubren los datos', () {
    final a = niceScale(96.8, 99.3);
    expect((a.min, a.max, a.step), (96.5, 99.5, 0.5));
    final b = niceScale(97.0, 97.1); // casi plano: se abre a 1 kg
    expect(b.min <= 96.55 && b.max >= 97.55, isTrue);
    final c = niceScale(80, 101);
    expect((c.min, c.max, c.step), (80.0, 105.0, 5.0));
  });

  test('entryInput: coma decimal, límites y diario', () {
    final ok = entryInput(weight: '97,4', waist: '', kcal: '2100', protein: '', fromDiary: false);
    expect(ok.json, {'weight_kg': 97.4, 'waist_cm': null, 'kcal': 2100, 'protein_g': null});
    // Con diario no se mandan kcal ni proteína: el backend conserva las escritas a mano
    expect(entryInput(weight: '97', waist: '', kcal: '', protein: '', fromDiary: true).json, {'weight_kg': 97.0, 'waist_cm': null});
    expect(entryInput(weight: '9', waist: '', kcal: '', protein: '', fromDiary: false).error, contains('30 a 300'));
    expect(entryInput(weight: '', waist: '', kcal: '', protein: '', fromDiary: true).error, 'Apunta al menos el peso o la cintura.');
    expect(entryInput(weight: '', waist: '', kcal: '2000,5', protein: '', fromDiary: false).error, contains('entero'));
  });

  test('profileInput: mismos límites que UserPatch', () {
    final ok = profileInput(startDate: DateTime(2026, 10, 19), startWeight: '99', startBodyFat: '30,7', kcalTarget: '2000', proteinTarget: '160');
    expect(ok.json, {'start_date': '2026-10-19', 'start_weight_kg': 99.0, 'start_body_fat_pct': 30.7, 'kcal_target': 2000, 'protein_target_g': 160});
    String? err({String w = '99', String bf = '30', String k = '2000', String p = '160'}) =>
        profileInput(startDate: null, startWeight: w, startBodyFat: bf, kcalTarget: k, proteinTarget: p).error;
    expect(err(w: ''), isNull);
    expect(err(bf: '80'), contains('grasa'));
    expect(err(k: '2000,5'), contains('kcal'));
    expect(err(p: '10'), contains('proteína'));
  });

  test('BodySummary con el formato de /body/summary', () {
    final s = BodySummary.fromJson({
      'current_weight': 97.6, 'current_weight_date': '2026-10-28', 'body_fat_est': 29.7, 'lean_mass': 68.6,
      'goal_25_weight': 91.5, 'goal_20_weight': 85.8,
      'weeks': [
        {'monday': '2026-10-26', 'avg_weight': 97.3, 'n_weights': 2, 'avg_kcal': null, 'avg_protein': null, 'waist_cm': null,
         'delta_kg': -0.7, 'delta_pct': -0.71, 'pace': 'on_track'},
      ],
      'entries': [
        {'date': '2026-10-28', 'weight_kg': 97.2, 'waist_cm': null, 'kcal': 1950, 'protein_g': 170, 'from_diary': true},
      ],
    });
    expect(s.weeks.single.pace, 'on_track');
    expect(s.entryOn(DateTime(2026, 10, 28))!.fromDiary, isTrue);
    expect(s.entryOn(DateTime(2026, 10, 27)), isNull);
  });

  testWidgets('la gráfica se dibuja y al tocar muestra el día más cercano', (tester) async {
    final pts = weightSeries([
      for (var i = 0; i < 30; i++) _w('2026-10-${(i + 1).toString().padLeft(2, '0')}', 99 - i * 0.06 + (i % 3 == 0 ? 0.4 : -0.2)),
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: Center(child: SizedBox(width: 380, child: RepaintBoundary(child: WeightChart(points: pts))))),
    ));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(WeightChart), matchesGoldenFile('goldens/weight_chart.png'));

    await tester.tapAt(tester.getTopLeft(find.byType(WeightChart)) + const Offset(40 + 1, 100)); // primer día
    await tester.pump();
    expect(find.text('1 oct'), findsWidgets);
    expect(find.text('ese día'), findsOneWidget);
    await expectLater(find.byType(WeightChart), matchesGoldenFile('goldens/weight_chart_tooltip.png'));
  });
}
