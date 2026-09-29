import '../models/user.dart';
import '../services/api_client.dart';

/// `/api/auth`. Every call but the `/auth/me` ones ([rename],
/// [changePassword], [deleteAccount]) is unauthenticated: a 401 there is a
/// wrong password, not an expired session.
class AuthRepository {
  const AuthRepository(this._api);

  final ApiClient _api;

  /// `POST /auth/login` → 401 `INVALID_CREDENTIALS`, 400 `MISSING_CREDENTIALS`.
  Future<AuthSession> login(String username, String password) async =>
      AuthSession.fromJson(
        await _api.post(
          '/auth/login',
          body: {'username': username, 'password': password},
          authenticated: false,
        ),
      );

  /// `POST /auth/register` → 409 `USERNAME_EXISTS`. The returned user has no
  /// `isAdmin` (a new account never is).
  Future<AuthSession> register(String username, String password) async =>
      AuthSession.fromJson(
        await _api.post(
          '/auth/register',
          body: {'username': username, 'password': password},
          authenticated: false,
        ),
      );

  /// `POST /auth/google` with a Google ID token → 401 `GOOGLE_AUTH_FAILED` for a token it refuses, 400
  /// `MISSING_CREDENTIAL` for none. A new Google user is created on
  /// the way (`isNewUser`, not read).
  Future<AuthSession> loginWithGoogle(String credential) async =>
      AuthSession.fromJson(
        await _api.post(
          '/auth/google',
          body: {'credential': credential},
          authenticated: false,
        ),
      );

  /// `PATCH /auth/me`, signed in: the account takes [username] (sign-up's
  /// rules) and the answer a new token carrying it → 409 `USERNAME_EXISTS`,
  /// 400 `VALIDATION_ERROR`.
  Future<AuthSession> rename(String username) async => AuthSession.fromJson(
    await _api.patch('/auth/me', body: {'username': username}),
  );

  /// `PUT /auth/me/password`, signed in: [newPassword], confirmed as
  /// [deleteAccount] is — by [currentPassword], or for a Google account
  /// without one by a fresh Google ID token ([credential]), which sets its
  /// first password. Never a 401 for a wrong confirmation: 403
  /// `INVALID_PASSWORD` or `GOOGLE_AUTH_FAILED`, 400 `MISSING_CONFIRMATION`
  /// or `VALIDATION_ERROR`.
  Future<void> changePassword({
    required String newPassword,
    String? currentPassword,
    String? credential,
  }) => _api.put(
    '/auth/me/password',
    body: {
      'newPassword': newPassword,
      'currentPassword': ?currentPassword,
      'credential': ?credential,
    },
  );

  /// `DELETE /auth/me`, signed in, confirmed by the account's [password] or,
  /// for a Google account, a fresh Google ID token ([credential]). A refusal
  /// is never a 401, so it does not sign out: 403 `INVALID_PASSWORD` or
  /// `GOOGLE_AUTH_FAILED`, 400 `MISSING_CONFIRMATION`, 409 `ACTIVE_PARTY`
  /// (seated in or owning a game not finished) or `LAST_ADMIN`.
  Future<void> deleteAccount({String? password, String? credential}) =>
      _api.delete(
        '/auth/me',
        body: {'password': ?password, 'credential': ?credential},
      );
}
