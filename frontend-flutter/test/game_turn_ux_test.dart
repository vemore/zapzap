// The turn reads itself (J1–J6, T1, T2 of the UX study, 2026-09-23): the
// step indicator, the button that names the move, the hand value in plain
// words, ZapZap with its risk, the discard pile and the deck in the draw
// step, the hand-size choice explained, and the compact opponents. Each
// group names the item of the study it proves.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/card_back.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_action_buttons.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_hand_size_selector.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/game_zapzap_sheet.dart';
import 'package:zapzap/widgets/playing_card.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

/// Four seats: the caller (Vincent, seat 0) and three bots — the table of
/// the study's mockups, whose counteract penalty is 3 × 5.
const List<JsonMap> fourPlayers = [
  ...gamePlayersJson,
  {'playerIndex': 3, 'userId': 'b3', 'username': 'HardBot1'},
];

void main() {
  const phone = Size(360, 740);

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

  FakeGameBackend table({
    int currentTurn = 0,
    String currentAction = 'play',
    List<int> playerHand = const [0, 1, 2, 30, 44],
    List<int> lastCardsPlayed = const [],
    List<JsonMap> players = gamePlayersJson,
    Map<String, int> scores = const {'0': 12, '1': 30, '2': 5},
    Map<String, int> otherPlayersHandSizes = const {'1': 4, '2': 6},
    List<int> eliminatedPlayers = const [],
    int startingPlayer = 0,
    bool isGoldenScore = false,
  }) => FakeGameBackend(
    state: gameSnapshotJson(
      players: players,
      gameState: gameStateJson(
        currentTurn: currentTurn,
        currentAction: currentAction,
        playerHand: playerHand,
        lastCardsPlayed: lastCardsPlayed,
        scores: scores,
        otherPlayersHandSizes: otherPlayersHandSizes,
        eliminatedPlayers: eliminatedPlayers,
        startingPlayer: startingPlayer,
        isGoldenScore: isGoldenScore,
      ),
    ),
  );

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

  void selectCard(WidgetTester tester, int cardId) {
    tester.widget<CardFan>(find.byType(CardFan)).onCardTap!(cardId);
  }

  String primaryLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('primaryMoveLabel'))).data!;

  String zapZapLabel(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('zapzapLabel'))).data!;

  /// The fill of the step chip under [key].
  Color? stepColor(WidgetTester tester, Key key) {
    final box = tester.widget<Container>(
      find.descendant(of: find.byKey(key), matching: find.byType(Container)),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  /// The look of the card under [key] — a face ([PlayingCard.look]) or the
  /// deck's top card, by its edge. Either way drawn in its own colours:
  /// opaque, never through a `ColorFiltered`.
  CardLook look(WidgetTester tester, Key key) {
    final opacities = tester.widgetList<Opacity>(
      find.descendant(of: find.byKey(key), matching: find.byType(Opacity)),
    );
    expect(opacities.where((o) => o.opacity < 1), isEmpty);
    expect(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
    final face = find.descendant(
      of: find.byKey(key),
      matching: find.byType(PlayingCard),
      matchRoot: true,
    );
    if (face.evaluate().isNotEmpty) {
      return tester.widget<PlayingCard>(face.first).look;
    }
    final top = tester.widget<Container>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byKey(const Key('deckTop')),
      ),
    );
    final edge =
        (top.foregroundDecoration as BoxDecoration?)?.border as Border?;
    return switch (edge?.top.color) {
      null => CardLook.plain,
      AppColors.amber200 => CardLook.playable,
      _ => CardLook.selected,
    };
  }

  Border feltBorder(WidgetTester tester) =>
      (tester.widget<Container>(find.byKey(const Key('gameTable'))).decoration!
                  as BoxDecoration)
              .border!
          as Border;

  group('J1 — the step indicator: ① Jouer → ② Piocher', () {
    testWidgets('the play step is amber, the draw step grey to come', (
      tester,
    ) async {
      await pumpGame(tester, table());

      final play = GameActionButtons.stepKey('play');
      final draw = GameActionButtons.stepKey('draw');
      expect(find.text('① Jouer'), findsOneWidget);
      expect(find.text('② Piocher'), findsOneWidget);
      expect(
        tester.widget<TurnStepChip>(find.byKey(play)).state,
        TurnStepState.current,
      );
      expect(
        tester.widget<TurnStepChip>(find.byKey(draw)).state,
        TurnStepState.pending,
      );
      expect(stepColor(tester, play), TurnStepChip.currentColor);
      expect(stepColor(tester, draw), TurnStepChip.otherColor);
      expect(find.text('Ton tour'), findsOneWidget);
      expect(find.byKey(const Key('turnBanner')), findsNothing);
    });

    testWidgets('the draw step is amber, the play step grey and checked', (
      tester,
    ) async {
      await pumpGame(
        tester,
        table(currentAction: 'draw', lastCardsPlayed: [19]),
      );

      final play = GameActionButtons.stepKey('play');
      final draw = GameActionButtons.stepKey('draw');
      expect(find.text('✓ Jouer'), findsOneWidget);
      expect(find.text('① Jouer'), findsNothing);
      expect(
        tester.widget<TurnStepChip>(find.byKey(play)).state,
        TurnStepState.done,
      );
      expect(
        tester.widget<TurnStepChip>(find.byKey(draw)).state,
        TurnStepState.current,
      );
      expect(stepColor(tester, play), TurnStepChip.otherColor);
      expect(stepColor(tester, draw), TurnStepChip.currentColor);
    });

    testWidgets('another player\'s turn shows whom the board waits for', (
      tester,
    ) async {
      await pumpGame(tester, table(currentTurn: 1));

      expect(find.byKey(const Key('turnSteps')), findsNothing);
      expect(find.text('En attente de EasyBot1'), findsOneWidget);
    });
  });

  group('J2 — one full-width button that names the move', () {
    testWidgets('a pair, a run, a single card, then plain Jouer when refused', (
      tester,
    ) async {
      // 7♠ 7♥, 5♥ 6♥ (7♥ with them makes a run), K♣.
      await pumpGame(tester, table(playerHand: [6, 19, 17, 18, 38]));

      // One button for the step at hand, as wide as the bar.
      expect(find.byKey(const Key('play-cards')), findsOneWidget);
      expect(find.byKey(const Key('draw-card')), findsNothing);
      final bar = tester.getSize(find.byType(GameActionButtons)).width;
      expect(
        tester.getSize(find.byKey(const Key('play-cards'))).width,
        greaterThanOrEqualTo(bar - 20),
      );
      expect(primaryLabel(tester), 'Jouer');
      expect(enabled(tester, const Key('play-cards')), isFalse);

      selectCard(tester, 6);
      selectCard(tester, 19);
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Jouer la paire de 7');
      expect(enabled(tester, const Key('play-cards')), isTrue);

      selectCard(tester, 6);
      selectCard(tester, 17);
      selectCard(tester, 18);
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Jouer la suite (3 cartes)');

      selectCard(tester, 17);
      selectCard(tester, 18);
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Jouer 7♥');

      // 7♥ K♣: refused. The button says no move, and the reason stays,
      // under it.
      selectCard(tester, 38);
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Jouer');
      expect(enabled(tester, const Key('play-cards')), isFalse);
      final reason = find.byKey(const Key('invalidPlayReason'));
      expect(reason, findsOneWidget);
      expect(
        tester.getTopLeft(reason).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const Key('play-cards'))).dy,
        ),
      );
    });

    testWidgets('a group of three names its rank', (tester) async {
      await pumpGame(tester, table(playerHand: [6, 19, 32]));
      selectCard(tester, 6);
      selectCard(tester, 19);
      selectCard(tester, 32);
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Jouer le groupe de 7 (3 cartes)');
    });

    testWidgets('the draw step: Piocher, then Prendre 7♥ once it is picked', (
      tester,
    ) async {
      final backend = table(currentAction: 'draw', lastCardsPlayed: [17, 19]);
      await pumpGame(tester, backend);

      expect(find.byKey(const Key('play-cards')), findsNothing);
      expect(primaryLabel(tester), 'Piocher');

      await tester.tap(find.byKey(GameTableArea.discardKey(19)));
      await tester.pumpAndSettle();
      expect(primaryLabel(tester), 'Prendre 7♥');

      await tester.tap(find.byKey(const Key('draw-card')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {
        'source': 'played',
        'cardId': 19,
      });
    });
  });

  group('J3 — the hand value in plain words', () {
    testWidgets('Ta main · 29 pts, a gauge towards ZapZap à 5, no penalty', (
      tester,
    ) async {
      // 10♠ + J♥ + 8♣ = 10 + 11 + 8.
      await pumpGame(tester, table(playerHand: [9, 23, 33]));

      expect(find.text('Ta main · 29 pts'), findsOneWidget);
      expect(find.text('ZapZap à 5'), findsOneWidget);
      final gauge = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('zapzapGauge')),
      );
      expect(gauge.value, closeTo(5 / 29, 1e-9));
      // No joker: the one value is the one that counts.
      expect(find.byKey(const Key('handPenaltyValue')), findsNothing);
      expect(find.textContaining('Pénalité'), findsNothing);
    });

    testWidgets('a joker shows what the hand scores at round end', (
      tester,
    ) async {
      // A♠ + 2♠ + a joker: 3 for ZapZap, 28 if counteracted.
      await pumpGame(tester, table(playerHand: [0, 1, 52]));

      expect(find.text('Ta main · 3 pts'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const Key('zapzapGauge')),
            )
            .value,
        1,
      );
      // A joker counts 25 at round end for anyone without the lowest hand,
      // counteracted or not: the label does not tie it to a counteract.
      expect(find.text('En fin de manche : 28 pts (joker 25)'), findsOneWidget);
      expect(find.textContaining('contré'), findsNothing);
    });
  });

  group('J4 — ZapZap, confirmed knowing the risk', () {
    testWidgets('always visible, disabled with its reason', (tester) async {
      await pumpGame(tester, table(playerHand: [9, 23, 33]));

      expect(find.byKey(const Key('call-zapzap')), findsOneWidget);
      expect(enabled(tester, const Key('call-zapzap')), isFalse);
      expect(zapZapLabel(tester), 'ZapZap · main 29, il faut 5 ou moins');
    });

    testWidgets('a low hand waits for the play step of my turn', (
      tester,
    ) async {
      await pumpGame(tester, table(currentTurn: 1, playerHand: [0, 1]));

      expect(enabled(tester, const Key('call-zapzap')), isFalse);
      expect(zapZapLabel(tester), 'ZapZap · au début de ton tour');
    });

    testWidgets('a tap asks first: cancel calls nothing, confirm calls', (
      tester,
    ) async {
      // A♠ 2♠: 3 points; four players, so three opponents × 5.
      final backend = table(
        players: fourPlayers,
        playerHand: [0, 1],
        scores: const {'0': 12, '1': 30, '2': 5, '3': 40},
        otherPlayersHandSizes: const {'1': 4, '2': 6, '3': 5},
      );
      await pumpGame(tester, backend);

      expect(enabled(tester, const Key('call-zapzap')), isTrue);
      expect(zapZapLabel(tester), 'ZapZap !');

      await tester.tap(find.byKey(const Key('call-zapzap')));
      await tester.pumpAndSettle();
      expect(find.byType(ZapZapConfirmSheet), findsOneWidget);
      expect(find.text('Appeler ZapZap avec 3 points ?'), findsOneWidget);
      expect(
        find.text("Tu gagnes la manche si aucun adversaire n'a 3 ou moins."),
        findsOneWidget,
      );
      // hand + (active players − 1) × 5 = 3 + 15.
      expect(
        find.text(
          'Sinon tu es contré : ta main, 3, + 15 de pénalité '
          '(3 adversaires × 5) = 18 points.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('zapzapJokerNote')), findsNothing);

      await tester.tap(find.byKey(const Key('zapzap-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(ZapZapConfirmSheet), findsNothing);
      expect(backend.paths, isNot(contains('/api/game/p1/zapzap')));

      await tester.tap(find.byKey(const Key('call-zapzap')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zapzap-confirm')));
      await tester.pumpAndSettle();
      expect(backend.paths, contains('/api/game/p1/zapzap'));
    });

    testWidgets('an eliminated player is no opponent; a joker counts 25', (
      tester,
    ) async {
      // Four seats, one out: two opponents. A♠ + joker: 1, scored 26.
      await pumpGame(
        tester,
        table(
          players: fourPlayers,
          playerHand: [0, 53],
          eliminatedPlayers: [3],
          scores: const {'0': 12, '1': 30, '2': 5, '3': 104},
          otherPlayersHandSizes: const {'1': 4, '2': 6, '3': 0},
        ),
      );

      await tester.tap(find.byKey(const Key('call-zapzap')));
      await tester.pumpAndSettle();
      expect(find.text('Appeler ZapZap avec 1 point ?'), findsOneWidget);
      expect(
        find.text(
          'Sinon tu es contré : ta main, 26, + 10 de pénalité '
          '(2 adversaires × 5) = 36 points.',
        ),
        findsOneWidget,
      );
      expect(find.text('Le joker y compte alors 25.'), findsOneWidget);
      expect(find.byKey(const Key('zapzapGoldenNote')), findsNothing);
    });

    testWidgets('in Golden Score, being counteracted loses the game', (
      tester,
    ) async {
      await pumpGame(
        tester,
        table(playerHand: [0], eliminatedPlayers: [2], isGoldenScore: true),
      );

      await tester.tap(find.byKey(const Key('call-zapzap')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Sinon tu es contré : ta main, 1, + 5 de pénalité '
          '(1 adversaire × 5) = 6 points.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Score en or : contré, tu perds la partie.'),
        findsOneWidget,
      );
    });
  });

  group('J5 — the discard pile: what can be taken, and when', () {
    testWidgets('during Jouer the pile is "À prendre ensuite", plain', (
      tester,
    ) async {
      await pumpGame(tester, table(lastCardsPlayed: [17, 18, 19]));

      expect(find.text('À prendre ensuite'), findsOneWidget);
      expect(look(tester, GameTableArea.discardKey(19)), CardLook.plain);
      expect(find.byKey(const Key('drawInstruction')), findsNothing);
      expect(feltBorder(tester).top.color, isNot(GameTableArea.drawEdgeColor));
      expect(enabled(tester, const Key('draw-deck')), isFalse);
      expect(look(tester, const Key('draw-deck')), CardLook.plain);
      // The hand is what can be played now: each card takes the edge.
      for (final card in tester.widgetList<PlayingCard>(
        find.descendant(
          of: find.byType(CardFan),
          matching: find.byType(PlayingCard),
        ),
      )) {
        expect(card.look, CardLook.playable);
      }
    });

    testWidgets('during Piocher: amber edge, the instruction, full colour, '
        'and the deck is a target', (tester) async {
      final backend = table(
        currentAction: 'draw',
        lastCardsPlayed: [17, 18, 19],
      );
      await pumpGame(tester, backend);

      final edge = feltBorder(tester).top;
      expect(edge.color, GameTableArea.drawEdgeColor);
      expect(edge.width, 2);
      expect(
        find.text('Touche une carte pour la prendre, ou la pioche'),
        findsOneWidget,
      );
      expect(look(tester, GameTableArea.discardKey(19)), CardLook.playable);
      expect(look(tester, const Key('draw-deck')), CardLook.playable);
      // The hand is only read in the draw step: plain, in its colours.
      for (final card in tester.widgetList<PlayingCard>(
        find.descendant(
          of: find.byType(CardFan),
          matching: find.byType(PlayingCard),
        ),
      )) {
        expect(card.look, CardLook.plain);
      }
      expect(find.text('À prendre ensuite'), findsOneWidget);

      // Picking a card says what it costs.
      await tester.tap(find.byKey(GameTableArea.discardKey(19)));
      await tester.pumpAndSettle();
      expect(
        find.text('Prendre 7♥ ajoute 7 points à ta main.'),
        findsOneWidget,
      );
      expect(look(tester, GameTableArea.discardKey(19)), CardLook.selected);
      expect(look(tester, GameTableArea.discardKey(18)), CardLook.playable);

      // The deck is a target of its own: it draws from the deck even with
      // a discard card picked.
      expect(enabled(tester, const Key('draw-deck')), isTrue);
      await tester.tap(find.byKey(const Key('draw-deck')));
      await tester.pumpAndSettle();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {'source': 'deck'});
    });

    testWidgets('a joker from the pile counts 0 for ZapZap, 25 at round end', (
      tester,
    ) async {
      await pumpGame(
        tester,
        table(currentAction: 'draw', lastCardsPlayed: [17, 52]),
      );

      await tester.tap(find.byKey(GameTableArea.discardKey(52)));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Prendre Joker rouge : 0 point pour ZapZap, mais 25 en fin de '
          "manche si ta main n'est pas la plus basse.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining("n'ajoute aucun point"), findsNothing);
    });

    testWidgets('a refused deck draw keeps the pile pick', (tester) async {
      final backend = table(currentAction: 'draw', lastCardsPlayed: [17, 19]);
      backend.failures['POST /api/game/p1/draw'] = (
        status: 400,
        body: {'error': 'refused', 'code': 'INVALID_ACTION'},
      );
      await pumpGame(tester, backend);

      await tester.tap(find.byKey(GameTableArea.discardKey(19)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw-deck')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {'source': 'deck'});
      // The pick is still there: the button still takes 7♥, the hint too.
      expect(primaryLabel(tester), 'Prendre 7♥');
      expect(find.byKey(const Key('takeHint')), findsOneWidget);
    });

    testWidgets('a pick the pile no longer holds gets no hint, as the button '
        'draws', (tester) async {
      final backend = table(currentAction: 'draw', lastCardsPlayed: [17, 19]);
      final transport = await pumpGame(tester, backend);

      await tester.tap(find.byKey(GameTableArea.discardKey(19)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('takeHint')), findsOneWidget);

      // Same hand, but 7♥ has left the pile: the pick is stale.
      backend.state = gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'draw',
          playerHand: const [0, 1, 2, 30, 44],
          lastCardsPlayed: const [17, 18],
        ),
      );
      transport.last.send(
        jsonEncode({'partyId': 'p1', 'action': 'draw', 'type': 'gameAction'}),
      );
      await tester.pumpAndSettle();

      expect(primaryLabel(tester), 'Piocher');
      expect(find.byKey(const Key('takeHint')), findsNothing);
    });
  });

  group('T1, T2 — the hand-size choice', () {
    FakeGameBackend handSize({bool golden = false}) => FakeGameBackend(
      state: gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'selectHandSize',
          isGoldenScore: golden,
        ),
      ),
    );

    testWidgets('T1: one line says what the choice changes', (tester) async {
      await pumpGame(tester, handSize());

      final hint = find.byKey(const Key('handSizeHint'));
      expect(
        find.descendant(of: hint, matching: find.text('5 cartes par joueur')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hint,
          matching: find.text(
            'Moins de cartes, ZapZap plus vite ; '
            'plus de cartes, plus de combinaisons.',
          ),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(GameHandSizeSelector.sizeKey(6)));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: hint, matching: find.text('6 cartes par joueur')),
        findsOneWidget,
      );
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('T2: 48 dp targets and "Distribuer N cartes" at a text '
          'scale of $scale', (tester) async {
        final backend = handSize(golden: true);
        await pumpGame(tester, backend, size: phone, textScale: scale);

        for (var size = 4; size <= 10; size++) {
          final target = tester.getSize(
            find.byKey(GameHandSizeSelector.sizeKey(size)),
          );
          expect(target.width, greaterThanOrEqualTo(48), reason: '$size');
          expect(target.height, greaterThanOrEqualTo(48), reason: '$size');
        }
        expect(find.text('Distribuer 7 cartes'), findsOneWidget);

        // At a 2.0 text scale the choice sits below the fold.
        await tester.ensureVisible(find.byKey(GameHandSizeSelector.sizeKey(4)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(GameHandSizeSelector.sizeKey(4)));
        await tester.pumpAndSettle();
        expect(find.text('Distribuer 4 cartes'), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('confirm-hand-size')));
        await tester.tap(find.byKey(const Key('confirm-hand-size')));
        await tester.pumpAndSettle();
        expect(backend.bodyOf('POST', '/api/game/p1/selectHandSize'), {
          'handSize': 4,
        });
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('J6 — compact opponents', () {
    // HardBot1 starts the round, so the turn order is 2, 3, 0, 1 — not the
    // seat order. HardBot1 (seat 3) is to move; EasyBot1 is past 80.
    FakeGameBackend fourSeats() => table(
      players: fourPlayers,
      currentTurn: 3,
      startingPlayer: 2,
      eliminatedPlayers: [2],
      scores: const {'0': 23, '1': 85, '2': 104, '3': 12},
      otherPlayersHandSizes: const {'1': 5, '2': 0, '3': 3},
    );

    final sizes = {
      '390×844': const Size(390, 844),
      'desktop': const Size(1280, 800),
    };
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key}, text scale $scale: "▯ n", the amber edge, '
            'the bar to 100, equal lines in turn order', (tester) async {
          await pumpGame(
            tester,
            fourSeats(),
            size: entry.value,
            textScale: scale,
          );
          // The phone board folds the table on the player to move.
          if (entry.value.width < 800) {
            await tester.tap(find.byKey(GamePlayerTable.toggleKey));
            await tester.pumpAndSettle();
          }

          // Turn order from the round's starting player.
          final order = [2, 3, 0, 1];
          final tops = [
            for (final seat in order)
              tester.getTopLeft(find.byKey(GamePlayerTable.seatKey(seat))).dy,
          ];
          for (var i = 1; i < tops.length; i++) {
            expect(tops[i], greaterThan(tops[i - 1]));
          }

          // Equal heights: a badge, a card back or "Éliminé" changes none.
          final heights = {
            for (final seat in order)
              tester.getSize(find.byKey(GamePlayerTable.seatKey(seat))).height,
          };
          expect(heights, hasLength(1));

          // One card back and the count, not a back per card.
          for (final (seat, count) in [(0, 5), (1, 5), (3, 3)]) {
            final cell = find.byKey(GamePlayerTable.cardCountKey(seat));
            expect(
              find.descendant(of: cell, matching: find.byType(CardBack)),
              findsOneWidget,
            );
            expect(
              find.descendant(of: cell, matching: find.text('$count')),
              findsOneWidget,
            );
          }
          expect(find.byKey(GamePlayerTable.cardCountKey(2)), findsNothing);
          expect(
            find.descendant(
              of: find.byKey(GamePlayerTable.seatKey(2)),
              matching: find.text('Éliminé'),
            ),
            findsOneWidget,
          );

          // The player to move sits on an amber edge; nobody else does.
          BorderSide edge(int seat) =>
              ((tester
                                  .widget<Container>(
                                    find.byKey(GamePlayerTable.seatKey(seat)),
                                  )
                                  .decoration!
                              as BoxDecoration)
                          .border!
                      as Border)
                  .left;
          expect(edge(3).color, GamePlayerTable.activeEdgeColor);
          for (final seat in [0, 1, 2]) {
            expect(edge(seat).color, Colors.transparent);
          }

          // The bar towards 100, red past 80.
          LinearProgressIndicator bar(int seat) =>
              tester.widget<LinearProgressIndicator>(
                find.byKey(GamePlayerTable.scoreBarKey(seat)),
              );
          expect(bar(0).value, closeTo(0.23, 1e-9));
          expect(bar(0).color, GamePlayerTable.barColor);
          expect(bar(1).value, closeTo(0.85, 1e-9));
          expect(bar(1).color, GamePlayerTable.dangerBarColor);
          expect(bar(3).color, GamePlayerTable.barColor);
          expect(GamePlayerTable.dangerBarColor, AppColors.error);

          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  // Every new piece at a phone's size, at the largest system font too.
  group('a 360×740 phone', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the play step with a named move fits at $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          table(
            players: fourPlayers,
            playerHand: [16, 17, 18, 19, 20, 52, 38],
            lastCardsPlayed: [30, 31, 32],
            scores: const {'0': 23, '1': 85, '2': 12, '3': 40},
            otherPlayersHandSizes: const {'1': 5, '2': 3, '3': 4},
          ),
          size: phone,
          textScale: scale,
        );
        for (final id in [16, 17, 18, 19, 20]) {
          selectCard(tester, id);
        }
        await tester.pumpAndSettle();

        expect(primaryLabel(tester), 'Jouer la suite (5 cartes)');
        expect(find.byKey(const Key('handPenaltyValue')), findsOneWidget);
        expect(find.byType(GameHand), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the draw step with a picked card fits at $scale', (
        tester,
      ) async {
        await pumpGame(
          tester,
          table(
            players: fourPlayers,
            currentAction: 'draw',
            playerHand: [0, 1, 2, 3, 4, 5],
            lastCardsPlayed: [30, 31, 32, 33, 34],
            otherPlayersHandSizes: const {'1': 5, '2': 3, '3': 4},
          ),
          size: phone,
          textScale: scale,
        );
        await tester.ensureVisible(find.byKey(GameTableArea.discardKey(34)));
        await tester.tap(find.byKey(GameTableArea.discardKey(34)));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('takeHint')), findsOneWidget);
        expect(primaryLabel(tester), 'Prendre 9♣');
        expect(tester.takeException(), isNull);
      });

      testWidgets('the ZapZap sheet fits at $scale', (tester) async {
        await pumpGame(
          tester,
          table(
            players: fourPlayers,
            playerHand: [0, 52],
            isGoldenScore: true,
            otherPlayersHandSizes: const {'1': 5, '2': 3, '3': 4},
          ),
          size: phone,
          textScale: scale,
        );
        await tester.tap(find.byKey(const Key('call-zapzap')));
        await tester.pumpAndSettle();

        expect(find.byType(ZapZapConfirmSheet), findsOneWidget);
        await tester.ensureVisible(find.byKey(const Key('zapzap-confirm')));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
