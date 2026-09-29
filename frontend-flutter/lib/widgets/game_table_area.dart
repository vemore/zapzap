import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// This player plays: the pile is what can be taken *next*, not a target yet.
  play,

  /// This player draws: the felt is the target, pile and deck alike.
  draw,
}

/// The felt: what just happened, the cards laid down this turn, the discard
/// pile — "À prendre ensuite" — and the deck. The port of
/// `frontend/src/components/Game/TableArea.jsx`, reworked by J5 of the UX
/// study: while this player plays, the pile is only shown; once a draw is
/// owed the felt takes an amber edge and says what to tap, and the pile's
/// cards and the deck take the light edge of a target ([PlayingCard]).
///
/// A card that comes onto the felt — played this turn, or straight onto
/// the pile by a player who played and drew in one go — glides in (J9 of
/// the UX study): up from the hand when this player played it, down from
/// the players otherwise. A card already on the felt, going from the
/// played row to the pile, slides from the one to the other and is not
/// taken for a new card. A card that leaves the felt does not vanish: the
/// one a draw took from the pile — or a card back off the deck — moves on
/// toward the player who took it, down to the hand for this player, up
/// to the players otherwise, fading out; the rest of the pile, gone to the
/// discard, fades out where it lay. Nothing moves under reduced motion
/// ([Motion]).
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
    this.playedBeside = false,
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

  /// The cards played this turn beside the pile and the deck, their labels
  /// in line, rather than above them: a wide board's felt has the width,
  /// and a laptop window not the height of two rows of cards over the hand
  /// (1366x768). They fold above the pile when the felt is too narrow.
  final bool playedBeside;

  /// The last move was this player's: the cards it brought glide up from
  /// the hand, under the felt, instead of down from the players, and a
  /// card it took leaves down toward the hand.
  final bool playedByMe;

  /// How far, in card heights, a card starts from where it lands.
  static const glideDistance = 1.5;

  /// The key of the glide around card [cardId], while it glides in.
  static Key glideKey(int cardId) => ValueKey('feltGlide-$cardId');

  /// The key of card [cardId] while it slides from the played row to the
  /// pile.
  static Key slideKey(int cardId) => ValueKey('feltSlide-$cardId');

  /// The key of card [cardId]'s image while it leaves the felt.
  static Key leavingKey(int cardId) => ValueKey('feltLeaving-$cardId');

  /// The key of the card back leaving the deck after a deck draw.
  static const deckLeavingKey = ValueKey('feltLeaving-deck');

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

