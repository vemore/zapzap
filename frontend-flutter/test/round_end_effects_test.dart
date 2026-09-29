import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/widgets/game_round_end.dart';
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
  }) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
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

  testWidgets('an elimination far down a long table scrolls it into view', (
    tester,
  ) async {
    final players = [
      for (var i = 0; i < 8; i++)
        RoundEndPlayer(
          playerIndex: i,
          name: 'Bot$i',
          hand: const [4, 5, 6],
          roundScore: i * 3,
          totalScore: i == 7 ? 108 : 20 + i,
          isEliminated: i == 7,
        ),
    ];
    await pump(tester, roundEnd(players: players), textScale: 2);
    await at(tester, 100);
    expect(find.byKey(elimination), findsOneWidget);
    final row = tester.getRect(find.byKey(GameRoundEnd.playerKey(7)));
    final footer = tester.getRect(find.byKey(const Key('roundEndFooter')));
    expect(row.bottom, lessThanOrEqualTo(footer.top));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
