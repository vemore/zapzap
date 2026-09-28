import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:zapzap/providers/auth_provider.dart';
import 'package:zapzap/repositories/auth_repository.dart';
import 'package:zapzap/services/google_sign_in_service.dart';

import 'auth_helpers.dart';

/// The Android side of `google_sign_in`, replaced: [authenticate] answers
/// [result] or throws [error]; [init] throws [initError].
class _FakePlatform extends GoogleSignInPlatform {
  InitParameters? initParams;
  Object? initError;
  int signOuts = 0;
  Object? error;
  AuthenticationResults? result;

  @override
  Future<void> init(InitParameters params) async {
    initParams = params;
    if (initError != null) throw initError!;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<void> signOut(SignOutParams params) async => signOuts++;

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    if (error != null) throw error!;
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AuthenticationResults _results(String idToken) => AuthenticationResults(
  user: const GoogleSignInUserData(email: 'v@example.com', id: 'g1'),
  authenticationTokens: AuthenticationTokenData(idToken: idToken),
);

void main() {
  const webId = '1234-abc.apps.googleusercontent.com';
  late _FakePlatform platform;
  late PluginGoogleSignInService service;
  late List<String> tokens;
  late List<Object> errors;
  StreamSubscription<String>? subscription;

  setUp(() async {
    platform = _FakePlatform();
    GoogleSignInPlatform.instance = platform;
    service = PluginGoogleSignInService(
      const GoogleSignInConfig(serverClientId: webId),
    );
    tokens = [];
    errors = [];
    subscription = service.idTokens.listen(tokens.add, onError: errors.add);
    await pumpEventQueue();
  });

  tearDown(() => subscription?.cancel());

  test('Android initialises with the web client id as serverClientId, and '
      'draws its own button', () {
    expect(platform.initParams?.serverClientId, webId);
    expect(platform.initParams?.clientId, isNull);
  });

  test('a completed sign-in puts its ID token on idTokens', () async {
    platform.result = _results('google-id-token');
    await service.signIn();
    await pumpEventQueue();
    expect(tokens, ['google-id-token']);
    expect(errors, isEmpty);
  });

  test('a closed dialog: nothing on idTokens, signIn does not throw', () async {
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.canceled,
    );
    await service.signIn();
    await pumpEventQueue();
    expect(tokens, isEmpty);
    expect(errors, isEmpty);
  });

  test('a Google failure is a GoogleSignInFailure on idTokens, once', () async {
    platform.error = const GoogleSignInException(
      code: GoogleSignInExceptionCode.clientConfigurationError,
      description: 'unknown SHA-1',
    );
    await service.signIn();
    await pumpEventQueue();
    expect(errors, [isA<GoogleSignInFailure>()]);
  });

  test('any other failure of authenticate is thrown by signIn as a '
      'GoogleSignInFailure', () async {
    platform.error = PlatformException(code: 'boom');
    await expectLater(service.signIn(), throwsA(isA<GoogleSignInFailure>()));
  });

  test(
    'a failed initialisation is thrown by signIn as a GoogleSignInFailure',
    () async {
      await subscription?.cancel();
      subscription = null;
      platform.initError = StateError('init failed');
      final fresh = PluginGoogleSignInService(
        const GoogleSignInConfig(serverClientId: webId),
      );
      await expectLater(fresh.signIn(), throwsA(isA<GoogleSignInFailure>()));
    },
  );

  test('ready completes once initialised', () async {
    await expectLater(service.ready(), completes);
  });

  test('a failed initialisation fails ready and puts nothing on idTokens: '
      'the section hides itself, no error shown', () async {
    await subscription?.cancel();
    platform.initError = StateError('init failed');
    final fresh = PluginGoogleSignInService(
      const GoogleSignInConfig(serverClientId: webId),
    );
    subscription = fresh.idTokens.listen(tokens.add, onError: errors.add);
    await expectLater(fresh.ready(), throwsStateError);
    await pumpEventQueue();
    expect(tokens, isEmpty);
    expect(errors, isEmpty);
  });

  test('signOut signs the plugin out once initialised', () async {
    await service.signOut();
    expect(platform.signOuts, 1);
  });

  group('signOut before any use in this run (a restored session)', () {
    setUp(() async {
      await subscription?.cancel();
      subscription = null;
      platform = _FakePlatform();
      GoogleSignInPlatform.instance = platform;
    });

    test('Android initialises Google, then signs it out', () async {
      final unused = PluginGoogleSignInService(
        const GoogleSignInConfig(serverClientId: webId),
      );
      await unused.signOut();
      expect(platform.initParams?.serverClientId, webId);
      expect(platform.signOuts, 1);
    });

    test('the web neither loads GIS nor signs out: nothing to undo', () async {
      final unused = PluginGoogleSignInService(
        const GoogleSignInConfig(clientId: webId),
      );
      await unused.signOut();
      expect(platform.initParams, isNull);
      expect(platform.signOuts, 0);
    });

    test('the web signs out once GIS is loaded in this run', () async {
      final used = PluginGoogleSignInService(
        const GoogleSignInConfig(clientId: webId),
      );
      await used.ready();
      await used.signOut();
      expect(platform.signOuts, 1);
    });

    test('an Android initialisation that fails is thrown by signOut, which '
        'the logout only logs', () async {
      platform.initError = StateError('no Play services');
      final unused = PluginGoogleSignInService(
        const GoogleSignInConfig(serverClientId: webId),
      );
      await expectLater(unused.signOut(), throwsStateError);
      expect(platform.signOuts, 0);
    });

    AuthProvider restoredWith(GoogleSignInService google) {
      final api = unusedApi();
      return AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: storedSession(validToken),
        google: google,
      );
    }

    test('logout after a restored session reaches the platform\'s signOut on '
        'Android', () async {
      final auth = restoredWith(
        PluginGoogleSignInService(
          const GoogleSignInConfig(serverClientId: webId),
        ),
      );
      await auth.restore();
      expect(auth.isAuthenticated, isTrue);
      expect(platform.initParams, isNull);

      await auth.logout();
      await pumpEventQueue();

      expect(platform.initParams?.serverClientId, webId);
      expect(platform.signOuts, 1);
    });

    test(
      'logout after a restored session leaves Google alone on the web',
      () async {
        final auth = restoredWith(
          PluginGoogleSignInService(const GoogleSignInConfig(clientId: webId)),
        );
        await auth.restore();

        await auth.logout();
        await pumpEventQueue();

        expect(auth.isAuthenticated, isFalse);
        expect(platform.initParams, isNull);
        expect(platform.signOuts, 0);
      },
    );
  });
}
