import 'json.dart';
import 'party.dart';

/// The phase of a round (`gameState.currentAction`).
enum GameAction {
  selectHandSize('selectHandSize'),
  play('play'),
  draw('draw'),
  finished('finished'),

  /// A value this client does not know; treat as "wait for the next update".
  unknown('');

  const GameAction(this.wire);

  /// The backend's spelling.
  final String wire;

  static GameAction fromWire(String? value) => GameAction.values.firstWhere(
    (action) => action.wire == value && action != unknown,
    orElse: () => unknown,
  );
}

/// The last move of the round (`gameState.lastAction`). Only [type] and
/// [playerIndex] are always set; the rest depends on the move:
/// `selectHandSize` → [handSize]; `play` → [cardIds]; `draw` → [source],
/// [cardId], [deckReshuffled]; `zapzap` → [wasCounterActed],
/// [counterActedByPlayerIndex], [callerHandPoints], [roundScores].
class LastAction {
  const LastAction({
    required this.type,
    required this.playerIndex,
    this.handSize,
    this.cardIds = const [],
    this.source,
    this.cardId,
    this.deckReshuffled = false,
    this.wasCounterActed = false,
    this.counterActedByPlayerIndex,
    this.callerHandPoints,
    this.roundScores,
    this.timestamp,
  });

  factory LastAction.fromJson(JsonMap json) => LastAction(
    type: Json.string(json, 'type'),
    playerIndex: Json.integer(json, 'playerIndex'),
    handSize: Json.intOrNull(json['handSize']),
    cardIds: Json.ints(json['cardIds']),
    source: Json.stringOrNull(json, 'source'),
    cardId: Json.intOrNull(json['cardId']),
    deckReshuffled: Json.boolean(json, 'deckReshuffled'),
    wasCounterActed: Json.boolean(json, 'wasCounterActed'),
    counterActedByPlayerIndex: Json.intOrNull(
      json['counterActedByPlayerIndex'],
    ),
    callerHandPoints: Json.intOrNull(json['callerHandPoints']),
    roundScores: Json.intMapOrNull(json['roundScores']),
    timestamp: Json.timestamp(json, 'timestamp'),
  );

  /// `selectHandSize`, `play`, `draw` or `zapzap`.
  final String type;
  final int playerIndex;
  final int? handSize;
  final List<int> cardIds;

  /// `deck` or `played`.
  final String? source;
  final int? cardId;
  final bool deckReshuffled;
  final bool wasCounterActed;
  final int? counterActedByPlayerIndex;
  final int? callerHandPoints;
  final Map<int, int>? roundScores;

  /// Unix milliseconds on the wire.
  final DateTime? timestamp;
}

/// The winner of a finished game: `{userId, playerIndex, username, score}`.
class GameWinner {
  const GameWinner({
    required this.playerIndex,
    this.userId,
    this.username,
    this.score,
  });

  /// Accepts the object, or a bare player index (the Rust `nextRound`).
  static GameWinner? fromJsonOrNull(Object? value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();
      return GameWinner(
        playerIndex: Json.integer(json, 'playerIndex'),
        userId: Json.stringOrNull(json, 'userId'),
        username: Json.stringOrNull(json, 'username'),
        score: Json.intOrNull(json['score']),
      );
    }
    final index = Json.intOrNull(value);
    return index == null ? null : GameWinner(playerIndex: index);
  }

  final int playerIndex;
  final String? userId;
  final String? username;
  final int? score;
}

/// The round as the caller sees it (`gameState` of `GET /game/:id/state`).
///
/// Maps are keyed by player index (JSON object keys are strings on the wire:
/// `{"0": 28}`). Cards are ids 0-53 (`GAME_RULES.md`).
///
/// The fields from [allHands] to [winner] are only filled once
/// [currentAction] is [GameAction.finished]; before that they are `null`,
/// `false` or empty.
class GameState {
  const GameState({
    required this.currentTurn,
    required this.currentAction,
    required this.deckSize,
    this.lastCardsPlayed = const [],
    this.cardsPlayed = const [],
    this.scores = const {},
    this.playerHand = const [],
    this.otherPlayersHandSizes = const {},
    this.lastAction,
    this.isGoldenScore = false,
    this.eliminatedPlayers = const [],
    this.startingPlayer = 0,
    this.allHands,
    this.handPoints,
    this.zapZapCaller,
    this.lowestHandPlayerIndex,
    this.wasCounterActed = false,
    this.counterActedByPlayerIndex,
    this.roundScores,
    this.gameFinished = false,
    this.winner,
  });

