import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/card.dart';
import '../models/game_state.dart';
import '../models/party.dart';
import '../models/sse_event.dart';
import '../repositories/game_repository.dart';
import '../utils/rules.dart';

/// The game error codes the board reacts to, on top of `ApiErrorCode` —
/// which already names `NOT_YOUR_TURN` and `HAND_TOO_HIGH`.
abstract final class GameErrorCode {
  /// The move does not fit the phase (playing when a draw is owed).
  static const invalidActionState = 'INVALID_ACTION_STATE';
  static const invalidPlay = 'INVALID_PLAY';
  static const invalidCards = 'INVALID_CARDS';
  static const cardNotAvailable = 'CARD_NOT_AVAILABLE';
  static const deckEmpty = 'DECK_EMPTY';
  static const invalidHandSize = 'INVALID_HAND_SIZE';
  static const roundNotFinished = 'ROUND_NOT_FINISHED';

  /// The caller has no seat at this table (both backends).
  static const notInParty = 'NOT_IN_PARTY';
}

/// What ends the board: the screen watches [GameProvider.outcome] and
/// navigates.
enum GameOutcome {
  /// The party was deleted while the game was open: go back to the list.
  closed,
}

/// The hand sizes the starting player may pick (`GAME_RULES.md`): 4-7, and
/// 4-10 once two players are left (Golden Score).
const int minHandSize = 4;
const int maxHandSize = 7;
const int maxGoldenHandSize = 10;

/// One party's board (`GET /game/:id/state`), refreshed by the event
/// stream, plus the selection the player builds before a move.
///
/// A move's answer is not the new table, so every action refetches the
/// state — as the React client does (`GameBoard.jsx`). Nothing takes a
/// drawn table away: a refused **move** fills [actionError], a **refresh**
/// that fails over a table already on screen fills [refreshError], and only
/// a **load with nothing to show** fills [error]. The React board has one
/// `error` for all three and draws an error page instead of the table
/// (`GameBoard.jsx:220-235`).
class GameProvider extends ChangeNotifier {
  GameProvider(
    this._repository, {
    required this.partyId,
    required Stream<SseEvent> events,
    this.currentUserId,
  }) {
    _subscription = events.listen(_onEvent);
  }

  final String partyId;
  final GameRepository _repository;

  /// Who is signed in: the seat, and so [isMyTurn], is found by user id —
  /// the state carries no "this is you" flag.
  final String? currentUserId;

  late final StreamSubscription<SseEvent> _subscription;

  GameSnapshot? _snapshot;
  bool _loading = true;
  Object? _error;
  Object? _refreshError;
  Object? _actionError;

  /// Counts the loads, so a stale answer cannot overwrite a newer table.
  int _loadGeneration = 0;
  bool _busy = false;
  bool _disposed = false;
  GameOutcome? _outcome;
  final List<int> _selectedCards = [];
  int? _selectedDiscardCard;
  List<int> _handShown = const [];

  GameSnapshot? get snapshot => _snapshot;
  GameState? get game => _snapshot?.gameState;
  RoundInfo? get round => _snapshot?.round;
  List<PartyPlayer> get players => _snapshot?.players ?? const [];

  /// `true` until the first answer, and again while a spinner-showing
  /// load runs; a refresh driven by an event does not set it.
  bool get loading => _loading;

  /// A failure of the load with nothing to fall back on: the board cannot
  /// be drawn at all. A refresh that fails over a table already on screen
  /// goes to [refreshError] instead.
  Object? get error => _error;

  /// The last refresh failed while a table was on screen: what is drawn may
  /// be out of date. Cleared by the next load that succeeds; the board shows
  /// a banner and stays.
  Object? get refreshError => _refreshError;

  /// A refused move. The board stays on screen; the screen shows it once
  /// and clears it with [consumeActionError].
  Object? get actionError => _actionError;

  /// A move is in flight: the buttons are disabled.
  bool get busy => _busy;

  GameOutcome? get outcome => _outcome;

  /// The party is not playing yet (`gameState` is null): nothing to draw.
  bool get isStarted => game != null;

  GameAction get currentAction => game?.currentAction ?? GameAction.unknown;
  bool get isGoldenScore => game?.isGoldenScore ?? false;
  int get deckSize => game?.deckSize ?? 0;
  int get startingPlayer => game?.startingPlayer ?? 0;
  List<int> get myHand => game?.playerHand ?? const [];
  List<int> get cardsPlayed => game?.cardsPlayed ?? const [];
  List<int> get lastCardsPlayed => game?.lastCardsPlayed ?? const [];
  LastAction? get lastAction => game?.lastAction;

