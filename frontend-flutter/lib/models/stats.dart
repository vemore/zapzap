import 'json.dart';

/// ZapZap calls: `{total, successful, failed, successRate}` (rate in 0..1).
class ZapZapStats {
  const ZapZapStats({
    this.total = 0,
    this.successful = 0,
    this.failed = 0,
    this.successRate = 0,
  });

  factory ZapZapStats.fromJson(JsonMap? json) {
    if (json == null) return const ZapZapStats();
    return ZapZapStats(
      total: Json.integer(json, 'total'),
      successful: Json.integer(json, 'successful'),
      failed: Json.integer(json, 'failed'),
      successRate: Json.number(json, 'successRate'),
    );
  }

  final int total;
  final int successful;
  final int failed;
  final double successRate;
}

/// `GET /stats/me` and `/stats/user/:userId`.
class UserStats {
  const UserStats({
    required this.userId,
    required this.username,
    required this.gamesPlayed,
    required this.wins,
    required this.losses,
    required this.winRate,
    required this.averageScore,
    required this.bestScore,
    required this.totalRoundsPlayed,
    required this.zapzaps,
    required this.lowestHandCount,
  });

  factory UserStats.fromJson(JsonMap json) {
    final stats = Json.map(json, 'stats') ?? const {};
    return UserStats(
      userId: Json.string(json, 'userId'),
      username: Json.string(json, 'username'),
      gamesPlayed: Json.integer(stats, 'gamesPlayed'),
      wins: Json.integer(stats, 'wins'),
      losses: Json.integer(stats, 'losses'),
      winRate: Json.number(stats, 'winRate'),
      averageScore: Json.number(stats, 'averageScore'),
      bestScore: Json.integer(stats, 'bestScore'),
      totalRoundsPlayed: Json.integer(stats, 'totalRoundsPlayed'),
      zapzaps: ZapZapStats.fromJson(Json.map(stats, 'zapzaps')),
      lowestHandCount: Json.integer(stats, 'lowestHandCount'),
    );
  }

  final String userId;
  final String username;
  final int gamesPlayed;
  final int wins;
  final int losses;

  /// 0..1.
  final double winRate;
  final double averageScore;

  /// The lowest final score (lower is better).
  final int bestScore;
  final int totalRoundsPlayed;
  final ZapZapStats zapzaps;

  /// Rounds ended with the lowest hand.
  final int lowestHandCount;
}

/// A row of `GET /stats/leaderboard` (humans with at least `minGames`).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.username,
    required this.gamesPlayed,
    required this.wins,
    required this.winRate,
    this.averageScore,
  });

  factory LeaderboardEntry.fromJson(JsonMap json) => LeaderboardEntry(
    rank: Json.integer(json, 'rank'),
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    gamesPlayed: Json.integer(json, 'gamesPlayed'),
    wins: Json.integer(json, 'wins'),
    winRate: Json.number(json, 'winRate'),
    averageScore: json['averageScore'] is num
        ? Json.number(json, 'averageScore')
        : null,
  );

  final int rank;
  final String userId;
  final String username;
  final int gamesPlayed;
  final int wins;
  final double winRate;

  /// Node only.
  final double? averageScore;
}

/// Totals over every bot (`totals` of `GET /stats/bots`).
class BotTotals {
  const BotTotals({
    required this.totalBots,
    required this.totalGamesPlayed,
    required this.totalRoundsPlayed,
    required this.totalWins,
    required this.totalZapzapCalls,
    required this.totalSuccessfulZapzaps,
    required this.overallWinRate,
    required this.overallZapzapSuccessRate,
  });

  factory BotTotals.fromJson(JsonMap json) => BotTotals(
    totalBots: Json.integer(json, 'totalBots'),
    totalGamesPlayed: Json.integer(json, 'totalGamesPlayed'),
    totalRoundsPlayed: Json.integer(json, 'totalRoundsPlayed'),
    totalWins: Json.integer(json, 'totalWins'),
    totalZapzapCalls: Json.integer(json, 'totalZapzapCalls'),
    totalSuccessfulZapzaps: Json.integer(json, 'totalSuccessfulZapzaps'),
    overallWinRate: Json.number(json, 'overallWinRate'),
    overallZapzapSuccessRate: Json.number(json, 'overallZapzapSuccessRate'),
  );

  final int totalBots;
  final int totalGamesPlayed;
  final int totalRoundsPlayed;
  final int totalWins;
  final int totalZapzapCalls;
  final int totalSuccessfulZapzaps;
  final double overallWinRate;
  final double overallZapzapSuccessRate;
}

/// Bot results, grouped by difficulty ([botId] and [username] `null`) or
/// per bot ([botCount] and [roundWinRate] `null`).
class BotStatsLine {
  const BotStatsLine({
    required this.difficulty,
    required this.gamesPlayed,
    required this.roundsPlayed,
    required this.wins,
    required this.winRate,
    required this.zapzaps,
    required this.lowestHandCount,
    this.botId,
    this.username,
    this.botCount,
    this.roundWinRate,
  });

  factory BotStatsLine.fromJson(JsonMap json) => BotStatsLine(
    difficulty: Json.string(json, 'difficulty'),
    gamesPlayed: Json.integer(json, 'gamesPlayed'),
    roundsPlayed: Json.integer(json, 'roundsPlayed'),
    wins: Json.integer(json, 'wins'),
    winRate: Json.number(json, 'winRate'),
    zapzaps: ZapZapStats.fromJson(Json.map(json, 'zapzaps')),
    lowestHandCount: Json.integer(json, 'lowestHandCount'),
    botId: Json.stringOrNull(json, 'botId'),
    username: Json.stringOrNull(json, 'username'),
    botCount: Json.intOrNull(json['botCount']),
    roundWinRate: json['roundWinRate'] is num
        ? Json.number(json, 'roundWinRate')
        : null,
  );

  final String difficulty;
  final int gamesPlayed;
  final int roundsPlayed;
  final int wins;
  final double winRate;
  final ZapZapStats zapzaps;
  final int lowestHandCount;
  final String? botId;
  final String? username;
  final int? botCount;
  final double? roundWinRate;
}

/// `GET /stats/bots`.
class BotStats {
  const BotStats({
    required this.totals,
    required this.byDifficulty,
    required this.byBot,
  });

  factory BotStats.fromJson(JsonMap json) => BotStats(
    totals: BotTotals.fromJson(Json.map(json, 'totals') ?? const {}),
    byDifficulty: Json.list(json, 'byDifficulty', BotStatsLine.fromJson),
    byBot: Json.list(json, 'byBot', BotStatsLine.fromJson),
  );

  final BotTotals totals;
  final List<BotStatsLine> byDifficulty;
  final List<BotStatsLine> byBot;
}
