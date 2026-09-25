import '../models/bot.dart';
import '../models/json.dart';
import '../models/party.dart';
import '../services/api_client.dart';

/// `/api/party`, plus the lobby's `/api/bots` and `/api/players/connected`.
class PartyRepository {
  const PartyRepository(this._api);

  final ApiClient _api;

  /// `GET /party`: public parties, optionally one [status] ([PartyStatus]).
  Future<Page<PartySummary>> list({
    String? status,
    int? limit,
    int? offset,
  }) async {
    final json = await _api.get(
      '/party',
      query: {
        'status': ?status,
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
      },
    );
    return Page.fromJson(json, 'parties', PartySummary.fromJson);
  }

  /// `POST /party`. [playerCount] (3-8, the seats) is required: the backend
  /// answers 400 `VALIDATION_ERROR` without it. It is sent as
  /// `settings.playerCount` and overrides any in [settings].
  Future<CreatePartyResult> create({
    required String name,
    required int playerCount,
    String visibility = 'public',
    PartySettings settings = const PartySettings(),
    List<String> botIds = const [],
  }) async => CreatePartyResult.fromJson(
    await _api.post(
      '/party',
      body: {
        'name': name,
        'visibility': visibility,
        'settings': {...settings.toJson(), 'playerCount': playerCount},
        'botIds': botIds,
      },
    ),
  );

  /// `GET /party/:id` → 404 `PARTY_NOT_FOUND`.
  Future<PartyDetails> details(String partyId) async =>
      PartyDetails.fromJson(await _api.get('/party/$partyId'));

  /// `POST /party/:id/join` → 409 `PARTY_FULL`.
  Future<JoinPartyResult> join(String partyId, {String? inviteCode}) async =>
      JoinPartyResult.fromJson(
        await _api.post(
          '/party/$partyId/join',
          body: {'inviteCode': ?inviteCode},
        ),
      );

  /// `POST /party/:id/leave`; the new owner's id when the owner left.
  Future<String?> leave(String partyId) async {
    final json = await _api.post('/party/$partyId/leave');
    return Json.stringOrNull(json, 'newOwner');
  }

  /// `POST /party/:id/start` (owner only, 3-8 players) → 403 `NOT_OWNER`.
  Future<StartPartyResult> start(String partyId) async =>
      StartPartyResult.fromJson(await _api.post('/party/$partyId/start'));

  /// `DELETE /party/:id` → 403 `NOT_AUTHORIZED`.
  Future<void> delete(String partyId) async {
    await _api.delete('/party/$partyId');
  }

  /// `GET /bots`, optionally one [difficulty] (see [Bot.difficulty]).
  Future<List<Bot>> bots({String? difficulty}) async {
    final json = await _api.get(
      '/bots',
      query: {'difficulty': ?difficulty},
      authenticated: false,
    );
    return Json.list(json, 'bots', Bot.fromJson);
  }

  /// `GET /players/connected` (at most 5).
  Future<List<ConnectedPlayer>> connectedPlayers() async {
    final json = await _api.get('/players/connected', authenticated: false);
    return Json.list(json, 'players', ConnectedPlayer.fromJson);
  }
}
