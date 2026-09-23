import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/game_details_screen.dart';
import 'package:zapzap/screens/history_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/utils/date_format.dart';
import 'package:zapzap/widgets/connection_indicator.dart';
import 'package:zapzap/widgets/history_game_tile.dart';
import 'package:zapzap/widgets/stats_common.dart';
import 'package:zapzap/widgets/zapzap_app_bar.dart';

import 'fixtures.dart';
import 'history_helpers.dart';

void main() {
  const partyId = 'da33c689-6f43-49d4-ba89-953f105e7960';
  const winnerId = '74a0d812-54b3-4b99-95a3-ca56596fe8bf';
  const easyBotId = '2f76f109-185e-45ee-9890-4a5240f0f901';
  const vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';

  /// The history reads among [requests]: the app bar reads who is online
  /// too.
  List<String> historyPaths(List<http.Request> requests) => [
    for (final request in requests)
      if (request.url.path.startsWith('/api/history')) request.url.path,
  ];

  Map<String, String> historyBodies() => {
    '/api/history': fixtureText('history_list'),
    '/api/history/public': fixtureText('history_public'),
    '/api/history/$partyId': fixtureText('history_details'),
  };

  group('history', () {
    testWidgets('My games lists the finished games of the backend', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi(historyBodies(), requests: requests),
      );

      expect(historyPaths(requests), ['/api/history']);
      expect(find.byType(HistoryGameTile), findsOneWidget);
      expect(find.text('Fixture party'), findsOneWidget);
      expect(find.text('MediumBot1 (77 pts)'), findsOneWidget);
      expect(find.text('3 joueurs'), findsOneWidget);
      expect(find.text('5 manches'), findsOneWidget);
      expect(find.text('Golden Score'), findsOneWidget);
      // The date is the backend's Unix seconds, in the device's zone.
      expect(
        find.text(
          Formats.dateTime(
            DateTime.fromMillisecondsSinceEpoch(1790094408 * 1000, isUtc: true),
            'fr',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the Public tab reads /history/public', (tester) async {
      final requests = <http.Request>[];
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi(historyBodies(), requests: requests),
      );

      await tester.tap(find.text('Parties publiques'));
      await tester.pumpAndSettle();

      expect(historyPaths(requests), ['/api/history', '/api/history/public']);
      expect(find.byType(HistoryGameTile), findsOneWidget);
    });

    testWidgets('no game of mine shows the way to a game', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi({'/api/history': '{"success":true,"games":[]}'}),
      );

      // My games has its own empty state (test/history_ux_test.dart).
      expect(find.byKey(const Key('history-invite')), findsOneWidget);
      expect(find.byType(HistoryGameTile), findsNothing);
    });

    testWidgets('no public game shows the empty message of the tab', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi({
          '/api/history': fixtureText('history_list'),
          '/api/history/public': '{"success":true,"games":[]}',
        }),
      );

      await tester.tap(find.text('Parties publiques'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('async-empty')), findsOneWidget);
      expect(
        find.text('Aucune partie publique terminée pour le moment.'),
        findsOneWidget,
      );
      expect(find.byType(HistoryGameTile), findsNothing);
    });

    testWidgets('a failed read shows the error and tries again', (
      tester,
    ) async {
      final requests = <http.Request>[];
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        // No body for `/api/history`: the routed client answers 404.
        api: routedApi(const {}, requests: requests),
      );

      expect(find.text("Impossible de charger l'historique."), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(historyPaths(requests), ['/api/history', '/api/history']);
    });

    testWidgets('tapping a game opens its details, and Back returns to the '
        'list', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi(historyBodies()),
      );

      await tester.tap(find.byKey(const Key('history-game-$partyId')));
      await tester.pumpAndSettle();

      expect(find.text('Classement final'), findsOneWidget);
      // Pushed over the list: the Android system Back pops back to it
      // rather than leaving the app.
      expect(find.byType(GameDetailsScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(GameDetailsScreen), findsNothing);
      expect(find.byType(HistoryScreen), findsOneWidget);

      // and so does the app-bar back button
      await tester.tap(find.byKey(const Key('history-game-$partyId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
    });

    testWidgets('the app bar is the signed-in one: who is online, the '
        'connection, the menu', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi({
          ...historyBodies(),
          '/api/players/connected':
              '{"players":[{"userId":"u1","username":"Vincent",'
              '"status":"lobby","connectedAt":1790094174000}]}',
        }),
      );

      expect(find.byType(ZapZapAppBar), findsOneWidget);
      expect(find.byType(ConnectionIndicator), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('connected-players-count')))
            .data,
        '1',
      );
      expect(find.byKey(const Key('app-bar-menu')), findsOneWidget);
    });

    testWidgets('opened by a link, its back button leads to the parties', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi(historyBodies()),
      );

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.byType(PartiesScreen), findsOneWidget);
    });
  });

  group('game details', () {
    Future<void> pumpDetails(WidgetTester tester) => pumpScreen(
      tester,
      initialLocation: AppRoutes.gameDetails(partyId),
      api: routedApi(historyBodies()),
    );

    testWidgets('shows the summary and the winner', (tester) async {
      await pumpDetails(tester);

      // The app bar takes the game's name once it is read.
      expect(find.text('Fixture party'), findsOneWidget);
      expect(find.text('Fin en Golden Score'), findsOneWidget);
      expect(find.byKey(const Key('game-winner')), findsOneWidget);
      expect(find.text('MediumBot1'), findsWidgets);
      expect(find.text('Score final : 77 points'), findsOneWidget);
      expect(find.text('Publique'), findsOneWidget);
      // The summary grid: 3 players over 5 rounds.
      expect(find.text('Joueurs'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Joueurs'),
            matching: find.byType(StatTile),
          ),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Manches'),
            matching: find.byType(StatTile),
          ),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the standings are in finishing order, the winner marked', (
      tester,
    ) async {
      await pumpDetails(tester);

      expect(find.byKey(const Key('standings-$winnerId')), findsOneWidget);
      expect(find.byKey(const Key('standings-$easyBotId')), findsOneWidget);
      expect(find.byKey(const Key('standings-$vincentId')), findsOneWidget);
      // MediumBot1 won with 77, EasyBot1 scored 58: the lowest score does
      // not win, the finishing position does.
      expect(find.text('77 pts'), findsOneWidget);
      expect(find.text('58 pts'), findsOneWidget);
      expect(find.text('122 pts'), findsOneWidget);
      expect(find.text('1/1 ZapZap'), findsOneWidget);
      expect(find.text('3/3 ZapZap'), findsOneWidget);
      expect(find.text('0/0 ZapZap'), findsOneWidget);
      expect(find.text('3 plus petites mains'), findsOneWidget);
      expect(find.text('1 plus petite main'), findsOneWidget);
      // French counts zero as a singular, and the count is in the message.
      expect(find.text('0 plus petite main'), findsOneWidget);
    });

    testWidgets('the round-by-round table has a row per round and a legend', (
      tester,
    ) async {
      await pumpDetails(tester);

      expect(find.byKey(const Key('rounds-table')), findsOneWidget);
      for (var round = 1; round <= 5; round++) {
        expect(find.text('Manche $round'), findsOneWidget);
      }
      // Round 1: Vincent took 28 points, MediumBot1 none with the lowest hand.
      expect(find.text('+28'), findsOneWidget);
      expect(find.text('(28)'), findsOneWidget);
      expect(find.text('Plus petite main'), findsOneWidget);
      expect(find.text('ZapZap réussi'), findsOneWidget);
      expect(find.text('ZapZap raté'), findsOneWidget);
      expect(find.text('Éliminé'), findsOneWidget);
      expect(find.text('Contré'), findsOneWidget);
    });

    testWidgets('a counteracted caller is red, even on the lowest hand', (
      tester,
    ) async {
      // The capture has no counteracted round, so the last one is turned into
      // the Golden-Score tie `GAME_RULES.md` describes: MediumBot1 calls,
      // holds the lowest hand, is counteracted all the same and pays
      // 3 + (3 − 1) × 5. The local database has rows of that shape
      // (`was_counteracted = 1 AND is_lowest_hand = 1`).
      final details = fixture('history_details');
      final lastRound = (details['rounds'] as List).last as Map;
      final caller = (lastRound['players'] as List).cast<Map>().firstWhere(
        (player) => player['userId'] == winnerId,
      );
      caller
        ..['zapZapSuccess'] = false
        ..['wasCounterActed'] = true
        ..['isLowestHand'] = true
        ..['scoreThisRound'] = 13
        ..['totalScoreAfter'] = 90;
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.gameDetails(partyId),
        api: routedApi({
          ...historyBodies(),
          '/api/history/$partyId': jsonEncode(details),
        }),
      );

      final score = tester.widget<Text>(find.text('+13'));
      expect(score.style?.color, StatsColors.danger);
      expect(find.text('(90)'), findsOneWidget);
      // A lowest hand that was not a counteracted call stays green.
      final earlier = tester.widget<Text>(find.text('+0').first);
      expect(earlier.style?.color, StatsColors.success);
    });

    testWidgets('an unknown game says so rather than failing generically', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.gameDetails('nope'),
        api: routedApi(const {}),
      );

      expect(find.text('Cette partie est introuvable.'), findsOneWidget);
    });
  });

  group('phone width', () {
    // Anything that does not fit throws a layout error, which fails the
    // test. A 1.5 text scale is the same layout with every text wider: a
    // row of unconstrained texts overflows there and nowhere else.
    for (final scale in [1.0, 1.5]) {
      final at = scale == 1 ? '' : ' at a $scale text scale';

      testWidgets('the history list fits$at', (tester) async {
        await pumpScreen(
          tester,
          initialLocation: AppRoutes.history,
          api: routedApi(historyBodies()),
          size: phoneSize,
          textScale: scale,
        );

        expect(find.byType(HistoryGameTile), findsOneWidget);
      });

      testWidgets('the game details fit$at', (tester) async {
        await pumpScreen(
          tester,
          initialLocation: AppRoutes.gameDetails(partyId),
          api: routedApi(historyBodies()),
          size: phoneSize,
          textScale: scale,
        );

        // The summary card, whose header carries the golden-score badge
        // beside the title — the narrowest row of the screen.
        expect(find.byKey(const Key('game-winner')), findsOneWidget);
        expect(find.text('Fin en Golden Score'), findsOneWidget);
        // Then the two cards below it: on a phone each lays out — and each
        // could overflow — only once scrolled into view.
        await tester.scrollUntilVisible(
          find.byKey(const Key('standings-$winnerId')),
          300,
        );
        expect(find.byKey(const Key('standings-$winnerId')), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Contré'), 300);
        expect(find.byKey(const Key('rounds-table')), findsOneWidget);
      });
    }
  });
}