  /// The caller's seat, or `null` for a spectator.
  int? get myPlayerIndex {
    if (currentUserId == null) return null;
    for (final player in players) {
      if (player.userId == currentUserId) return player.playerIndex;
    }
    return null;
  }

  int get currentTurn => game?.currentTurn ?? 0;

  bool get isMyTurn {
    final mine = myPlayerIndex;
    return mine != null && game != null && game!.currentTurn == mine;
  }

  /// The players in turn order, the round's starting player first
  /// (`PlayerTable.jsx:28-34`).
  List<PartyPlayer> get orderedPlayers {
    final ordered = [...players];
    final count = ordered.length;
    if (count == 0) return ordered;
    final first = startingPlayer;
    ordered.sort(
      (a, b) => ((a.playerIndex - first) % count).compareTo(
        (b.playerIndex - first) % count,
      ),
    );
    return ordered;
  }

  /// How many cards [playerIndex] holds: the caller's own hand is counted,
  /// the others come from `otherPlayersHandSizes`.
  int cardCountOf(int playerIndex) {
    if (playerIndex == myPlayerIndex) return myHand.length;
    return game?.otherPlayersHandSizes[playerIndex] ?? 0;
  }

  int scoreOf(int playerIndex) => game?.scores[playerIndex] ?? 0;

  bool isEliminated(int playerIndex) =>
      game?.eliminatedPlayers.contains(playerIndex) ?? false;

  /// The name of the player at [playerIndex], or `null` when no seat
  /// carries it (the screen falls back to "Player n").
  String? nameOf(int? playerIndex) {
    if (playerIndex == null) return null;
    for (final player in players) {
      if (player.playerIndex == playerIndex) return player.username;
    }
    return null;
  }

  /// The cards tapped, in tap order — the order they are played in.
  List<int> get selectedCards => List.unmodifiable(_selectedCards);

  /// The discard card tapped in the draw phase, if any.
  int? get selectedDiscardCard => _selectedDiscardCard;

  /// Something is selected — cards, a discard card, or both.
  bool get hasSelection =>
      _selectedCards.isNotEmpty || _selectedDiscardCard != null;

  /// Why the selection is not a legal play, or `null` when it is (or when
  /// nothing is selected).
  PlayError? get invalidPlay {
    if (_selectedCards.isEmpty) return null;
    return analyzePlay(_selectedCards).error;
  }

  ({int eligibility, int penalty}) get handValues => handValueDisplay(myHand);

  bool get zapZapEligible => isZapZapEligible(myHand);

  /// The largest hand size the starting player may pick this round.
  int get handSizeMax => isGoldenScore ? maxGoldenHandSize : maxHandSize;

  /// What the hand-size selector starts on: the middle of the range, as
  /// React (`HandSizeSelector.jsx:712`) — 5 normally, 7 in Golden Score.
  int get defaultHandSize => (minHandSize + handSizeMax) ~/ 2;

  bool get canPlay =>
      isMyTurn &&
      currentAction == GameAction.play &&
      _selectedCards.isNotEmpty &&
      invalidPlay == null &&
      !_busy;

  bool get canDraw => isMyTurn && currentAction == GameAction.draw && !_busy;

  /// Drawing takes the selected discard card when it is still on the pile,
  /// and the deck otherwise (React's single Draw/Take button). A card the
  /// pile no longer holds is never posted: the backend would refuse a
  /// `cardId` that is gone.
  bool get willTakeFromDiscard =>
      _selectedDiscardCard != null &&
      lastCardsPlayed.contains(_selectedDiscardCard);

  bool get canZapZap =>
      isMyTurn && currentAction == GameAction.play && zapZapEligible && !_busy;

  /// The discard pile is tappable only when a draw is owed.
  bool get canSelectDiscard => isMyTurn && currentAction == GameAction.draw;

  bool get isRoundFinished => currentAction == GameAction.finished;

  bool get isGameFinished => game?.gameFinished ?? false;

