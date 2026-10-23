import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:cuaderno/features/figures/figure.dart';
import 'package:flutter_test/flutter_test.dart';

/// Comprueba que la cinemática da las mismas posiciones que el cuaderno web.
/// Valores de referencia calculados con la versión JavaScript.
void main() {
  final catalog = jsonDecode(File('../backend/app/data/catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final specs = {
    for (final e in catalog['exercises'] as List) e['id'] as String: FigureSpec.fromJson(e['figure'] as Map<String, dynamic>),
  };

  void near(Offset? got, List<double> want) {
    expect(got, isNotNull);
    expect(got!.dx, closeTo(want[0], 0.01));
    expect(got.dy, closeTo(want[1], 0.01));
  }

  test('todas las figuras del catálogo se resuelven', () {
    for (final s in specs.values) {
      for (final u in [0.0, 0.5, 1.0]) {
        final j = s.solve(u);
        expect(j.head.dx.isFinite && j.w1.dy.isFinite && j.a1.dx.isFinite, isTrue);
      }
    }
  });

  test('press banca, pose a', () {
    final j = specs['press_banca']!.solve(0);
    near(j.w1, [74, 55.3]);
    near(j.k1, [154.532, 120.286]);
    near(j.head, [61, 107]);
  });

  test('sentadilla multipower, pose b (mano relativa al hombro)', () {
    final j = specs['sentadilla_smith']!.solve(1);
    near(j.w1, [97.376, 82.99]);
    near(j.k1, [116.932, 123.243]);
    near(j.head, [111.265, 70.965]);
  });

  test('elevaciones laterales de frente, mitad del recorrido', () {
    final j = specs['laterales']!.solve(0.5);
    near(j.w1, [65, 66]);
    near(j.w2, [135, 66]);
    near(j.k1, [86.98, 120.507]);
  });

  test('crunch, pose b (mano relativa a la cabeza)', () {
    final j = specs['crunch']!.solve(1);
    near(j.w1, [55.965, 114.735]);
    near(j.head, [49.965, 120.735]);
  });
}
