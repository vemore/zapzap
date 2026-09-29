import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The drawing kit of the round-end overlays, ported from the proposals the
/// user chose on 2026-09-29 (artifact XxPTAsHtJmAQwpA6vDc2Mo): the lightning,
/// the sparks, the rings, the flashes, the arcs, the dust, the shakes and the
/// Web Animations keyframes they are timed with.
///
/// Every piece is a pure function of its own clock, in milliseconds, and of a
/// seed: a frame is the same on every device and in every test, and nothing
/// is integrated frame by frame. Speeds are in pixels per 16.7 ms frame, as
/// the proposals wrote them.

/// One frame of the proposals, in milliseconds.
const fxFrame = 16.7;

/// A number between [a] and [b].
double rnd(math.Random r, double a, double b) => a + r.nextDouble() * (b - a);

/// `1 − (1 − t)³`.
double out3(double t) => 1 - math.pow(1 - t, 3).toDouble();

/// The cubic ease in and out.
double inOut3(double t) =>
    t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

double linear(double t) => t;

/// The CSS `cubic-bezier` easings of the proposals, by what they do.
abstract final class FxCurves {
  /// A letter, a float or a badge popping in past its size.
  static const pop = Cubic(0.2, 1.4, 0.35, 1);

  /// The stamp falling: slow, then all at once.
  static const slam = Cubic(0.55, 0, 1, 0.45);

  /// The gauge growing out of the score bar.
  static const grow = Cubic(0.2, 1.3, 0.4, 1);

  /// The tape sliding across the row.
  static const tape = Cubic(0.2, 0.9, 0.3, 1);

  /// The word drawn back into the banner.
  static const absorb = Cubic(0.55, 0, 0.85, 0.35);

  /// CSS `ease-out` and `ease-in`.
  static const easeOut = Cubic(0, 0, 0.58, 1);
  static const easeIn = Cubic(0.42, 0, 1, 1);
}

/// A Web Animations run with `fill: both`: [values] at [offsets] (evenly
/// spread when null), [ease] over the whole run, held before [delay] and
/// after its end. An easing that overshoots extrapolates the end segments,
/// as a browser does.
double kf(
  double t,
  double delay,
  double duration,
  List<double> values, {
  List<double>? offsets,
  double Function(double) ease = linear,
}) {
  final p = ((t - delay) / duration).clamp(0.0, 1.0);
  final e = ease(p);
  final n = values.length;
  final at = offsets ?? [for (var i = 0; i < n; i++) i / (n - 1)];
  var i = 0;
  while (i < n - 2 && e > at[i + 1]) {
    i++;
  }
  final span = at[i + 1] - at[i];
  final local = span == 0 ? 1.0 : (e - at[i]) / span;
  return values[i] + (values[i + 1] - values[i]) * local;
}

/// Whether a run with `fill: none` shows at [t].
bool running(double t, double delay, double duration) =>
    t >= delay && t < delay + duration;

/// `s.dim` and `s.spot` of the proposals: an opacity that fades in over
/// [fadeIn] from [from], holds, then fades out over [fadeOut] from [until].
double fadeInOut(
  double t, {
  required double from,
  required double until,
  double fadeIn = 200,
  double fadeOut = 320,
}) {
  if (t < from) return 0;
  if (t < until) {
    return FxCurves.easeOut.transform(((t - from) / fadeIn).clamp(0.0, 1.0));
  }
  return 1 - FxCurves.easeIn.transform(((t - until) / fadeOut).clamp(0, 1));
}

/// A shake (`s.shake`): eleven random offsets and tilts that die out,
/// linear between them, nothing outside its run.
class Shake {
  Shake(int seed, this.amplitude, this.duration, {this.delay = 0}) {
    final r = math.Random(seed);
    for (var i = 0; i <= 10; i++) {
      final k = 1 - i / 10;
      _dx.add(i == 10 ? 0 : rnd(r, -amplitude, amplitude) * k);
      _dy.add(i == 10 ? 0 : rnd(r, -amplitude, amplitude) * k);
      _deg.add(i == 10 ? 0 : rnd(r, -0.7, 0.7) * k);
    }
  }

