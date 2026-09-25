import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/utils/motion.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/playing_card.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

/// J9 of the UX study: played cards glide onto the felt, the card a draw
/// brings in is badged "Nouveau" for 2 s, and none of it moves when the
/// system asks for reduced motion (`MediaQuery.disableAnimations`).
void main() {
  /// [child] in French, with reduced motion when [still].
  Widget app(Widget child, {bool still = false}) => MediaQuery(
    data: MediaQueryData(size: const Size(400, 800), disableAnimations: still),
    child: MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Widget fan(
    List<int> cards, {
    Set<int> selected = const {},
    bool still = false,
  }) => app(
    SizedBox(
      width: 328,
      child: CardFan(cards: cards, selectedCards: selected),
    ),
    still: still,
  );

  Widget felt(
    List<int> cardsPlayed, {
    List<int> pile = const [],
    bool playedByMe = true,
    bool still = false,
  }) => app(
    SizedBox(
      width: 380,
      height: 400,
      child: GameTableArea(
        cardsPlayed: cardsPlayed,
        lastCardsPlayed: pile,
        playerName: (index) => 'P$index',
        playedByMe: playedByMe,
      ),
    ),
    still: still,
  );

  Finder badge(int cardId) => find.byKey(CardFan.freshBadgeKey(cardId));

  group('the card a draw brings in', () {
    testWidgets('is badged "Nouveau" for 2 s', (tester) async {
      await tester.pumpWidget(fan(const [0, 13, 26]));
      expect(find.text('Nouveau'), findsNothing);

      await tester.pumpWidget(fan(const [0, 13, 26, 7]));
      await tester.pump(const Duration(milliseconds: 250));
      expect(badge(7), findsOneWidget);
      expect(
        find.descendant(of: badge(7), matching: find.text('Nouveau')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1700));
      expect(badge(7), findsOneWidget, reason: 'not yet 2 s');
      await tester.pump(const Duration(milliseconds: 100));
      expect(badge(7), findsNothing);
    });

    testWidgets('a new deal, a play or a reorder is not a draw', (
      tester,
    ) async {
      await tester.pumpWidget(fan(const [0, 13]));
      await tester.pumpWidget(fan(const [0, 13, 26, 40, 51]));
      await tester.pumpWidget(fan(const [0, 13, 40]));
      await tester.pumpWidget(fan(const [40, 0, 13]));
      await tester.pump();
      expect(find.text('Nouveau'), findsNothing);
    });

    testWidgets('loses the badge when it leaves the hand', (tester) async {
      await tester.pumpWidget(fan(const [0, 13]));
      await tester.pumpWidget(fan(const [0, 13, 7]));
      await tester.pump();
      expect(badge(7), findsOneWidget);
      await tester.pumpWidget(fan(const [0, 13]));
      expect(badge(7), findsNothing);
      await tester.pump(Motion.freshCard);
    });
  });

  group('a card played', () {
    testWidgets('glides up onto the felt from the hand', (tester) async {
      await tester.pumpWidget(felt(const []));
      await tester.pumpWidget(felt(const [20]));
      final card = find.byType(PlayingCard);
      expect(find.byKey(GameTableArea.glideKey(20)), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 100));
      final flying = tester.getRect(card);
      await tester.pumpAndSettle();
      final landed = tester.getRect(card);
      expect(flying.top, greaterThan(landed.top), reason: 'from below');
      expect(flying.left, landed.left);
    });

    testWidgets("another player's glides down from the players", (
      tester,
    ) async {
      await tester.pumpWidget(felt(const [], playedByMe: false));
      await tester.pumpWidget(felt(const [], pile: [9], playedByMe: false));
      final card = find.byKey(GameTableArea.discardKey(9));
      await tester.pump(const Duration(milliseconds: 100));
      final flying = tester.getRect(card);
      await tester.pumpAndSettle();
      expect(flying.top, lessThan(tester.getRect(card).top), reason: 'above');
    });

    testWidgets('does not glide again from the played row to the pile', (
      tester,
    ) async {
      await tester.pumpWidget(felt(const [20]));
      await tester.pumpWidget(felt(const [], pile: [20]));
      expect(find.byKey(GameTableArea.glideKey(20)), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the first table drawn does not glide', (tester) async {
      await tester.pumpWidget(felt(const [20], pile: [7, 8]));
      expect(find.byKey(GameTableArea.glideKey(20)), findsNothing);
    });
  });

  group('under reduced motion', () {
    testWidgets('a selected card is up at once', (tester) async {
      const hand = [0, 13, 26];
      await tester.pumpWidget(fan(hand, still: true));
      final resting = tester.getRect(find.byKey(CardFan.itemKey(1)));
      await tester.pumpWidget(fan(hand, selected: {13}, still: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(
        resting.top - tester.getRect(find.byKey(CardFan.itemKey(1))).top,
        CardSizes.selectedLift,
      );
    });

    testWidgets('a card played lands at once', (tester) async {
      await tester.pumpWidget(felt(const [], still: true));
      await tester.pumpWidget(felt(const [20], still: true));
      expect(find.byKey(GameTableArea.glideKey(20)), findsNothing);
      expect(
        find.descendant(
          of: find.byType(GameTableArea),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('the drawn card is badged, still, and unbadged after 2 s', (
      tester,
    ) async {
      await tester.pumpWidget(fan(const [0, 13], still: true));
      await tester.pumpWidget(fan(const [0, 13, 7], still: true));
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(badge(7), findsOneWidget);
      expect(
        find.ancestor(
          of: badge(7),
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
        findsNothing,
      );
      await tester.pump(Motion.freshCard);
      expect(badge(7), findsNothing);
    });
  });

  group('on the board', () {
    Future<FakeSseTransport> pumpGame(
      WidgetTester tester,
      FakeGameBackend backend,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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

    JsonMap state({
      required int currentTurn,
      required String currentAction,
      required List<int> hand,
      List<int> cardsPlayed = const [],
      List<int> pile = const [],
      JsonMap? lastAction,
    }) => gameSnapshotJson(
      gameState: gameStateJson(
        currentTurn: currentTurn,
        currentAction: currentAction,
        playerHand: hand,
        cardsPlayed: cardsPlayed,
        lastCardsPlayed: pile,
        lastAction: lastAction,
      ),
    );

    /// Plays 2♠ (id 1) from the play step, then draws 8♠ (id 7) from the
    /// deck; [check] runs after each move has landed.
    Future<void> playThenDraw(
      WidgetTester tester, {
      required Future<void> Function(String move) check,
    }) async {
      final backend = FakeGameBackend(
        state: state(
          currentTurn: 0,
          currentAction: 'play',
          hand: const [0, 1, 30, 44],
          pile: const [20],
        ),
      );
      await pumpGame(tester, backend);

      await tester.tap(find.byKey(CardFan.itemKey(1)));
      await tester.pumpAndSettle();
      backend.state = state(
        currentTurn: 0,
        currentAction: 'draw',
        hand: const [0, 30, 44],
        cardsPlayed: const [1],
        pile: const [20],
        lastAction: {
          'type': 'play',
          'playerIndex': 0,
          'cardIds': [1],
        },
      );
      await tester.tap(find.byKey(const Key('play-cards')));
      await check('play');

      backend.state = state(
        currentTurn: 1,
        currentAction: 'play',
        hand: const [0, 30, 44, 7],
        pile: const [1],
        lastAction: {'type': 'draw', 'playerIndex': 0, 'source': 'deck'},
      );
      await tester.tap(find.byKey(const Key('draw-card')));
      await check('draw');
    }

    testWidgets('the play glides, the drawn card says "Nouveau" for 2 s', (
      tester,
    ) async {
      await playThenDraw(
        tester,
        check: (move) async {
          // The request and the refetch that follows it.
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          if (move == 'play') {
            expect(find.byKey(GameTableArea.glideKey(1)), findsOneWidget);
            await tester.pumpAndSettle();
            return;
          }
          await tester.pump(const Duration(milliseconds: 300));
          expect(badge(7), findsOneWidget);
          expect(find.text('Nouveau'), findsOneWidget);
          await tester.pump(Motion.freshCard);
          await tester.pumpAndSettle();
          expect(badge(7), findsNothing);
        },
      );
    });

    testWidgets('under reduced motion nothing on the board animates', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await playThenDraw(
        tester,
        check: (move) async {
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          expect(find.byKey(GameTableArea.glideKey(1)), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const Key('gameTable')),
              matching: find.byType(SlideTransition),
            ),
            findsNothing,
          );
          if (move == 'draw') {
            expect(badge(7), findsOneWidget);
            expect(
              find.ancestor(
                of: badge(7),
                matching: find.byType(TweenAnimationBuilder<double>),
              ),
              findsNothing,
            );
          }
          // Settled without waiting: no frame left to pump.
          expect(await tester.pumpAndSettle(), 1);
          if (move == 'draw') {
            await tester.pump(Motion.freshCard);
            expect(badge(7), findsNothing);
          }
        },
      );
    });
  });
}
