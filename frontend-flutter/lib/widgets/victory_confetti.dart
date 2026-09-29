import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// The winner's celebration on the game-over screen: two cannons fire from
/// the bottom corners, ~110 pieces tumble under gravity and fade out.
/// Played once, [duration] long, paints nothing afterwards and takes no
/// pointer event. Pure Flutter: an [AnimationController] and a painter.
class VictoryConfetti extends StatefulWidget {
  const VictoryConfetti({super.key, this.pieces = 110, this.seed = 7});

  final int pieces;
  final int seed;

  static const duration = Duration(milliseconds: 2400);

  @override
  State<VictoryConfetti> createState() => _VictoryConfettiState();
}

class _VictoryConfettiState extends State<VictoryConfetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: VictoryConfetti.duration,
  )..forward();
  late final List<_Piece> _pieces = _makePieces(widget.pieces, widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        painter: _ConfettiPainter(_pieces, _controller),
        size: Size.infinite,
      ),
    ),
  );
}

/// The banner "pops": scales in from small with a small overshoot.
class VictoryPop extends StatelessWidget {
  const VictoryPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.6, end: 1),
    duration: const Duration(milliseconds: 600),
    curve: Curves.easeOutBack,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: child,
  );
}

class _Piece {
  const _Piece({
    required this.fromRight,
    required this.angle,
    required this.speed,
    required this.spin,
    required this.colour,
    required this.width,
    required this.height,
  });

  final bool fromRight;

  /// Launch angle from the horizontal, towards the centre of the screen.
  final double angle;
  final double speed;
  final double spin;
  final Color colour;
  final double width;
  final double height;
}

const _palette = [
  AppColors.amber400,
  AppColors.amber200,
  Colors.white,
  Color(0xFF4ADE80),
  AppColors.amber600,
];

List<_Piece> _makePieces(int count, int seed) {
  final random = math.Random(seed);
  return List.generate(
    count,
    (i) => _Piece(
      fromRight: i.isOdd,
      angle: math.pi * (0.28 + 0.27 * random.nextDouble()),
      speed: 0.7 + 0.6 * random.nextDouble(),
      spin: (random.nextDouble() - 0.5) * 24,
      colour: _palette[random.nextInt(_palette.length)],
      width: 5 + 5 * random.nextDouble(),
      height: 8 + 6 * random.nextDouble(),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.animation) : super(repaint: animation);

  final List<_Piece> pieces;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t >= 1) return;
    // Seconds of flight, and the fade over the last 35 %.
    final seconds = t * VictoryConfetti.duration.inMilliseconds / 1000;
    final fade = t < 0.65 ? 1.0 : (1 - t) / 0.35;
    final reach = size.height * 1.1;
    final gravity = size.height * 1.6;
    final paint = Paint();
    for (final p in pieces) {
      final direction = p.fromRight ? -1.0 : 1.0;
      final vx = math.cos(p.angle) * p.speed * reach * direction * 0.9;
      final vy = -math.sin(p.angle) * p.speed * reach * 1.5;
      final x = (p.fromRight ? size.width : 0) + vx * seconds;
      final y = size.height + vy * seconds + 0.5 * gravity * seconds * seconds;
      if (y > size.height + 20) continue;
      paint.color = p.colour.withValues(alpha: fade.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * seconds);
      // Tumbling: the piece flips edge-on as it turns.
      canvas.scale(1, math.cos(p.spin * seconds * 0.7).abs().clamp(0.15, 1));
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.width, height: p.height),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
