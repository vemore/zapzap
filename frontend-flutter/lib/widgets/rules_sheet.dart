import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Opens the rules of the game in a bottom sheet over the current screen, so
/// the table stays in sight behind it: from the app bar's ⋮ menu, on every
/// signed-in screen, the game board included.
///
/// A short summary of `GAME_RULES.md`: a rule change updates the ARB strings
/// (`rules*`) with it.
Future<void> showRulesSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => const RulesSheet(),
);

class RulesSheet extends StatelessWidget {
  const RulesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sections = [
      (l10n.rulesGoalTitle, l10n.rulesGoalBody),
      (l10n.rulesRoundTitle, l10n.rulesRoundBody),
      (l10n.rulesCardsTitle, l10n.rulesCardsBody),
      (l10n.rulesTurnTitle, l10n.rulesTurnBody),
      (l10n.rulesTurnTimerTitle, l10n.rulesTurnTimerBody),
      (l10n.rulesPlaysTitle, l10n.rulesPlaysBody),
      (l10n.rulesZapZapTitle, l10n.rulesZapZapBody),
      (l10n.rulesCounteractTitle, l10n.rulesCounteractBody),
      (l10n.rulesEliminationTitle, l10n.rulesEliminationBody),
      (l10n.rulesGoldenScoreTitle, l10n.rulesGoldenScoreBody),
    ];
    // Opens at 60 % of the screen, the table visible above it; dragged up to
    // 90 % to read without scrolling as much.
    return DraggableScrollableSheet(
      key: const Key('rules-sheet'),
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(l10n.rulesTitle, style: theme.textTheme.titleLarge),
          for (final (title, body) in sections) ...[
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(body, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
