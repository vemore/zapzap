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
import 'wide_screen_helpers.dart';

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
// 360×740 phone and the large system fonts Android offers, then in the
// windows of the `wide screen` groups. A RenderFlex that
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
    Size size = phone,
  }) async {
    tester.view.physicalSize = size;
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

  /// [finder] scrolled into view lies wholly on the screen.
  Future<void> expectOnScreen(WidgetTester tester, Finder finder) async {
    expect(finder, findsOneWidget);
    await tester.ensureVisible(finder);
    await tester.pump();
    final rect = tester.getRect(finder);
    final screen =
        Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
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

  group('wide screen', () {
    for (final MapEntry(key: name, value: size) in wideScreens.entries) {
      for (final scale in wideTextScales) {
        final at = '$name, text x$scale';

        testWidgets('the home screen fits at $at', (tester) async {
          await pumpApp(tester, textScale: scale, size: size);
          await expectOnScreen(tester, find.byType(AppLogo));
          await expectOnScreen(tester, find.byType(FilledButton));
          expect(tester.takeException(), isNull);
        });

        testWidgets('the splash screen fits at $at', (tester) async {
          await pumpApp(
            tester,
            textScale: scale,
            storage: _PendingTokenStorage(),
            settle: false,
            size: size,
          );
          await expectOnScreen(tester, find.byType(AppLogo));
          await expectOnScreen(tester, find.byType(CircularProgressIndicator));
          expect(tester.takeException(), isNull);
        });

        for (final screen in ['login', 'register']) {
          testWidgets('the $screen screen fits at $at, its card no wider '
              'than the content column', (tester) async {
            await pumpApp(
              tester,
              textScale: scale,
              initialLocation: '/$screen',
              size: size,
            );
            for (final key in ['username', 'password', 'submit']) {
              await expectOnScreen(tester, find.byKey(Key('$screen-$key')));
              expectInContentColumn(
                tester,
                find.byKey(Key('$screen-$key')),
                windowWidth: size.width,
              );
            }
            expect(tester.takeException(), isNull);
          });
        }

        testWidgets('the not-found screen fits at $at', (tester) async {
          await pumpApp(
            tester,
            textScale: scale,
            initialLocation: '/nowhere',
            size: size,
          );
          await expectOnScreen(tester, find.byType(FilledButton));
          expect(tester.takeException(), isNull);
        });

        testWidgets('the game screen error fits at $at', (tester) async {
          await pumpApp(
            tester,
            textScale: scale,
            initialLocation: AppRoutes.gamePath('p1'),
            api: FakeGameBackend().client(),
            storage: storedSession(validToken),
            size: size,
          );
          await expectOnScreen(tester, find.byKey(const Key('retry-game')));
          await expectOnScreen(tester, find.byKey(const Key('game-back-body')));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
