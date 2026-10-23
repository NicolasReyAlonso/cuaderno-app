import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'figure.dart';

/// Muñeco animado que va y vuelve entre la pose a y la b.
class AnimatedFigure extends StatefulWidget {
  const AnimatedFigure({super.key, required this.spec, this.period = const Duration(milliseconds: 2800)});

  final FigureSpec spec;
  final Duration period;

  @override
  State<AnimatedFigure> createState() => _AnimatedFigureState();
}

class _AnimatedFigureState extends State<AnimatedFigure> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);
  final double _offset = math.Random().nextDouble();
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FigureColors.of(Theme.of(context));
    return AspectRatio(
      aspectRatio: kFigureW / kFigureH,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final phase = (_c.value + _offset) % 1;
          // Con «reducir movimiento» activado se queda quieto en la pose b
          final u = _still ? 1.0 : (1 - math.cos(phase * 2 * math.pi)) / 2;
          return CustomPaint(painter: FigurePainter(widget.spec, u, colors));
        },
      ),
    );
  }
}

class FigureColors {
  final Color body, ghost, equipment, equipmentFill, plate, plateHole, pad, iron, cable;
  const FigureColors({
    required this.body,
    required this.ghost,
    required this.equipment,
    required this.equipmentFill,
    required this.plate,
    required this.plateHole,
    required this.pad,
    required this.iron,
    required this.cable,
  });

  factory FigureColors.of(ThemeData t) {
    final c = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return FigureColors(
      body: c.onSurface,
      ghost: c.primary.withValues(alpha: 0.2),
      equipment: c.outline,
      equipmentFill: c.outlineVariant,
      plate: dark ? const Color(0xFFE5594E) : const Color(0xFFC8332A),
      plateHole: c.surfaceContainerHighest,
      pad: dark ? const Color(0xFFE5B43A) : const Color(0xFFD9A10B),
      iron: dark ? const Color(0xFFB9C3CD) : const Color(0xFF3A434D),
      cable: c.onSurfaceVariant,
    );
  }
}

class FigurePainter extends CustomPainter {
  FigurePainter(this.spec, this.u, this.colors);

