import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/router.dart';
import 'package:zapzap/utils/date_format.dart';
import 'package:zapzap/widgets/history_game_tile.dart';
import 'package:zapzap/widgets/stats_common.dart';

import 'fixtures.dart';
import 'history_helpers.dart';

void main() {
  const partyId = 'da33c689-6f43-49d4-ba89-953f105e7960';
  const winnerId = '74a0d812-54b3-4b99-95a3-ca56596fe8bf';
  const easyBotId = '2f76f109-185e-45ee-9890-4a5240f0f901';
  const vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';

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

      expect(requests.single.url.path, '/api/history');
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

      expect(requests.map((r) => r.url.path), [
        '/api/history',
        '/api/history/public',
      ]);
      expect(find.byType(HistoryGameTile), findsOneWidget);
    });

    testWidgets('no game shows the empty message of the tab', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi({'/api/history': '{"success":true,"games":[]}'}),
      );

      expect(find.byKey(const Key('async-empty')), findsOneWidget);
      expect(
        find.text('Aucune partie terminée. Jouez pour remplir votre historique !'),
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
      expect(requests.length, 2);
    });

    testWidgets('tapping a game opens its details', (tester) async {
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi(historyBodies()),
      );

      await tester.tap(find.byKey(const Key('history-game-$partyId')));
      await tester.pumpAndSettle();

      expect(find.text('Classement final'), findsOneWidget);
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
}
