import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/widgets/game_round_end.dart';
import 'package:zapzap/widgets/round_end_effects/fx_core.dart';
import 'package:zapzap/widgets/round_end_effects/round_end_effects.dart';

/// The overlays of the round end (wip 2026-09-29, the styles the user chose
/// that day): a held ZapZap strikes, a counteracted one is stamped, an
/// elimination overheats its gauge — once, in that order, before the
/// confetti; skipped by a touch; never under reduced motion.
void main() {
  const held = Key('zapzapHeldAnimation');
  const countered = Key('zapzapCounteredAnimation');
  const elimination = Key('eliminationAnimation');

  /// HardBot1 called on 2 and held; EasyBot1 crossed 100 with it.
  const heldPlayers = [
    RoundEndPlayer(
      playerIndex: 2,
      name: 'HardBot1',
      hand: [0, 13],
      roundScore: 0,
      totalScore: 30,
      isLowestHand: true,
      isZapZapCaller: true,
    ),
    RoundEndPlayer(
      playerIndex: 0,
      name: 'Vincent',
      hand: [4, 5],
      roundScore: 11,
      totalScore: 57,
      isMe: true,
    ),
    RoundEndPlayer(
      playerIndex: 1,
      name: 'EasyBot1',
      hand: [9, 8],
      roundScore: 17,
      totalScore: 104,
      isEliminated: true,
    ),
  ];

  /// Vincent called on 1 and EasyBot1 held 1 too: counteracted, 41
  /// points, and out at 121.
  const counteredPlayers = [
    RoundEndPlayer(
      playerIndex: 1,
      name: 'EasyBot1',
      hand: [13],
      roundScore: 0,
      totalScore: 30,
      isLowestHand: true,
    ),
    RoundEndPlayer(
      playerIndex: 2,
      name: 'HardBot1',
      hand: [4, 5],
      roundScore: 11,
      totalScore: 60,
    ),
    RoundEndPlayer(
      playerIndex: 0,
      name: 'Vincent',
      hand: [0, 52],
      roundScore: 41,
      totalScore: 121,
      isEliminated: true,
      isZapZapCaller: true,
      isMe: true,
    ),
  ];

  var nextRounds = 0;

  Widget roundEnd({
    required List<RoundEndPlayer> players,
    String? caller,
    bool wasCounterActed = false,
    bool gameFinished = false,
    bool winnerIsMe = false,
    bool busy = false,
  }) => GameRoundEnd(
    roundNumber: 7,
    players: players,
    onNextRound: () => nextRounds++,
    onBackToParties: () {},
    zapZapCallerName: caller,
    wasCounterActed: wasCounterActed,
    counterActedByName: wasCounterActed ? 'EasyBot1' : null,
    callerHandValue: wasCounterActed ? 26 : null,
    callerRoundScore: wasCounterActed ? 41 : null,
    activePlayerCount: 4,
    callerZapZapValue: 1,
    counterActorZapZapValue: wasCounterActed ? 1 : null,
    gameFinished: gameFinished,
    winnerName: gameFinished ? 'EasyBot1' : null,
    winnerScore: gameFinished ? 30 : null,
    winnerIsMe: winnerIsMe,
    busy: busy,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool disableAnimations = false,
    double textScale = 1,
    String locale = 'fr',
  }) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 740),
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    // The overlays start once the table is laid out: their clock reads 0
    // after this frame.
    await tester.pump();
  }

  /// The clock of the overlays moves on by [ms].
  Future<void> at(WidgetTester tester, int ms) =>
      tester.pump(Duration(milliseconds: ms));

  String totalOf(WidgetTester tester, int playerIndex) =>
      tester.widget<Text>(find.byKey(GameRoundEnd.totalKey(playerIndex))).data!;

  /// Whether the Eliminated badge of [playerIndex]'s row shows.
  bool badgeShown(WidgetTester tester, int playerIndex) {
    final opacity = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(GameRoundEnd.playerKey(playerIndex)),
              matching: find.text('Éliminé'),
            ),
            matching: find.byType(Opacity),
          )
          .first,
    );
    return opacity.opacity == 1;
  }

  setUp(() => nextRounds = 0);

  testWidgets('a held ZapZap strikes once, then the elimination overheats', (
    tester,
  ) async {
    await pump(tester, roundEnd(players: heldPlayers, caller: 'HardBot1'));

    await at(tester, 300);
    expect(find.byKey(held), findsOneWidget);
    expect(find.byKey(elimination), findsNothing);
    expect(find.byKey(countered), findsNothing);
    // The word drops in over the table.
    expect(find.text('Z'), findsWidgets);
    // EasyBot1's total waits for the gauge; the badge is not out yet.
    expect(totalOf(tester, 1), '87');
    expect(badgeShown(tester, 1), isFalse);

    // The bolt is said at 1.7 s: the gauge takes over while the last
    // sparks die on the banner, gone by 2.4 s.
    await at(tester, 1500);
    expect(find.byKey(elimination), findsOneWidget);
    expect(totalOf(tester, 1), '87');

    // 1.7 s + 0.3 s: the gauge climbs; it passes 100 before 1.7 s + 1 s.
    await at(tester, 600);
    expect(find.byKey(held), findsNothing);
    final climbing = int.parse(totalOf(tester, 1));
    expect(climbing, greaterThan(87));
    expect(climbing, lessThan(104));
    await at(tester, 600);
    expect(totalOf(tester, 1), '104');
    // The tape is across the row.
    expect(find.textContaining('ÉLIMINÉ ×'), findsOneWidget);
    expect(badgeShown(tester, 1), isFalse);

    // 1.7 s + 2.0 s: the badge pops; everything is gone by 1.7 s + 2.4 s.
    await at(tester, 700);
    expect(badgeShown(tester, 1), isTrue);
    await at(tester, 600);
    expect(find.byKey(elimination), findsNothing);
    expect(find.textContaining('ÉLIMINÉ ×'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);

    // Once: a rebuild of the same round end plays nothing again.
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 740)),
          child: Scaffold(
            body: roundEnd(
              players: heldPlayers,
              caller: 'HardBot1',
              busy: true,
            ),
          ),
        ),
      ),
    );
    await at(tester, 300);
    expect(find.byKey(held), findsNothing);
    expect(find.byKey(elimination), findsNothing);
  });

  testWidgets('a held ZapZap alone is over within 2.5 s', (tester) async {
    await pump(
      tester,
      roundEnd(players: heldPlayers.take(2).toList(), caller: 'HardBot1'),
    );
    await at(tester, 100);
    expect(find.byKey(held), findsOneWidget);
    await at(tester, 2400);
    expect(find.byKey(held), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a counteract stamps, then the gauge of the caller it put out', (
    tester,
  ) async {
    await pump(
      tester,
      roundEnd(
        players: counteredPlayers,
        caller: 'Vincent',
        wasCounterActed: true,
      ),
    );

    await at(tester, 100);
    expect(find.byKey(countered), findsOneWidget);
    expect(find.byKey(elimination), findsNothing);
    expect(find.byKey(held), findsNothing);

    // The caller's row is hit at 620 ms: "+41" pops above its column. The
    // round put Vincent out, so the gauge, not the stamp, counts the total.
    await at(tester, 700);
    expect(
      find.descendant(of: find.byKey(countered), matching: find.text('+41')),
      findsOneWidget,
    );
    expect(totalOf(tester, 0), '80');

    // The stamp is said at 1.92 s; the gauge follows it, once the stamp's
    // tail is gone.
    await at(tester, 1300);
    expect(find.byKey(elimination), findsOneWidget);
    expect(find.byKey(countered), findsNothing);
    await at(tester, 1000);
    expect(totalOf(tester, 0), '121');

    await at(tester, 2000);
    expect(find.byKey(elimination), findsNothing);
    expect(badgeShown(tester, 0), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a counteract that puts nobody out counts the caller up itself', (
    tester,
  ) async {
    const players = [
      RoundEndPlayer(
        playerIndex: 1,
        name: 'EasyBot1',
        hand: [13],
        roundScore: 0,
        totalScore: 30,
      ),
      RoundEndPlayer(
        playerIndex: 0,
        name: 'Vincent',
        hand: [0, 52],
        roundScore: 41,
        totalScore: 61,
        isZapZapCaller: true,
      ),
    ];
    await pump(
      tester,
      roundEnd(players: players, caller: 'Vincent', wasCounterActed: true),
    );
    await at(tester, 500);
    expect(totalOf(tester, 0), '20');
    await at(tester, 700);
    expect(totalOf(tester, 0), '61');
    await at(tester, 1000);
    expect(find.byKey(countered), findsNothing);
    expect(find.byKey(elimination), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a player out before this round is not eliminated again', (
    tester,
  ) async {
    const players = [
      RoundEndPlayer(
        playerIndex: 0,
        name: 'Vincent',
        hand: [0],
        roundScore: 0,
        totalScore: 20,
      ),
      RoundEndPlayer(
        playerIndex: 1,
        name: 'EasyBot1',
        hand: [],
        roundScore: 0,
        totalScore: 131,
        isEliminated: true,
      ),
    ];
    await pump(tester, roundEnd(players: players));
    expect(find.byType(RoundEndEffects), findsNothing);
    expect(badgeShown(tester, 1), isTrue);
  });

  testWidgets('a touch skips to the table, which stays live under them', (
    tester,
  ) async {
    await pump(
      tester,
      roundEnd(
        players: counteredPlayers,
        caller: 'Vincent',
        wasCounterActed: true,
      ),
    );
    await at(tester, 300);
    expect(find.byKey(countered), findsOneWidget);

    // Next round is reachable while the stamp falls: the touch reaches it
    // and skips what is left.
    await tester.tap(find.byKey(const Key('next-round')));
    await tester.pump();
    expect(nextRounds, 1);
    expect(find.byKey(countered), findsNothing);
    expect(find.byKey(elimination), findsNothing);
    // The rows end the 400 ms climb they started with the table.
    await at(tester, 100);
    expect(totalOf(tester, 0), '121');
    expect(badgeShown(tester, 0), isTrue);
    await tester.pumpAndSettle();
    expect(find.byKey(elimination), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a touch anywhere skips', (tester) async {
    await pump(tester, roundEnd(players: heldPlayers, caller: 'HardBot1'));
    await at(tester, 200);
    expect(find.byKey(held), findsOneWidget);
    await tester.tapAt(const Offset(180, 400));
    await tester.pump();
    expect(find.byKey(held), findsNothing);
    expect(find.byKey(elimination), findsNothing);
    await at(tester, 400);
    expect(totalOf(tester, 1), '104');
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the confetti of a win comes after the overlays', (tester) async {
    const players = [
      RoundEndPlayer(
        playerIndex: 0,
        name: 'Vincent',
        hand: [0],
        roundScore: 0,
        totalScore: 40,
        isMe: true,
        isZapZapCaller: true,
      ),
      RoundEndPlayer(
        playerIndex: 1,
        name: 'EasyBot1',
        hand: [9, 8],
        roundScore: 17,
        totalScore: 104,
        isEliminated: true,
      ),
    ];
    await pump(
      tester,
      roundEnd(
        players: players,
        caller: 'Vincent',
        gameFinished: true,
        winnerIsMe: true,
      ),
    );
    await at(tester, 100);
    expect(find.byKey(held), findsOneWidget);
    expect(find.byKey(const Key('victoryAnimation')), findsNothing);
    await at(tester, 1700);
    expect(find.byKey(elimination), findsOneWidget);
    expect(find.byKey(const Key('victoryAnimation')), findsNothing);
    await at(tester, 2500);
    expect(find.byKey(elimination), findsNothing);
    expect(find.byKey(const Key('victoryAnimation')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('with animations off, none of them is built', (tester) async {
    await pump(
      tester,
      roundEnd(
        players: counteredPlayers,
        caller: 'Vincent',
        wasCounterActed: true,
        gameFinished: true,
        winnerIsMe: true,
      ),
      disableAnimations: true,
    );
    expect(find.byType(RoundEndEffects), findsNothing);
    for (final key in [held, countered, elimination]) {
      expect(find.byKey(key), findsNothing);
    }
    expect(find.byKey(const Key('victoryAnimation')), findsNothing);
    expect(totalOf(tester, 0), '121');
    expect(badgeShown(tester, 0), isTrue);
    expect(tester.hasRunningAnimations, isFalse);

    await pump(
      tester,
      roundEnd(players: heldPlayers, caller: 'HardBot1'),
      disableAnimations: true,
    );
    expect(find.byType(RoundEndEffects), findsNothing);
    expect(find.byKey(held), findsNothing);
    expect(find.byKey(elimination), findsNothing);
  });

  /// Eight players at twice the text size: the table scrolls.
  List<RoundEndPlayer> longTable({Set<int> out = const {}}) => [
    for (var i = 0; i < 8; i++)
      RoundEndPlayer(
        playerIndex: i,
        name: 'Bot$i',
        hand: const [4, 5, 6],
        roundScore: i * 3,
        totalScore: out.contains(i) ? 100 + i : 20 + i,
        isEliminated: out.contains(i),
        isZapZapCaller: i == 0,
      ),
  ];

  testWidgets('eliminations far down a long table are all scrolled into view', (
    tester,
  ) async {
    await pump(tester, roundEnd(players: longTable(out: {6, 7})), textScale: 2);
    await at(tester, 100);
    // Its own scroll does not skip it.
    expect(find.byKey(elimination), findsOneWidget);
    final view = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('roundOver')),
        matching: find.byType(Scrollable),
      ),
    );
    for (final index in [6, 7]) {
      final row = tester.getRect(find.byKey(GameRoundEnd.playerKey(index)));
      expect(row.top, greaterThanOrEqualTo(view.top), reason: 'row $index');
      expect(row.bottom, lessThanOrEqualTo(view.bottom), reason: 'row $index');
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wheel or trackpad scroll skips them: they aim at the rows', (
    tester,
  ) async {
    await pump(
      tester,
      roundEnd(players: longTable(), caller: 'Bot0'),
      textScale: 2,
    );
    await at(tester, 300);
    expect(find.byKey(held), findsOneWidget);
    // No pointer down: a signal, as a mouse wheel sends.
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('roundOver')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: const Offset(180, 300),
        scrollDelta: const Offset(0, 80),
      ),
    );
    await tester.pump();
    expect(position.pixels, greaterThan(0));
    expect(find.byKey(held), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a resize or a rotation skips them', (tester) async {
    await pump(tester, roundEnd(players: heldPlayers, caller: 'HardBot1'));
    await at(tester, 300);
    expect(find.byKey(held), findsOneWidget);
    tester.view.physicalSize = const Size(740, 360);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(held), findsNothing);
    expect(find.byKey(elimination), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"ZAPZAP!" drops in left to right in Arabic too', (tester) async {
    await pump(
      tester,
      roundEnd(players: heldPlayers.take(2).toList(), caller: 'HardBot1'),
      locale: 'ar',
    );
    await at(tester, 900);
    Finder letter(String text) =>
        find.descendant(of: find.byKey(held), matching: find.text(text));
    double x(Finder finder) => tester.getCenter(finder).dx;
    final zeds = letter('Z').evaluate().map((e) => x(find.byWidget(e.widget)));
    final bang = x(letter('!').first);
    expect(zeds, isNotEmpty);
    for (final z in zeds) {
      expect(z, lessThan(bang));
    }
    expect(x(letter('Z').first), lessThan(x(letter('A').first)));
  });

  test('the bolt starts inside the area, from the side the icon faces', () {
    const target = Offset(340, 60);
    final rtl = HeldBoltPhase.boltOrigin(target, 360, TextDirection.rtl);
    expect(rtl.dx, lessThan(target.dx - 39));
    expect(rtl.dx, greaterThanOrEqualTo(8));
    final ltr = HeldBoltPhase.boltOrigin(target, 360, TextDirection.ltr);
    expect(ltr.dx, lessThanOrEqualTo(352), reason: 'clamped inside');
    final left = HeldBoltPhase.boltOrigin(
      const Offset(20, 60),
      360,
      TextDirection.ltr,
    );
    expect(left.dx, greaterThan(59));
  });

  test('two adjacent rows share one hole in the veil', () {
    const size = Size(360, 740);
    final path = spotPath(size, const [
      Rect.fromLTWH(0, 100, 360, 50),
      Rect.fromLTWH(0, 150, 360, 50),
    ]);
    // Where the two holes, grown by 2 px, overlap: not darkened again.
    expect(path.contains(const Offset(180, 150)), isFalse);
    expect(path.contains(const Offset(180, 101)), isFalse);
    expect(path.contains(const Offset(180, 199)), isFalse);
    expect(path.contains(const Offset(180, 40)), isTrue);
    expect(path.contains(const Offset(180, 260)), isTrue);
  });

  testWidgets('a counteracted caller losing in Golden Score gets the tape, '
      'not a gauge past 100', (tester) async {
    const players = [
      RoundEndPlayer(
        playerIndex: 1,
        name: 'EasyBot1',
        hand: [13],
        roundScore: 0,
        totalScore: 90,
        isLowestHand: true,
      ),
      RoundEndPlayer(
        playerIndex: 0,
        name: 'Vincent',
        hand: [0, 52],
        roundScore: 31,
        totalScore: 98,
        isEliminated: true,
        isZapZapCaller: true,
        isMe: true,
      ),
    ];
    await pump(
      tester,
      roundEnd(players: players, caller: 'Vincent', wasCounterActed: true),
    );
    await at(tester, 1200);
    // The stamp counts the caller's total, not a gauge.
    expect(totalOf(tester, 0), '98');
    await at(tester, 1000);
    expect(find.byKey(elimination), findsOneWidget);
    expect(find.byKey(const Key('eliminationGauge')), findsNothing);
    await at(tester, 1100);
    expect(find.textContaining('ÉLIMINÉ ×'), findsOneWidget);
    expect(badgeShown(tester, 0), isFalse);
    await at(tester, 1000);
    expect(badgeShown(tester, 0), isTrue);
    expect(totalOf(tester, 0), '98');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the hidden badge is read out all along', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, roundEnd(players: heldPlayers, caller: 'HardBot1'));
    await at(tester, 300);
    expect(badgeShown(tester, 1), isFalse);
    expect(find.bySemanticsLabel('Éliminé'), findsOneWidget);
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the table is shaken only while a shake runs, and not repainted '
      'by the clock', (tester) async {
    await pump(
      tester,
      roundEnd(players: heldPlayers.take(2).toList(), caller: 'HardBot1'),
    );
    final table = find.byKey(const Key('roundEndTable'));
    await at(tester, 200);
    final shaken = tester.getTopLeft(table);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byType(FxShake).first,
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    await at(tester, 800);
    final still = tester.getTopLeft(table);
    // A repaint records new pictures into the boundary's layer.
    final picture = boundary.debugLayer!.firstChild;
    for (var i = 0; i < 6; i++) {
      await at(tester, 100);
    }
    expect(identical(boundary.debugLayer!.firstChild, picture), isTrue);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(table), still);
    expect(shaken, isNot(still));
  });

  testWidgets('the stamp is painted once, then only moved', (tester) async {
    const players = [
      RoundEndPlayer(
        playerIndex: 1,
        name: 'EasyBot1',
        hand: [13],
        roundScore: 0,
        totalScore: 30,
      ),
      RoundEndPlayer(
        playerIndex: 0,
        name: 'Vincent',
        hand: [0, 52],
        roundScore: 41,
        totalScore: 61,
        isZapZapCaller: true,
      ),
    ];
    await pump(
      tester,
      roundEnd(players: players, caller: 'Vincent', wasCounterActed: true),
    );
    await at(tester, 100);
    final stamp = tester.renderObject<RenderRepaintBoundary>(
      find
          .descendant(
            of: find.byKey(countered),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    // A repaint records a new picture into the stamp's layer.
    final picture = stamp.debugLayer!.firstChild;
    expect(picture, isNotNull);
    // It falls, bounces and lifts: moved, never painted again.
    for (var i = 0; i < 16; i++) {
      await at(tester, 100);
      expect(identical(stamp.debugLayer!.firstChild, picture), isTrue);
    }
    await tester.pumpAndSettle();
  });
}
