import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../workout/exercise_card.dart' show fmtNum, shortDate;
import 'models.dart';

/// Escala del eje Y en números redondos: de 3 a 6 marcas que cubren [lo, hi].
({double min, double max, double step}) niceScale(double lo, double hi) {
  if (hi - lo < 0.5) {
    final mid = (hi + lo) / 2;
    lo = mid - 0.5;
    hi = mid + 0.5;
  }
  const steps = [0.2, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];
  final step = steps.firstWhere((s) => (hi - lo) / s <= 5, orElse: () => 50);
  return (min: (lo / step).floor() * step, max: (hi / step).ceil() * step, step: step);
}

/// Peso del día (puntos grises, en segundo plano) y media de 7 días (línea de acento).
/// Al pasar el ratón, tocar o arrastrar, una línea vertical marca el día más cercano y muestra sus valores.
class WeightChart extends StatefulWidget {
  const WeightChart({super.key, required this.points});
  final List<WeightPoint> points; // por fecha ascendente, ya filtrados por el rango

  @override
  State<WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<WeightChart> {
  int? _hover;

  static const _left = 40.0, _right = 64.0, _top = 12.0, _bottom = 24.0, _height = 220.0;

  int _nearest(double dx, double width) {
    final g = _Geom(widget.points, Size(width, _height));
    var best = 0;
    for (var i = 1; i < widget.points.length; i++) {
      if ((g.x(widget.points[i].date) - dx).abs() < (g.x(widget.points[best].date) - dx).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final pts = widget.points;
    final last = pts.last;
    return Semantics(
      label: 'Gráfica de peso: media de 7 días de ${fmtNum(_r(pts.first.avg7))} kg el ${shortDate(pts.first.date)} '
          'a ${fmtNum(_r(last.avg7))} kg el ${shortDate(last.date)}. Los valores de cada día están en Registros.',
      child: LayoutBuilder(builder: (context, c) {
        final size = Size(c.maxWidth, _height);
        final g = _Geom(pts, size);
        final i = _hover;
        return MouseRegion(
          onHover: (e) => setState(() => _hover = _nearest(e.localPosition.dx, c.maxWidth)),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (e) => setState(() => _hover = _nearest(e.localPosition.dx, c.maxWidth)),
            onHorizontalDragUpdate: (e) => setState(() => _hover = _nearest(e.localPosition.dx, c.maxWidth)),
            child: SizedBox(
              height: _height,
              child: Stack(clipBehavior: Clip.none, children: [
                CustomPaint(
                  size: size,
                  painter: _ChartPainter(
                    pts,
                    g,
                    hover: i,
                    grid: cs.outlineVariant,
                    dots: cs.onSurfaceVariant.withValues(alpha: 0.45),
                    line: cs.primary,
                    surface: cs.surface,
                    crosshair: cs.outline,
                    axisText: t.textTheme.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                    endLabel: t.textTheme.labelMedium!.copyWith(color: cs.onSurface, fontWeight: FontWeight.w600),
                  ),
                ),
                // El cuadro va en la mitad contraria a la del punto, para no taparlo
                if (i != null)
                  Positioned(
                    left: (g.x(pts[i].date) + 10).clamp(0, math.max(0, c.maxWidth - 170)),
                    top: g.y(pts[i].avg7) < _height / 2 ? null : 0,
                    bottom: g.y(pts[i].avg7) < _height / 2 ? _bottom + 4 : null,
                    child: IgnorePointer(child: _Tooltip(p: pts[i])),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

double _r(double v) => (v * 10).round() / 10;

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.p});
  final WeightPoint p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    Widget row(Widget key, String value, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 14, child: Center(child: key)),
          const SizedBox(width: 6),
          Text(value, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 4),
          Text(label, style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ]);
    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(shortDate(p.date), style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          row(Container(width: 12, height: 2, color: cs.primary), '${fmtNum(_r(p.avg7))} kg', 'media 7 días'),
          row(Container(width: 6, height: 6, decoration: BoxDecoration(color: cs.onSurfaceVariant, shape: BoxShape.circle)),
              '${fmtNum(p.weight)} kg', 'ese día'),
        ]),
      ),
    );
  }
}

/// Posiciones compartidas por el dibujo y la detección del punto más cercano.
class _Geom {
  _Geom(List<WeightPoint> pts, this.size)
      : t0 = pts.first.date,
        days = math.max(1, daysBetween(pts.first.date, pts.last.date)),
        scale = niceScale(
          pts.map((p) => math.min(p.weight, p.avg7)).reduce(math.min),
          pts.map((p) => math.max(p.weight, p.avg7)).reduce(math.max),
        );
  final Size size;
  final DateTime t0;
  final int days;
  final ({double min, double max, double step}) scale;

  double get plotW => size.width - _WeightChartState._left - _WeightChartState._right;
  double get plotH => size.height - _WeightChartState._top - _WeightChartState._bottom;
  double x(DateTime d) => _WeightChartState._left + plotW * daysBetween(t0, d) / days;
  double y(double v) => _WeightChartState._top + plotH * (1 - (v - scale.min) / (scale.max - scale.min));
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.pts, this.g,
      {required this.hover,
      required this.grid,
      required this.dots,
      required this.line,
      required this.surface,
      required this.crosshair,
      required this.axisText,
      required this.endLabel});
  final List<WeightPoint> pts;
  final _Geom g;
  final int? hover;
  final Color grid, dots, line, surface, crosshair;
  final TextStyle axisText, endLabel;

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {TextAlign align = TextAlign.left, bool vCenter = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    final dx = switch (align) { TextAlign.right => at.dx - tp.width, TextAlign.center => at.dx - tp.width / 2, _ => at.dx };
    tp.paint(canvas, Offset(dx, vCenter ? at.dy - tp.height / 2 : at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final hair = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final left = _WeightChartState._left, right = size.width - _WeightChartState._right;
    // Rejilla horizontal: líneas finas y continuas, con las marcas del eje Y
    for (var v = g.scale.min; v <= g.scale.max + 1e-9; v += g.scale.step) {
      final y = g.y(v);
      canvas.drawLine(Offset(left, y), Offset(right, y), hair);
      _text(canvas, fmtNum(_r(v)), axisText, Offset(left - 6, y), align: TextAlign.right);
    }
    // Eje X: primera, mitad y última fecha
    final base = size.height - _WeightChartState._bottom;
    final ticks = {pts.first.date, if (g.days > 14) daysBefore(g.t0, -(g.days ~/ 2)), pts.last.date};
    for (final d in ticks) {
      _text(canvas, shortDate(d), axisText, Offset(g.x(d), base + 6), align: TextAlign.center, vCenter: false);
    }

    if (hover != null) {
      final x = g.x(pts[hover!].date);
      canvas.drawLine(Offset(x, _WeightChartState._top), Offset(x, base), hair..color = crosshair);
    }

    // Peso del día: puntos pequeños en segundo plano
    final dot = Paint()..color = dots;
    for (final p in pts) {
      canvas.drawCircle(Offset(g.x(p.date), g.y(p.weight)), 2.5, dot);
    }

    // Media de 7 días: línea de 2 px
    final path = Path()..moveTo(g.x(pts.first.date), g.y(pts.first.avg7));
    for (final p in pts.skip(1)) {
      path.lineTo(g.x(p.date), g.y(p.avg7));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);

    // Punto final con anillo del color de fondo y su valor al lado (única etiqueta directa)
    final end = Offset(g.x(pts.last.date), g.y(pts.last.avg7));
    final focus = hover == null ? end : Offset(g.x(pts[hover!].date), g.y(pts[hover!].avg7));
    canvas.drawCircle(focus, 6, Paint()..color = surface);
    canvas.drawCircle(focus, 4, Paint()..color = line);
    if (hover == null) _text(canvas, '${fmtNum(_r(pts.last.avg7))} kg', endLabel, end + const Offset(10, 0));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.pts != pts || old.hover != hover || old.line != line || old.grid != grid || old.g.size != g.size;
}
