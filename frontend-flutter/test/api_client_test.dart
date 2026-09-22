import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/api_config.dart';
import 'package:zapzap/services/api_exception.dart';

import 'fixtures.dart';

const config = ApiConfig('https://zapzap.example.org');

void main() {
  late List<http.Request> requests;

  ApiClient clientAnswering(
    int status,
    String body, {
    String? token,
    void Function(ApiException)? onUnauthorized,
  }) {
    requests = [];
    return ApiClient(
      config: config,
      token: token,
      onUnauthorized: onUnauthorized,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(utf8.encode(body), status);
      }),
    );
  }

  group('requests', () {
    test('go to <base>/api, with the Bearer token and JSON', () async {
      final api = clientAnswering(200, '{"ok":true}', token: 'abc');
      final json = await api.post('/party/p1/join', body: {'inviteCode': 'X'});
      expect(json, {'ok': true});
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://zapzap.example.org/api/party/p1/join',
      );
      expect(request.headers['Authorization'], 'Bearer abc');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {'inviteCode': 'X'});
    });

    test('an unauthenticated call sends no token', () async {
      final api = clientAnswering(200, '{}', token: 'abc');
      await api.get('/bots', authenticated: false);
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('no token yet: no Authorization header', () async {
      final api = clientAnswering(200, '{}');
      await api.get('/party');
      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('query parameters are encoded; an empty query adds nothing', () async {
      final api = clientAnswering(200, '{}');
      await api.get('/party', query: {'status': 'waiting'});
      await api.get('/party', query: {});
      expect(
        requests[0].url.toString(),
        'https://zapzap.example.org/api/party?status=waiting',
      );
      expect(
        requests[1].url.toString(),
        'https://zapzap.example.org/api/party',
      );
    });

    test('DELETE, and an empty 2xx body', () async {
      final api = clientAnswering(204, '');
      expect(await api.delete('/party/p1'), isEmpty);
      expect(requests.single.method, 'DELETE');
    });

    test('the default timeout is 10 s', () {
      expect(ApiClient(config: config).timeout, const Duration(seconds: 10));
    });
  });

  group('401', () {
    test(
      'on an authenticated call fires onUnauthorized, then throws',
      () async {
        final seen = <ApiException>[];
        final error = errorFixture('error_invalid_token');
        final api = clientAnswering(
          error.status,
          error.body,
          token: 'expired',
          onUnauthorized: seen.add,
        );
        await expectLater(
          api.get('/stats/me'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', 401)
                .having((e) => e.code, 'code', 'INVALID_TOKEN'),
          ),
        );
        expect(seen, hasLength(1));
        expect(seen.single.code, 'INVALID_TOKEN');
      },
    );

    test('the Rust bare 401 fires it too', () async {
      var calls = 0;
      final api = clientAnswering(
        401,
        '',
        token: 'expired',
        onUnauthorized: (_) => calls++,
      );
      await expectLater(
        api.post('/game/p1/play', body: {'cardIds': <int>[]}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.unauthorized,
          ),
        ),
      );
      expect(calls, 1);
    });

    test(
      'the callback can be set after construction (the auth layer)',
      () async {
        var calls = 0;
        final api = clientAnswering(401, '', token: 'expired');
        api.onUnauthorized = (_) => calls++;
        await expectLater(api.get('/party/p1'), throwsA(isA<ApiException>()));
        expect(calls, 1);
      },
    );

    test('a wrong password (unauthenticated call) does not log out', () async {
      var calls = 0;
      final error = errorFixture('error_invalid_credentials');
      final api = clientAnswering(
        error.status,
        error.body,
        onUnauthorized: (_) => calls++,
      );
      await expectLater(
        api.post('/auth/login', body: {}, authenticated: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(calls, 0);
    });

    test('a 403 is not a logout', () async {
      var calls = 0;
      final error = errorFixture('error_admin_required');
      final api = clientAnswering(
        error.status,
        error.body,
        token: 'abc',
        onUnauthorized: (_) => calls++,
      );
      await expectLater(api.get('/admin/users'), throwsA(isA<ApiException>()));
      expect(calls, 0);
    });
  });

  group('no answer', () {
    test('a connection failure is NETWORK_ERROR', () async {
      final api = ApiClient(
        config: config,
        httpClient: MockClient((_) async {
          throw http.ClientException('Connection refused');
        }),
      );
      await expectLater(
        api.get('/party'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ApiErrorCode.network)
              .having((e) => e.status, 'status', 0)
              .having((e) => e.isConnectivity, 'isConnectivity', isTrue),
        ),
      );
    });

    test('no answer in time is TIMEOUT', () async {
      final never = Completer<http.Response>();
      final api = ApiClient(
        config: config,
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) => never.future),
      );
      await expectLater(
        api.get('/party'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.timeout,
          ),
        ),
      );
    });

    test(
      'a TLS failure, not wrapped by the client, is NETWORK_ERROR',
      () async {
        for (final failure in <Exception>[
          const HandshakeException('CERTIFICATE_VERIFY_FAILED'),
          const TlsException('bad record'),
          const SocketException('Network is unreachable'),
        ]) {
          final api = ApiClient(
            config: config,
            httpClient: MockClient((_) async => throw failure),
          );
          await expectLater(
            api.get('/party'),
            throwsA(
              isA<ApiException>()
                  .having((e) => e.code, 'code', ApiErrorCode.network)
                  .having((e) => e.status, 'status', 0),
            ),
            reason: failure.runtimeType.toString(),
          );
        }
      },
    );

    test('one deadline covers the headers and the body together', () async {
      // Headers after 60 % of the timeout, the body after another 60 %:
      // each part alone fits, the whole request does not.
      const timeout = Duration(milliseconds: 200);
      const part = Duration(milliseconds: 120);
      final api = ApiClient(
        config: config,
        timeout: timeout,
        httpClient: MockClient.streaming((request, _) async {
          await Future<void>.delayed(part);
          final body = Stream<List<int>>.fromFuture(
            Future.delayed(part, () => utf8.encode('{}')),
          );
          return http.StreamedResponse(body, 200);
        }),
      );
      await expectLater(
        api.get('/party'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.timeout,
          ),
        ),
      );
    });

    test('a slow but in-time answer is not a timeout', () async {
      final api = ApiClient(
        config: config,
        timeout: const Duration(milliseconds: 300),
        httpClient: MockClient.streaming((request, _) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"ok":true}')),
            200,
          );
        }),
      );
      expect(await api.get('/party'), {'ok': true});
    });

    test('a 2xx that is not a JSON object is INVALID_RESPONSE', () async {
      final api = clientAnswering(200, '[1,2]');
      await expectLater(
        api.get('/party'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiErrorCode.invalidResponse,
          ),
        ),
      );
    });
  });
}
