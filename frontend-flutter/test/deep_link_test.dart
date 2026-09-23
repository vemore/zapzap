import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/game_details_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'history_helpers.dart';
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

  test('main uses path URLs on the web, before runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final strategy = main.indexOf('usePathUrlStrategy();');
    expect(strategy, isNonNegative);
    expect(strategy, lessThan(main.indexOf('runApp(')));
  });
}
