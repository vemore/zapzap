import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/app.dart';
import 'package:zapzap/providers/auth_provider.dart';
import 'package:zapzap/repositories/auth_repository.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'sse_fakes.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    String initialLocation = AppRoutes.login,
    ApiClient? api,
    TokenStorage? storage,
    Locale locale = const Locale('fr'),
  }) async {
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: locale,
        initialLocation: initialLocation,
        apiClient: api ?? unusedApi(),
        tokenStorage: storage ?? MemoryTokenStorage(),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool submitEnabled(WidgetTester tester, String key) =>
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(Key(key)),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed !=
      null;

  group('register', () {
    testWidgets('invalid username and password show the messages and '
        'disable submit', (tester) async {
      await pumpApp(tester, initialLocation: AppRoutes.register);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(submitEnabled(tester, 'register-submit'), isFalse);

      await tester.enterText(find.byKey(const Key('register-username')), 'ab');
      await tester.enterText(find.byKey(const Key('register-password')), '123');
      await tester.pump();
      expect(
        find.text('Le pseudo doit contenir au moins 3 caractères'),
        findsOneWidget,
      );
      expect(
        find.text('Le mot de passe doit contenir au moins 6 caractères'),
        findsOneWidget,
      );
      expect(submitEnabled(tester, 'register-submit'), isFalse);

      await tester.enterText(
        find.byKey(const Key('register-username')),
        'bob smith',
      );
      await tester.pump();
      expect(
        find.text(
          'Le pseudo ne peut contenir que des lettres, chiffres, tirets (-) '
          'et underscores (_)',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('register-username')),
        'a' * 31,
      );
      await tester.enterText(
        find.byKey(const Key('register-password')),
        'x' * 101,
      );
      await tester.pump();
      expect(
        find.text('Le pseudo ne peut pas dépasser 30 caractères'),
        findsOneWidget,
      );
      expect(
        find.text('Le mot de passe ne peut pas dépasser 100 caractères'),
        findsOneWidget,
      );
      expect(submitEnabled(tester, 'register-submit'), isFalse);

      await tester.enterText(find.byKey(const Key('register-username')), '');
      await tester.enterText(find.byKey(const Key('register-password')), '');
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsOneWidget);
      expect(find.text('Le mot de passe est requis'), findsOneWidget);
      expect(submitEnabled(tester, 'register-submit'), isFalse);

      await tester.enterText(
        find.byKey(const Key('register-username')),
        'new_player-1',
      );
      await tester.enterText(
        find.byKey(const Key('register-password')),
        'secret1',
      );
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsNothing);
      expect(submitEnabled(tester, 'register-submit'), isTrue);
    });

    testWidgets('the messages are English in English', (tester) async {
      await pumpApp(
        tester,
        initialLocation: AppRoutes.register,
        locale: const Locale('en'),
      );
      await tester.enterText(find.byKey(const Key('register-username')), 'ab');
      await tester.pump();
      expect(
        find.text('Username must be at least 3 characters'),
        findsOneWidget,
      );
    });

    testWidgets('success reaches the parties screen', (tester) async {
      final requests = <http.Request>[];
      final storage = MemoryTokenStorage();
      await pumpApp(
        tester,
        initialLocation: AppRoutes.register,
        storage: storage,
        api: fakeApi(
          (_) async => http.Response(authFixtureWithJwt('auth_register'), 201),
          requests: requests,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('register-username')),
        ' fixture537397 ',
      );
      await tester.enterText(
        find.byKey(const Key('register-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(requests.single.url.path, '/api/auth/register');
      expect(jsonDecode(requests.single.body), {
        'username': 'fixture537397',
        'password': 'secret1',
      });
      expect(find.text('Bienvenue, fixture537397 !'), findsOneWidget);
      expect(storage.values['token'], validToken);
    });

    testWidgets('a taken username shows the refusal', (tester) async {
      await pumpApp(
        tester,
        initialLocation: AppRoutes.register,
        api: fakeApi(
          (_) async => http.Response(
            jsonEncode({
              'error': 'Username already exists',
              'code': 'USERNAME_EXISTS',
            }),
            409,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('register-username')),
        'Vincent',
      );
      await tester.enterText(
        find.byKey(const Key('register-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Ce pseudo est déjà pris'), findsOneWidget);
      expect(find.text('Créer un compte'), findsOneWidget);
    });
  });

  group('login', () {
    testWidgets('submit is disabled until both fields are filled in', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Connexion'), findsOneWidget);
      expect(submitEnabled(tester, 'login-submit'), isFalse);

      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.pump();
      expect(submitEnabled(tester, 'login-submit'), isFalse);

      await tester.enterText(find.byKey(const Key('login-password')), 'x');
      await tester.pump();
      expect(submitEnabled(tester, 'login-submit'), isTrue);

      await tester.enterText(find.byKey(const Key('login-username')), '   ');
      await tester.enterText(find.byKey(const Key('login-password')), '');
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsOneWidget);
      expect(find.text('Le mot de passe est requis'), findsOneWidget);
      expect(submitEnabled(tester, 'login-submit'), isFalse);
    });

    testWidgets('a wrong password shows the refusal and stays', (tester) async {
      final error = errorFixture('error_invalid_credentials');
      await pumpApp(
        tester,
        api: fakeApi((_) async => http.Response(error.body, error.status)),
      );
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
      await tester.pump();
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Pseudo ou mot de passe incorrect'), findsOneWidget);
      expect(find.text('Connexion'), findsOneWidget);
    });

    testWidgets('no server shows the network message', (tester) async {
      await pumpApp(
        tester,
        api: fakeApi((_) async => throw http.ClientException('refused')),
      );
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('Serveur injoignable. Vérifiez votre connexion.'),
        findsOneWidget,
      );
    });

    testWidgets('success reaches the parties screen; logout returns to login', (
      tester,
    ) async {
      final storage = MemoryTokenStorage();
      await pumpApp(
        tester,
        storage: storage,
        api: fakeApi(
          (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Parties'), findsOneWidget);
      expect(find.text('Bienvenue, Vincent !'), findsOneWidget);

      await tester.tap(find.byKey(const Key('logout')));
      await tester.pumpAndSettle();

      expect(find.text('Connexion'), findsOneWidget);
      expect(storage.values, isEmpty);
    });

    testWidgets('the register link opens the register screen', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text("S'inscrire"));
      await tester.pumpAndSettle();
      expect(find.text('Créer un compte'), findsOneWidget);
      await tester.tap(find.text('Se connecter').last);
      await tester.pumpAndSettle();
      expect(find.text('Connexion'), findsOneWidget);
    });
  });

  group('routing', () {
    testWidgets('an expired JWT sends a protected route to login', (
      tester,
    ) async {
      final storage = storedSession(expiredToken);
      await pumpApp(
        tester,
        initialLocation: AppRoutes.parties,
        storage: storage,
      );

      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Parties'), findsNothing);
      expect(storage.values, isEmpty);
    });

    testWidgets('a valid stored session opens the protected route', (
      tester,
    ) async {
      await pumpApp(
        tester,
        initialLocation: AppRoutes.parties,
        storage: storedSession(validToken),
      );
      expect(find.text('Bienvenue, Vincent !'), findsOneWidget);
    });

    testWidgets('signed out, a protected route goes to login and back after '
        'signing in', (tester) async {
      await pumpApp(
        tester,
        initialLocation: AppRoutes.parties,
        api: fakeApi(
          (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
        ),
      );
      expect(find.text('Connexion'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        'secret1',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Bienvenue, Vincent !'), findsOneWidget);
    });

    testWidgets('a 401 on an authenticated call returns to login', (
      tester,
    ) async {
      final unauthorized = errorFixture('error_invalid_token');
      final api = fakeApi(
        (_) async => http.Response(unauthorized.body, unauthorized.status),
      );
      await pumpApp(
        tester,
        initialLocation: AppRoutes.parties,
        api: api,
        storage: storedSession(validToken),
      );
      expect(find.text('Parties'), findsOneWidget);

      await tester.runAsync(
        () => Future.wait([
          api.get('/party').then((_) {}, onError: (_) {}),
          api.get('/party').then((_) {}, onError: (_) {}),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connexion'), findsOneWidget);
    });
  });

  group('authRedirect', () {
    Future<AuthProvider> restored(TokenStorage storage) async {
      final api = unusedApi();
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storage,
      );
      await auth.restore();
      return auth;
    }

    String? go(AuthProvider auth, String location) =>
        authRedirect(auth, Uri.parse(location));

    test('waits on the splash until the session is read', () {
      final api = unusedApi();
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: MemoryTokenStorage(),
      );
      expect(go(auth, '/parties'), '/splash?from=%2Fparties');
      expect(go(auth, '/'), '/splash');
      expect(go(auth, '/splash?from=%2Fparties'), isNull);
    });

    test('signed out: public routes stay, others go to login', () async {
      final auth = await restored(MemoryTokenStorage());
      expect(go(auth, '/'), isNull);
      expect(go(auth, '/login'), isNull);
      expect(go(auth, '/register'), isNull);
      expect(go(auth, '/parties'), '/login?from=%2Fparties');
      expect(go(auth, '/admin/users'), '/login?from=%2Fadmin%2Fusers');
      expect(go(auth, '/splash?from=%2Fparties'), '/parties');
    });

    test('signed in: login and home lead on; /admin needs isAdmin', () async {
      final player = await restored(storedSession(validToken));
      expect(go(player, '/login'), '/parties');
      expect(go(player, '/'), '/parties');
      expect(go(player, '/login?from=%2Fparty%2Fp1'), '/party/p1');
      expect(go(player, '/parties'), isNull);
      expect(go(player, '/admin'), '/parties');
      expect(go(player, '/admin/users'), '/parties');
      expect(go(player, '/administrator'), isNull);

      final admin = await restored(storedSession(validToken, isAdmin: true));
      expect(go(admin, '/admin/users'), isNull);
    });

    test('a remembered path to another site is ignored', () async {
      final player = await restored(storedSession(validToken));
      expect(go(player, '/login?from=https%3A%2F%2Fevil.example'), '/parties');
      expect(go(player, '/login?from=%2F%2Fevil.example'), '/parties');
    });
  });
}
