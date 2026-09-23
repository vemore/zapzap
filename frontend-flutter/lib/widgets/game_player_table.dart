import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_theme.dart';
import 'card_back.dart';

/// One seat as the table shows it — plain data, so the widget knows nothing
/// of the provider.
class GameSeat {
  const GameSeat({
    required this.playerIndex,
    required this.name,
    required this.score,
    required this.cardCount,
    this.isMe = false,
    this.isCurrentTurn = false,
    this.isEliminated = false,
  });

  final int playerIndex;
  final String name;
  final int score;
  final int cardCount;
  final bool isMe;
  final bool isCurrentTurn;
  final bool isEliminated;
}

/// The players, one line each, in the order given — turn order, from the
/// round's starting player (`GameProvider.orderedPlayers`). The port of
/// `frontend/src/components/Game/PlayerTable.jsx`, made compact by J6 of the
/// UX study: a small card back and the number of cards instead of a row of
/// backs, the player to move on an amber edge, and each score's bar towards
/// 100 — the elimination line — turning red above 80. Every line has the
/// same height, whatever it holds.
class GamePlayerTable extends StatelessWidget {
  const GamePlayerTable({super.key, required this.seats});

  final List<GameSeat> seats;

  /// Past this total a player is out (`GAME_RULES.md`, Game Elimination).
  static const eliminationScore = 100;

  /// Above this total the bar turns red: the player is close to going out.
  static const dangerScore = 80;

  static const activeEdgeColor = AppColors.amber400;
  static const barColor = AppColors.amber400;
  static const dangerBarColor = AppColors.error;

  static Key seatKey(int playerIndex) => ValueKey('gameSeat-$playerIndex');
  static Key cardCountKey(int playerIndex) =>
      ValueKey('seatCardCount-$playerIndex');
  static Key scoreBarKey(int playerIndex) =>
      ValueKey('seatScoreBar-$playerIndex');

  /// The height of every line: one line of text at the current scale, plus
  /// room for the card back. Fixed, so a line holding a badge, a card back
  /// or "Éliminé" is no taller than another.
  static double rowHeight(BuildContext context) =>
      math.max(34, MediaQuery.textScalerOf(context).scale(20) + 12);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (seats.isEmpty) {
      return Card(
        color: AppColors.slate800,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(child: Text(l10n.gamePlayersWaiting)),
        ),
      );
    }
    final height = rowHeight(context);
    return Card(
      color: AppColors.slate800,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final seat in seats) _SeatRow(seat: seat, height: height),
          ],
        ),
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat, required this.height});

  final GameSeat seat;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = seat.isCurrentTurn;
    final out = seat.isEliminated;
    final score = seat.score;
    final danger = out || score > GamePlayerTable.dangerScore;

    return Container(
      key: GamePlayerTable.seatKey(seat.playerIndex),
      height: height,
      padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: active
                ? GamePlayerTable.activeEdgeColor
                : Colors.transparent,
            width: 3,
          ),
        ),
        color: active ? AppColors.amber400.withValues(alpha: 0.10) : null,
      ),
      child: Opacity(
        opacity: out ? 0.5 : 1,
        child: Row(
          children: [
            Icon(
              out
                  ? Icons.dangerous_outlined
                  : active
                  ? Icons.play_arrow
                  : Icons.person_outline,
              size: 16,
              color: out
                  ? AppColors.error
                  : active
                  ? AppColors.amber400
                  : AppColors.slate400,
            ),
            const SizedBox(width: 4),
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      seat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: out ? TextDecoration.lineThrough : null,
                        color: out ? AppColors.slate400 : AppColors.slate100,
                      ),
                    ),
                  ),
                  if (seat.isMe) ...[
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          l10n.gameYouBadge,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.amber400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: out
                    ? Text(
                        l10n.gameEliminatedMark,
                        style: const TextStyle(color: AppColors.slate400),
                      )
                    : _CardCount(seat: seat),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 3,
              child: LinearProgressIndicator(
                key: GamePlayerTable.scoreBarKey(seat.playerIndex),
                value: out
                    ? 1
                    : score.clamp(0, GamePlayerTable.eliminationScore) /
                          GamePlayerTable.eliminationScore,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
                color: danger
                    ? GamePlayerTable.dangerBarColor
                    : GamePlayerTable.barColor,
                backgroundColor: AppColors.slate700,
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 28),
              child: Text(
                '$score',
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: out ? AppColors.error : AppColors.slate100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "▯ 5": one small card back and the number of cards, instead of a back
/// per card to count.
class _CardCount extends StatelessWidget {
  const _CardCount({required this.seat});

  final GameSeat seat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.gameHandCards(seat.cardCount),
      excludeSemantics: true,
      child: Row(
        key: GamePlayerTable.cardCountKey(seat.playerIndex),
        mainAxisSize: MainAxisSize.min,
        children: [
          const CardBack(size: CardBackSize.xxs),
          const SizedBox(width: 4),
          Text(
            '${seat.cardCount}',
            style: const TextStyle(color: AppColors.slate400),
          ),
        ],
      ),
    );
  }
}
