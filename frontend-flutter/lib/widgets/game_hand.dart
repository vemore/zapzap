import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import 'card_fan.dart';

/// The player's own cards, in the fan of `CardFan.jsx`, with the header of
/// `frontend/src/components/Game/PlayerHand.jsx`: how many cards, the two
/// hand values (jokers at 0 for ZapZap, at 25 for the score), the "ZapZap
/// eligible" badge, and the deck button that draws.
///
/// Selection is the board's, not this widget's: the React client keeps one
/// in `PlayerHand` and another in `GameBoard`, and they drift apart.
class GameHand extends StatelessWidget {
  const GameHand({
    super.key,
    required this.cards,
    required this.selectedCards,
    required this.eligibilityValue,
    required this.penaltyValue,
    required this.zapZapEligible,
    required this.deckSize,
    this.onCardTap,
    this.onClearSelection,
    this.onDrawFromDeck,
    this.disabled = false,
  });

  final List<int> cards;

  /// The ids tapped, in tap order.
  final List<int> selectedCards;

  /// The hand's value with jokers at 0 (ZapZap eligibility).
  final int eligibilityValue;

  /// The hand's value with jokers at 25 (what it would score).
  final int penaltyValue;

  final bool zapZapEligible;
  final int deckSize;
  final ValueChanged<int>? onCardTap;

  /// `null` disables Clear. The board decides: there is something to clear
  /// when cards *or* a discard card are selected, and the discard one is
  /// picked in the draw phase, where the hand itself is disabled.
  final VoidCallback? onClearSelection;

  /// Given only when a draw from the deck is allowed.
  final VoidCallback? onDrawFromDeck;

  /// The cards cannot be selected (not this player's turn, or a draw is
  /// owed).
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('gameHand'),
      color: AppColors.slate800,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A `Wrap`: at a large text size the header folds instead of
            // overflowing.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.gameHandCards(cards.length),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  l10n.gameHandValues(eligibilityValue, penaltyValue),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate400,
                  ),
                ),
                if (zapZapEligible)
                  Container(
                    key: const Key('zapzapEligibleBadge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amber400.withValues(alpha: 0.2),
                      border: Border.all(color: AppColors.amber400),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.gameZapZapEligible,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.amber400,
                      ),
                    ),
                  ),
                OutlinedButton.icon(
                  key: const Key('draw-deck'),
                  onPressed: onDrawFromDeck,
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.style, size: 16),
                  label: Text(l10n.gameDeckLabel(deckSize)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l10n.gameHandEmpty,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.slate400),
                ),
              )
            else
              CardFan(
                cards: cards,
                selectedCards: selectedCards.toSet(),
                onCardTap: disabled ? null : onCardTap,
                disabled: disabled,
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  key: const Key('clear-selection'),
                  onPressed: onClearSelection,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close, size: 16),
                  label: Text(l10n.gameClearSelection),
                ),
                if (selectedCards.isNotEmpty)
                  Text(
                    l10n.gameSelectedCards(selectedCards.length),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.amber400,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
