import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/motion.dart';

/// A card face, from the SVGs under `assets/cards/` — the port of
/// `frontend/src/components/Game/PlayingCard.jsx`.
///
/// Height is `width × 1.4`. A face always keeps its colours; what can be
/// done with it shows on its edge, in three looks ([CardLook]): a card that
/// cannot be played is plain, one that can takes a light amber edge and a
/// soft glow, and a selected one a thicker amber edge and a stronger glow.
/// A disabled card ignores taps. A screen reader activates it as a tap does.
class PlayingCard extends StatelessWidget {
  const PlayingCard({
    super.key,
    required this.cardId,
    this.selected = false,
    this.disabled = false,
    this.onTap,
    this.width = 80,
  });

  final int cardId;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;
  final double width;

  /// The look of this card: selected, else playable when it takes a tap.
  CardLook get look => selected
      ? CardLook.selected
      : (!disabled && onTap != null ? CardLook.playable : CardLook.plain);

  /// The standard playing-card ratio of the React client.
  static const aspectRatio = 1.4;

  static double heightFor(double width) =>
      (width * aspectRatio).roundToDouble();

  /// About 5 % of the width, at least 2 px.
  static double radiusFor(double width) =>
      math.max(2, (width * 0.05).round()).toDouble();

  /// The edge of a card in [look], drawn in front of the face so it does
  /// not shrink it; none on a plain card. Also the deck's (`GameTableArea`).
  static BoxDecoration? edgeFor(CardLook look, BorderRadius radius) =>
      switch (look) {
        CardLook.plain => null,
        CardLook.playable => BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: AppColors.amber200,
            width: CardSizes.playableBorder,
          ),
        ),
        CardLook.selected => BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: AppColors.amber400,
            width: CardSizes.selectedBorder,
          ),
        ),
      };

  /// The shadow of a card in [look]: a plain drop shadow, a soft amber glow
  /// when playable, a strong one when selected.
  static List<BoxShadow> shadowFor(CardLook look) => switch (look) {
    CardLook.plain => [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
    CardLook.playable => [
      BoxShadow(
        color: AppColors.amber200.withValues(alpha: 0.45),
        blurRadius: 6,
        spreadRadius: 1,
      ),
    ],
    CardLook.selected => [
      BoxShadow(
        color: AppColors.amber400.withValues(alpha: 0.85),
        blurRadius: 14,
        spreadRadius: 3,
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final card = GameCard(cardId);
    final height = heightFor(width);
    final radius = BorderRadius.circular(radiusFor(width));
    final look = this.look;

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
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.select),
          width: width,
          height: height,
          foregroundDecoration: edgeFor(look, radius),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: radius,
            boxShadow: shadowFor(look),
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
    );
  }
}

/// How a card shows what can be done with it ([PlayingCard]).
enum CardLook {
  /// Cannot be played now: the plain card.
  plain,

  /// Can be played, taken or drawn: a light amber edge and a soft glow.
  playable,

  /// Picked for the move: a thick amber edge and a strong glow.
  selected,
}
