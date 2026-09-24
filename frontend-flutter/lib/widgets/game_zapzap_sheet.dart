import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/rules.dart';

/// What calling ZapZap now would risk, from `GAME_RULES.md`: the call holds
/// when no opponent's hand is [handValue] or less; otherwise the caller
/// scores [scoredValue] (a joker counting 25) plus 5 for every other player
/// still in the game — and, in Golden Score, loses the game.
class ZapZapRisk {
  const ZapZapRisk({
    required this.handValue,
    required this.scoredValue,
    required this.activePlayers,
    required this.eligible,
    required this.holdsJoker,
    this.isGoldenScore = false,
  });

  /// Whether the hand may call ZapZap — the board's own
  /// `GameProvider.zapZapEligible`, so the button's reason and its enabled
  /// state never disagree.
  final bool eligible;

  /// The hand holds a joker (`hasJoker`): it counts 25 if counteracted.
  final bool holdsJoker;

  /// The hand, jokers at 0: what the call is decided on.
  final int handValue;

  /// The hand, jokers at 25: what a counteracted caller scores.
  final int scoredValue;

  /// The players not eliminated, the caller included.
  final int activePlayers;

  final bool isGoldenScore;

  int get opponents => activePlayers - 1;
  int get penalty => counteractPenalty(activePlayers);
  int get counteractedScore => scoredValue + penalty;
}

/// Asks before calling ZapZap, stating what a counteract costs; answers
/// `true` only when the player confirms. Dismissing the sheet is a no.
Future<bool> confirmZapZap(BuildContext context, ZapZapRisk risk) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    // Scrolls rather than overflows at a large system font.
    isScrollControlled: true,
    backgroundColor: AppColors.slate800,
    builder: (context) => ZapZapConfirmSheet(risk: risk),
  );
  return confirmed ?? false;
}

class ZapZapConfirmSheet extends StatelessWidget {
  const ZapZapConfirmSheet({super.key, required this.risk});

  final ZapZapRisk risk;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final body = Theme.of(context).textTheme.bodyLarge;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('zapzapSheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt, color: AppColors.amber400),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.gameZapZapSheetTitle(risk.handValue),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(l10n.gameZapZapSheetWin(risk.handValue), style: body),
            const SizedBox(height: 12),
            Container(
              key: const Key('zapzapRisk'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.45),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.gameZapZapSheetRisk(
                      risk.scoredValue,
                      risk.penalty,
                      l10n.gameZapZapSheetOpponents(risk.opponents),
                      risk.counteractedScore,
                    ),
                    style: body?.copyWith(color: const Color(0xFFFECACA)),
                  ),
                  if (risk.holdsJoker) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.gameZapZapSheetJoker,
                      key: const Key('zapzapJokerNote'),
                      style: const TextStyle(color: Color(0xFFFECACA)),
                    ),
                  ],
                  if (risk.isGoldenScore) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.gameZapZapSheetGolden,
                      key: const Key('zapzapGoldenNote'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFECACA),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('zapzap-cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(l10n.cancelButton),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('zapzap-confirm'),
                    onPressed: () => Navigator.of(context).pop(true),
                    // The theme's 200 px minimum would not fit two buttons.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.bolt),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(l10n.gameZapZapButton, maxLines: 1),
                    ),
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
