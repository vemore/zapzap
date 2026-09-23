import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import 'playing_card.dart';

/// One player as the end of a round shows them — plain data, so the widget
/// knows nothing of the provider (as [GameSeat] for the player table).
class RoundEndPlayer {
  const RoundEndPlayer({
    required this.playerIndex,
    required this.name,
    required this.hand,
    required this.roundScore,
    required this.totalScore,
    this.isLowestHand = false,
    this.isEliminated = false,
    this.isZapZapCaller = false,
    this.isMe = false,
  });

  final int playerIndex;
  final String name;

  /// The hand revealed at the end of the round (`gameState.allHands`).
  final List<int> hand;

  /// What this round cost them (`gameState.roundScores`).
  final int roundScore;

  /// Their total after the round (`gameState.scores`).
  final int totalScore;
  final bool isLowestHand;
  final bool isEliminated;
  final bool isZapZapCaller;

  /// The row of the player holding this device.
  final bool isMe;

  /// Their total before the round: where the animated total starts.
  int get previousTotal => math.max(0, totalScore - roundScore);
}

/// The end of a round and the end of a game — the port of
/// `frontend/src/components/Game/RoundEnd.jsx`, laid out to read at a
/// glance on a phone.
///
/// The ZapZap in one sentence (held, or counteracted with its penalty), then
/// one row per player in the order the round scored them — rank, name, the
/// revealed hand in miniature, this round's points and the total, which
/// climbs from the old score to the new one over a bar towards 100 —, and,
/// pinned under them, the way on: who picks the next hand size and Next
/// round, or the way out of a finished game.
class GameRoundEnd extends StatelessWidget {
  const GameRoundEnd({
    super.key,
    required this.roundNumber,
    required this.players,
    required this.onNextRound,
    required this.onBackToParties,
    this.zapZapCallerName,
    this.counterActedByName,
    this.wasCounterActed = false,
    this.callerHandValue,
    this.callerRoundScore,
    this.activePlayerCount,
    this.callerZapZapValue,
    this.counterActorZapZapValue,
    this.nextChooserName,
    this.nextChooserIsMe = false,
    this.gameFinished = false,
    this.winnerName,
    this.winnerScore,
    this.busy = false,
  });

  /// The round that just ended.
  final int roundNumber;

  /// Already sorted: lowest round score first.
  final List<RoundEndPlayer> players;

  /// `POST /nextRound`; `null` while a move is in flight.
  final VoidCallback? onNextRound;
  final VoidCallback onBackToParties;

  /// Who called ZapZap, when anybody did.
  final String? zapZapCallerName;

  /// Who held a hand as low, when the call was counteracted.
  final String? counterActedByName;
  final bool wasCounterActed;

  /// The three numbers of the counteract penalty, `GAME_RULES.md`:
  /// `handValue + (activePlayers − 1) × 5`. [callerHandValue] counts a
  /// Joker 25, as the score does.
  final int? callerHandValue;
  final int? callerRoundScore;
  final int? activePlayerCount;

  /// The hand values the ZapZap was decided on (a Joker counts 0): the
  /// caller's, and the counteracting player's.
  final int? callerZapZapValue;
  final int? counterActorZapZapValue;

  /// Who picks the hand size of the next round (`GAME_RULES.md`,
  /// "Subsequent Rounds"), when it is known.
  final String? nextChooserName;
  final bool nextChooserIsMe;

  final bool gameFinished;
  final String? winnerName;
  final int? winnerScore;

  /// A move is in flight: the button waits.
  final bool busy;

  /// How long a total takes to climb to its new value.
  static const totalAnimation = Duration(milliseconds: 400);

  /// Above this text scale the miniature hand goes under the name.
  static const stackedTextScale = 1.2;

  static Key playerKey(int playerIndex) =>
      ValueKey('roundEndPlayer-$playerIndex');
  static Key totalKey(int playerIndex) =>
      ValueKey('roundEndTotal-$playerIndex');
  static Key barKey(int playerIndex) => ValueKey('roundEndBar-$playerIndex');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final animate = !MediaQuery.of(context).disableAnimations;
    final stacked =
        MediaQuery.textScalerOf(context).scale(10) / 10 > stackedTextScale;

