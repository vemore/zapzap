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
}

/// The end of a round and the end of a game — the port of
/// `frontend/src/components/Game/RoundEnd.jsx`.
///
/// Whether the ZapZap held or was counteracted, then every player in the
/// order the round scored them, with their badges, their revealed hand and
/// the two scores; last the way on — the next round, or the winner and the
/// way out of a finished game.
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
  /// `handValue + (activePlayers − 1) × 5`.
  final int? callerHandValue;
  final int? callerRoundScore;
  final int? activePlayerCount;

  final bool gameFinished;
  final String? winnerName;
  final int? winnerScore;

  /// A move is in flight: the button waits.
  final bool busy;

  /// Below this width the revealed hands are drawn small.
  static const compactBreakpoint = 640.0;

  static Key playerKey(int playerIndex) => ValueKey('roundEndPlayer-$playerIndex');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = MediaQuery.sizeOf(context).width < compactBreakpoint;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            key: const Key('roundOver'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, l10n),
              if (zapZapCallerName != null) ...[
                const SizedBox(height: 12),
                _zapZapBanner(context, l10n),
              ],
              const SizedBox(height: 16),
              for (var i = 0; i < players.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PlayerResult(
                    player: players[i],
                    rank: i + 1,
                    compact: compact,
                  ),
                ),
              const SizedBox(height: 4),
              if (gameFinished)
                FilledButton.icon(
                  key: const Key('back-to-parties'),
                  onPressed: onBackToParties,
                  icon: const Icon(Icons.home_outlined),
                  label: Text(l10n.lobbyBack),
                )
              else
                FilledButton.icon(
                  key: const Key('next-round'),
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

  /// "Round n over", or the end of the game with its winner banner.
  Widget _header(BuildContext context, AppLocalizations l10n) {
    final titles = Theme.of(context).textTheme;
    if (!gameFinished) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.emoji_events_outlined, color: AppColors.amber400),
          const SizedBox(height: 8),
          Text(
            l10n.gameRoundOverTitle,
            style: titles.titleLarge,
            textAlign: TextAlign.center,
          ),
          Text(
            l10n.gameRoundLabel(roundNumber),
            style: const TextStyle(color: AppColors.slate400),
            textAlign: TextAlign.center,
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

  /// The ZapZap held (green), or it was counteracted (red) and the penalty
  /// is spelled out.
  Widget _zapZapBanner(BuildContext context, AppLocalizations l10n) {
    final colour = wasCounterActed ? AppColors.error : const Color(0xFF4ADE80);
    return Container(
      key: const Key('zapZapBanner'),
      padding: const EdgeInsets.all(12),
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
                wasCounterActed ? Icons.warning_amber : Icons.auto_awesome,
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
          if (wasCounterActed && counterActedByName != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.gameRoundOverCounteracted(counterActedByName!),
                style: const TextStyle(color: AppColors.slate400),
              ),
            ),
          if (wasCounterActed &&
              callerHandValue != null &&
              callerRoundScore != null &&
              activePlayerCount != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
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
}

/// One player's line: the badges, the hand that was revealed and the two
/// scores.
class _PlayerResult extends StatelessWidget {
  const _PlayerResult({
    required this.player,
    required this.rank,
    required this.compact,
  });

  final RoundEndPlayer player;
  final int rank;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlight = player.isEliminated
        ? AppColors.error
        : player.isLowestHand
        ? AppColors.amber400
        : AppColors.slate600;

    return Container(
      key: GameRoundEnd.playerKey(player.playerIndex),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slate800,
        border: Border.all(color: highlight, width: player.isEliminated || player.isLowestHand ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A `Wrap`, not a `Row`: a long name and four badges do not fit a
          // 360 px phone on one line at any text size.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                player.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate100,
                ),
              ),
              if (rank == 1 && !player.isEliminated)
                _Badge(label: l10n.gameRankBadge(rank), colour: AppColors.amber400),
              if (player.isLowestHand)
                _Badge(
                  label: l10n.gameLowestHandBadge,
                  colour: AppColors.amber400,
                  icon: Icons.workspace_premium,
                ),
              if (player.isEliminated)
                _Badge(label: l10n.gameEliminatedMark, colour: AppColors.error),
              if (player.isZapZapCaller)
                _Badge(
                  label: l10n.gameZapZapBadge,
                  colour: const Color(0xFFC084FC),
                  icon: Icons.bolt,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.gameRoundOverHandLabel,
            style: const TextStyle(fontSize: 12, color: AppColors.slate400),
          ),
          const SizedBox(height: 4),
          if (player.hand.isEmpty)
            Text(
              l10n.gameHandEmpty,
              style: const TextStyle(color: AppColors.slate400),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final cardId in player.hand)
                  PlayingCard(
                    cardId: cardId,
                    width: compact ? 38 : 52,
                    disabled: true,
                  ),
              ],
            ),
          const SizedBox(height: 10),
          // `IntrinsicHeight`, because the two tiles must match and the
          // column they sit in has no height to stretch them to: one label
          // wraps to two lines at a large system font and the other does not.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ScoreTile(
                    label: l10n.gameRoundEndThisRound,
                    value: l10n.gameRoundEndPoints(player.roundScore),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ScoreTile(
                    label: l10n.gameRoundEndTotalScore,
                    value: '${player.totalScore}',
                    colour: player.isEliminated ? AppColors.error : null,
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

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour, this.icon});

  final String label;
  final Color colour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.15),
      border: Border.all(color: colour.withValues(alpha: 0.4)),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: colour),
          const SizedBox(width: 3),
        ],
        // `Flexible`, or a `Row` that sizes itself to its children hands the
        // text an unbounded width: the longest badge then runs off a 360 px
        // phone at a large system font instead of wrapping.
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colour,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.slate900.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.slate400),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: colour ?? AppColors.slate100,
            ),
          ),
        ),
      ],
    ),
  );
}
