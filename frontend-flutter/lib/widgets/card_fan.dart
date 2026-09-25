import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/motion.dart';
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
///
/// A [compact] fan is to be read, not played — the hand in the draw step:
/// one row whatever the count, straight, cards at most
/// [CardSizes.handCompact] wide, opaque, and no room kept for a lift.
///
/// The card a draw brings in carries a "Nouveau" badge for
/// [Motion.freshCard]; a selected card rises in [Motion.lift] — at once
/// under reduced motion ([Motion]).
class CardFan extends StatefulWidget {
  const CardFan({
    super.key,
    required this.cards,
    this.selectedCards = const {},
    this.onCardTap,
    this.disabled = false,
    this.compact = false,
  });

  final List<int> cards;
  final Set<int> selectedCards;
  final ValueChanged<int>? onCardTap;
  final bool disabled;
  final bool compact;

  /// How much of a card's height the row below leaves uncovered.
  static const rowReveal = 0.5;

  /// How far below its centre a row's end cards sit.
  static const bow = 4.0;

  /// How far above a card's top edge its "Nouveau" badge sits.
  static const badgeRise = 8.0;

  /// The key of the card at [index], for tests and the game board.
  static Key itemKey(int index) => ValueKey('cardFanItem-$index');

  /// The key of the "Nouveau" badge on the card [cardId].
  static Key freshBadgeKey(int cardId) => ValueKey('freshCard-$cardId');

  /// Where each card lies, for a hand of [count] cards [width] wide.
  static FanLayout layoutFor(int count, double width, {bool compact = false}) =>
      FanLayout._(count, width, compact: compact);

  @override
  State<CardFan> createState() => _CardFanState();
}

/// Follows the hand from one build to the next to spot the card that just
/// arrived — a draw adds exactly one card and takes none away — and badges
/// it "Nouveau" for [Motion.freshCard] (J9 of the UX study).
class _CardFanState extends State<CardFan> {
  int? _fresh;
  Timer? _freshTimer;

  @override
  void didUpdateWidget(CardFan oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = oldWidget.cards.toSet();
    final added = [
      for (final id in widget.cards)
        if (!before.contains(id)) id,
    ];
    // Exactly one more card, and every card of before still held: a draw.
    // A new deal, a play or a reorder is not.
    if (added.length == 1 && widget.cards.length == before.length + 1) {
      _fresh = added.single;
      _freshTimer?.cancel();
      _freshTimer = Timer(Motion.freshCard, () {
        if (mounted) setState(() => _fresh = null);
      });
    }
  }

  @override
  void dispose() {
    _freshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards;
    if (cards.isEmpty) return const SizedBox.shrink();
    final fresh = cards.indexOf(_fresh ?? -1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fan = CardFan.layoutFor(
          cards.length,
          constraints.maxWidth,
          compact: widget.compact,
        );
        return SizedBox(
          width: fan.width,
          height: fan.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < cards.length; i++)
                _card(context, fan, i, widget.selectedCards.contains(cards[i])),
              // Over every card, so the next one in the row never hides it.
              if (fresh >= 0) _badge(context, fan, fresh),
            ],
          ),
        );
      },
    );
  }

  double _top(FanLayout fan, int index) =>
      fan.cardRect(index).top -
      (widget.selectedCards.contains(widget.cards[index])
          ? CardSizes.selectedLift
          : 0);

  Widget _card(BuildContext context, FanLayout fan, int index, bool selected) {
    final id = widget.cards[index];
    final rest = fan.cardRect(index);
    return AnimatedPositioned(
      key: CardFan.itemKey(index),
      duration: Motion.of(context, Motion.lift),
      curve: Curves.easeOutCubic,
      left: rest.left,
      top: _top(fan, index),
      child: PlayingCard(
        cardId: id,
        selected: selected,
        disabled: widget.disabled,
        dimmed: widget.compact ? false : null,
        width: fan.cardWidth,
        onTap: widget.onCardTap == null ? null : () => widget.onCardTap!(id),
      ),
    );
  }

  /// "Nouveau" across the top edge of card [index], at its left, where the
  /// card's own strip shows. It pops in; under reduced motion it is simply
  /// there, and it goes when its time is up either way.
  Widget _badge(BuildContext context, FanLayout fan, int index) {
    final l10n = AppLocalizations.of(context);
    final id = widget.cards[index];
    final label = Container(
      key: CardFan.freshBadgeKey(id),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.amber400,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3)],
      ),
      child: Text(
        l10n.gameCardNew,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.slate900,
          height: 1.2,
        ),
      ),
    );
    return Positioned(
      left: fan.cardRect(index).left + 2,
      top: math.max(0, _top(fan, index) - CardFan.badgeRise),
      child: IgnorePointer(
        child: Motion.enabled(context)
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Motion.badgeIn,
                curve: Curves.easeOutBack,
                builder: (context, t, child) => Opacity(
                  opacity: t.clamp(0, 1),
                  child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
                ),
                child: label,
              )
            : label,
      ),
    );
  }
}

/// The geometry of a [CardFan]: the card size, the rows, and each card's
/// rect at rest, in the fan's own coordinates.
class FanLayout {
  FanLayout._(this.count, double available, {this.compact = false})
    : width = available.isFinite ? available : 4 * CardSizes.handMax,
      cardWidth = compact
          ? math.min(
              CardSizes.handCompact,
              available.isFinite ? available / 4 : CardSizes.handCompact,
            )
          : (available.isFinite ? available / 4 : CardSizes.handMax).clamp(
              CardSizes.handMin,
              CardSizes.handMax,
            ) {
    final perRow = compact
        ? math.max(1, count)
        : math.max(
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

  /// One row, and no room for a lift ([CardFan.compact]).
  final bool compact;

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

  /// The room kept above the top row for a selected card to rise into.
  double get lift => compact ? 0 : CardSizes.selectedLift;

  /// How far below its centre a row's end cards sit: a compact row is
  /// straight.
  double get bow => compact ? 0 : CardFan.bow;

  double get height => lift + cardHeight + (rows - 1) * rowStep + bow;

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
    final top = lift + row * rowStep + bow * off * off;
    return Rect.fromLTWH(left, top, cardWidth, cardHeight);
  }

  /// The part of card [index] no other card covers while none is lifted:
  /// the strip up to the next card of its row, down to the row below. Its
  /// centre is where a tap is sure to reach this card.
  Rect visibleRect(int index) {
    final rect = cardRect(index);
    final (row, column) = position(index);
    final last = column == rowLengths[row] - 1;
    final bottom = row == rows - 1 ? rect.bottom : lift + (row + 1) * rowStep;
    return Rect.fromLTRB(
      rect.left,
      rect.top,
      last ? rect.right : rect.left + step,
      bottom,
    );
  }
}
