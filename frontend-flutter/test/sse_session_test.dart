import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/providers/auth_provider.dart';
import 'package:zapzap/providers/sse_provider.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'sse_fakes.dart';

void main() {
  testWidgets('the real-time channel follows the session', (tester) async {
    final transport = FakeSseTransport();
    final newToken = jwtExpiringIn(const Duration(hours: 12), userId: 'u2');
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.login,
        apiClient: fakeApi(
          (_) async =>
              http.Response(authFixtureWithJwt('auth_login', newToken), 200),
        ),
        tokenStorage: storedSession(validToken),
        sseTransport: transport,
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    final auth = context.read<AuthProvider>();
    final sse = context.read<SseProvider>();

    // A restored session connects with its token.
    expect(transport.connections, hasLength(1));
    expect(transport.last.uri.queryParameters['token'], validToken);
    transport.last.open();
    expect(sse.connected, isTrue);

    // Logout closes it, and nothing reconnects.
    await auth.logout();
    await tester.pump();
    expect(transport.last.cancelled, isTrue);
    expect(sse.connected, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(transport.connections, hasLength(1));

    // Signing in again connects with the new token.
    await auth.login('Vincent', 'demo123');
    await tester.pump();
    expect(transport.connections, hasLength(2));
    expect(transport.last.uri.queryParameters['token'], newToken);

    await tester.pumpWidget(const SizedBox());
    expect(transport.last.cancelled, isTrue, reason: 'closed with the tree');
  });

  testWidgets('signed out, nothing connects', (tester) async {
    final transport = FakeSseTransport();
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        tokenStorage: MemoryTokenStorage(),
        sseTransport: transport,
      ),
    );
    await tester.pumpAndSettle();
    expect(transport.connections, isEmpty);
  });
}
