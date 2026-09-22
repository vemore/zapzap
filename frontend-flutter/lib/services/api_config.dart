import 'package:flutter/foundation.dart';

/// Where the ZapZap backend lives.
///
/// Resolution order:
/// 1. `--dart-define=API_BASE_URL=<url>` at build or run time;
/// 2. on the web, the origin the page was served from: the PWA is served
///    under `/app/` on the same domain as the API, so no CORS is involved;
/// 3. elsewhere (Android), the public production URL.
class ApiConfig {
  const ApiConfig(this.baseUrl);

  /// The public production URL, the default outside the web.
  static const String productionUrl = 'https://zapzap.ombivince.synology.me';

  /// The value of `--dart-define=API_BASE_URL`, empty when not given.
  static const String definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The backend origin, without a trailing slash (`https://host[:port]`).
  final String baseUrl;

  /// The configuration for this build and platform.
  factory ApiConfig.fromEnvironment() => ApiConfig.resolve(
    defined: definedBaseUrl,
    isWeb: kIsWeb,
    pageUri: Uri.base,
  );

  /// The resolution itself, with its inputs explicit so tests can drive it.
  factory ApiConfig.resolve({
    required String defined,
    required bool isWeb,
    required Uri pageUri,
  }) {
    final String base;
    if (defined.trim().isNotEmpty) {
      base = defined.trim();
    } else if (isWeb) {
      base = pageUri.origin;
    } else {
      base = productionUrl;
    }
    return ApiConfig(_stripTrailingSlashes(base));
  }

  /// The URL of an API route: `apiUri('/auth/login')` is `<base>/api/auth/login`.
  Uri apiUri(String path, [Map<String, String>? query]) {
    final route = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$baseUrl/api$route');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  /// The server-sent events stream (the historical spelling is the backend's).
  Uri get sseUri => Uri.parse('$baseUrl/suscribeupdate');

  static String _stripTrailingSlashes(String url) {
    var result = url;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