  final double amplitude;
  final double duration;
  final double delay;
  final _dx = <double>[];
  final _dy = <double>[];
  final _deg = <double>[];

  /// The offset at [t].
  Offset offset(double t) => running(t, delay, duration)
      ? Offset(kf(t, delay, duration, _dx), kf(t, delay, duration, _dy))
      : Offset.zero;

  /// The tilt at [t], in radians.
  double angle(double t) => running(t, delay, duration)
      ? kf(t, delay, duration, _deg) * math.pi / 180
      : 0;
}

/// A midpoint-displaced zigzag from [a] to [b] (`jag`): 2^[depth] segments.
List<Offset> jag(math.Random r, Offset a, Offset b, double rough, int depth) {
  var points = [a, b];
  var off = (b - a).distance * rough;
  for (var d = 0; d < depth; d++) {
    final next = <Offset>[points.first];
    for (var i = 0; i < points.length - 1; i++) {
      final p1 = points[i], p2 = points[i + 1];
      final length = (p2 - p1).distance == 0 ? 1.0 : (p2 - p1).distance;
      final o = rnd(r, -off, off);
      next
        ..add(
          Offset(
            (p1.dx + p2.dx) / 2 - (p2.dy - p1.dy) / length * o,
            (p1.dy + p2.dy) / 2 + (p2.dx - p1.dx) / length * o,
          ),
        )
        ..add(p2);
    }
    points = next;
    off *= 0.5;
  }
  return points;
}

/// [n] branches off a bolt's [main] path (`forks`).
List<List<Offset>> forks(
  math.Random r,
  List<Offset> main,
  int n,
  double scale,
) => [
  for (var k = 0; k < n; k++)
    () {
      final i = (rnd(r, 0.15, 0.7) * main.length).floor();
      final p = main[i], q = main[math.min(main.length - 1, i + 4)];
      final angle =
          math.atan2(q.dy - p.dy, q.dx - p.dx) +
          rnd(r, 0.35, 0.8) * (r.nextBool() ? -1 : 1);
      final length = rnd(r, 0.16, 0.32) * scale;
      return jag(
        r,
        p,
        p + Offset(math.cos(angle) * length, math.sin(angle) * length),
        0.25,
        4,
      );
    }(),
];

/// A bolt's strokes (`strokeBolt`): a wide faint glow, a coloured body and
/// a white core, added onto what lies under them; the branches are thinner.
void strokeBolt(
  Canvas canvas,
  List<List<Offset>> paths,
  Color colour,
  double width,
  double alpha,
) {
  if (alpha <= 0 || paths.isEmpty) return;
  final built = [
    for (var k = 0; k < paths.length; k++)
      (path: _polyline(paths[k]), m: k == 0 ? 1.0 : 0.55),
  ];
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..blendMode = BlendMode.plus;
  for (final b in built) {
    _stroke(
      canvas,
      b.path,
      paint,
      colour,
      alpha * 0.28 * b.m,
      width * 5 * b.m,
      22,
    );
  }
  for (final b in built) {
    _stroke(
      canvas,
      b.path,
      paint,
      colour,
      alpha * 0.95 * b.m,
      width * 1.7 * b.m,
      8,
    );
  }
  for (final b in built) {
    _stroke(
      canvas,
      b.path,
      paint,
      const Color(0xFFFFFFFF),
      alpha * b.m,
      width * 0.65 * b.m,
      0,
    );
  }
}

Path _polyline(List<Offset> points) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (final p in points.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  return path;
}

/// One stroke and, for a canvas `shadowBlur`, its blurred copy under it.
void _stroke(
  Canvas canvas,
  Path path,
  Paint paint,
  Color colour,
  double alpha,
  double width,
  double blur,
) {
  paint
    ..color = colour.withValues(alpha: alpha.clamp(0.0, 1.0))
    ..strokeWidth = width;
  if (blur > 0) {
    paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2);
    canvas.drawPath(path, paint);
    paint.maskFilter = null;
  }
  canvas.drawPath(path, paint);
}

