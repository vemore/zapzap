import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../utils/app_theme.dart';
import 'stats_common.dart';

/// The final standings of a finished game: every player in finishing order,
/// with their ZapZap record and their final score. Lower is better, so the
/// winner is not the highest score.
class HistoryStandings extends StatelessWidget {
  const HistoryStandings({super.key, required this.players});

  final List<GamePlayerResult> players;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final player in players)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _StandingsRow(player: player),
        ),
    ],
  );
}

class _StandingsRow extends StatelessWidget {
  const _StandingsRow({required this.player});

  final GamePlayerResult player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: Key('standings-${player.userId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: player.isWinner
            ? AppColors.amber400.withValues(alpha: 0.12)
            : AppColors.slate700,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: player.isWinner ? AppColors.amber400 : AppColors.slate600,
        ),
      ),
      child: Row(
        children: [
          RankBadge(rank: player.finishPosition),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.username,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 12,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt,
                          size: 14,
                          color: StatsColors.zapzap,
                        ),
                        Text(
                          l10n.standingsZapzaps(
                            player.successfulZapZaps,
                            player.totalZapZapCalls,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.slate400,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      l10n.standingsLowestHands(player.lowestHandCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.slate400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Text(
            l10n.points(player.finalScore),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: player.isWinner ? AppColors.amber400 : null,
            ),
          ),
        ],
      ),
    );
  }
}
