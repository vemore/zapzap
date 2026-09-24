import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/google_sign_in_service.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'sse_fakes.dart';

/// Google replaced: [signIn] hands over [nextToken], or fails with
/// [nextFailure], or does nothing (the user closed the dialog) when both are
/// `null`.
class FakeGoogleSignIn implements GoogleSignInService {
  final _tokens = StreamController<String>.broadcast();
  String? nextToken = 'google-id-token';
  Object? nextFailure;

  /// Thrown by [signIn] itself (a failure the token stream does not carry).
  Object? signInThrows;
  int signIns = 0;

  /// Google's own button, as on the web; `null`: the app draws one.
  Widget Function()? webButton;
  int platformButtonCalls = 0;

  /// A token handed over by Google's own button, bypassing [signIn].
  void emit(String token) => _tokens.add(token);

  @override
  bool get enabled => true;

  @override
  Stream<String> get idTokens => _tokens.stream;

  @override
  Widget? platformButton(BuildContext context) {
    platformButtonCalls++;
    return webButton?.call();
  }

  @override
  Future<void> signIn() async {
    signIns++;
    if (signInThrows != null) throw signInThrows!;
    if (nextFailure != null) {
      _tokens.addError(nextFailure!);
    } else if (nextToken != null) {
      _tokens.add(nextToken!);
    }
  }
}

