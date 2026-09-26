import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../services/api_client.dart';
import '../services/google_sign_in_service.dart';
import '../services/token_storage.dart';
import '../utils/jwt.dart';

/// The session: who is signed in, with which JWT. The counterpart of the
/// React `AuthContext`, plus what it lacks: the token's expiry is checked.
///
/// It keeps [ApiClient.token] in step and owns [ApiClient.onUnauthorized]:
/// a 401 on an authenticated call signs out, and the router — which listens
/// to this notifier — sends the user to the login screen. Others (the SSE
/// connection) follow [token] the same way.
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required this._repository,
    required ApiClient apiClient,
    required this._storage,
    this._google = const DisabledGoogleSignIn(),
    DateTime Function()? clock,
  }) : _api = apiClient,
       _clock = clock ?? DateTime.now {
    _api.onUnauthorized = (_) => logout();
  }

  final AuthRepository _repository;
  final ApiClient _api;
  final TokenStorage _storage;
  final GoogleSignInService _google;
  final DateTime Function() _clock;

  User? _user;
  String? _token;
  bool _isRestored = false;

  /// The signed-in user, `null` when signed out.
  User? get user => _user;

  /// The JWT, `null` when signed out.
  String? get token => _token;

  /// Signed in with a token that has not expired yet.
  bool get isAuthenticated =>
      _user != null && Jwt.isValid(_token, now: _clock());

  bool get isAdmin => isAuthenticated && _user!.isAdmin;

  /// `false` until [restore] has read the stored session: the router waits
  /// for it before deciding where a start-up path leads.
  bool get isRestored => _isRestored;

  /// Reloads the session saved by a previous run. An expired or unreadable
  /// one is erased.
  Future<void> restore() async {
    AuthSession? session;
    try {
      session = await _storage.read();
    } catch (error) {
      debugPrint('Session not restored: $error');
    }
    if (session != null && Jwt.isValid(session.token, now: _clock())) {
      _setSession(session);
    } else if (session != null) {
      await _clearStorage();
    }
    _isRestored = true;
    notifyListeners();
  }

  /// Throws the [ApiException] of a refusal (`INVALID_CREDENTIALS`...).
  Future<void> login(String username, String password) async =>
      _signIn(await _repository.login(username, password));

  /// Throws the [ApiException] of a refusal (`USERNAME_EXISTS`...).
  Future<void> register(String username, String password) async =>
      _signIn(await _repository.register(username, password));

  /// Signs in (or up) with a Google ID token, which the backend checks
  /// against its web client id. Throws the [ApiException] of a refusal
  /// (`GOOGLE_AUTH_FAILED`...).
  Future<void> loginWithGoogle(String credential) async =>
      _signIn(await _repository.loginWithGoogle(credential));

  /// Deletes the signed-in account, confirmed by its [password] or, for a
  /// Google account, a fresh Google ID token ([credential]); then signs out,
  /// which erases the stored session and lets the router show the login
  /// screen. Throws the [ApiException] of a refusal (`INVALID_PASSWORD`,
  /// `ACTIVE_PARTY`...), still signed in.
  Future<void> deleteAccount({String? password, String? credential}) async {
    await _repository.deleteAccount(password: password, credential: credential);
    await logout();
  }

  /// Signs out, of Google too: on a shared device the next person is not
  /// offered this Google account. Idempotent: several 401s in flight each
  /// call it, and only the first does anything.
  Future<void> logout() async {
    if (_token == null && _user == null) return;
    _user = null;
    _token = null;
    _api.token = null;
    notifyListeners();
    _signOutOfGoogle();
    await _clearStorage();
  }

  /// Not awaited: Google may never answer (its script blocked), and the
  /// session is closed either way.
  void _signOutOfGoogle() {
    Future<void>.sync(
      _google.signOut,
    ).catchError((Object error) => debugPrint('Google not signed out: $error'));
  }

  Future<void> _signIn(AuthSession session) async {
    _setSession(session);
    notifyListeners();
    try {
      await _storage.write(session);
    } catch (error) {
      // Signed in for this run all the same.
      debugPrint('Session not saved: $error');
    }
  }

  void _setSession(AuthSession session) {
    _user = session.user;
    _token = session.token;
    _api.token = session.token;
  }

  Future<void> _clearStorage() async {
    try {
      await _storage.clear();
    } catch (error) {
      debugPrint('Session not erased: $error');
    }
  }

  @override
  void dispose() {
    _api.onUnauthorized = null;
    super.dispose();
  }
}
