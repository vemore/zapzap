import 'dart:convert';

/// Reads a JWT's payload without checking its signature — the backend does
/// that. The client only needs `exp`, to stop treating an expired session as
/// signed in (the React `ProtectedRoute` never looks at it).
abstract final class Jwt {
  /// The decoded payload, or `null` when [token] is not a JWT.
  static Map<String, dynamic>? payload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// When [token] expires (`exp`, Unix seconds), or `null` when it has no
  /// readable `exp`.
  static DateTime? expiry(String token) {
    final exp = payload(token)?['exp'];
    if (exp is! num) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      (exp * 1000).round(),
      isUtc: true,
    );
  }

  /// Whether [token] is a JWT whose `exp` is after [now] (default: the
  /// current time). The backend always sets `exp` (7 days,
  /// `jwt_service.rs`), so a token without one is not trusted.
  static bool isValid(String? token, {DateTime? now}) {
    if (token == null || token.isEmpty) return false;
    final expiresAt = expiry(token);
    return expiresAt != null && expiresAt.isAfter(now ?? DateTime.now());
  }
}
