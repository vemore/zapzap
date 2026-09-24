// The player table folds on the player to move: at 5 to 8 players, a line
// each took the phone's felt height (2026-09-24). A chevron unfolds every
// line and folds them back; the folded line follows the turn; on the phone
// board the height the other lines free goes to the felt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/phone_board_layout.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

void main() {
  List<GameSeat> seats({required int turn}) => [
    for (var i = 0; i < 5; i++)
      GameSeat(
        playerIndex: i,
        name: 'Joueur $i',
        score: i * 10,
        cardCount: 5,
        isMe: i == 0,
        isCurrentTurn: i == turn,
      ),
  ];

  /// The table as the phone board holds it: folded until the chevron is
  /// tapped, the choice kept by the host.
  Future<void> pumpTable(
    WidgetTester tester, {
    required ValueNotifier<int> turn,
    Locale locale = const Locale('fr'),
  }) async {
    var expanded = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: turn,
            builder: (context, current, _) => StatefulBuilder(
              builder: (context, setState) => GamePlayerTable(
                seats: seats(turn: current),
                expanded: expanded,
                onToggle: () => setState(() => expanded = !expanded),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<int> shownSeats(WidgetTester tester) => [
    for (var i = 0; i < 5; i++)
      if (tester.any(find.byKey(GamePlayerTable.seatKey(i)))) i,
  ];

  testWidgets('folded on the player to move; the chevron unfolds and folds', (
    tester,
  ) async {
    await pumpTable(tester, turn: ValueNotifier(2));

    expect(shownSeats(tester), [2]);
    expect(find.text('Joueur 2'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.byKey(GamePlayerTable.cardCountKey(2)), findsOneWidget);

    await tester.tap(find.byKey(GamePlayerTable.toggleKey));
    await tester.pumpAndSettle();
    expect(shownSeats(tester), [0, 1, 2, 3, 4]);

    await tester.tap(find.byKey(GamePlayerTable.toggleKey));
    await tester.pumpAndSettle();
    expect(shownSeats(tester), [2]);
  });

  testWidgets('the folded line follows the turn', (tester) async {
    final turn = ValueNotifier(2);
    await pumpTable(tester, turn: turn);
    expect(shownSeats(tester), [2]);

    turn.value = 3;
    await tester.pumpAndSettle();
    expect(shownSeats(tester), [3]);
    expect(find.text('Joueur 3'), findsOneWidget);
  });

  testWidgets('nobody to move: the first in turn order', (tester) async {
    await pumpTable(tester, turn: ValueNotifier(-1));
    expect(shownSeats(tester), [0]);
  });

  testWidgets('without onToggle, every line and no chevron', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GamePlayerTable(seats: seats(turn: 1))),
      ),
    );
    expect(shownSeats(tester), [0, 1, 2, 3, 4]);
    expect(find.byKey(GamePlayerTable.toggleKey), findsNothing);
  });

  for (final (locale, unfold, fold) in [
    (
      const Locale('fr'),
      'Voir tous les joueurs',
      'Ne montrer que le joueur qui joue',
    ),
    (const Locale('en'), 'Show all players', 'Show only the player to move'),
  ]) {
    testWidgets('the chevron is labelled in ${locale.languageCode}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpTable(tester, turn: ValueNotifier(0), locale: locale);

      expect(find.bySemanticsLabel(unfold), findsOneWidget);
      await tester.tap(find.byKey(GamePlayerTable.toggleKey));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(fold), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('on the phone board, the folded table is one line tall and the '
      'felt gets the rest', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.gamePath('p1'),
        apiClient: FakeGameBackend(
          state: gameSnapshotJson(
            gameState: gameStateJson(currentTurn: 1, currentAction: 'play'),
          ),
        ).client(),
        tokenStorage: storedSession(validToken),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();

    final row = GamePlayerTable.rowHeight(
      tester.element(find.byType(GamePlayerTable)),
    );
    Rect table() => tester.getRect(find.byType(GamePlayerTable));
    Rect felt() => tester.getRect(find.byType(GameTableArea));

    // One line (and the card's padding), the felt right under it.
    expect(shownSeats(tester), [1]);
    expect(table().height, row + 8);
    expect(felt().top, table().bottom + PhoneBoardLayout.gap);
    final foldedFelt = felt().height;

    await tester.tap(find.byKey(GamePlayerTable.toggleKey));
    await tester.pumpAndSettle();

    // Three lines: the felt gives the two others back.
    expect(shownSeats(tester), [0, 1, 2]);
    expect(table().height, 3 * row + 8);
    expect(felt().top, table().bottom + PhoneBoardLayout.gap);
    expect(felt().height, closeTo(foldedFelt - 2 * row, 0.01));
    expect(tester.takeException(), isNull);
  });
}
