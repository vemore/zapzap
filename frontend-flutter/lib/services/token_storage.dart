import 'dart:convert';

import '../models/user.dart';
import 'token_storage_io.dart'
    if (dart.library.js_interop) 'token_storage_web.dart'
    as platform;

/// Where the session survives a restart: the JWT under `token` and the user
/// as JSON under `user`, the keys of the React client (`services/auth.js`).
///
/// [TokenStorage.platform] is `flutter_secure_storage` on Android
/// (`token_storage_io.dart`) and `shared_preferences` on the web
/// (`token_storage_web.dart`, the browser's localStorage, where the plugin
/// prefixes the keys with `flutter.` — no clash with the React client's own
/// `token` on the same origin).
abstract class TokenStorage {
  const TokenStorage();

  /// The storage of the platform the app runs on.
  factory TokenStorage.platform() => platform.createTokenStorage();

  static const tokenKey = 'token';
  static const userKey = 'user';

  /// A guest account's credentials ([GuestCredentials], JSON): the password
  /// the backend answered once, which signs the guest back in when its token
  /// has expired. Kept apart from the session: an expired or refused session
  /// is erased ([clear]), the guest's way back in is not — only signing out,
  /// deleting the account or claiming it ([clearGuest]) erases it.
  static const guestKey = 'guest';

  /// The raw value under [key], `null` when absent.
  Future<String?> readKey(String key);
  Future<void> writeKey(String key, String value);
  Future<void> deleteKey(String key);

  /// The stored session, or `null` when there is none or it is unreadable
  /// (a missing token, a corrupted user).
  Future<AuthSession?> read() async {
    final token = await readKey(tokenKey);
    final userText = await readKey(userKey);
    if (token == null || token.isEmpty || userText == null) return null;
    try {
      final decoded = jsonDecode(userText);
      if (decoded is! Map) return null;
      return AuthSession(
        token: token,
        user: User.fromJson(decoded.cast<String, dynamic>()),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    await writeKey(tokenKey, session.token);
    await writeKey(userKey, jsonEncode(session.user.toJson()));
  }

  /// Erases the session; the guest's credentials stay.
  Future<void> clear() async {
    await deleteKey(tokenKey);
    await deleteKey(userKey);
  }

  /// The stored guest credentials, `null` when there are none or they are
  /// unreadable.
  Future<GuestCredentials?> readGuest() async {
    final text = await readKey(guestKey);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return GuestCredentials.fromJson(decoded.cast<String, dynamic>());
    } on FormatException {
      return null;
    }
  }

  Future<void> writeGuest(GuestCredentials guest) =>
      writeKey(guestKey, jsonEncode(guest.toJson()));

  Future<void> clearGuest() => deleteKey(guestKey);
}

/// How a guest account signs in: its id (whose account they are), its
/// current username (a rename follows) and the password the backend
/// generated. Secure storage on Android; on the web, the browser's
/// localStorage — the account lives only in that browser.
class GuestCredentials {
  const GuestCredentials({
    required this.userId,
    required this.username,
    required this.password,
  });

  factory GuestCredentials.fromJson(Map<String, dynamic> json) {
    final userId = json['userId'];
    final username = json['username'];
    final password = json['password'];
    if (userId is! String || username is! String || password is! String) {
      throw const FormatException('Incomplete guest credentials');
    }
    return GuestCredentials(
      userId: userId,
      username: username,
      password: password,
    );
  }

  final String userId;
  final String username;
  final String password;

  GuestCredentials renamed(String username) =>
      GuestCredentials(userId: userId, username: username, password: password);

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'username': username,
    'password': password,
  };
}

/// A [TokenStorage] that forgets everything on restart; for tests.
class MemoryTokenStorage extends TokenStorage {
  MemoryTokenStorage([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  @override
  Future<String?> readKey(String key) async => values[key];

  @override
  Future<void> writeKey(String key, String value) async => values[key] = value;

  @override
  Future<void> deleteKey(String key) async => values.remove(key);
}
