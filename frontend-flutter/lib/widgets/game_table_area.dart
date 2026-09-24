import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import 'card_back.dart';
import 'playing_card.dart';

/// Where this player's turn stands, as the felt shows it.
enum TableStep {
  /// Another player is to move.
  waiting,

  /// This player plays: the pile is what can be taken *next*, dimmed.
  play,

  /// This player draws: the felt is the target, pile and deck alike.
  draw,
}

/// The felt: what just happened, the cards laid down this turn, the discard
/// pile — "À prendre ensuite" — and the deck. The port of
/// `frontend/src/components/Game/TableArea.jsx`, reworked by J5 of the UX
/// study: while this player plays, the pile is dimmed; once a draw is owed
/// the felt takes an amber edge and says what to tap, the pile goes to full
/// opacity and the deck becomes a target too.
///
/// Given a height it must fill (tight constraints), it fills it, its
/// content centred; given a loose one, it takes the height its content
/// needs up to that. Either way its content scrolls inside the edge past
/// that.
class GameTableArea extends StatefulWidget {
  const GameTableArea({
    super.key,
    required this.cardsPlayed,
    required this.lastCardsPlayed,
    required this.playerName,
    this.step = TableStep.waiting,
    this.deckSize = 0,
    this.lastAction,
    this.onDiscardTap,
    this.onDeckTap,
    this.selectedDiscardCard,
    this.takeCard,
    this.cardWidth = CardSizes.tablePhone,
  });

  final List<int> cardsPlayed;

  /// The previous player's cards: the discard pile.
  final List<int> lastCardsPlayed;

  /// The name of a seat, for the action message.
  final String Function(int playerIndex) playerName;

  final TableStep step;

  /// How many cards are left in the deck.
  final int deckSize;

  final LastAction? lastAction;

  /// Given only when a draw is owed: the pile is dead otherwise.
  final ValueChanged<int>? onDiscardTap;

  /// Draws from the deck; given only when a draw is owed.
  final VoidCallback? onDeckTap;

  final int? selectedDiscardCard;

  /// The discard card the draw will actually take — the one the button
  /// names —, or `null`: a pick the pile no longer holds gets no hint.
  final int? takeCard;

  final double cardWidth;

  /// How long the "Reshuffled!" banner stays, as React
  /// (`TableArea.jsx:222`).
  static const reshuffleDuration = Duration(milliseconds: 2500);

  /// The edge of the felt while a draw is owed.
  static const drawEdgeColor = AppColors.amber400;

  static Key discardKey(int cardId) => ValueKey('discardCard-$cardId');

  @override
  State<GameTableArea> createState() => _GameTableAreaState();
}

class _GameTableAreaState extends State<GameTableArea> {
  Timer? _reshuffleTimer;
  bool _showReshuffle = false;
  Object? _shownAction;

  @override
  void initState() {
    super.initState();
    _followReshuffle();
  }

  @override
  void didUpdateWidget(GameTableArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followReshuffle();
  }

  @override
  void dispose() {
    _reshuffleTimer?.cancel();
    super.dispose();
  }

  /// A *new* draw that reshuffled the deck raises the banner for 2.5 s.
  void _followReshuffle() {
    final action = widget.lastAction;
    final stamp = action == null
        ? null
        : '${action.type}/${action.playerIndex}/${action.timestamp}';
    if (stamp == _shownAction) return;
    _shownAction = stamp;
    if (action == null || !action.deckReshuffled) return;
    _reshuffleTimer?.cancel();
    setState(() => _showReshuffle = true);
    _reshuffleTimer = Timer(GameTableArea.reshuffleDuration, () {
      if (mounted) setState(() => _showReshuffle = false);
    });
  }

