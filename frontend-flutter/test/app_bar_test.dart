import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/admin_screen.dart';
import 'package:zapzap/screens/game_screen.dart';
import 'package:zapzap/screens/history_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/stats_screen.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/widgets/connection_indicator.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/rules_sheet.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// The app signed in on the parties list, with [backend] answering the API.
  ///
  /// The window is tall by default so every action is built; the phone-width
  /// tests pass [size] and [textScale], where a row that does not fit throws
  /// a layout error and fails the test.
  Future<void> pumpApp(
    WidgetTester tester, {
    FakeLobbyBackend? backend,
    bool isAdmin = false,
    Size size = const Size(1000, 2000),
    double textScale = 1,
    MemoryTokenStorage? storage,
    Locale locale = const Locale('fr'),
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
        locale: locale,
        initialLocation: AppRoutes.parties,
        apiClient: (backend ?? FakeLobbyBackend()).client(),
        tokenStorage: storage ?? storedSession(validToken, isAdmin: isAdmin),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The router driving the screen on show.
  GoRouter routerOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  /// The path of the screen on top — the pushed one, where
  /// `currentConfiguration.uri` would still name the one below it.
  String locationOf(WidgetTester tester) => routerOf(tester).state.uri.path;

  /// The Android system Back button.
  Future<void> systemBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('app-bar-menu')));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String item) async {
    await openMenu(tester);
    await tester.tap(find.byKey(Key(item)));
    await tester.pumpAndSettle();
  }

  group('app bar menu', () {
    testWidgets('it leads to the history, and Back returns to the list', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(locationOf(tester), AppRoutes.parties);

      await choose(tester, 'menu-history');

      expect(locationOf(tester), AppRoutes.history);
      expect(find.byType(HistoryScreen), findsOneWidget);
      // Pushed, not gone to: the parties list is still under it, which is
      // what the Android system Back button pops back to.
      expect(routerOf(tester).canPop(), isTrue);

      await systemBack(tester);
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('it leads to the statistics, and Back returns to the list', (
      tester,
    ) async {
      await pumpApp(tester);

      await choose(tester, 'menu-stats');

      expect(locationOf(tester), AppRoutes.stats);
      expect(find.byType(StatsScreen), findsOneWidget);
      expect(routerOf(tester).canPop(), isTrue);

      await systemBack(tester);
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('history, then statistics: Back unwinds them one at a time', (
      tester,
    ) async {
      await pumpApp(tester);

      await choose(tester, 'menu-history');
      await choose(tester, 'menu-stats');
      expect(locationOf(tester), AppRoutes.stats);
      // The history and statistics carry the signed-in app bar: who is
      // online and whether the stream is up, beside the menu.
      expect(find.byKey(const Key('connected-players')), findsOneWidget);
      expect(find.byType(ConnectionIndicator), findsOneWidget);

      await systemBack(tester);
      expect(locationOf(tester), AppRoutes.history);
      expect(find.byType(HistoryScreen), findsOneWidget);

      await systemBack(tester);
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('the back button of a pushed screen pops it', (tester) async {
      await pumpApp(tester);

      await choose(tester, 'menu-history');
      await choose(tester, 'menu-stats');
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), AppRoutes.history);

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('a non-admin session has no admin entry', (tester) async {
      await pumpApp(tester);
      await openMenu(tester);

      expect(find.byKey(const Key('menu-history')), findsOneWidget);
      expect(find.byKey(const Key('menu-stats')), findsOneWidget);
      expect(find.byKey(const Key('menu-admin')), findsNothing);
      expect(find.text('Administration'), findsNothing);
    });

    testWidgets(
      'an admin session leads to the admin screen, and Back returns',
      (tester) async {
        await pumpApp(tester, isAdmin: true);
        await openMenu(tester);
        expect(find.text('Administration'), findsOneWidget);

        await tester.tap(find.byKey(const Key('menu-admin')));
        await tester.pumpAndSettle();
        expect(locationOf(tester), AppRoutes.admin);
        expect(find.byType(AdminScreen), findsOneWidget);

        await systemBack(tester);
        expect(locationOf(tester), AppRoutes.parties);
      },
    );
  });

  group('sign out', () {
    testWidgets('it is in the ⋮ menu, not a one-tap icon in the bar', (
      tester,
    ) async {
      await pumpApp(tester);

      expect(find.byKey(const Key('logout')), findsNothing);
      expect(find.byIcon(Icons.logout), findsNothing);
      await openMenu(tester);
      expect(find.byKey(const Key('menu-logout')), findsOneWidget);
    });

    testWidgets('Cancel keeps the session and the screen', (tester) async {
      final storage = storedSession(validToken);
      await pumpApp(tester, storage: storage);

      await choose(tester, 'menu-logout');
      expect(find.byKey(const Key('logout-dialog')), findsOneWidget);
      expect(find.text('Se déconnecter ?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logout-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('logout-dialog')), findsNothing);
      expect(locationOf(tester), AppRoutes.parties);
      expect(storage.values, isNotEmpty);
    });

    testWidgets('confirming signs out to the login screen', (tester) async {
      final storage = storedSession(validToken);
      await pumpApp(tester, storage: storage);

      await choose(tester, 'menu-logout');
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.values, isEmpty);
    });

    testWidgets('the dialog speaks English', (tester) async {
      await pumpApp(tester, locale: const Locale('en'));

      await choose(tester, 'menu-logout');
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('rules', () {
    testWidgets('the ⋮ menu opens them over the parties list', (tester) async {
      await pumpApp(tester);

      await choose(tester, 'menu-rules');

      expect(find.byType(RulesSheet), findsOneWidget);
      expect(find.text('Règles du ZapZap'), findsOneWidget);
      // A sheet over the screen, not a route.
      expect(locationOf(tester), AppRoutes.parties);

      await systemBack(tester);
      expect(find.byType(RulesSheet), findsNothing);
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('the values are those of GAME_RULES.md', (tester) async {
      await pumpApp(tester, locale: const Locale('en'));
      await choose(tester, 'menu-rules');

      String text(String start) => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((data) => data.startsWith(start));

      expect(text('Instead of playing'), contains('5 points or less'));
      expect(text('Above 100 points'), contains('eliminated'));
      expect(text('If another player'), contains('plus 5 for each other'));
      expect(text('Ace 1'), allOf(contains('0 to call'), contains('25')));
    });

    testWidgets('the game screen opens them, the table still behind', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ZapZapApp(
          apiConfig: testConfig,
          locale: const Locale('fr'),
          initialLocation: AppRoutes.gamePath('p1'),
          apiClient: FakeGameBackend(
            state: gameSnapshotJson(
              gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
            ),
          ).client(),
          tokenStorage: storedSession(validToken),
          sseTransport: FakeSseTransport(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GameHand), findsOneWidget);

      await choose(tester, 'menu-rules');

      expect(find.byType(RulesSheet), findsOneWidget);
      expect(find.byType(GameScreen), findsOneWidget);
      // The sheet takes part of the screen: its top sits below the app bar.
      expect(
        tester.getTopLeft(find.byType(RulesSheet)).dy,
        greaterThan(kToolbarHeight),
      );

      await systemBack(tester);
      expect(find.byType(RulesSheet), findsNothing);
      expect(locationOf(tester), AppRoutes.gamePath('p1'));
    });
  });

  group('phone width', () {
    // A 360×740 phone: anything that does not fit throws a layout error,
    // which fails the test.
    const phone = Size(360, 740);

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the bar and its menu fit at a $scale text scale', (
        tester,
      ) async {
        await pumpApp(
          tester,
          backend: FakeLobbyBackend(
            parties: [partySummaryJson(id: 'p1', name: 'Une partie')],
            connected: [connectedPlayerJson('u1', 'Vincent')],
          ),
          size: phone,
          textScale: scale,
        );

        expect(find.byKey(const Key('app-bar-menu')), findsOneWidget);
        expect(find.byKey(const Key('connected-players')), findsOneWidget);

        await openMenu(tester);
        expect(find.text('Historique'), findsOneWidget);
        expect(find.text('Statistiques'), findsOneWidget);
        expect(find.text('Règles'), findsOneWidget);
        expect(find.text('Se déconnecter'), findsOneWidget);
      });

      testWidgets('the rules sheet fits at a $scale text scale', (
        tester,
      ) async {
        await pumpApp(tester, size: phone, textScale: scale);

        await choose(tester, 'menu-rules');
        expect(find.byType(RulesSheet), findsOneWidget);
        // Its end is reached by scrolling, never cut.
        await tester.scrollUntilVisible(
          find.textContaining('Un ZapZap contré'),
          200,
          scrollable: find.descendant(
            of: find.byType(RulesSheet),
            matching: find.byType(Scrollable),
          ),
        );
        expect(find.textContaining('Un ZapZap contré'), findsOneWidget);
      });

      testWidgets('the bar with its back button fits the history and the '
          'statistics at a $scale text scale', (tester) async {
        await pumpApp(
          tester,
          backend: FakeLobbyBackend(
            connected: [connectedPlayerJson('u1', 'Vincent')],
          ),
          size: phone,
          textScale: scale,
        );

        await choose(tester, 'menu-history');
        expect(find.byKey(const Key('back')), findsOneWidget);
        expect(find.byKey(const Key('connected-players')), findsOneWidget);

        await choose(tester, 'menu-stats');
        expect(find.byKey(const Key('back')), findsOneWidget);
        expect(find.byKey(const Key('connected-players')), findsOneWidget);
      });
    }
  });
}
