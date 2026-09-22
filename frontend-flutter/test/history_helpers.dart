import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/app.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'sse_fakes.dart';

/// A signed-in session for [userId] — the id the leaderboard compares against
/// ([AuthProvider.user] holds it, not the JWT).
MemoryTokenStorage sessionFor(String userId, {String username = 'Vincent'}) =>
    MemoryTokenStorage({
      TokenStorage.tokenKey: jwtExpiringIn(
        const Duration(hours: 24),
        userId: userId,
      ),
      TokenStorage.userKey: jsonEncode({
        'id': userId,
        'username': username,
        'isAdmin': false,
      }),
    });

/// An [ApiClient] answering each `/api/...` path with the body [bodies] holds
/// for it, and 404 for anything else — so a screen reading a path nobody
/// declared fails the way the backend would.
ApiClient routedApi(
  Map<String, String> bodies, {
  List<http.Request>? requests,
  Map<String, int> statuses = const {},
}) => fakeApi((request) async {
  final path = request.url.path;
  final body = bodies[path];
  if (body == null) {
    return http.Response(
      jsonEncode({'error': 'Party not found'}),
      404,
      headers: _jsonHeaders,
    );
  }
  return http.Response(body, statuses[path] ?? 200, headers: _jsonHeaders);
}, requests: requests);

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

/// The app on [initialLocation], signed in as [userId], over [api].
///
/// The window is made tall so the long statistics and history screens build
/// every section: a `ListView` only builds what fits its viewport.
Future<void> pumpScreen(
  WidgetTester tester, {
  required String initialLocation,
  required ApiClient api,
  String userId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e',
  Size size = const Size(1100, 3000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ZapZapApp(
      apiConfig: testConfig,
      locale: const Locale('fr'),
      initialLocation: initialLocation,
      apiClient: api,
      tokenStorage: sessionFor(userId),
      sseTransport: FakeSseTransport(),
    ),
  );
  await tester.pumpAndSettle();
}
