import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/stats.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// The signed-in player's own record (`GET /stats/me`): games and wins, then
/// the ZapZap calls, then the best score and the rounds played.
class StatsPersonal extends StatelessWidget {
  const StatsPersonal({super.key, required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final zapzaps = stats.zapzaps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatTileGrid(
          tiles: [
            StatTile(
              icon: Icons.tag,
              color: StatsColors.info,
              label: l10n.statsGamesPlayed,
              value: '${stats.gamesPlayed}',
            ),
            StatTile(
              icon: Icons.emoji_events,
              label: l10n.statsWins,
              value: '${stats.wins}',
            ),
            StatTile(
              icon: Icons.trending_up,
              color: StatsColors.success,
              label: l10n.statsWinRate,
              value: Formats.percent(stats.winRate),
            ),
            StatTile(
              icon: Icons.track_changes,
              color: StatsColors.zapzap,
              label: l10n.statsAverageScore,
              value: Formats.decimal(stats.averageScore),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.slate700,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: StatsColors.zapzap, size: 20),
                  const SizedBox(width: 8),
                  // Flexible: the title is the only thing that can give way
                  // when the system font is large.
                  Flexible(
                    child: Text(
                      l10n.statsZapzapTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MiniStat(
                      label: l10n.statsZapzapTotal,
                      value: '${zapzaps.total}',
                    ),
                  ),
                  Expanded(
                    child: MiniStat(
                      label: l10n.statsZapzapSuccessful,
                      value: '${zapzaps.successful}',
                      color: StatsColors.success,
                    ),
                  ),
                  Expanded(
                    child: MiniStat(
                      label: l10n.statsZapzapFailed,
                      value: '${zapzaps.failed}',
                      color: StatsColors.danger,
                    ),
                  ),
                ],
              ),
              if (zapzaps.total > 0) ...[
                const Divider(height: 24, color: AppColors.slate600),
                MiniStat(
                  label: l10n.statsZapzapSuccessRate,
                  value: Formats.percent(zapzaps.successRate),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: l10n.statsBestScore,
                value: stats.gamesPlayed == 0
                    ? Formats.missing
                    : '${stats.bestScore}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: l10n.statsTotalRounds,
                value: '${stats.totalRoundsPlayed}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
