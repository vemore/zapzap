import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/providers/game_provider.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_hand_size_selector.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_round_end.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/playing_card.dart';

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

  /// How many lines the turn banner is drawn on.
  int bannerLines(WidgetTester tester) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const Key('turnBanner')),
        matching: find.byType(RichText),
      ),
    );
    final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
    return (paragraph.size.height / line).round();
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

    testWidgets('a Golden Score that ends pulls the choice back into range', (
      tester,
    ) async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'selectHandSize',
            isGoldenScore: true,
          ),
        ),
      );
      final transport = await pumpGame(tester, backend);

      await tester.tap(find.byKey(GameHandSizeSelector.sizeKey(10)));
      await tester.pumpAndSettle();
      expect(find.text('10 cartes par joueur'), findsOneWidget);

      // The round starts again outside Golden Score: 10 is gone, and a
      // selector still holding it would post a size the backend refuses.
      backend.state = gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'selectHandSize',
        ),
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'roundStarted',
        'type': 'roundStarted',
      });

      expect(find.byKey(GameHandSizeSelector.sizeKey(10)), findsNothing);
      expect(find.text('5 cartes par joueur'), findsOneWidget);

      await tester.tap(find.byKey(const Key('confirm-hand-size')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/selectHandSize'), {
        'handSize': 5,
      });
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
      expect(find.byKey(const Key('turnSteps')), findsOneWidget);
      expect(find.byKey(GamePlayerTable.seatKey(0)), findsOneWidget);
      expect(find.byKey(GamePlayerTable.seatKey(2)), findsOneWidget);
      expect(find.text('Toi'), findsOneWidget);
      // Nothing selected yet; one button, for the step at hand.
      expect(enabled(tester, 'play-cards'), isFalse);
      expect(find.byKey(const Key('draw-card')), findsNothing);

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
      expect(find.byKey(const Key('draw-card')), findsNothing);
      expect(enabled(tester, 'call-zapzap'), isFalse);
      expect(enabled(tester, 'draw-deck'), isFalse);
    });

    testWidgets(
      'a ZapZap hand enables the button, which calls once confirmed',
      (tester) async {
        final backend = playing(playerHand: [0, 13, 52]);
        await pumpGame(tester, backend);

        expect(enabled(tester, 'call-zapzap'), isTrue);

        await tester.tap(find.byKey(const Key('call-zapzap')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('zapzap-confirm')));
        await tester.pumpAndSettle();
        expect(backend.paths, contains('/api/game/p1/zapzap'));
      },
    );

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

    testWidgets('a move refused with NOT_IN_PARTY says so', (tester) async {
      final backend = playing(playerHand: [0, 13, 26]);
      backend.failures['POST /api/game/p1/play'] = (
        status: 403,
        body: {'error': 'not in party', 'code': GameErrorCode.notInParty},
      );
      await pumpGame(tester, backend);

      selectCard(tester, 0);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('play-cards')));
      await tester.pumpAndSettle();

      expect(find.text("Tu n'as pas de place à cette table."), findsOneWidget);
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
      expect(find.byKey(const Key('turnSteps')), findsOneWidget);
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

      expect(find.byKey(const Key('drawInstruction')), findsOneWidget);
      expect(find.text('Piocher'), findsOneWidget);
      expect(enabled(tester, 'draw-card'), isTrue);
      expect(enabled(tester, 'draw-deck'), isTrue);

      await tester.tap(find.byKey(GameTableArea.discardKey(8)));
      await tester.pumpAndSettle();
      expect(find.text('Prendre 9♠'), findsOneWidget);

      await tester.tap(find.byKey(const Key('draw-card')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {
        'source': 'played',
        'cardId': 8,
      });
    });

    testWidgets('Clear drops the discard card, so Take goes back to Draw', (
      tester,
    ) async {
      await pumpGame(
        tester,
        playing(currentAction: 'draw', lastCardsPlayed: [7, 8]),
      );

      // The hand is disabled in the draw phase, so Clear is the only way
      // back from a discard card picked by mistake.
      expect(enabled(tester, 'clear-selection'), isFalse);
      await tester.tap(find.byKey(GameTableArea.discardKey(8)));
      await tester.pumpAndSettle();
      expect(find.text('Prendre 9♠'), findsOneWidget);
      expect(enabled(tester, 'clear-selection'), isTrue);

      await tester.tap(find.byKey(const Key('clear-selection')));
      await tester.pumpAndSettle();

      expect(find.text('Piocher'), findsOneWidget);
      expect(find.textContaining('Prendre'), findsNothing);
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
      expect(find.textContaining('Prendre'), findsNothing);
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

  group('a refresh that fails', () {
    testWidgets('leaves the table on screen under a banner, and retries', (
      tester,
    ) async {
      final backend = playing(currentTurn: 1);
      final transport = await pumpGame(tester, backend);
      expectBoardStanding(tester);

      backend.failures['GET /api/game/p1/state'] = (
        status: 500,
        body: {'error': 'the refetch fell over', 'code': 'SERVER_ERROR'},
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'play',
        'type': 'gameAction',
      });

      // The move landed; only the refetch did not. The React board would
      // have replaced the whole table with an error page here.
      expectBoardStanding(tester);
      expect(find.byKey(const Key('gameStaleBanner')), findsOneWidget);
      expect(find.text('Partie indisponible'), findsNothing);

      backend.failures.clear();
      await tester.tap(find.byKey(const Key('retry-refresh')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gameStaleBanner')), findsNothing);
      expectBoardStanding(tester);
    });
  });

  group('the end of a round', () {
    /// The round MediumBot1 (seat 2) closed with the lowest hand: the call
    /// held, so it scores 0 and everybody else their hand's points.
    FakeGameBackend zapZapHeld() => FakeGameBackend(
      state: gameSnapshotJson(
        roundStatus: 'finished',
        gameState: gameStateJson(
          currentTurn: 2,
          currentAction: 'finished',
          zapZapCaller: 2,
          lowestHandPlayerIndex: 2,
          allHands: {
            '0': [0, 1, 2],
            '1': [10, 11],
            '2': [14],
          },
          roundScores: {'0': 28, '1': 49, '2': 0},
          scores: {'0': 28, '1': 49, '2': 0},
          handPoints: {'0': 28, '1': 49, '2': 2},
        ),
      ),
    );

    /// Vincent (seat 0) called on 4 points, EasyBot1 held 1: counteracted,
    /// so the caller takes `4 + (3 − 1) × 5 = 14` (`GAME_RULES.md`).
    FakeGameBackend zapZapCounteracted() => FakeGameBackend(
      state: gameSnapshotJson(
        roundStatus: 'finished',
        roundNumber: 4,
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'finished',
          zapZapCaller: 0,
          lowestHandPlayerIndex: 1,
          wasCounterActed: true,
          counterActedByPlayerIndex: 1,
          allHands: {
            '0': [0, 2],
            '1': [13],
            '2': [22, 9],
          },
          handPoints: {'0': 4, '1': 1, '2': 10},
          roundScores: {'0': 14, '1': 0, '2': 10},
          scores: {'0': 14, '1': 0, '2': 10},
        ),
      ),
    );

    double topOf(WidgetTester tester, int playerIndex) =>
        tester.getTopLeft(find.byKey(GameRoundEnd.playerKey(playerIndex))).dy;

    testWidgets('a ZapZap that held: the standings and the way on', (
      tester,
    ) async {
      final backend = zapZapHeld();
      await pumpGame(tester, backend);

      expect(find.byKey(const Key('roundOver')), findsOneWidget);
      expect(find.text('Manche terminée'), findsOneWidget);
      expect(find.text('Manche 1'), findsOneWidget);
      expect(find.byType(GameHand), findsNothing);

      // The call held: the green banner, no penalty.
      expect(find.text('MediumBot1 a réussi son ZapZap !'), findsOneWidget);
      expect(
        find.text(
          'Sa main valait 2 points, la plus basse de la table : '
          'MediumBot1 marque 0.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('ontré'), findsNothing);

      // Lowest round score first, and the badges of the player who closed.
      expect(topOf(tester, 2), lessThan(topOf(tester, 0)));
      expect(topOf(tester, 0), lessThan(topOf(tester, 1)));
      expect(find.byTooltip('Main la plus basse'), findsOneWidget);
      expect(find.byTooltip('ZapZap'), findsOneWidget);
      expect(find.text('Éliminé'), findsNothing);

      // This round's points beside the total, and every hand revealed.
      expect(find.text('+0'), findsOneWidget);
      expect(find.text('+28'), findsOneWidget);
      expect(find.text('+49'), findsOneWidget);
      expect(find.byType(PlayingCard), findsNWidgets(6));

      await tester.tap(find.byKey(const Key('next-round')));
      await tester.pumpAndSettle();
      expect(backend.paths, contains('/api/game/p1/nextRound'));
    });

    testWidgets('a counteracted ZapZap spells out the penalty', (tester) async {
      await pumpGame(tester, zapZapCounteracted());

      expect(find.text('Manche 4'), findsOneWidget);
      expect(
        find.text('Vincent a appelé ZapZap mais a été contré !'),
        findsOneWidget,
      );
      expect(
        find.text('Contré par EasyBot1 (1 ≤ 4) : 4 + 10 de pénalité.'),
        findsOneWidget,
      );
      expect(
        find.text('Pénalité : 4 + (3 − 1) × 5 = 14 points'),
        findsOneWidget,
      );

      // The counteracted caller pays and falls last; the lowest hand keeps
      // its crown even though it never called.
      expect(topOf(tester, 1), lessThan(topOf(tester, 2)));
      expect(topOf(tester, 2), lessThan(topOf(tester, 0)));
      expect(find.text('+14'), findsOneWidget);
      expect(find.byTooltip('Main la plus basse'), findsOneWidget);
      expect(find.byKey(const Key('next-round')), findsOneWidget);
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
              eliminatedPlayers: [2],
              // The backend points the lowest hand at the player it has
              // just put out, hand empty (seen locally, 2026-09-23).
              lowestHandPlayerIndex: 2,
              allHands: {
                '0': [5],
                '1': [6],
                '2': const <int>[],
              },
              handPoints: {'0': 0, '1': 30, '2': 40},
              roundScores: {'0': 0, '1': 30, '2': 40},
              scores: {'0': 12, '1': 60, '2': 110},
            ),
          ),
        ),
      );

      expect(find.text('Partie terminée'), findsOneWidget);
      expect(find.byKey(const Key('winnerBanner')), findsOneWidget);
      expect(find.text('VAINQUEUR'), findsOneWidget);
      expect(find.text('Vainqueur : Vincent'), findsOneWidget);
      expect(find.text('Score final : 12 points'), findsOneWidget);
      expect(find.text('Éliminé'), findsOneWidget);
      expect(
        find.byTooltip('Main la plus basse'),
        findsNothing,
        reason: 'a player who is out does not hold the lowest hand',
      );
      expect(find.text('Aucune carte en main'), findsOneWidget);
      expect(find.byKey(const Key('next-round')), findsNothing);

      await tester.tap(find.byKey(const Key('back-to-parties')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('roundOver')), findsNothing);
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

      expect(find.byKey(const Key('turnSteps')), findsOneWidget);
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

  group('leaving the board', () {
    testWidgets('the back control leads to the parties, not the lobby', (
      tester,
    ) async {
      // The lobby bounces a playing party straight back to the board
      // (`PartyLobbyProvider.load`), so going "back" there is a flash and
      // a remount, never a way out.
      await pumpGame(tester, playing());

      await tester.tap(find.byKey(const Key('game-back')));
      await tester.pumpAndSettle();

      expect(find.byType(GamePlayerTable), findsNothing);
      expect(find.text('Parties'), findsWidgets);
    });

    testWidgets('from the list, the back control pops back to it: the '
        "browser's Back never returns to the game", (tester) async {
      // What the router tells the browser: each new path, and whether it
      // replaces the entry on show rather than adding one.
      final reported = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        (call) async {
          if (call.method == 'routeInformationUpdated') {
            final arguments = call.arguments as Map;
            final path = Uri.parse(arguments['uri'] as String).path;
            reported.add(
              arguments['replace'] == true ? '$path (replace)' : path,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.navigation,
          null,
        ),
      );
      await pumpGame(tester, playing());
      final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
      // What the list does (`parties_screen.dart`): the game goes on top.
      router.go(AppRoutes.parties);
      await tester.pumpAndSettle();
      router.push(AppRoutes.gamePath('p1'));
      await tester.pumpAndSettle();
      expect(find.byType(GamePlayerTable), findsOneWidget);

      await tester.tap(find.byKey(const Key('game-back')));
      await tester.pumpAndSettle();

      expect(find.byType(GamePlayerTable), findsNothing);
      expect(router.state.uri.path, AppRoutes.parties);
      // Popped, not gone to: nothing is left under the list.
      expect(router.canPop(), isFalse);
      // A pop, like a `go`, reaches the browser as a new entry, and its
      // Back would reopen the game: the game's entry is replaced instead.
      expect(reported.last, '${AppRoutes.parties} (replace)');
    });
  });

  group('the cards', () {
    const phone = Size(360, 740);
    const seven = [0, 13, 26, 40, 51, 6, 19];

    /// This player's turn with [seven] in hand, the previous player's run
    /// of three up for grabs and, in the draw step, a run of three played.
    FakeGameBackend turn(String currentAction) => playing(
      currentAction: currentAction,
      playerHand: seven,
      lastCardsPlayed: const [32, 33, 34],
      cardsPlayed: currentAction == 'draw' ? const [3, 4, 5] : const [],
    );

    Set<int> selectedInHand(WidgetTester tester) =>
        tester.widget<CardFan>(find.byType(CardFan)).selectedCards;

    Iterable<PlayingCard> feltCards(WidgetTester tester) =>
        tester.widgetList<PlayingCard>(
          find.descendant(
            of: find.byType(GameTableArea),
            matching: find.byType(PlayingCard),
          ),
        );

    testWidgets('at 360×740 each of seven cards in hand is 76 px wide or '
        'more, and a tap at the centre of its visible part selects it', (
      tester,
    ) async {
      await pumpGame(tester, turn('play'), size: phone);

      final fan = find.byType(CardFan);
      final layout = CardFan.layoutFor(seven.length, tester.getSize(fan).width);
      expect(layout.rows, 2);
      final origin = tester.getTopLeft(fan);
      for (var i = 0; i < seven.length; i++) {
        final card = find.descendant(
          of: find.byKey(CardFan.itemKey(i)),
          matching: find.byType(PlayingCard),
        );
        expect(tester.getSize(card).width, greaterThanOrEqualTo(76));
        final visible = layout.visibleRect(i);
        expect(visible.width, greaterThanOrEqualTo(48));

        final centre = origin + visible.center;
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
        expect(selectedInHand(tester), {seven[i]}, reason: 'card $i');
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
        expect(selectedInHand(tester), isEmpty);
      }
    });

    testWidgets('at 360×740 the pile is 70 px wide, and the played cards '
        '49 in the draw step, which leaves the hand its room', (tester) async {
      await pumpGame(tester, turn('draw'), size: phone);
      expect(feltCards(tester), hasLength(6));
      final pile = [
        for (final id in const [32, 33, 34])
          tester.widget<PlayingCard>(find.byKey(GameTableArea.discardKey(id))),
      ];
      expect(pile.every((card) => card.width >= 70), isTrue);
      final played = feltCards(tester).where((card) => card.cardId < 32);
      expect(played.map((card) => card.width).toSet(), {
        CardSizes.tablePlayedDraw,
      });
    });

    testWidgets('on a wide screen they are 84 px wide', (tester) async {
      await pumpGame(tester, turn('draw'));
      final widths = feltCards(tester).map((card) => card.width).toSet();
      expect(widths.every((width) => width >= 84), isTrue, reason: '$widths');
    });

    testWidgets('a screen reader selects a card of the hand while playing', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpGame(tester, turn('play'), size: phone);

      tester.semantics.tap(find.semantics.byLabel('7 de Cœur'));
      await tester.pumpAndSettle();
      expect(selectedInHand(tester), {19});
      semantics.dispose();
    });

    testWidgets('a screen reader selects a card of the pile while drawing, '
        'and is offered no tap on the hand', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpGame(
        tester,
        playing(
          currentAction: 'draw',
          playerHand: const [0, 13, 26, 40, 51, 6],
          lastCardsPlayed: const [19, 32],
          cardsPlayed: const [3, 4, 5],
        ),
        size: phone,
      );

      tester.semantics.tap(find.semantics.byLabel('7 de Cœur'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PlayingCard>(find.byKey(GameTableArea.discardKey(19)))
            .selected,
        isTrue,
      );
      // The hand cannot be played in the draw step: no tap to offer.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('A de Pique'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isFalse,
      );
      semantics.dispose();
    });

    for (final step in ['play', 'draw']) {
      testWidgets('at 360×740 and a text scale of 1.5 ($step) nothing '
          'overflows and less than 24 px part the felt from the hand', (
        tester,
      ) async {
        await pumpGame(tester, turn(step), size: phone, textScale: 1.5);
        expect(tester.takeException(), isNull);
        final felt = tester.getRect(find.byKey(const Key('gameTable')));
        final hand = tester.getRect(find.byKey(const Key('gameHand')));
        expect(hand.top - felt.bottom, inInclusiveRange(0, 24));
      });
    }
  });

  group('failures', () {
    testWidgets('a party that cannot be loaded offers the lobby', (
      tester,
    ) async {
      await pumpGame(tester, FakeGameBackend());

      expect(find.text('Partie indisponible'), findsOneWidget);
      expect(find.byKey(const Key('game-back-body')), findsOneWidget);
    });

    testWidgets('a party that has not dealt yet says so', (tester) async {
      await pumpGame(
        tester,
        FakeGameBackend(state: gameSnapshotJson(gameState: null)),
      );

      expect(find.text('Partie pas encore commencée'), findsOneWidget);
    });

    testWidgets('the owner starting the party brings the board, no reload', (
      tester,
    ) async {
      final backend = FakeGameBackend(state: gameSnapshotJson(gameState: null));
      final transport = await pumpGame(tester, backend);
      expect(find.text('Partie pas encore commencée'), findsOneWidget);

      backend.state = gameSnapshotJson(
        gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
      );
      await broadcast(tester, transport, {
        'partyId': 'p1',
        'action': 'partyStarted',
        'type': 'partyUpdate',
      });

      expect(find.text('Partie pas encore commencée'), findsNothing);
      expectBoardStanding(tester);
    });

    testWidgets('the "not started" page retries by hand', (tester) async {
      // For a `partyStarted` this client missed while its channel was down.
      final backend = FakeGameBackend(state: gameSnapshotJson(gameState: null));
      await pumpGame(tester, backend);

      backend.state = gameSnapshotJson(
        gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
      );
      await tester.tap(find.byKey(const Key('retry-game')));
      await tester.pumpAndSettle();

      expectBoardStanding(tester);
    });
  });

  // Two parallel pull requests shipped clipping bugs the suite's default
  // 1100×3000 hid: every layout is pumped at a phone's size, and again at
  // the largest system font Android offers.
  group('a 360×740 phone', () {
    const phone = Size(360, 740);

    for (final scale in [1.0, 1.5, 2.0]) {
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

        expect(find.byKey(const Key('drawInstruction')), findsOneWidget);
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
                lowestHandPlayerIndex: 1,
                wasCounterActed: true,
                counterActedByPlayerIndex: 1,
                allHands: {
                  '0': [0, 1, 2, 3, 4, 5, 6],
                  '1': [20],
                  '2': [30, 31, 32],
                },
                handPoints: {'0': 28, '1': 1, '2': 20},
                roundScores: {'0': 28, '1': 0, '2': 30},
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byKey(const Key('roundOver')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('next-round')),
          200,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the end of a game fits at a text scale of $scale', (
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
                eliminatedPlayers: [1, 2],
                allHands: {
                  '0': [5],
                  '1': [6, 7],
                  '2': [8],
                },
                roundScores: {'0': 0, '1': 30, '2': 40},
                scores: {'0': 12, '1': 104, '2': 118},
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byKey(const Key('winnerBanner')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('back-to-parties')),
          200,
        );
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

      testWidgets('not my turn fits at a text scale of $scale', (tester) async {
        // The longest waiting banner a username can make: two lines.
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              players: [
                gamePlayersJson[0],
                {
                  'playerIndex': 1,
                  'userId': 'b1',
                  'username': 'AnExceptionallyLongUsernameForABot',
                },
                gamePlayersJson[2],
              ],
              gameState: gameStateJson(
                currentTurn: 1,
                currentAction: 'play',
                playerHand: [0, 1, 2, 3, 4, 5, 6],
                lastCardsPlayed: [7, 8, 9],
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expectBoardStanding(tester);
        expect(enabled(tester, 'play-cards'), isFalse);
        expect(bannerLines(tester), 2);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the tallest action bar fits at a text scale of $scale', (
        tester,
      ) async {
        // The steps, the named button, the invalid-play reason box and
        // ZapZap with its reason: the most the bar ever stacks.
        await pumpGame(
          tester,
          playing(playerHand: [0, 1, 2, 3, 4, 14, 30], lastCardsPlayed: [7]),
          size: phone,
          textScale: scale,
        );
        selectCard(tester, 0);
        selectCard(tester, 14);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('invalidPlayReason')), findsOneWidget);
        expect(find.byKey(const Key('turnSteps')), findsOneWidget);
        expect(
          find.text('ZapZap · main 22, il faut 5 ou moins'),
          findsOneWidget,
        );
        expectBoardStanding(tester);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a Golden Score hand of 10 fits at a text scale of $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              gameState: gameStateJson(
                currentTurn: 0,
                currentAction: 'play',
                isGoldenScore: true,
                eliminatedPlayers: [2],
                playerHand: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
                otherPlayersHandSizes: {'1': 10, '2': 0},
              ),
            ),
          ),
          size: phone,
          textScale: scale,
        );

        expectBoardStanding(tester);
        expect(
          tester.widget<CardFan>(find.byType(CardFan)).cards,
          hasLength(10),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  for (final scale in [1.0, 1.5, 2.0]) {
    testWidgets(
      'a wide screen puts the players beside the felt at a text scale of '
      '$scale',
      (tester) async {
        await pumpGame(
          tester,
          playing(lastCardsPlayed: [7, 8]),
          size: const Size(1280, 900),
          textScale: scale,
        );

        expectBoardStanding(tester);
        final table = tester.getTopLeft(find.byType(GamePlayerTable));
        final felt = tester.getTopLeft(find.byType(GameTableArea));
        expect(felt.dx, greaterThan(table.dx));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
