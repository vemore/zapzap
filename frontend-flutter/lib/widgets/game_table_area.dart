import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/card.dart';
import '../models/game_state.dart';
import '../utils/app_theme.dart';
import '../utils/card_l10n.dart';
import '../utils/motion.dart';
import 'card_back.dart';
import 'felt_painter.dart';
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
/// A card that comes onto the felt — played this turn, or straight onto
/// the pile by a player who played and drew in one go — glides in (J9 of
/// the UX study): up from the hand when this player played it, down from
/// the players otherwise. A card already on the felt, going from the
/// played row to the pile, does not move again. Nothing glides under
/// reduced motion ([Motion]).
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
    this.drawPlayedWidth,
    this.playedByMe = false,
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

  /// The width of the cards played this turn while this player draws —
  /// by default [cardWidth]. On a phone they are smaller then: a reminder
  /// of this player's own play beside the pile and the deck, the targets,
  /// the height they leave going to the hand.
  final double? drawPlayedWidth;

  /// The last move was this player's: the cards it brought glide up from
  /// the hand, under the felt, instead of down from the players.
  final bool playedByMe;

  /// How far, in card heights, a card starts from where it lands.
  static const glideDistance = 1.5;

  /// The key of the glide around card [cardId], while it glides in.
  static Key glideKey(int cardId) => ValueKey('feltGlide-$cardId');

  /// How long the "Reshuffled!" banner stays, as React
  /// (`TableArea.jsx:222`).
  static const reshuffleDuration = Duration(milliseconds: 2500);

  /// The edge of the felt while a draw is owed.
  static const drawEdgeColor = AppColors.amber400;

  /// The dark wood rim around the felt, and the felt's corner radius.
  static const rimWidth = 6.0;
  static const feltRadius = 8.0;

  /// The room between the felt's edge and its content: the rim takes 6 px
  /// a side the plain felt did not, so the felt gives some back.
  static const feltPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 4);

  static Key discardKey(int cardId) => ValueKey('discardCard-$cardId');

  /// The small card beside the message naming a card taken from the pile.
  static const takenCardWidth = 24.0;

  @override
  State<GameTableArea> createState() => _GameTableAreaState();
}

class _GameTableAreaState extends State<GameTableArea> {
  Timer? _reshuffleTimer;
  bool _showReshuffle = false;
  Object? _shownAction;

  /// The cards gliding in, and where from: below (the hand) or above.
  final Map<int, bool> _gliding = {};

  @override
  void initState() {
    super.initState();
    _followReshuffle();
  }

  @override
  void didUpdateWidget(GameTableArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followReshuffle();
    _followArrivals(oldWidget);
  }

  /// The cards on the felt now that were not on it before glide in; a card
  /// gone from the felt stops. The first table drawn does not glide: it was
  /// not just played.
  void _followArrivals(GameTableArea oldWidget) {
    final now = {...widget.cardsPlayed, ...widget.lastCardsPlayed};
    _gliding.removeWhere((id, _) => !now.contains(id));
    if (!Motion.enabled(context)) {
      _gliding.clear();
      return;
    }
    final before = {...oldWidget.cardsPlayed, ...oldWidget.lastCardsPlayed};
    for (final id in now.difference(before)) {
      _gliding[id] = widget.playedByMe;
    }
  }

