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

  Future<void> clear() async {
    await deleteKey(tokenKey);
    await deleteKey(userKey);
  }
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
