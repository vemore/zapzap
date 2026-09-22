import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../utils/app_theme.dart';

/// The start of a round: the starting player picks how many cards are
/// dealt — 4 to 7, or 4 to 10 in Golden Score (`GAME_RULES.md`). Everyone
/// else waits. The port of
/// `frontend/src/components/Game/HandSizeSelector.jsx`.
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
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var size = minHandSize; size <= widget.maxSize; size++)
                  ChoiceChip(
                    key: GameHandSizeSelector.sizeKey(size),
                    label: Text('$size'),
                    selected: _size == size,
                    onSelected: widget.busy
                        ? null
                        : (_) => setState(() => _size = size),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.gameHandSizeSelected(_size),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.amber400,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('confirm-hand-size'),
              onPressed: widget.busy || widget.onSelect == null
                  ? null
                  : () => widget.onSelect!(_size),
              child: Text(l10n.gameHandSizeConfirm),
            ),
          ],
        ),
      ),
    );
  }
}
