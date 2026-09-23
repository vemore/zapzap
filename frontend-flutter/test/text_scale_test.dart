import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/widgets/app_logo.dart';

import 'auth_helpers.dart';
import 'game_helpers.dart';
import 'sse_fakes.dart';

/// A storage that never answers: the app stays on the splash screen.
class _PendingTokenStorage extends TokenStorage {
  @override
  Future<String?> readKey(String key) => Completer<String?>().future;

  @override
  Future<void> writeKey(String key, String value) async {}

  @override
  Future<void> deleteKey(String key) async {}
}

// The screens no other phone-width group covers — the way in, the splash,
// the not-found page and the game screen's three message states — at a
// 360×740 phone and the large system fonts Android offers. A RenderFlex that
// does not fit fails the test; a widget clipped by a fixed-size box does not,
// so each test also checks its key controls lie inside the screen.
void main() {
  const phone = Size(360, 740);

  Future<void> pumpApp(
    WidgetTester tester, {
    required double textScale,
    String initialLocation = AppRoutes.home,
    ApiClient? api,
    TokenStorage? storage,
    bool settle = true,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: initialLocation,
        apiClient: api ?? unusedApi(),
        tokenStorage: storage ?? MemoryTokenStorage(),
        sseTransport: FakeSseTransport(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A spinner never settles.
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// [finder] scrolled into view lies wholly on the phone's screen.
  Future<void> expectOnScreen(WidgetTester tester, Finder finder) async {
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pump();
    final rect = tester.getRect(finder);
    final screen = Offset.zero & phone;
    expect(
      screen.intersect(rect) == rect,
      isTrue,
      reason: '$rect is not inside $screen',
    );
  }

  for (final scale in [1.5, 2.0]) {
    group('a 360×740 phone at a text scale of $scale', () {
      testWidgets('the home screen fits', (tester) async {
        await pumpApp(tester, textScale: scale);
        await expectOnScreen(tester, find.byType(AppLogo));
        await expectOnScreen(tester, find.byType(FilledButton));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the splash screen fits', (tester) async {
        await pumpApp(
          tester,
          textScale: scale,
          storage: _PendingTokenStorage(),
          settle: false,
        );
        await expectOnScreen(tester, find.byType(AppLogo));
        await expectOnScreen(tester, find.byType(CircularProgressIndicator));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the login screen fits', (tester) async {
        await pumpApp(
          tester,
          textScale: scale,
          initialLocation: AppRoutes.login,
        );
        for (final key in [
          'login-username',
          'login-password',
          'login-submit',
        ]) {
          await expectOnScreen(tester, find.byKey(Key(key)));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the register screen fits', (tester) async {
        await pumpApp(
          tester,
          textScale: scale,
          initialLocation: AppRoutes.register,
        );
        for (final key in [
          'register-username',
          'register-password',
          'register-submit',
        ]) {
          await expectOnScreen(tester, find.byKey(Key(key)));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('the not-found screen fits', (tester) async {
        await pumpApp(tester, textScale: scale, initialLocation: '/nowhere');
        await expectOnScreen(tester, find.byType(FilledButton));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the game screen loading fits', (tester) async {
        final answer = Completer<void>();
        final backend = FakeGameBackend(state: gameSnapshotJson())
          ..onState = (_) => answer.future;
        await pumpApp(
          tester,
          textScale: scale,
          initialLocation: AppRoutes.gamePath('p1'),
          api: backend.client(),
          storage: storedSession(validToken),
          settle: false,
        );
        await expectOnScreen(tester, find.byType(CircularProgressIndicator));
        await expectOnScreen(tester, find.byKey(const Key('game-back')));
        expect(tester.takeException(), isNull);
        // Let the request end, or its timeout outlives the test.
        answer.complete();
        await tester.pumpAndSettle();
      });

      testWidgets('the game screen error fits', (tester) async {
        await pumpApp(
          tester,
          textScale: scale,
          initialLocation: AppRoutes.gamePath('p1'),
          api: FakeGameBackend().client(),
          storage: storedSession(validToken),
        );
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        await expectOnScreen(tester, find.byKey(const Key('retry-game')));
        await expectOnScreen(tester, find.byKey(const Key('game-back-body')));
        expect(tester.takeException(), isNull);
      });

      testWidgets('the game screen "not started" message fits', (tester) async {
        await pumpApp(
          tester,
          textScale: scale,
          initialLocation: AppRoutes.gamePath('p1'),
          api: FakeGameBackend(state: gameSnapshotJson(gameState: null))
              .client(),
          storage: storedSession(validToken),
        );
        expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
        await expectOnScreen(tester, find.byKey(const Key('retry-game')));
        await expectOnScreen(tester, find.byKey(const Key('game-back-body')));
        expect(tester.takeException(), isNull);
      });
    });
  }
}
