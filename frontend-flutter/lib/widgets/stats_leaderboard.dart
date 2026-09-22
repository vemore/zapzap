import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/stats.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// The global leaderboard (`GET /stats/leaderboard`), the signed-in player's
/// own row marked.
class StatsLeaderboard extends StatelessWidget {
  const StatsLeaderboard({
    super.key,
    required this.entries,
    required this.currentUserId,
  });

  final List<LeaderboardEntry> entries;

  /// `AuthProvider.user?.id`, `null` when nobody is signed in — the React
  /// client compares the same way
  /// (`frontend/src/components/Stats/Statistics.jsx:194`).
  final String? currentUserId;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final entry in entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: LeaderboardRow(
            key: Key('leaderboard-row-${entry.userId}'),
            entry: entry,
            isCurrentUser:
                currentUserId != null && entry.userId == currentUserId,
          ),
        ),
    ],
  );
}

/// One row of the leaderboard; [isCurrentUser] is what highlights it.
class LeaderboardRow extends StatelessWidget {
  const LeaderboardRow({
    super.key,
    required this.entry,
    required this.isCurrentUser,
  });

  final LeaderboardEntry entry;
  final bool isCurrentUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.amber400.withValues(alpha: 0.15)
            : AppColors.slate700,
        borderRadius: BorderRadius.circular(8),
        border: isCurrentUser ? Border.all(color: AppColors.amber400) : null,
      ),
      child: Row(
        children: [
          RankBadge(rank: entry.rank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: entry.username),
                      if (isCurrentUser)
                        TextSpan(
                          text: ' ${l10n.leaderboardYou}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.amber400,
                          ),
                        ),
                    ],
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCurrentUser ? AppColors.amber400 : null,
                  ),
                ),
                Text(
                  l10n.leaderboardWins(entry.wins, entry.gamesPlayed),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
          // Flexible: "taux de victoire" under the percentage is wide, and
          // at a large system font it pushes the row past a phone's width.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Formats.percent(entry.winRate),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: StatsColors.success,
                  ),
                ),
                Text(
                  l10n.leaderboardWinRate,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
