import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/rules.dart';

/// Whose turn it is, why the selection cannot be played, and the three
/// moves: Play, Draw (or Take, when a discard card is selected) and ZapZap.
/// The port of `frontend/src/components/Game/ActionButtons.jsx`.
class GameActionButtons extends StatelessWidget {
  const GameActionButtons({
    super.key,
    required this.isMyTurn,
    required this.currentAction,
    required this.currentPlayerName,
    required this.selectedCount,
    this.invalidPlay,
    this.takeFromDiscard = false,
    this.onPlay,
    this.onDraw,
    this.onZapZap,
  });

  final bool isMyTurn;
  final GameAction currentAction;

  /// Who the board is waiting for, shown when it is not this player.
  final String currentPlayerName;

  final int selectedCount;

  /// Why the selection is refused, from `analyzePlay`; the reason is shown
  /// and the board stays — the point of this screen.
  final PlayError? invalidPlay;

  /// The Draw button becomes Take: a discard card is selected.
  final bool takeFromDiscard;

  /// `null` disables the button.
  final VoidCallback? onPlay;
  final VoidCallback? onDraw;
  final VoidCallback? onZapZap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final banner = isMyTurn
        ? currentAction == GameAction.draw
              ? l10n.gameTurnDraw
              : l10n.gameTurnPlay
        : l10n.gameTurnWaiting(currentPlayerName);

    return Card(
      color: AppColors.slate800,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: isMyTurn
                    ? const Color(0xFF166534).withValues(alpha: 0.35)
                    : AppColors.slate700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isMyTurn ? Icons.auto_awesome : Icons.schedule,
                    size: 16,
                    color: isMyTurn
                        ? const Color(0xFF4ADE80)
                        : AppColors.slate400,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      banner,
                      key: const Key('turnBanner'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isMyTurn
                            ? const Color(0xFF4ADE80)
                            : AppColors.slate400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (invalidPlay != null) ...[
              const SizedBox(height: 6),
              Container(
                key: const Key('invalidPlayReason'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.error),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.playErrorMessage(invalidPlay!),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    buttonKey: const Key('play-cards'),
                    icon: Icons.play_arrow,
                    label: selectedCount > 0
                        ? l10n.gamePlayButtonCount(selectedCount)
                        : l10n.gamePlayButton,
                    onPressed: onPlay,
                    background: AppColors.amber500,
                    foreground: AppColors.slate900,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    buttonKey: const Key('draw-card'),
                    icon: Icons.download,
                    label: takeFromDiscard
                        ? l10n.gameTakeButton
                        : l10n.gameDrawButton,
                    onPressed: onDraw,
                    background: takeFromDiscard
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF2563EB),
                    foreground: AppColors.slate100,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _ActionButton(
                    buttonKey: const Key('call-zapzap'),
                    icon: Icons.bolt,
                    label: l10n.gameZapZapButton,
                    onPressed: onZapZap,
                    background: AppColors.amber400,
                    foreground: AppColors.slate900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    key: buttonKey,
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      // The theme's 200 px minimum would not fit three buttons on a phone.
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    // Scaled down rather than wrapped: the row of three must hold at any
    // text size.
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 4),
          Text(label, maxLines: 1),
        ],
      ),
    ),
  );
}
