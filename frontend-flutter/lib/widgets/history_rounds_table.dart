import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// The round-by-round scores: one row per round, one column per player, the
/// points taken that round over the running total, and the markers of the
/// round — who called ZapZap and whether it held, who had the lowest hand,
/// who was counteracted, who was eliminated.
///
/// Wider than a phone, so it scrolls sideways.
class HistoryRoundsTable extends StatelessWidget {
  const HistoryRoundsTable({
    super.key,
    required this.players,
    required this.rounds,
  });

  /// The columns, in the order of the final standings.
  final List<GamePlayerResult> players;
  final List<RoundHistory> rounds;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.slate400,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          key: const Key('rounds-scroll'),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('rounds-table'),
            columnSpacing: 24,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 76,
            columns: [
              DataColumn(label: Text(l10n.roundColumn, style: headerStyle)),
              for (final player in players)
                DataColumn(
                  label: Text(player.username, style: headerStyle),
                ),
            ],
            rows: [
              for (final round in rounds)
                DataRow(
                  key: ValueKey('round-${round.roundNumber}'),
                  cells: [
                    DataCell(Text(l10n.roundLabel(round.roundNumber))),
                    for (final player in players)
                      DataCell(
                        _Cell(
                          score: round.players
                              .where((p) => p.userId == player.userId)
                              .firstOrNull,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _Legend(),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.score});

  /// `null` when the player took no part in that round.
  final RoundPlayerScore? score;

  @override
  Widget build(BuildContext context) {
    final round = score;
    if (round == null) return const Text(Formats.missing);
    final theme = Theme.of(context);
    final color = round.isLowestHand
        ? StatsColors.success
        : round.wasCounterActed
        ? StatsColors.danger
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '+${round.scoreThisRound}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          '(${round.totalScoreAfter})',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.slate400,
          ),
        ),
        if (round.isZapZapCaller || round.isLowestHand || round.isEliminated)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (round.isZapZapCaller)
                Icon(
                  Icons.bolt,
                  size: 14,
                  color: round.zapZapSuccess
                      ? StatsColors.success
                      : StatsColors.danger,
                ),
              if (round.isLowestHand)
                const Icon(
                  Icons.workspace_premium,
                  size: 14,
                  color: AppColors.amber400,
                ),
              if (round.isEliminated)
                const Icon(Icons.close, size: 14, color: StatsColors.danger),
            ],
          ),
      ],
    );
  }
}

/// What the colours and the icons of a cell mean.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        _LegendItem(
          icon: Icons.workspace_premium,
          color: AppColors.amber400,
          label: l10n.legendLowestHand,
        ),
        _LegendItem(
          icon: Icons.bolt,
          color: StatsColors.success,
          label: l10n.legendZapzapSuccess,
        ),
        _LegendItem(
          icon: Icons.bolt,
          color: StatsColors.danger,
          label: l10n.legendZapzapFailed,
        ),
        _LegendItem(
          icon: Icons.close,
          color: StatsColors.danger,
          label: l10n.legendEliminated,
        ),
        // The counteracted player's points are shown in red, with no icon.
        _LegendItem(color: StatsColors.danger, label: l10n.legendCounteracted),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, this.icon});

  /// A colour alone (no [icon]) stands for the colour of the points.
  final IconData? icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null)
        Icon(icon, size: 14, color: color)
      else
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      const SizedBox(width: 4),
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.slate400),
      ),
    ],
  );
}