  /// (Re)loads the table. [showSpinner] false is a refresh driven by an
  /// event or by a move: the current table stays on screen meanwhile.
  ///
  /// Two loads can be in flight at once — a move's refetch and the event
  /// its own broadcast triggers, a fraction of a second apart — and they
  /// can answer out of order. Only the newest one is kept
  /// ([_loadGeneration], the guard of `services/sse_client.dart`);
  /// an older answer, good or bad, is dropped.
  Future<void> load({bool showSpinner = true}) async {
    if (showSpinner && !_loading) {
      _loading = true;
      _notify();
    }
    final generation = ++_loadGeneration;
    try {
      final snapshot = await _repository.state(partyId);
      if (generation != _loadGeneration) return;
      _snapshot = snapshot;
      _error = null;
      _refreshError = null;
      _syncSelection();
    } catch (error) {
      if (generation != _loadGeneration) return;
      // A table already on screen is never taken away by a *refresh* that
      // fails: the move went through, only the refetch did not. The error
      // screen is for a load with nothing to show.
      if (_snapshot == null) {
        _error = error;
      } else {
        _refreshError = error;
      }
    }
    _loading = false;
    _notify();
  }

  /// Taps [cardId] in the hand: selected cards keep their tap order, so
  /// they are played in it.
  void toggleCard(int cardId) {
    if (!GameCard.isValidId(cardId)) return;
    if (!_selectedCards.remove(cardId)) _selectedCards.add(cardId);
    _notify();
  }

  /// Drops the whole selection — the cards *and* the discard card, which
  /// otherwise leaves the Draw button reading "Take".
  void clearSelection() {
    if (_selectedCards.isEmpty && _selectedDiscardCard == null) return;
    _selectedCards.clear();
    _selectedDiscardCard = null;
    _notify();
  }

  /// Taps [cardId] in the discard pile; tapping the selected one again
  /// deselects it.
  void selectDiscardCard(int? cardId) {
    _selectedDiscardCard = _selectedDiscardCard == cardId ? null : cardId;
    _notify();
  }

  Future<void> selectHandSize(int handSize) =>
      _act(() => _repository.selectHandSize(partyId, handSize));

  /// Plays the selection. A refusal — this client's or the backend's —
  /// leaves the cards selected and the board as it is.
  Future<void> play() async {
    if (!canPlay) return;
    final cards = [..._selectedCards];
    await _act(() => _repository.play(partyId, cards));
  }

  /// Draws: the selected discard card, or the deck.
  Future<void> draw() async {
    if (!canDraw) return;
    final fromDiscard = willTakeFromDiscard ? _selectedDiscardCard : null;
    await _act(
      () => fromDiscard == null
          ? _repository.drawFromDeck(partyId)
          : _repository.drawFromPlayed(partyId, fromDiscard),
    );
  }

  Future<void> zapZap() async {
    if (!canZapZap) return;
    await _act(() => _repository.zapZap(partyId));
  }

  /// `POST /game/:id/nextRound` once the round is over.
  Future<void> nextRound() => _act(() => _repository.nextRound(partyId));

  /// Reads the refused move and forgets it, so the screen shows it once.
  Object? consumeActionError() {
    final error = _actionError;
    _actionError = null;
    return error;
  }

  /// Runs a move, then refetches the table: no answer carries it.
  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _actionError = null;
    _notify();
    try {
      await action();
      _selectedDiscardCard = null;
      await load(showSpinner: false);
    } catch (error) {
      _actionError = error;
    }
    _busy = false;
    _notify();
  }

  /// Every hand change drops the selection: the ids meant a hand that is
  /// gone (`PlayerHand.jsx:447-449`, which only watches the length).
  void _syncSelection() {
    final hand = myHand;
    if (!listEquals(hand, _handShown)) {
      _handShown = List.unmodifiable(hand);
      _selectedCards.clear();
      _selectedDiscardCard = null;
    }
  }

  /// Every client gets every broadcast: only this party's matter
  /// (`GameBoard.jsx:108-142`). `partyStarted` brings a client that opened
  /// the board before the owner started from the "not started" page onto
  /// the table, with no reload.
  void _onEvent(SseEvent event) {
    if (event.partyId != partyId || _outcome != null) return;
    switch (event.action) {
      case 'play':
      case 'draw':
      case 'selectHandSize':
      case 'zapzap':
      case 'gameFinished':
      case 'roundStarted':
      case 'partyStarted':
        load(showSpinner: false);
      case 'partyDeleted':
        _outcome = GameOutcome.closed;
        _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription.cancel();
    super.dispose();
  }
}