  /// [card], gliding in if it just came onto the felt.
  Widget _landing(int id, Widget card) {
    final fromBelow = _gliding[id];
    if (fromBelow == null) return card;
    return _Glide(
      key: GameTableArea.glideKey(id),
      from: Offset(
        0,
        fromBelow ? GameTableArea.glideDistance : -GameTableArea.glideDistance,
      ),
      // Done: it stays where it landed, with no wrapper left to restart.
      onDone: () => _gliding.remove(id),
      child: card,
    );
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

  /// The card the last action took from the discard pile — public, it lay
  /// face up —, or `null`. A deck draw never names its card, even when the
  /// server were to send one (the Node backend did, until its removal).
  int? _takenCard() {
    final action = widget.lastAction;
    if (action == null || action.type != 'draw') return null;
    return action.source == 'played' ? action.cardId : null;
  }

  String? _message(AppLocalizations l10n) {
    final action = widget.lastAction;
    if (action == null) return null;
    final name = widget.playerName(action.playerIndex);
    final taken = _takenCard();
    return switch (action.type) {
      'play' => l10n.gameActionPlayed(
        name,
        action.cardIds.isEmpty
            ? widget.cardsPlayed.length
            : action.cardIds.length,
      ),
      'draw' when taken != null => l10n.gameActionTookDiscardCard(
        name,
        l10n.cardName(GameCard(taken)),
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
    final taken = message == null ? null : _takenCard();
    final take = widget.takeCard;
    final edge = drawing ? GameTableArea.drawEdgeColor : AppColors.rimInlay;
    final edgeWidth = drawing ? 2.0 : 1.0;
    return Stack(
      // Passes a tight height down to the felt, which then fills it.
      fit: StackFit.passthrough,
      children: [
        Container(
          key: const Key('feltRim'),
          width: double.infinity,
          padding: const EdgeInsets.all(GameTableArea.rimWidth),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.rimLight, AppColors.rimDark],
            ),
            borderRadius: BorderRadius.circular(
              GameTableArea.feltRadius + GameTableArea.rimWidth,
            ),
            // In the draw step the rim glows amber around the amber edge.
            boxShadow: [
              drawing
                  ? BoxShadow(
                      color: GameTableArea.drawEdgeColor.withValues(
                        alpha: 0.45,
                      ),
                      blurRadius: 8,
                    )
                  : const BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
            ],
          ),
          child: Container(
            key: const Key('gameTable'),
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                radius: 0.9,
                colors: [AppColors.feltCenter, AppColors.feltEdge],
              ),
              borderRadius: BorderRadius.circular(GameTableArea.feltRadius),
              // The edge sits on the rim's inner lip, above the texture —
              // which paints inside it —: amber and 2 px in the draw step.
              border: Border.all(color: edge, width: edgeWidth),
            ),
            child: CustomPaint(
              painter: FeltPainter(
                watermark: l10n.appTitle,
                radius: GameTableArea.feltRadius - edgeWidth,
              ),
              child: RepaintBoundary(
                child: Padding(
                  padding: GameTableArea.feltPadding,
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
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
                                      // The card taken from the pile, small:
                                      // it has left the felt, the message
                                      // keeps it in sight.
                                      if (taken != null) ...[
                                        const SizedBox(width: 6),
                                        PlayingCard(
                                          key: const Key('tableMessageCard'),
                                          cardId: taken,
                                          width: GameTableArea.takenCardWidth,
                                          disabled: true,
                                          dimmed: false,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              if (drawing)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
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
                                  (id) => _landing(
                                    id,
                                    PlayingCard(
                                      cardId: id,
                                      width: drawing
                                          ? widget.drawPlayedWidth ??
                                                widget.cardWidth
                                          : widget.cardWidth,
                                      disabled: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
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
          (id) => _landing(
            id,
            PlayingCard(
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
        ),
    ],
  );

  /// The deck: a target in the draw step, as the pile is, greyed otherwise.
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Greyed, not transparent: the felt would show through the back.
          if (onTap == null)
            const ColorFiltered(
              colorFilter: PlayingCard.greyed,
              child: CardBack(size: CardBackSize.md),
            )
          else
            const CardBack(size: CardBackSize.md),
          const SizedBox(height: 3),
          Text(
            l10n.gameDeckLabel(widget.deckSize),
            style: const TextStyle(fontSize: 11),
          ),
        ],
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

/// A card gliding [from] an offset, in card sizes, to where it lies, fading
/// in over the first half of the way; run once, when it is built.
class _Glide extends StatefulWidget {
  const _Glide({
    super.key,
    required this.from,
    required this.onDone,
    required this.child,
  });

  final Offset from;
  final VoidCallback onDone;
  final Widget child;

  @override
  State<_Glide> createState() => _GlideState();
}

class _GlideState extends State<_Glide> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.glide,
  );
  late final Animation<Offset> _offset = Tween(
    begin: widget.from,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted && _controller.isCompleted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
    position: _offset,
    child: FadeTransition(opacity: _opacity, child: widget.child),
  );
}
