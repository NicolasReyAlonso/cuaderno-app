import 'dart:math' as math;
import 'dart:ui' show Offset, lerpDouble;

/// Muñeco articulado con cinemática inversa de dos segmentos.
///
/// Mismo formato y misma matemática que el cuaderno web: cada ejercicio trae
/// una pose `a` y otra `b` en un lienzo de 200 × 170 (suelo en y = 160) y la
/// animación interpola entre ambas.
const double kFigureW = 200, kFigureH = 170, kFloorY = 160;
const double _d2r = math.pi / 180;

class Target {
  final Offset? abs;
  final String? rel; // 'S' hombro, 'H' cadera, 'head'
  final Offset d;
  const Target.absolute(Offset p)
      : abs = p,
        rel = null,
        d = Offset.zero;
  const Target.relative(this.rel, this.d) : abs = null;

  static Target parse(dynamic j) {
    if (j is List) return Target.absolute(_off(j));
    final m = j as Map<String, dynamic>;
    return Target.relative(m['rel'] as String, _off(m['d'] as List));
  }

  Target lerp(Target o, double u) => abs != null && o.abs != null
      ? Target.absolute(Offset.lerp(abs, o.abs, u)!)
      : Target.relative(rel, Offset.lerp(d, o.d, u)!);
}

class Pose {
  final Offset hip;
  final double t; // ángulo del tronco en grados (90 = vertical)
  final Target hand;
  final Target? hand2;
  final Offset foot;
  final Offset? foot2;
  final double? toe, toe2;

  const Pose({required this.hip, required this.t, required this.hand, this.hand2, required this.foot, this.foot2, this.toe, this.toe2});

  factory Pose.fromJson(Map<String, dynamic> j) => Pose(
        hip: _off(j['hip'] as List),
        t: (j['t'] as num).toDouble(),
        hand: Target.parse(j['hand']),
        hand2: j['hand2'] == null ? null : Target.parse(j['hand2']),
        foot: _off(j['foot'] as List),
        foot2: j['foot2'] == null ? null : _off(j['foot2'] as List),
        toe: (j['toe'] as num?)?.toDouble(),
        toe2: (j['toe2'] as num?)?.toDouble(),
      );

  Pose lerp(Pose b, double u) => Pose(
        hip: Offset.lerp(hip, b.hip, u)!,
        t: lerpDouble(t, b.t, u)!,
        hand: hand.lerp(b.hand, u),
        hand2: hand2 == null ? null : hand2!.lerp(b.hand2 ?? hand2!, u),
        foot: Offset.lerp(foot, b.foot, u)!,
        foot2: foot2 == null ? null : Offset.lerp(foot2, b.foot2 ?? foot2, u),
        toe: toe == null ? null : lerpDouble(toe, b.toe ?? toe, u),
        toe2: toe2 == null ? null : lerpDouble(toe2, b.toe2 ?? toe2, u),
      );
}

/// Elemento del decorado: máquina, banco, poste…
class Prop {
  final String kind; // line | rect | circle | poly
  final List<double> v;
  final List<Offset> points;
  const Prop(this.kind, this.v, [this.points = const []]);

  static Prop parse(List j) {
    final kind = j[0] as String;
    if (kind == 'poly') {
      final pts = (j[1] as String).split(' ').map((p) {
        final xy = p.split(',').map(double.parse).toList();
        return Offset(xy[0], xy[1]);
      }).toList();
      return Prop(kind, const [], pts);
    }
    return Prop(kind, j.sublist(1).map((e) => (e as num).toDouble()).toList());
  }
}

/// Material que se mueve con el cuerpo: disco, mancuerna, cable…
class Gear {
  final String kind;
  final String? at;
  final Offset d;
  final Offset? from;
  final double? r, angle;
  final bool behind;
  const Gear({required this.kind, this.at, this.d = Offset.zero, this.from, this.r, this.angle, this.behind = false});

  factory Gear.fromJson(Map<String, dynamic> j) => Gear(
        kind: j['k'] as String,
        at: j['at'] as String?,
        d: j['d'] == null ? Offset.zero : _off(j['d'] as List),
        from: j['from'] == null ? null : _off(j['from'] as List),
        r: (j['r'] as num?)?.toDouble(),
        angle: (j['a'] as num?)?.toDouble(),
        behind: j['behind'] == true,
      );
}

class FigureSpec {
  final Pose a, b;
  final bool front, floor;
  final double fs, ls, tl, ho;
  final double eb, eb2, kb, kb2;
  final List<Prop> props;
  final List<Gear> gear;

  const FigureSpec({
    required this.a,
    required this.b,
    this.front = false,
    this.floor = true,
    this.fs = 1,
    this.ls = 1,
    this.tl = 46,
    this.ho = 13,
    this.eb = -1,
    this.eb2 = -1,
    this.kb = 1,
    this.kb2 = 1,
    this.props = const [],
    this.gear = const [],
  });

