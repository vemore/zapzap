/// The account rules of the React client (`frontend/src/services/auth.js`,
/// `validateUsername` and `validatePassword`), as error kinds: screens map
/// them to localised text.
library;

/// Why a username is refused.
enum UsernameError { required, tooShort, tooLong, invalidCharacters }

/// Why a password is refused.
enum PasswordError { required, tooShort, tooLong }

const usernameMinLength = 3;
const usernameMaxLength = 30;
const passwordMinLength = 6;
const passwordMaxLength = 100;

final _usernamePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// `null` when [username] is acceptable. Empty is [UsernameError.required];
/// otherwise it is trimmed first, as in React, so a blank one is
/// [UsernameError.tooShort].
UsernameError? validateUsername(String? username) {
  if (username == null || username.isEmpty) return UsernameError.required;
  final trimmed = username.trim();
  if (trimmed.length < usernameMinLength) return UsernameError.tooShort;
  if (trimmed.length > usernameMaxLength) return UsernameError.tooLong;
  if (!_usernamePattern.hasMatch(trimmed)) {
    return UsernameError.invalidCharacters;
  }
  return null;
}

/// `null` when [password] is acceptable. Not trimmed: spaces count.
PasswordError? validatePassword(String? password) {
  if (password == null || password.isEmpty) return PasswordError.required;
  if (password.length < passwordMinLength) return PasswordError.tooShort;
  if (password.length > passwordMaxLength) return PasswordError.tooLong;
  return null;
}
