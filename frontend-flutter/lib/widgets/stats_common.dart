import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';

/// The accents the history and statistics screens borrow from the React
/// client's Tailwind palette (`frontend/src/components/Stats/Statistics.jsx`),
/// beyond the slate and amber of [AppColors]: a win is green, a loss red, a
/// ZapZap purple, the podium gold/silver/bronze.
abstract final class StatsColors {
  static const success = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);
  static const zapzap = Color(0xFFC084FC);
  static const info = Color(0xFF60A5FA);
  static const silver = Color(0xFFD1D5DB);
  static const bronze = Color(0xFFFB923C);
}

/// A titled card, the block every section of these screens is made of.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor ?? theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
                // Flexible around the trailing badge too: `Expanded` alone
                // gives the title whatever the badge asks for, and a badge
                // that wants more than the row has left squeezes the title
                // into a column of single letters and is clipped anyway.
                if (trailing != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: trailing,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// One figure with its label, as React's `StatCard`.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate700,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
            const SizedBox(height: 6),
          ],
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.slate400,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// A grid of [StatTile] that keeps two columns on a phone and stays readable
/// on a wide window.
class StatTileGrid extends StatelessWidget {
  const StatTileGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 640 ? 4 : 2;
      const spacing = 12.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final tile in tiles) SizedBox(width: width, child: tile),
        ],
      );
    },
  );
}

/// The rank or finishing position, gold, silver, bronze then slate.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (rank) {
      1 => (AppColors.amber400, AppColors.slate900),
      2 => (StatsColors.silver, AppColors.slate900),
      3 => (StatsColors.bronze, AppColors.slate900),
      _ => (AppColors.slate600, AppColors.slate100),
    };
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Text(
        '$rank',
        style: TextStyle(color: foreground, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// The badge of a game that ended on the golden score.
class GoldenScoreChip extends StatelessWidget {
  const GoldenScoreChip({super.key, this.finish = false});

  /// The longer wording of the game details ("Golden Score finish").
  final bool finish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.amber400.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.amber400.withValues(alpha: 0.4)),
      ),
      child: Text(
        finish ? l10n.goldenScoreFinish : l10n.goldenScore,
        // The chip is the part that gives way in a header too narrow for
        // both it and the title (see [SectionCard]).
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.amber400, fontSize: 12),
      ),
    );
  }
}

/// A small figure with its caption, used inside the cards.
class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.slate400),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