/// A lightning bolt (`Lightning`): redrawn every [regen] ms from [from] to
/// [to], lit fully for [hold] ms, then flickering out until [life].
class Lightning {
  Lightning({
    required this.seed,
    required this.from,
    required this.to,
    this.width = _constWidth,
    this.life = 450,
    double? hold,
    this.regen = 45,
    this.branches = 2,
    this.rough = 0.18,
    this.depth = 7,
    this.colour = const Color(0xFFFBBF24),
  }) : hold = hold ?? life * 0.4;

  final int seed;
  final Offset Function(double t) from;
  final Offset Function(double t) to;
  final double Function(double t) width;
  final double life;
  final double hold;
  final double regen;
  final int branches;
  final double rough;
  final int depth;
  final Color colour;

  static double _constWidth(double t) => 2.2;

  void paint(Canvas canvas, double t) {
    if (t < 0 || t > life) return;
    final k = (t / regen).floor();
    final at = k * regen;
    final r = math.Random(seed * 7919 + k);
    final a = from(at), b = to(at);
    final main = jag(r, a, b, rough, depth);
    final paths = [main, ...forks(r, main, branches, (b - a).distance)];
    final flicker = math.Random(seed * 31 + (t / fxFrame).floor());
    final alpha = t < hold
        ? 1.0
        : math.max(0.0, 1 - (t - hold) / (life - hold)) * rnd(flicker, 0.55, 1);
    strokeBolt(canvas, paths, colour, width(t), alpha);
  }
}

/// Arcs crawling along a rectangle's border (`ArcCrawl`).
class ArcCrawl {
  ArcCrawl({
    required this.seed,
    required this.rect,
    this.life = 900,
    this.count = 3,
    this.colour = const Color(0xFFFBBF24),
  });

  final int seed;
  final Rect rect;
  final double life;
  final int count;
  final Color colour;

  Offset _at(double d) {
    final w = rect.width, h = rect.height, per = 2 * (w + h);
    d = ((d % per) + per) % per;
    if (d < w) return Offset(rect.left + d, rect.top);
    d -= w;
    if (d < h) return Offset(rect.right, rect.top + d);
    d -= h;
    if (d < w) return Offset(rect.right - d, rect.bottom);
    d -= w;
    return Offset(rect.left, rect.bottom - d);
  }

  void paint(Canvas canvas, double t) {
    if (t < 0 || t > life) return;
    final k = (t / 55).floor();
    final r = math.Random(seed * 7919 + k);
    final per = 2 * (rect.width + rect.height);
    final arcs = [
      for (var n = 0; n < count; n++)
        () {
          final d0 = rnd(r, 0, per), length = rnd(r, 24, 54);
          return [
            for (var s = 0; s <= 8; s++)
              _at(d0 + length * s / 8) + Offset(rnd(r, -3, 3), rnd(r, -3, 3)),
          ];
        }(),
    ];
    final flicker = math.Random(seed * 31 + (t / fxFrame).floor());
    strokeBolt(
      canvas,
      arcs,
      colour,
      1.1,
      (1 - t / life) * rnd(flicker, 0.6, 1),
    );
  }
}

/// The spark palettes of the proposals, from hot to cool.
abstract final class FxPalette {
  static const gold = [
    Color(0xFFFFFFFF),
    Color(0xFFFEF3C7),
    Color(0xFFFDE68A),
    Color(0xFFFBBF24),
    Color(0xFFF59E0B),
    Color(0xFFD97706),
  ];
  static const red = [
    Color(0xFFFFFFFF),
    Color(0xFFFECACA),
    Color(0xFFF87171),
    Color(0xFFEF4444),
    Color(0xFFB91C1C),
  ];
  static const fire = [
    Color(0xFFFFFFFF),
    Color(0xFFFEF08A),
    Color(0xFFFDBA74),
    Color(0xFFF97316),
    Color(0xFFC2410C),
  ];
  static const ink = [Color(0xFFEF4444), Color(0xFFDC2626), Color(0xFFB91C1C)];
}

