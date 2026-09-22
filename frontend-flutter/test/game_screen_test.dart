import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/providers/game_provider.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_hand_size_selector.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_table_area.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// The app signed in as Vincent (`u1`), on `/game/p1`, with [backend]
  /// answering the API and a real-time channel the test drives.
  Future<FakeSseTransport> pumpGame(
    WidgetTester tester,
    FakeGameBackend backend, {
    Size size = const Size(1100, 3000),
    double textScale = 1,
  }) async {
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
        initialLocation: AppRoutes.gamePath('p1'),
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: transport,
      ),
    );
    await tester.pumpAndSettle();
    return transport;
  }

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

  /// Selects [cardId] through the fan's own callback. The cards of a fan
  /// overlap by design, so the centre of one is often covered by the next:
  /// a real tap is asserted on the card drawn on top ([tapTopCard]).
  void selectCard(WidgetTester tester, int cardId) {
    tester.widget<CardFan>(find.byType(CardFan)).onCardTap!(cardId);
  }

  /// Taps the one card of a single-card fan: no neighbour, no rotation, so
  /// the tap lands where it is aimed.
  Future<void> tapLoneCard(WidgetTester tester) async {
    await tester.tap(find.byKey(CardFan.itemKey(0)));
    await tester.pumpAndSettle();
  }

  /// The board is still there: the players, the felt and the hand.
  void expectBoardStanding(WidgetTester tester) {
    expect(find.byType(GamePlayerTable), findsOneWidget);
    expect(find.byType(GameTableArea), findsOneWidget);
    expect(find.byType(GameHand), findsOneWidget);
  }

  FakeGameBackend playing({
    int currentTurn = 0,
    String currentAction = 'play',
    List<int> playerHand = const [0, 1, 2, 30, 44],
    List<int> lastCardsPlayed = const [],
    List<int> cardsPlayed = const [],
    JsonMap? lastAction,
    List<int> eliminatedPlayers = const [],
  }) => FakeGameBackend(
    state: gameSnapshotJson(
      gameState: gameStateJson(
        currentTurn: currentTurn,
        currentAction: currentAction,
        playerHand: playerHand,
        lastCardsPlayed: lastCardsPlayed,
        cardsPlayed: cardsPlayed,
        lastAction: lastAction,
        eliminatedPlayers: eliminatedPlayers,
      ),
    ),
  );

  group('the hand-size phase', () {
    testWidgets('the starting player picks a size and deals', (tester) async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'selectHandSize',
          ),
        ),
      );
      await pumpGame(tester, backend);

      expect(find.text('Nombre de cartes'), findsOneWidget);
      expect(find.byKey(GameHandSizeSelector.sizeKey(4)), findsOneWidget);
      expect(find.byKey(GameHandSizeSelector.sizeKey(7)), findsOneWidget);
      expect(
        find.byKey(GameHandSizeSelector.sizeKey(8)),
        findsNothing,
        reason: 'only Golden Score goes past 7',
      );
      expect(find.text('5 cartes par joueur'), findsOneWidget);

      await tester.tap(find.byKey(GameHandSizeSelector.sizeKey(6)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-hand-size')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('POST', '/api/game/p1/selectHandSize'), {
        'handSize': 6,
      });
    });

    testWidgets('Golden Score offers up to 10 cards', (tester) async {
      await pumpGame(
        tester,
        FakeGameBackend(
          state: gameSnapshotJson(
            gameState: gameStateJson(
              currentTurn: 0,
              currentAction: 'selectHandSize',
              isGoldenScore: true,
            ),
          ),
        ),
      );

      expect(find.byKey(GameHandSizeSelector.sizeKey(10)), findsOneWidget);
      expect(find.text('7 cartes par joueur'), findsOneWidget);
    });

    testWidgets('anybody else waits for the starting player', (tester) async {
      await pumpGame(
        tester,
        FakeGameBackend(
          state: gameSnapshotJson(
            gameState: gameStateJson(
              currentTurn: 1,
              currentAction: 'selectHandSize',
            ),
          ),
        ),
      );

      expect(find.text('En attente'), findsOneWidget);
      expect(
        find.text('EasyBot1 choisit le nombre de cartes.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('confirm-hand-size')), findsNothing);
    });
  });

  group('the play phase', () {
    testWidgets('my turn: the board, the banner and a playable selection', (
      tester,
    ) async {
      final backend = playing(playerHand: [0, 13, 26]);
      await pumpGame(tester, backend);

      expectBoardStanding(tester);
      expect(find.text('À vous — posez des cartes'), findsOneWidget);
      expect(find.byKey(GamePlayerTable.seatKey(0)), findsOneWidget);
      expect(find.byKey(GamePlayerTable.seatKey(2)), findsOneWidget);
      expect(find.text('Vous'), findsOneWidget);
      // Nothing selected yet.
      expect(enabled(tester, 'play-cards'), isFalse);
      expect(enabled(tester, 'draw-card'), isFalse);

      // Three aces: a same-rank group, played in the order they were tapped.
      selectCard(tester, 26);
      selectCard(tester, 0);
      selectCard(tester, 13);
      await tester.pumpAndSettle();

      expect(find.text('3 sélectionnées'), findsOneWidget);
      expect(find.byKey(const Key('invalidPlayReason')), findsNothing);
      expect(enabled(tester, 'play-cards'), isTrue);

      await tester.tap(find.byKey(const Key('play-cards')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('POST', '/api/game/p1/play'), {
        'cardIds': [26, 0, 13],
      });
      expectBoardStanding(tester);
    });

    testWidgets('a tap on a card selects it and arms Play', (tester) async {
      final backend = playing(playerHand: [26]);
      await pumpGame(tester, backend);

      expect(enabled(tester, 'play-cards'), isFalse);
      await tapLoneCard(tester);

      expect(find.text('1 sélectionnée'), findsOneWidget);
      expect(enabled(tester, 'play-cards'), isTrue);

      await tester.tap(find.byKey(const Key('play-cards')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/play'), {
        'cardIds': [26],
      });
    });

    testWidgets('not my turn: everything is disabled and the banner says who', (
      tester,
    ) async {
      await pumpGame(tester, playing(currentTurn: 1));

      expectBoardStanding(tester);
      expect(find.text('En attente de EasyBot1'), findsOneWidget);
      expect(enabled(tester, 'play-cards'), isFalse);
      expect(enabled(tester, 'draw-card'), isFalse);
      expect(enabled(tester, 'call-zapzap'), isFalse);
      expect(enabled(tester, 'draw-deck'), isFalse);
    });

    testWidgets('a ZapZap hand shows its badge and enables the button', (
      tester,
    ) async {
      final backend = playing(playerHand: [0, 13, 52]);
      await pumpGame(tester, backend);

      expect(find.byKey(const Key('zapzapEligibleBadge')), findsOneWidget);
      expect(enabled(tester, 'call-zapzap'), isTrue);

      await tester.tap(find.byKey(const Key('call-zapzap')));
      await tester.pumpAndSettle();
      expect(backend.paths, contains('/api/game/p1/zapzap'));
    });

    testWidgets('an invalid selection shows its reason and keeps the board', (
      tester,
    ) async {
      // The React board replaces itself on any error; this one must not.
      await pumpGame(tester, playing(playerHand: [0, 14, 30]));

      selectCard(tester, 0);
      selectCard(tester, 14);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('invalidPlayReason')), findsOneWidget);
      expect(
        find.text("Une suite doit être d'une seule couleur"),
        findsOneWidget,
      );
      expect(enabled(tester, 'play-cards'), isFalse);
      expectBoardStanding(tester);
    });

    testWidgets('a play the backend refuses shows why and keeps the board', (
      tester,
    ) async {
      final backend = playing(playerHand: [0, 13, 26]);
      backend.failures['POST /api/game/p1/play'] = (
        status: 400,
        body: {'error': 'Invalid play', 'code': GameErrorCode.invalidPlay},
      );
      await pumpGame(tester, backend);

      selectCard(tester, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('play-cards')));
      await tester.pumpAndSettle();

      expect(find.text("Cette combinaison n'est pas valide."), findsOneWidget);
      expectBoardStanding(tester);
      expect(find.text('À vous — posez des cartes'), findsOneWidget);
    });
  });

  group('the draw phase', () {
    testWidgets('the deck button draws, the discard pile takes', (
      tester,
    ) async {
      final backend = playing(
        currentAction: 'draw',
        lastCardsPlayed: [7, 8],
        cardsPlayed: [20],
      );
      await pumpGame(tester, backend);

      expect(find.text('À vous — piochez une carte'), findsOneWidget);
      expect(find.text('Piocher'), findsOneWidget);
      expect(enabled(tester, 'draw-card'), isTrue);
      expect(enabled(tester, 'draw-deck'), isTrue);

      await tester.tap(find.byKey(GameTableArea.discardKey(8)));
      await tester.pumpAndSettle();
      expect(find.text('Prendre'), findsOneWidget);

      await tester.tap(find.byKey(const Key('draw-card')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {
        'source': 'played',
        'cardId': 8,
      });
    });

    testWidgets('the discard pile is dead outside my draw phase', (
      tester,
    ) async {
      await pumpGame(
        tester,
        playing(currentTurn: 1, currentAction: 'draw', lastCardsPlayed: [7]),
      );

      await tester.tap(
        find.byKey(GameTableArea.discardKey(7)),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(find.text('Prendre'), findsNothing);
    });

    testWidgets('a reshuffled deck raises its banner, then drops it', (
      tester,
    ) async {
      await pumpGame(
        tester,
        playing(
          currentTurn: 1,
          currentAction: 'play',
          lastAction: {
            'type': 'draw',
            'playerIndex': 1,
            'source': 'deck',
            'deckReshuffled': true,
            'timestamp': 1790094197863,
          },
        ),
      );

      expect(find.byKey(const Key('reshuffleBanner')), findsOneWidget);
      expect(
        find.text('EasyBot1 a pioché (pioche remélangée !)'),
        findsOneWidget,
      );

      await tester.pump(GameTableArea.reshuffleDuration);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reshuffleBanner')), findsNothing);
    });
  });

  group('the end of a round', () {
    testWidgets('shows the scores and the way on', (tester) async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          roundStatus: 'finished',
          gameState: gameStateJson(
            currentTurn: 2,
            currentAction: 'finished',
            zapZapCaller: 2,
            lowestHandPlayerIndex: 2,
            roundScores: {'0': 28, '1': 49, '2': 0},
            scores: {'0': 28, '1': 49, '2': 0},
            handPoints: {'0': 28, '1': 49, '2': 2},
          ),
        ),
      );
      await pumpGame(tester, backend);

      expect(find.byKey(const Key('roundOver')), findsOneWidget);
      expect(find.text('Manche terminée'), findsOneWidget);
      expect(find.text('ZapZap appelé par MediumBot1'), findsOneWidget);
      expect(find.text('Manche 49'), findsOneWidget);
      expect(find.byType(GameHand), findsNothing);

      await tester.tap(find.byKey(const Key('next-round')));
      await tester.pumpAndSettle();
      expect(backend.paths, contains('/api/game/p1/nextRound'));
    });

    testWidgets('a finished game names the winner and leads out', (
      tester,
    ) async {
      await pumpGame(
        tester,
        FakeGameBackend(
          state: gameSnapshotJson(
            roundStatus: 'finished',
            gameState: gameStateJson(
              currentTurn: 0,
              currentAction: 'finished',
              gameFinished: true,
              winner: {'playerIndex': 0, 'username': 'Vincent', 'score': 12},
              roundScores: {'0': 0},
            ),
          ),
        ),
      );

      expect(find.text('Partie terminée'), findsOneWidget);
      expect(find.text('Vainqueur : Vincent'), findsOneWidget);
      expect(find.byKey(const Key('next-round')), findsNothing);
    });
  });

  group('the event stream', () {
    testWidgets('another player\'s move refreshes the board', (tester) async {
      final backend = playing(currentTurn: 1);
      final transport = await pumpGame(tester, backend);

      backend.state = gameSnapshotJson(
        gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'draw',
        'type': 'gameAction',
      });

      expect(find.text('À vous — posez des cartes'), findsOneWidget);
    });

    testWidgets('a deleted party sends the player back to the list', (
      tester,
    ) async {
      final transport = await pumpGame(tester, playing());

      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'partyDeleted',
        'type': 'partyDeleted',
      });

      expect(find.byType(GamePlayerTable), findsNothing);
      expect(find.text('Parties'), findsWidgets);
    });
  });

  group('failures', () {
    testWidgets('a party that cannot be loaded offers the lobby', (
      tester,
    ) async {
      await pumpGame(tester, FakeGameBackend());

      expect(find.text('Partie indisponible'), findsOneWidget);
      expect(find.byKey(const Key('back-to-lobby-body')), findsOneWidget);
    });

    testWidgets('a party that has not dealt yet says so', (tester) async {
      await pumpGame(
        tester,
        FakeGameBackend(state: gameSnapshotJson(gameState: null)),
      );

      expect(find.text('Partie pas encore commencée'), findsOneWidget);
    });
  });

  // Two parallel pull requests shipped clipping bugs the suite's default
  // 1100×3000 hid: every layout is pumped at a phone's size, and again at
  // the largest system font Android offers.
  group('a 360×740 phone', () {
    const phone = Size(360, 740);

    for (final scale in [1.0, 1.5]) {
      testWidgets('the play phase fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          playing(
            playerHand: [0, 1, 2, 3, 4, 5, 6],
            lastCardsPlayed: [7, 8, 9],
            cardsPlayed: [20, 21],
            lastAction: {
              'type': 'play',
              'playerIndex': 2,
              'cardIds': [20, 21],
              'timestamp': 1790094197863,
            },
          ),
          size: phone,
          textScale: scale,
        );

        expectBoardStanding(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the draw phase fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          playing(
            currentAction: 'draw',
            playerHand: [0, 1, 2, 3, 4, 5, 6, 7],
            lastCardsPlayed: [30, 31, 32, 33],
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byKey(const Key('turnBanner')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the hand-size phase fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              gameState: gameStateJson(
                currentTurn: 0,
                currentAction: 'selectHandSize',
                isGoldenScore: true,
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byType(GameHandSizeSelector), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the end of a round fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              roundStatus: 'finished',
              gameState: gameStateJson(
                currentTurn: 2,
                currentAction: 'finished',
                zapZapCaller: 2,
                wasCounterActed: true,
                counterActedByPlayerIndex: 1,
                roundScores: {'0': 28, '1': 0, '2': 30},
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byKey(const Key('roundOver')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('an eliminated player fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          playing(currentTurn: 1, eliminatedPlayers: [2]),
          size: phone,
          textScale: scale,
        );

        expect(find.text('Éliminé'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('a wide screen puts the players beside the felt', (tester) async {
    await pumpGame(
      tester,
      playing(lastCardsPlayed: [7, 8]),
      size: const Size(1280, 900),
    );

    expectBoardStanding(tester);
    final table = tester.getTopLeft(find.byType(GamePlayerTable));
    final felt = tester.getTopLeft(find.byType(GameTableArea));
    expect(felt.dx, greaterThan(table.dx));
    expect(tester.takeException(), isNull);
  });
}
