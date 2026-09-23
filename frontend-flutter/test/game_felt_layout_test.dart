// The felt on a phone (found smoke-testing #57 on production at 390x844,
// 2026-09-23): during the draw step the green box, its amber edge, the deck
// and the take hint were cut by the section holding the felt, while an empty
// band stayed under it. A clip raises no RenderFlex error, so only the rects
// tell. The text is laid out in Roboto, the font the app is drawn in on
// Android and in the PWA: the test font's square glyphs are about twice as
// wide and would make every line of the felt wrap.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_table_area.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

void main() {
  setUpAll(() async {
    // `flutter test` sets FLUTTER_ROOT; the SDK ships Roboto for Material.
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}'
        '/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final bytes = File('$fonts/Roboto-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  Future<void> pumpGame(
    WidgetTester tester,
    FakeGameBackend backend, {
    required Size size,
    required double textScale,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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

  /// This player's turn right after laying [played] down, the previous
  /// player's [pile] up for grabs. The production screenshot's board is one
  /// played card, one pile card and four in the hand.
  FakeGameBackend board({
    String currentAction = 'draw',
    required List<int> played,
    required List<int> pile,
  }) => FakeGameBackend(
    state: gameSnapshotJson(
      gameState: gameStateJson(
        currentTurn: 0,
        currentAction: currentAction,
        deckSize: 38,
        playerHand: const [0, 13, 26, 40],
        cardsPlayed: played,
        lastCardsPlayed: pile,
        lastAction: <String, Object?>{
          'type': 'play',
          'playerIndex': 0,
          'cardIds': played,
          'timestamp': 1790094197863,
        },
      ),
    ),
  );

  final felt = find.byKey(const Key('gameTable'));
  final feltScroll = find.byKey(const Key('gameTableScroll'));

  /// What of [finder] the screen shows: its rect cut by every scroll view
  /// that holds it.
  Rect shownRect(WidgetTester tester, Finder finder) {
    var rect = tester.getRect(finder);
    final viewports = find.ancestor(
      of: finder,
      matching: find.byType(Scrollable),
    );
    for (final element in viewports.evaluate()) {
      final box = element.renderObject! as RenderBox;
      rect = rect.intersect(box.localToGlobal(Offset.zero) & box.size);
    }
    return rect;
  }

  void expectShownInFelt(WidgetTester tester, Finder finder, String what) {
    const slack = 0.5;
    final outer = tester.getRect(felt);
    final inner = tester.getRect(finder);
    expect(
      shownRect(tester, finder),
      inner,
      reason: '$what $inner is cut by a scroll view',
    );
    expect(
      inner.top >= outer.top - slack &&
          inner.left >= outer.left - slack &&
          inner.bottom <= outer.bottom + slack &&
          inner.right <= outer.right + slack,
      isTrue,
      reason: '$what $inner is not inside the felt, $outer',
    );
  }

  double feltScrollExtent(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: feltScroll, matching: find.byType(Scrollable)),
      )
      .position
      .maxScrollExtent;

  const boards = <String, ({List<int> played, List<int> pile})>{
    'one played, one up for grabs': (played: [34], pile: [47]),
    'a run played, a triple up for grabs': (
      played: [3, 4, 5],
      pile: [19, 32, 45],
    ),
  };

  for (final size in const [Size(360, 740), Size(390, 844)]) {
    for (final scale in const [1.0, 1.5]) {
      // The smallest phone at x1.5 has no room for the whole draw step: the
      // players and the actions alone take half its height. The felt then
      // keeps its whole edge and scrolls inside it.
      final fits = !(size.width == 360 && scale == 1.5);
      for (final entry in boards.entries) {
        final pile = entry.value.pile;
        testWidgets('Piocher at ${size.width.toInt()}x${size.height.toInt()}, '
            'text x$scale, ${entry.key}: the whole felt shows'
            '${fits ? '' : ', its content scrolling inside the edge'}', (
          tester,
        ) async {
          await pumpGame(
            tester,
            board(played: entry.value.played, pile: pile),
            size: size,
            textScale: scale,
          );
          final pick = find.byKey(GameTableArea.discardKey(pile.last));
          await tester.ensureVisible(pick);
          await tester.tap(pick);
          await tester.pumpAndSettle();

          // Nothing cuts the felt: its amber edge is whole.
          expect(shownRect(tester, felt), tester.getRect(felt));
          expect(
            (tester.widget<Container>(felt).decoration! as BoxDecoration)
                .border!
                .bottom
                .color,
            GameTableArea.drawEdgeColor,
          );

          final deckLabel = find.descendant(
            of: find.byKey(const Key('draw-deck')),
            matching: find.textContaining('38'),
          );
          final hint = find.byKey(const Key('takeHint'));
          expect(hint, findsOneWidget);
          if (fits) {
            expect(feltScrollExtent(tester), 0);
          } else {
            expect(feltScrollExtent(tester), greaterThan(0));
            await tester.ensureVisible(hint);
            await tester.pumpAndSettle();
          }
          expectShownInFelt(tester, deckLabel, 'the deck label');
          expectShownInFelt(tester, hint, 'the take hint');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('Jouer at 390x844: the felt shows whole and the hand keeps '
      'its share', (tester) async {
    await pumpGame(
      tester,
      board(currentAction: 'play', played: const [], pile: const [19, 32]),
      size: const Size(390, 844),
      textScale: 1,
    );

    expect(shownRect(tester, felt), tester.getRect(felt));
    expect(feltScrollExtent(tester), 0);
    final fan = find.byType(CardFan);
    expect(shownRect(tester, fan), tester.getRect(fan));
  });

  testWidgets('the draw button is the theme primary, as Jouer is', (
    tester,
  ) async {
    await pumpGame(
      tester,
      board(played: const [34], pile: const [47]),
      size: const Size(390, 844),
      textScale: 1,
    );

    final draw = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('draw-card')),
    );
    expect(
      draw.style!.backgroundColor!.resolve(<WidgetState>{}),
      AppColors.amber500,
    );
    expect(
      draw.style!.foregroundColor!.resolve(<WidgetState>{}),
      AppColors.slate900,
    );
  });
}
