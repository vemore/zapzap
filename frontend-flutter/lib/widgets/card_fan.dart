import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'playing_card.dart';

/// The player's hand: cards overlapping left to right, each one leaving at
/// least [CardSizes.handMinVisible] of the one under it uncovered, on one row
/// or, when the width cannot hold that, on two or more — each row drawn over
/// the top of the one above, which keeps its ranks in view.
///
/// It replaces the arc of `frontend/src/components/Game/CardFan.jsx`, whose
/// 50 px cards left 18 px of each to tap on a phone. Cards are a quarter of
/// the width wide, from [CardSizes.handMin] to [CardSizes.handMax]; a row
/// bows down a few pixels at its ends, and a selected card rises by
/// [CardSizes.selectedLift] without leaving its place in the order, so the
/// cards beside it stay as easy to tap.
class CardFan extends StatelessWidget {
  const CardFan({
    super.key,
    required this.cards,
    this.selectedCards = const {},
    this.onCardTap,
    this.disabled = false,
  });

  final List<int> cards;
  final Set<int> selectedCards;
  final ValueChanged<int>? onCardTap;
  final bool disabled;

  /// How much of a card's height the row below leaves uncovered.
  static const rowReveal = 0.5;

  /// How far below its centre a row's end cards sit.
  static const bow = 4.0;

  /// The key of the card at [index], for tests and the game board.
  static Key itemKey(int index) => ValueKey('cardFanItem-$index');

  /// Where each card lies, for a hand of [count] cards [width] wide.
  static FanLayout layoutFor(int count, double width) =>
      FanLayout._(count, width);

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final fan = layoutFor(cards.length, constraints.maxWidth);
        return SizedBox(
          width: fan.width,
          height: fan.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < cards.length; i++)
                _card(fan, i, selectedCards.contains(cards[i])),
            ],
          ),
        );
      },
    );
  }

  Widget _card(FanLayout fan, int index, bool selected) {
    final id = cards[index];
    final rest = fan.cardRect(index);
    return Positioned(
      key: itemKey(index),
      left: rest.left,
      top: rest.top - (selected ? CardSizes.selectedLift : 0),
      child: PlayingCard(
        cardId: id,
        selected: selected,
        disabled: disabled,
        width: fan.cardWidth,
        onTap: onCardTap == null ? null : () => onCardTap!(id),
      ),
    );
  }
}

/// The geometry of a [CardFan]: the card size, the rows, and each card's
/// rect at rest, in the fan's own coordinates.
class FanLayout {
  FanLayout._(this.count, double available)
    : width = available.isFinite ? available : 4 * CardSizes.handMax,
      cardWidth = (available.isFinite ? available / 4 : CardSizes.handMax)
          .clamp(CardSizes.handMin, CardSizes.handMax) {
    final perRow = math.max(
      1,
      ((width - cardWidth) / CardSizes.handMinVisible).floor() + 1,
    );
    final rows = (count / perRow).ceil();
    // Balanced rows, the longer ones first: 7 cards on two is 4 + 3, not
    // 6 + 1.
    rowLengths = [
      for (var r = 0; r < rows; r++) count ~/ rows + (r < count % rows ? 1 : 0),
    ];
    final longest = rowLengths.first;
    step = longest < 2
        ? 0
        : math.min(cardWidth * 0.75, (width - cardWidth) / (longest - 1));
  }

  final int count;

  /// The width the fan takes: all of what it is given.
  final double width;
  final double cardWidth;

  /// How many cards each row holds, top row first.
  late final List<int> rowLengths;

  /// From the left edge of a card to the left edge of the next.
  late final double step;

  double get cardHeight => PlayingCard.heightFor(cardWidth);

  /// From the top of a row to the top of the next.
  double get rowStep => (cardHeight * CardFan.rowReveal).roundToDouble();

  int get rows => rowLengths.length;

  double get height =>
      CardSizes.selectedLift + cardHeight + (rows - 1) * rowStep + CardFan.bow;

  /// The row of card [index] and its place in that row.
  (int row, int column) position(int index) {
    var start = 0;
    for (var r = 0; r < rows; r++) {
      if (index < start + rowLengths[r]) return (r, index - start);
      start += rowLengths[r];
    }
    throw RangeError.index(index, List.filled(count, 0));
  }

  /// Card [index] at rest, not lifted.
  Rect cardRect(int index) {
    final (row, column) = position(index);
    final length = rowLengths[row];
    final rowWidth = cardWidth + (length - 1) * step;
    final left = (width - rowWidth) / 2 + column * step;
    final centre = (length - 1) / 2;
    final off = centre == 0 ? 0.0 : (column - centre) / centre;
    final top =
        CardSizes.selectedLift + row * rowStep + CardFan.bow * off * off;
    return Rect.fromLTWH(left, top, cardWidth, cardHeight);
  }

  /// The part of card [index] no other card covers while none is lifted:
  /// the strip up to the next card of its row, down to the row below. Its
  /// centre is where a tap is sure to reach this card.
  Rect visibleRect(int index) {
    final rect = cardRect(index);
    final (row, column) = position(index);
    final last = column == rowLengths[row] - 1;
    final bottom = row == rows - 1
        ? rect.bottom
        : CardSizes.selectedLift + (row + 1) * rowStep;
    return Rect.fromLTRB(
      rect.left,
      rect.top,
      last ? rect.right : rect.left + step,
      bottom,
    );
  }
}