    return Column(
      key: const Key('roundOver'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, l10n),
                    if (zapZapCallerName != null) ...[
                      const SizedBox(height: 10),
                      _zapZapBanner(l10n),
                    ],
                    const SizedBox(height: 10),
                    _table(l10n, animate: animate, stacked: stacked),
                    const SizedBox(height: 6),
                    Text(
                      l10n.gameRoundEndDangerLegend,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _footer(l10n),
      ],
    );
  }

  /// "Round over · Round n", or the end of the game with its winner banner.
  Widget _header(BuildContext context, AppLocalizations l10n) {
    final titles = Theme.of(context).textTheme;
    if (!gameFinished) {
      return Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          const Icon(Icons.emoji_events_outlined, color: AppColors.amber400),
          Text(l10n.gameRoundOverTitle, style: titles.titleLarge),
          Text(
            l10n.gameRoundLabel(roundNumber),
            style: const TextStyle(color: AppColors.slate400),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.gameOverTitle,
          style: titles.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (winnerName != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('winnerBanner'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.amber600.withValues(alpha: 0.15),
              border: Border.all(color: AppColors.amber400, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      color: AppColors.amber400,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        l10n.gameWinnerLabel,
                        style: const TextStyle(
                          color: AppColors.amber400,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.gameOverWinner(winnerName!),
                  style: titles.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (winnerScore != null)
                  Text(
                    l10n.gameFinalScore(winnerScore!),
                    style: const TextStyle(color: AppColors.amber400),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          l10n.gameRoundLabel(roundNumber),
          style: const TextStyle(color: AppColors.slate400),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// The ZapZap in one sentence: it held (green) and why, or it was
  /// counteracted (red), by whom, on which values, and the penalty.
  Widget _zapZapBanner(AppLocalizations l10n) {
    final colour = wasCounterActed ? AppColors.error : const Color(0xFF4ADE80);
    final String? detail;
    if (!wasCounterActed) {
      detail = callerZapZapValue == null
          ? null
          : l10n.gameRoundOverZapZapHeldDetail(
              zapZapCallerName!,
              callerZapZapValue!,
            );
    } else if (counterActedByName == null) {
      detail = null;
    } else if (counterActorZapZapValue != null &&
        callerZapZapValue != null &&
        callerHandValue != null &&
        activePlayerCount != null) {
      detail = l10n.gameRoundOverCounteractedDetail(
        counterActedByName!,
        counterActorZapZapValue!,
        callerZapZapValue!,
        callerHandValue!,
        (activePlayerCount! - 1) * 5,
      );
    } else {
      detail = l10n.gameRoundOverCounteracted(counterActedByName!);
    }

    return Container(
      key: const Key('zapZapBanner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                wasCounterActed ? Icons.warning_amber : Icons.bolt,
                color: colour,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  wasCounterActed
                      ? l10n.gameRoundOverCounteractedCall(zapZapCallerName!)
                      : l10n.gameRoundOverZapZapSuccess(zapZapCallerName!),
                  style: TextStyle(color: colour, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                detail,
                key: const Key('zapZapDetail'),
                style: const TextStyle(color: AppColors.slate100),
              ),
            ),
          if (wasCounterActed &&
              callerHandValue != null &&
              callerRoundScore != null &&
              activePlayerCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.gameRoundOverPenalty(
                  callerHandValue!,
                  activePlayerCount!,
                  callerRoundScore!,
                ),
                style: const TextStyle(color: AppColors.slate400),
              ),
            ),
        ],
      ),
    );
  }

  /// One row per player under a header row.
  Widget _table(
    AppLocalizations l10n, {
    required bool animate,
    required bool stacked,
  }) => Container(
    key: const Key('roundEndTable'),
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.slate800,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoundEndRowLayout(
          stacked: stacked,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          rank: _headerText(l10n.gameRoundEndColumnRank),
          name: _headerText(l10n.gameRoundEndColumnPlayer),
          hand: stacked ? null : _headerText(l10n.gameRoundOverHandLabel),
          round: _headerText(l10n.gameRoundEndColumnRound, end: true),
          total: _headerText(l10n.gameRoundEndColumnTotal, end: true),
        ),
        for (var i = 0; i < players.length; i++)
          _PlayerRow(
            player: players[i],
            rank: i + 1,
            animate: animate,
            stacked: stacked,
          ),
      ],
    ),
  );

  static Widget _headerText(String text, {bool end = false}) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: end ? Alignment.centerRight : Alignment.centerLeft,
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppColors.slate400),
    ),
  );

  /// Pinned under the table: who picks the next hand size and Next round,
  /// or the way out of a finished game.
  Widget _footer(AppLocalizations l10n) => Container(
    key: const Key('roundEndFooter'),
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
    decoration: const BoxDecoration(
      color: AppColors.slate800,
      boxShadow: [
        BoxShadow(color: Colors.black38, blurRadius: 16, offset: Offset(0, -6)),
      ],
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!gameFinished && (nextChooserIsMe || nextChooserName != null))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  nextChooserIsMe
                      ? l10n.gameNextRoundChooserMe(roundNumber + 1)
                      : l10n.gameNextRoundChooser(
                          roundNumber + 1,
                          nextChooserName!,
                        ),
                  key: const Key('nextChooser'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.slate400,
                  ),
                ),
              ),
            if (gameFinished)
              FilledButton.icon(
                key: const Key('back-to-parties'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onBackToParties,
                icon: const Icon(Icons.home_outlined),
                label: Text(l10n.lobbyBack),
              )
            else
              FilledButton.icon(
                key: const Key('next-round'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: busy ? null : onNextRound,
                icon: const Icon(Icons.arrow_forward),
                label: Text(l10n.gameNextRoundButton),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The columns of the table, shared by the header and every row so they
/// line up: rank, name, the miniature hand (under the name when [stacked]),
/// this round's points, the total.
class _RoundEndRowLayout extends StatelessWidget {
  const _RoundEndRowLayout({
    required this.stacked,
    required this.padding,
    required this.rank,
    required this.name,
    required this.hand,
    required this.round,
    required this.total,
  });

  final bool stacked;
  final EdgeInsets padding;
  final Widget rank;
  final Widget name;
  final Widget? hand;
  final Widget round;
  final Widget total;

  static const rankWidth = 24.0;
  static const roundWidth = 48.0;
  static const totalWidth = 48.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        SizedBox(width: rankWidth, child: rank),
        Expanded(
          flex: 5,
          child: stacked && hand != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, const SizedBox(height: 4), hand!],
                )
              : name,
        ),
        if (!stacked) ...[
          const SizedBox(width: 6),
          Expanded(flex: 4, child: hand ?? const SizedBox.shrink()),
        ],
        const SizedBox(width: 6),
        SizedBox(width: roundWidth, child: round),
        const SizedBox(width: 6),
        SizedBox(width: totalWidth, child: total),
      ],
    ),
  );
}

