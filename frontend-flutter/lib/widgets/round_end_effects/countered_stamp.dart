import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import 'fx_core.dart';
import 'round_end_phase.dart';

/// A counteracted ZapZap — "Coup de tampon", option B of the proposals
/// (`ctrStamp`, 1.9 s): an ink stamp slams onto the banner from 2.8 times
/// its size, tilted −12°, with who counteracted and on which values; the
/// screen shakes, dust puffs, ink specks fly; then the caller's row flashes
/// red, its round points pop with a "+n" above them, and the stamp lifts.
class CounteredStampPhase extends RoundEndPhase {
  CounteredStampPhase({
    required this.title,
    required this.line,
    required this.textDirection,
    this.textStyle = const TextStyle(),
    required this.callerIndex,
    required this.callerPreviousTotal,
    required this.callerTotal,
    required this.penaltyLabel,
    required this.countsCallerTotal,
  });

  static const animationKey = Key('zapzapCounteredAnimation');

  /// "CONTRÉ", and "par X · a ≤ b" under it when the values are known.
  final String title;
  final String? line;
  final TextDirection textDirection;

  /// The round end's text style, whose font the stamp is lettered in.
  final TextStyle textStyle;

  final int? callerIndex;
  final int callerPreviousTotal;
  final int callerTotal;

  /// "+n", the caller's points this round, above their round column.
  final String penaltyLabel;

  /// The stamp counts the caller's total up, unless the round put the
  /// caller out: the gauge does it then.
  final bool countsCallerTotal;

  @override
  Key get key => animationKey;

  @override
  double get nominal => 1920;

  @override
  double get length => 2020;

  @override
  Set<int> get rows => {?callerIndex};

  @override
  Set<int> get totals => countsCallerTotal ? {?callerIndex} : const {};

  static const _tilt = -12 * math.pi / 180;
  static const _hit = 620.0;

  final _screenShake = Shake(201, 9, 420, delay: 300);
  final _rowShake = Shake(203, 4, 320, delay: _hit);

  Rect? _box;
  Rect? _roundCell;
  late Dust _dust;
  late Sparks _ink;
  Sparks? _hitSparks;

  @override
  bool get ready => _box != null;

  @override
  bool measure(FxMeasure measure) {
    final banner = measure.rect(measure.keys.banner);
    if (banner == null) return true;
    final w = math.min(230.0, banner.width * 0.92), h = w * 96 / 220;
    final box = Rect.fromCenter(
      center: banner.center + const Offset(0, 4),
      width: w,
      height: h,
    );
    _box = box;
    _dust = Dust(seed: 211, rect: box, count: 46);
    _ink = Sparks(
      seed: 213,
      at: box.center,
      count: 16,
      jitterX: w * 0.45,
      jitterY: h * 0.4,
      speed: (1.5, 4),
      gravity: 0.22,
      width: (1.8, 3.2),
      tail: 0.25,
      colours: FxPalette.ink,
      additive: false,
      life: (300, 600),
    );
    if (callerIndex != null) {
      _roundCell = measure.rect(measure.keys.roundCell(callerIndex!));
      if (_roundCell != null) {
        _hitSparks = Sparks(
          seed: 217,
          at: _roundCell!.center,
          count: 22,
          speed: (1, 3.5),
          colours: FxPalette.red,
          gravity: 0.1,
        );
      }
    }
    return true;
  }

  @override
  Offset shake(double t) => _screenShake.offset(t);

  @override
  double tilt(double t) => _screenShake.angle(t);

  @override
  void banner(double t, BannerLook look) {
    if (!running(t, 300, 320)) return;
    look.scaleY *= kf(
      t,
      300,
      320,
      const [1, 0.93, 1.02, 1],
      offsets: const [0, 0.3, 0.7, 1],
    );
  }

