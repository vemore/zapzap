import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../utils/app_theme.dart';

/// The start of a round: the starting player picks how many cards are
/// dealt — 4 to 7, or 4 to 10 in Golden Score (`GAME_RULES.md`). Everyone
/// else waits. The port of
/// `frontend/src/components/Game/HandSizeSelector.jsx`, with 58 × 50
/// targets, a line on what the choice changes and a button that says what
/// it deals (T1, T2 of the UX study).
class GameHandSizeSelector extends StatefulWidget {
  const GameHandSizeSelector({
    super.key,
    required this.isMyTurn,
    required this.currentPlayerName,
    required this.maxSize,
    required this.initialSize,
    this.isGoldenScore = false,
    this.busy = false,
    this.onSelect,
  });

  final bool isMyTurn;

  /// Who the others are waiting for.
  final String currentPlayerName;

  /// 7, or 10 in Golden Score.
  final int maxSize;

  /// What the selector starts on (the middle of the range).
  final int initialSize;

  final bool isGoldenScore;
  final bool busy;
  final ValueChanged<int>? onSelect;

  static Key sizeKey(int size) => ValueKey('handSize-$size');

  @override
  State<GameHandSizeSelector> createState() => _GameHandSizeSelectorState();
}

class _GameHandSizeSelectorState extends State<GameHandSizeSelector> {
  late int _size = widget.initialSize;

  /// Golden Score can end between two rounds (a player is back in the game
  /// on the Rust side), and the range shrinks from 4-10 to 4-7 under a
  /// selector still showing 8, 9 or 10 — which the backend refuses with
  /// `INVALID_HAND_SIZE`.
  @override
  void didUpdateWidget(GameHandSizeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.maxSize != oldWidget.maxSize && _size > widget.maxSize) {
      setState(
        () => _size = widget.initialSize.clamp(minHandSize, widget.maxSize),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!widget.isMyTurn) {
      return Card(
        color: AppColors.slate800,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A still icon, not a spinner: nothing here is loading, and an
              // endless animation never lets a widget test settle.
              const Icon(Icons.hourglass_top, size: 40),
              const SizedBox(height: 16),
              Text(
                l10n.gameHandSizeWaitingTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.gameHandSizeWaitingBody(widget.currentPlayerName),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: AppColors.slate800,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.gameHandSizeTitle,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(l10n.gameHandSizeBody, textAlign: TextAlign.center),
            if (widget.isGoldenScore) ...[
              const SizedBox(height: 4),
              Text(
                l10n.gameHandSizeGoldenHint,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.amber400),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var size = minHandSize; size <= widget.maxSize; size++)
                  _SizeButton(
                    key: GameHandSizeSelector.sizeKey(size),
                    size: size,
                    selected: _size == size,
                    onPressed: widget.busy
                        ? null
                        : () => setState(() => _size = size),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // What the choice changes, not only the figure again (T1).
            Container(
              key: const Key('handSizeHint'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.slate900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.gameHandSizeSelected(_size),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.amber400,
                    ),
                  ),
                  Text(
                    l10n.gameHandSizeEffect,
                    style: const TextStyle(color: AppColors.slate400),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('confirm-hand-size'),
              onPressed: widget.busy || widget.onSelect == null
                  ? null
                  : () => widget.onSelect!(_size),
              child: Text(l10n.gameHandSizeConfirm(_size)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One hand size: a 58 × 50 target (T2 of the UX study), well over the
/// 48 dp minimum, filled amber when picked.
class _SizeButton extends StatelessWidget {
  const _SizeButton({
    super.key,
    required this.size,
    required this.selected,
    this.onPressed,
  });

  final int size;
  final bool selected;
  final VoidCallback? onPressed;

  static const minimum = Size(58, 50);

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const text = TextStyle(fontSize: 19, fontWeight: FontWeight.w500);
    final label = Text('$size');
    return Semantics(
      selected: selected,
      child: selected
          ? FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: minimum,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: label,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                minimumSize: minimum,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
                foregroundColor: AppColors.slate100,
                side: const BorderSide(color: Color(0xFF64748B)),
              ),
              child: label,
            ),
    );
  }
}
