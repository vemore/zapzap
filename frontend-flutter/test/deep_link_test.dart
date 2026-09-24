import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/game_details_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/screens/party_lobby_screen.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'history_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

/// A cold load of a path URL: the browser's path, less the `/app/` base href,
/// is the platform's initial route, which go_router opens instead of its
/// `initialLocation` — the app is started on home here, as `main` starts it.
void main() {
  const partyId = 'da33c689-6f43-49d4-ba89-953f105e7960';

  void openedAt(WidgetTester tester, String route) {
    tester.platformDispatcher.defaultRouteNameTestValue = route;
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
  }

  Future<void> coldLoad(WidgetTester tester, String route) async {
    openedAt(tester, route);
    await pumpScreen(
      tester,
      initialLocation: AppRoutes.home,
      api: routedApi({
        '/api/party': '{"parties":[]}',
        '/api/history/$partyId': fixtureText('history_details'),
      }),
    );
  }

  testWidgets('/history/<id> opens that finished game', (tester) async {
    await coldLoad(tester, '/history/$partyId');

    final details = tester.widget<GameDetailsScreen>(
      find.byType(GameDetailsScreen),
    );
    expect(details.partyId, partyId);
  });

  testWidgets('/parties opens the parties list', (tester) async {
    await coldLoad(tester, '/parties');

    expect(find.byType(PartiesScreen), findsOneWidget);
  });

  testWidgets('signed out, /history/<id> is the login', (tester) async {
    openedAt(tester, '/history/$partyId');
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        apiClient: routedApi({}),
        tokenStorage: MemoryTokenStorage(),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(GameDetailsScreen), findsNothing);
  });

  testWidgets('/parties/<id> opens that lobby', (tester) async {
    openedAt(tester, '/parties/$partyId');
    await pumpScreen(
      tester,
      initialLocation: AppRoutes.home,
      api: FakeLobbyBackend(details: partyDetailsJson(id: partyId)).client(),
    );

    final lobby = tester.widget<PartyLobbyScreen>(
      find.byType(PartyLobbyScreen),
    );
    expect(lobby.partyId, partyId);
  });

  /// The paths reported to the engine (the browser's address bar), in order;
  /// one that replaces the current history entry rather than adding one
  /// ends in ` (replace)`.
  List<String> reportedPaths(WidgetTester tester) {
    final paths = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.navigation,
      (call) async {
        if (call.method == 'routeInformationUpdated') {
          final arguments = call.arguments as Map;
          final path = Uri.parse(arguments['uri'] as String).path;
          paths.add(arguments['replace'] == true ? '$path (replace)' : path);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.navigation,
        null,
      ),
    );
    return paths;
  }

  FakeLobbyBackend backend() => FakeLobbyBackend(
    parties: [partySummaryJson(id: 'p1', name: 'Open party')],
    details: partyDetailsJson(id: 'p1', name: 'Open party'),
    createdPartyId: 'p1',
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  // A pushed screen reports its own path to the browser, so the address bar,
  // a reload and a shared link follow it — go_router's default keeps the path
  // of the screen below (`GoRouter.optionURLReflectsImperativeAPIs`).
  group('the URL of a pushed screen', () {
    testWidgets('the create form and a lobby show their own path, and '
        'Back shows the list again', (tester) async {
      final paths = reportedPaths(tester);
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.parties,
        api: backend().client(),
      );
      expect(paths.last, AppRoutes.parties);

      await tapKey(tester, 'create-party');
      expect(paths.last, AppRoutes.createParty);

      await tapKey(tester, 'back-to-parties');
      expect(paths.last, '${AppRoutes.parties} (replace)');

      await tapKey(tester, 'join-p1');
      expect(paths.last, AppRoutes.partyPath('p1'));

      // Android's system Back, as `test/party_screens_test.dart` drives it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(paths.last, AppRoutes.parties);
    });

    // The browser's Back then skips the form, as Android's Back does.
    testWidgets('the lobby a new party opens replaces the form in the '
        "browser's history", (tester) async {
      final paths = reportedPaths(tester);
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.parties,
        api: backend().client(),
      );

      await tapKey(tester, 'create-party');
      await tester.enterText(find.byKey(const Key('party-name')), 'Soirée');
      await tester.pump();
      await tapKey(tester, 'create-submit');

      expect(find.byType(PartyLobbyScreen), findsOneWidget);
      expect(paths.last, '${AppRoutes.partyPath('p1')} (replace)');
    });
  });

  // go_router reports a pop, like a `go`, as a new browser entry: the
  // browser's Back would then reopen the screen just left. A screen's own
  // back button (`popOrGo`) replaces that entry instead.
  group("a back button replaces the screen it leaves in the browser's "
      'history', () {
    Future<void> openFromMenu(WidgetTester tester, String item) async {
      await tapKey(tester, 'app-bar-menu');
      await tapKey(tester, item);
    }

    for (final (item, route) in [
      ('menu-history', AppRoutes.history),
      ('menu-stats', AppRoutes.stats),
    ]) {
      testWidgets('list → $route → back', (tester) async {
        final paths = reportedPaths(tester);
        await pumpScreen(
          tester,
          initialLocation: AppRoutes.parties,
          api: backend().client(),
        );

        await openFromMenu(tester, item);
        expect(paths.last, route);

        await tapKey(tester, 'back');
        expect(find.byType(PartiesScreen), findsOneWidget);
        expect(paths.last, '${AppRoutes.parties} (replace)');
      });
    }

    testWidgets('list → history → statistics → back → back', (tester) async {
      final paths = reportedPaths(tester);
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.parties,
        api: backend().client(),
      );
      await openFromMenu(tester, 'menu-history');
      await openFromMenu(tester, 'menu-stats');

      await tapKey(tester, 'back');
      expect(paths.last, '${AppRoutes.history} (replace)');
      await tapKey(tester, 'back');
      expect(paths.last, '${AppRoutes.parties} (replace)');
    });

    testWidgets('list → lobby → back', (tester) async {
      final paths = reportedPaths(tester);
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.parties,
        api: backend().client(),
      );
      await tapKey(tester, 'join-p1');
      expect(find.byType(PartyLobbyScreen), findsOneWidget);

      await tapKey(tester, 'back-to-parties');
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(paths.last, '${AppRoutes.parties} (replace)');
    });

    testWidgets('the details opened by a link fall back to the history', (
      tester,
    ) async {
      final paths = reportedPaths(tester);
      openedAt(tester, '/history/$partyId');
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.home,
        api: routedApi({
          '/api/history/$partyId': fixtureText('history_details'),
          '/api/history': '{"games":[]}',
        }),
      );
      expect(find.byType(GameDetailsScreen), findsOneWidget);

      await tapKey(tester, 'back');
      expect(find.byType(GameDetailsScreen), findsNothing);
      expect(paths.last, '${AppRoutes.history} (replace)');
    });
  });

  test('main uses path URLs on the web, before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final strategy = main.indexOf('usePathUrlStrategy();');
    expect(strategy, isNonNegative);
    expect(strategy, lessThan(main.indexOf('runApp(')));
  });
}
