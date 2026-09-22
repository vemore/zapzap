import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/widgets/stats_leaderboard.dart';
import 'package:zapzap/widgets/stats_personal.dart';

import 'fixtures.dart';
import 'history_helpers.dart';

void main() {
  const vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';

  Map<String, String> statsBodies() => {
    '/api/stats/me': fixtureText('stats_me'),
    '/api/stats/leaderboard': fixtureText('stats_leaderboard'),
    '/api/stats/bots': fixtureText('stats_bots'),
  };

  Future<void> pumpStats(WidgetTester tester, {String userId = vincentId}) =>
      pumpScreen(
        tester,
        initialLocation: AppRoutes.stats,
        api: routedApi(statsBodies()),
        userId: userId,
      );

  bool highlighted(WidgetTester tester, String userId) => tester
      .widget<LeaderboardRow>(find.byKey(Key('leaderboard-row-$userId')))
      .isCurrentUser;

  testWidgets('personal statistics come from /stats/me', (tester) async {
    await pumpStats(tester);

    expect(find.text('Mes statistiques'), findsOneWidget);
    expect(find.text('Parties jouées'), findsWidgets);
    // 1 game, 0 win, a 0 win rate, an average of 122.
    expect(find.text('0.0%'), findsWidgets);
    expect(find.text('122.0'), findsOneWidget);
    expect(find.text('Performance ZapZap'), findsOneWidget);
    // No ZapZap called, so no success rate line in the ZapZap block (the
    // bots' cards further down have one of their own).
    expect(
      find.descendant(
        of: find.byType(StatsPersonal),
        matching: find.text('Taux de réussite'),
      ),
      findsNothing,
    );
    expect(find.text('Meilleur score'), findsOneWidget);
    expect(find.text('122'), findsOneWidget);
  });

  testWidgets('my own leaderboard row is highlighted and marked', (
    tester,
  ) async {
    await pumpStats(tester);

    expect(find.byType(LeaderboardRow), findsOneWidget);
    expect(highlighted(tester, vincentId), isTrue);
    expect(find.textContaining('(vous)'), findsOneWidget);
  });

  testWidgets('another user is not highlighted — the React bug this port '
      'fixes', (tester) async {
    await pumpStats(tester, userId: 'someone-else');

    expect(highlighted(tester, vincentId), isFalse);
    expect(find.textContaining('(vous)'), findsNothing);
  });

  testWidgets('the leaderboard row shows the wins and the win rate', (
    tester,
  ) async {
    await pumpStats(tester);

    expect(find.text('0/1 victoires'), findsOneWidget);
    expect(find.text('taux de victoire'), findsOneWidget);
    expect(find.text('1 partie jouée minimum pour figurer au classement'),
        findsOneWidget);
  });

  group('bots', () {
    testWidgets('every difficulty is shown with its strategy', (tester) async {
      await pumpStats(tester);

      expect(find.byKey(const Key('bot-card-easy')), findsOneWidget);
      expect(find.byKey(const Key('bot-card-medium')), findsOneWidget);
      expect(find.text('Stratégie aléatoire'), findsOneWidget);
      expect(find.text('Priorité aux grosses cartes'), findsOneWidget);
      expect(find.text('1 bot'), findsNWidgets(2));
      // Totals: 2 bots, 50 % overall win rate, every ZapZap successful.
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('100.0%'), findsWidgets);
      // No difficulty picked yet, so no per-bot breakdown.
      expect(find.text('Bot par bot'), findsNothing);
    });

    testWidgets('picking a difficulty filters it and lists its bots', (
      tester,
    ) async {
      await pumpStats(tester);

      await tester.tap(find.byKey(const Key('bot-difficulty-easy')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bot-card-easy')), findsOneWidget);
      expect(find.byKey(const Key('bot-card-medium')), findsNothing);
      expect(find.text('Bot par bot'), findsOneWidget);
      expect(
        find.byKey(const Key('bot-row-2f76f109-185e-45ee-9890-4a5240f0f901')),
        findsOneWidget,
      );
      expect(find.text('EasyBot1'), findsOneWidget);
      expect(find.text('1 partie · 0 victoire · 5 manches'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bot-difficulty-all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bot-card-medium')), findsOneWidget);
      expect(find.text('Bot par bot'), findsNothing);
    });
  });

  testWidgets('a failing section leaves the others standing', (tester) async {
    await pumpScreen(
      tester,
      initialLocation: AppRoutes.stats,
      // No leaderboard body: that read alone answers 404.
      api: routedApi({
        '/api/stats/me': fixtureText('stats_me'),
        '/api/stats/bots': fixtureText('stats_bots'),
      }),
    );

    expect(find.text('Impossible de charger le classement.'), findsOneWidget);
    expect(find.text('Mes statistiques'), findsOneWidget);
    expect(find.byKey(const Key('bot-card-easy')), findsOneWidget);
  });
}
