import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/create_party_screen.dart';
import 'package:zapzap/screens/history_screen.dart';
import 'package:zapzap/screens/stats_screen.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/history_game_tile.dart';

import 'history_helpers.dart';

/// The history and statistics put my own result first (H1, H2, H3, St1, St2
/// of the Flutter UX study).
void main() {
  const vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';

  /// A Rust `GET /history` entry: `roundsPlayed`, `userPlacement`,
  /// `userScore`, no winner id or score.
  Map<String, Object?> rustGame(
    String id, {
    int? placement,
    int? score,
    String winner = 'HardBot1',
  }) => {
    'partyId': id,
    'partyName': 'Partie $id',
    'finishedAt': 1790094408,
    'playerCount': 4,
    'roundsPlayed': 7,
    'winnerUsername': winner,
    'userPlacement': ?placement,
    'userScore': ?score,
  };

  /// An older Node `GET /history` entry (before 2026-09-24): a winner id and
  /// score, no place of mine.
  Map<String, Object?> nodeGame(String id, {required String winnerId}) => {
    'id': 1,
    'partyId': id,
    'partyName': 'Partie $id',
    'winnerUserId': winnerId,
    'winnerUsername': winnerId == vincentId ? 'Vincent' : 'MediumBot1',
    'winnerFinalScore': 40,
    'totalRounds': 5,
    'wasGoldenScore': false,
    'playerCount': 3,
    'finishedAt': 1790094408,
    'visibility': 'public',
  };

  String page(List<Map<String, Object?>> games) =>
      jsonEncode({'success': true, 'games': games, 'total': games.length});

  String stats({
    int games = 1,
    int wins = 0,
    num average = 134.0,
    int best = 134,
    int calls = 0,
    int successful = 0,
  }) => jsonEncode({
    'success': true,
    'userId': vincentId,
    'username': 'Vincent',
    'stats': {
      'gamesPlayed': games,
      'wins': wins,
      'losses': games - wins,
      'winRate': games == 0 ? 0 : wins / games,
      'averageScore': average,
      'bestScore': best,
      'totalRoundsPlayed': 7,
      'zapzaps': {
        'total': calls,
        'successful': successful,
        'failed': calls - successful,
        'successRate': calls == 0 ? 0 : successful / calls,
      },
      'lowestHandCount': 0,
    },
  });

  Future<void> pumpHistory(
    WidgetTester tester,
    List<Map<String, Object?>> games, {
    String? statsBody,
    Size size = const Size(1100, 3000),
    double textScale = 1,
  }) => pumpScreen(
    tester,
    initialLocation: AppRoutes.history,
    api: routedApi({
      '/api/history': page(games),
      '/api/history/public': page(games),
      '/api/stats/me': ?statsBody,
    }),
    size: size,
    textScale: textScale,
  );

  Finder inTile(String partyId, Finder matching) => find.descendant(
    of: find.byKey(Key('history-game-$partyId')),
    matching: matching,
  );

  BoxDecoration badgeOf(WidgetTester tester, String partyId) =>
      tester
              .widget<Container>(
                inTile(partyId, find.byKey(const Key('history-placement'))),
              )
              .decoration!
          as BoxDecoration;

  group('H1 my result on each game', () {
    testWidgets('a place badge opens the row, amber when I won', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpHistory(tester, [
        rustGame('won', placement: 1, score: 12, winner: 'Vincent'),
        rustGame('lost', placement: 4, score: 134),
      ], statsBody: stats(games: 2, wins: 1));

      expect(inTile('won', find.text('1er')), findsOneWidget);
      expect(inTile('lost', find.text('4e')), findsOneWidget);
      expect(badgeOf(tester, 'won').color, AppColors.amber400);
      expect(badgeOf(tester, 'lost').color, isNull);
      // The row's InkWell merges its texts: the badge reads as a sentence.
      expect(find.bySemanticsLabel(RegExp('Ta place : 4e')), findsOneWidget);
      semantics.dispose();
      // The badge is the first thing of the row.
      expect(
        tester
            .getTopLeft(
              inTile('lost', find.byKey(const Key('history-placement'))),
            )
            .dx,
        lessThan(tester.getTopLeft(find.text('Partie lost')).dx),
      );
    });

    testWidgets('my score shows beside the winner', (tester) async {
      await pumpHistory(tester, [
        rustGame('lost', placement: 4, score: 134),
      ], statsBody: stats());

      expect(inTile('lost', find.text('HardBot1')), findsOneWidget);
      expect(inTile('lost', find.text('toi : 134 pts')), findsOneWidget);
    });

    testWidgets('Node: a win of mine still shows first, a loss no badge', (
      tester,
    ) async {
      await pumpHistory(tester, [
        nodeGame('won', winnerId: vincentId),
        nodeGame('lost', winnerId: 'someone-else'),
      ]);

      expect(inTile('won', find.text('1er')), findsOneWidget);
      expect(
        inTile('lost', find.byKey(const Key('history-placement'))),
        findsNothing,
      );
      expect(find.byKey(const Key('history-my-score')), findsNothing);
    });

    testWidgets('the public tab shows no place of mine', (tester) async {
      await pumpHistory(tester, [
        rustGame('lost', placement: 4, score: 134),
      ], statsBody: stats());

      await tester.tap(find.text('Parties publiques'));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryGameTile), findsOneWidget);
      expect(find.byKey(const Key('history-placement')), findsNothing);
      expect(find.text('toi : 134 pts'), findsNothing);
      expect(find.byKey(const Key('history-summary')), findsNothing);
    });

    test('the places as ordinals, in French and in English', () {
      final fr = lookupAppLocalizations(const Locale('fr'));
      final en = lookupAppLocalizations(const Locale('en'));
      expect(
        [
          for (final p in [1, 2, 4]) placementLabel(fr, p),
        ],
        ['1er', '2e', '4e'],
      );
      expect(
        [
          for (final p in [1, 2, 3, 4, 8]) placementLabel(en, p),
        ],
        ['1st', '2nd', '3rd', '4th', '8th'],
      );
    });
  });

  group('H2 summary and the way to the statistics', () {
    testWidgets('games, wins and best place open the list', (tester) async {
      await pumpHistory(tester, [
        rustGame('a', placement: 4, score: 134),
        rustGame('b', placement: 2, score: 40),
      ], statsBody: stats(games: 12, wins: 0));

      final summary = find.byKey(const Key('history-summary'));
      expect(summary, findsOneWidget);
      // Games and wins are the whole record (/stats/me), not the page.
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary-games')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      expect(find.text('parties'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary-wins')),
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary-best')),
          matching: find.text('2e'),
        ),
        findsOneWidget,
      );
      expect(find.text('meilleur rang'), findsOneWidget);
      // Above the first game.
      expect(
        tester.getTopLeft(summary).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('history-game-a'))).dy),
      );
    });

    testWidgets('a win in the record makes the best place first', (
      tester,
    ) async {
      await pumpHistory(tester, [
        rustGame('a', placement: 4, score: 134),
      ], statsBody: stats(games: 30, wins: 1));

      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary-best')),
          matching: find.text('1er'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unknown figures show a dash, the link still works', (
      tester,
    ) async {
      // No /stats/me body: that read fails; Node gives no place.
      await pumpHistory(tester, [nodeGame('a', winnerId: 'someone-else')]);

      expect(find.byKey(const Key('history-summary')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary')),
          matching: find.text('—'),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('it pushes the statistics, and Back returns', (tester) async {
      await pumpHistory(tester, [
        rustGame('a', placement: 4, score: 134),
      ], statsBody: stats());

      await tester.tap(find.byKey(const Key('history-summary-stats')));
      await tester.pumpAndSettle();
      expect(find.byType(StatsScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.byType(StatsScreen), findsNothing);
    });
  });

  group('H3 an empty state that leads to a game', () {
    testWidgets('no game: the invitation alone', (tester) async {
      await pumpHistory(tester, const [], statsBody: stats(games: 0));

      expect(
        find.text('Tes prochaines parties terminées apparaîtront ici.'),
        findsOneWidget,
      );
      expect(find.text('Lancer une partie contre des bots'), findsOneWidget);
      expect(find.byKey(const Key('history-summary')), findsNothing);
      expect(find.byType(HistoryGameTile), findsNothing);
    });

    testWidgets('the link pushes the create-party form, and Back returns', (
      tester,
    ) async {
      await pumpHistory(tester, const [], statsBody: stats(games: 0));

      await tester.tap(find.byKey(const Key('history-invite-play')));
      await tester.pumpAndSettle();
      expect(find.byType(CreatePartyScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('a short list ends on the invitation', (tester) async {
      await pumpHistory(tester, [
        rustGame('a', placement: 4, score: 134),
      ], statsBody: stats());

      final invite = find.byKey(const Key('history-invite'));
      expect(invite, findsOneWidget);
      expect(
        tester.getTopLeft(invite).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const Key('history-game-a'))).dy,
        ),
      );
    });

    testWidgets('a list of ${HistoryScreen.inviteBelow} games does not', (
      tester,
    ) async {
      await pumpHistory(tester, [
        for (final id in ['a', 'b', 'c']) rustGame(id, placement: 2, score: 9),
      ], statsBody: stats(games: 3));

      expect(find.byType(HistoryGameTile), findsNWidgets(3));
      expect(find.byKey(const Key('history-invite')), findsNothing);
    });
  });

  group('St1 two hero figures, the rest as a list', () {
    testWidgets('wins over games and the average in large', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.stats,
        api: routedApi({'/api/stats/me': stats(games: 1, wins: 0)}),
      );

      final wins = find.byKey(const Key('stats-hero-wins'));
      final average = find.byKey(const Key('stats-hero-average'));
      expect(
        find.descendant(of: wins, matching: find.text('0 / 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: wins, matching: find.text('Victoire / partie')),
        findsOneWidget,
      );
      // 134.0 reads 134.
      expect(
        find.descendant(of: average, matching: find.text('134')),
        findsOneWidget,
      );
      expect(find.text('134.0'), findsNothing);
      // The rest is a list: rate, best score, rounds.
      expect(find.text('Taux de victoire'), findsOneWidget);
      expect(find.text('Meilleur score'), findsOneWidget);
      expect(find.text('Manches jouées'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      // Larger than a list figure.
      final heroSize = tester.getSize(
        find.descendant(of: wins, matching: find.text('0 / 1')),
      );
      final lineSize = tester.getSize(find.text('7'));
      expect(heroSize.height, greaterThan(lineSize.height));
    });

    testWidgets('a fractional average keeps its decimal', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.stats,
        api: routedApi({
          '/api/stats/me': stats(games: 4, wins: 3, average: 12.5),
        }),
      );

      expect(find.text('3 / 4'), findsOneWidget);
      expect(find.text('Victoires / parties'), findsOneWidget);
      expect(find.text('12.5'), findsOneWidget);
    });
  });

  group('St2 ZapZap bar and help', () {
    testWidgets('no call: the rule and an empty bar', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.stats,
        api: routedApi({'/api/stats/me': stats()}),
      );

      expect(
        find.text(
          'Pas encore de ZapZap appelé. Il faut une main de 5 points ou '
          'moins (joker = 0).',
        ),
        findsOneWidget,
      );
      expect(find.text('0 réussi / 0 appel'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('stats-zapzap-bar')),
      );
      expect(bar.value, 0);
    });

    testWidgets('calls: the successful share, no help', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.stats,
        api: routedApi({'/api/stats/me': stats(calls: 5, successful: 3)}),
      );

      expect(find.byKey(const Key('stats-zapzap-none')), findsNothing);
      expect(find.text('3 réussis / 5 appels'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byKey(const Key('stats-zapzap-bar')),
      );
      expect(bar.value, closeTo(0.6, 1e-9));
      expect(find.text('60.0%'), findsOneWidget);
    });
  });

  group('phone width', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      final at = scale == 1 ? '' : ' at a $scale text scale';

      testWidgets('the summary, badges and invitation fit$at', (tester) async {
        await pumpHistory(
          tester,
          [
            rustGame('a', placement: 1, score: 12, winner: 'Vincent'),
            rustGame('b', placement: 4, score: 134),
          ],
          statsBody: stats(games: 128, wins: 57),
          size: phoneSize,
          textScale: scale,
        );

        expect(find.byKey(const Key('history-summary')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('history-invite')),
          300,
        );
        expect(find.byKey(const Key('history-invite')), findsOneWidget);
      });

      testWidgets('the empty history fits$at', (tester) async {
        await pumpHistory(tester, const [], size: phoneSize, textScale: scale);

        expect(find.byKey(const Key('history-invite')), findsOneWidget);
      });

      testWidgets('the hero figures and the ZapZap bar fit$at', (tester) async {
        await pumpScreen(
          tester,
          initialLocation: AppRoutes.stats,
          api: routedApi({
            '/api/stats/me': stats(
              games: 1234,
              wins: 567,
              average: 88.75,
              calls: 1234,
              successful: 1000,
            ),
          }),
          size: phoneSize,
          textScale: scale,
        );

        expect(find.byKey(const Key('stats-hero-wins')), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('stats-zapzap-bar')),
          300,
        );
        expect(find.text('1000 réussis / 1234 appels'), findsOneWidget);
      });
    }
  });
}
