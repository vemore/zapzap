import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../providers/auth_provider.dart';
import '../providers/tutorial_game.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/navigation.dart';
import '../utils/rules.dart';
import '../widgets/game_action_buttons.dart';
import '../widgets/game_hand.dart';
import '../widgets/game_player_table.dart';
import '../widgets/game_table_area.dart';
import '../widgets/game_zapzap_sheet.dart';
import '../widgets/phone_board_layout.dart';

/// The example game (`/tutorial`): the board of [GameScreen] — the same
/// players, felt, hand and moves — fed by a [TutorialGame] instead of the
/// backend, and a coach bubble over the zone each step is played in. A move
/// other than the one asked for is refused with the step's hint. Reachable
/// signed in or not; Skip leaves it at any step.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  /// Where the tutorial is left for: home, which the router sends a
  /// signed-in player on to the parties.
  static const exit = AppRoutes.home;

  /// The board's width at most: the phone column, centred on a wide screen.
  static const maxWidth = 520.0;

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _game = TutorialGame();

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  void _leave() => context.popOrGo(TutorialScreen.exit);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tutorialTitle),
        actions: [
          TextButton(
            key: const Key('tutorial-skip'),
            onPressed: _leave,
            child: Text(l10n.tutorialSkip),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: TutorialScreen.maxWidth,
            ),
            child: ListenableBuilder(
              listenable: _game,
              builder: (context, _) => _board(context, l10n),
            ),
          ),
        ),
      ),
    );
  }

  String _myName(AppLocalizations l10n) =>
      context.read<AuthProvider>().user?.username ?? l10n.tutorialGuestName;

  String _nameOf(int player) => player == TutorialGame.opponent
      ? TutorialGame.opponentName
      : _myName(AppLocalizations.of(context));

  Widget _board(BuildContext context, AppLocalizations l10n) {
    // The opponent's turn: the board as in a game once the player has
    // drawn — not their draw step any more, the felt's message naming each
    // move —, and nothing is played or drawn meanwhile.
    final waiting = _game.opponentMoving;
    final drawing = _game.step.draws && !waiting;
    final values = (
      eligibility: handValue(_game.hand),
      penalty: handValue(_game.hand, penalty: true),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: CustomMultiChildLayout(
        delegate: PhoneBoardLayout(feltFirst: drawing),
        children: [
          LayoutId(
            id: PhoneBoardSlot.players,
            child: _scroll(
              GamePlayerTable(
                seats: [
                  for (final player in [TutorialGame.me, TutorialGame.opponent])
                    GameSeat(
                      playerIndex: player,
                      name: _nameOf(player),
                      // The opponent's hand, scored once ZapZap has held.
                      score: player == TutorialGame.opponent
                          ? _game.opponentScore
                          : 0,
                      cardCount: player == TutorialGame.me
                          ? _game.hand.length
                          : _game.opponentCardCount,
                      isMe: player == TutorialGame.me,
                      isCurrentTurn:
                          player ==
                          (waiting ? TutorialGame.opponent : TutorialGame.me),
                    ),
                ],
              ),
            ),
          ),
          LayoutId(
            id: PhoneBoardSlot.felt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // At most half the felt's height, scrolling past it: the
                // felt keeps the other half whatever the text size.
                if (_coach(l10n, TutorialZone.felt) case final coach?)
                  Flexible(child: SingleChildScrollView(child: coach)),
                Expanded(
                  child: GameTableArea(
                    cardsPlayed: _game.cardsPlayed,
                    lastCardsPlayed: _game.lastCardsPlayed,
                    lastAction: _game.lastAction,
                    playedByMe:
                        _game.lastAction?.playerIndex == TutorialGame.me,
                    playerName: _nameOf,
                    drawPlayedWidth: CardSizes.tablePlayedDraw,
                    step: drawing ? TableStep.draw : TableStep.play,
                    deckSize: _game.deckSize,
                    selectedDiscardCard: _game.selectedDiscardCard,
                    takeCard: _game.selectedDiscardCard,
                    onDiscardTap: drawing ? _game.selectDiscardCard : null,
                    onDeckTap: drawing
                        ? () => _game.draw(fromDeck: true)
                        : null,
                  ),
                ),
              ],
            ),
          ),
          LayoutId(
            id: PhoneBoardSlot.hand,
            child: _scroll(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?_coach(l10n, TutorialZone.hand),
                  GameHand(
                    compact: drawing,
                    cards: _game.hand,
                    selectedCards: _game.selectedCards,
                    eligibilityValue: values.eligibility,
                    penaltyValue: values.penalty,
                    disabled: !_game.handPlayable,
                    onCardTap: _game.toggleCard,
                    onSelectCards: _game.selectCards,
                    onClearSelection: _game.selectedCards.isEmpty
                        ? null
                        : _game.clearSelection,
                  ),
                ],
              ),
            ),
          ),
          LayoutId(
            id: PhoneBoardSlot.actions,
            child: _scroll(
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?_coach(l10n, TutorialZone.actions),
                  // Once ZapZap is called, no move is left to make.
                  if (_game.step.index <= TutorialStep.zapZap.index)
                    GameActionButtons(
                      isMyTurn: !waiting,
                      currentAction: _game.currentAction,
                      currentPlayerName: waiting
                          ? TutorialGame.opponentName
                          : _myName(l10n),
                      selectedCards: _game.selectedCards,
                      invalidPlay: _game.invalidPlay,
                      takeCard: _game.selectedDiscardCard,
                      zapZapRisk: ZapZapRisk(
                        handValue: values.eligibility,
                        scoredValue: values.penalty,
                        activePlayers: 2,
                        eligible: values.eligibility <= zapZapThreshold,
                        holdsJoker: hasJoker(_game.hand),
                      ),
                      onPlay: _game.canPlay ? _game.play : null,
                      onDraw: drawing ? _game.draw : null,
                      onZapZap: _game.step == TutorialStep.zapZap
                          ? _game.zapZap
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scroll(Widget child) => SingleChildScrollView(
    child: Align(alignment: Alignment.topCenter, child: child),
  );

  /// The bubble of the step, over the zone it is played in; `null` over
  /// every other zone.
  Widget? _coach(AppLocalizations l10n, TutorialZone zone) {
    final step = _game.step;
    if (step.zone != zone) return null;
    // The opponent's turn, after a draw: its bubble in the same place, so
    // the felt keeps its size while his moves cross it.
    if (_game.opponentMoving) {
      return CoachBubble(
        text: l10n.tutorialOpponentTurn(TutorialGame.opponentName),
      );
    }
    return CoachBubble(
      text: _text(l10n, step),
      hint: _game.refused ? _hint(l10n, step) : null,
      action: !step.isInfo
          ? null
          : _game.isLast
          ? TextButton(
              key: const Key('tutorial-finish'),
              onPressed: _leave,
              child: Text(l10n.tutorialFinish),
            )
          : TextButton(
              key: const Key('tutorial-next'),
              onPressed: _game.next,
              child: Text(l10n.tutorialNext),
            ),
    );
  }

  String _card(AppLocalizations l10n, int id) => l10n.cardShort(GameCard(id));

  String _text(AppLocalizations l10n, TutorialStep step) => switch (step) {
    TutorialStep.intro => l10n.tutorialIntro(
      handValue(_game.hand),
      zapZapThreshold,
    ),
    TutorialStep.playSingle => l10n.tutorialPlaySingle(
      _card(l10n, TutorialGame.kingSpades),
    ),
    TutorialStep.drawDeck => l10n.tutorialDrawDeck,
    TutorialStep.playPair => l10n.tutorialPlayPair(
      _card(l10n, TutorialGame.nineHearts),
      _card(l10n, TutorialGame.nineClubs),
    ),
    TutorialStep.takePile => l10n.tutorialTakePile(
      TutorialGame.opponentName,
      _card(l10n, TutorialGame.aceClubs),
    ),
    TutorialStep.playRun => l10n.tutorialPlayRun(
      _card(l10n, TutorialGame.fourHearts),
      _card(l10n, TutorialGame.fiveHearts),
    ),
    TutorialStep.drawAgain => l10n.tutorialDrawAgain,
    TutorialStep.zapZap => l10n.tutorialZapZap(
      handValue(_game.hand),
      zapZapThreshold,
    ),
    TutorialStep.held => l10n.tutorialHeld(TutorialGame.opponentName),
    TutorialStep.end => l10n.tutorialEnd(GamePlayerTable.eliminationScore),
  };

  String? _hint(AppLocalizations l10n, TutorialStep step) => switch (step) {
    TutorialStep.playSingle => l10n.tutorialPlaySingleHint(
      _card(l10n, TutorialGame.kingSpades),
    ),
    TutorialStep.drawDeck ||
    TutorialStep.drawAgain => l10n.tutorialDrawDeckHint,
    TutorialStep.playPair => l10n.tutorialPlayPairHint(
      _card(l10n, TutorialGame.nineHearts),
      _card(l10n, TutorialGame.nineClubs),
    ),
    TutorialStep.takePile => l10n.tutorialTakePileHint(
      _card(l10n, TutorialGame.aceClubs),
    ),
    TutorialStep.playRun => l10n.tutorialPlayRunHint(
      _card(l10n, TutorialGame.fourHearts),
      _card(l10n, TutorialGame.fiveHearts),
    ),
    TutorialStep.zapZap => l10n.tutorialZapZapHint,
    _ => null,
  };
}

/// A short instruction over the zone of the board it is about, its tail
/// pointing down at it; under it, once a move was refused, the step's hint;
/// and Next or Finish on a step that asks for no move.
class CoachBubble extends StatelessWidget {
  const CoachBubble({super.key, required this.text, this.hint, this.action});

  final String text;
  final String? hint;
  final Widget? action;

  static const color = AppColors.amber400;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('tutorialCoach'),
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: AppColors.slate800,
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.school, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        key: const Key('tutorialText'),
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            hint!,
                            key: const Key('tutorialHint'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFCA5A5),
                            ),
                          ),
                        ),
                      // Under the text, not beside it: a long one at a large
                      // text size keeps the width.
                      if (action != null)
                        Align(alignment: Alignment.centerRight, child: action),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The tail, pointing at the zone under the bubble.
          const Icon(Icons.arrow_drop_down, size: 22, color: color),
        ],
      ),
    );
  }
}