class _Spark {
  const _Spark(this.origin, this.velocity, this.life, this.width);

  final Offset origin;
  final Offset velocity;
  final double life;
  final double width;
}

/// A burst of sparks (`Sparks`): streaks under drag and gravity, fading and
/// cooling through [colours]. Positions are the closed form of the
/// proposals' per-frame integration.
class Sparks {
  Sparks({
    required int seed,
    required Offset at,
    int count = 30,
    double jitterX = 0,
    double jitterY = 0,
    (double, double) speed = (2, 6),
    (double, double) angle = (0, math.pi * 2),
    (double, double) life = (350, 750),
    (double, double) width = (1, 2.2),
    this.gravity = 0.15,
    this.drag = 0.96,
    this.tail = 2.5,
    this.colours = FxPalette.gold,
    this.additive = true,
  }) {
    final r = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final a = rnd(r, angle.$1, angle.$2), s = rnd(r, speed.$1, speed.$2);
      _sparks.add(
        _Spark(
          at + Offset(rnd(r, -jitterX, jitterX), rnd(r, -jitterY, jitterY)),
          Offset(math.cos(a) * s, math.sin(a) * s),
          rnd(r, life.$1, life.$2),
          rnd(r, width.$1, width.$2),
        ),
      );
    }
  }

  final double gravity;
  final double drag;
  final double tail;
  final List<Color> colours;
  final bool additive;
  final _sparks = <_Spark>[];

  void paint(Canvas canvas, double t) {
    if (t < 0) return;
    final k = -math.log(drag);
    final tau = t / fxFrame;
    final decay = math.exp(-k * tau);
    final terminal = gravity / k;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = additive ? BlendMode.plus : BlendMode.srcOver;
    for (final s in _sparks) {
      if (t > s.life) continue;
      final vx = s.velocity.dx * decay;
      final vy = (s.velocity.dy - terminal) * decay + terminal;
      final x = s.origin.dx + s.velocity.dx * (1 - decay) / k;
      final y =
          s.origin.dy +
          terminal * tau +
          (s.velocity.dy - terminal) * (1 - decay) / k;
      final f = t / s.life;
      paint
        ..color =
            colours[math.min(colours.length - 1, (f * colours.length).floor())]
                .withValues(alpha: (1 - f * f).clamp(0.0, 1.0))
        ..strokeWidth = s.width;
      canvas.drawLine(
        Offset(x - vx * tail, y - vy * tail),
        Offset(x + 0.01, y),
        paint,
      );
    }
  }
}

/// A shock ring (`Ring`) growing from [r0] to [r1] and thinning out.
class Ring {
  const Ring({
    required this.at,
    this.r0 = 0,
    this.r1 = 160,
    this.life = 600,
    this.width = 8,
    this.colour = const Color(0xFFFBBF24),
  });

  final Offset at;
  final double r0;
  final double r1;
  final double life;
  final double width;
  final Color colour;

  void paint(Canvas canvas, double t) {
    final p = t / life;
    if (p < 0 || p >= 1) return;
    final radius = math.max(0.1, r0 + (r1 - r0) * out3(p));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus
      ..color = colour.withValues(alpha: 1 - p)
      ..strokeWidth = math.max(0.5, width * (1 - p * 0.7));
    canvas.drawCircle(
      at,
      radius,
      Paint.from(paint)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawCircle(at, radius, paint);
  }
}

/// A flash (`Flash`): the whole area, or a glow of radius [radius] round
/// [at], fading out as the square of the time left.
class Flash {
  const Flash({
    this.at,
    this.radius = 0,
    this.life = 320,
    this.peak = 0.5,
    this.colour = const Color(0xFFFFF7D6),
  });

  final Offset? at;
  final double radius;
  final double life;
  final double peak;
  final Color colour;

