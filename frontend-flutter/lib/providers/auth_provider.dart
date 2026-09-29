import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../repositories/auth_repository.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
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
///
/// A guest ([playAsGuest]) is signed back in without a word when its token
/// has expired or is refused: its credentials stay stored
/// ([TokenStorage.guestKey]) until the player signs out, deletes the account
/// or claims it with a password of their own ([changePassword]).
class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required this._repository,
    required ApiClient apiClient,
    required this._storage,
    this._google = const DisabledGoogleSignIn(),
    DateTime Function()? clock,
  }) : _api = apiClient,
       _clock = clock ?? DateTime.now {
    _api.onUnauthorized = (_) => _unauthorized();
  }

  final AuthRepository _repository;
  final ApiClient _api;
  final TokenStorage _storage;
  final GoogleSignInService _google;
  final DateTime Function() _clock;

  User? _user;
  String? _token;
  bool _isRestored = false;

  /// This device's guest account, `null` when it has none.
  GuestCredentials? _guest;

  /// The guest sign-in under way, which parallel 401s share.
  Future<bool>? _resuming;

  /// The signed-in user, `null` when signed out.
  User? get user => _user;

  /// The JWT, `null` when signed out.
  String? get token => _token;

  /// Signed in with a token that has not expired yet.
  bool get isAuthenticated =>
      _user != null && Jwt.isValid(_token, now: _clock());

  bool get isAdmin => isAuthenticated && _user!.isAdmin;

  /// Signed in as a guest account, not yet claimed.
  bool get isGuest => _user?.isGuest ?? false;

  /// The password the backend generated for the signed-in guest account:
  /// what confirms a password change or a deletion in its name, the player
  /// never having seen it. `null` when this device keeps none for it.
  String? get guestPassword {
    final guest = _guest;
    return guest != null && guest.userId == _user?.id ? guest.password : null;
  }

  /// `false` until [restore] has read the stored session: the router waits
  /// for it before deciding where a start-up path leads.
  bool get isRestored => _isRestored;

  /// Reloads the session saved by a previous run. An expired or unreadable
  /// one is erased; the guest's is replaced by a new sign-in with its stored
  /// credentials, when the backend answers.
  Future<void> restore() async {
    AuthSession? session;
    try {
      session = await _storage.read();
    } catch (error) {
      debugPrint('Session not restored: $error');
    }
    try {
      _guest = await _storage.readGuest();
    } catch (error) {
      debugPrint('Guest account not read: $error');
    }
    if (session != null && Jwt.isValid(session.token, now: _clock())) {
      _setSession(session);
    } else {
      if (session != null) await _clearStorage();
      // Another account's expired session is that account's: to the login
      // screen, as for anyone.
      if (session == null || session.user.id == _guest?.userId) {
        await _resumeGuest();
      }
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

  /// Plays without an account: signs this device's guest account back in,
  /// or creates one (`POST /auth/guest`) and keeps its credentials. Throws
  /// the [ApiException] of a refusal (`RATE_LIMITED`...).
  Future<void> playAsGuest() async {
    if (_guest != null && await _resumeGuest()) return;
    final guest = await _repository.createGuest();
    final user = guest.session.user;
    _guest = GuestCredentials(
      userId: user.id,
      username: user.username,
      password: guest.password,
    );
    await _writeGuest();
    await _signIn(guest.session);
  }

  /// Renames the signed-in account. The token names the user, so the new one
  /// the backend answers replaces it, stored as a sign-in's is; a guest's
  /// stored credentials follow the new name. Throws the [ApiException] of a
  /// refusal (`USERNAME_EXISTS`, `VALIDATION_ERROR`), unchanged.
  Future<void> rename(String username) async {
    final session = await _repository.rename(username);
    final guest = _guest;
    if (guest != null && guest.userId == session.user.id) {
      _guest = guest.renamed(session.user.username);
      await _writeGuest();
    }
    await _signIn(session);
  }

  /// Sets the signed-in account's password to [newPassword], confirmed by
  /// [currentPassword] (a guest's: [guestPassword]) or, for a Google account
  /// without one, a fresh Google ID token ([credential]); the session goes
  /// on, and remembers the account has a password now. A guest's account is
  /// claimed: the player's own from now on, its generated password erased
  /// from the device. Throws the [ApiException] of a refusal
  /// (`INVALID_PASSWORD`, `GOOGLE_AUTH_FAILED`...), unchanged.
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? credential,
  }) async {
    final answered = await _repository.changePassword(
      newPassword: newPassword,
      currentPassword: currentPassword,
      credential: credential,
    );
    final user = _user;
    final token = _token;
    if (user == null || token == null) return;
    final updated =
        answered ??
        (user.hasPassword && !user.isGuest ? user : user.withPassword());
    if (_guest?.userId == user.id && !updated.isGuest) await _forgetGuest();
    await _signIn(AuthSession(user: updated, token: token));
  }

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
  /// offered this Google account. A guest's credentials are erased: the
  /// account is lost to this device (the menu warns first). Idempotent:
  /// only the first of several calls does anything.
  Future<void> logout() async {
    final user = _user;
    if (user != null && user.id == _guest?.userId) await _forgetGuest();
    await _endSession();
  }

  /// A 401: the session is over. The guest's is signed back in with its
  /// stored credentials; any other ends, a guest's credentials kept.
  Future<void> _unauthorized() async {
    final user = _user;
    if (user != null && user.id == _guest?.userId && await _resumeGuest()) {
      return;
    }
    await _endSession();
  }

  /// Signs the guest back in with its stored credentials (`POST
  /// /auth/login`); `true` when it is. Credentials the backend refuses
  /// (`INVALID_CREDENTIALS`: the account deleted by an admin) are erased; a
  /// network failure keeps them for the next try.
  Future<bool> _resumeGuest() =>
      _resuming ??= _signInAsGuest().whenComplete(() => _resuming = null);

  Future<bool> _signInAsGuest() async {
    final guest = _guest;
    if (guest == null) return false;
    try {
      await _signIn(await _repository.login(guest.username, guest.password));
      return true;
    } catch (error) {
      debugPrint('Guest not signed back in: $error');
      if (error is ApiException &&
          error.code == ApiErrorCode.invalidCredentials) {
        await _forgetGuest();
      }
      return false;
    }
  }

  /// Idempotent: several 401s in flight each call it, and only the first
  /// does anything.
  Future<void> _endSession() async {
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

  Future<void> _writeGuest() async {
    try {
      await _storage.writeGuest(_guest!);
    } catch (error) {
      // Signed in for this run all the same.
      debugPrint('Guest account not saved: $error');
    }
  }

  Future<void> _forgetGuest() async {
    _guest = null;
    try {
      await _storage.clearGuest();
    } catch (error) {
      debugPrint('Guest account not erased: $error');
    }
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
