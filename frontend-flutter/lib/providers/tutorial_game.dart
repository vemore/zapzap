import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/game_state.dart';
import '../utils/rules.dart';

/// The zone of the board a coach bubble points at.
enum TutorialZone { hand, felt, actions }

/// The steps of the example game, in order. Each move step accepts one
/// move — the one its bubble asks for — and refuses any other with its hint.
enum TutorialStep {
  intro(TutorialZone.hand),
  playSingle(TutorialZone.hand, play: {TutorialGame.kingSpades}),
  drawDeck(TutorialZone.felt, draws: true),
  playPair(
    TutorialZone.hand,
    play: {TutorialGame.nineHearts, TutorialGame.nineClubs},
  ),
  takePile(TutorialZone.felt, draws: true, take: TutorialGame.aceClubs),
  playRun(
    TutorialZone.hand,
    play: {
      TutorialGame.fourHearts,
      TutorialGame.fiveHearts,
      TutorialGame.joker,
    },
  ),
  drawAgain(TutorialZone.felt, draws: true),
  zapZap(TutorialZone.actions),
  held(TutorialZone.actions),
  end(TutorialZone.actions);

  const TutorialStep(this.zone, {this.play, this.draws = false, this.take});

  final TutorialZone zone;

  /// The cards this step asks to play, or `null` when it asks for no play.
  final Set<int>? play;

  /// This step asks for a draw: from the pile when [take] is set, else from
  /// the deck.
  final bool draws;
  final int? take;

  /// A step read, then left with Next (or Finish): it asks for no move.
  bool get isInfo => this == intro || this == held || this == end;
}

/// A scripted example game, played offline on the real board widgets: a
/// fixed deal, one opponent whose moves are written in advance, and the
/// state the board is drawn from — the hand, the felt, the deck, the last
/// action — moved on as the backend would (`game_service.rs`: a play puts
/// the cards laid down before it on the pile). No repository, no API call.
///
/// After each of the player's draws, the opponent's turn plays out on its
/// own: a pause, his play, a pause, his deck draw — one action at a time, so
/// the felt moves and names each ([opponentPause]).
///
/// The hand goes 40 → 29 → 12 → 4 points: K♠ alone, then the pair of 9, the
/// A♣ taken from the pile, the run 4♥ 5♥ joker, and ZapZap at 4 — 5 or less
/// (`GAME_RULES.md`, ZapZap Eligibility).
class TutorialGame extends ChangeNotifier {
  static const me = 0;
  static const opponent = 1;

  /// The opponent: a name, not translated, as a player's would be.
  static const opponentName = 'Alex';

  /// The pause before each of the opponent's moves: the move before it
  /// has finished moving on the felt, and its message can be read.
  static const opponentPause = Duration(milliseconds: 900);

  /// The size of the hands dealt.
  static const handSize = 6;

  /// The deck once the hands are dealt and a card is flipped.
  static const startingDeck = 54 - 2 * handSize - 1;

  static const aceSpades = 0;
  static const twoHearts = 14;
  static const threeSpades = 2;
  static const sevenHearts = 19;
  static const jackSpades = 10;
  static const sixClubs = 31;
  static const tenDiamonds = 48;
  static const eightSpades = 7;
  static const kingSpades = 12;
  static const fourHearts = 16;
  static const fiveHearts = 17;
  static const nineHearts = 21;
  static const aceClubs = 26;
  static const eightClubs = 33;
  static const nineClubs = 34;
  static const queenClubs = 37;
  static const twoDiamonds = 40;
  static const joker = 52;

  /// What the deck gives each of this player's deck draws, in order.
  static const _deckDraws = {
    TutorialStep.drawDeck: twoDiamonds,
    TutorialStep.drawAgain: aceSpades,
  };

  /// What the opponent plays after each of this player's draws; it then
  /// draws from the deck.
  static const _opponentPlays = {
    TutorialStep.drawDeck: aceClubs,
    TutorialStep.takePile: eightClubs,
    TutorialStep.drawAgain: queenClubs,
  };

  /// The opponent's hand when ZapZap is called, shown by his score once it
  /// holds: 39 points, above the player's 4.
  static const opponentFinalHand = [
    threeSpades,
    sevenHearts,
    tenDiamonds,
    jackSpades,
    sixClubs,
    twoHearts,
  ];

  TutorialStep _step = TutorialStep.intro;
  List<int> _hand = const [
    kingSpades,
    nineHearts,
    nineClubs,
    fourHearts,
    fiveHearts,
    joker,
  ];
  List<int> _cardsPlayed = const [];

  /// The card flipped at the start of the round (`GAME_RULES.md`, Round
  /// Start).
  List<int> _lastCardsPlayed = const [eightSpades];
  int _deckSize = startingDeck;
  LastAction? _lastAction;
  int _clock = 0;
  List<int> _selected = const [];
  int? _selectedDiscard;
  bool _refused = false;
  bool _opponentMoving = false;
  Timer? _opponentTimer;

