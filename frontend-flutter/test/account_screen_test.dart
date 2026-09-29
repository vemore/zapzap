import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/account_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'google_fakes.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// A stored session of Vincent; [google] marks a Google account, which has
  /// a password when [hasPassword] says so (absent: none).
  MemoryTokenStorage session({bool google = false, bool? hasPassword}) =>
      MemoryTokenStorage({
        TokenStorage.tokenKey: validToken,
        TokenStorage.userKey: jsonEncode({
          'id': 'u1',
          'username': 'Vincent',
          'isAdmin': false,
          'isGoogleUser': google,
          'hasPassword': ?hasPassword,
          if (google) 'email': 'vincent@example.com',
        }),
      });

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeLobbyBackend backend,
    required MemoryTokenStorage storage,
    String initialLocation = AppRoutes.parties,
    Locale locale = const Locale('fr'),
    FakeGoogleSignIn? google,
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
        locale: locale,
        initialLocation: initialLocation,
        apiClient: backend.client(),
        tokenStorage: storage,
        sseTransport: FakeSseTransport(),
        googleSignIn: google,
      ),
    );
    await tester.pumpAndSettle();
  }

  String locationOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path;

  /// ⋮ → « Mon compte ».
  Future<void> openAccount(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('app-bar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu-account')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
  }

  Map<String, dynamic> storedUser(MemoryTokenStorage storage) =>
      (jsonDecode(storage.values[TokenStorage.userKey]!) as Map)
          .cast<String, dynamic>();

  FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const Key('account-username-save')),
  );

  group('the menu', () {
    testWidgets('« Mon compte » replaces « Supprimer mon compte », and leads '
        'to the account page; Back returns', (tester) async {
      await pumpApp(tester, backend: FakeLobbyBackend(), storage: session());

      await tester.tap(find.byKey(const Key('app-bar-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-delete-account')), findsNothing);
      expect(find.text('Supprimer mon compte'), findsNothing);
      expect(find.text('Mon compte'), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-account')));
      await tester.pumpAndSettle();

      expect(locationOf(tester), AppRoutes.account);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('account-current-username')))
            .data,
        'Vincent',
      );
      expect(find.text('Connexion par mot de passe'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('it speaks English', (tester) async {
      await pumpApp(
        tester,
        backend: FakeLobbyBackend(),
        storage: session(),
        locale: const Locale('en'),
      );

      await tester.tap(find.byKey(const Key('app-bar-menu')));
      await tester.pumpAndSettle();
      expect(find.text('My account'), findsOneWidget);
      expect(find.text('Delete my account'), findsNothing);
      await tester.tap(find.byKey(const Key('menu-account')));
      await tester.pumpAndSettle();
      expect(find.text('My account'), findsOneWidget);
      expect(find.text('Delete my account'), findsOneWidget);
    });

    testWidgets('/account is a deep link; its back button leads to the '
        'parties', (tester) async {
      await pumpApp(
        tester,
        backend: FakeLobbyBackend(),
        storage: session(),
        initialLocation: AppRoutes.account,
      );
      expect(find.byType(AccountScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
    });

    testWidgets('signed out, /account leads to the login screen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        backend: FakeLobbyBackend(),
        storage: MemoryTokenStorage(),
        initialLocation: AppRoutes.account,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('rename', () {
    testWidgets('the new name is sent, and the session takes the new token '
        'and name', (tester) async {
      final backend = FakeLobbyBackend();
      final storage = session();
      await pumpApp(tester, backend: backend, storage: storage);
      await openAccount(tester);

      // Nothing to save until the name changes.
      expect(saveButton(tester).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('account-username')),
        '  Vince_2 ',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('account-username-save')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('PATCH', '/api/auth/me'), {'username': 'Vince_2'});
      final request = backend.requests.lastWhere((r) => r.method == 'PATCH');
      expect(request.headers['Authorization'], 'Bearer $validToken');
      expect(find.text('Pseudo modifié'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('account-current-username')))
            .data,
        'Vince_2',
      );
      expect(saveButton(tester).onPressed, isNull);
      expect(storage.values[TokenStorage.tokenKey], backend.renamedToken);
      expect(storedUser(storage)['username'], 'Vince_2');
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('a name the sign-up form refuses is not sent', (tester) async {
      final backend = FakeLobbyBackend();
      await pumpApp(tester, backend: backend, storage: session());
      await openAccount(tester);

      await tester.enterText(find.byKey(const Key('account-username')), 'ab');
      await tester.pump();
      expect(
        find.text('Le pseudo doit contenir au moins 3 caractères'),
        findsOneWidget,
      );
      expect(saveButton(tester).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('account-username')),
        'Vin cent',
      );
      await tester.pump();
      expect(saveButton(tester).onPressed, isNull);
      expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    testWidgets('a taken name: the page says so, the session unchanged', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      backend.failures['PATCH /api/auth/me'] = (
        status: 409,
        body: {'error': 'Username already exists', 'code': 'USERNAME_EXISTS'},
      );
      final storage = session();
      await pumpApp(tester, backend: backend, storage: storage);
      await openAccount(tester);

      await tester.enterText(
        find.byKey(const Key('account-username')),
        'Taken',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('account-username-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('account-username-error')), findsOneWidget);
      expect(find.text('Ce pseudo est déjà pris'), findsOneWidget);
      expect(storage.values[TokenStorage.tokenKey], validToken);
      expect(storedUser(storage)['username'], 'Vincent');
    });
  });

  group('password', () {
    testWidgets('changed with the current one', (tester) async {
      final backend = FakeLobbyBackend();
      await pumpApp(tester, backend: backend, storage: session());
      await openAccount(tester);

      await tester.tap(find.byKey(const Key('account-password')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-password-dialog')), findsOneWidget);
      expect(find.text('Changer le mot de passe'), findsWidgets);
      final confirm = find.byKey(const Key('change-password-confirm'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('change-password-current')),
        'secret1',
      );
      // The sign-up form's rule: six characters at least.
      await tester.enterText(
        find.byKey(const Key('change-password-new')),
        'abc',
      );
      await tester.pump();
      expect(
        find.text('Le mot de passe doit contenir au moins 6 caractères'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('change-password-new')),
        'brandnew',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(backend.bodyOf('PUT', '/api/auth/me/password'), {
        'newPassword': 'brandnew',
        'currentPassword': 'secret1',
      });
      expect(find.byKey(const Key('change-password-dialog')), findsNothing);
      expect(find.text('Mot de passe enregistré'), findsOneWidget);
    });

    testWidgets('a wrong current password stays in the dialog, signed in', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      backend.failures['PUT /api/auth/me/password'] = (
        status: 403,
        body: {'error': 'Invalid password', 'code': 'INVALID_PASSWORD'},
      );
      final storage = session();
      await pumpApp(tester, backend: backend, storage: storage);
      await openAccount(tester);

      await tester.tap(find.byKey(const Key('account-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('change-password-current')),
        'wrong',
      );
      await tester.enterText(
        find.byKey(const Key('change-password-new')),
        'brandnew',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('change-password-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('change-password-error')), findsOneWidget);
      expect(find.text('Mot de passe incorrect.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(storage.values, isNotEmpty);
    });

    testWidgets('a Google account without one sets a first password with a '
        'fresh Google token', (tester) async {
      final backend = FakeLobbyBackend();
      final storage = session(google: true);
      final google = FakeGoogleSignIn()..nextToken = 'fresh-google-token';
      await pumpApp(tester, backend: backend, storage: storage, google: google);
      await openAccount(tester);

      expect(find.textContaining('Connexion avec Google'), findsOneWidget);
      expect(find.textContaining('vincent@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-password')));
      await tester.pumpAndSettle();
      expect(find.text('Choisir un mot de passe'), findsWidgets);
      expect(find.byKey(const Key('change-password-current')), findsNothing);
      expect(find.byKey(const Key('change-password-confirm')), findsNothing);
      // Google confirms only once the new password is acceptable.
      final googleButton = find.byKey(const Key('change-password-google'));
      expect(tester.widget<OutlinedButton>(googleButton).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('change-password-new')),
        'firstone',
      );
      await tester.pump();
      await tester.tap(googleButton);
      await tester.pumpAndSettle();

      expect(google.signIns, 1);
      expect(backend.bodyOf('PUT', '/api/auth/me/password'), {
        'newPassword': 'firstone',
        'credential': 'fresh-google-token',
      });
      expect(find.text('Mot de passe enregistré'), findsOneWidget);
      // The account has a password now: the page and the stored session say
      // so.
      expect(
        find.textContaining('Connexion avec Google ou par mot de passe'),
        findsOneWidget,
      );
      expect(find.text('Changer le mot de passe'), findsOneWidget);
      expect(storedUser(storage)['hasPassword'], isTrue);
    });

    testWidgets('a Google account that has one changes it with it', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      await pumpApp(
        tester,
        backend: backend,
        storage: session(google: true, hasPassword: true),
        google: FakeGoogleSignIn(),
      );
      await openAccount(tester);

      await tester.tap(find.byKey(const Key('account-password')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-password-current')), findsOneWidget);
      expect(find.byKey(const Key('change-password-google')), findsNothing);
    });
  });

  group('delete', () {
    testWidgets('the page opens the deletion dialog', (tester) async {
      await pumpApp(tester, backend: FakeLobbyBackend(), storage: session());
      await openAccount(tester);

      await tester.ensureVisible(find.byKey(const Key('account-delete')));
      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-account-dialog')), findsOneWidget);
    });
  });

  group('phone width', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the page and the password dialog fit 360×740 at a $scale '
          'text scale', (tester) async {
        await pumpApp(
          tester,
          backend: FakeLobbyBackend(),
          storage: session(google: true),
          google: FakeGoogleSignIn(),
          initialLocation: AppRoutes.account,
          size: const Size(360, 740),
          textScale: scale,
        );
        expect(find.byType(AccountScreen), findsOneWidget);
        // The page's own list, not the username field's.
        final page = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('account-delete')),
          200,
          scrollable: page,
        );

        await tester.ensureVisible(find.byKey(const Key('account-password')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('account-password')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('change-password-dialog')), findsOneWidget);
      });
    }
  });
}
