import 'json.dart';
import 'party.dart';

/// A human account in `GET /admin/users`.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.isAdmin,
    this.userType = 'human',
    this.lastLoginAt,
    this.totalPlayTimeSeconds = 0,
    this.gamesPlayed = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory AdminUser.fromJson(JsonMap json) => AdminUser(
    id: Json.string(json, 'id'),
    username: Json.string(json, 'username'),
    isAdmin: Json.boolean(json, 'isAdmin'),
    userType: Json.string(json, 'userType', 'human'),
    lastLoginAt: Json.timestamp(json, 'lastLoginAt'),
    totalPlayTimeSeconds: Json.integer(json, 'totalPlayTimeSeconds'),
    gamesPlayed: Json.integer(json, 'gamesPlayed'),
    createdAt: Json.timestamp(json, 'createdAt'),
    updatedAt: Json.timestamp(json, 'updatedAt'),
  );

  final String id;
  final String username;
  final bool isAdmin;
  final String userType;
  final DateTime? lastLoginAt;
  final int totalPlayTimeSeconds;
  final int gamesPlayed;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A party in `GET /admin/parties` (every visibility and status).
class AdminParty {
  const AdminParty({
    required this.id,
    required this.name,
    required this.status,
    required this.playerCount,
    this.ownerId,
    this.ownerUsername,
    this.inviteCode,
    this.visibility,
    this.settings = const PartySettings(),
    this.currentRoundId,
    this.createdAt,
    this.updatedAt,
  });

  factory AdminParty.fromJson(JsonMap json) => AdminParty(
    id: Json.string(json, 'id'),
    name: Json.string(json, 'name'),
    status: Json.string(json, 'status'),
    playerCount: Json.integer(json, 'playerCount'),
    ownerId: Json.stringOrNull(json, 'ownerId'),
    ownerUsername: Json.stringOrNull(json, 'ownerUsername'),
    inviteCode: Json.stringOrNull(json, 'inviteCode'),
    visibility: Json.stringOrNull(json, 'visibility'),
    // Both backends send the settings JSON-encoded, as stored.
    settings: PartySettings.fromJson(json['settings']),
    currentRoundId: Json.stringOrNull(json, 'currentRoundId'),
    createdAt: Json.timestamp(json, 'createdAt'),
    updatedAt: Json.timestamp(json, 'updatedAt'),
  );

  final String id;
  final String name;
  final String status;
  final int playerCount;
  final String? ownerId;
  final String? ownerUsername;
  final String? inviteCode;
  final String? visibility;
  final PartySettings settings;
  final String? currentRoundId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// `{period, count}`: `period` is `2026-09-22` (daily), `2026-38` (weekly)
/// or `2026-09` (monthly).
class GamePeriod {
  const GamePeriod({required this.period, required this.count});

  factory GamePeriod.fromJson(JsonMap json) => GamePeriod(
    period: Json.string(json, 'period'),
    count: Json.integer(json, 'count'),
  );

  final String period;
  final int count;
}

/// A row of `mostActiveUsers`.
class ActiveUser {
  const ActiveUser({
    required this.userId,
    required this.username,
    required this.gamesPlayed,
    required this.wins,
  });

  factory ActiveUser.fromJson(JsonMap json) => ActiveUser(
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    gamesPlayed: Json.integer(json, 'gamesPlayed'),
    wins: Json.integer(json, 'wins'),
  );

  final String userId;
  final String username;
  final int gamesPlayed;
  final int wins;
}

/// `GET /admin/statistics`.
class AdminStatistics {
  const AdminStatistics({
    required this.totalUsers,
    required this.totalParties,
    required this.waitingParties,
    required this.playingParties,
    required this.finishedParties,
    required this.completionRate,
    required this.totalRounds,
    required this.daily,
    required this.weekly,
    required this.monthly,
    required this.mostActiveUsers,
  });

  factory AdminStatistics.fromJson(JsonMap json) {
    final stats = Json.map(json, 'stats') ?? const {};
    final users = Json.map(stats, 'users') ?? const {};
    final parties = Json.map(stats, 'parties') ?? const {};
    final rounds = Json.map(stats, 'rounds') ?? const {};
    final overTime = Json.map(stats, 'gamesOverTime') ?? const {};
    return AdminStatistics(
      totalUsers: Json.integer(users, 'total'),
      totalParties: Json.integer(parties, 'total'),
      waitingParties: Json.integer(parties, 'waiting'),
      playingParties: Json.integer(parties, 'playing'),
      finishedParties: Json.integer(parties, 'finished'),
      completionRate: Json.number(parties, 'completionRate'),
      totalRounds: Json.integer(rounds, 'total'),
      daily: Json.list(overTime, 'daily', GamePeriod.fromJson),
      weekly: Json.list(overTime, 'weekly', GamePeriod.fromJson),
      monthly: Json.list(overTime, 'monthly', GamePeriod.fromJson),
      mostActiveUsers: Json.list(stats, 'mostActiveUsers', ActiveUser.fromJson),
    );
  }

  final int totalUsers;
  final int totalParties;
  final int waitingParties;
  final int playingParties;
  final int finishedParties;

  /// A percentage, 0..100.
  final double completionRate;
  final int totalRounds;
  final List<GamePeriod> daily;
  final List<GamePeriod> weekly;
  final List<GamePeriod> monthly;
  final List<ActiveUser> mostActiveUsers;
}
