import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:zapzap/models/party.dart';
import 'package:zapzap/providers/app_providers.dart';
import 'package:zapzap/repositories/admin_repository.dart';
import 'package:zapzap/repositories/auth_repository.dart';
import 'package:zapzap/repositories/game_repository.dart';
import 'package:zapzap/repositories/history_repository.dart';
import 'package:zapzap/repositories/party_repository.dart';
import 'package:zapzap/repositories/stats_repository.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/api_config.dart';

import 'fixtures.dart';

/// A fake backend: `'<METHOD> <path>'` → the fixture it answers with.
/// Records every request; an unknown route is a 404.
class FakeBackend {
  FakeBackend(this.routes);

  final Map<String, String> routes;
  final requests = <http.Request>[];

  late final api = ApiClient(
    config: const ApiConfig('https://z.test'),
    token: 'tok',
    httpClient: MockClient((request) async {
      requests.add(request);
      final name = routes['${request.method} ${request.url.path}'];
      if (name == null) return http.Response('', 404);
      return http.Response.bytes(utf8.encode(fixtureText(name)), 200);
    }),
  );

  http.Request get last => requests.last;
  Object? get lastBody => last.body.isEmpty ? null : jsonDecode(last.body);
  bool get lastAuthenticated => last.headers['Authorization'] == 'Bearer tok';
}

