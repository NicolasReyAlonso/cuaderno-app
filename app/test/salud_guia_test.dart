import 'package:cuaderno/core/theme.dart';
import 'package:cuaderno/features/body/models.dart';
import 'package:cuaderno/features/guide/guide_page.dart';
import 'package:cuaderno/features/health/health_page.dart';
import 'package:cuaderno/features/health/health_repository.dart';
import 'package:cuaderno/features/health/metric_chart.dart';
import 'package:cuaderno/features/health/metrics.dart';
import 'package:cuaderno/features/workout/exercise_card.dart' show shortDate;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Metric _m(String key) => metrics.firstWhere((m) => m.key == key);

class _NoHealth extends HealthController {
  @override
  Future<HealthState> build() async => const HealthState(); // como en Mac o web: sin almacén de salud
}

void main() {
  group('valores de Salud', () {
    final health = {
      '2026-10-20': {'steps': 9500, 'sleep_minutes': 412, 'resting_hr': 58, 'hrv_ms': 41.5},
      '2026-10-21': {'steps': 7200, 'sleep_minutes': null, 'resting_hr': 61},
      '2026-10-26': {'steps': 12000},
    };
    final body = {
      '2026-10-20': {'weight_kg': 98.1, 'waist_cm': null},
      '2026-10-22': {'weight_kg': null, 'waist_cm': 104},
    };

    test('series por día: solo los días con dato, en orden', () {
      expect(seriesOf(_m('steps'), health, body).map((p) => p.value), [9500, 7200, 12000]);
      expect(seriesOf(_m('sleep_minutes'), health, body).length, 1);
      expect(seriesOf(_m('weight_kg'), health, body).single, (date: DateTime(2026, 10, 20), value: 98.1));
    });

    test('rango de días hasta hoy, también cruzando el cambio de hora', () {
      final r = rangeEnding(DateTime(2026, 10, 27, 15), 7);
      expect((r.from, r.to), (DateTime(2026, 10, 21), DateTime(2026, 10, 27)));
      expect(inRange(seriesOf(_m('steps'), health, body), r).map((p) => p.date.day), [21, 26]);
    });

    test('media, mínimo, máximo y formatos', () {
      final st = MetricStats.of(seriesOf(_m('steps'), health, body));
      expect((st.avg, st.min, st.max, st.days), ((9500 + 7200 + 12000) / 3, 7200.0, 12000.0, 3));
      expect(MetricStats.of(const []).last, isNull);
      expect(_m('steps').withUnit(9566.6), '9.567 pasos');
      expect(_m('sleep_minutes').withUnit(425), '7 h 05');
      expect(_m('hrv_ms').withUnit(41.26), '41,3 ms');
      expect(_m('sleep_minutes').axisText(480), '8 h');
      final today = DateTime(2026, 10, 27);
      expect([27, 26, 20].map((d) => whenText(DateTime(2026, 10, d), today, shortDate)), ['hoy', 'ayer', '20 oct']);
    });
  });

  test('la guía pone tus números: con tus datos, los mismos que escribiste', () {
    final p = Profile.fromJson({'start_date': '2026-10-19', 'start_weight_kg': 99, 'start_body_fat_pct': 30.7, 'kcal_target': 2000, 'protein_target_g': 160});
    final n = GuideNumbers.from(p, const BodySummary(currentWeight: 92.0, goal25Weight: 91.5));
    expect(n.start, '19 oct 2026: 99 kg y 30,7 % de grasa. Unos 30,4 kg de grasa y 68,6 kg de masa magra.');
    expect(n.pace, 'unos 0,5–0,9 kg ahora mismo'); // 92 kg: 0,46–0,92
    expect(n.goal25, 'unos 91,5 kg');
    final empty = GuideNumbers.from(null, null);
    expect((empty.start, empty.pace, empty.goal25), (null, null, null));
  });

  testWidgets('la pestaña Guía y la de Salud se dibujan sin servidor', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final today = DateTime.now();
    final steps = [for (var i = 0; i < 20; i++) (date: DateTime(today.year, today.month, today.day - i * 1), value: 6000.0 + i * 150)];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        metricSeriesProvider.overrideWithValue(AsyncData({for (final m in metrics) m.key: m.key == 'steps' ? steps.reversed.toList() : const <DayValue>[]})),
        healthProvider.overrideWith(_NoHealth.new),
        healthActivitiesProvider.overrideWithValue(const AsyncData([])),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: HealthPage())),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Pasos'), findsOneWidget);
    expect(find.text('Sin datos'), findsNWidgets(metrics.length - 1));
    await tester.tap(find.text('Pasos'));
    await tester.pumpAndSettle();
    expect(find.text('Día a día'), findsOneWidget);
    expect(find.textContaining('objetivo de la guía'), findsOneWidget);
  });

  testWidgets('gráficas de barras y de línea', (tester) async {
    final from = DateTime(2026, 10, 1), to = DateTime(2026, 10, 30);
    final steps = [
      for (var d = 1; d <= 30; d++)
        if (d % 6 != 0) (date: DateTime(2026, 10, d), value: 5000.0 + (d * 731) % 6000),
    ];
    final hr = [for (var d = 1; d <= 30; d++) (date: DateTime(2026, 10, d), value: 62.0 - d * 0.12 + (d % 4))];
    Future<void> shot(Metric m, List<DayValue> pts, String name) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: Center(child: SizedBox(width: 380, child: RepaintBoundary(child: MetricChart(metric: m, points: pts, from: from, to: to))))),
      ));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MetricChart), matchesGoldenFile('goldens/$name.png'));
    }

    await shot(_m('steps'), steps, 'salud_pasos');
    await shot(_m('resting_hr'), hr, 'salud_pulso');
    await tester.tapAt(tester.getCenter(find.byType(MetricChart)));
    await tester.pump();
    expect(find.textContaining('ppm'), findsOneWidget); // recuadro con el valor del día señalado
  });
}
