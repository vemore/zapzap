import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_sign_in_button_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_button_web.dart'
    as platform;
import 'google_sign_in_script_stub.dart'
    if (dart.library.js_interop) 'google_sign_in_script_web.dart'
    as script;

/// Which Google OAuth client asks for the ID token, for this build and
/// platform. The backend checks the token's audience against
/// the **web** client id, so both platforms name that one:
///
/// - on the web, as the Google Identity Services `clientId`, as the React
///   client does (`GoogleLoginButton.jsx`);
/// - on Android, as `serverClientId`: the token is then issued for the web
///   client. Android identifies the app itself by its package name and the
///   SHA-1 of its signing key, registered as an Android OAuth client in the
///   same Google Cloud project (`.llmwiki/FrontendFlutter.md`).
///
/// No `--dart-define=GOOGLE_CLIENT_ID` → no Google sign-in at all.
class GoogleSignInConfig {
  const GoogleSignInConfig({this.clientId, this.serverClientId});

  /// Google sign-in turned off.
  const GoogleSignInConfig.disabled() : this();

  /// The value of `--dart-define=GOOGLE_CLIENT_ID`, empty when not given.
  static const String definedClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
  );

  /// The client id the web flow asks with, `null` off the web.
  final String? clientId;

  /// The client id the Android flow asks the token for, `null` off Android.
  final String? serverClientId;

  bool get enabled => clientId != null || serverClientId != null;

  /// The configuration for this build and platform.
  factory GoogleSignInConfig.fromEnvironment() => GoogleSignInConfig.resolve(
    webClientId: definedClientId,
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// The resolution itself, with its inputs explicit so tests can drive it.
  factory GoogleSignInConfig.resolve({
    required String webClientId,
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    final id = webClientId.trim();
    if (id.isEmpty) return const GoogleSignInConfig.disabled();
    if (isWeb) return GoogleSignInConfig(clientId: id);
    if (platform == TargetPlatform.android) {
      return GoogleSignInConfig(serverClientId: id);
    }
    return const GoogleSignInConfig.disabled();
  }
}

/// A Google sign-in that did not complete for another reason than the user
/// closing it (that one is silent).
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure(this.message);

  final String message;

  @override
  String toString() => 'GoogleSignInFailure: $message';
}

/// Obtains a Google ID token, to be posted to `POST /auth/google`. Behind an
/// interface so widget tests replace Google with a fake.
///
/// Every token arrives on [idTokens], however the sign-in started: on the
/// web Google draws its own button ([platformButton]) and runs the flow
/// itself; on Android the app draws the button and calls [signIn].
abstract class GoogleSignInService {
  /// `false` when the build has no client id: the button is hidden.
  bool get enabled;

  /// Completes once Google is ready to sign in; fails if it cannot be. On the
  /// web it may never complete: Google's script blocked or unreachable. The
  /// section therefore waits for it with a timeout
  /// (`GoogleSignInSection.readyTimeout`).
  Future<void> ready();

  /// The ID token of each completed sign-in. An error is a
  /// [GoogleSignInFailure]; a sign-in the user closes emits nothing.
  Stream<String> get idTokens;

  /// Google's own button when the platform requires it (the web), else
  /// `null` and the app draws one that calls [signIn]. Build it once and keep
  /// the instance: the web button re-renders Google's iframe whenever a new
  /// one replaces it.
  Widget? platformButton(BuildContext context);

  /// Starts a sign-in; completes when it is over, its token on [idTokens].
  /// Throws a [GoogleSignInFailure] for a failure [idTokens] does not carry.
  Future<void> signIn();

  /// Forgets the Google account on this device, so the next person is not
  /// offered it. Called on logout; a no-op when Google was never used.
  Future<void> signOut();
}

/// No client id: nothing to show, nothing to do.
class DisabledGoogleSignIn implements GoogleSignInService {
  const DisabledGoogleSignIn();

  @override
  bool get enabled => false;

  @override
  Stream<String> get idTokens => const Stream.empty();

  @override
  Future<void> ready() async {}

  @override
  Widget? platformButton(BuildContext context) => null;

  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() async {}
}

/// The `google_sign_in` plugin (Google Identity Services on the web,
/// Credential Manager on Android), initialised once on first use.
///
/// On the web, Google's GIS script is held back by `web/index.html` until
/// the first use releases it ([script.loadGoogleScript]): a build without a
/// client id, or a session that never shows the login screen, never contacts
/// accounts.google.com.
class PluginGoogleSignInService implements GoogleSignInService {
  PluginGoogleSignInService(this.config);

  final GoogleSignInConfig config;
  Future<void>? _initialized;

  static GoogleSignIn get _google => GoogleSignIn.instance;

  Future<void> _initialize() => _initialized ??= () {
    script.loadGoogleScript();
    return _google.initialize(
      clientId: config.clientId,
      serverClientId: config.serverClientId,
    );
  }();

  @override
  bool get enabled => config.enabled;

  @override
  Future<void> ready() => _initialize();

  // A failed initialisation is reported by [ready], which hides the section,
  // and by [signIn]: not here as well.
  @override
  Stream<String> get idTokens => Stream.fromFuture(
    _initialize().then((_) => true, onError: (Object _) => false),
  ).asyncExpand((ok) => ok ? _signIns : const Stream<String>.empty());

  Stream<String> get _signIns => _google.authenticationEvents.transform(
    StreamTransformer.fromHandlers(
      handleData: (event, sink) {
        if (event is! GoogleSignInAuthenticationEventSignIn) return;
        final token = event.user.authentication.idToken;
        if (token == null || token.isEmpty) {
          sink.addError(const GoogleSignInFailure('no ID token'));
        } else {
          sink.add(token);
        }
      },
      // A failure does not end the stream: the next sign-in still arrives.
      handleError: (error, stack, sink) {
        if (!_isCancel(error)) sink.addError(_failure(error), stack);
      },
    ),
  );

  @override
  Widget? platformButton(BuildContext context) =>
      _google.supportsAuthenticate() ? null : platform.googleButton(context);

  @override
  Future<void> signIn() async {
    try {
      await _initialize();
      await _google.authenticate();
    } on GoogleSignInException catch (error) {
      // Already on idTokens: the plugin reports it there too.
      debugPrint('Google sign-in: $error');
    } catch (error) {
      // Not on idTokens (an initialisation or platform failure): the caller
      // shows it.
      throw _failure(error);
    }
  }

  @override
  Future<void> signOut() async {
    // Never initialised: no account to forget (and the web plugin would wait
    // for an initialisation that never comes).
    final initialized = _initialized;
    if (initialized == null) return;
    await initialized;
    await _google.signOut();
  }

  static bool _isCancel(Object error) =>
      error is GoogleSignInException &&
      (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted);

  static Object _failure(Object error) => error is GoogleSignInException
      ? GoogleSignInFailure('${error.code.name}: ${error.description}')
      : GoogleSignInFailure('$error');
}
