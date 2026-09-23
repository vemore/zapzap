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

/// The players, one row each, in turn order — the port of
/// `frontend/src/components/Game/PlayerTable.jsx`:
/// `<name> - <score> : <card backs> (<count>)`, the player to move marked
/// with a green edge, an eliminated one struck through.
class GamePlayerTable extends StatelessWidget {
  const GamePlayerTable({super.key, required this.seats});

  final List<GameSeat> seats;

  /// Under this width a row shows at most 5 card backs, and the smallest
  /// ones (`PlayerTable.jsx:150-164`).
  static const compactBreakpoint = 640.0;

  static Key seatKey(int playerIndex) => ValueKey('gameSeat-$playerIndex');

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
    return Card(
      color: AppColors.slate800,
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (final seat in seats) _SeatRow(seat: seat)],
      ),
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat});

  final GameSeat seat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < GamePlayerTable.compactBreakpoint;
    final border = seat.isCurrentTurn
        ? const Color(0xFF4ADE80)
        : Colors.transparent;

    return Container(
      key: GamePlayerTable.seatKey(seat.playerIndex),
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: border, width: 4)),
        color: seat.isCurrentTurn
            ? const Color(0xFF166534).withValues(alpha: 0.25)
            : seat.isMe
            ? AppColors.amber600.withValues(alpha: 0.10)
            : null,
      ),
      child: Opacity(
        opacity: seat.isEliminated ? 0.5 : 1,
        child: Row(
          children: [
            Icon(
              seat.isEliminated
                  ? Icons.dangerous_outlined
                  : seat.isCurrentTurn
                  ? Icons.play_arrow
                  : Icons.person_outline,
              size: 16,
              color: seat.isEliminated
                  ? AppColors.error
                  : seat.isCurrentTurn
                  ? const Color(0xFF4ADE80)
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
                        decoration: seat.isEliminated
                            ? TextDecoration.lineThrough
                            : null,
                        color: seat.isEliminated
                            ? AppColors.slate400
                            : AppColors.slate100,
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
                            fontSize: 10,
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
            Text(
              '${seat.score}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: seat.isEliminated ? AppColors.error : AppColors.slate100,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 4,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: seat.isEliminated
                      ? Text(
                          l10n.gameEliminatedMark,
                          style: const TextStyle(color: AppColors.slate400),
                        )
                      : _CardBacks(count: seat.cardCount, compact: compact),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBacks extends StatelessWidget {
  const _CardBacks({required this.count, required this.compact});

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = count.clamp(0, compact ? 5 : 8);
    final size = compact ? CardBackSize.xxs : CardBackSize.xs;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visible; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: CardBack(size: size),
          ),
        Text(
          l10n.gameSeatCards(count),
          style: const TextStyle(fontSize: 11, color: AppColors.slate400),
        ),
      ],
    );
  }
}
