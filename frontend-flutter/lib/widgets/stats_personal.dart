import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/stats.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// The signed-in player's own record (`GET /stats/me`): two figures in large
/// — games won over games played, the average score — then the rest as a
/// list, then the ZapZap calls as a bar of the successful ones.
class StatsPersonal extends StatelessWidget {
  const StatsPersonal({super.key, required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final played = stats.gamesPlayed > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: HeroStat(
                key: const Key('stats-hero-wins'),
                value: l10n.statsHeroWinsValue(stats.wins, stats.gamesPlayed),
                label: l10n.statsHeroWinsLabel(stats.wins, stats.gamesPlayed),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: HeroStat(
                key: const Key('stats-hero-average'),
                value: played
                    ? Formats.number(stats.averageScore)
                    : Formats.missing,
                label: l10n.statsAverageScore,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StatLine(
          label: l10n.statsWinRate,
          value: Formats.percent(stats.winRate),
        ),
        StatLine(
          label: l10n.statsBestScore,
          value: played ? '${stats.bestScore}' : Formats.missing,
        ),
        StatLine(
          label: l10n.statsTotalRounds,
          value: '${stats.totalRoundsPlayed}',
        ),
        const SizedBox(height: 16),
        _ZapZapBlock(zapzaps: stats.zapzaps),
      ],
    );
  }
}

/// The ZapZap calls: a bar of the successful ones over every call, or — none
/// called yet — when one may call it (`GAME_RULES.md`, ZapZap Eligibility).
class _ZapZapBlock extends StatelessWidget {
  const _ZapZapBlock({required this.zapzaps});

  final ZapZapStats zapzaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final called = zapzaps.total > 0;
    return Container(
      key: const Key('stats-zapzap'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          if (!called) ...[
            const SizedBox(height: 8),
            Text(
              l10n.statsZapzapNone,
              key: const Key('stats-zapzap-none'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.slate400,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    key: const Key('stats-zapzap-bar'),
                    value: called ? zapzaps.successful / zapzaps.total : 0,
                    minHeight: 8,
                    color: StatsColors.success,
                    backgroundColor: AppColors.slate600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.statsZapzapBar(zapzaps.successful, zapzaps.total),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              ),
            ],
          ),
          if (called)
            StatLine(
              label: l10n.statsZapzapSuccessRate,
              value: Formats.percent(zapzaps.successRate),
              divider: false,
            ),
        ],
      ),
    );
  }
}
