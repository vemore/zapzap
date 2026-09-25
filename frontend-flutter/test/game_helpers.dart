import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/services/api_client.dart';

import 'auth_helpers.dart';

/// The three seats of the local backend's demo table: the caller and two
/// bots (`test/fixtures/game_state_playing.json`).
const List<JsonMap> gamePlayersJson = [
  {'playerIndex': 0, 'userId': 'u1', 'username': 'Vincent'},
  {'playerIndex': 1, 'userId': 'b1', 'username': 'EasyBot1'},
  {'playerIndex': 2, 'userId': 'b2', 'username': 'MediumBot1'},
];

/// A `gameState` of `GET /game/:id/state` (`game_state_playing.json`).
JsonMap gameStateJson({
  required int currentTurn,
  required String currentAction,
  int deckSize = 24,
  List<int> playerHand = const [0, 13, 26, 40, 51],
  List<int> lastCardsPlayed = const [],
  List<int> cardsPlayed = const [],
  Map<String, int> otherPlayersHandSizes = const {'1': 4, '2': 6},
  Map<String, int> scores = const {'0': 12, '1': 30, '2': 5},
  JsonMap? lastAction,
  bool isGoldenScore = false,
  List<int> eliminatedPlayers = const [],
  int startingPlayer = 0,
  Map<String, List<int>>? allHands,
  Map<String, int>? handPoints,
  int? zapZapCaller,
  int? lowestHandPlayerIndex,
  bool wasCounterActed = false,
  int? counterActedByPlayerIndex,
  Map<String, int>? roundScores,
  bool gameFinished = false,
  JsonMap? winner,
}) => {
  'currentTurn': currentTurn,
  'currentAction': currentAction,
  'deckSize': deckSize,
  'lastCardsPlayed': lastCardsPlayed,
  'cardsPlayed': cardsPlayed,
  'scores': scores,
  'playerHand': playerHand,
  'otherPlayersHandSizes': otherPlayersHandSizes,
  'lastAction': lastAction,
  'isGoldenScore': isGoldenScore,
  'eliminatedPlayers': eliminatedPlayers,
  'startingPlayer': startingPlayer,
  'allHands': allHands,
  'handPoints': handPoints,
  'zapZapCaller': zapZapCaller,
  'lowestHandPlayerIndex': lowestHandPlayerIndex,
  'wasCounterActed': wasCounterActed,
  'counterActedByPlayerIndex': counterActedByPlayerIndex,
  'roundScores': roundScores,
  'gameFinished': gameFinished,
  'winner': winner,
};

/// The whole answer of `GET /game/:id/state`. A `null` [gameState] is a
/// party that has not dealt yet.
JsonMap gameSnapshotJson({
  String id = 'p1',
  String name = 'Fixture party',
  JsonMap? gameState,
  List<JsonMap> players = gamePlayersJson,
  int roundNumber = 1,
  String roundStatus = 'active',
}) => {
  'success': true,
  'party': {
    'id': id,
    'name': name,
    'status': 'playing',
    'currentRoundId': 'r1',
  },
  'players': players,
  'round': {'id': 'r1', 'roundNumber': roundNumber, 'status': roundStatus},
  'gameState': gameState,
};

/// A stand-in backend for the board: it answers `GET /game/:id/state` from
/// [state], records every request, and can be made to refuse one route.
///
/// Anything it does not know answers `{"success": true}`, so a screen
/// calling one more route does not blow up a test about something else.
class FakeGameBackend {
  FakeGameBackend({this.state, this.connected = const []});

  /// The answer of `GET /game/:id/state`; `null` answers 404
  /// `PARTY_NOT_FOUND`.
  JsonMap? state;

  /// The answer of `GET /players/connected` (the app bar reads it).
  List<JsonMap> connected;

  /// `'<METHOD> <path>'` (`'POST /api/game/p1/play'`) to the refusal that
  /// route answers instead.
  final Map<String, ({int status, JsonMap body})> failures = {};

  /// Awaited before a `GET /state` answers, with the 1-based call number.
  /// The body is captured *before* the wait, so a test can hold answer 1
  /// back until answer 2 has landed and check which one the board keeps.
  Future<void> Function(int call)? onState;

  /// How many times `GET /state` has been called.
  int stateCalls = 0;

  final List<http.Request> requests = [];

  /// The paths of every request, in order.
  List<String> get paths =>
      requests.map((request) => request.url.path).toList();

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
    if (failure != null) return _json(failure.body, failure.status);
    if (path == '/api/players/connected') {
      return _json({'players': connected});
    }
    if (path.endsWith('/state')) {
      final call = ++stateCalls;
      final body = state;
      if (onState != null) await onState!(call);
      if (body == null) {
        return _json({
          'error': 'Party not found',
          'code': 'PARTY_NOT_FOUND',
        }, 404);
      }
      return _json(body);
    }
    if (path.endsWith('/play')) {
      return _json({
        'success': true,
        'cardsPlayed': <int>[],
        'remainingCards': 0,
      });
    }
    if (path.endsWith('/draw')) {
      return _json({
        'success': true,
        'cardDrawn': 7,
        'source': 'deck',
        'handSize': 5,
      });
    }
    if (path.endsWith('/selectHandSize')) {
      return _json({'success': true, 'handSize': 5});
    }
    if (path.endsWith('/zapzap')) {
      return _json({
        'success': true,
        'zapzapSuccess': true,
        'counteracted': false,
        'callerPoints': 3,
      });
    }
    if (path.endsWith('/nextRound')) {
      return _json({'success': true, 'gameFinished': false});
    }
    return _json({'success': true});
  }

  http.Response _json(JsonMap body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}
