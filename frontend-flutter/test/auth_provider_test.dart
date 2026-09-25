import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapzap/models/user.dart';
import 'package:zapzap/providers/auth_provider.dart';
import 'package:zapzap/repositories/auth_repository.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/api_exception.dart';
import 'package:zapzap/services/google_sign_in_service.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/services/token_storage_web.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'google_fakes.dart';

void main() {
  AuthProvider providerWith(ApiClient api, TokenStorage storage) =>
      AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storage,
      );

  group('restore', () {
    test('a stored session with a valid token signs in', () async {
      final api = unusedApi();
      final auth = providerWith(api, storedSession(validToken, isAdmin: true));
      expect(auth.isRestored, isFalse);

      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isAdmin, isTrue);
      expect(auth.user!.username, 'Vincent');
      expect(auth.token, validToken);
      expect(api.token, validToken);
    });

    test('an expired token is erased and signs nobody in', () async {
      final storage = storedSession(expiredToken);
      final auth = providerWith(unusedApi(), storage);

      await auth.restore();

      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isFalse);
      expect(auth.token, isNull);
      expect(storage.values, isEmpty);
    });

    test('nothing stored, or a corrupted user, is signed out', () async {
      final empty = providerWith(unusedApi(), MemoryTokenStorage());
      await empty.restore();
      expect(empty.isAuthenticated, isFalse);

      final corrupted = providerWith(
        unusedApi(),
        MemoryTokenStorage({'token': validToken, 'user': '{not json'}),
      );
      await corrupted.restore();
      expect(corrupted.isRestored, isTrue);
      expect(corrupted.isAuthenticated, isFalse);
    });

    test('a session that expires while the app runs stops counting', () async {
      var now = DateTime.now();
      final api = unusedApi();
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storedSession(jwtExpiringIn(const Duration(minutes: 5))),
        clock: () => now,
      );
      await auth.restore();
      expect(auth.isAuthenticated, isTrue);

      now = now.add(const Duration(minutes: 6));
      expect(auth.isAuthenticated, isFalse);
      expect(auth.isAdmin, isFalse);
    });
  });

  group('login and register', () {
    test('login stores the token and the user under the React keys', () async {
      final requests = <http.Request>[];
      final api = fakeApi(
        (_) async => http.Response(authFixtureWithJwt('auth_login'), 200),
        requests: requests,
      );
      final storage = MemoryTokenStorage();
      final auth = providerWith(api, storage);
      var notified = 0;
      auth.addListener(() => notified++);

      await auth.login('Vincent', 'secret1');

      expect(requests.single.url.path, '/api/auth/login');
      expect(jsonDecode(requests.single.body), {
        'username': 'Vincent',
        'password': 'secret1',
      });
      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.username, 'Vincent');
      expect(api.token, validToken);
      expect(notified, 1);
      expect(storage.values['token'], validToken);
      expect(
        jsonDecode(storage.values['user']!),
        containsPair('isAdmin', false),
      );

      // What was stored is what the next start restores.
      final next = providerWith(unusedApi(), storage);
      await next.restore();
      expect(next.user!.id, auth.user!.id);
    });

    test('register signs in too', () async {
      final api = fakeApi(
        (_) async => http.Response(authFixtureWithJwt('auth_register'), 201),
      );
      final auth = providerWith(api, MemoryTokenStorage());

      await auth.register('fixture537397', 'secret1');

      expect(auth.isAuthenticated, isTrue);
      expect(auth.user!.username, 'fixture537397');
    });

    test('a refusal throws and leaves the session signed out', () async {
      final error = errorFixture('error_invalid_credentials');
      final api = fakeApi((_) async => http.Response(error.body, error.status));
      final storage = MemoryTokenStorage();
      final auth = providerWith(api, storage);

      await expectLater(
        auth.login('Vincent', 'wrong-password'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
      expect(storage.values, isEmpty);
    });
  });

  group('logout', () {
    test('clears the session, the client token and the storage', () async {
      final api = unusedApi();
      final storage = storedSession(validToken);
      final auth = providerWith(api, storage);
      await auth.restore();

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.user, isNull);
      expect(auth.token, isNull);
      expect(api.token, isNull);
      expect(storage.values, isEmpty);
    });

    test('signs out of Google too, so the next person is not offered the '
        'account', () async {
      final google = FakeGoogleSignIn();
      final api = unusedApi();
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storedSession(validToken),
        google: google,
      );
      await auth.restore();

      await auth.logout();
      expect(google.signOuts, 1);

      // Idempotent: already signed out, Google is not asked again.
      await auth.logout();
      expect(google.signOuts, 1);
    });

    test('a Google sign-out that fails still signs out', () async {
      final google = FakeGoogleSignIn()
        ..signOutThrows = const GoogleSignInFailure('no GIS');
      final api = unusedApi();
      final storage = storedSession(validToken);
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storage,
        google: google,
      );
      await auth.restore();

      await auth.logout();
      await pumpEventQueue();

      expect(google.signOuts, 1);
      expect(auth.isAuthenticated, isFalse);
      expect(api.token, isNull);
      expect(storage.values, isEmpty);
    });

    test(
      'a Google sign-out that never answers does not hold the logout',
      () async {
        final google = FakeGoogleSignIn()
          ..onSignOut = () => Completer<void>().future;
        final api = unusedApi();
        final auth = AuthProvider(
          repository: AuthRepository(api),
          apiClient: api,
          storage: storedSession(validToken),
          google: google,
        );
        await auth.restore();

        await auth.logout();
        expect(google.signOuts, 1);
        expect(auth.isAuthenticated, isFalse);
      },
    );

    test('a 401 on an authenticated call signs out, once for many', () async {
      final unauthorized = errorFixture('error_invalid_token');
      final api = fakeApi(
        (_) async => http.Response(unauthorized.body, unauthorized.status),
      );
      final auth = providerWith(api, storedSession(validToken));
      await auth.restore();
      var notified = 0;
      auth.addListener(() => notified++);

      // Parallel requests, each answered 401: logout runs once.
      await Future.wait([
        for (var i = 0; i < 3; i++)
          api.get('/party').then((_) {}, onError: (_) {}),
      ]);

      expect(auth.isAuthenticated, isFalse);
      expect(api.token, isNull);
      expect(notified, 1);

      await auth.logout();
      expect(notified, 1);
    });
  });

  group('PreferencesTokenStorage (the web storage)', () {
    test('round-trips a session through shared_preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = PreferencesTokenStorage();
      expect(await storage.read(), isNull);

      await storage.write(
        AuthSession(
          token: validToken,
          user: const User(id: 'u1', username: 'Vincent', isAdmin: true),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('token'), validToken);

      final session = await storage.read();
      expect(session!.token, validToken);
      expect(session.user.isAdmin, isTrue);

      await storage.clear();
      expect(await storage.read(), isNull);
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
