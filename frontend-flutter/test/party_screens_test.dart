import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:go_router/go_router.dart';
import 'package:zapzap/screens/create_party_screen.dart';
import 'package:zapzap/screens/game_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/screens/party_lobby_screen.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// The app signed in as Vincent (`u1`), with [backend] answering the API
  /// and a real-time channel the test drives.
  Future<FakeSseTransport> pumpApp(
    WidgetTester tester,
    FakeLobbyBackend backend, {
    String initialLocation = AppRoutes.parties,
    Size size = const Size(1000, 2000),
    double textScale = 1,
  }) async {
    // Tall enough that every button of a screen is built: a `ListView`
    // only builds what fits. The phone-width test below uses a real one.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final transport = FakeSseTransport();
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: initialLocation,
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: transport,
      ),
    );
    await tester.pumpAndSettle();
    return transport;
  }

  /// Sends one backend broadcast to every listening screen.
  Future<void> broadcast(
    WidgetTester tester,
    FakeSseTransport transport,
    JsonMap event,
  ) async {
    transport.last.send(jsonEncode(event));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  group('parties', () {
    testWidgets('each party shows its seats, its status and the one thing '
        'to do with it', (tester) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          parties: [
            partySummaryJson(id: 'p1', name: 'Open party', playerCount: 2),
            partySummaryJson(
              id: 'p2',
              name: 'My lobby',
              playerCount: 3,
              isMember: true,
            ),
            partySummaryJson(
              id: 'p3',
              name: 'My game',
              status: 'playing',
              playerCount: 4,
              isMember: true,
            ),
            partySummaryJson(
              id: 'p4',
              name: 'Packed',
              playerCount: 5,
              maxPlayers: 5,
            ),
          ],
        ),
      );

      expect(find.text('Open party'), findsOneWidget);
      expect(find.text('2 / 5'), findsOneWidget);
      expect(find.text('Rejointe'), findsNWidgets(2));
      expect(enabled(tester, 'join-p1'), isTrue);
      expect(find.text('Retour au salon'), findsOneWidget);
      expect(find.text('Reprendre la partie'), findsOneWidget);
      expect(enabled(tester, 'join-p4'), isFalse);
      expect(find.text('Complète'), findsOneWidget);
    });

    testWidgets('a seat taken elsewhere shows up without a pull, once the '
        'burst is over', (tester) async {
      final backend = FakeLobbyBackend(
        parties: [
          partySummaryJson(id: 'p1', name: 'Open party', playerCount: 2),
        ],
      );
      final transport = await pumpApp(tester, backend);
      expect(find.text('2 / 5'), findsOneWidget);

      backend.parties = [
        partySummaryJson(id: 'p1', name: 'Open party', playerCount: 3),
      ];
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'userId': 'u2',
        'action': 'playerJoined',
        'playerIndex': 2,
      });
      // Debounced: nothing yet, in case more seats follow.
      expect(find.text('2 / 5'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('3 / 5'), findsOneWidget);
      expect(find.text('2 / 5'), findsNothing);
    });

    testWidgets('a party deleted elsewhere leaves the list', (tester) async {
      final backend = FakeLobbyBackend(
        parties: [partySummaryJson(id: 'p1', name: 'Doomed party')],
      );
      final transport = await pumpApp(tester, backend);
      expect(find.text('Doomed party'), findsOneWidget);

      backend.parties = [];
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'partyDeleted',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Doomed party'), findsNothing);
      expect(find.text('Aucune partie disponible'), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      await pumpApp(tester, FakeLobbyBackend());
      expect(find.text('Aucune partie disponible'), findsOneWidget);
    });

    testWidgets('a failed first load shows the error, not an empty list', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      backend.failures['GET /api/party'] = (
        status: 500,
        body: {'error': 'boom'},
      );
      await pumpApp(tester, backend);

      expect(find.text('Une erreur est survenue. Réessaie.'), findsOneWidget);
      expect(find.text('Aucune partie disponible'), findsNothing);
    });

    testWidgets('a row without maxPlayers reads 5 seats and can be joined', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          parties: [
            partySummaryJson(id: 'p1', playerCount: 2)..remove('maxPlayers'),
          ],
        ),
      );

      expect(find.text('2 / 5'), findsOneWidget);
      expect(find.text('Complète'), findsNothing);
      expect(enabled(tester, 'join-p1'), isTrue);
    });

    testWidgets('joining takes a seat and opens the lobby', (tester) async {
      final backend = FakeLobbyBackend(
        parties: [partySummaryJson(id: 'p1', name: 'Open party')],
        details: partyDetailsJson(
          id: 'p1',
          name: 'Open party',
          players: [
            partyPlayerJson(userId: 'u1', username: 'Vincent', playerIndex: 0),
          ],
        ),
      );
      await pumpApp(tester, backend);

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();

      expect(
        backend.requests.map((request) => request.url.path),
        contains('/api/party/p1/join'),
      );
      expect(find.text('Joueurs (1/5)'), findsOneWidget);
    });

    testWidgets('a party the user is already in still opens its lobby', (
      tester,
    ) async {
      // `ALREADY_IN_PARTY` is a refusal React navigates on anyway.
      final backend = FakeLobbyBackend(
        parties: [partySummaryJson(id: 'p1')],
        details: partyDetailsJson(id: 'p1'),
      );
      backend.failures['POST /api/party/p1/join'] = (
        status: 409,
        body: {'error': 'already in party', 'code': 'ALREADY_IN_PARTY'},
      );
      await pumpApp(tester, backend);

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();

      expect(find.text('Joueurs (0/5)'), findsOneWidget);
    });

    testWidgets('a refused join shows the reason and stays', (tester) async {
      final backend = FakeLobbyBackend(parties: [partySummaryJson(id: 'p1')]);
      backend.failures['POST /api/party/p1/join'] = (
        status: 409,
        body: {'error': 'Party is full', 'code': 'PARTY_FULL'},
      );
      await pumpApp(tester, backend);

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();

      expect(find.text('Cette partie est complète.'), findsOneWidget);
      expect(find.text('Parties disponibles'), findsOneWidget);
    });
  });

  group('create party', () {
    /// Picks [option] in the selector of the configurable seat [index].
    Future<void> chooseSlot(
      WidgetTester tester,
      int index,
      String option,
    ) async {
      await tester.tap(find.byKey(Key('slot-$index-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option).last);
      await tester.pumpAndSettle();
    }

    testWidgets('two seats asking for the same difficulty never get the '
        'same bot, and the difficulty then runs out', (tester) async {
      final backend = FakeLobbyBackend(
        createdPartyId: 'p9',
        details: partyDetailsJson(id: 'p9'),
      );
      await pumpApp(tester, backend, initialLocation: AppRoutes.createParty);

      await tester.tap(find.byKey(const Key('player-count')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('4').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('slot-2')), findsOneWidget);

      await chooseSlot(tester, 0, 'Bot — Facile');
      await chooseSlot(tester, 1, 'Bot — Facile');
      expect(find.text('Humains : 2 · Bots : 2'), findsOneWidget);

      // Both easy bots are seated: the third seat cannot have one.
      await tester.tap(find.byKey(const Key('slot-2-type')));
      await tester.pumpAndSettle();
      expect(find.text('Bot — Facile (aucun disponible)'), findsOneWidget);
      await tester.tap(find.text('Bot — Moyen').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('party-name')), '  Soirée  ');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pumpAndSettle();

      final body = backend.bodyOf('POST', '/api/party');
      expect(body['name'], 'Soirée');
      expect(body['visibility'], 'public');
      expect((body['settings']! as Map)['playerCount'], 4);
      final botIds = (body['botIds']! as List).cast<String>();
      expect(botIds, hasLength(3));
      expect(botIds.toSet(), hasLength(3));
      expect(botIds, containsAll(['bot-easy-1', 'bot-easy-2']));
      // and it lands on the new party's lobby
      expect(find.text('Joueurs (0/5)'), findsOneWidget);
    });

    testWidgets('a refusal is shown and the form stays', (tester) async {
      final backend = FakeLobbyBackend();
      backend.failures['POST /api/party'] = (
        status: 500,
        body: {'error': 'Failed', 'code': 'CREATE_PARTY_ERROR'},
      );
      await pumpApp(tester, backend, initialLocation: AppRoutes.createParty);

      await tester.enterText(find.byKey(const Key('party-name')), 'Soirée');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Une erreur est survenue. Réessaie.'), findsOneWidget);
      expect(find.byKey(const Key('create-submit')), findsOneWidget);
    });
  });

  group('lobby', () {
    FakeLobbyBackend backendWith(List<JsonMap> players) => FakeLobbyBackend(
      details: partyDetailsJson(
        id: 'p1',
        name: 'Fixture party',
        ownerId: 'u1',
        playerCount: 5,
        players: players,
      ),
    );

    final vincent = partyPlayerJson(
      userId: 'u1',
      username: 'Vincent',
      playerIndex: 0,
    );
    final easyBot = partyPlayerJson(
      userId: 'b1',
      username: 'EasyBot1',
      playerIndex: 1,
      userType: 'bot',
      botDifficulty: 'easy',
    );
    final second = partyPlayerJson(
      userId: 'u2',
      username: 'Alice',
      playerIndex: 2,
    );

    testWidgets('start stays disabled below three players and the empty '
        'seats are shown', (tester) async {
      await pumpApp(
        tester,
        backendWith([vincent, easyBot]),
        initialLocation: AppRoutes.partyPath('p1'),
      );

      expect(find.text('Joueurs (2/5)'), findsOneWidget);
      expect(find.text('Encore 1 joueur pour démarrer'), findsOneWidget);
      expect(find.text('En attente d\'un joueur…'), findsNWidgets(3));
      expect(find.text('Facile'), findsOneWidget);
      expect(enabled(tester, 'start-party'), isFalse);
    });

    testWidgets('a second client joining shows up without a refresh, and '
        'start becomes possible', (tester) async {
      final backend = backendWith([vincent, easyBot]);
      final transport = await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );
      expect(find.text('Alice'), findsNothing);
      expect(enabled(tester, 'start-party'), isFalse);

      // Another client took a seat: the backend now has three players and
      // the stream says so.
      backend.details = partyDetailsJson(
        id: 'p1',
        ownerId: 'u1',
        players: [vincent, easyBot, second],
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'userId': 'u2',
        'action': 'playerJoined',
        'playerIndex': 2,
      });

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Joueurs (3/5)'), findsOneWidget);
      expect(find.text('Encore 1 joueur pour démarrer'), findsNothing);
      expect(enabled(tester, 'start-party'), isTrue);
    });

    testWidgets('an event about another party is ignored', (tester) async {
      final backend = backendWith([vincent, easyBot]);
      final transport = await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );
      backend.details = partyDetailsJson(
        id: 'p1',
        ownerId: 'u1',
        players: [vincent, easyBot, second],
      );
      await broadcast(tester, transport, {
        'partyId': 'other',
        'userId': 'u2',
        'action': 'playerJoined',
      });

      expect(find.text('Alice'), findsNothing);
      expect(find.text('Joueurs (2/5)'), findsOneWidget);
    });

    testWidgets('starting the game leads to the game route', (tester) async {
      final backend = backendWith([vincent, easyBot, second]);
      await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );

      expect(enabled(tester, 'start-party'), isTrue);
      await tester.tap(find.byKey(const Key('start-party')));
      await tester.pumpAndSettle();

      expect(
        backend.requests.map((request) => request.url.path),
        contains('/api/party/p1/start'),
      );
      expect(find.byType(GameScreen), findsOneWidget);
    });

    testWidgets('another client starting the game leads there too', (
      tester,
    ) async {
      final transport = await pumpApp(
        tester,
        backendWith([vincent, easyBot, second]),
        initialLocation: AppRoutes.partyPath('p1'),
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'userId': 'u2',
        'action': 'partyStarted',
        'roundId': 'r1',
      });

      expect(find.byType(GameScreen), findsOneWidget);
    });

    testWidgets('the party being deleted goes back to the list', (
      tester,
    ) async {
      final transport = await pumpApp(
        tester,
        backendWith([vincent, easyBot]),
        initialLocation: AppRoutes.partyPath('p1'),
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'userId': 'u1',
        'action': 'partyDeleted',
      });

      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('deleting asks first, then goes back to the list', (
      tester,
    ) async {
      final backend = backendWith([vincent, easyBot]);
      await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );

      await tester.tap(find.byKey(const Key('delete-party')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(
        backend.requests.where((request) => request.method == 'DELETE'),
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('delete-party')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('delete-confirm-ok')));
      await tester.pumpAndSettle();

      expect(
        backend.requests
            .where((request) => request.method == 'DELETE')
            .map((request) => request.url.path),
        ['/api/party/p1'],
      );
      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('leaving goes back to the list', (tester) async {
      final backend = backendWith([vincent, easyBot]);
      await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );

      await tester.tap(find.byKey(const Key('leave-party')));
      await tester.pumpAndSettle();

      expect(
        backend.requests.map((request) => request.url.path),
        contains('/api/party/p1/leave'),
      );
      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('leaving a party someone already took you out of says so', (
      tester,
    ) async {
      final backend = backendWith([vincent, easyBot]);
      backend.failures['POST /api/party/p1/leave'] = (
        status: 403,
        body: {'error': 'User is not in this party', 'code': 'NOT_IN_PARTY'},
      );
      await pumpApp(
        tester,
        backend,
        initialLocation: AppRoutes.partyPath('p1'),
      );

      await tester.tap(find.byKey(const Key('leave-party')));
      await tester.pumpAndSettle();

      expect(find.text("Tu n'as pas de place à cette table."), findsOneWidget);
    });

    testWidgets('a party that does not exist says so', (tester) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(),
        initialLocation: AppRoutes.partyPath('gone'),
      );
      expect(find.text('Partie introuvable'), findsOneWidget);
    });

    testWidgets('someone who owns nothing sees neither start nor delete', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          details: partyDetailsJson(
            id: 'p1',
            ownerId: 'someone-else',
            players: [
              partyPlayerJson(userId: 'u9', username: 'Owner', playerIndex: 0),
              partyPlayerJson(
                userId: 'u1',
                username: 'Vincent',
                playerIndex: 1,
              ),
            ],
          ),
        ),
        initialLocation: AppRoutes.partyPath('p1'),
      );

      expect(find.byKey(const Key('start-party')), findsNothing);
      expect(find.byKey(const Key('delete-party')), findsNothing);
      expect(find.byKey(const Key('leave-party')), findsOneWidget);
    });

    testWidgets('the only human at a table of bots may delete it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          details: partyDetailsJson(
            id: 'p1',
            ownerId: 'someone-else',
            players: [
              partyPlayerJson(
                userId: 'u1',
                username: 'Vincent',
                playerIndex: 0,
              ),
              easyBot,
            ],
          ),
        ),
        initialLocation: AppRoutes.partyPath('p1'),
      );

      expect(find.byKey(const Key('start-party')), findsNothing);
      expect(find.byKey(const Key('delete-party')), findsOneWidget);
    });
  });

  group('phone width', () {
    // Anything that does not fit throws a layout error, which fails the
    // test: the screens have to work on a phone, which the React header
    // does not.
    const phone = Size(360, 740);

    testWidgets('the party list fits', (tester) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          parties: [
            partySummaryJson(
              id: 'p1',
              name: 'Une partie au nom particulièrement long',
              playerCount: 2,
              isMember: true,
            ),
          ],
          connected: [connectedPlayerJson('u1', 'Vincent')],
        ),
        size: phone,
      );
      expect(find.byKey(const Key('party-p1')), findsOneWidget);
    });

    testWidgets('the lobby fits', (tester) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(
          details: partyDetailsJson(
            id: 'p1',
            name: 'Une partie au nom particulièrement long',
            ownerId: 'u1',
            players: [
              partyPlayerJson(
                userId: 'u1',
                username: 'Vincent',
                playerIndex: 0,
              ),
              partyPlayerJson(
                userId: 'b1',
                username: 'HardVinceBot1',
                playerIndex: 1,
                userType: 'bot',
                botDifficulty: 'hard_vince',
              ),
            ],
          ),
        ),
        initialLocation: AppRoutes.partyPath('p1'),
        size: phone,
      );
      expect(find.text('Joueurs (2/5)'), findsOneWidget);
    });

    testWidgets('the create form fits', (tester) async {
      await pumpApp(
        tester,
        FakeLobbyBackend(),
        initialLocation: AppRoutes.createParty,
        size: phone,
      );
      expect(find.byKey(const Key('slot-3')), findsOneWidget);
    });

    // A large system font size is the same layout with everything taller
    // and wider; a tile of a fixed height, or a row of unconstrained
    // texts, overflows there and nowhere else.
    for (final scale in [1.5, 2.0]) {
      testWidgets('the party list fits at a $scale text scale', (tester) async {
        await pumpApp(
          tester,
          FakeLobbyBackend(
            parties: [
              partySummaryJson(
                id: 'p1',
                name: 'Une partie au nom particulièrement long',
                playerCount: 2,
                isMember: true,
              ),
              partySummaryJson(id: 'p2', name: 'Deuxième', playerCount: 3),
            ],
            connected: [connectedPlayerJson('u1', 'Vincent')],
          ),
          size: phone,
          textScale: scale,
        );
        expect(find.byKey(const Key('party-p1')), findsOneWidget);
        expect(find.byKey(const Key('open-p1')), findsOneWidget);
      });

      testWidgets('the lobby fits at a $scale text scale', (tester) async {
        await pumpApp(
          tester,
          FakeLobbyBackend(
            details: partyDetailsJson(
              id: 'p1',
              name: 'Une partie au nom particulièrement long',
              ownerId: 'u1',
              players: [
                partyPlayerJson(
                  userId: 'u1',
                  username: 'Vincent-au-pseudo-très-long',
                  playerIndex: 0,
                ),
                partyPlayerJson(
                  userId: 'b1',
                  username: 'HardVinceBot1',
                  playerIndex: 1,
                  userType: 'bot',
                  botDifficulty: 'hard_vince',
                ),
              ],
            ),
          ),
          initialLocation: AppRoutes.partyPath('p1'),
          size: phone,
          textScale: scale,
        );
        // A ListView lays out — and can overflow — only what is scrolled
        // into view: scroll down to its last button.
        await tester.scrollUntilVisible(
          find.byKey(const Key('leave-party')),
          200,
        );
        expect(find.byKey(const Key('lobby-seats-header')), findsOneWidget);
        expect(find.byKey(const Key('seat-b1')), findsOneWidget);
      });

      testWidgets('the create form fits at a $scale text scale', (
        tester,
      ) async {
        await pumpApp(
          tester,
          FakeLobbyBackend(),
          initialLocation: AppRoutes.createParty,
          size: phone,
          textScale: scale,
        );
        expect(find.byKey(const Key('slot-0')), findsOneWidget);
        // The form's ListView builds — and lays out — only what is in
        // view; its text fields are scrollables too.
        await tester.scrollUntilVisible(
          find.byKey(const Key('create-submit')),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('back navigation', () {
    // Android's system Back pops the route on top; a screen reached with
    // `go` would have nothing under it, and Back would leave the app.
    Future<void> systemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    FakeLobbyBackend backend() => FakeLobbyBackend(
      parties: [partySummaryJson(id: 'p1', name: 'Open party')],
      details: partyDetailsJson(
        id: 'p1',
        name: 'Open party',
        players: [
          partyPlayerJson(userId: 'u1', username: 'Vincent', playerIndex: 0),
        ],
      ),
      createdPartyId: 'p1',
    );

    testWidgets('Back from the create form returns to the list, as does '
        'its back button', (tester) async {
      await pumpApp(tester, backend());

      await tester.tap(find.byKey(const Key('create-party')));
      await tester.pumpAndSettle();
      expect(find.byType(CreatePartyScreen), findsOneWidget);
      await systemBack(tester);
      expect(find.byType(CreatePartyScreen), findsNothing);
      expect(find.byType(PartiesScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('create-party')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back-to-parties')));
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
    });

    testWidgets("the lobby a new party opens takes the form's place: Back "
        'returns to the list', (tester) async {
      await pumpApp(tester, backend());

      await tester.tap(find.byKey(const Key('create-party')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('party-name')), 'Soirée');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(PartyLobbyScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(PartyLobbyScreen), findsNothing);
      expect(find.byType(CreatePartyScreen), findsNothing);
      expect(find.byType(PartiesScreen), findsOneWidget);
    });

    testWidgets('Back from a joined lobby returns to the list', (tester) async {
      await pumpApp(tester, backend());

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();
      expect(find.byType(PartyLobbyScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(PartiesScreen), findsOneWidget);
    });

    testWidgets('leaving the lobby pops back to the list', (tester) async {
      await pumpApp(tester, backend());

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('leave-party')));
      await tester.pumpAndSettle();

      expect(find.byType(PartyLobbyScreen), findsNothing);
      expect(find.byType(PartiesScreen), findsOneWidget);
      // Popped, not stacked: one more Back would leave the app, not
      // return to the lobby.
      expect(
        GoRouter.of(tester.element(find.byType(PartiesScreen))).canPop(),
        isFalse,
      );
    });

    testWidgets('the game a lobby starts takes its place: Back returns to '
        'the list', (tester) async {
      final lobby = backend()
        ..details = partyDetailsJson(
          id: 'p1',
          players: [
            partyPlayerJson(userId: 'u1', username: 'Vincent', playerIndex: 0),
            partyPlayerJson(userId: 'u2', username: 'Alice', playerIndex: 1),
            partyPlayerJson(userId: 'u3', username: 'Bob', playerIndex: 2),
          ],
        );
      await pumpApp(tester, lobby);

      await tester.tap(find.byKey(const Key('join-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-party')));
      await tester.pumpAndSettle();
      expect(find.byType(GameScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.byType(PartyLobbyScreen), findsNothing);
      expect(find.byType(PartiesScreen), findsOneWidget);
    });

    testWidgets('a lobby opened by a link goes back to the list', (
      tester,
    ) async {
      await pumpApp(
        tester,
        backend(),
        initialLocation: AppRoutes.partyPath('p1'),
      );

      await tester.tap(find.byKey(const Key('back-to-parties')));
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
    });
  });

  group('connected players', () {
    testWidgets('no count before the first answer, nor after a failed one', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      backend.failures['GET /api/players/connected'] = (
        status: 500,
        body: {'error': 'boom'},
      );
      await pumpApp(tester, backend);

      // "0" would claim nobody is online.
      expect(
        tester
            .widget<Text>(find.byKey(const Key('connected-players-count')))
            .data,
        '–',
      );
    });

    testWidgets('the app bar counts them and the stream keeps it up to date', (
      tester,
    ) async {
      final transport = await pumpApp(
        tester,
        FakeLobbyBackend(connected: [connectedPlayerJson('u1', 'Vincent')]),
      );
      expect(find.text('1'), findsOneWidget);

      await broadcast(tester, transport, {
        'type': 'userConnected',
        'userId': 'u2',
        'username': 'Alice',
        'timestamp': 1790094174000,
      });
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('connected-players')));
      await tester.pumpAndSettle();
      expect(find.text('Joueurs connectés'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Salon'), findsNWidgets(2));
    });
  });
}
