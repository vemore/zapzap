import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';

/// A card face, from the SVGs under `assets/cards/` — the port of
/// `frontend/src/components/Game/PlayingCard.jsx`.
///
/// Height is `width × 1.4`; a selected card takes an amber edge and glows
/// amber, a disabled one is half transparent and ignores taps. A screen
/// reader activates it as a tap does.
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.cardId,
    this.selected = false,
    this.disabled = false,
    this.onTap,
    this.width = 80,
    this.dimmed,
  });

  final int cardId;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final double width;

  /// Half transparent; by default when [disabled]. A hand only read, whose
  /// cards overlap, stays opaque: the cards under would show through.
  final bool? dimmed;

  /// The standard playing-card ratio of the React client.
  static const aspectRatio = 1.4;

  static double heightFor(double width) =>
      (width * aspectRatio).roundToDouble();

  /// About 5 % of the width, at least 2 px.
  static double radiusFor(double width) =>
      math.max(2, (width * 0.05).round()).toDouble();

  @override
  Widget build(BuildContext context) {
    final card = GameCard(cardId);
    final height = heightFor(width);
    final radius = BorderRadius.circular(radiusFor(width));

    final tap = disabled ? null : onTap;
    return Semantics(
      button: true,
      enabled: !disabled,
      selected: selected,
      label: AppLocalizations.of(context).cardName(card),
      onTap: tap,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: tap,
        child: Opacity(
          opacity: (dimmed ?? disabled) ? 0.5 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: width,
            height: height,
            // In front of the face, so the edge does not shrink it.
            foregroundDecoration: selected
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: AppColors.amber400,
                      width: CardSizes.selectedBorder,
                    ),
                  )
                : null,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
              boxShadow: [
                if (selected)
                  BoxShadow(
                    color: AppColors.amber400.withValues(alpha: 0.7),
                    blurRadius: 12,
                    spreadRadius: 2,
                  )
                else
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: SvgPicture.asset(
                card.assetPath,
                width: width,
                height: height,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