void main() {
  const webId = '1234-abc.apps.googleusercontent.com';

  group('GoogleSignInConfig', () {
    test('no client id: disabled on every platform', () {
      for (final isWeb in [true, false]) {
        final config = GoogleSignInConfig.resolve(
          webClientId: '  ',
          isWeb: isWeb,
          platform: TargetPlatform.android,
        );
        expect(config.enabled, isFalse);
      }
      // This test run has no --dart-define=GOOGLE_CLIENT_ID.
      expect(GoogleSignInConfig.definedClientId, isEmpty);
      expect(GoogleSignInConfig.fromEnvironment().enabled, isFalse);
    });

    test('the web asks with the web client id as clientId', () {
      final config = GoogleSignInConfig.resolve(
        webClientId: ' $webId ',
        isWeb: true,
        platform: TargetPlatform.android,
      );
      expect(config.enabled, isTrue);
      expect(config.clientId, webId);
      expect(config.serverClientId, isNull);
    });

    test('Android asks the token for the web client id: serverClientId', () {
      final config = GoogleSignInConfig.resolve(
        webClientId: webId,
        isWeb: false,
        platform: TargetPlatform.android,
      );
      expect(config.enabled, isTrue);
      expect(config.serverClientId, webId);
      expect(config.clientId, isNull);
    });

    test('other platforms: disabled', () {
      for (final platform in [TargetPlatform.iOS, TargetPlatform.linux]) {
        expect(
          GoogleSignInConfig.resolve(
            webClientId: webId,
            isWeb: false,
            platform: platform,
          ).enabled,
          isFalse,
        );
      }
    });
  });

  Future<void> pumpApp(
    WidgetTester tester, {
    String initialLocation = AppRoutes.login,
    ApiClient? api,
    TokenStorage? storage,
    GoogleSignInService? google,
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
        googleSignIn: google,
      ),
    );
    await tester.pumpAndSettle();
  }

  final googleButton = find.byKey(const Key('google-sign-in'));

  group('login screen', () {
    testWidgets('without --dart-define=GOOGLE_CLIENT_ID: no Google button', (
      tester,
    ) async {
      // No fake: the app builds Google from the (empty) define.
      await pumpApp(tester);
      expect(find.text('Connexion'), findsOneWidget);
      expect(googleButton, findsNothing);
      expect(find.text('Continuer avec Google'), findsNothing);
      expect(find.text('ou'), findsNothing);

      // A fresh tree: the router keeps its first location otherwise.
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, initialLocation: AppRoutes.register);
      expect(find.text('Créer un compte'), findsOneWidget);
      expect(googleButton, findsNothing);
    });

    testWidgets('with a client id: the button and the rule above the fields', (
      tester,
    ) async {
      await pumpApp(tester, google: FakeGoogleSignIn());
      expect(find.text('Continuer avec Google'), findsOneWidget);
      expect(find.text('ou'), findsOneWidget);
      expect(
        tester.getRect(googleButton).bottom,
        lessThan(tester.getRect(find.byKey(const Key('login-username'))).top),
      );
    });

    testWidgets('a Google sign-in posts the ID token as credential to '
        'POST /auth/google and lands on the parties', (tester) async {
      final requests = <http.Request>[];
      final storage = MemoryTokenStorage();
      await pumpApp(
        tester,
        storage: storage,
        google: FakeGoogleSignIn(),
        api: fakeApi(
          (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
          requests: requests,
        ),
      );

      await tester.tap(googleButton);
      await tester.pumpAndSettle();

      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/api/auth/google');
      expect(requests.first.headers['Authorization'], isNull);
      expect(jsonDecode(requests.first.body), {
        'credential': 'google-id-token',
      });
      expect(find.text('Parties disponibles'), findsOneWidget);
      expect(storage.values['token'], validToken);
    });

    testWidgets('a backend refusal shows an error and stays on the login '
        'screen', (tester) async {
      final requests = <http.Request>[];
      await pumpApp(
        tester,
        google: FakeGoogleSignIn(),
        api: fakeApi(
          (_) async => http.Response(
            jsonEncode({
              'error': 'Invalid Google token',
              'code': 'GOOGLE_AUTH_FAILED',
            }),
            401,
          ),
          requests: requests,
        ),
      );

      await tester.tap(googleButton);
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(find.byKey(const Key('auth-error')), findsOneWidget);
      expect(
        find.text('La connexion Google a échoué. Réessaie.'),
        findsOneWidget,
      );
      expect(find.text('Connexion'), findsOneWidget);
      expect(find.text('Parties disponibles'), findsNothing);
      // The button is usable again.
      expect(tester.widget<OutlinedButton>(googleButton).onPressed, isNotNull);
    });

    testWidgets('a failure on Google\'s side shows the error and posts '
        'nothing; a closed dialog says nothing', (tester) async {
      final requests = <http.Request>[];
      final google = FakeGoogleSignIn()..nextToken = null;
      await pumpApp(
        tester,
        google: google,
        api: fakeApi((_) async => http.Response('{}', 500), requests: requests),
      );

      await tester.tap(googleButton);
      await tester.pumpAndSettle();
      expect(google.signIns, 1);
      expect(find.byKey(const Key('auth-error')), findsNothing);

      google.nextFailure = const GoogleSignInFailure(
        'clientConfigurationError',
      );
      await tester.tap(googleButton);
      await tester.pumpAndSettle();
      expect(
        find.text('La connexion Google a échoué. Réessaie.'),
        findsOneWidget,
      );
      expect(requests, isEmpty);
      expect(find.text('Connexion'), findsOneWidget);
    });

    testWidgets('a failure signIn throws itself shows the error', (
      tester,
    ) async {
      final google = FakeGoogleSignIn()
        ..signInThrows = const GoogleSignInFailure('init failed');
      await pumpApp(tester, google: google);
      await tester.tap(googleButton);
      await tester.pumpAndSettle();
      expect(
        find.text('La connexion Google a échoué. Réessaie.'),
        findsOneWidget,
      );
      expect(find.text('Connexion'), findsOneWidget);
    });

    testWidgets('a token arriving while a password login is in flight is '
        'dropped', (tester) async {
      final requests = <http.Request>[];
      final login = Completer<http.Response>();
      final google = FakeGoogleSignIn()
        ..webButton = () => const SizedBox(key: Key('gsi'), height: 44);
      await pumpApp(
        tester,
        google: google,
        api: fakeApi((_) => login.future, requests: requests),
      );
      await tester.enterText(
        find.byKey(const Key('login-username')),
        'Vincent',
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'x');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();

      // Google's web button still works while the form is busy.
      google.emit('google-id-token');
      await tester.pump();
      expect(requests.map((r) => r.url.path), ['/api/auth/login']);

      login.complete(http.Response(authFixtureWithJwt('auth_login'), 200));
      await tester.pumpAndSettle();
      expect(
        requests.map((r) => r.url.path),
        isNot(contains('/api/auth/google')),
      );
      expect(find.text('Parties disponibles'), findsOneWidget);
    });

    testWidgets('Google\'s web button is built once: typing in the fields '
        'keeps the same instance', (tester) async {
      var created = 0;
      final google = FakeGoogleSignIn()
        ..webButton = () => _CountingButton(onCreate: () => created++);
      await pumpApp(tester, google: google);
      expect(find.byType(_CountingButton), findsOneWidget);
      expect(googleButton, findsNothing);
      final first = tester.widget(find.byType(_CountingButton));

      for (final text in ['V', 'Vi', 'Vin']) {
        await tester.enterText(find.byKey(const Key('login-username')), text);
        await tester.pump();
      }
      await tester.enterText(find.byKey(const Key('login-password')), 'x');
      await tester.pump();

      expect(google.platformButtonCalls, 1);
      expect(created, 1);
      expect(
        identical(tester.widget(find.byType(_CountingButton)), first),
        isTrue,
      );
    });

    testWidgets('no network: the network message', (tester) async {
      await pumpApp(
        tester,
        google: FakeGoogleSignIn(),
        api: fakeApi((_) async => throw http.ClientException('offline')),
      );
      await tester.tap(googleButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Serveur injoignable. Vérifie ta connexion.'),
        findsOneWidget,
      );
    });

    testWidgets('English', (tester) async {
      await pumpApp(
        tester,
        google: FakeGoogleSignIn(),
        locale: const Locale('en'),
      );
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('or'), findsOneWidget);
    });
  });

  testWidgets('the register screen signs up with Google too', (tester) async {
    final requests = <http.Request>[];
    await pumpApp(
      tester,
      initialLocation: AppRoutes.register,
      google: FakeGoogleSignIn(),
      api: fakeApi(
        (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
        requests: requests,
      ),
    );
    await tester.tap(googleButton);
    await tester.pumpAndSettle();
    expect(requests.first.url.path, '/api/auth/google');
    expect(find.text('Parties disponibles'), findsOneWidget);
  });

  group('phone width', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('login with Google at 360x740, text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(tester, google: FakeGoogleSignIn());
        expect(tester.takeException(), isNull);
        expect(googleButton, findsOneWidget);
      });
    }
  });
}

/// Stands for Google's web button: counts the states created, i.e. how many
/// times the iframe would be rendered.
class _CountingButton extends StatefulWidget {
  const _CountingButton({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_CountingButton> createState() => _CountingButtonState();
}

class _CountingButtonState extends State<_CountingButton> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 44);
}
