import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'history_game_tile.dart';

/// The band that opens My games: games played, games won, my best place, and
/// the way to the statistics.
///
/// A figure not known yet (the statistics still loading or failed, no place
/// in the entries) shows [Formats.missing]; the link always works.
class HistorySummary extends StatelessWidget {
  const HistorySummary({
    super.key,
    required this.onOpenStats,
    this.gamesPlayed,
    this.wins,
    this.bestPlace,
  });

  final int? gamesPlayed;
  final int? wins;
  final int? bestPlace;
  final VoidCallback onOpenStats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final best = bestPlace;
    return Card(
      key: const Key('history-summary'),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: const Key('history-summary-stats'),
        onTap: onOpenStats,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: _Figure(
                  key: const Key('history-summary-games'),
                  value: gamesPlayed == null ? Formats.missing : '$gamesPlayed',
                  label: l10n.historySummaryGames(gamesPlayed ?? 0),
                ),
              ),
              Expanded(
                child: _Figure(
                  key: const Key('history-summary-wins'),
                  value: wins == null ? Formats.missing : '$wins',
                  label: l10n.historySummaryWins(wins ?? 0),
                ),
              ),
              Expanded(
                child: _Figure(
                  key: const Key('history-summary-best'),
                  value: best == null
                      ? Formats.missing
                      : placementLabel(l10n, best),
                  label: l10n.historySummaryBestPlace,
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.statsTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.amber400,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.amber400,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate400),
        ),
      ],
    );
  }
}

/// Under a short or empty My games list: what will show up here, and the way
/// to a game against bots.
class HistoryInvite extends StatelessWidget {
  const HistoryInvite({super.key, required this.onPlay});

  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Container(
      key: const Key('history-invite'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slate600, width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            l10n.historyInviteText,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.slate400,
            ),
          ),
          TextButton(
            key: const Key('history-invite-play'),
            onPressed: onPlay,
            child: Text(l10n.historyInvitePlay, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