class _GameTableAreaState extends State<GameTableArea>
    with TickerProviderStateMixin {
  Timer? _reshuffleTimer;
  bool _showReshuffle = false;
  Object? _shownAction;

  /// The cards gliding in, and where from: below (the hand) or above.
  final Map<int, bool> _gliding = {};

  /// Every card on the felt, and the deck's top card ([_deckSlot]), as laid
  /// out: where each was is read before the felt changes.
  final Map<int, RenderBox> _slots = {};

  /// The slot of the deck's top card in [_slots]: no card has this id.
  static const _deckSlot = -1;

  /// The cards sliding from the played row to the pile, and where each
  /// was, in the felt's coordinates.
  final Map<int, Rect> _sliding = {};

  /// The images of the cards leaving the felt.
  final List<_Leaving> _leaving = [];

  late final AnimationController _shift = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(_sliding.clear);
      }
    });

  late final AnimationController _leave = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(_leaving.clear);
      }
    });

  @override
  void initState() {
    super.initState();
    _followReshuffle();
  }

  @override
  void didUpdateWidget(GameTableArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _followReshuffle();
    _followMoves(oldWidget);
    _followArrivals(oldWidget);
  }

  /// The felt's own box: the coordinates the moves are measured in.
  RenderBox? get _felt {
    final box = context.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  /// Where [box] lies on the felt, or `null` when it is not laid out.
  Rect? _rectOf(RenderBox box, RenderBox felt) {
    if (!box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: felt) & box.size;
  }

  /// Read before the new felt is built, while the boxes still lie where
  /// the last one put them: the cards going from the played row to the
  /// pile slide there, a card taken from the pile moves on toward its
  /// taker, the rest of the pile fades out, and a deck draw sends a card
  /// back off the deck. Only a play or a draw moves cards so: a new round
  /// lays a new table.
  void _followMoves(GameTableArea oldWidget) {
    final action = widget.lastAction;
    final felt = _felt;
    if (felt == null ||
        action == null ||
        (action.type != 'play' && action.type != 'draw')) {
      return;
    }
    final shift = Motion.of(context, Motion.shift);
    final leave = Motion.of(context, Motion.leave);
    if (shift == Duration.zero || leave == Duration.zero) return;

    Rect? was(int id) {
      final box = _slots[id];
      return box == null ? null : _rectOf(box, felt);
    }

    final sliding = <int, Rect>{};
    final pile = widget.lastCardsPlayed.toSet();
    for (final id in oldWidget.cardsPlayed) {
      final rect = pile.contains(id) ? was(id) : null;
      if (rect != null) sliding[id] = rect;
    }

    final taken = action.type == 'draw' && action.source == 'played'
        ? action.cardId
        : null;
    final now = {...widget.cardsPlayed, ...pile};
    final leaving = <_Leaving>[
      for (final id in {...oldWidget.cardsPlayed, ...oldWidget.lastCardsPlayed})
        if (!now.contains(id))
          if (was(id) case final rect?)
            _Leaving(
              key: GameTableArea.leavingKey(id),
              rect: rect,
              cardId: id,
              towardTaker: id == taken,
              down: widget.playedByMe,
            ),
    ];
    final newDraw =
        action.type == 'draw' &&
        action.source != 'played' &&
        _stamp(action) != _stamp(oldWidget.lastAction);
    if (newDraw) {
      if (was(_deckSlot) case final rect?) {
        leaving.add(
          _Leaving(
            key: GameTableArea.deckLeavingKey,
            rect: rect,
            towardTaker: true,
            down: widget.playedByMe,
          ),
        );
      }
    }

    if (sliding.isNotEmpty) {
      _sliding
        ..clear()
        ..addAll(sliding);
      _shift
        ..duration = shift
        ..forward(from: 0);
    }
    if (leaving.isNotEmpty) {
      _leaving
        ..clear()
        ..addAll(leaving);
      _leave
        ..duration = leave
        ..forward(from: 0);
    }
  }

  /// What tells one action from the next.
  static String? _stamp(LastAction? action) => action == null
      ? null
      : '${action.type}/${action.playerIndex}/${action.timestamp}';

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

  /// [card] in its slot on the felt: gliding in if it just came onto it,
  /// sliding over from the played row if it just went to the pile.
  Widget _landing(int id, Widget card) {
    final from = _sliding[id];
    return _FeltSlot(
      key: from == null ? null : GameTableArea.slideKey(id),
      id: id,
      slots: _slots,
      felt: () => _felt,
      from: from,
      progress: from == null ? null : _shift,
      child: _glidingIn(id, card),
    );
  }

  /// [card], gliding in if it just came onto the felt.
  Widget _glidingIn(int id, Widget card) {
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
    _shift.dispose();
    _leave.dispose();
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
    final played = widget.cardsPlayed.isEmpty
        ? null
        : Column(
            key: const Key('playedCards'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _label(l10n.gameTablePlayedLabel),
              _cards(
                widget.cardsPlayed,
                (id) => _landing(
                  id,
                  PlayingCard(
                    cardId: id,
                    width: drawing
                        ? widget.drawPlayedWidth ?? widget.cardWidth
                        : widget.cardWidth,
                    disabled: true,
                  ),
                ),
              ),
            ],
          );
    final edge = drawing ? GameTableArea.drawEdgeColor : AppColors.rimInlay;
    final edgeWidth = drawing ? 2.0 : 1.0;
    return Stack(
      // Passes a tight height down to the felt, which then fills it.
      fit: StackFit.passthrough,
      // A card leaving toward its taker goes past the rim.
      clipBehavior: Clip.none,
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
                              if (played != null && !widget.playedBeside) ...[
                                played,
                                const SizedBox(height: 2),
                              ],
                              // The pile and the deck side by side, the deck folding under
                              // the pile when the pile is long.
                              // Their labels and their top cards line up.
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.start,
                                spacing: 18,
                                runSpacing: 6,
                                children: [
                                  if (played != null && widget.playedBeside)
                                    played,
                                  _pile(l10n),
                                  _deck(l10n),
                                ],
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
        for (final card in _leaving)
          Positioned.fromRect(
            rect: card.rect,
            child: IgnorePointer(
              child: _LeavingCard(key: card.key, card: card, progress: _leave),
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

  /// The deck: a card back as wide as the pile's cards, labelled above as
  /// the pile is, over the edges of the cards under it — fewer as the deck
  /// runs low. A target in the draw step, with a playable card's edge
  /// ([PlayingCard.edgeFor]); plain, in its colours, otherwise.
  Widget _deck(AppLocalizations l10n) {
    final onTap = widget.onDeckTap;
    final width = widget.cardWidth;
    final height = PlayingCard.heightFor(width);
    final radius = BorderRadius.circular(PlayingCard.radiusFor(width));
    final look = onTap == null ? CardLook.plain : CardLook.playable;
    const step = CardSizes.deckLayerStep;
    final layers = widget.deckSize > 10
        ? 2
        : widget.deckSize > 1
        ? 1
        : 0;
    return TextButton(
      key: const Key('draw-deck'),
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      // The felt's text style, not the button's: the label reads as the
      // pile's does.
      child: DefaultTextStyle(
        style: DefaultTextStyle.of(context).style,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _label(
              l10n.gameDeckLabel(widget.deckSize),
              key: const Key('deckLabel'),
            ),
            SizedBox(
              key: const Key('deckStack'),
              width: width + 2 * step,
              height: height + 2 * step,
              child: Stack(
                children: [
                  // The cards under the top one: their edges, deepest first.
                  for (var i = layers; i >= 1; i--)
                    Positioned(
                      left: i * step,
                      top: i * step,
                      child: Container(
                        key: Key('deckLayer$i'),
                        width: width,
                        height: height,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5E7EB),
                          borderRadius: radius,
                          border: Border.all(
                            color: const Color(0xFF9CA3AF),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _FeltSlot(
                    id: _deckSlot,
                    slots: _slots,
                    felt: () => _felt,
                    child: Container(
                      key: const Key('deckTop'),
                      foregroundDecoration: PlayingCard.edgeFor(look, radius),
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        boxShadow: PlayingCard.shadowFor(look),
                      ),
                      child: CardBack(width: width),
                    ),
                  ),
                ],
              ),
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

/// A card on the felt, or the deck's top card: it keeps its box in
/// [slots] under [id] while it is laid out, so the felt can tell where it
/// was once it has moved. Given [from] and [progress], it slides from
/// [from] — a rect in the felt's coordinates — to where it lies now,
/// taking the size it has there, as [progress] runs from 0 to 1.
class _FeltSlot extends SingleChildRenderObjectWidget {
  const _FeltSlot({
    super.key,
    required this.id,
    required this.slots,
    required this.felt,
    this.from,
    this.progress,
    super.child,
  });

  final int id;
  final Map<int, RenderBox> slots;
  final RenderBox? Function() felt;
  final Rect? from;
  final Animation<double>? progress;

  @override
  _RenderFeltSlot createRenderObject(BuildContext context) => _RenderFeltSlot(
    id: id,
    slots: slots,
    felt: felt,
    from: from,
    progress: progress,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderFeltSlot renderObject) {
    renderObject
      ..id = id
      ..felt = felt
      ..from = from
      ..progress = progress;
  }
}

/// Paints its child where [from] and the child's place meet at
/// [progress]: the new place is known only once laid out, so the slide is
/// worked out at paint time, not at build time.
class _RenderFeltSlot extends RenderProxyBox {
  _RenderFeltSlot({
    required this._id,
    required this.slots,
    required this.felt,
    this._from,
    this._progress,
  });

  final Map<int, RenderBox> slots;
  RenderBox? Function() felt;

  int _id;
  set id(int value) {
    if (value == _id) return;
    if (slots[_id] == this) slots.remove(_id);
    _id = value;
    if (attached) slots[_id] = this;
  }

  Rect? _from;
  set from(Rect? value) {
    if (value == _from) return;
    _from = value;
    markNeedsPaint();
  }

  Animation<double>? _progress;
  set progress(Animation<double>? value) {
    if (value == _progress) return;
    if (attached) _progress?.removeListener(markNeedsPaint);
    _progress = value;
    if (attached) _progress?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    slots[_id] = this;
    _progress?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    if (slots[_id] == this) slots.remove(_id);
    _progress?.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Where the child is drawn relative to where it lies, or `null` when
  /// it lies where it is drawn.
  Matrix4? get _shift {
    final from = _from;
    final progress = _progress;
    final felt = this.felt();
    if (from == null ||
        progress == null ||
        progress.isCompleted ||
        felt == null ||
        !hasSize ||
        size.width == 0) {
      return null;
    }
    final t = Curves.easeInOutCubic.transform(progress.value);
    final lies = localToGlobal(Offset.zero, ancestor: felt);
    final offset = (from.topLeft - lies) * (1 - t);
    final scale = from.width / size.width * (1 - t) + t;
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(offset.dx, offset.dy, 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shift = _shift;
    if (shift == null) return super.paint(context, offset);
    context.pushTransform(needsCompositing, offset, shift, super.paint);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    if (shift != null) transform.multiply(shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final shift = _shift;
    if (shift == null) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintTransform(
      transform: shift,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }
}

/// A card leaving the felt: where it lay, and whether it goes on toward
/// the player who took it — [down] to the hand when that is this player —
/// or, gone to the discard, fades out where it lay. No [cardId]: a card
/// back off the deck.
class _Leaving {
  const _Leaving({
    required this.key,
    required this.rect,
    required this.towardTaker,
    required this.down,
    this.cardId,
  });

  final Key key;
  final Rect rect;
  final bool towardTaker;
  final bool down;
  final int? cardId;
}

/// The image of a card leaving the felt, as [progress] runs from 0 to 1.
class _LeavingCard extends StatelessWidget {
  const _LeavingCard({super.key, required this.card, required this.progress});

  final _Leaving card;
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final id = card.cardId;
    final face = id == null
        ? CardBack(width: card.rect.width)
        : PlayingCard(cardId: id, width: card.rect.width, disabled: true);
    final fade = FadeTransition(
      opacity: ReverseAnimation(
        CurvedAnimation(
          parent: progress,
          // The card taken fades on its way out; the rest, at once.
          curve: card.towardTaker
              ? const Interval(0.4, 1, curve: Curves.easeIn)
              : Curves.easeOut,
        ),
      ),
      child: face,
    );
    if (!card.towardTaker) return fade;
    final away = card.down
        ? GameTableArea.glideDistance
        : -GameTableArea.glideDistance;
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: Offset(0, away),
      ).animate(CurvedAnimation(parent: progress, curve: Curves.easeInCubic)),
      child: fade,
    );
  }
}
