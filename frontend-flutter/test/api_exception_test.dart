import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/services/api_exception.dart';

import 'fixtures.dart';

ApiException fromFixture(String name) {
  final error = errorFixture(name);
  return ApiException.fromResponse(error.status, error.body);
}

void main() {
  group('{error, code, details?} — auth, party, game', () {
    final cases = {
      'error_invalid_credentials': (
        401,
        'INVALID_CREDENTIALS',
        'Invalid username or password',
      ),
      'error_missing_credentials': (
        400,
        'MISSING_CREDENTIALS',
        'Username and password are required',
      ),
      'error_missing_auth_header': (
        401,
        'MISSING_AUTH_HEADER',
        'Missing authorization header',
      ),
      'error_invalid_token': (401, 'INVALID_TOKEN', 'Invalid or expired token'),
      'error_party_not_found': (404, 'PARTY_NOT_FOUND', 'Party not found'),
      'error_not_your_turn': (403, 'NOT_YOUR_TURN', 'Not your turn'),
      'error_create_party': (
        400,
        'VALIDATION_ERROR',
        'Player count must be between 3 and 8',
      ),
    };
    cases.forEach((name, expected) {
      test(name, () {
        final error = fromFixture(name);
        expect(error.status, expected.$1);
        expect(error.code, expected.$2);
        expect(error.message, expected.$3);
      });
    });

    test('details is kept: a string for a 500', () {
      final error = ApiException.fromResponse(
        500,
        '{"error":"Failed to create party","code":"CREATE_PARTY_ERROR",'
        '"details":"database is locked"}',
      );
      expect(error.code, 'CREATE_PARTY_ERROR');
      expect(error.details, 'database is locked');
    });

    test('details is kept: an object', () {
      final error = ApiException.fromResponse(
        401,
        '{"error":"Invalid authorization header format",'
        '"code":"INVALID_AUTH_FORMAT","details":{"expected":"Bearer <token>"}}',
      );
      expect(error.code, 'INVALID_AUTH_FORMAT');
      expect(error.details, {'expected': 'Bearer <token>'});
    });

    test('a message with a non-ASCII character', () {
      final error = fromFixture('error_hand_too_high');
      expect(error.code, ApiErrorCode.handTooHigh);
      expect(error.message, contains('≤5'));
    });
  });

  group('{success: false, error, code?} — admin', () {
    test('the admin middleware sends a code', () {
      final error = fromFixture('error_admin_required');
      expect(error.status, 403);
      expect(error.code, ApiErrorCode.adminRequired);
      expect(error.message, 'Admin access required');
    });

    test(
      "an admin route's refusal has none: the code comes from the status",
      () {
        final error = ApiException.fromResponse(
          400,
          '{"success":false,"error":"Cannot modify your own admin status"}',
        );
        expect(error.code, ApiErrorCode.badRequest);
        expect(error.message, 'Cannot modify your own admin status');
      },
    );
  });

  test('{error} alone — history, stats', () {
    final error = fromFixture('error_history_not_found');
    expect(error.status, 404);
    expect(error.code, ApiErrorCode.notFound);
    expect(error.message, 'Party not found');
  });

  test('{error, code, path, message} — a path no route serves: error wins', () {
    final error = fromFixture('error_route_not_found');
    expect(error.code, 'ROUTE_NOT_FOUND');
    expect(error.message, 'Not Found');
  });

  test('{message} alone (not the backend: a proxy)', () {
    final error = ApiException.fromResponse(500, '{"message":"Boom"}');
    expect(error.code, ApiErrorCode.serverError);
    expect(error.message, 'Boom');
  });

  test('a 401 with no body at all (not the backend: a proxy)', () {
    final error = ApiException.fromResponse(401, '');
    expect(error.status, 401);
    expect(error.code, ApiErrorCode.unauthorized);
    expect(error.message, isEmpty);
    expect(error.isUnauthorized, isTrue);
  });

  test('a body that is not JSON (a proxy error page)', () {
    final error = ApiException.fromResponse(502, '<html>Bad Gateway</html>');
    expect(error.code, ApiErrorCode.serverError);
    expect(error.message, isEmpty);
  });

  test('codes from the status', () {
    expect(ApiErrorCode.fromStatus(400), ApiErrorCode.badRequest);
    expect(ApiErrorCode.fromStatus(409), ApiErrorCode.conflict);
    expect(ApiErrorCode.fromStatus(503), ApiErrorCode.serverError);
    expect(ApiErrorCode.fromStatus(418), 'HTTP_418');
  });
}
