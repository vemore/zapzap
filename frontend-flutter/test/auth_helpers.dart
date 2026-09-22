import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/api_config.dart';
import 'package:zapzap/services/token_storage.dart';

import 'fixtures.dart';

const testConfig = ApiConfig('http://localhost:9999');

String _segment(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An unsigned JWT with these claims; the client never checks signatures.
String jwt(Map<String, Object?> claims) =>
    '${_segment({'alg': 'HS256', 'typ': 'JWT'})}.${_segment(claims)}.sig';

/// A JWT expiring [from] now (negative: already expired).
String jwtExpiringIn(Duration from, {String userId = 'u1'}) => jwt({
  'userId': userId,
  'exp': DateTime.now().add(from).millisecondsSinceEpoch ~/ 1000,
});

final validToken = jwtExpiringIn(const Duration(hours: 24));
final expiredToken = jwtExpiringIn(const Duration(hours: -1));

/// A storage already holding a session for [username].
MemoryTokenStorage storedSession(
  String token, {
  String username = 'Vincent',
  bool isAdmin = false,
}) => MemoryTokenStorage({
  TokenStorage.tokenKey: token,
  TokenStorage.userKey: jsonEncode({
    'id': 'u1',
    'username': username,
    'isAdmin': isAdmin,
  }),
});

/// The body of `test/fixtures/<name>.json` with its placeholder token
/// replaced by a real (unsigned, valid) JWT.
String authFixtureWithJwt(String name, [String? token]) {
  final json = fixture(name);
  json['token'] = token ?? validToken;
  return jsonEncode(json);
}

/// An [ApiClient] whose every request goes to [handler]; [requests] records
/// them.
ApiClient fakeApi(
  Future<http.Response> Function(http.Request request) handler, {
  List<http.Request>? requests,
}) => ApiClient(
  config: testConfig,
  httpClient: MockClient((request) {
    requests?.add(request);
    return handler(request);
  }),
);

/// An [ApiClient] that fails the test if it is called.
ApiClient unusedApi() =>
    fakeApi((request) => throw StateError('unexpected ${request.url}'));