  factory GameState.fromJson(JsonMap json) {
    final lastAction = Json.map(json, 'lastAction');
    return GameState(
      currentTurn: Json.integer(json, 'currentTurn'),
      currentAction: GameAction.fromWire(
        Json.stringOrNull(json, 'currentAction'),
      ),
      deckSize: Json.integer(json, 'deckSize'),
      lastCardsPlayed: Json.ints(json['lastCardsPlayed']),
      cardsPlayed: Json.ints(json['cardsPlayed']),
      scores: Json.intMap(json['scores']),
      playerHand: Json.ints(json['playerHand']),
      otherPlayersHandSizes: Json.intMap(json['otherPlayersHandSizes']),
      lastAction: lastAction == null ? null : LastAction.fromJson(lastAction),
      isGoldenScore: Json.boolean(json, 'isGoldenScore'),
      eliminatedPlayers: Json.ints(json['eliminatedPlayers']),
      startingPlayer: Json.integer(json, 'startingPlayer'),
      allHands: Json.handsOrNull(json['allHands']),
      handPoints: Json.intMapOrNull(json['handPoints']),
      zapZapCaller: Json.intOrNull(json['zapZapCaller']),
      lowestHandPlayerIndex: Json.intOrNull(json['lowestHandPlayerIndex']),
      wasCounterActed: Json.boolean(json, 'wasCounterActed'),
      counterActedByPlayerIndex: Json.intOrNull(
        json['counterActedByPlayerIndex'],
      ),
      roundScores: Json.intMapOrNull(json['roundScores']),
      gameFinished: Json.boolean(json, 'gameFinished'),
      winner: GameWinner.fromJsonOrNull(json['winner']),
    );
  }

  /// The player index whose move it is.
  final int currentTurn;
  final GameAction currentAction;
  final int deckSize;

  /// The cards the previous player laid down — the ones that can be drawn.
  final List<int> lastCardsPlayed;

  /// The cards laid down this turn.
  final List<int> cardsPlayed;

  /// Total score per player index.
  final Map<int, int> scores;

  /// The caller's own hand (empty for a spectator).
  final List<int> playerHand;

  /// Card count per opponent's player index.
  final Map<int, int> otherPlayersHandSizes;
  final LastAction? lastAction;
  final bool isGoldenScore;
  final List<int> eliminatedPlayers;
  final int startingPlayer;

  /// Every hand, revealed at the end of the round.
  final Map<int, List<int>>? allHands;

  /// Points per hand at the end of the round (jokers count 25).
  final Map<int, int>? handPoints;
  final int? zapZapCaller;
  final int? lowestHandPlayerIndex;
  final bool wasCounterActed;
  final int? counterActedByPlayerIndex;

  /// Points each player scored this round.
  final Map<int, int>? roundScores;

  /// The whole game is over, not only the round.
  final bool gameFinished;
  final GameWinner? winner;

  bool get isRoundFinished => currentAction == GameAction.finished;
}

/// `GET /game/:id/state`: the party, its seats, the round and the caller's
/// view of it. [round] and [gameState] are `null` while the party waits.
class GameSnapshot {
  const GameSnapshot({
    required this.party,
    required this.players,
    this.round,
    this.gameState,
  });

  factory GameSnapshot.fromJson(JsonMap json) {
    final round = Json.map(json, 'round');
    final gameState = Json.map(json, 'gameState');
    return GameSnapshot(
      party: Party.fromJson(Json.map(json, 'party') ?? const {}),
      players: Json.list(json, 'players', PartyPlayer.fromJson),
      round: round == null ? null : RoundInfo.fromJson(round),
      gameState: gameState == null ? null : GameState.fromJson(gameState),
    );
  }

  /// Only `id`, `name`, `status` and `currentRoundId` are set.
  final Party party;

  /// Node sends `playerIndex`, `userId`, `username`; Rust adds `userType`
  /// and `botDifficulty`.
  final List<PartyPlayer> players;
  final RoundInfo? round;
  final GameState? gameState;
}
