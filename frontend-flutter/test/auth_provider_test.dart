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

  group('guest', () {
    const guestPassword = 'Gen3ratedGuestPassw0rd42';
    const guestUser = {
      'id': 'g1',
      'username': 'Guest_12345',
      'email': null,
      'isAdmin': false,
      'isGoogleUser': false,
      'hasPassword': true,
      'isGuest': true,
    };
    final freshToken = jwtExpiringIn(const Duration(days: 7), userId: 'g1');

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    http.Response signedIn(String token, [Map<String, Object?>? user]) =>
        json({'success': true, 'user': user ?? guestUser, 'token': token});

    Map<String, Object> credentials({
      String username = 'Guest_12345',
      bool active = true,
    }) => {
      'userId': 'g1',
      'username': username,
      'password': guestPassword,
      'active': active,
    };

    /// A storage holding the guest's session under [token] and its
    /// credentials.
    MemoryTokenStorage guestStorage(String token) => MemoryTokenStorage({
      TokenStorage.tokenKey: token,
      TokenStorage.userKey: jsonEncode(guestUser),
      TokenStorage.guestKey: jsonEncode(credentials()),
    });

    Map<String, dynamic>? storedGuest(MemoryTokenStorage storage) {
      final text = storage.values[TokenStorage.guestKey];
      return text == null
          ? null
          : (jsonDecode(text) as Map).cast<String, dynamic>();
    }

    test('playAsGuest creates the account and keeps its credentials', () async {
      final requests = <http.Request>[];
      final api = fakeApi(
        (_) async => json({
          'success': true,
          'user': guestUser,
          'token': freshToken,
          'password': guestPassword,
        }, 201),
        requests: requests,
      );
      final storage = MemoryTokenStorage();
      final auth = providerWith(api, storage);

      await auth.playAsGuest();

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/api/auth/guest');
      expect(requests.single.headers['Authorization'], isNull);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isGuest, isTrue);
      expect(auth.guestPassword, guestPassword);
      expect(storage.values[TokenStorage.tokenKey], freshToken);
      expect(storedGuest(storage), credentials());
    });

    test('with an expired token and a stored guest password, the start-up '
        'signs back in silently', () async {
      final requests = <http.Request>[];
      final api = fakeApi(
        (_) async => signedIn(freshToken),
        requests: requests,
      );
      final storage = guestStorage(expiredToken);
      final auth = providerWith(api, storage);

      await auth.restore();

      expect(requests.single.url.path, '/api/auth/login');
      expect(jsonDecode(requests.single.body), {
        'username': 'Guest_12345',
        'password': guestPassword,
      });
      expect(auth.isRestored, isTrue);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.isGuest, isTrue);
      expect(api.token, freshToken);
      expect(storage.values[TokenStorage.tokenKey], freshToken);
      expect(storedGuest(storage), credentials());
    });

    test(
      'a 401 signs the guest back in rather than out, once for many',
      () async {
        var logins = 0;
        final unauthorized = errorFixture('error_invalid_token');
        final api = fakeApi((request) async {
          if (request.url.path == '/api/auth/login') {
            logins++;
            return signedIn(freshToken);
          }
          return http.Response(unauthorized.body, unauthorized.status);
        });
        final refused = jwtExpiringIn(const Duration(hours: 1), userId: 'g1');
        final auth = providerWith(api, guestStorage(refused));
        await auth.restore();
        expect(auth.token, refused);

        await Future.wait([
          for (var i = 0; i < 3; i++)
            api.get('/party').then((_) {}, onError: (_) {}),
        ]);
        await pumpEventQueue();

        expect(logins, 1);
        expect(auth.isAuthenticated, isTrue);
        expect(auth.token, freshToken);
        expect(api.token, freshToken);
      },
    );

    test('credentials the backend refuses are erased, and the guest is '
        'signed out', () async {
      final error = errorFixture('error_invalid_credentials');
      final api = fakeApi((_) async => http.Response(error.body, error.status));
      final storage = guestStorage(expiredToken);
      final auth = providerWith(api, storage);

      await auth.restore();

      expect(auth.isAuthenticated, isFalse);
      expect(storage.values, isEmpty);
    });

    test(
      'a network failure keeps the credentials for the next start',
      () async {
        var online = false;
        final api = fakeApi((_) async {
          if (!online) throw http.ClientException('offline');
          return signedIn(freshToken);
        });
        final storage = guestStorage(expiredToken);

        final offline = providerWith(api, storage);
        await offline.restore();
        expect(offline.isAuthenticated, isFalse);
        expect(storage.values[TokenStorage.tokenKey], isNull);
        expect(storedGuest(storage), credentials());

        online = true;
        final next = providerWith(api, storage);
        await next.restore();
        expect(next.isAuthenticated, isTrue);
        expect(next.user!.id, 'g1');
      },
    );

    test(
      "another account's expired session does not sign the guest in",
      () async {
        final storage = storedSession(expiredToken)
          ..values[TokenStorage.guestKey] = jsonEncode(credentials());
        final auth = providerWith(unusedApi(), storage);

        await auth.restore();

        expect(auth.isAuthenticated, isFalse);
        expect(storedGuest(storage), credentials());
      },
    );

    test('« Jouer sans compte » with stored credentials signs that account '
        'back in instead of creating one', () async {
      var online = false;
      final requests = <http.Request>[];
      final api = fakeApi((_) async {
        if (!online) throw http.ClientException('offline');
        return signedIn(freshToken);
      }, requests: requests);
      final storage = MemoryTokenStorage({
        TokenStorage.guestKey: jsonEncode(credentials()),
      });
      final auth = providerWith(api, storage);
      await auth.restore();
      expect(auth.isAuthenticated, isFalse);

      online = true;
      requests.clear();
      await auth.playAsGuest();

      expect(requests.map((r) => r.url.path), ['/api/auth/login']);
      expect(auth.user!.id, 'g1');
      expect(auth.isGuest, isTrue);
    });

    test('a rename carries the stored credentials along', () async {
      final api = fakeApi(
        (_) async => signedIn(freshToken, {...guestUser, 'username': 'Zoe'}),
      );
      final storage = guestStorage(validToken);
      final auth = providerWith(api, storage);
      await auth.restore();

      await auth.rename('Zoe');

      expect(storedGuest(storage), credentials(username: 'Zoe'));
      expect(auth.isGuest, isTrue);
    });

    test('a claim erases the stored guest password', () async {
      final requests = <http.Request>[];
      final api = fakeApi(
        (_) async => json({
          'success': true,
          'user': {...guestUser, 'isGuest': false},
        }),
        requests: requests,
      );
      final storage = guestStorage(validToken);
      final auth = providerWith(api, storage);
      await auth.restore();

      await auth.changePassword(
        newPassword: 'mon-secret',
        currentPassword: auth.guestPassword,
      );

      expect(jsonDecode(requests.single.body), {
        'newPassword': 'mon-secret',
        'currentPassword': guestPassword,
      });
      expect(auth.isGuest, isFalse);
      expect(auth.guestPassword, isNull);
      expect(storedGuest(storage), isNull);
      expect(
        (jsonDecode(storage.values[TokenStorage.userKey]!) as Map)['isGuest'],
        isFalse,
      );
      // A 401 now signs out, as any account's
      final unauthorized = errorFixture('error_invalid_token');
      final after = fakeApi(
        (_) async => http.Response(unauthorized.body, unauthorized.status),
      );
      final next = providerWith(after, storage);
      await next.restore();
      await after.get('/party').then((_) {}, onError: (_) {});
      await pumpEventQueue();
      expect(next.isAuthenticated, isFalse);
    });

    test('a sign-in again failing on the network neither creates a new '
        'guest nor loses the stored password', () async {
      final requests = <http.Request>[];
      final api = fakeApi((_) async {
        throw http.ClientException('offline');
      }, requests: requests);
      final storage = MemoryTokenStorage({
        TokenStorage.guestKey: jsonEncode(credentials()),
      });
      final auth = providerWith(api, storage);
      await auth.restore();
      requests.clear();

      await expectLater(
        auth.playAsGuest(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isConnectivity,
            'isConnectivity',
            isTrue,
          ),
        ),
      );

      expect(requests.map((r) => r.url.path), ['/api/auth/login']);
      expect(auth.isAuthenticated, isFalse);
      expect(storedGuest(storage), credentials());
    });

    test(
      'a 5xx on the sign-in again is thrown too, the password kept',
      () async {
        final requests = <http.Request>[];
        final api = fakeApi(
          (_) async =>
              json({'error': 'Login failed', 'code': 'LOGIN_ERROR'}, 500),
          requests: requests,
        );
        final storage = MemoryTokenStorage({
          // Not the last account: the start-up leaves it alone
          TokenStorage.guestKey: jsonEncode(credentials(active: false)),
        });
        final auth = providerWith(api, storage);
        await auth.restore();

        await expectLater(auth.playAsGuest(), throwsA(isA<ApiException>()));

        expect(requests.map((r) => r.url.path), ['/api/auth/login']);
        expect(storedGuest(storage), credentials(active: false));
      },
    );

    test(
      'stored credentials the backend refuses give way to a new guest',
      () async {
        final requests = <http.Request>[];
        final invalid = errorFixture('error_invalid_credentials');
        final api = fakeApi((request) async {
          if (request.url.path == '/api/auth/login') {
            return http.Response(invalid.body, invalid.status);
          }
          return json({
            'success': true,
            'user': {...guestUser, 'id': 'g2', 'username': 'Guest_87654321'},
            'token': jwtExpiringIn(const Duration(days: 7), userId: 'g2'),
            'password': 'An0therGeneratedPassw0rd',
          }, 201);
        }, requests: requests);
        final storage = MemoryTokenStorage({
          // Not the last account: the start-up leaves it alone
          TokenStorage.guestKey: jsonEncode(credentials(active: false)),
        });
        final auth = providerWith(api, storage);
        await auth.restore();

        await auth.playAsGuest();

        expect(requests.map((r) => r.url.path), [
          '/api/auth/login',
          '/api/auth/guest',
        ]);
        expect(auth.user!.id, 'g2');
        expect(storedGuest(storage), {
          'userId': 'g2',
          'username': 'Guest_87654321',
          'password': 'An0therGeneratedPassw0rd',
          'active': true,
        });
      },
    );

    test('after another account signs in and out, the start-up lands on the '
        'login screen, not the guest', () async {
      var online = false;
      final api = fakeApi((request) async {
        if (!online) throw http.ClientException('offline');
        return signedIn(validToken, {
          'id': 'u1',
          'username': 'Vincent',
          'isAdmin': false,
        });
      });
      final storage = guestStorage(expiredToken);

      // The guest's sign-in again fails on the network: its credentials stay
      final offline = providerWith(api, storage);
      await offline.restore();
      expect(offline.isAuthenticated, isFalse);
      expect(storedGuest(storage), credentials());

      // Another account signs in on the device, then out
      online = true;
      await offline.login('Vincent', 'secret1');
      expect(storedGuest(storage), credentials(active: false));
      await offline.logout();
      expect(storedGuest(storage), credentials(active: false));

      // The next start-up asks nothing of the backend: to the login screen
      final asked = <http.Request>[];
      final next = providerWith(
        fakeApi((_) async => signedIn(freshToken), requests: asked),
        storage,
      );
      await next.restore();
      expect(asked, isEmpty);
      expect(next.isRestored, isTrue);
      expect(next.isAuthenticated, isFalse);

      // « Jouer sans compte » still brings that guest back, the last one again
      final back = providerWith(
        fakeApi((_) async => signedIn(freshToken)),
        storage,
      );
      await back.restore();
      expect(back.isAuthenticated, isFalse);
      await back.playAsGuest();
      expect(back.user!.id, 'g1');
      expect(storedGuest(storage), credentials());
    });

    test('signing out erases the credentials: the account is lost', () async {
      final storage = guestStorage(validToken);
      final auth = providerWith(unusedApi(), storage);
      await auth.restore();

      await auth.logout();

      expect(auth.isAuthenticated, isFalse);
      expect(storage.values, isEmpty);
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

    test("keeps a guest's credentials apart from the session", () async {
      SharedPreferences.setMockInitialValues({});
      final storage = PreferencesTokenStorage();
      const guest = GuestCredentials(
        userId: 'g1',
        username: 'Guest_12345',
        password: 'Gen3ratedGuestPassw0rd42',
      );
      await storage.write(
        AuthSession(
          token: validToken,
          user: const User(id: 'g1', username: 'Guest_12345', isGuest: true),
        ),
      );
      await storage.writeGuest(guest);

      expect((await storage.read())!.user.isGuest, isTrue);
      await storage.clear();
      expect(await storage.read(), isNull);
      final kept = await storage.readGuest();
      expect(kept!.toJson(), guest.toJson());

      await storage.clearGuest();
      expect(await storage.readGuest(), isNull);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });
}
