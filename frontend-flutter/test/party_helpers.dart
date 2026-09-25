import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/services/api_client.dart';

import 'auth_helpers.dart';

/// A row of `GET /party`, in the shape Node sends
/// (`test/fixtures/party_list.json`).
JsonMap partySummaryJson({
  required String id,
  String name = 'Fixture party',
  String ownerId = 'u1',
  String status = 'waiting',
  int playerCount = 1,
  int maxPlayers = 5,
  bool isMember = false,
}) => {
  'id': id,
  'name': name,
  'ownerId': ownerId,
  'status': status,
  'playerCount': playerCount,
  'maxPlayers': maxPlayers,
  'isMember': isMember,
  'createdAt': 1790094174,
};

/// A seat of `GET /party/:id`.
JsonMap partyPlayerJson({
  required String userId,
  required String username,
  required int playerIndex,
  String userType = 'human',
  String? botDifficulty,
}) => {
  'id': playerIndex + 1,
  'userId': userId,
  'username': username,
  'userType': userType,
  'botDifficulty': botDifficulty,
  'playerIndex': playerIndex,
  'joinedAt': 1790094174,
};

/// The whole answer of `GET /party/:id`.
JsonMap partyDetailsJson({
  required String id,
  String name = 'Fixture party',
  String ownerId = 'u1',
  String status = 'waiting',
  int playerCount = 5,
  List<JsonMap> players = const [],
}) => {
  'success': true,
  'party': {
    'id': id,
    'name': name,
    'ownerId': ownerId,
    'inviteCode': 'BGJARGH7',
    'visibility': 'public',
    'status': status,
    'settings': {
      'playerCount': playerCount,
      'allowSpectators': false,
      'roundTimeLimit': 0,
    },
    'currentRoundId': null,
    'createdAt': 1790094174,
    'updatedAt': 1790094174,
  },
  'players': players,
};

/// A bot account of `GET /bots`.
JsonMap botJson(String id, String username, String difficulty) => {
  'id': id,
  'username': username,
  'userType': 'bot',
  'botDifficulty': difficulty,
};

/// A connected player of `GET /players/connected`.
JsonMap connectedPlayerJson(
  String userId,
  String username, {
  String status = 'lobby',
}) => {
  'userId': userId,
  'username': username,
  'status': status,
  'partyId': null,
  'connectedAt': 1790094174000,
};

/// The two easy and two medium bots the local backend seeds
/// (`zapzap-backend seed`, `test/fixtures/bots.json`).
final List<JsonMap> defaultBots = [
  botJson('bot-easy-1', 'EasyBot1', 'easy'),
  botJson('bot-easy-2', 'EasyBot2', 'easy'),
  botJson('bot-medium-1', 'MediumBot1', 'medium'),
  botJson('bot-medium-2', 'MediumBot2', 'medium'),
];

/// A stand-in backend for the lobby screens: it answers the party routes
/// from fields the test sets, records every request, and can be made to
/// fail one route.
///
/// Anything it does not know answers `{"success": true}`, so a screen
/// calling one more route does not blow up a test about something else.
class FakeLobbyBackend {
  FakeLobbyBackend({
    this.parties = const [],
    this.details,
    List<JsonMap>? bots,
    this.connected = const [],
    this.createdPartyId = 'new-party',
  }) : bots = bots ?? defaultBots;

  List<JsonMap> parties;

  /// The answer of `GET /party/:id`; `null` answers 404 `PARTY_NOT_FOUND`.
  JsonMap? details;

  List<JsonMap> bots;
  List<JsonMap> connected;

  /// The id `POST /party` hands back.
  String createdPartyId;

  /// `'<METHOD> <path>'` (`'POST /api/party/p1/join'`) to the refusal that
  /// route answers instead.
  final Map<String, ({int status, JsonMap body})> failures = {};

  final List<http.Request> requests = [];

  /// When set, `GET /party` answers only once it completes: the list's
  /// loading state stays on screen until then.
  Completer<void>? partiesGate;

  /// The last body sent to [path], decoded.
  JsonMap bodyOf(String method, String path) => (jsonDecode(
    requests
        .lastWhere(
          (request) => request.method == method && request.url.path == path,
        )
        .body,
  ) as Map).cast<String, dynamic>();

  ApiClient client() =>
      ApiClient(config: testConfig, httpClient: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final failure = failures['${request.method} $path'];
    if (failure != null) {
      return _json(failure.body, failure.status);
    }
    if (path == '/api/party' && request.method == 'GET') {
      await partiesGate?.future;
      return _json({'success': true, 'parties': parties});
    }
    if (path == '/api/party' && request.method == 'POST') {
      return _json({
        'success': true,
        'party': {
          'id': createdPartyId,
          'name': 'Fixture party',
          'status': 'waiting',
        },
        'botsJoined': 0,
      });
    }
    if (path == '/api/bots') {
      return _json({'success': true, 'bots': bots});
    }
    if (path == '/api/players/connected') {
      return _json({'players': connected});
    }
    if (RegExp(r'^/api/party/[^/]+$').hasMatch(path)) {
      if (request.method == 'DELETE') return _json({'success': true});
      if (details == null) {
        return _json({
          'error': 'Party not found',
          'code': 'PARTY_NOT_FOUND',
        }, 404);
      }
      return _json(details!);
    }
    if (path.endsWith('/start')) {
      return _json({
        'success': true,
        'party': {'id': createdPartyId, 'status': 'playing'},
        'round': {'id': 'r1', 'roundNumber': 1, 'status': 'active'},
      });
    }
    if (path.endsWith('/join') || path.endsWith('/leave')) {
      return _json({
        'success': true,
        'party': {'id': createdPartyId},
      });
    }
    return _json({'success': true});
  }

  http.Response _json(JsonMap body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
