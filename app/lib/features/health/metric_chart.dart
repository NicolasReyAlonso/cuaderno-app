import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../body/models.dart' show daysBetween;
import '../body/weight_chart.dart' show niceScale;
import '../workout/exercise_card.dart' show shortDate;
import 'metrics.dart';

/// Gráfica de un valor por día entre [from] y [to] (los días sin dato quedan vacíos).
/// Barras para cantidades (pasos, kcal, sueño) y línea para tendencias (pulso, VFC, peso).
/// [compact]: sin ejes ni interacción, para la tarjeta.
class MetricChart extends StatefulWidget {
  const MetricChart({super.key, required this.metric, required this.points, required this.from, required this.to, this.compact = false, this.height});
  final Metric metric;
  final List<DayValue> points;
  final DateTime from, to;
  final bool compact;
  final double? height;

  @override
  State<MetricChart> createState() => _MetricChartState();
}

class _MetricChartState extends State<MetricChart> {
  int? _hover;

  double get _height => widget.height ?? (widget.compact ? 44 : 220);

  int _nearest(_Geom g, double dx) {
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
    final m = widget.metric;
    final pts = widget.points;
    if (pts.isEmpty) return SizedBox(height: _height);
    return Semantics(
      label: widget.compact
          ? null
          : '${m.label}: ${pts.length} días con dato entre el ${shortDate(widget.from)} y el ${shortDate(widget.to)}; '
              'el último, ${m.withUnit(pts.last.value)}. Los valores de cada día están en la lista de abajo.',
      child: LayoutBuilder(builder: (context, c) {
        final g = _Geom(widget, Size(c.maxWidth, _height));
        final i = _hover;
        final chart = CustomPaint(
          size: g.size,
          painter: _Painter(
            g,
            hover: i,
            series: cs.primary,
            grid: cs.outlineVariant,
            band: cs.onSurface.withValues(alpha: 0.06),
            surface: cs.surface,
            crosshair: cs.outline,
            axis: t.textTheme.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        );
        if (widget.compact) return SizedBox(height: _height, child: chart);
        void pick(Offset p) => setState(() => _hover = _nearest(g, p.dx));
        return MouseRegion(
          onHover: (e) => pick(e.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: GestureDetector(
            onTapDown: (e) => pick(e.localPosition),
            onHorizontalDragUpdate: (e) => pick(e.localPosition),
            child: SizedBox(
              height: _height,
              child: Stack(clipBehavior: Clip.none, children: [
                chart,
                if (i != null)
                  Positioned(
                    left: (g.x(pts[i].date) + 10).clamp(0, math.max(0, c.maxWidth - 150)),
                    // En la mitad contraria a la del valor, para no taparlo
                    top: g.y(pts[i].value) < _height / 2 ? null : 0,
                    bottom: g.y(pts[i].value) < _height / 2 ? _Geom.bottomPad + 4 : null,
                    child: IgnorePointer(child: _Tooltip(text: m.withUnit(pts[i].value), date: pts[i].date)),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.text, required this.date});
  final String text;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(shortDate(date), style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          Text(text, style: t.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// Posiciones compartidas por el dibujo y la detección del día más cercano.
class _Geom {
  _Geom(this.w, this.size)
      : days = math.max(0, daysBetween(w.from, w.to)),
        scale = _scale(w);
  final MetricChart w;
  final Size size;
  final int days;
  final ({double min, double max, double step}) scale;

  static const bottomPad = 22.0;
  double get left => w.compact ? 2 : 44;
  double get right => w.compact ? 2 : 12;
  double get top => w.compact ? 4 : 10;
  double get bottom => w.compact ? 2 : bottomPad;
  double get plotW => size.width - left - right;
  double get plotH => size.height - top - bottom;
  double get slot => plotW / (days + 1);

  static ({double min, double max, double step}) _scale(MetricChart w) {
    final vals = [for (final p in w.points) p.value];
    final hi = math.max(vals.reduce(math.max), w.metric.target?.hi ?? 0);
    if (w.metric.kind == ChartKind.bars) {
      // Las barras salen siempre de cero: si no, la altura engaña
      final u = w.metric.axisUnit;
      final s = _niceUp(hi / u);
      return (min: 0, max: s.max * u, step: s.step * u);
    }
    return niceScale(vals.reduce(math.min), vals.reduce(math.max));
  }

  /// De 0 a un número redondo por encima de [hi], con 3–5 marcas.
  static ({double max, double step}) _niceUp(double hi) {
    if (hi <= 0) return (max: 1, step: 1);
    final raw = hi / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final step = [1, 2, 2.5, 5, 10].map((f) => f * mag).firstWhere((s) => s >= raw);
    return (max: (hi / step).ceil() * step, step: step);
  }

  double x(DateTime d) => left + slot * (daysBetween(w.from, d) + 0.5);
  double y(double v) => top + plotH * (1 - (v - scale.min) / (scale.max - scale.min));
}

class _Painter extends CustomPainter {
  _Painter(this.g, {required this.hover, required this.series, required this.grid, required this.band, required this.surface, required this.crosshair, required this.axis});
  final _Geom g;
  final int? hover;
  final Color series, grid, band, surface, crosshair;
  final TextStyle axis;

  void _text(Canvas canvas, String s, Offset at, {TextAlign align = TextAlign.left, bool vCenter = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: axis), textDirection: TextDirection.ltr)..layout();
    final dx = switch (align) { TextAlign.right => at.dx - tp.width, TextAlign.center => at.dx - tp.width / 2, _ => at.dx };
    tp.paint(canvas, Offset(dx, vCenter ? at.dy - tp.height / 2 : at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final m = g.w.metric;
    final pts = g.w.points;
    final compact = g.w.compact;
    final base = size.height - g.bottom;
    final hair = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Franja de referencia (objetivo de pasos de la guía). Sin etiqueta dentro: las barras la taparían;
    // la pantalla de detalle la explica debajo de las cifras.
    final target = m.target;
    if (target != null) {
      final top = g.y(target.hi).clamp(g.top, base), bottom = g.y(target.lo).clamp(g.top, base);
      canvas.drawRect(Rect.fromLTRB(g.left, top, size.width - g.right, bottom), Paint()..color = band);
    }

    if (!compact) {
      // Rejilla horizontal: líneas finas y continuas, con las marcas del eje Y
      for (var v = g.scale.min; v <= g.scale.max + 1e-9; v += g.scale.step) {
        canvas.drawLine(Offset(g.left, g.y(v)), Offset(size.width - g.right, g.y(v)), hair);
        _text(canvas, m.axisText(v), Offset(g.left - 6, g.y(v)), align: TextAlign.right);
      }
      final ticks = {g.w.from, if (g.days > 14) DateTime(g.w.from.year, g.w.from.month, g.w.from.day + g.days ~/ 2), g.w.to};
      for (final d in ticks) {
        _text(canvas, shortDate(d), Offset(g.x(d), base + 6), align: TextAlign.center, vCenter: false);
      }
      if (hover != null) {
        final x = g.x(pts[hover!].date);
        canvas.drawLine(Offset(x, g.top), Offset(x, base), hair..color = crosshair);
      }
    }

    final fill = Paint()..color = series;
    if (m.kind == ChartKind.bars) {
      final w = (g.slot * 0.62).clamp(2.0, 24.0); // el resto del hueco queda de aire entre barras
      final r = math.min(4.0, w / 2);
      for (final p in pts) {
        final x = g.x(p.date);
        final rect = Rect.fromLTRB(x - w / 2, g.y(p.value), x + w / 2, g.y(0));
        // Extremo redondeado arriba, recto en la base
        canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: Radius.circular(r), topRight: Radius.circular(r)), fill);
      }
    } else {
      final path = Path()..moveTo(g.x(pts.first.date), g.y(pts.first.value));
      for (final p in pts.skip(1)) {
        path.lineTo(g.x(p.date), g.y(p.value));
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = series
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);
      // Puntos con anillo del color de fondo: todos si son pocos; si no, solo el último (o el señalado)
      final marks = !compact && pts.length <= 31 ? pts : [hover == null ? pts.last : pts[hover!]];
      for (final p in marks) {
        final o = Offset(g.x(p.date), g.y(p.value));
        canvas.drawCircle(o, compact ? 3.5 : 5.5, Paint()..color = surface);
        canvas.drawCircle(o, compact ? 2.5 : 4, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_Painter old) => old.g.w.points != g.w.points || old.hover != hover || old.series != series || old.g.size != g.size;
}
