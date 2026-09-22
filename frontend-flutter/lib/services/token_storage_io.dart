import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

/// Android (and any non-web platform): the Keystore-backed secure storage.
TokenStorage createTokenStorage() => SecureTokenStorage();

class SecureTokenStorage extends TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readKey(String key) => _storage.read(key: key);

  @override
  Future<void> writeKey(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> deleteKey(String key) => _storage.delete(key: key);
}
