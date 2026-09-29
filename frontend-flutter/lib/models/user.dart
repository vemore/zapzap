import 'json.dart';

/// The signed-in user, as `/auth/login`, `/auth/register`, `/auth/google`
/// and `PATCH /auth/me` return it. Register sends `createdAt` and no
/// `isAdmin`; login, Google and the rename send one shape: `isAdmin`,
/// `email`, `isGoogleUser` and `hasPassword`.
class User {
  const User({
    required this.id,
    required this.username,
    this.isAdmin = false,
    this.email,
    this.isGoogleUser = false,
    bool? hasPassword,
    this.createdAt,
  }) : hasPassword = hasPassword ?? !isGoogleUser;

  factory User.fromJson(JsonMap json) {
    final isGoogleUser = Json.boolean(json, 'isGoogleUser');
    return User(
      id: Json.string(json, 'id'),
      username: Json.string(json, 'username'),
      isAdmin: Json.boolean(json, 'isAdmin'),
      email: Json.stringOrNull(json, 'email'),
      isGoogleUser: isGoogleUser,
      hasPassword: Json.boolOrNull(json, 'hasPassword'),
      createdAt: Json.timestamp(json, 'createdAt'),
    );
  }

  final String id;
  final String username;
  final bool isAdmin;
  final String? email;
  final bool isGoogleUser;

  /// Signs in with a password. Register does not say: it proves
  /// one. Absent (a session stored before the field), it is taken to be the
  /// case of every account but a Google one, which may have set one since
  /// (`PUT /auth/me/password`).
  final bool hasPassword;
  final DateTime? createdAt;

  /// This user with a password set ([AuthProvider.changePassword]).
  User withPassword() => User(
    id: id,
    username: username,
    isAdmin: isAdmin,
    email: email,
    isGoogleUser: isGoogleUser,
    hasPassword: true,
    createdAt: createdAt,
  );

  /// The shape the auth layer stores and restores.
  JsonMap toJson() => {
    'id': id,
    'username': username,
    'isAdmin': isAdmin,
    if (email != null) 'email': email,
    'isGoogleUser': isGoogleUser,
    'hasPassword': hasPassword,
    if (createdAt != null) 'createdAt': createdAt!.millisecondsSinceEpoch,
  };
}

/// A successful authentication: `{success, user, token, isNewUser?}`.
class AuthSession {
  const AuthSession({
    required this.user,
    required this.token,
    this.isNewUser = false,
  });

  factory AuthSession.fromJson(JsonMap json) => AuthSession(
    user: User.fromJson(Json.map(json, 'user') ?? const {}),
    token: Json.string(json, 'token'),
    isNewUser: Json.boolean(json, 'isNewUser'),
  );

  final User user;

  /// The JWT for `Authorization: Bearer` (valid 7 days).
  final String token;

  /// Google sign-in only: the account was created by this call.
  final bool isNewUser;
}
