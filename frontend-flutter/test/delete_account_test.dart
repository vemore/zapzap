import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations_en.dart';
import 'package:zapzap/l10n/app_localizations_fr.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/services/google_sign_in_service.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/utils/player_name.dart';
import 'package:zapzap/widgets/google_sign_in_section.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'google_fakes.dart';
import 'history_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// A stored session; [google] marks a Google account (no password).
  MemoryTokenStorage session({bool google = false}) => MemoryTokenStorage({
    TokenStorage.tokenKey: validToken,
    TokenStorage.userKey: jsonEncode({
      'id': 'u1',
      'username': 'Vincent',
      'isAdmin': false,
      'isGoogleUser': google,
    }),
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeLobbyBackend backend,
    required MemoryTokenStorage storage,
    FakeGoogleSignIn? google,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.parties,
        apiClient: backend.client(),
        tokenStorage: storage,
        sseTransport: FakeSseTransport(),
        googleSignIn: google,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('app-bar-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer mon compte'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-delete-account')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete-account-dialog')), findsOneWidget);
    expect(find.text('Supprimer ton compte ?'), findsOneWidget);
  }

  List<String> deleteCalls(FakeLobbyBackend backend) => [
    for (final request in backend.requests)
      if (request.method == 'DELETE') request.url.path,
  ];

  group('delete my account', () {
    testWidgets('the menu entry, the confirmation with the password, the '
        'call, then the login screen with the session erased', (tester) async {
      final backend = FakeLobbyBackend();
      final storage = session();
      await pumpApp(tester, backend: backend, storage: storage);

      await openDialog(tester);
      // Nothing is sent without the password.
      final confirm = find.byKey(const Key('delete-account-confirm'));
      expect(tester.widget<TextButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('delete-account-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(deleteCalls(backend), ['/api/auth/me']);
      expect(backend.bodyOf('DELETE', '/api/auth/me'), {'password': 'secret1'});
      final request = backend.requests.lastWhere((r) => r.method == 'DELETE');
      expect(request.headers['Authorization'], 'Bearer $validToken');
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const Key('delete-account-dialog')), findsNothing);
      expect(storage.values, isEmpty);
    });

    testWidgets('cancel sends nothing and stays signed in', (tester) async {
      final backend = FakeLobbyBackend();
      final storage = session();
      await pumpApp(tester, backend: backend, storage: storage);

      await openDialog(tester);
      await tester.tap(find.byKey(const Key('delete-account-cancel')));
      await tester.pumpAndSettle();

      expect(deleteCalls(backend), isEmpty);
      expect(find.byKey(const Key('delete-account-dialog')), findsNothing);
      expect(find.byType(LoginScreen), findsNothing);
      expect(storage.values, isNotEmpty);
    });

    final refusals = {
      (403, 'INVALID_PASSWORD'): 'Mot de passe incorrect.',
      (409, 'ACTIVE_PARTY'): "Quitte ou termine d'abord tes parties en cours.",
      (409, 'LAST_ADMIN'):
          'Tu es le seul administrateur : ton compte ne peut pas être '
          'supprimé.',
    };
    for (final MapEntry(key: (status, code), value: text) in refusals.entries) {
      testWidgets('$status $code: the dialog says so, still signed in', (
        tester,
      ) async {
        final backend = FakeLobbyBackend();
        backend.failures['DELETE /api/auth/me'] = (
          status: status,
          body: {'error': 'refused', 'code': code},
        );
        final storage = session();
        await pumpApp(tester, backend: backend, storage: storage);

        await openDialog(tester);
        await tester.enterText(
          find.byKey(const Key('delete-account-password')),
          'wrong',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('delete-account-confirm')));
        await tester.pumpAndSettle();

        expect(deleteCalls(backend), ['/api/auth/me']);
        expect(find.byKey(const Key('delete-account-error')), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.byType(LoginScreen), findsNothing);
        expect(storage.values, isNotEmpty);
      });
    }

    testWidgets('a Google account confirms with a fresh Google token', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      final storage = session(google: true);
      final google = FakeGoogleSignIn()..nextToken = 'fresh-google-token';
      await pumpApp(tester, backend: backend, storage: storage, google: google);

      await openDialog(tester);
      expect(find.byKey(const Key('delete-account-password')), findsNothing);
      await tester.tap(find.byKey(const Key('delete-account-google')));
      await tester.pumpAndSettle();

      expect(google.signIns, 1);
      expect(backend.bodyOf('DELETE', '/api/auth/me'), {
        'credential': 'fresh-google-token',
      });
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.values, isEmpty);
    });

    testWidgets('Google not ready: after the login screen\'s timeout, a '
        'notice instead of the button', (tester) async {
      final backend = FakeLobbyBackend();
      final google = FakeGoogleSignIn()
        ..webButton = (() => const Text('Getting ready'))
        ..onReady = () => Completer<void>().future;
      await pumpApp(
        tester,
        backend: backend,
        storage: session(google: true),
        google: google,
      );

      await openDialog(tester);
      expect(find.text('Getting ready'), findsOneWidget);
      await tester.pump(GoogleSignInSection.readyTimeout);
      await tester.pumpAndSettle();

      expect(find.text('Getting ready'), findsNothing);
      expect(find.byKey(const Key('delete-account-google')), findsNothing);
      expect(
        find.byKey(const Key('delete-account-google-unavailable')),
        findsOneWidget,
      );
      expect(deleteCalls(backend), isEmpty);
    });

    testWidgets('Google failed to initialise: the notice at once', (
      tester,
    ) async {
      final google = FakeGoogleSignIn()
        ..onReady = () async => throw const GoogleSignInFailure('init failed');
      await pumpApp(
        tester,
        backend: FakeLobbyBackend(),
        storage: session(google: true),
        google: google,
      );

      await openDialog(tester);
      expect(find.byKey(const Key('delete-account-google')), findsNothing);
      expect(
        find.text(
          "Google est injoignable d'ici : il ne peut pas confirmer la "
          'suppression. Réessaie plus tard, ou demande-la par e-mail (voir '
          'la politique de confidentialité).',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refused Google token stays in the dialog', (tester) async {
      final backend = FakeLobbyBackend();
      backend.failures['DELETE /api/auth/me'] = (
        status: 403,
        body: {'error': 'refused', 'code': 'GOOGLE_AUTH_FAILED'},
      );
      final storage = session(google: true);
      await pumpApp(
        tester,
        backend: backend,
        storage: storage,
        google: FakeGoogleSignIn(),
      );

      await openDialog(tester);
      await tester.tap(find.byKey(const Key('delete-account-google')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "La confirmation Google a échoué, ou ce n'est pas le bon compte "
          'Google.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginScreen), findsNothing);
      expect(storage.values, isNotEmpty);
    });
  });

  group('a deleted player in the history', () {
    test('is named by the l10n, anyone else by their username', () {
      final fr = AppLocalizationsFr();
      final en = AppLocalizationsEn();
      expect(isDeletedUser('deleted-1b2c'), isTrue);
      expect(isDeletedUser('a8891da0-2bf8'), isFalse);
      expect(isDeletedUser(null), isFalse);
      expect(playerName(fr, 'deleted-1b2c', 'deleted-1b2c'), 'Joueur supprimé');
      expect(playerName(en, 'deleted-1b2c', 'deleted-1b2c'), 'Deleted player');
      expect(playerName(fr, 'u1', 'Vincent'), 'Vincent');
      // A username that merely looks like one is someone's name.
      expect(playerName(fr, 'u1', 'deleted-1b2c'), 'deleted-1b2c');
    });

    testWidgets('the game details show « Joueur supprimé », never the '
        'stand-in username', (tester) async {
      const partyId = 'da33c689-6f43-49d4-ba89-953f105e7960';
      const winnerId = '74a0d812-54b3-4b99-95a3-ca56596fe8bf';
      const deletedId = 'deleted-0f5e1c2a-7d3b-4e8f-9a6b-1c2d3e4f5a6b';
      final details = fixtureText('history_details')
          .replaceAll(winnerId, deletedId)
          .replaceAll('MediumBot1', deletedId);
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.gameDetails(partyId),
        api: routedApi({'/api/history/$partyId': details}),
      );

      expect(find.textContaining(deletedId), findsNothing);
      // The winner card, the standings and the rounds table.
      expect(find.text('Joueur supprimé'), findsNWidgets(3));
      expect(find.byKey(const Key('standings-$deletedId')), findsOneWidget);
      expect(find.text('EasyBot1'), findsWidgets);
    });

    testWidgets('the history list names the deleted winner', (tester) async {
      final list = fixture('history_list');
      final games = (list['games'] as List).cast<Map<String, dynamic>>();
      final deletedId = 'deleted-${games.first['winnerUserId']}';
      games.first['winnerUserId'] = deletedId;
      games.first['winnerUsername'] = deletedId;
      await pumpScreen(
        tester,
        initialLocation: AppRoutes.history,
        api: routedApi({
          '/api/history': jsonEncode(list),
          '/api/history/public': fixtureText('history_public'),
        }),
      );

      expect(find.textContaining(deletedId), findsNothing);
      expect(find.textContaining('Joueur supprimé'), findsWidgets);
    });
  });
}