  factory FigureSpec.fromJson(Map<String, dynamic> j) {
    double n(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    final eb = n('eb', -1), kb = n('kb', 1);
    return FigureSpec(
      a: Pose.fromJson(j['a'] as Map<String, dynamic>),
      b: Pose.fromJson(j['b'] as Map<String, dynamic>),
      front: j['front'] == true,
      floor: j['floor'] != false,
      fs: n('fs', 1),
      ls: n('ls', 1),
      tl: n('tl', 46),
      ho: n('ho', 13),
      eb: eb,
      eb2: n('eb2', eb),
      kb: kb,
      kb2: n('kb2', kb),
      props: ((j['props'] as List?) ?? const []).map((p) => Prop.parse(p as List)).toList(),
      gear: ((j['gear'] as List?) ?? const []).map((g) => Gear.fromJson(g as Map<String, dynamic>)).toList(),
    );
  }

  /// Fase de animación u ∈ [0, 1]: 0 = pose a, 1 = pose b.
  Joints solve(double u) => _solve(this, a.lerp(b, u));
}

/// Articulaciones resueltas, en coordenadas del lienzo 200 × 170.
class Joints {
  final Offset hip, shoulder, head, s1, s2, h1, h2, dir;
  final Offset e1, w1, k1, a1, t1;
  final Offset? e2, w2, k2, a2, t2;
  const Joints({
    required this.hip,
    required this.shoulder,
    required this.head,
    required this.s1,
    required this.s2,
    required this.h1,
    required this.h2,
    required this.dir,
    required this.e1,
    required this.w1,
    required this.k1,
    required this.a1,
    required this.t1,
    this.e2,
    this.w2,
    this.k2,
    this.a2,
    this.t2,
  });

  Offset? at(String? key) => switch (key) {
        'hand' => w1,
        'hand2' => w2,
        'ankle' => a1,
        'ankle2' => a2,
        'knee' => k1,
        'knee2' => k2,
        'hip' => hip,
        'S' => shoulder,
        'head' => head,
        'toe' => t1,
        _ => shoulder,
      };
}

/// Resuelve un segmento doble: devuelve [articulación intermedia, extremo].
(Offset, Offset) ik(Offset root, Offset target, double l1, double l2, double bend) {
  final dx = target.dx - root.dx, dy = root.dy - target.dy;
  final th = math.atan2(dy, dx);
  final double d = math.sqrt(dx * dx + dy * dy).clamp((l1 - l2).abs() + 0.5, l1 + l2 - 0.3).toDouble();
  final double ca = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d);
  final double al = math.acos(ca.clamp(-1.0, 1.0).toDouble());
  final ang = th + bend * al;
  return (
    Offset(root.dx + l1 * math.cos(ang), root.dy - l1 * math.sin(ang)),
    Offset(root.dx + d * math.cos(th), root.dy - d * math.sin(th)),
  );
}

Joints _solve(FigureSpec s, Pose p) {
  final h = p.hip;
  final tr = p.t * _d2r;
  final dir = Offset(math.cos(tr), -math.sin(tr));
  final sh = h + dir * s.tl;
  final head = sh + dir * s.ho;
  final sw = s.front ? 11.0 : 0.0, hw = s.front ? 7.0 : 0.0;
  final s1 = Offset(sh.dx - sw, sh.dy), s2 = Offset(sh.dx + sw, sh.dy);
  final h1 = Offset(h.dx - hw, h.dy), h2 = Offset(h.dx + hw, h.dy);

  Offset tg(Target t) {
    if (t.abs != null) return t.abs!;
    final base = switch (t.rel) { 'S' => sh, 'H' => h, _ => head };
    return base + t.d;
  }

  final (e1, w1) = ik(s1, tg(p.hand), 27 * s.fs, 25 * s.fs, s.eb);
  Offset? e2, w2;
  if (p.hand2 != null) {
    final r = ik(s.front ? s2 : sh, tg(p.hand2!), 27 * s.fs, 25 * s.fs, s.eb2);
    e2 = r.$1;
    w2 = r.$2;
  }
  final (k1, a1) = ik(h1, p.foot, 37 * s.ls, 36 * s.ls, s.kb);
  Offset? k2, a2;
  if (p.foot2 != null) {
    final r = ik(s.front ? h2 : h, p.foot2!, 37 * s.ls, 36 * s.ls, s.kb2);
    k2 = r.$1;
    a2 = r.$2;
  }

  Offset toe(Offset a, double deg) => Offset(a.dx + 9 * math.cos(deg * _d2r), a.dy - 9 * math.sin(deg * _d2r));
  final t1 = toe(a1, s.front ? (s.kb == -1 ? 200 : -20) : (p.toe ?? 0));
  final t2 = a2 == null ? null : toe(a2, s.front ? -20 : (p.toe2 ?? 0));

  return Joints(hip: h, shoulder: sh, head: head, s1: s1, s2: s2, h1: h1, h2: h2, dir: dir,
      e1: e1, w1: w1, k1: k1, a1: a1, t1: t1, e2: e2, w2: w2, k2: k2, a2: a2, t2: t2);
}

Offset _off(List l) => Offset((l[0] as num).toDouble(), (l[1] as num).toDouble());
