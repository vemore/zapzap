import 'dart:async';
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
import 'party_helpers.dart';
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
    testWidgets('invalid username and password show the messages on '
        'submit, which sends nothing', (tester) async {
      final requests = <http.Request>[];
      await pumpApp(
        tester,
        initialLocation: AppRoutes.register,
        api: fakeApi((_) async => http.Response('{}', 500), requests: requests),
      );
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(submitEnabled(tester, 'register-submit'), isTrue);

      await tester.enterText(find.byKey(const Key('register-username')), 'ab');
      await tester.enterText(find.byKey(const Key('register-password')), '123');
      await tester.pump();
      await tester.tap(find.byKey(const Key('register-submit')));
      await tester.pump();
      expect(
        find.text('Le pseudo doit contenir au moins 3 caractères'),
        findsOneWidget,
      );
      expect(
        find.text('Le mot de passe doit contenir au moins 6 caractères'),
        findsOneWidget,
      );
      expect(requests, isEmpty);

      // From then on the rules are checked live.
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

      await tester.enterText(find.byKey(const Key('register-username')), '');
      await tester.enterText(find.byKey(const Key('register-password')), '');
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsOneWidget);
      expect(find.text('Le mot de passe est requis'), findsOneWidget);

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
      expect(find.text('Le mot de passe est requis'), findsNothing);
    });

    testWidgets('a field shows its refusal once edited and left, not while '
        'typing', (tester) async {
      await pumpApp(tester, initialLocation: AppRoutes.register);
      await tester.enterText(find.byKey(const Key('register-username')), 'ab');
      await tester.pump();
      expect(
        find.text('Le pseudo doit contenir au moins 3 caractères'),
        findsNothing,
      );
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(
        find.text('Le pseudo doit contenir au moins 3 caractères'),
        findsOneWidget,
      );
      // The password field has the focus but was not edited: quiet.
      expect(find.text('Le mot de passe est requis'), findsNothing);
    });

    testWidgets('the messages are English in English', (tester) async {
      await pumpApp(
        tester,
        initialLocation: AppRoutes.register,
        locale: const Locale('en'),
      );
      await tester.enterText(find.byKey(const Key('register-username')), 'ab');
      await tester.tap(find.byKey(const Key('register-submit')));
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

      expect(requests.first.url.path, '/api/auth/register');
      expect(jsonDecode(requests.first.body), {
        'username': 'fixture537397',
        'password': 'secret1',
      });
      expect(find.text('Parties disponibles'), findsOneWidget);
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
    testWidgets('C1: the logo says what the game is, above the title', (
      tester,
    ) async {
      await pumpApp(tester);
      final pitch = find.text(
        'Vide ta main : à 5 points ou moins, crie ZapZap !',
      );
      expect(pitch, findsOneWidget);
      expect(
        tester.getRect(pitch).bottom,
        lessThanOrEqualTo(tester.getRect(find.text('Connexion')).top),
      );
    });

    testWidgets('C2: submit stays active; a click says what is missing and '
        'sends nothing', (tester) async {
      final requests = <http.Request>[];
      await pumpApp(
        tester,
        api: fakeApi((_) async => http.Response('{}', 500), requests: requests),
      );
      expect(find.text('Connexion'), findsOneWidget);
      expect(submitEnabled(tester, 'login-submit'), isTrue);
      expect(find.text('Le pseudo est requis'), findsNothing);
      expect(find.text('Le mot de passe est requis'), findsNothing);

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsOneWidget);
      expect(find.text('Le mot de passe est requis'), findsOneWidget);
      expect(requests, isEmpty);
      expect(submitEnabled(tester, 'login-submit'), isTrue);

      // Each message goes as soon as its field is filled in.
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsNothing);
      expect(find.text('Le mot de passe est requis'), findsOneWidget);

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(requests, isEmpty);

      await tester.enterText(find.byKey(const Key('login-username')), '   ');
      await tester.enterText(find.byKey(const Key('login-password')), 'x');
      await tester.pump();
      expect(find.text('Le pseudo est requis'), findsOneWidget);
      expect(find.text('Le mot de passe est requis'), findsNothing);
    });

    testWidgets('C3: the eye shows the password; Next moves on, Done signs '
        'in; both fields share one AutofillGroup', (tester) async {
      final requests = <http.Request>[];
      await pumpApp(
        tester,
        api: fakeApi(
          (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
          requests: requests,
        ),
      );
      EditableText editable(String key) => tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(EditableText),
        ),
      );
      final group = find.byType(AutofillGroup);
      expect(group, findsOneWidget);
      for (final key in ['login-username', 'login-password']) {
        expect(
          find.descendant(of: group, matching: find.byKey(Key(key))),
          findsOneWidget,
        );
      }
      expect(editable('login-username').autofillHints, [
        AutofillHints.username,
      ]);
      expect(editable('login-password').autofillHints, [
        AutofillHints.password,
      ]);

      expect(editable('login-password').obscureText, isTrue);
      expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('password-visibility')));
      await tester.pump();
      expect(editable('login-password').obscureText, isFalse);
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
      await tester.tap(find.byKey(const Key('password-visibility')));
      await tester.pump();
      expect(editable('login-password').obscureText, isTrue);

      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(editable('login-password').focusNode.hasFocus, isTrue);

      await tester.enterText(
        find.byKey(const Key('login-password')),
        'secret1',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(requests.first.url.path, '/api/auth/login');
      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('C4: a spinner in the button while signing in, one request '
        'only; the refusal sits just above the button', (tester) async {
      final requests = <http.Request>[];
      final answer = Completer<http.Response>();
      final error = errorFixture('error_invalid_credentials');
      await pumpApp(
        tester,
        api: fakeApi((_) => answer.future, requests: requests),
      );
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'wrong');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byKey(const Key('login-submit')),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text('Connexion…'), findsOneWidget);
      expect(submitEnabled(tester, 'login-submit'), isFalse);
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(requests, hasLength(1));

      answer.complete(http.Response(error.body, error.status));
      await tester.pumpAndSettle();
      final banner = find.byKey(const Key('auth-error'));
      expect(
        find.descendant(
          of: banner,
          matching: find.text('Pseudo ou mot de passe incorrect'),
        ),
        findsOneWidget,
      );
      final bannerRect = tester.getRect(banner);
      expect(
        bannerRect.top,
        greaterThan(
          tester.getRect(find.byKey(const Key('login-password'))).bottom,
        ),
      );
      expect(
        bannerRect.bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('login-submit'))).top,
        ),
      );
      expect(submitEnabled(tester, 'login-submit'), isTrue);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('on a 360×740 phone at a text scale of $scale, the pitch, '
          'both errors, the eye and the banner fit', (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(
          tester,
          api: fakeApi((_) async => throw http.ClientException('refused')),
        );
        await tester.enterText(
          find.byKey(const Key('login-username')),
          'Vincent',
        );
        await tester.enterText(find.byKey(const Key('login-password')), 'x');
        await tester.ensureVisible(find.byKey(const Key('login-submit')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('login-submit')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('login-username')), '');
        await tester.enterText(find.byKey(const Key('login-password')), '');
        await tester.pump();

        for (final finder in [
          find.byKey(const Key('app-pitch')),
          find.text('Le pseudo est requis'),
          find.text('Le mot de passe est requis'),
          find.byKey(const Key('password-visibility')),
          find.byKey(const Key('auth-error')),
          find.byKey(const Key('login-submit')),
        ]) {
          expect(finder, findsOneWidget);
          await tester.ensureVisible(finder);
          await tester.pump();
          final rect = tester.getRect(finder);
          final screen = Offset.zero & const Size(360, 740);
          expect(screen.intersect(rect), rect, reason: '$finder off screen');
        }
        expect(tester.takeException(), isNull);
      });
    }

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
        find.text('Serveur injoignable. Vérifie ta connexion.'),
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
      expect(find.text('Parties disponibles'), findsOneWidget);

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
        api: FakeLobbyBackend().client(),
        storage: storedSession(validToken),
      );
      expect(find.text('Parties disponibles'), findsOneWidget);
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
      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('a 401 on an authenticated call returns to login', (
      tester,
    ) async {
      final unauthorized = errorFixture('error_invalid_token');
      // The session only goes stale once the parties screen is up.
      var expired = false;
      final api = fakeApi(
        (_) async => expired
            ? http.Response(unauthorized.body, unauthorized.status)
            : http.Response(jsonEncode({'parties': <Object>[]}), 200),
      );
      await pumpApp(
        tester,
        initialLocation: AppRoutes.parties,
        api: api,
        storage: storedSession(validToken),
      );
      expect(find.text('Parties'), findsOneWidget);
      expired = true;

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
