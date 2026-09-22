import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/utils/jwt.dart';
import 'package:zapzap/utils/validators.dart';

import 'auth_helpers.dart';

void main() {
  group('validateUsername (auth.js validateUsername)', () {
    test('empty is required', () {
      expect(validateUsername(null), UsernameError.required);
      expect(validateUsername(''), UsernameError.required);
    });

    test('is trimmed, then 3 to 30 characters', () {
      expect(validateUsername('   '), UsernameError.tooShort);
      expect(validateUsername(' ab '), UsernameError.tooShort);
      expect(validateUsername('abc'), isNull);
      expect(validateUsername('  abc  '), isNull);
      expect(validateUsername('a' * 30), isNull);
      expect(validateUsername('a' * 31), UsernameError.tooLong);
    });

    test('letters, digits, hyphens and underscores only', () {
      expect(validateUsername('Bob_the-2nd'), isNull);
      expect(validateUsername('bob smith'), UsernameError.invalidCharacters);
      expect(validateUsername('bob!'), UsernameError.invalidCharacters);
      expect(validateUsername('élodie'), UsernameError.invalidCharacters);
    });
  });

  group('validatePassword (auth.js validatePassword)', () {
    test('empty is required', () {
      expect(validatePassword(null), PasswordError.required);
      expect(validatePassword(''), PasswordError.required);
    });

    test('6 to 100 characters, not trimmed', () {
      expect(validatePassword('12345'), PasswordError.tooShort);
      expect(validatePassword('123456'), isNull);
      expect(validatePassword('      '), isNull);
      expect(validatePassword(' 1234 '), isNull);
      expect(validatePassword('x' * 100), isNull);
      expect(validatePassword('x' * 101), PasswordError.tooLong);
    });
  });

  group('Jwt', () {
    test('reads the payload and exp', () {
      final token = jwt({'userId': 'u1', 'exp': 2000000000});
      expect(Jwt.payload(token), {'userId': 'u1', 'exp': 2000000000});
      expect(
        Jwt.expiry(token),
        DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true),
      );
    });

    test('is valid only before exp', () {
      final token = jwt({'exp': 1000});
      expect(
        Jwt.isValid(
          token,
          now: DateTime.fromMillisecondsSinceEpoch(999000, isUtc: true),
        ),
        isTrue,
      );
      expect(
        Jwt.isValid(
          token,
          now: DateTime.fromMillisecondsSinceEpoch(1000000, isUtc: true),
        ),
        isFalse,
      );
      expect(Jwt.isValid(validToken), isTrue);
      expect(Jwt.isValid(expiredToken), isFalse);
    });

    test('a token that is not a JWT, or has no exp, is not valid', () {
      expect(Jwt.isValid(null), isFalse);
      expect(Jwt.isValid(''), isFalse);
      expect(Jwt.isValid('test-token-auth_login'), isFalse);
      expect(Jwt.isValid('a.%%%.c'), isFalse);
      expect(Jwt.isValid(jwt({'userId': 'u1'})), isFalse);
      expect(Jwt.isValid(jwt({'exp': 'tomorrow'})), isFalse);
      expect(Jwt.payload('a.bm90IGpzb24.c'), isNull);
    });
  });
}
