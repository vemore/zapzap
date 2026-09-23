import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/history_screen.dart';
import 'package:zapzap/screens/stats_screen.dart';
import 'package:zapzap/widgets/connection_indicator.dart';

import 'auth_helpers.dart';
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
        locale: const Locale('fr'),
        initialLocation: AppRoutes.parties,
        apiClient: (backend ?? FakeLobbyBackend()).client(),
        tokenStorage: storedSession(validToken, isAdmin: isAdmin),
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

    testWidgets('nor does an admin one, while no admin screen exists', (
      tester,
    ) async {
      // `/admin` has the router guard of #29 but no screen: an entry would
      // land on the not-found screen. This fails the day one is added, which
      // is when the entry belongs in the menu.
      await pumpApp(tester, isAdmin: true);
      await openMenu(tester);

      expect(find.byKey(const Key('menu-admin')), findsNothing);
    });
  });

  group('phone width', () {
    // A 360×740 phone: anything that does not fit throws a layout error,
    // which fails the test.
    const phone = Size(360, 740);

    for (final scale in [1.0, 1.5]) {
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
        expect(find.byKey(const Key('logout')), findsOneWidget);
        expect(find.byKey(const Key('connected-players')), findsOneWidget);

        await openMenu(tester);
        expect(find.text('Historique'), findsOneWidget);
        expect(find.text('Statistiques'), findsOneWidget);
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
