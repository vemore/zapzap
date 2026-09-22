import '../models/json.dart';
import '../models/stats.dart';
import '../services/api_client.dart';

/// `/api/stats`.
class StatsRepository {
  const StatsRepository(this._api);

  final ApiClient _api;

  /// `GET /stats/me`.
  Future<UserStats> mine() async =>
      UserStats.fromJson(await _api.get('/stats/me'));

  /// `GET /stats/user/:userId` (public).
  Future<UserStats> user(String userId) async => UserStats.fromJson(
    await _api.get('/stats/user/$userId', authenticated: false),
  );

  /// `GET /stats/leaderboard`: humans with at least [minGames] games (the
  /// backend defaults to 5).
  Future<Page<LeaderboardEntry>> leaderboard({
    int? minGames,
    int? limit,
    int? offset,
  }) async => Page.fromJson(
    await _api.get(
      '/stats/leaderboard',
      query: {
        if (minGames != null) 'minGames': '$minGames',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
      authenticated: false,
    ),
    'leaderboard',
    LeaderboardEntry.fromJson,
  );

  /// `GET /stats/bots`.
  Future<BotStats> bots() async =>
      BotStats.fromJson(await _api.get('/stats/bots', authenticated: false));
}
