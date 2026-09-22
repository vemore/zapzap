import 'package:shared_preferences/shared_preferences.dart';

import 'token_storage.dart';

/// The web: `shared_preferences`, i.e. the browser's localStorage. The web
/// has no secure store worth the name; the React client keeps the same token
/// in localStorage.
TokenStorage createTokenStorage() => PreferencesTokenStorage();

class PreferencesTokenStorage extends TokenStorage {
  @override
  Future<String?> readKey(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeKey(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> deleteKey(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
