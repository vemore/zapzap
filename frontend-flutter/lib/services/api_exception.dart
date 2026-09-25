import 'dart:convert';

/// Error codes. The backend's own codes pass through unchanged (a few are
/// named here for the screens that react to them); the others are made up by
/// the client when the backend sent no `code`, or sent nothing at all.
abstract final class ApiErrorCode {
  // Client-side.
  /// No connection, DNS failure, refused connection, CORS on the web.
  static const network = 'NETWORK_ERROR';

  /// No answer within the client timeout (10 s by default).
  static const timeout = 'TIMEOUT';

  /// A 2xx whose body is not a JSON object.
  static const invalidResponse = 'INVALID_RESPONSE';

  // From the status, when the body has no `code`.
  static const badRequest = 'BAD_REQUEST'; // 400
  static const unauthorized = 'UNAUTHORIZED'; // 401 (Rust: bare, no body)
  static const forbidden = 'FORBIDDEN'; // 403
  static const notFound = 'NOT_FOUND'; // 404
  static const conflict = 'CONFLICT'; // 409
  static const serverError = 'SERVER_ERROR'; // 5xx

  // Backend codes the client reacts to.
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const missingCredentials = 'MISSING_CREDENTIALS';
  static const usernameExists = 'USERNAME_EXISTS';
  static const invalidToken = 'INVALID_TOKEN';
  static const missingAuthHeader = 'MISSING_AUTH_HEADER';
  static const adminRequired = 'ADMIN_REQUIRED';
  static const partyNotFound = 'PARTY_NOT_FOUND';
  static const partyFull = 'PARTY_FULL';
  static const notYourTurn = 'NOT_YOUR_TURN';
  static const handTooHigh = 'HAND_TOO_HIGH';

  /// The code for a status when the body did not carry one.
  static String fromStatus(int status) => switch (status) {
    400 => badRequest,
    401 => unauthorized,
    403 => forbidden,
    404 => notFound,
    409 => conflict,
    >= 500 => serverError,
    _ => 'HTTP_$status',
  };
}

/// A failed API call.
///
/// Reads every error shape the backend sends (`zapzap-rust/src/api/`):
/// - `{error, code, details?}` — auth, party, game (`error.rs`, the auth
///   middleware);
/// - `{success: false, error, code}` — the admin middleware's 401 and 403;
/// - `{success: false, error}` or `{error}` — the admin routes' refusals,
///   stats, history: [code] comes from the status;
/// - `{error, code, path, message}` — the 404 of a path no route serves
///   (`not_found.rs`): [message] is `error`;
/// - and, from whatever stands in front of it (a proxy, the platform), a body
///   that is not JSON, `{message}` alone, or no body at all.
///
/// [message] is the backend's text, for logs: screens show a localised text
/// chosen from [code], never [message] (no user-facing literal outside
/// `lib/l10n/`).
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    this.message = '',
    this.details,
  });

  /// From a non-2xx response.
  factory ApiException.fromResponse(int status, String body) {
    Object? decoded;
    if (body.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
    }
    if (decoded is! Map) {
      return ApiException(
        status: status,
        code: ApiErrorCode.fromStatus(status),
        message: decoded is String ? decoded : '',
      );
    }
    final code = decoded['code'];
    final error = decoded['error'];
    final message = decoded['message'];
    return ApiException(
      status: status,
      code: code is String && code.isNotEmpty
          ? code
          : ApiErrorCode.fromStatus(status),
      message: error is String
          ? error
          : message is String
          ? message
          : '',
      details: decoded['details'],
    );
  }

  /// The request never got an answer.
  factory ApiException.network(Object error) => ApiException(
    status: 0,
    code: ApiErrorCode.network,
    message: error.toString(),
  );

  factory ApiException.timeout(Duration after) => ApiException(
    status: 0,
    code: ApiErrorCode.timeout,
    message: 'No response after ${after.inSeconds} s',
  );

  /// The HTTP status, `0` when there was no response.
  final int status;

  /// The backend's `code`, else one of [ApiErrorCode].
  final String code;

  /// The backend's `error` (or `message`), empty when it sent none.
  final String message;

  /// The backend's `details`: a string (the underlying error of a 500) or an
  /// object (`{expected: "Bearer <token>"}`).
  final Object? details;

  bool get isUnauthorized => status == 401;

  /// No response at all: offline, timeout.
  bool get isConnectivity => status == 0;

  @override
  String toString() => 'ApiException($status $code: $message)';
}
