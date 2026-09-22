import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// One finished game in the history list: its name, who won, how many
/// players, when it ended and over how many rounds.
///
/// Node fills `winnerFinalScore` and `totalRounds`; Rust sends `roundsPlayed`
/// and no winner score ([GameHistoryEntry]), so both are optional here.
class HistoryGameTile extends StatelessWidget {
  const HistoryGameTile({super.key, required this.game, required this.onTap});

  final GameHistoryEntry game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final score = game.winnerFinalScore;
    final rounds = game.totalRounds;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(game.partyName, style: theme.textTheme.titleMedium),
                        if (game.wasGoldenScore ?? false) const GoldenScoreChip(),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        _Fact(
                          icon: Icons.emoji_events,
                          iconColor: AppColors.amber400,
                          text: score == null
                              ? game.winnerUsername
                              : l10n.historyWinnerWithScore(
                                  game.winnerUsername,
                                  score,
                                ),
                        ),
                        _Fact(
                          icon: Icons.group,
                          text: l10n.playerCount(game.playerCount),
                        ),
                        _Fact(
                          icon: Icons.event,
                          text: Formats.dateTime(game.finishedAt, locale),
                        ),
                        if (rounds != null)
                          _Fact(icon: Icons.flag, text: l10n.roundCount(rounds)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.iconColor});

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: iconColor ?? AppColors.slate400),
      const SizedBox(width: 4),
      Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.slate400),
      ),
    ],
  );
}