  String? _message(AppLocalizations l10n) {
    final action = widget.lastAction;
    if (action == null) return null;
    final name = widget.playerName(action.playerIndex);
    return switch (action.type) {
      'play' => l10n.gameActionPlayed(
        name,
        action.cardIds.isEmpty
            ? widget.cardsPlayed.length
            : action.cardIds.length,
      ),
      'draw' when action.source == 'played' => l10n.gameActionTookDiscard(name),
      'draw' when action.deckReshuffled => l10n.gameActionDrewReshuffled(name),
      'draw' => l10n.gameActionDrewDeck(name),
      'selectHandSize' => l10n.gameActionSelectedHandSize(
        name,
        action.handSize ?? 0,
      ),
      'zapzap' => l10n.gameActionCalledZapZap(name),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final drawing = widget.step == TableStep.draw;
    // While this player draws, the last action is their own play, which
    // the "Posées" row shows already: the draw hint takes the line.
    final message = drawing ? null : _message(l10n);
    final take = widget.takeCard;
    return Stack(
      // Passes a tight height down to the felt, which then fills it.
      fit: StackFit.passthrough,
      children: [
        Container(
          key: const Key('gameTable'),
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.table, AppColors.tableLight],
            ),
            borderRadius: BorderRadius.circular(12),
            border: drawing
                ? Border.all(color: GameTableArea.drawEdgeColor, width: 2)
                : Border.all(color: AppColors.tableLight),
          ),
          // The content scrolls inside the edge: a felt given less height
          // than it needs keeps its whole border, amber in the draw step,
          // instead of being cut by a scroll view around it.
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              key: const Key('gameTableScroll'),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.hasTightHeight ? box.maxHeight : 0,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            message,
                            key: const Key('tableMessage'),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF86EFAC),
                            ),
                          ),
                        ),
                      if (drawing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            l10n.gameTableDrawHint,
                            key: const Key('drawInstruction'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFFFDE68A),
                            ),
                          ),
                        ),
                      if (widget.cardsPlayed.isNotEmpty) ...[
                        _label(l10n.gameTablePlayedLabel),
                        _cards(
                          widget.cardsPlayed,
                          (id) => PlayingCard(
                            cardId: id,
                            width: widget.cardWidth,
                            disabled: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      // The pile and the deck side by side, the deck folding under
                      // the pile when the pile is long.
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        spacing: 18,
                        runSpacing: 6,
                        children: [_pile(l10n), _deck(l10n)],
                      ),
                      if (drawing && take != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _takeHint(l10n, GameCard(take)),
                            key: const Key('takeHint'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFFBBF7D0),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showReshuffle)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  key: const Key('reshuffleBanner'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber500,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    l10n.gameReshuffled,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.slate900,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// What taking [card] does to the hand. A joker counts 0 towards ZapZap
  /// but 25 at the end of the round for anyone without the lowest hand
  /// (`GAME_RULES.md`), so it is never "no points".
  String _takeHint(AppLocalizations l10n, GameCard card) => card.isJoker
      ? l10n.gameTableTakeJokerHint(l10n.cardShort(card))
      : l10n.gameTableTakeHint(card.value(), l10n.cardShort(card));

  /// The previous player's cards: what the next draw may take. A card is
  /// tappable — and at full opacity — only while this player draws.
  Widget _pile(AppLocalizations l10n) => Column(
    key: const Key('discardPile'),
    mainAxisSize: MainAxisSize.min,
    children: [
      _label(l10n.gameTableNextLabel, key: const Key('discardLabel')),
      if (widget.lastCardsPlayed.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            l10n.gameTableEmpty,
            style: const TextStyle(fontSize: 12, color: AppColors.slate400),
          ),
        )
      else
        _cards(
          widget.lastCardsPlayed,
          (id) => PlayingCard(
            key: GameTableArea.discardKey(id),
            cardId: id,
            width: widget.cardWidth,
            selected: widget.selectedDiscardCard == id,
            disabled: widget.onDiscardTap == null,
            onTap: widget.onDiscardTap == null
                ? null
                : () => widget.onDiscardTap!(id),
          ),
        ),
    ],
  );

  /// The deck: a target in the draw step, as the pile is, dimmed otherwise.
  Widget _deck(AppLocalizations l10n) {
    final onTap = widget.onDeckTap;
    return TextButton(
      key: const Key('draw-deck'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.all(4),
        foregroundColor: AppColors.slate100,
        disabledForegroundColor: AppColors.slate400,
      ),
      child: Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CardBack(size: CardBackSize.md),
            const SizedBox(height: 3),
            Text(
              l10n.gameDeckLabel(widget.deckSize),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      key: key,
      style: const TextStyle(fontSize: 11, color: AppColors.slate400),
    ),
  );

  /// A `Wrap`, not a `Row`: a long pile folds onto a second line instead of
  /// overflowing a phone.
  Widget _cards(List<int> cards, Widget Function(int cardId) build) => Wrap(
    alignment: WrapAlignment.center,
    spacing: 4,
    runSpacing: 4,
    children: [for (final id in cards) build(id)],
  );
}
