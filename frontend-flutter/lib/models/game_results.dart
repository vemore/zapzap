import 'game_state.dart';
import 'json.dart';
import 'party.dart';

// The answers to the game moves. None of them carries the new game state the
// caller should render: refetch `GET /game/:id/state` (the React client does).
// The Node play and draw answers also carry a raw `gameState` with every hand
// and the deck; it is deliberately not parsed.

/// `POST /game/:id/play`.
class PlayResult {
  const PlayResult({required this.cardsPlayed, required this.remainingCards});

  factory PlayResult.fromJson(JsonMap json) => PlayResult(
    cardsPlayed: Json.ints(json['cardsPlayed']),
    remainingCards: Json.integer(json, 'remainingCards'),
  );

  final List<int> cardsPlayed;
  final int remainingCards;
}

/// `POST /game/:id/draw`.
class DrawResult {
  const DrawResult({
    required this.cardDrawn,
    required this.source,
    required this.handSize,
  });

  factory DrawResult.fromJson(JsonMap json) => DrawResult(
    cardDrawn: Json.integer(json, 'cardDrawn'),
    source: Json.string(json, 'source'),
    handSize: Json.integer(json, 'handSize'),
  );

  final int cardDrawn;

  /// `deck` or `played`.
  final String source;

  /// The caller's card count after the draw.
  final int handSize;
}

/// `POST /game/:id/selectHandSize`.
class SelectHandSizeResult {
  const SelectHandSizeResult({required this.handSize});

  factory SelectHandSizeResult.fromJson(JsonMap json) =>
      SelectHandSizeResult(handSize: Json.integer(json, 'handSize'));

  final int handSize;
}

/// `POST /game/:id/zapzap`.
class ZapZapResult {
  const ZapZapResult({
    required this.zapzapSuccess,
    required this.counteracted,
    required this.callerPoints,
    this.totalScores,
    this.roundScores,
    this.counteractedByPlayerIndex,
    this.counteractedBy,
    this.handPoints,
  });

  factory ZapZapResult.fromJson(JsonMap json) {
    final by = json['counteractedBy'];
    // The backends put different numbers under the same key: Node sends the
    // running totals as an object, Rust this round's points as a list.
    final scores = json['scores'];
    return ZapZapResult(
      zapzapSuccess: Json.boolean(json, 'zapzapSuccess'),
      counteracted: Json.boolean(json, 'counteracted'),
      counteractedByPlayerIndex: Json.intOrNull(by),
      counteractedBy: by?.toString(),
      totalScores: scores is Map ? Json.intMap(scores) : null,
      roundScores: scores is List ? Json.intMap(scores) : null,
      handPoints: json['handPoints'] is Map
          ? Json.intMap(json['handPoints'])
          : null,
      callerPoints: Json.integer(json, 'callerPoints'),
    );
  }

  /// The caller had the lowest hand.
  final bool zapzapSuccess;
  final bool counteracted;

  /// Who counteracted, when the backend sent a player index (Node does).
  final int? counteractedByPlayerIndex;

  /// Who counteracted, as sent (Rust sends a string).
  final String? counteractedBy;

  /// Node only (`scores` as an object): each player's total score after
  /// this round.
  final Map<int, int>? totalScores;

  /// Rust only (`scores` as a list of `{playerIndex, score}`): the points
  /// each player scored this round.
  ///
  /// Exactly one of [totalScores] and [roundScores] is set. Either way the
  /// finished round's `GET /game/:id/state` carries both (`scores` and
  /// `roundScores`), so screens should read that rather than this.
  final Map<int, int>? roundScores;

  /// Node only: hand points per player index.
  final Map<int, int>? handPoints;

  /// The caller's hand value (jokers at 0).
  final int callerPoints;
}

/// `POST /game/:id/nextRound`: either the next round, or the end of the game.
class NextRoundResult {
  const NextRoundResult({
    required this.gameFinished,
    this.round,
    this.startingPlayer,
    this.scores = const {},
    this.finalScores,
    this.eliminatedPlayers = const [],
    this.isGoldenScore = false,
    this.enteringGoldenScore = false,
    this.winner,
  });

  factory NextRoundResult.fromJson(JsonMap json) {
    final round = Json.map(json, 'round');
    return NextRoundResult(
      gameFinished: Json.boolean(json, 'gameFinished'),
      round: round == null ? null : RoundInfo.fromJson(round),
      startingPlayer: Json.intOrNull(json['startingPlayer']),
      scores: Json.intMap(json['scores']),
      finalScores: Json.intMapOrNull(json['finalScores']),
      eliminatedPlayers: Json.ints(json['eliminatedPlayers']),
      isGoldenScore: Json.boolean(json, 'isGoldenScore'),
      enteringGoldenScore: Json.boolean(json, 'enteringGoldenScore'),
      winner: GameWinner.fromJsonOrNull(json['winner']),
    );
  }

  final bool gameFinished;

  /// The new round, when the game goes on.
  final RoundInfo? round;
  final int? startingPlayer;
  final Map<int, int> scores;

  /// When the game is over.
  final Map<int, int>? finalScores;

  /// Player indexes (Node sends objects with `playerIndex`, Rust bare
  /// indexes).
  final List<int> eliminatedPlayers;

  /// Node only.
  final bool isGoldenScore;

  /// Node only: this round starts the golden score.
  final bool enteringGoldenScore;
  final GameWinner? winner;
}
