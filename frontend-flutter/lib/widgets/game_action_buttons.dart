import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/rules.dart';
import 'game_zapzap_sheet.dart';

/// Where a turn step stands in the step indicator.
enum TurnStepState { current, pending, done }

/// The turn read at a glance (`GAME_RULES.md`, Turn Flow: play, then draw):
/// the step indicator ① Jouer → ② Piocher — or whom the board waits for —,
/// one full-width button that names the move, why the selection cannot be
/// played, and ZapZap, always there, disabled with its reason and asking
/// before it calls. The port of `frontend/src/components/Game/ActionButtons.jsx`,
/// reworked by J1, J2 and J4 of the UX study.
class GameActionButtons extends StatelessWidget {
  const GameActionButtons({
    super.key,
    required this.isMyTurn,
    required this.currentAction,
    required this.currentPlayerName,
    required this.zapZapRisk,
    this.selectedCards = const [],
    this.invalidPlay,
    this.takeCard,
    this.onPlay,
    this.onDraw,
    this.onZapZap,
  });

  final bool isMyTurn;
  final GameAction currentAction;

  /// Who the board is waiting for, shown when it is not this player.
  final String currentPlayerName;

  /// The cards tapped, which the Play button names.
  final List<int> selectedCards;

  /// Why the selection is refused, from `analyzePlay`; the reason is shown
  /// under the button and the board stays.
  final PlayError? invalidPlay;

  /// The discard card the draw will take; `null` draws from the deck.
  final int? takeCard;

  /// What a ZapZap now would cost if counteracted, and whether the hand
  /// allows one.
  final ZapZapRisk zapZapRisk;

  /// `null` disables the button.
  final VoidCallback? onPlay;
  final VoidCallback? onDraw;

  /// Called once the player has confirmed on the sheet; `null` disables
  /// the button.
  final VoidCallback? onZapZap;

  static Key stepKey(String step) => ValueKey('turnStep-$step');

  bool get _drawStep => currentAction == GameAction.draw;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: AppColors.slate800,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMyTurn) _steps(l10n) else _waiting(l10n),
            const SizedBox(height: 8),
            _primary(l10n),
            if (invalidPlay != null) ...[
              const SizedBox(height: 6),
              _refusal(l10n),
            ],
            const SizedBox(height: 6),
            _zapZap(context, l10n),
          ],
        ),
      ),
    );
  }

  Widget _steps(AppLocalizations l10n) => Row(
    key: const Key('turnSteps'),
    children: [
      Flexible(
        child: TurnStepChip(
          key: stepKey('play'),
          label: _drawStep ? l10n.gameStepPlayDone : l10n.gameStepPlay,
          state: _drawStep ? TurnStepState.done : TurnStepState.current,
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Icon(Icons.arrow_forward, size: 14, color: AppColors.slate400),
      ),
      Flexible(
        child: TurnStepChip(
          key: stepKey('draw'),
          label: l10n.gameStepDraw,
          state: _drawStep ? TurnStepState.current : TurnStepState.pending,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          l10n.gameStepYourTurn,
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: AppColors.slate400),
        ),
      ),
    ],
  );

  Widget _waiting(AppLocalizations l10n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.slate700,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.schedule, size: 16, color: AppColors.slate400),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            l10n.gameTurnWaiting(currentPlayerName),
            key: const Key('turnBanner'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.slate400,
            ),
          ),
        ),
      ],
    ),
  );

  /// One button for the step at hand: Play, naming the cards it lays down,
  /// or Draw — Take, naming the discard card, once one is picked.
  Widget _primary(AppLocalizations l10n) {
    final draw = isMyTurn && _drawStep;
    final label = draw
        ? takeCard == null
              ? l10n.gameDrawButton
              : l10n.gameMoveTake(l10n.cardShort(GameCard(takeCard!)))
        : invalidPlay == null && selectedCards.isNotEmpty
        ? l10n.playMoveLabel(selectedCards)
        : l10n.gameMovePlay;
    return FilledButton.icon(
      key: Key(draw ? 'draw-card' : 'play-cards'),
      onPressed: draw ? onDraw : onPlay,
      style: FilledButton.styleFrom(
        // One colour for the move at hand, the theme's primary: the step
        // chips say which step it is.
        backgroundColor: AppColors.amber500,
        foregroundColor: AppColors.slate900,
        disabledBackgroundColor: AppColors.slate700,
        disabledForegroundColor: AppColors.slate400,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      icon: Icon(draw ? Icons.download : Icons.play_arrow),
      // Scaled down rather than wrapped: the button keeps one line at any
      // text size.
      label: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, key: const Key('primaryMoveLabel'), maxLines: 1),
      ),
    );
  }

  Widget _refusal(AppLocalizations l10n) => Container(
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
  );

  /// Always shown: when it cannot be called, it says why instead of
  /// greying out without a word.
  Widget _zapZap(BuildContext context, AppLocalizations l10n) {
    final risk = zapZapRisk;
    final String label;
    if (!risk.eligible) {
      label = l10n.gameZapZapNeedLow(risk.handValue, zapZapThreshold);
    } else if (!isMyTurn || currentAction != GameAction.play) {
      label = l10n.gameZapZapNotNow;
    } else {
      label = l10n.gameZapZapButton;
    }
    final call = onZapZap;
    return FilledButton.icon(
      key: const Key('call-zapzap'),
      onPressed: call == null
          ? null
          : () async {
              if (await confirmZapZap(context, risk)) call();
            },
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.amber400,
        foregroundColor: AppColors.slate900,
        disabledBackgroundColor: AppColors.slate700,
        disabledForegroundColor: AppColors.slate400,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      icon: const Icon(Icons.bolt, size: 18),
      label: Text(
        label,
        key: const Key('zapzapLabel'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// One step of the indicator: amber while it is the step to take, grey
/// before it comes and once it is done (then with a check, from its
/// label).
class TurnStepChip extends StatelessWidget {
  const TurnStepChip({super.key, required this.label, required this.state});

  final String label;
  final TurnStepState state;

  static const currentColor = AppColors.amber500;
  static const otherColor = AppColors.slate700;

  @override
  Widget build(BuildContext context) {
    final current = state == TurnStepState.current;
    return Semantics(
      selected: current,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: current ? currentColor : otherColor,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: current ? AppColors.slate900 : AppColors.slate400,
          ),
        ),
      ),
    );
  }
}
