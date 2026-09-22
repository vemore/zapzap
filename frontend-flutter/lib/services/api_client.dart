import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// The one HTTP client of the app, the counterpart of the React
/// `frontend/src/services/api.js`: every call goes to `<base>/api/...`, as
/// JSON, with `Authorization: Bearer <token>` once signed in, and a 10 s
/// timeout.
///
/// Every failure is an [ApiException]. A 401 on an authenticated call means
/// the session is over: [onUnauthorized] fires (the auth layer clears the
/// session and routes to the login screen), then the exception is thrown.
/// Login and register are sent unauthenticated, so a wrong password never
/// logs anyone out.
class ApiClient {
  ApiClient({
    required this.config,
    http.Client? httpClient,
    this.timeout = defaultTimeout,
    this.token,
    this.onUnauthorized,
  }) : _http = httpClient ?? http.Client();

  static const Duration defaultTimeout = Duration(seconds: 10);

  final ApiConfig config;
  final Duration timeout;
  final http.Client _http;

  /// The JWT sent as `Bearer`; `null` when signed out. Set by the auth layer.
  String? token;

  /// Called with the exception on a 401 to an authenticated call, before it
  /// is thrown. Set by the auth layer.
  void Function(ApiException error)? onUnauthorized;

  Future<JsonMap> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) => _send('GET', path, query: query, authenticated: authenticated);

  Future<JsonMap> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) => _send('POST', path, body: body, authenticated: authenticated);

  Future<JsonMap> delete(String path, {bool authenticated = true}) =>
      _send('DELETE', path, authenticated: authenticated);

  /// Releases the underlying connection pool.
  void close() => _http.close();

  Future<JsonMap> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    required bool authenticated,
  }) async {
    final uri = config.apiUri(
      path,
      query == null || query.isEmpty ? null : query,
    );
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    final bearer = token;
    if (authenticated && bearer != null && bearer.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $bearer';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw ApiException.timeout(timeout);
    } on http.ClientException catch (error) {
      throw ApiException.network(error);
    }

    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = ApiException.fromResponse(response.statusCode, text);
      if (authenticated && error.isUnauthorized) onUnauthorized?.call(error);
      throw error;
    }
    if (text.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      // Falls through.
    }
    throw ApiException(
      status: response.statusCode,
      code: ApiErrorCode.invalidResponse,
      message: 'Expected a JSON object',
    );
  }
}