  TutorialStep get step => _step;
  List<int> get hand => _hand;
  List<int> get cardsPlayed => _cardsPlayed;
  List<int> get lastCardsPlayed => _lastCardsPlayed;
  int get deckSize => _deckSize;
  LastAction? get lastAction => _lastAction;
  List<int> get selectedCards => _selected;
  int? get selectedDiscardCard => _selectedDiscard;
  int get opponentCardCount => handSize;

  /// The opponent's turn is playing out: no move is taken meanwhile.
  bool get opponentMoving => _opponentMoving;

  /// The opponent's score: his hand's points once ZapZap has held, else 0.
  int get opponentScore => _step.index >= TutorialStep.held.index
      ? handValue(opponentFinalHand, penalty: true)
      : 0;

  /// The last move was not the one the step asks for: its hint shows.
  bool get refused => _refused;

  bool get isLast => _step == TutorialStep.end;

  GameAction get currentAction =>
      _step.draws ? GameAction.draw : GameAction.play;

  /// The hand can be played: a play step, or ZapZap's, where a play is
  /// refused with the hint.
  bool get handPlayable => !_step.isInfo && !_step.draws && !_opponentMoving;

  PlayError? get invalidPlay =>
      _selected.isEmpty ? null : analyzePlay(_selected).error;

  bool get canPlay =>
      handPlayable && _selected.isNotEmpty && invalidPlay == null;

  void toggleCard(int id) {
    if (!handPlayable) return;
    _selected = _selected.contains(id)
        ? (List.of(_selected)..remove(id))
        : [..._selected, id];
    notifyListeners();
  }

  void selectCards(List<int> ids) {
    if (!handPlayable) return;
    _selected = List.of(ids);
    notifyListeners();
  }

  void clearSelection() {
    _selected = const [];
    _selectedDiscard = null;
    notifyListeners();
  }

  void selectDiscardCard(int id) {
    if (!_step.draws || _opponentMoving) return;
    _selectedDiscard = _selectedDiscard == id ? null : id;
    notifyListeners();
  }

  /// Leaves a step that asks for no move.
  void next() {
    if (!_step.isInfo || isLast) return;
    _advance();
  }

  void play() {
    if (_opponentMoving) return;
    final want = _step.play;
    if (want == null || !setEquals(_selected.toSet(), want)) return _refuse();
    _hand = [
      for (final id in _hand)
        if (!want.contains(id)) id,
    ];
    _layDown(me, _selected);
    _selected = const [];
    _advance();
  }

  /// Draws the pile card picked, or the deck's top card when none is (or
  /// [fromDeck]).
  void draw({bool fromDeck = false}) {
    if (_opponentMoving) return;
    final take = fromDeck ? null : _selectedDiscard;
    if (!_step.draws || take != _step.take) return _refuse();
    final drawn = take ?? _deckDraws[_step]!;
    _hand = [..._hand, drawn];
    if (take != null) {
      _lastCardsPlayed = List.of(_lastCardsPlayed)..remove(take);
    } else {
      _deckSize--;
    }
    _act(
      LastAction(
        type: 'draw',
        playerIndex: me,
        source: take == null ? 'deck' : 'played',
        cardId: take,
      ),
    );
    _selectedDiscard = null;
    _opponentMoving = true;
    // The felt sees this draw on its own, before the opponent moves.
    notifyListeners();
    _opponentTurn(_opponentPlays[_step]!);
  }

  void zapZap() {
    if (_opponentMoving) return;
    if (_step != TutorialStep.zapZap) return _refuse();
    _act(const LastAction(type: 'zapzap', playerIndex: me));
    _selected = const [];
    _advance();
  }

  /// The opponent plays [card], then draws from the deck, each after
  /// [opponentPause]; then the next step.
  void _opponentTurn(int card) {
    _opponentTimer = Timer(opponentPause, () {
      _layDown(opponent, [card]);
      notifyListeners();
      _opponentTimer = Timer(opponentPause, () {
        _deckSize--;
        _act(
          const LastAction(type: 'draw', playerIndex: opponent, source: 'deck'),
        );
        _opponentMoving = false;
        _advance();
      });
    });
  }

  /// [cards] go under "Posées"; those laid down before become the pile — or
  /// the pile stays the flipped card, at the first play of the round.
  void _layDown(int player, List<int> cards) {
    if (_cardsPlayed.isNotEmpty) _lastCardsPlayed = _cardsPlayed;
    _cardsPlayed = List.of(cards);
    _act(LastAction(type: 'play', playerIndex: player, cardIds: cards));
  }

  /// Each action a new timestamp: the felt moves its cards once per action.
  void _act(LastAction action) {
    _clock++;
    _lastAction = LastAction(
      type: action.type,
      playerIndex: action.playerIndex,
      cardIds: action.cardIds,
      source: action.source,
      cardId: action.cardId,
      timestamp: DateTime.fromMillisecondsSinceEpoch(_clock * 1000),
    );
  }

  @override
  void dispose() {
    _opponentTimer?.cancel();
    super.dispose();
  }

  void _refuse() {
    _refused = true;
    notifyListeners();
  }

  void _advance() {
    _step = TutorialStep.values[_step.index + 1];
    _refused = false;
    notifyListeners();
  }
}
