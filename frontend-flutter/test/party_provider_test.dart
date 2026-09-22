import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/providers/connected_players_provider.dart';
import 'package:zapzap/providers/create_party_provider.dart';
import 'package:zapzap/providers/party_provider.dart';
import 'package:zapzap/repositories/party_repository.dart';

import 'party_helpers.dart';

void main() {
  PartyRepository repositoryOf(FakeLobbyBackend backend) =>
      PartyRepository(backend.client());

  group('CreatePartyProvider', () {
    Future<CreatePartyProvider> loaded(FakeLobbyBackend backend) async {
      final create = CreatePartyProvider(repositoryOf(backend));
      await create.loadBots();
      return create;
    }

    test('a difficulty asked twice seats two different bots', () async {
      final create = await loaded(FakeLobbyBackend());
      create
        ..setSlotBot(0, 'easy')
        ..setSlotBot(1, 'easy');

      expect(create.slots[0].botId, 'bot-easy-1');
      expect(create.slots[1].botId, 'bot-easy-2');
      expect(create.botCount, 2);
      expect(create.humanCount, 3);
    });

    test('a difficulty with no bot left leaves the seat human', () async {
      final create = await loaded(FakeLobbyBackend());
      create
        ..setSlotBot(0, 'easy')
        ..setSlotBot(1, 'easy')
        ..setSlotBot(2, 'easy');

      expect(create.slots[2].isBot, isFalse);
      expect(create.slots[2].difficulty, isNull);
      expect(create.availableBots(2, 'easy'), 0);
      // the seat that already holds one still counts it as its own
      expect(create.availableBots(0, 'easy'), 1);
    });

    test('freeing a seat gives its bot back', () async {
      final create = await loaded(FakeLobbyBackend());
      create
        ..setSlotBot(0, 'easy')
        ..setSlotBot(1, 'easy')
        ..setSlotHuman(0)
        ..setSlotBot(2, 'easy');

      expect(create.slots[2].botId, 'bot-easy-1');
      expect(
        create.slots.where((slot) => slot.isBot).map((slot) => slot.botId),
        ['bot-easy-2', 'bot-easy-1'],
      );
    });

    test('no bot account at all leaves every seat human', () async {
      final create = await loaded(FakeLobbyBackend(bots: const []));
      create.setSlotBot(0, 'easy');
      expect(create.slots[0].isBot, isFalse);
      expect(create.botCount, 0);
    });

    test('changing the seat count keeps what was configured', () async {
      final create = await loaded(FakeLobbyBackend());
      create
        ..setSlotBot(0, 'medium')
        ..setPlayerCount(8);

      expect(create.slots, hasLength(7));
      expect(create.slots[0].botId, 'bot-medium-1');
      expect(create.slots.last.isBot, isFalse);

      create.setPlayerCount(3);
      expect(create.slots, hasLength(2));
      expect(create.slots[0].botId, 'bot-medium-1');
    });

    test('the seat count stays between 3 and 8', () async {
      final create = await loaded(FakeLobbyBackend());
      create.setPlayerCount(99);
      expect(create.playerCount, maxPartyPlayers);
      create.setPlayerCount(0);
      expect(create.playerCount, minPartyPlayers);
      expect(create.slots, hasLength(minPartyPlayers - 1));
    });

    test('submitting sends the name, the seats and the bots', () async {
      final backend = FakeLobbyBackend(createdPartyId: 'p7');
      final create = await loaded(backend);
      create
        ..setPlayerCount(4)
        ..setVisibility('private')
        ..setSlotBot(0, 'easy')
        ..setSlotBot(1, 'medium');

      expect(await create.submit('  Soirée  '), 'p7');
      final body = backend.bodyOf('POST', '/api/party');
      expect(body['name'], 'Soirée');
      expect(body['visibility'], 'private');
      expect((body['settings']! as Map)['playerCount'], 4);
      expect(body['botIds'], ['bot-easy-1', 'bot-medium-1']);
      expect(create.error, isNull);
    });

    test('a refused create keeps the form and says why', () async {
      final backend = FakeLobbyBackend();
      backend.failures['POST /api/party'] = (
        status: 500,
        body: {'error': 'Failed', 'code': 'CREATE_PARTY_ERROR'},
      );
      final create = await loaded(backend);
      expect(await create.submit('Soirée'), isNull);
      expect(create.error, isNotNull);
      expect(create.busy, isFalse);
    });

    test('bots that cannot be loaded only mean no bot can be seated', () async {
      final backend = FakeLobbyBackend();
      backend.failures['GET /api/bots'] = (
        status: 500,
        body: {'error': 'boom'},
      );
      final create = await loaded(backend);
      expect(create.bots, isEmpty);
      create.setSlotBot(0, 'easy');
      expect(create.slots[0].isBot, isFalse);
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

  group('ConnectedPlayersProvider', () {
    test('the stream adds, removes and moves players', () async {
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

      events.add(
        const SseEvent({
          'type': 'userStatusChanged',
          'userId': 'u2',
          'status': 'game',
          'partyId': 'p1',
        }),
      );
      await pumpEventQueue();
      expect(players.players.first.status, 'game');
      expect(players.players.first.partyId, 'p1');

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
  });
}
