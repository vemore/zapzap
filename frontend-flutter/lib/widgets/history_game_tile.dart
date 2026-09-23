import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'stats_common.dart';

/// Where [userId] finished [game], or `null` when the entry does not say.
///
/// Rust sends `userPlacement`; Node does not, but its `winnerUserId` still
/// tells a win apart.
int? myPlacement(GameHistoryEntry game, String? userId) =>
    game.userPlacement ??
    (userId != null && game.winnerUserId == userId ? 1 : null);

/// [place] as an ordinal in the app's language: `1er`, `4e`; `1st`, `4th`.
String placementLabel(AppLocalizations l10n, int place) =>
    l10n.historyPlacement(place, switch (place) {
      1 => 'first',
      2 => 'second',
      3 => 'third',
      _ => 'other',
    });

/// One finished game in the history list: where I finished, its name, who
/// won and my own score, how many players, when it ended and over how many
/// rounds.
///
/// Node fills `winnerFinalScore` and `totalRounds`; Rust sends `roundsPlayed`,
/// `userPlacement` and `userScore` but no winner score ([GameHistoryEntry]),
/// so each is optional here.
class HistoryGameTile extends StatelessWidget {
  const HistoryGameTile({
    super.key,
    required this.game,
    required this.onTap,
    this.currentUserId,
  });

  final GameHistoryEntry game;
  final VoidCallback onTap;

  /// The signed-in player, on the My games tab: the row then opens on where
  /// they finished. `null` on the public tab.
  final String? currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final score = game.winnerFinalScore;
    final rounds = game.totalRounds;
    final mine = currentUserId != null;
    final place = mine ? myPlacement(game, currentUserId) : null;
    final myScore = mine ? game.userScore : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (place != null) ...[
                PlacementBadge(place: place),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          game.partyName,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (game.wasGoldenScore ?? false)
                          const GoldenScoreChip(),
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
                        if (myScore != null)
                          _Fact(
                            key: const Key('history-my-score'),
                            icon: Icons.person,
                            iconColor: AppColors.amber400,
                            text: l10n.historyYourScore(myScore),
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
                          _Fact(
                            icon: Icons.flag,
                            text: l10n.roundCount(rounds),
                          ),
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

/// My finishing place in a round badge: amber when I won, outlined otherwise.
class PlacementBadge extends StatelessWidget {
  const PlacementBadge({super.key, required this.place});

  final int place;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final won = place == 1;
    final label = placementLabel(l10n, place);
    return Semantics(
      label: l10n.historyYourPlacement(label),
      excludeSemantics: true,
      child: Container(
        key: const Key('history-placement'),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: won ? AppColors.amber400 : null,
          border: won ? null : Border.all(color: AppColors.slate400, width: 2),
        ),
        // FittedBox: a large system font shrinks the ordinal instead of
        // spilling out of the circle.
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: won ? AppColors.slate900 : AppColors.slate100,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    super.key,
    required this.icon,
    required this.text,
    this.iconColor,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: iconColor ?? AppColors.slate400),
      const SizedBox(width: 4),
      // Flexible, or a long winner name — or a large system font — makes
      // the fact wider than the `Wrap` run it sits in.
      Flexible(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppColors.slate400),
        ),
      ),
    ],
  );
}