  @override
  void row(int playerIndex, double t, RowLook look) {
    if (playerIndex != callerIndex) return;
    look
      ..shake += _rowShake.offset(t)
      ..tilt += _rowShake.angle(t);
    if (running(t, _hit, 650)) {
      look.flash = math.max(
        look.flash,
        1 - FxCurves.easeOut.transform((t - _hit) / 650),
      );
    }
    if (running(t, _hit, 520)) {
      final ease = FxCurves.easeOut.transform;
      const offsets = [0.0, 0.3, 1.0];
      look
        ..roundScale *= kf(
          t,
          _hit,
          520,
          const [1, 1.9, 1],
          offsets: offsets,
          ease: ease,
        )
        ..roundRed = math.max(
          look.roundRed,
          kf(t, _hit, 520, const [0, 1, 0], offsets: offsets, ease: ease),
        );
    }
  }

  @override
  int total(int playerIndex, double t) => kf(t, _hit, 480, [
    callerPreviousTotal.toDouble(),
    callerTotal.toDouble(),
  ], ease: out3).round();

  @override
  Widget overlay(double t, Widget Function(Widget layer) shaken) {
    final box = _box!;
    return Stack(
      key: animationKey,
      fit: StackFit.expand,
      children: [
        shaken(
          Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: FxPainter(
                  (canvas, size) => paintDim(
                    canvas,
                    size,
                    0.35 * fadeInOut(t, from: 0, until: 1700),
                  ),
                ),
              ),
              if (t < 550) _shadow(t, box),
              _stamp(t, box),
              if (_roundCell != null && running(t, _hit, 1000))
                _float(t, _roundCell!),
            ],
          ),
        ),
        CustomPaint(
          painter: FxPainter((canvas, size) {
            _dust.paint(canvas, t - 300);
            _ink.paint(canvas, t - 300);
            _hitSparks?.paint(canvas, t - _hit);
          }),
        ),
      ],
    );
  }

  /// The blurred shadow the stamp casts as it falls.
  Widget _shadow(double t, Rect box) {
    final opacity = t < 300
        ? kf(t, 0, 300, const [0, 0.8], ease: FxCurves.slam.transform)
        : kf(t, 300, 250, const [0.8, 0]);
    final scale = kf(t, 0, 300, const [1.5, 1], ease: FxCurves.slam.transform);
    return Positioned.fromRect(
      rect: box,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationZ(_tilt)
            ..scaleByDouble(scale, scale, 1, 1),
          child: CustomPaint(
            painter: FxPainter(
              (canvas, size) => canvas.drawRRect(
                RRect.fromRectAndRadius(
                  Offset.zero & size,
                  const Radius.circular(14),
                ),
                Paint()
                  ..color = const Color(0x8C000000)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The stamp: the slam, a bounce as it lands, the lift at the end.
  Widget _stamp(double t, Rect box) {
    var opacity = 1.0, dy = 0.0, tilt = _tilt, scale = 1.0;
    if (t < 300) {
      final slam = FxCurves.slam.transform;
      const offsets = [0.0, 0.25, 1.0];
      opacity = kf(t, 0, 300, const [0, 1, 1], offsets: offsets, ease: slam);
      dy = kf(t, 0, 300, const [-34, -26, 0], offsets: offsets, ease: slam);
      scale = kf(t, 0, 300, const [2.8, 2.4, 1], offsets: offsets, ease: slam);
    } else if (t < 560) {
      scale = kf(
        t,
        300,
        260,
        const [1, 1.06, 1],
        offsets: const [0, 0.35, 1],
        ease: FxCurves.easeOut.transform,
      );
    } else if (t >= 1560) {
      final lift = FxCurves.easeIn.transform;
      opacity = kf(t, 1560, 360, const [1, 0], ease: lift);
      dy = kf(t, 1560, 360, const [0, -14], ease: lift);
      tilt = kf(t, 1560, 360, const [-12, -10], ease: lift) * math.pi / 180;
      scale = kf(t, 1560, 360, const [1, 1.08], ease: lift);
    }
    return Positioned.fromRect(
      rect: box,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, dy, 0)
            ..rotateZ(tilt)
            ..scaleByDouble(scale, scale, 1, 1),
          child: CustomPaint(
            painter: _StampPainter(title, line, textDirection, textStyle),
          ),
        ),
      ),
    );
  }

  /// "+n" rising over the caller's round column.
  Widget _float(double t, Rect cell) {
    final ease = FxCurves.easeOut.transform;
    const offsets = [0.0, 0.3, 0.75, 1.0];
    double at(List<double> values) =>
        kf(t, _hit, 1000, values, offsets: offsets, ease: ease);
    final scale = at(const [0.4, 1.15, 1, 0.9]);
    return Positioned(
      left: cell.center.dx - 40,
      top: cell.top - 32,
      width: 80,
      child: Opacity(
        opacity: at(const [0, 1, 1, 0]).clamp(0.0, 1.0),
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, at(const [22, -4, 0, -10]), 0)
            ..scaleByDouble(scale, scale, 1, 1),
          child: Text(
            penaltyLabel,
            textAlign: TextAlign.center,
            textScaler: TextScaler.noScaling,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w800,
              color: AppColors.error,
              shadows: [
                Shadow(color: Color(0xFF450A0A), offset: Offset(0, 2)),
                Shadow(color: Color(0xB3EF4444), blurRadius: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The stamp's face (`stampSVG`), drawn on a 220 × 96 grid: a thick and a
/// thin rounded frame, the word, the line under it, and worn ink — specks
/// of the page showing through.
class _StampPainter extends CustomPainter {
  _StampPainter(this.title, this.line, this.textDirection, this.base);

  final String title;
  final String? line;
  final TextDirection textDirection;
  final TextStyle base;

  static const _ink = AppColors.error;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.scale(size.width / 220, size.height / 96);
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..color = _ink;
    final outer = RRect.fromLTRBR(5, 5, 215, 91, const Radius.circular(12));
    canvas
      ..drawRRect(outer, Paint()..color = _ink.withValues(alpha: 0.1))
      ..drawRRect(outer, frame..strokeWidth = 6)
      ..drawRRect(
        RRect.fromLTRBR(14, 14, 206, 82, const Radius.circular(7)),
        frame..strokeWidth = 1.8,
      );
    _text(
      canvas,
      title,
      const TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        letterSpacing: 3,
      ),
      baseline: line == null ? 62 : 58,
    );
    if (line != null) {
      _text(
        canvas,
        line!,
        const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
        ),
        baseline: 75,
      );
    }
    // The worn ink: the fractal-noise mask of the SVG, as seeded specks.
    final r = math.Random(29);
    final hole = Paint()..blendMode = BlendMode.dstOut;
    for (var i = 0; i < 260; i++) {
      hole.color = Color.fromRGBO(0, 0, 0, rnd(r, 0.35, 1));
      canvas.drawCircle(
        Offset(rnd(r, 4, 216), rnd(r, 4, 92)),
        rnd(r, 0.3, 1.2),
        hole,
      );
    }
    for (var i = 0; i < 16; i++) {
      hole.color = Color.fromRGBO(0, 0, 0, rnd(r, 0.12, 0.35));
      canvas.drawCircle(
        Offset(rnd(r, 4, 216), rnd(r, 4, 92)),
        rnd(r, 1.5, 3.5),
        hole,
      );
    }
    canvas.restore();
  }

  /// [text] centred on x = 110, its baseline at [baseline], shrunk to fit
  /// inside the thin frame.
  void _text(
    Canvas canvas,
    String text,
    TextStyle style, {
    required double baseline,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: base.merge(style).copyWith(color: _ink, height: 1),
      ),
      textDirection: textDirection,
      maxLines: 1,
    )..layout();
    final fit = math.min(1.0, 184 / painter.width);
    final ascent = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    canvas
      ..save()
      ..translate(110 - painter.width * fit / 2, baseline - ascent * fit)
      ..scale(fit);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
    painter.dispose();
  }

  @override
  bool shouldRepaint(_StampPainter old) =>
      old.title != title || old.line != line;
}