void main() {
  test('auth: login and register are sent without the token', () async {
    final backend = FakeBackend({
      'POST /api/auth/login': 'auth_login',
      'POST /api/auth/register': 'auth_register',
      'POST /api/auth/google': 'auth_login',
    });
    final auth = AuthRepository(backend.api);

    final session = await auth.login('Vincent', 'demo123');
    expect(session.user.username, 'Vincent');
    expect(backend.lastBody, {'username': 'Vincent', 'password': 'demo123'});
    expect(backend.lastAuthenticated, isFalse);

    await auth.register('new', 'secret');
    expect(backend.last.url.path, '/api/auth/register');
    expect(backend.lastAuthenticated, isFalse);

    await auth.loginWithGoogle('google-id-token');
    expect(backend.lastBody, {'credential': 'google-id-token'});
  });

  test('party: every route', () async {
    final backend = FakeBackend({
      'GET /api/party': 'party_list',
      'POST /api/party': 'party_create',
      'GET /api/party/p1': 'party_details',
      'POST /api/party/p1/join': 'party_join',
      'POST /api/party/p1/leave': 'party_leave',
      'POST /api/party/p1/start': 'party_start',
      'DELETE /api/party/p1': 'party_delete',
      'GET /api/bots': 'bots',
      'GET /api/players/connected': 'players_connected',
    });
    final party = PartyRepository(backend.api);

    final page = await party.list(status: PartyStatus.waiting, limit: 10);
    expect(page.items, hasLength(2));
    expect(backend.last.url.queryParameters, {
      'status': 'waiting',
      'limit': '10',
    });
    expect(backend.lastAuthenticated, isTrue);

    final created = await party.create(
      name: 'Friday',
      playerCount: 4,
      settings: const PartySettings(playerCount: 8, allowSpectators: true),
      botIds: ['b1'],
    );
    expect(created.botsJoined, 2);
    expect(backend.lastBody, {
      'name': 'Friday',
      'visibility': 'public',
      'settings': {'playerCount': 4, 'allowSpectators': true},
      'botIds': ['b1'],
    });
    // Without settings, playerCount is still sent (the backend answers 400
    // VALIDATION_ERROR without it), and never a key it no longer has.
    await party.create(name: 'Bare', playerCount: 3);
    expect(backend.lastBody, {
      'name': 'Bare',
      'visibility': 'public',
      'settings': {'playerCount': 3},
      'botIds': <String>[],
    });

    expect((await party.details('p1')).players, hasLength(3));
    expect((await party.join('p1')).party.name, 'Second');
    expect(backend.lastBody, isEmpty);
    await party.join('p1', inviteCode: 'CODE');
    expect(backend.lastBody, {'inviteCode': 'CODE'});
    expect(await party.leave('p1'), isNull);
    expect((await party.start('p1')).round.roundNumber, 1);
    await party.delete('p1');
    expect(backend.last.method, 'DELETE');

    final bots = await party.bots(difficulty: 'easy');
    expect(bots, hasLength(8));
    expect(backend.last.url.queryParameters, {'difficulty': 'easy'});
    expect(backend.lastAuthenticated, isFalse);
    expect(await party.connectedPlayers(), isEmpty);
  });

  test('party: create sends {playerCount, allowSpectators, roundTimeLimit}, '
      'never handSize or maxScore', () async {
    final backend = FakeBackend({'POST /api/party': 'party_create'});
    await PartyRepository(backend.api).create(
      name: 'Friday',
      playerCount: 5,
      settings: const PartySettings(allowSpectators: false, roundTimeLimit: 0),
    );
    final settings = (backend.lastBody! as Map)['settings'] as Map;
    expect(settings, {
      'playerCount': 5,
      'allowSpectators': false,
      'roundTimeLimit': 0,
    });
    for (final key in [
      'handSize',
      'maxScore',
      'enableGoldenScore',
      'goldenScoreThreshold',
    ]) {
      expect(settings.containsKey(key), isFalse, reason: key);
    }
  });

  test('game: every move', () async {
    final backend = FakeBackend({
      'GET /api/game/p1/state': 'game_state_finished',
      'POST /api/game/p1/selectHandSize': 'game_select_hand_size',
      'POST /api/game/p1/play': 'game_play',
      'POST /api/game/p1/draw': 'game_draw',
      'POST /api/game/p1/zapzap': 'game_zapzap',
      'POST /api/game/p1/nextRound': 'game_next_round',
    });
    final game = GameRepository(backend.api);

    expect((await game.state('p1')).gameState!.zapZapCaller, 2);
    expect((await game.selectHandSize('p1', 5)).handSize, 5);
    expect(backend.lastBody, {'handSize': 5});
    await game.play('p1', [3, 16]);
    expect(backend.lastBody, {
      'cardIds': [3, 16],
    });
    await game.drawFromDeck('p1');
    expect(backend.lastBody, {'source': 'deck'});
    await game.drawFromPlayed('p1', 45);
    expect(backend.lastBody, {'source': 'played', 'cardId': 45});
    expect((await game.zapZap('p1')).zapzapSuccess, isTrue);
    expect((await game.nextRound('p1')).round!.roundNumber, 2);
    expect(
      backend.requests.every((r) => r.headers['Authorization'] != null),
      isTrue,
    );
  });

  test('history', () async {
    final backend = FakeBackend({
      'GET /api/history': 'history_list',
      'GET /api/history/public': 'history_public',
      'GET /api/history/p1': 'history_details',
    });
    final history = HistoryRepository(backend.api);

    expect((await history.mine(limit: 5)).items, hasLength(1));
    expect(backend.last.url.queryParameters, {'limit': '5'});
    expect((await history.public()).items, hasLength(1));
    expect(backend.lastAuthenticated, isFalse);
    expect((await history.details('p1')).rounds, hasLength(5));
  });

  test('stats', () async {
    final backend = FakeBackend({
      'GET /api/stats/me': 'stats_me',
      'GET /api/stats/user/u1': 'stats_user',
      'GET /api/stats/leaderboard': 'stats_leaderboard',
      'GET /api/stats/bots': 'stats_bots',
    });
    final stats = StatsRepository(backend.api);

    expect((await stats.mine()).gamesPlayed, 1);
    expect(backend.lastAuthenticated, isTrue);
    expect((await stats.user('u1')).username, 'Vincent');
    expect((await stats.leaderboard(minGames: 1)).items.single.rank, 1);
    expect(backend.last.url.queryParameters, {'minGames': '1'});
    expect((await stats.bots()).byBot, hasLength(2));
  });

  test('admin', () async {
    final backend = FakeBackend({
      'GET /api/admin/users': 'admin_users',
      'DELETE /api/admin/users/u1': 'party_delete',
      'POST /api/admin/users/u1/admin': 'admin_set_admin',
      'GET /api/admin/parties': 'admin_parties',
      'POST /api/admin/parties/p1/stop': 'party_leave',
      'DELETE /api/admin/parties/p1': 'party_delete',
      'GET /api/admin/statistics': 'admin_statistics',
    });
    final admin = AdminRepository(backend.api);

    expect((await admin.users()).items, hasLength(8));
    await admin.deleteUser('u1');
    expect(backend.last.method, 'DELETE');
    await admin.setAdmin('u1', isAdmin: true);
    expect(backend.lastBody, {'isAdmin': true});
    expect((await admin.parties(status: 'finished')).items, hasLength(2));
    expect(backend.last.url.queryParameters, {'status': 'finished'});
    await admin.stopParty('p1');
    await admin.deleteParty('p1');
    expect((await admin.statistics()).totalUsers, 8);
    expect(
      backend.requests.every((r) => r.headers['Authorization'] != null),
      isTrue,
    );
  });

  testWidgets('appProviders exposes the client and every repository', (
    tester,
  ) async {
    final api = ApiClient(config: const ApiConfig('https://z.test'));
    late BuildContext context;
    await tester.pumpWidget(
      MultiProvider(
        providers: appProviders(
          apiConfig: const ApiConfig('https://z.test'),
          apiClient: api,
        ),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(context.read<ApiClient>(), same(api));
    expect(context.read<AuthRepository>(), isNotNull);
    expect(context.read<PartyRepository>(), isNotNull);
    expect(context.read<GameRepository>(), isNotNull);
    expect(context.read<HistoryRepository>(), isNotNull);
    expect(context.read<StatsRepository>(), isNotNull);
    expect(context.read<AdminRepository>(), isNotNull);
  });
}
