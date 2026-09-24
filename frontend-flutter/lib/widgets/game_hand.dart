import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/rules.dart';
import 'card_fan.dart';
import 'hand_suggestions.dart';

/// The player's own cards, in the fan of `CardFan.jsx`, under what the hand
/// is worth in plain words (J3 of the UX study): "Ta main · 29 pts" — jokers
/// at 0, what ZapZap is decided on —, a gauge towards "ZapZap à 5", and, only
/// when the hand holds a joker, what it scores at the end of the round
/// (jokers 25, for anyone without the lowest hand).
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
    this.onCardTap,
    this.onClearSelection,
    this.onSelectCards,
    this.disabled = false,
    this.compact = false,
  });

  final List<int> cards;

  /// The ids tapped, in tap order.
  final List<int> selectedCards;

  /// The hand's value with jokers at 0 (ZapZap eligibility).
  final int eligibilityValue;

  /// The hand's value with jokers at 25 (what it would score).
  final int penaltyValue;

  final ValueChanged<int>? onCardTap;

  /// `null` disables Clear. The board decides: there is something to clear
  /// when cards *or* a discard card are selected, and the discard one is
  /// picked in the draw phase, where the hand itself is disabled.
  final VoidCallback? onClearSelection;

  /// Selects a suggestion's cards in place of the selection; `null` hides
  /// the suggestions (J8), as does a hand that cannot be played.
  final ValueChanged<List<int>>? onSelectCards;

  /// The cards cannot be selected (not this player's turn, or a draw is
  /// owed).
  final bool disabled;

  /// The hand in the draw step on a phone, read, not played: the cards on
  /// one row of small ones ([CardFan.compact]) under the value alone. The
  /// gauge and Clear go — the ZapZap button says the same, and a discard
  /// card picked by mistake is dropped by tapping it again.
  final bool compact;

  bool get _holdsJoker => hasJoker(cards);

  bool get _showSuggestions =>
      onSelectCards != null && !disabled && !compact && cards.isNotEmpty;

  /// The gauge fills green as the hand comes down to the threshold.
  static const gaugeColor = Color(0xFF4ADE80);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final suggestions = _showSuggestions
        ? suggestPlays(cards)
        : const <PlaySuggestion>[];
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
            // A `Wrap`: at a large text size the gauge folds under the
            // value instead of overflowing.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.gameHandTitle(eligibilityValue),
                  key: const Key('handValue'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!compact)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.gameZapZapThreshold(zapZapThreshold),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate400,
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 60,
                        child: LinearProgressIndicator(
                          key: const Key('zapzapGauge'),
                          value: zapZapProgress(eligibilityValue),
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                          color: GameHand.gaugeColor,
                          backgroundColor: AppColors.slate700,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (_holdsJoker)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  l10n.gameHandPenalty(penaltyValue),
                  key: const Key('handPenaltyValue'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate400,
                  ),
                ),
              ),
            SizedBox(height: compact ? 2 : 4),
            if (suggestions.isNotEmpty) ...[
              HandSuggestions(
                suggestions: suggestions,
                selectedCards: selectedCards,
                onSelect: onSelectCards!,
              ),
              const SizedBox(height: 6),
            ],
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
                compact: compact,
              ),
            if (!compact) ...[
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
          ],
        ),
      ),
    );
  }
}
