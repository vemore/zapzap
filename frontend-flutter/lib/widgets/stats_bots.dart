import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/stats.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// What one bot difficulty looks like and plays like.
typedef DifficultyStyle = ({
  String label,
  String strategy,
  String description,
  Color color,
});

/// The name, the strategy and the colour of [difficulty], as the React
/// client shows them (`frontend/src/components/Stats/Statistics.jsx`,
/// `difficultyLabels` / `difficultyStrategies` / `difficultyColors`). An
/// unknown difficulty — a new bot kind — keeps its raw name and no strategy
/// rather than breaking the screen.
DifficultyStyle difficultyStyle(String difficulty, AppLocalizations l10n) =>
    switch (difficulty) {
      'easy' => (
        label: l10n.difficultyEasy,
        strategy: l10n.strategyEasyTitle,
        description: l10n.strategyEasyDescription,
        color: StatsColors.success,
      ),
      'medium' => (
        label: l10n.difficultyMedium,
        strategy: l10n.strategyMediumTitle,
        description: l10n.strategyMediumDescription,
        color: AppColors.amber400,
      ),
      'hard' => (
        label: l10n.difficultyHard,
        strategy: l10n.strategyHardTitle,
        description: l10n.strategyHardDescription,
        color: StatsColors.danger,
      ),
      'hard_vince' => (
        label: l10n.difficultyHardVince,
        strategy: l10n.strategyHardVinceTitle,
        description: l10n.strategyHardVinceDescription,
        color: StatsColors.zapzap,
      ),
      'ml' => (
        label: l10n.difficultyMl,
        strategy: l10n.strategyMlTitle,
        description: l10n.strategyMlDescription,
        color: Color(0xFF22D3EE),
      ),
      'drl' => (
        label: l10n.difficultyDrl,
        strategy: l10n.strategyDrlTitle,
        description: l10n.strategyDrlDescription,
        color: Color(0xFF818CF8),
      ),
      'llm' => (
        label: l10n.difficultyLlm,
        strategy: l10n.strategyLlmTitle,
        description: l10n.strategyLlmDescription,
        color: Color(0xFFF472B6),
      ),
      'thibot' => (
        label: l10n.difficultyThibot,
        strategy: l10n.strategyThibotTitle,
        description: l10n.strategyThibotDescription,
        color: StatsColors.bronze,
      ),
      _ => (
        label: difficulty,
        strategy: '',
        description: '',
        color: AppColors.slate400,
      ),
    };

/// The bots' record (`GET /stats/bots`): the totals, then one card per
/// difficulty, filtered by a row of chips — and, once a difficulty is
/// picked, the bots of that difficulty one by one.
class StatsBots extends StatefulWidget {
  const StatsBots({super.key, required this.stats});

  final BotStats stats;

  @override
  State<StatsBots> createState() => _StatsBotsState();
}

class _StatsBotsState extends State<StatsBots> {
  /// `null` shows every difficulty and no per-bot breakdown.
  String? _difficulty;

  /// A reload that no longer carries the picked difficulty falls back to
  /// all of them, rather than a heading over no row.
  @override
  void didUpdateWidget(StatsBots oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _difficulty;
    if (selected != null &&
        !widget.stats.byDifficulty.any((line) => line.difficulty == selected)) {
      _difficulty = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = widget.stats.totals;
    final selected = _difficulty;
    final shown = selected == null
        ? widget.stats.byDifficulty
        : widget.stats.byDifficulty
              .where((line) => line.difficulty == selected)
              .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatTileGrid(
          tiles: [
            StatTile(
              icon: Icons.smart_toy,
              color: StatsColors.zapzap,
              label: l10n.botTotalBots,
              value: '${totals.totalBots}',
            ),
            StatTile(
              icon: Icons.tag,
              color: StatsColors.info,
              label: l10n.statsGamesPlayed,
              value: '${totals.totalGamesPlayed}',
            ),
            StatTile(
              icon: Icons.emoji_events,
              label: l10n.botOverallWinRate,
              value: Formats.percent(totals.overallWinRate),
            ),
            StatTile(
              icon: Icons.bolt,
              color: StatsColors.success,
              label: l10n.botZapzapSuccess,
              value: Formats.percent(totals.overallZapzapSuccessRate),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          key: const Key('bot-difficulty-filter'),
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('bot-difficulty-all'),
              label: Text(l10n.botFilterAll),
              selected: selected == null,
              onSelected: (_) => setState(() => _difficulty = null),
            ),
            for (final line in widget.stats.byDifficulty)
              ChoiceChip(
                key: Key('bot-difficulty-${line.difficulty}'),
                label: Text(difficultyStyle(line.difficulty, l10n).label),
                selected: selected == line.difficulty,
                onSelected: (_) =>
                    setState(() => _difficulty = line.difficulty),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final line in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DifficultyCard(line: line),
          ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Text(
            l10n.botIndividualTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final bot in widget.stats.byBot.where(
            (bot) => bot.difficulty == selected,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _BotRow(bot: bot),
            ),
        ],
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({required this.line});

  final BotStatsLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final style = difficultyStyle(line.difficulty, l10n);
    return Container(
      key: Key('bot-card-${line.difficulty}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: style.color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (line.botCount != null)
                Text(
                  l10n.botCount(line.botCount!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
            ],
          ),
          if (style.strategy.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              style.strategy,
              style: theme.textTheme.bodySmall?.copyWith(color: style.color),
            ),
            const SizedBox(height: 2),
            Text(
              style.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.slate400,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MiniStat(
                  label: l10n.botGames,
                  value: '${line.gamesPlayed}',
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: l10n.botRounds,
                  value: '${line.roundsPlayed}',
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: l10n.statsWinRate,
                  value: Formats.percent(line.winRate),
                  color: StatsColors.success,
                ),
              ),
              if (line.roundWinRate != null)
                Expanded(
                  child: MiniStat(
                    label: l10n.botRoundWinRate,
                    value: Formats.percent(line.roundWinRate),
                    color: AppColors.amber400,
                  ),
                ),
            ],
          ),
          const Divider(height: 24, color: AppColors.slate600),
          Row(
            children: [
              Expanded(
                child: MiniStat(
                  label: l10n.botZapzapCalls,
                  value: '${line.zapzaps.total}',
                ),
              ),
              Expanded(
                child: MiniStat(
                  label: l10n.statsZapzapSuccessRate,
                  value: Formats.percent(line.zapzaps.successRate),
                  color: StatsColors.zapzap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BotRow extends StatelessWidget {
  const _BotRow({required this.bot});

  final BotStatsLine bot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      key: Key('bot-row-${bot.botId}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bot.username ?? '', style: theme.textTheme.titleSmall),
                Text(
                  l10n.botRowSummary(
                    l10n.gameCount(bot.gamesPlayed),
                    l10n.winCount(bot.wins),
                    l10n.roundCount(bot.roundsPlayed),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Formats.percent(bot.winRate),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: StatsColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
