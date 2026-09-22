import 'json.dart';

/// A finished game in a history listing (`GET /history`, `/history/public`).
///
/// The backends differ: Node sends `id`, `winnerUserId`, `winnerFinalScore`,
/// `totalRounds`, `wasGoldenScore`, `visibility`; Rust sends `roundsPlayed`,
/// `userPlacement`, `userScore`. Fields one side lacks are `null`.
class GameHistoryEntry {
  const GameHistoryEntry({
    required this.partyId,
    required this.partyName,
    required this.winnerUsername,
    required this.playerCount,
    this.finishedAt,
    this.totalRounds,
    this.winnerUserId,
    this.winnerFinalScore,
    this.wasGoldenScore,
    this.visibility,
    this.userPlacement,
    this.userScore,
  });

  factory GameHistoryEntry.fromJson(JsonMap json) => GameHistoryEntry(
    partyId: Json.string(json, 'partyId'),
    partyName: Json.string(json, 'partyName'),
    winnerUsername: Json.string(json, 'winnerUsername'),
    playerCount: Json.integer(json, 'playerCount'),
    finishedAt: Json.timestamp(json, 'finishedAt'),
    totalRounds: Json.intOrNull(json['totalRounds'] ?? json['roundsPlayed']),
    winnerUserId: Json.stringOrNull(json, 'winnerUserId'),
    winnerFinalScore: Json.intOrNull(json['winnerFinalScore']),
    wasGoldenScore: Json.boolOrNull(json, 'wasGoldenScore'),
    visibility: Json.stringOrNull(json, 'visibility'),
    userPlacement: Json.intOrNull(json['userPlacement']),
    userScore: Json.intOrNull(json['userScore']),
  );

  final String partyId;
  final String partyName;
  final String winnerUsername;
  final int playerCount;
  final DateTime? finishedAt;

  /// Node `totalRounds`, Rust `roundsPlayed`.
  final int? totalRounds;
  final String? winnerUserId;
  final int? winnerFinalScore;
  final bool? wasGoldenScore;
  final String? visibility;
  final int? userPlacement;
  final int? userScore;
}

/// The summary block of `GET /history/:partyId`.
class GameSummary {
  const GameSummary({
    required this.partyId,
    required this.partyName,
    required this.status,
    required this.totalRounds,
    required this.wasGoldenScore,
    required this.playerCount,
    this.visibility,
    this.winnerUserId,
    this.winnerUsername,
    this.winnerFinalScore,
    this.finishedAt,
  });

  factory GameSummary.fromJson(JsonMap json) {
    final winner = Json.map(json, 'winner') ?? const {};
    return GameSummary(
      partyId: Json.string(json, 'partyId'),
      partyName: Json.string(json, 'partyName'),
      status: Json.string(json, 'status'),
      totalRounds: Json.integer(json, 'totalRounds'),
      wasGoldenScore: Json.boolean(json, 'wasGoldenScore'),
      playerCount: Json.integer(json, 'playerCount'),
      visibility: Json.stringOrNull(json, 'visibility'),
      winnerUserId: Json.stringOrNull(winner, 'userId'),
      winnerUsername: Json.stringOrNull(winner, 'username'),
      winnerFinalScore: Json.intOrNull(winner['finalScore']),
      finishedAt: Json.timestamp(json, 'finishedAt'),
    );
  }

  final String partyId;
  final String partyName;
  final String status;
  final int totalRounds;
  final bool wasGoldenScore;
  final int playerCount;
  final String? visibility;
  final String? winnerUserId;
  final String? winnerUsername;
  final int? winnerFinalScore;
  final DateTime? finishedAt;
}

/// A player's result over a whole game.
class GamePlayerResult {
  const GamePlayerResult({
    required this.userId,
    required this.username,
    required this.finalScore,
    required this.finishPosition,
    required this.roundsPlayed,
    required this.totalZapZapCalls,
    required this.successfulZapZaps,
    required this.failedZapZaps,
    required this.lowestHandCount,
    required this.isWinner,
  });

  factory GamePlayerResult.fromJson(JsonMap json) => GamePlayerResult(
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    finalScore: Json.integer(json, 'finalScore'),
    finishPosition: Json.integer(json, 'finishPosition'),
    roundsPlayed: Json.integer(json, 'roundsPlayed'),
    totalZapZapCalls: Json.integer(json, 'totalZapZapCalls'),
    successfulZapZaps: Json.integer(json, 'successfulZapZaps'),
    failedZapZaps: Json.integer(json, 'failedZapZaps'),
    lowestHandCount: Json.integer(json, 'lowestHandCount'),
    isWinner: Json.boolean(json, 'isWinner'),
  );

  final String userId;
  final String username;
  final int finalScore;

  /// 1 for the winner.
  final int finishPosition;
  final int roundsPlayed;
  final int totalZapZapCalls;
  final int successfulZapZaps;
  final int failedZapZaps;
  final int lowestHandCount;
  final bool isWinner;
}

/// A player's line in one round of a finished game.
class RoundPlayerScore {
  const RoundPlayerScore({
    required this.userId,
    required this.username,
    required this.playerIndex,
    required this.scoreThisRound,
    required this.totalScoreAfter,
    required this.handPoints,
    required this.handCards,
    this.isZapZapCaller = false,
    this.zapZapSuccess = false,
    this.wasCounterActed = false,
    this.isLowestHand = false,
    this.isEliminated = false,
  });

  factory RoundPlayerScore.fromJson(JsonMap json) => RoundPlayerScore(
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    playerIndex: Json.integer(json, 'playerIndex'),
    scoreThisRound: Json.integer(json, 'scoreThisRound'),
    totalScoreAfter: Json.integer(json, 'totalScoreAfter'),
    handPoints: Json.integer(json, 'handPoints'),
    handCards: Json.ints(json['handCards']),
    isZapZapCaller: Json.boolean(json, 'isZapZapCaller'),
    zapZapSuccess: Json.boolean(json, 'zapZapSuccess'),
    wasCounterActed: Json.boolean(json, 'wasCounterActed'),
    isLowestHand: Json.boolean(json, 'isLowestHand'),
    isEliminated: Json.boolean(json, 'isEliminated'),
  );

  final String userId;
  final String username;
  final int playerIndex;
  final int scoreThisRound;
  final int totalScoreAfter;
  final int handPoints;

  /// Card ids. Node sends a JSON-encoded string (`"[17,28,1]"`), Rust a list.
  final List<int> handCards;
  final bool isZapZapCaller;
  final bool zapZapSuccess;
  final bool wasCounterActed;
  final bool isLowestHand;
  final bool isEliminated;
}

/// One round of a finished game.
class RoundHistory {
  const RoundHistory({required this.roundNumber, required this.players});

  factory RoundHistory.fromJson(JsonMap json) => RoundHistory(
    roundNumber: Json.integer(json, 'roundNumber'),
    players: Json.list(json, 'players', RoundPlayerScore.fromJson),
  );

  final int roundNumber;
  final List<RoundPlayerScore> players;
}

/// `GET /history/:partyId`.
class GameDetails {
  const GameDetails({
    required this.game,
    required this.players,
    required this.rounds,
  });

  factory GameDetails.fromJson(JsonMap json) => GameDetails(
    game: GameSummary.fromJson(Json.map(json, 'game') ?? const {}),
    players: Json.list(json, 'players', GamePlayerResult.fromJson),
    rounds: Json.list(json, 'rounds', RoundHistory.fromJson),
  );

  final GameSummary game;

  /// Ordered by finish position.
  final List<GamePlayerResult> players;
  final List<RoundHistory> rounds;
}
