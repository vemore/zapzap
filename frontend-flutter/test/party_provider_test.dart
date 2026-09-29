import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/providers/connected_players_provider.dart';
import 'package:zapzap/providers/create_party_provider.dart';
import 'package:zapzap/providers/party_provider.dart';
import 'package:zapzap/repositories/party_repository.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/api_exception.dart';

import 'auth_helpers.dart';

import 'party_helpers.dart';

void main() {
  PartyRepository repositoryOf(FakeLobbyBackend backend) =>
      PartyRepository(backend.client());

  group('CreatePartyProvider', () {
    test('the seat count stays between 3 and 8', () {
      final create = CreatePartyProvider(repositoryOf(FakeLobbyBackend()));
      expect(create.playerCount, defaultPartyPlayers);
      create.setPlayerCount(99);
      expect(create.playerCount, maxPartyPlayers);
      create.setPlayerCount(0);
      expect(create.playerCount, minPartyPlayers);
    });

    test('submitting sends the name, the seats and no bot', () async {
      final backend = FakeLobbyBackend(createdPartyId: 'p7');
      final create = CreatePartyProvider(repositoryOf(backend))
        ..setPlayerCount(4)
        ..setVisibility('private');

      expect(await create.submit('  Soirée  '), 'p7');
      final body = backend.bodyOf('POST', '/api/party');
      expect(body['name'], 'Soirée');
      expect(body['visibility'], 'private');
      expect(body['settings'], {'playerCount': 4, 'turnTimeLimit': 0});
      expect(body['botIds'], isEmpty);
      expect(create.error, isNull);
      // The form asks for no bot: it never lists them
      expect(
        backend.requests.where((request) => request.url.path == '/api/bots'),
        isEmpty,
      );
    });

    test('the time per turn is off by default, one of 0/30/60/120, and sent '
        'as settings.turnTimeLimit', () async {
      final backend = FakeLobbyBackend(createdPartyId: 'p7');
      final create = CreatePartyProvider(repositoryOf(backend));
      expect(create.turnTimeLimit, 0);
      // The backend refuses anything else with 400 VALIDATION_ERROR.
      create.setTurnTimeLimit(45);
      expect(create.turnTimeLimit, 0);
      create.setTurnTimeLimit(120);
      expect(create.turnTimeLimit, 120);

      await create.submit('Soirée');
      final settings = backend.bodyOf('POST', '/api/party')['settings'];
      expect(settings, {
        'playerCount': defaultPartyPlayers,
        'turnTimeLimit': 120,
      });
      expect((settings as Map).containsKey('roundTimeLimit'), isFalse);
    });

    test('a refused create keeps the form and says why', () async {
      final backend = FakeLobbyBackend();
      backend.failures['POST /api/party'] = (
        status: 500,
        body: {'error': 'Failed', 'code': 'CREATE_PARTY_ERROR'},
      );
      final create = CreatePartyProvider(repositoryOf(backend));
      expect(await create.submit('Soirée'), isNull);
      expect(create.error, isNotNull);
      expect(create.busy, isFalse);
    });
  });

  group('PartyListProvider', () {
    test('already being in a party is not a refusal', () async {
      final backend = FakeLobbyBackend(parties: [partySummaryJson(id: 'p1')]);
      backend.failures['POST /api/party/p1/join'] = (
        status: 409,
        body: {'error': 'already in party', 'code': 'ALREADY_IN_PARTY'},
      );
      final list = PartyListProvider(repositoryOf(backend));
      await list.load();

      expect(list.parties, hasLength(1));
      expect(await list.join('p1'), isTrue);
      expect(list.error, isNull);
    });

    test('a full party is a refusal', () async {
      final backend = FakeLobbyBackend();
      backend.failures['POST /api/party/p1/join'] = (
        status: 409,
        body: {'error': 'Party is full', 'code': 'PARTY_FULL'},
      );
      final list = PartyListProvider(repositoryOf(backend));
      expect(await list.join('p1'), isFalse);
      expect(list.error, isNotNull);
    });

    int listRequests(FakeLobbyBackend backend) => backend.requests
        .where((r) => r.method == 'GET' && r.url.path == '/api/party')
        .length;

    test('a burst of events is one reload, a second after the last', () {
      fakeAsync((async) {
        final backend = FakeLobbyBackend(
          parties: [partySummaryJson(id: 'p1', playerCount: 1)],
        );
        final events = StreamController<SseEvent>.broadcast();
        final list = PartyListProvider(
          repositoryOf(backend),
          events: events.stream,
        );
        list.load();
        async.flushMicrotasks();
        expect(listRequests(backend), 1);
        expect(list.parties.single.playerCount, 1);

        // Three bots take their seats a few hundred milliseconds apart.
        backend.parties = [partySummaryJson(id: 'p1', playerCount: 4)];
        for (var i = 0; i < 3; i++) {
          events.add(
            const SseEvent({'partyId': 'p1', 'action': 'playerJoined'}),
          );
          async.elapse(const Duration(milliseconds: 400));
        }
        expect(listRequests(backend), 1);

        async.elapse(const Duration(milliseconds: 700));
        expect(listRequests(backend), 2);
        expect(list.parties.single.playerCount, 4);
        expect(list.loading, isFalse);
        list.dispose();
        events.close();
      });
    });

    test('a game move reloads nothing', () {
      fakeAsync((async) {
        final backend = FakeLobbyBackend();
        final events = StreamController<SseEvent>.broadcast();
        final list = PartyListProvider(
          repositoryOf(backend),
          events: events.stream,
        );
        for (final action in ['play', 'draw', 'selectHandSize', 'zapzap']) {
          events.add(SseEvent({'partyId': 'p1', 'action': action}));
        }
        async.elapse(const Duration(seconds: 2));
        expect(listRequests(backend), 0);
        list.dispose();
        events.close();
      });
    });

    test('a move that passes the turn in a running game of mine reloads; in '
        "a lobby of mine or someone else's game it does not", () {
      for (final action in PartyListProvider.turnActions) {
        fakeAsync((async) {
          final backend = FakeLobbyBackend(
            parties: [
              partySummaryJson(id: 'mine', status: 'playing', isMember: true),
              partySummaryJson(id: 'lobby', isMember: true),
              partySummaryJson(id: 'theirs', status: 'playing'),
            ],
          );
          final events = StreamController<SseEvent>.broadcast();
          final list = PartyListProvider(
            repositoryOf(backend),
            events: events.stream,
          )..load();
          async.flushMicrotasks();
          expect(listRequests(backend), 1);

          for (final other in ['lobby', 'theirs', 'unknown']) {
            events.add(SseEvent({'partyId': other, 'action': action}));
          }
          async.elapse(const Duration(seconds: 2));
          expect(listRequests(backend), 1, reason: '$action elsewhere');

          events.add(SseEvent({'partyId': 'mine', 'action': action}));
          async.elapse(const Duration(seconds: 1));
          expect(listRequests(backend), 2, reason: action);
          list.dispose();
          events.close();
        });
      }
    });

    test('a party created elsewhere reloads the list', () {
      expect(PartyListProvider.refreshingActions, contains('partyCreated'));
    });

    test('a game waiting for my move comes first among mine', () async {
      final backend = FakeLobbyBackend(
        parties: [
          partySummaryJson(id: 'done', status: 'finished', isMember: true),
          partySummaryJson(id: 'lobby', isMember: true),
          partySummaryJson(id: 'waits', status: 'playing', isMember: true),
          partySummaryJson(
            id: 'turn',
            status: 'playing',
            isMember: true,
            isMyTurn: true,
          ),
          partySummaryJson(id: 'theirs'),
        ],
      );
      final list = PartyListProvider(repositoryOf(backend));
      await list.load();
      expect(list.myParties.map((party) => party.id), [
        'turn',
        'waits',
        'lobby',
        'done',
      ]);
    });

    test('every party-changing action reloads', () {
      for (final action in PartyListProvider.refreshingActions) {
        fakeAsync((async) {
          final backend = FakeLobbyBackend();
          final events = StreamController<SseEvent>.broadcast();
          final list = PartyListProvider(
            repositoryOf(backend),
            events: events.stream,
          );
          events.add(SseEvent({'partyId': 'p1', 'action': action}));
          async.elapse(const Duration(seconds: 1));
          expect(listRequests(backend), 1, reason: action);
          list.dispose();
          events.close();
        });
      }
    });

    test('a seat given to a bot reloads, so an ejected player is no longer a member', () {
      // The game screen pops back to a list loaded before the ejection: without
      // a reload its row keeps isMember and offers "Resume" to a seat that is gone
      for (final action in ['playerReplaced', 'playerForfeited']) {
        expect(PartyListProvider.refreshingActions, contains(action));
      }
    });

    test('disposing cancels a pending reload and the subscription', () {
      fakeAsync((async) {
        final backend = FakeLobbyBackend();
        final events = StreamController<SseEvent>.broadcast();
        final list = PartyListProvider(
          repositoryOf(backend),
          events: events.stream,
        );
        events.add(const SseEvent({'partyId': 'p1', 'action': 'playerLeft'}));
        async.flushMicrotasks();
        list.dispose();
        expect(events.hasListener, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(listRequests(backend), 0);
        expect(async.pendingTimers, isEmpty);
        events.close();
      });
    });

    test('two loads answering out of order keep the newest', () async {
      final answers = <Completer<http.Response>>[];
      final client = ApiClient(
        config: testConfig,
        httpClient: MockClient((request) {
          final answer = Completer<http.Response>();
          answers.add(answer);
          return answer.future;
        }),
      );
      http.Response parties(int seats) => http.Response(
        jsonEncode({
          'success': true,
          'parties': [partySummaryJson(id: 'p1', playerCount: seats)],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
      final list = PartyListProvider(PartyRepository(client));

      // A pull-to-refresh, then an event's reload, both in flight.
      final older = list.load(showSpinner: false);
      final newer = list.load(showSpinner: false);
      await pumpEventQueue();
      expect(answers, hasLength(2));

      answers[1].complete(parties(3));
      await newer;
      expect(list.parties.single.playerCount, 3);

      // The older answer, a seat short, arrives last and is dropped.
      answers[0].complete(parties(2));
      await older;
      expect(list.parties.single.playerCount, 3);
      expect(list.error, isNull);
      list.dispose();
    });
  });

  group('PartyLobbyProvider', () {
    final vincent = partyPlayerJson(
      userId: 'u1',
      username: 'Vincent',
      playerIndex: 0,
    );
    final bot = partyPlayerJson(
      userId: 'b1',
      username: 'EasyBot1',
      playerIndex: 1,
      userType: 'bot',
      botDifficulty: 'easy',
    );
    final alice = partyPlayerJson(
      userId: 'u2',
      username: 'Alice',
      playerIndex: 2,
    );

    PartyLobbyProvider lobbyOf(
      FakeLobbyBackend backend,
      StreamController<SseEvent> events, {
      String? userId = 'u1',
    }) => PartyLobbyProvider(
      repositoryOf(backend),
      partyId: 'p1',
      events: events.stream,
      currentUserId: userId,
    );

    test(
      'a player joining reloads the seats; another party does not',
      () async {
        final backend = FakeLobbyBackend(
          details: partyDetailsJson(id: 'p1', players: [vincent, bot]),
        );
        final events = StreamController<SseEvent>.broadcast();
        addTearDown(events.close);
        final lobby = lobbyOf(backend, events);
        await lobby.load();

        expect(lobby.playerCount, 2);
        expect(lobby.canStart, isFalse);
        expect(lobby.missingPlayers, 1);

        backend.details = partyDetailsJson(
          id: 'p1',
          players: [vincent, bot, alice],
        );
        events.add(
          const SseEvent({'partyId': 'other', 'action': 'playerJoined'}),
        );
        await pumpEventQueue();
        expect(lobby.playerCount, 2);

        events.add(const SseEvent({'partyId': 'p1', 'action': 'playerJoined'}));
        await pumpEventQueue();
        expect(lobby.playerCount, 3);
        expect(lobby.canStart, isTrue);
        expect(lobby.missingPlayers, 0);
        lobby.dispose();
      },
    );

    test('the stream decides the way out', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(id: 'p1', players: [vincent, bot, alice]),
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();
      expect(lobby.outcome, isNull);

      events.add(const SseEvent({'partyId': 'p1', 'action': 'partyStarted'}));
      await pumpEventQueue();
      expect(lobby.outcome, LobbyOutcome.started);
      lobby.dispose();
    });

    test('a party already playing is one to go back to', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(
          id: 'p1',
          status: 'playing',
          players: [vincent, bot, alice],
        ),
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();
      expect(lobby.outcome, LobbyOutcome.started);
      lobby.dispose();
    });

    test('the owner is what isOwner says, not a match on ownerId', () async {
      final details = partyDetailsJson(id: 'p1', players: [vincent, bot]);
      expect(details['isOwner'], isTrue);
      details['isOwner'] = false;
      final backend = FakeLobbyBackend(details: details);
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();

      expect(lobby.details!.party.ownerId, 'u1');
      expect(lobby.isOwner, isFalse);
      lobby.dispose();
    });

    test('only the owner starts; the only human may still delete', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(
          id: 'p1',
          ownerId: 'someone-else',
          players: [vincent, bot],
        ),
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();

      expect(lobby.isOwner, isFalse);
      expect(lobby.canStart, isFalse);
      expect(lobby.isOnlyHuman, isTrue);
      expect(lobby.canDelete, isTrue);
      lobby.dispose();
    });

    test('a second human takes the delete right away', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(
          id: 'p1',
          ownerId: 'someone-else',
          players: [vincent, bot, alice],
        ),
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();

      expect(lobby.isOnlyHuman, isFalse);
      expect(lobby.canDelete, isFalse);
      lobby.dispose();
    });

    test('a party that is gone leaves no details', () async {
      final backend = FakeLobbyBackend();
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = lobbyOf(backend, events);
      await lobby.load();

      expect(lobby.details, isNull);
      expect(lobby.error, isNotNull);
      expect(lobby.canDelete, isFalse);
      lobby.dispose();
    });
  });

  group('PartyLobbyProvider bots', () {
    final vincent = partyPlayerJson(
      userId: 'u1',
      username: 'Vincent',
      playerIndex: 0,
    );
    final seatedEasy = partyPlayerJson(
      userId: 'bot-easy-1',
      username: 'EasyBot1',
      playerIndex: 1,
      userType: 'bot',
      botDifficulty: 'easy',
    );

    Future<PartyLobbyProvider> lobbyOf(FakeLobbyBackend backend) async {
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = PartyLobbyProvider(
        repositoryOf(backend),
        partyId: 'p1',
        events: events.stream,
        currentUserId: 'u1',
      );
      addTearDown(lobby.dispose);
      await lobby.load();
      await lobby.loadBots();
      return lobby;
    }

    test('a bot already at the table is not offered again', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(id: 'p1', players: [vincent, seatedEasy]),
      );
      final lobby = await lobbyOf(backend);

      expect(lobby.canAddBots, isTrue);
      expect(lobby.freeSeats, 3);
      expect(lobby.availableBots('easy'), 1);
      expect(lobby.availableBots('medium'), 2);
      expect(lobby.availableBots('hard'), 0);

      await lobby.addBot('easy');
      expect(backend.bodyOf('POST', '/api/party/p1/bots'), {
        'botId': 'bot-easy-2',
      });
      // Shown at once, without waiting for the event
      expect(lobby.playerCount, 3);
      expect(lobby.availableBots('easy'), 0);
      expect(lobby.error, isNull);
    });

    test('a guest cannot add bots, nor can anyone at a full table', () async {
      final guest = await lobbyOf(
        FakeLobbyBackend(
          details: partyDetailsJson(
            id: 'p1',
            ownerId: 'someone-else',
            players: [vincent],
          ),
        ),
      );
      expect(guest.canAddBots, isFalse);

      final full = await lobbyOf(
        FakeLobbyBackend(
          details: partyDetailsJson(
            id: 'p1',
            playerCount: 3,
            players: [
              vincent,
              seatedEasy,
              partyPlayerJson(userId: 'u2', username: 'Alice', playerIndex: 2),
            ],
          ),
        ),
      );
      expect(full.freeSeats, 0);
      expect(full.canAddBots, isFalse);
    });

    test('fill-and-start sends the level and goes to the game', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(id: 'p1', players: [vincent]),
      );
      final lobby = await lobbyOf(backend);

      await lobby.fillAndStart('hard');
      expect(backend.bodyOf('POST', '/api/party/p1/fill-and-start'), {
        'difficulty': 'hard',
      });
      expect(lobby.outcome, LobbyOutcome.started);
    });

    test('a refused fill stays in the lobby and says why', () async {
      final backend = FakeLobbyBackend(
        details: partyDetailsJson(id: 'p1', players: [vincent]),
      );
      backend.failures['POST /api/party/p1/fill-and-start'] = (
        status: 409,
        body: {'error': 'Not enough bots', 'code': 'NOT_ENOUGH_BOTS'},
      );
      final lobby = await lobbyOf(backend);

      await lobby.fillAndStart('easy');
      expect(lobby.outcome, isNull);
      expect(lobby.busy, isFalse);
      expect((lobby.error! as ApiException).code, PartyErrorCode.notEnoughBots);
    });
  });

  group('ConnectedPlayersProvider', () {
    test('the stream adds and removes players', () async {
      final backend = FakeLobbyBackend(
        connected: [connectedPlayerJson('u1', 'Vincent')],
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final players = ConnectedPlayersProvider(
        repositoryOf(backend),
        events: events.stream,
      );
      players.follow(true);
      await pumpEventQueue();
      expect(players.players.map((player) => player.username), ['Vincent']);

      events.add(
        const SseEvent({
          'type': 'userConnected',
          'userId': 'u2',
          'username': 'Alice',
        }),
      );
      await pumpEventQueue();
      expect(players.players.first.username, 'Alice');

      events.add(const SseEvent({'type': 'userDisconnected', 'userId': 'u2'}));
      await pumpEventQueue();
      expect(players.players.map((player) => player.username), ['Vincent']);

      // Five at most, the newest first.
      for (var i = 0; i < 6; i++) {
        events.add(
          SseEvent({
            'type': 'userConnected',
            'userId': 'x$i',
            'username': 'Player$i',
          }),
        );
      }
      await pumpEventQueue();
      expect(players.players, hasLength(5));
      expect(players.players.first.username, 'Player5');

      players.follow(false);
      expect(players.players, isEmpty);
      players.dispose();
    });

    test('the first load keeps five too', () async {
      final backend = FakeLobbyBackend(
        connected: [
          for (var i = 0; i < 7; i++) connectedPlayerJson('u$i', 'Player$i'),
        ],
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final players = ConnectedPlayersProvider(
        repositoryOf(backend),
        events: events.stream,
      );
      expect(players.loaded, isFalse);

      players.follow(true);
      await pumpEventQueue();

      expect(players.loaded, isTrue);
      expect(players.players, hasLength(ConnectedPlayersProvider.maxPlayers));
      expect(players.players.first.username, 'Player0');
      players.dispose();
    });

    test('each (re)connection of the stream loads the list again', () async {
      // The sign-in load can answer before the backend registers our own
      // stream (a lone player then saw 0): the connection reloads it.
      final backend = FakeLobbyBackend();
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final players = ConnectedPlayersProvider(
        repositoryOf(backend),
        events: events.stream,
      );
      players.follow(true);
      await pumpEventQueue();
      expect(players.players, isEmpty);

      backend.connected = [connectedPlayerJson('u1', 'Vincent')];
      players.follow(true, streamConnected: true);
      await pumpEventQueue();
      expect(players.players.map((player) => player.username), ['Vincent']);

      // Still connected: no reload. Dropped and back: reload.
      backend.connected = [
        connectedPlayerJson('u2', 'Alice'),
        connectedPlayerJson('u1', 'Vincent'),
      ];
      players.follow(true, streamConnected: true);
      await pumpEventQueue();
      expect(players.players, hasLength(1));

      players.follow(true);
      players.follow(true, streamConnected: true);
      await pumpEventQueue();
      expect(players.players.map((player) => player.username), [
        'Alice',
        'Vincent',
      ]);
      players.dispose();
    });

    test('a failed first load leaves it not loaded', () async {
      final backend = FakeLobbyBackend();
      backend.failures['GET /api/players/connected'] = (
        status: 500,
        body: {'error': 'boom'},
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final players = ConnectedPlayersProvider(
        repositoryOf(backend),
        events: events.stream,
      );

      players.follow(true);
      await pumpEventQueue();

      expect(players.loaded, isFalse);
      expect(players.players, isEmpty);
      players.dispose();
    });
  });

  group('PartyLobbyProvider sequencing', () {
    test('two loads answering out of order keep the newest', () async {
      // Each `GET /party/p1` waits on its own completer, so the test decides
      // the order the answers arrive in.
      final answers = <Completer<http.Response>>[];
      final client = ApiClient(
        config: testConfig,
        httpClient: MockClient((request) {
          final answer = Completer<http.Response>();
          answers.add(answer);
          return answer.future;
        }),
      );
      http.Response details(int seats) => http.Response(
        jsonEncode(
          partyDetailsJson(
            id: 'p1',
            players: [
              for (var i = 0; i < seats; i++)
                partyPlayerJson(
                  userId: 'u$i',
                  username: 'Player$i',
                  playerIndex: i,
                ),
            ],
          ),
        ),
        200,
        headers: {'content-type': 'application/json'},
      );
      final events = StreamController<SseEvent>.broadcast();
      addTearDown(events.close);
      final lobby = PartyLobbyProvider(
        PartyRepository(client),
        partyId: 'p1',
        events: events.stream,
        currentUserId: 'u0',
      );

      // Two players join a moment apart: two reloads in flight.
      final older = lobby.load(showSpinner: false);
      final newer = lobby.load(showSpinner: false);
      await pumpEventQueue();
      expect(answers, hasLength(2));

      answers[1].complete(details(3));
      await newer;
      expect(lobby.playerCount, 3);

      // The older answer, with one seat fewer, arrives last and is dropped.
      answers[0].complete(details(2));
      await older;
      expect(lobby.playerCount, 3);
      lobby.dispose();
    });
  });
}