  void paint(Canvas canvas, Size size, double t) {
    final p = t / life;
    if (p < 0 || p >= 1) return;
    final alpha = peak * math.pow(1 - p, 2);
    final paint = Paint();
    if (at == null) {
      paint.color = colour.withValues(alpha: alpha);
    } else {
      paint
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(at!, radius, [
          colour.withValues(alpha: alpha),
          colour.withValues(alpha: 0),
        ]);
    }
    canvas.drawRect(Offset.zero & size, paint);
  }
}

class _Puff {
  const _Puff(this.origin, this.velocity, this.radius, this.life);

  final Offset origin;
  final Offset velocity;
  final double radius;
  final double life;
}

/// Dust puffing out of a rectangle's four edges (`Dust`), under a strong
/// drag, growing and fading.
class Dust {
  Dust({required int seed, required Rect rect, int count = 36}) {
    final r = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final side = r.nextInt(4);
      final (Offset at, Offset normal) = switch (side) {
        0 => (
          Offset(rnd(r, rect.left, rect.right), rect.top),
          const Offset(0, -1),
        ),
        1 => (
          Offset(rect.right, rnd(r, rect.top, rect.bottom)),
          const Offset(1, 0),
        ),
        2 => (
          Offset(rnd(r, rect.left, rect.right), rect.bottom),
          const Offset(0, 1),
        ),
        _ => (
          Offset(rect.left, rnd(r, rect.top, rect.bottom)),
          const Offset(-1, 0),
        ),
      };
      final s = rnd(r, 1.5, 4.5);
      _puffs.add(
        _Puff(
          at,
          normal * s + Offset(rnd(r, -0.8, 0.8), rnd(r, -0.8, 0.8)),
          rnd(r, 5, 10),
          rnd(r, 500, 950),
        ),
      );
    }
  }

  final _puffs = <_Puff>[];
  static const _colour = Color(0xFFE2D4BE);

  void paint(Canvas canvas, double t) {
    if (t < 0) return;
    final k = -math.log(0.9);
    final travel = (1 - math.exp(-k * t / fxFrame)) / k;
    for (final p in _puffs) {
      if (t > p.life) continue;
      final f = t / p.life, radius = p.radius * (1 + f * 1.8);
      final at = p.origin + p.velocity * travel;
      final alpha = (1 - f) * 0.85 * 0.6;
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(at, radius, [
            _colour.withValues(alpha: alpha),
            _colour.withValues(alpha: 0),
          ]),
      );
    }
  }
}

/// The dark veil over the table (`s.dim`), wider than the area so that a
/// shake never uncovers an edge.
void paintDim(Canvas canvas, Size size, double opacity) {
  if (opacity <= 0) return;
  canvas.drawRect(
    (Offset.zero & size).inflate(24),
    Paint()..color = const Color(0xFF020617).withValues(alpha: opacity),
  );
}

/// The veil with holes (`s.spot`): everything but [holes] darkened.
void paintSpot(Canvas canvas, Size size, List<Rect> holes, double darkness) {
  if (darkness <= 0) return;
  canvas.drawPath(
    spotPath(size, holes),
    Paint()..color = const Color(0xFF020617).withValues(alpha: darkness),
  );
}

/// The veil less the union of [holes], each grown by 2 px: two adjacent
/// rows' holes overlap, and must not darken where they do.
Path spotPath(Size size, List<Rect> holes) {
  var cut = Path();
  for (final hole in holes) {
    cut = Path.combine(
      PathOperation.union,
      cut,
      Path()..addRRect(
        RRect.fromRectAndRadius(hole.inflate(2), const Radius.circular(6)),
      ),
    );
  }
  return Path.combine(
    PathOperation.difference,
    Path()..addRect((Offset.zero & size).inflate(24)),
    cut,
  );
}

/// A painter drawing with [draw], every frame.
class FxPainter extends CustomPainter {
  FxPainter(this.draw);

  final void Function(Canvas canvas, Size size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(FxPainter old) => true;
}
