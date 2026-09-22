import 'json.dart';

/// The signed-in user, as `/auth/login`, `/auth/register` and `/auth/google`
/// return it. Register sends `createdAt` and no `isAdmin`; login sends
/// `isAdmin`; Google adds `email` and `isGoogleUser`.
class User {
  const User({
    required this.id,
    required this.username,
    this.isAdmin = false,
    this.email,
    this.isGoogleUser = false,
    this.createdAt,
  });

  factory User.fromJson(JsonMap json) => User(
    id: Json.string(json, 'id'),
    username: Json.string(json, 'username'),
    isAdmin: Json.boolean(json, 'isAdmin'),
    email: Json.stringOrNull(json, 'email'),
    isGoogleUser: Json.boolean(json, 'isGoogleUser'),
    createdAt: Json.timestamp(json, 'createdAt'),
  );

  final String id;
  final String username;
  final bool isAdmin;
  final String? email;
  final bool isGoogleUser;
  final DateTime? createdAt;

  /// The shape the auth layer stores and restores.
  JsonMap toJson() => {
    'id': id,
    'username': username,
    'isAdmin': isAdmin,
    if (email != null) 'email': email,
    'isGoogleUser': isGoogleUser,
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

  /// The JWT for `Authorization: Bearer` (24 h on Node, 7 days on Rust).
  final String token;

  /// Google sign-in only: the account was created by this call.
  final bool isNewUser;
}
