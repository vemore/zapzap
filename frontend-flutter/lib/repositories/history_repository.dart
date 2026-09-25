import '../models/history.dart';
import '../models/json.dart';
import '../services/api_client.dart';

/// `/api/history`: finished games.
class HistoryRepository {
  const HistoryRepository(this._api);

  final ApiClient _api;

  /// `GET /history`: the caller's games (the backend also serves it as
  /// `/history/my-games`).
  Future<Page<GameHistoryEntry>> mine({int? limit, int? offset}) async =>
      Page.fromJson(
        await _api.get('/history', query: _paging(limit, offset)),
        'games',
        GameHistoryEntry.fromJson,
      );

  /// `GET /history/public`.
  Future<Page<GameHistoryEntry>> public({int? limit, int? offset}) async =>
      Page.fromJson(
        await _api.get(
          '/history/public',
          query: _paging(limit, offset),
          authenticated: false,
        ),
        'games',
        GameHistoryEntry.fromJson,
      );

  /// `GET /history/:partyId` → 404 with `{error}` only (code `NOT_FOUND`).
  Future<GameDetails> details(String partyId) async =>
      GameDetails.fromJson(await _api.get('/history/$partyId'));

  static Map<String, String> _paging(int? limit, int? offset) => {
    if (limit != null) 'limit': '$limit',
    if (offset != null) 'offset': '$offset',
  };
}
