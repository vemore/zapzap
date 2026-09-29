import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'fx_core.dart';
import 'round_end_phase.dart';

/// A ZapZap that held — "Coup de foudre", option A of the proposals
/// (`heldBolt`, 1.7 s): a bolt strikes the banner's icon; a flash, a shake,
/// sparks and a ring at the impact; "ZAPZAP !" drops in letter by letter
/// over the table, then shrinks into the banner while arcs crawl along its
/// border.
class HeldBoltPhase extends RoundEndPhase {
  HeldBoltPhase({required this.word, this.textDirection = TextDirection.ltr});

  static const animationKey = Key('zapzapHeldAnimation');

  /// "ZAPZAP !", in the player's language.
  final String word;

  /// The bolt comes in from the side the banner's icon faces.
  final TextDirection textDirection;

  /// Where the bolt starts: above [target], 40 to 80 px towards the middle
  /// of the area (right of the icon, or left of it right to left), and
  /// never outside the [width].
  static Offset boltOrigin(
    Offset target,
    double width,
    TextDirection direction,
  ) {
    final side = direction == TextDirection.rtl ? -1 : 1;
    final dx = target.dx + side * rnd(math.Random(7), 40, 80);
    return Offset(dx.clamp(8, math.max(8, width - 8)).toDouble(), -8);
  }

  @override
  double get nominal => 1700;

  @override
  double get length => 2400;

  final _shake = Shake(101, 5, 360, delay: 170);
  static const _flash = Flash(life: 420, peak: 0.55);

  Rect? _banner;
  late Offset _target;
  late double _wordY;
  late Size _size;
  late Lightning _bolt;
  late Sparks _impact;
  late Sparks _settle;
  late Ring _ring;
  late ArcCrawl _arcs;

  @override
  bool get ready => _banner != null;

  @override
  bool measure(FxMeasure measure) {
    final banner = measure.rect(measure.keys.banner);
    final icon = measure.rect(measure.keys.bannerIcon);
    final table = measure.rect(measure.keys.table);
    if (banner == null || icon == null || table == null) return true;
    _banner = banner;
    _size = measure.size;
    _target = icon.center + const Offset(1, 0);
    final from = boltOrigin(_target, measure.size.width, textDirection);
    _wordY = table.top + 70;
    _bolt = Lightning(
      seed: 11,
      from: (_) => from,
      to: (t) => Offset.lerp(from, _target, math.min(1, t / 90))!,
      width: (t) => t < 90 ? 1 : 2.6,
      life: 560,
      hold: 260,
      regen: 42,
      branches: 3,
    );
    _impact = Sparks(
      seed: 13,
      at: _target,
      count: 50,
      speed: (2, 7.5),
      gravity: 0.14,
    );
    _ring = Ring(at: _target, r1: 190, life: 700, width: 7);
    _arcs = ArcCrawl(seed: 17, rect: banner, life: 1150);
    _settle = Sparks(
      seed: 19,
      at: banner.center,
      count: 24,
      speed: (1, 3.5),
      gravity: 0.05,
      jitterX: banner.width * 0.35,
      jitterY: 8,
    );
    return true;
  }

  @override
  Offset shake(double t) => _shake.offset(t);

  @override
  double tilt(double t) => _shake.angle(t);

  @override
  void banner(double t, BannerLook look) {
    // Charged from the strike to the last sparks, through a 300 ms
    // transition each way.
    final glow = t < 170
        ? 0.0
        : t < 1650
        ? Curves.ease.transform(((t - 170) / 300).clamp(0.0, 1.0))
        : 1 - Curves.ease.transform(((t - 1650) / 300).clamp(0.0, 1.0));
    look.glow = math.max(look.glow, glow);
    final pulse = kf(
      t,
      170,
      520,
      const [1, 1.05, 1],
      offsets: const [0, 0.3, 1],
      ease: FxCurves.easeOut.transform,
    );
    look
      ..scaleX *= pulse
      ..scaleY *= pulse;
  }

  @override
  Widget overlay(double t, Widget Function(Widget layer) shaken) {
    final banner = _banner!;
    return Stack(
      key: animationKey,
      fit: StackFit.expand,
      children: [
        shaken(
          Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: FxPainter((canvas, size) {
                  paintDim(
                    canvas,
                    size,
                    0.5 * fadeInOut(t, from: 0, until: 1500),
                  );
                }),
              ),
              if (t >= 260) _word(t, banner),
            ],
          ),
        ),
        CustomPaint(
          painter: FxPainter((canvas, size) {
            _bolt.paint(canvas, t - 80);
            _flash.paint(canvas, size, t - 170);
            _impact.paint(canvas, t - 170);
            _ring.paint(canvas, t - 170);
            _arcs.paint(canvas, t - 260);
            _settle.paint(canvas, t - 1650);
          }),
        ),
      ],
    );
  }

  /// The word over the table, then drawn into the banner (`absorb`).
  Widget _word(double t, Rect banner) {
    final letters = word.characters.toList();
    final p = t - 1330;
    final absorbed = kf(p, 0, 360, const [
      0,
      1,
    ], ease: FxCurves.absorb.transform);
    final into = Offset(
      banner.center.dx - _size.width / 2,
      banner.center.dy - _wordY,
    );
    return Positioned(
      key: const ValueKey('word'),
      left: 0,
      right: 0,
      top: _wordY,
      child: FractionalTranslation(
        translation: const Offset(0, -0.5),
        child: Opacity(
          opacity: (1 - absorbed).clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..translateByDouble(into.dx * absorbed, into.dy * absorbed, 0, 1)
              ..scaleByDouble(1 - 0.8 * absorbed, 1 - 0.8 * absorbed, 1, 1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  // A word of Latin letters, dropped in left to right in
                  // every language: an Arabic row would read "!PAZPAZ".
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < letters.length; i++)
                      _letter(letters[i], t - 260 - i * 45),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _gold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFFBEB),
      Color(0xFFFDE68A),
      Color(0xFFFBBF24),
      Color(0xFFD97706),
    ],
    stops: [0, 0.38, 0.62, 1],
  );

  static const _style = TextStyle(
    fontSize: 46,
    height: 1,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.46,
  );

  /// One letter dropping in: from above, 2.2 times its size and blurred.
  Widget _letter(String letter, double t) {
    double at(double from, double to) =>
        kf(t, 0, 420, [from, to], ease: FxCurves.pop.transform);
    final blur = at(6, 0).clamp(0.0, 6.0);
    final text = letter == ' ' ? ' ' : letter;
    Widget glyph = Stack(
      children: [
        Transform.translate(
          offset: const Offset(0, 3),
          child: Text(
            text,
            textScaler: TextScaler.noScaling,
            style: _style.copyWith(
              color: const Color(0xFF92400E),
              shadows: const [Shadow(color: Color(0xA6FBBF24), blurRadius: 16)],
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: _gold.createShader,
          child: Text(
            text,
            textScaler: TextScaler.noScaling,
            style: _style.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
    if (blur > 0.05) {
      glyph = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: glyph,
      );
    }
    final scale = at(2.2, 1);
    return Opacity(
      opacity: at(0, 1).clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translateByDouble(0, at(-18, 0), 0, 1)
          ..scaleByDouble(scale, scale, 1, 1),
        child: glyph,
      ),
    );
  }
}