  final FigureSpec spec;
  final double u;
  final FigureColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / kFigureW, size.height / kFigureH);
    _props(canvas);
    _body(canvas, spec.solve(0), colors.ghost);
    final j = spec.solve(u);
    _gear(canvas, j, behind: true);
    _body(canvas, j, colors.body);
    _gear(canvas, j, behind: false);
    canvas.restore();
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _fill(Color c) => Paint()..color = c;

  void _props(Canvas canvas) {
    if (spec.floor) canvas.drawLine(const Offset(4, kFloorY), const Offset(196, kFloorY), _stroke(colors.equipment, 2));
    for (final p in spec.props) {
      switch (p.kind) {
        case 'line':
          canvas.drawLine(Offset(p.v[0], p.v[1]), Offset(p.v[2], p.v[3]), _stroke(colors.equipment, p.v.length > 4 ? p.v[4] : 3));
        case 'rect':
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(p.v[0], p.v[1], p.v[2], p.v[3]), const Radius.circular(2)), _fill(colors.equipmentFill));
        case 'circle':
          canvas.drawCircle(Offset(p.v[0], p.v[1]), p.v[2], _fill(colors.equipmentFill));
        case 'poly':
          canvas.drawPath(Path()..addPolygon(p.points, true), _fill(colors.equipmentFill));
      }
    }
  }

  void _limb(Canvas canvas, List<Offset?> pts, Color c) {
    final ps = pts.whereType<Offset>().toList();
    if (ps.length < 2) return;
    final path = Path()..moveTo(ps.first.dx, ps.first.dy);
    for (final p in ps.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, _stroke(c, 6.5));
  }

  void _body(Canvas canvas, Joints j, Color c) {
    final far = spec.front ? c : c.withValues(alpha: c.a * 0.42);
    if (j.k2 != null) _limb(canvas, [spec.front ? j.h2 : j.hip, j.k2, j.a2, j.t2], far);
    if (j.e2 != null && !spec.front) _limb(canvas, [j.shoulder, j.e2, j.w2], far);
    _limb(canvas, [j.h1, j.k1, j.a1, j.t1], c);
    if (spec.front) {
      canvas.drawLine(j.h1, j.h2, _stroke(c, 9));
      canvas.drawLine(j.s1, j.s2, _stroke(c, 9));
    }
    canvas.drawLine(j.hip, j.shoulder, _stroke(c, 11));
    canvas.drawCircle(j.head, 8.5, _fill(c));
    _limb(canvas, [j.s1, j.e1, j.w1], c);
    if (j.e2 != null && spec.front) _limb(canvas, [j.s2, j.e2, j.w2], c);
  }

  void _gear(Canvas canvas, Joints j, {required bool behind}) {
    for (final g in spec.gear) {
      if (g.behind != behind) continue;
      final base = j.at(g.at);
      if (base == null) continue;
      final p = base + g.d;
      switch (g.kind) {
        case 'plate':
          final r = g.r ?? 10;
          canvas.drawCircle(p, r, _fill(colors.plate));
          canvas.drawCircle(p, r * 0.22, _fill(colors.plateHole));
        case 'wheel':
          canvas.drawCircle(p + const Offset(0, 4), 8, _fill(colors.plate));
          canvas.drawCircle(p + const Offset(0, 4), 2, _fill(colors.plateHole));
        case 'db':
          _rects(canvas, p, const [Rect.fromLTWH(-9, -2, 18, 4), Rect.fromLTWH(-10, -5, 5, 10), Rect.fromLTWH(5, -5, 5, 10)]);
        case 'dbv':
          _rects(canvas, p, const [Rect.fromLTWH(-2, -9, 4, 18), Rect.fromLTWH(-5, -10, 10, 5), Rect.fromLTWH(-5, 5, 10, 5)]);
        case 'cable':
          if (g.from != null) canvas.drawLine(g.from!, p, _stroke(colors.cable, 1.4)..strokeCap = StrokeCap.butt);
        case 'pad':
          canvas.drawCircle(p, 5.5, _fill(colors.pad));
        case 'spad':
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(p.dx - 9, p.dy - 8, 16, 7), const Radius.circular(3)), _fill(colors.pad));
        case 'hbar':
          canvas.drawLine(p - const Offset(20, 0), p + const Offset(20, 0), _stroke(colors.iron, 3));
        case 'sbar':
          canvas.drawLine(p + const Offset(-9, 2), p + const Offset(9, -2), _stroke(colors.iron, 3));
        case 'vbar':
          canvas.drawPath(
              Path()
                ..moveTo(p.dx - 7, p.dy + 3)
                ..lineTo(p.dx, p.dy - 5)
                ..lineTo(p.dx + 7, p.dy + 3),
              _stroke(colors.iron, 3));
        case 'backpad':
          final ang = math.atan2(-j.dir.dy, j.dir.dx) + math.pi / 2;
          final n = Offset(math.cos(ang), -math.sin(ang));
          final a = j.hip + n * 7 - j.dir * 4;
          final b = j.shoulder + n * 7 + j.dir * 6;
          canvas.drawLine(a, b, _stroke(colors.pad, 6));
        case 'lever':
          if (g.from == null) break;
          canvas.drawLine(g.from!, p, _stroke(colors.iron, 3));
          final v = g.from! - p;
          final len = v.distance == 0 ? 1.0 : v.distance;
          canvas.drawCircle(p + v / len * 12, 9, _fill(colors.plate));
        case 'plat':
          final a = (g.angle ?? 0) * math.pi / 180;
          final v = Offset(math.cos(a) * 15, -math.sin(a) * 15);
          canvas.drawLine(p - v, p + v, _stroke(colors.pad, 6));
      }
    }
  }

  void _rects(Canvas canvas, Offset p, List<Rect> rs) {
    for (final r in rs) {
      canvas.drawRRect(RRect.fromRectAndRadius(r.shift(p), const Radius.circular(1.5)), _fill(colors.iron));
    }
  }

  @override
  bool shouldRepaint(FigurePainter old) => old.u != u || old.spec != spec || old.colors.body != colors.body;
}
