import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// What the game felt shows under its cards, painted — no image asset: a
/// fine texture of fibres, the shadow the rim casts on the felt, and the
/// ZapZap mark faintly at the centre. The felt's radial gradient and its
/// edge are the decoration of the box this paints in.
class FeltPainter extends CustomPainter {
  const FeltPainter({required this.watermark, required this.radius});

  /// The text printed under the bolt, the application's name.
  final String watermark;

  /// The corner radius of the felt's inner edge: the texture stays in it.
  final double radius;

  /// The fibres per square logical pixel of felt.
  static const fleckDensity = 1 / 40;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final area = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(area, Radius.circular(radius));
    canvas.save();
    canvas.clipRRect(shape);
    _paintTexture(canvas, size);
    _paintWatermark(canvas, size);
    _paintInnerShadow(canvas, shape);
    canvas.restore();
  }

  /// Short strokes, lighter and darker than the felt, at places a fixed
  /// seed picks: the same felt on every frame.
  void _paintTexture(Canvas canvas, Size size) {
    final random = Random(7);
    final count = (size.width * size.height * fleckDensity).round();
    final light = Float32List(count * 4);
    final dark = Float32List(count * 4);
    for (var i = 0; i < count; i++) {
      final target = i.isEven ? light : dark;
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final angle = random.nextDouble() * pi;
      final length = 1 + random.nextDouble() * 2;
      final j = (i ~/ 2) * 4;
      target[j] = x;
      target[j + 1] = y;
      target[j + 2] = x + cos(angle) * length;
      target[j + 3] = y + sin(angle) * length;
    }
    final stroke = Paint()
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round;
    final used = (count + 1) ~/ 2 * 4;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(light, 0, used),
      stroke..color = AppColors.feltFleckLight,
    );
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.sublistView(dark, 0, count ~/ 2 * 4),
      stroke..color = AppColors.feltFleckDark,
    );
  }

  /// A bolt over the name, as the app's logo, sized to the felt.
  void _paintWatermark(Canvas canvas, Size size) {
    final side = min(size.width, size.height);
    final iconSize = (side * 0.35).clamp(24.0, 120.0);
    final bolt = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.bolt.codePoint),
        style: TextStyle(
          fontFamily: Icons.bolt.fontFamily,
          package: Icons.bolt.fontPackage,
          fontSize: iconSize,
          color: AppColors.feltWatermark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final name = TextPainter(
      text: TextSpan(
        text: watermark,
        style: TextStyle(
          fontSize: iconSize * 0.4,
          fontWeight: FontWeight.bold,
          letterSpacing: iconSize * 0.04,
          color: AppColors.feltWatermark,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = (size.height - bolt.height - name.height) / 2;
    bolt.paint(canvas, Offset((size.width - bolt.width) / 2, top));
    name.paint(
      canvas,
      Offset((size.width - name.width) / 2, top + bolt.height),
    );
    bolt.dispose();
    name.dispose();
  }

  /// The rim's shadow falling on the felt: a blurred dark band along the
  /// inside of the edge.
  void _paintInnerShadow(Canvas canvas, RRect shape) {
    canvas.drawRRect(
      shape.inflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = const Color(0x8C000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  @override
  bool shouldRepaint(FeltPainter oldDelegate) =>
      oldDelegate.watermark != watermark || oldDelegate.radius != radius;
}