/// One player's row: the columns, then the bar of their total towards 100.
/// The total and the bar climb together from the old score to the new one.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.rank,
    required this.animate,
    required this.stacked,
  });

  final RoundEndPlayer player;
  final int rank;
  final bool animate;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = player.isMe;

    return Container(
      key: GameRoundEnd.playerKey(player.playerIndex),
      decoration: BoxDecoration(
        color: me ? AppColors.amber400.withValues(alpha: 0.08) : null,
        border: Border(
          top: const BorderSide(color: AppColors.slate700),
          left: me
              ? const BorderSide(color: AppColors.amber400, width: 3)
              : BorderSide.none,
        ),
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          begin: player.previousTotal.toDouble(),
          end: player.totalScore.toDouble(),
        ),
        duration: animate ? GameRoundEnd.totalAnimation : Duration.zero,
        curve: Curves.easeOut,
        builder: (context, value, _) {
          final shown = value.round();
          return Padding(
            padding: EdgeInsets.fromLTRB(0, 5, me ? 3 : 0, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RoundEndRowLayout(
                  stacked: stacked,
                  padding: EdgeInsets.only(left: me ? 9 : 12, right: 9),
                  rank: Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: rank == 1 && !player.isEliminated
                          ? AppColors.amber400
                          : AppColors.slate100,
                    ),
                  ),
                  name: _name(l10n),
                  hand: _MiniHand(cards: player.hand),
                  round: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      l10n.gameRoundEndRoundPoints(player.roundScore),
                      style: TextStyle(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: player.roundScore == 0
                            ? const Color(0xFF4ADE80)
                            : AppColors.slate100,
                      ),
                    ),
                  ),
                  total: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$shown',
                      key: GameRoundEnd.totalKey(player.playerIndex),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: player.isEliminated
                            ? AppColors.error
                            : AppColors.slate100,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.only(
                    left: (me ? 9 : 12) + _RoundEndRowLayout.rankWidth,
                    right: 9,
                  ),
                  child: RoundEndScoreBar(
                    key: GameRoundEnd.barKey(player.playerIndex),
                    total: shown,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The name, "You" on the player's own row, a bolt for the ZapZap caller
  /// and a crown for the lowest hand — icons, so a row stays one line —,
  /// and "Eliminated" in words, not in colour alone.
  Widget _name(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Flexible(
            child: Text(
              player.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.slate100,
              ),
            ),
          ),
          if (player.isZapZapCaller)
            _Marker(
              label: l10n.gameZapZapBadge,
              icon: Icons.bolt,
              colour: const Color(0xFFC084FC),
            ),
          if (player.isLowestHand)
            _Marker(
              label: l10n.gameLowestHandBadge,
              icon: Icons.workspace_premium,
              colour: AppColors.amber400,
            ),
          if (player.isMe)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                l10n.gameYouBadge,
                key: const Key('roundEndMe'),
                style: const TextStyle(fontSize: 11, color: AppColors.amber400),
              ),
            ),
        ],
      ),
      if (player.isEliminated)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _Badge(
            label: l10n.gameEliminatedMark,
            colour: AppColors.error,
          ),
        ),
    ],
  );
}

