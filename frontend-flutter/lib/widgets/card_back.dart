import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'playing_card.dart';

/// The sizes of `frontend/src/components/Game/CardBack.jsx`, by width.
enum CardBackSize {
  xxs(16),
  xs(24),
  sm(40),
  md(60),
  lg(80);

  const CardBackSize(this.width);

  final double width;
}

/// A face-down card: a red lattice in a white border, painted rather than
/// drawn from an asset (the React client takes the cardmeister back). Its
/// width is [size]'s, or [width] when given — the deck matches the felt's
/// face-up cards so.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.size = CardBackSize.md, this.width});

  final CardBackSize size;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final width = this.width ?? size.width;
    return Semantics(
      label: AppLocalizations.of(context).cardBack,
      child: SizedBox(
        width: width,
        height: PlayingCard.heightFor(width),
        child: CustomPaint(
          painter: _CardBackPainter(PlayingCard.radiusFor(width)),
        ),
      ),
    );
  }
}

class _CardBackPainter extends CustomPainter {
  _CardBackPainter(this.radius);

  final double radius;

  static const _red = Color(0xFFB91C1C);
  static const _lattice = Color(0xFFEF4444);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.drawRRect(outer, Paint()..color = Colors.white);

    final inset = (size.width * 0.07).clamp(1.0, 6.0);
    final inner = outer.deflate(inset);
    canvas.drawRRect(inner, Paint()..color = _red);

    canvas.save();
    canvas.clipRRect(inner);
    final line = Paint()
      ..color = _lattice
      ..strokeWidth = (size.width / 60).clamp(0.5, 1.5);
    final step = (size.width / 6).clamp(3.0, 12.0);
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardBackPainter oldDelegate) =>
      oldDelegate.radius != radius;
}
