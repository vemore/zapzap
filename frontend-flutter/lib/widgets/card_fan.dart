import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'playing_card.dart';

/// A hand in an arc — the port of `frontend/src/components/Game/CardFan.jsx`,
/// with its parameters: each card pivots on its bottom centre, the spread
/// grows with the number of cards up to [maxSpreadAngle], and a selected card
/// is lifted and drawn on top. Under 640 px of screen width (mobile) cards are
/// [mobileCardWidth] wide, the spread is at most 50° and the fan 100 px high.
class CardFan extends StatelessWidget {
  const CardFan({
    super.key,
    required this.cards,
    this.selectedCards = const {},
    this.onCardTap,
    this.disabled = false,
    this.cardWidth = 70,
    this.mobileCardWidth = 50,
    this.maxSpreadAngle = 75,
  });

  final List<int> cards;
  final Set<int> selectedCards;
  final ValueChanged<int>? onCardTap;
  final bool disabled;
  final double cardWidth;
  final double mobileCardWidth;

  /// In degrees.
  final double maxSpreadAngle;

  static const mobileBreakpoint = 640.0;

  /// The key of the card at [index], for tests and the game board.
  static Key itemKey(int index) => ValueKey('cardFanItem-$index');

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final mobile = MediaQuery.sizeOf(context).width < mobileBreakpoint;
    final count = cards.length;
    final width = mobile ? mobileCardWidth : cardWidth;
    final maxAngle = mobile ? math.min(maxSpreadAngle, 50.0) : maxSpreadAngle;
    final spread = math.min(maxAngle, count * (mobile ? 8.0 : 12.0));
    final step = count > 1 ? spread / (count - 1) : 0.0;
    final spacing = math.max(
      mobile ? 18.0 : 25.0,
      (mobile ? 30.0 : 50.0) - count * (mobile ? 3.0 : 4.0),
    );
    final lift = mobile ? -15.0 : -25.0;
    final centre = (count - 1) / 2;

    final items = <(bool, Widget)>[];
    for (var i = 0; i < count; i++) {
      final id = cards[i];
      final selected = selectedCards.contains(id);
      final degrees = -spread / 2 + i * step;
      final transform = Matrix4.translationValues((i - centre) * spacing, 0, 0)
        ..rotateZ(degrees * math.pi / 180)
        ..translateByDouble(0, selected ? lift : 0, 0, 1);
      items.add((
        selected,
        Transform(
          key: itemKey(i),
          alignment: Alignment.bottomCenter,
          transform: transform,
          child: PlayingCard(
            cardId: id,
            selected: selected,
            disabled: disabled,
            width: width,
            onTap: onCardTap == null ? null : () => onCardTap!(id),
          ),
        ),
      ));
    }

    // Selected cards paint (and hit-test) above the others, as `zIndex: 100`.
    return SizedBox(
      width: double.infinity,
      height: mobile ? 100 : 150,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          for (final (selected, item) in items)
            if (!selected) item,
          for (final (selected, item) in items)
            if (selected) item,
        ],
      ),
    );
  }
}