/// A badge drawn as an icon, named by its tooltip and for screen readers.
class _Marker extends StatelessWidget {
  const _Marker({
    required this.label,
    required this.icon,
    required this.colour,
  });

  final String label;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 3),
    child: Tooltip(
      message: label,
      child: Icon(icon, size: 16, color: colour, semanticLabel: label),
    ),
  );
}

/// The hand revealed at the end of the round, in miniature: the cards
/// overlap as much as the width they are given needs.
class _MiniHand extends StatelessWidget {
  const _MiniHand({required this.cards});

  final List<int> cards;

  static const cardWidth = 22.0;
  static const gap = 3.0;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Text(
        AppLocalizations.of(context).gameHandEmpty,
        style: const TextStyle(fontSize: 12, color: AppColors.slate400),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = cards.length;
        final room = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : count * (cardWidth + gap);
        final step = count == 1
            ? 0.0
            : math.max(
                6.0,
                math.min(cardWidth + gap, (room - cardWidth) / (count - 1)),
              );
        final width = cardWidth + step * (count - 1);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: math.min(width, room),
            height: PlayingCard.heightFor(cardWidth),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (var i = 0; i < count; i++)
                  Positioned(
                    left: i * step,
                    top: 0,
                    child: PlayingCard(cardId: cards[i], width: cardWidth),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A total on its way to 100 points, past which a player is out
/// (`GAME_RULES.md`, "Game Elimination"): amber, then red above
/// [dangerFrom].
class RoundEndScoreBar extends StatelessWidget {
  const RoundEndScoreBar({super.key, required this.total});

  final int total;

  /// Above this total the bar turns red.
  static const dangerFrom = 80;
  static const limit = 100;

  Color get colour => total > dangerFrom ? AppColors.error : AppColors.amber400;

  double get fraction => (total / limit).clamp(0, 1).toDouble();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: SizedBox(
      height: 5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.slate700),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: ColoredBox(color: colour),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.15),
      border: Border.all(color: colour.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: colour,
      ),
    ),
  );
}
