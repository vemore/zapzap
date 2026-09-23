import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/game_round_end.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

/// The end of a round read at a glance (F1–F5 of the Flutter UX study):
/// a table rather than tall cards, the result in one sentence, the player's
/// own row and the danger zone, the way on pinned with who picks next, and
/// totals that climb.
void main() {
  const phone = Size(360, 740);

  /// The four seats of the study's mockup: Vincent (the caller, `u1`) and
  /// three bots.
  const fourPlayers = <JsonMap>[
    {'playerIndex': 0, 'userId': 'u1', 'username': 'Vincent'},
    {'playerIndex': 1, 'userId': 'b1', 'username': 'EasyBot1'},
    {'playerIndex': 2, 'userId': 'b2', 'username': 'HardBot1'},
    {'playerIndex': 3, 'userId': 'b3', 'username': 'MediumBot1'},
  ];

  /// The app signed in as Vincent on `/game/p1`, at [size] and [textScale].
  Future<void> pumpGame(
    WidgetTester tester,
    FakeGameBackend backend, {
    Size size = phone,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.gamePath('p1'),
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// HardBot1 (seat 2) called on 2 points and held: 0 for it, their hand
  /// for everybody else. Round 1, started by Vincent.
  FakeGameBackend zapZapHeld({
    List<JsonMap> players = fourPlayers,
    Map<String, List<int>>? allHands,
    Map<String, int>? roundScores,
    Map<String, int>? scores,
    int startingPlayer = 0,
    List<int> eliminatedPlayers = const [],
    bool gameFinished = false,
  }) => FakeGameBackend(
    state: gameSnapshotJson(
      players: players,
      roundStatus: 'finished',
      gameState: gameStateJson(
        currentTurn: 2,
        currentAction: 'finished',
        startingPlayer: startingPlayer,
        eliminatedPlayers: eliminatedPlayers,
        zapZapCaller: 2,
        lowestHandPlayerIndex: 2,
        gameFinished: gameFinished,
        winner: gameFinished
            ? {'playerIndex': 2, 'username': 'HardBot1', 'score': 0}
            : null,
        allHands:
            allHands ??
            {
              '0': [12, 24, 36, 48], // K♠ Q♥ J♣ 10♦: 46
              '1': [25, 21, 4, 16], // K♥ 9♥ 5♠ 4♥: 31
              '2': [0, 13], // A♠ A♥: 2
              '3': [27, 41, 3], // 2♣ 3♦ 4♠: 9
            },
        handPoints: {'0': 46, '1': 31, '2': 2, '3': 9},
        roundScores: roundScores ?? {'0': 46, '1': 31, '2': 0, '3': 9},
        scores: scores ?? {'0': 46, '1': 31, '2': 0, '3': 9},
      ),
    ),
  );

  double topOf(WidgetTester tester, int playerIndex) =>
      tester.getTopLeft(find.byKey(GameRoundEnd.playerKey(playerIndex))).dy;

  String totalOf(WidgetTester tester, int playerIndex) =>
      tester.widget<Text>(find.byKey(GameRoundEnd.totalKey(playerIndex))).data!;

  Finder inRow(int playerIndex, Finder finder) => find.descendant(
    of: find.byKey(GameRoundEnd.playerKey(playerIndex)),
    matching: finder,
  );

  /// Nothing scrolled, and the row laid out last ends above the pinned
  /// footer: every player is on screen at once.
  void expectRowsAboveFooter(WidgetTester tester, {required int lastRow}) {
    final scroll = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('roundOver')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    expect(scroll.pixels, 0);
    expect(
      tester.getBottomLeft(find.byKey(GameRoundEnd.playerKey(lastRow))).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const Key('roundEndFooter'))).dy,
      ),
    );
  }

  for (final scale in [1.0, 1.5]) {
    group('at a text scale of $scale on a 360×740 phone', () {
      testWidgets('F1: one row per player, lowest round first, no scrolling', (
        tester,
      ) async {
        await pumpGame(tester, zapZapHeld(), textScale: scale);

        expect(find.byKey(const Key('roundEndTable')), findsOneWidget);
        // Sorted by the round's points: HardBot1 0, MediumBot1 9,
        // EasyBot1 31, Vincent 46.
        expect(topOf(tester, 2), lessThan(topOf(tester, 3)));
        expect(topOf(tester, 3), lessThan(topOf(tester, 1)));
        expect(topOf(tester, 1), lessThan(topOf(tester, 0)));
        // A row is a line, not a tall card.
        final rowHeight = tester
            .getSize(find.byKey(GameRoundEnd.playerKey(3)))
            .height;
        expect(rowHeight, lessThan(scale == 1 ? 64 : 110));

        // Rank, name, the hand in miniature, this round and the total.
        expect(inRow(3, find.text('2')), findsOneWidget);
        expect(inRow(3, find.text('MediumBot1')), findsOneWidget);
        expect(inRow(3, find.text('+9')), findsOneWidget);
        expect(totalOf(tester, 3), '9');
        expect(
          inRow(0, find.byType(Positioned)),
          findsNWidgets(4),
          reason: 'the four cards of the revealed hand',
        );

        // The four players and the way on fit without scrolling.
        if (scale == 1) expectRowsAboveFooter(tester, lastRow: 0);
        expect(tester.takeException(), isNull);
      });

      testWidgets('F1: eight players fit the table', (tester) async {
        final players = [
          for (var i = 0; i < 8; i++)
            {
              'playerIndex': i,
              'userId': i == 0 ? 'u1' : 'b$i',
              'username': i == 0 ? 'Vincent' : 'Bot$i',
            },
        ];
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              players: players,
              roundStatus: 'finished',
              gameState: gameStateJson(
                currentTurn: 0,
                currentAction: 'finished',
                lowestHandPlayerIndex: 0,
                allHands: {
                  for (var i = 0; i < 8; i++)
                    '$i': [i, i + 13, i + 26, i + 39, 51 - i],
                },
                roundScores: {for (var i = 0; i < 8; i++) '$i': i * 7},
                scores: {for (var i = 0; i < 8; i++) '$i': i * 12},
              ),
            ),
          ),
          textScale: scale,
        );

        for (var i = 0; i < 8; i++) {
          expect(find.byKey(GameRoundEnd.playerKey(i)), findsOneWidget);
        }
        // Eight rows on screen at once, above the pinned button.
        if (scale == 1) expectRowsAboveFooter(tester, lastRow: 7);
        await tester.scrollUntilVisible(
          find.byKey(GameRoundEnd.playerKey(7)),
          200,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('F2: a ZapZap that held, in one sentence', (tester) async {
        await pumpGame(tester, zapZapHeld(), textScale: scale);

        expect(find.text('HardBot1 a réussi son ZapZap !'), findsOneWidget);
        expect(
          find.text(
            'Sa main valait 2 points, la plus basse de la table : '
            'HardBot1 marque 0.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('F2: a counteracted ZapZap, in one sentence', (tester) async {
        // Vincent called on A♠ + Joker (1 point, the Joker 0) and EasyBot1
        // held A♥ (1): counteracted on 1 ≤ 1. The Joker then counts 25, so
        // the caller scores 26 + (4 − 1) × 5 = 41 (`GAME_RULES.md`).
        await pumpGame(
          tester,
          FakeGameBackend(
            state: gameSnapshotJson(
              players: fourPlayers,
              roundStatus: 'finished',
              gameState: gameStateJson(
                currentTurn: 0,
                currentAction: 'finished',
                zapZapCaller: 0,
                lowestHandPlayerIndex: 1,
                wasCounterActed: true,
                counterActedByPlayerIndex: 1,
                allHands: {
                  '0': [0, 52],
                  '1': [13],
                  '2': [4, 5],
                  '3': [9],
                },
                handPoints: {'0': 26, '1': 1, '2': 11, '3': 10},
                roundScores: {'0': 41, '1': 0, '2': 11, '3': 10},
                scores: {'0': 41, '1': 0, '2': 11, '3': 10},
              ),
            ),
          ),
          textScale: scale,
        );

        expect(
          find.text('Vincent a appelé ZapZap mais a été contré !'),
          findsOneWidget,
        );
        expect(
          find.text('Contré par EasyBot1 (1 ≤ 1) : 26 + 15 de pénalité.'),
          findsOneWidget,
        );
        expect(
          find.text('Pénalité : 26 + (4 − 1) × 5 = 41 points'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('F3: my row stands out, and the bar warns of 100', (
        tester,
      ) async {
        await pumpGame(
          tester,
          zapZapHeld(
            roundScores: {'0': 46, '1': 31, '2': 0, '3': 9},
            scores: {'0': 76, '1': 112, '2': 0, '3': 89},
          ),
          textScale: scale,
        );

        // Only my row carries "Vous" and the amber edge.
        expect(inRow(0, find.byKey(const Key('roundEndMe'))), findsOneWidget);
        expect(find.byKey(const Key('roundEndMe')), findsOneWidget);
        final mine =
            tester
                    .widget<Container>(find.byKey(GameRoundEnd.playerKey(0)))
                    .decoration!
                as BoxDecoration;
        expect((mine.border! as Border).left.color, AppColors.amber400);
        final other =
            tester
                    .widget<Container>(find.byKey(GameRoundEnd.playerKey(3)))
                    .decoration!
                as BoxDecoration;
        expect((other.border! as Border).left, BorderSide.none);

        RoundEndScoreBar bar(int index) =>
            tester.widget(find.byKey(GameRoundEnd.barKey(index)));
        // 76 is amber, 89 is past 80 and red, 112 is full, red and out.
        expect(bar(0).colour, AppColors.amber400);
        expect(bar(0).fraction, closeTo(0.76, 0.001));
        expect(bar(3).colour, AppColors.error);
        expect(bar(1).colour, AppColors.error);
        expect(bar(1).fraction, 1);
        expect(inRow(1, find.text('Éliminé')), findsOneWidget);
        expect(find.text('Éliminé'), findsOneWidget);
        expect(
          find.text(
            'Barre : total vers 100. Au-delà de 100, le joueur est éliminé.',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('F4: Next round stays pinned and names who picks next', (
        tester,
      ) async {
        final backend = zapZapHeld();
        await pumpGame(tester, backend, textScale: scale);

        // Not inside the scrolling table: it stays at the bottom.
        expect(
          find.descendant(
            of: find.byType(Scrollable),
            matching: find.byKey(const Key('next-round')),
          ),
          findsNothing,
        );
        final button = tester.getRect(find.byKey(const Key('next-round')));
        expect(button.bottom, lessThanOrEqualTo(phone.height));
        expect(button.bottom, greaterThan(phone.height - 80));
        // Vincent started round 1: EasyBot1 picks the hand size of round 2.
        expect(
          find.text('Manche 2 : EasyBot1 choisit la taille de la main'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('next-round')));
        await tester.pumpAndSettle();
        expect(backend.paths, contains('/api/game/p1/nextRound'));
        expect(tester.takeException(), isNull);
      });
    });
  }

  group('F4: who picks the next hand size', () {
    testWidgets('an eliminated seat is skipped', (tester) async {
      await pumpGame(
        tester,
        zapZapHeld(
          startingPlayer: 0,
          scores: {'0': 46, '1': 131, '2': 0, '3': 9},
        ),
      );
      expect(
        find.text('Manche 2 : HardBot1 choisit la taille de la main'),
        findsOneWidget,
      );
    });

    testWidgets('the rotation wraps round to me', (tester) async {
      await pumpGame(tester, zapZapHeld(startingPlayer: 3));
      expect(
        find.text('Manche 2 : à vous de choisir la taille de la main'),
        findsOneWidget,
      );
    });

    testWidgets('a finished game names nobody', (tester) async {
      await pumpGame(
        tester,
        zapZapHeld(
          gameFinished: true,
          scores: {'0': 146, '1': 131, '2': 0, '3': 109},
          eliminatedPlayers: [0, 1, 3],
        ),
      );
      expect(find.byKey(const Key('nextChooser')), findsNothing);
      expect(find.byKey(const Key('back-to-parties')), findsOneWidget);
    });
  });

  group('F5: totals climb', () {
    /// The widget alone, so the test drives the clock from the first frame.
    Future<void> pumpRoundEnd(
      WidgetTester tester, {
      bool disableAnimations = false,
    }) async {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            body: GameRoundEnd(
              roundNumber: 3,
              players: const [
                RoundEndPlayer(
                  playerIndex: 0,
                  name: 'Vincent',
                  hand: [0],
                  roundScore: 0,
                  totalScore: 20,
                  isMe: true,
                ),
                RoundEndPlayer(
                  playerIndex: 1,
                  name: 'EasyBot1',
                  hand: [10, 11],
                  roundScore: 40,
                  totalScore: 90,
                ),
              ],
              onNextRound: () {},
              onBackToParties: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('from the old total to the new one in 400 ms', (tester) async {
      await pumpRoundEnd(tester);

      String total() => totalOf(tester, 1);
      RoundEndScoreBar bar() =>
          tester.widget(find.byKey(GameRoundEnd.barKey(1)));

      expect(total(), '50', reason: 'it starts from the total before');
      expect(bar().colour, AppColors.amber400);
      await tester.pump(const Duration(milliseconds: 200));
      final halfway = int.parse(total());
      expect(halfway, greaterThan(50));
      expect(halfway, lessThan(90));
      await tester.pump(const Duration(milliseconds: 250));
      expect(total(), '90');
      expect(bar().colour, AppColors.error);
      // A round that cost nothing does not move.
      expect(totalOf(tester, 0), '20');
    });

    testWidgets('straight to the new total when animations are off', (
      tester,
    ) async {
      await pumpRoundEnd(tester, disableAnimations: true);

      expect(totalOf(tester, 1), '90');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
