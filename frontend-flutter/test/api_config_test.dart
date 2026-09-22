import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/services/api_config.dart';

void main() {
  final page = Uri.parse('https://zapzap.example.org:8443/app/#/login');

  group('ApiConfig.resolve', () {
    test('a --dart-define wins on every platform', () {
      for (final isWeb in [true, false]) {
        final config = ApiConfig.resolve(
          defined: 'http://10.0.2.2:9999/',
          isWeb: isWeb,
          pageUri: page,
        );
        expect(config.baseUrl, 'http://10.0.2.2:9999');
      }
    });

    test('the web defaults to the page origin, not its /app/ path', () {
      final config = ApiConfig.resolve(defined: '', isWeb: true, pageUri: page);
      expect(config.baseUrl, 'https://zapzap.example.org:8443');
    });

    test('Android defaults to the public production URL', () {
      final config = ApiConfig.resolve(
        defined: '  ',
        isWeb: false,
        pageUri: page,
      );
      expect(config.baseUrl, ApiConfig.productionUrl);
      expect(config.baseUrl, 'https://zapzap.ombivince.synology.me');
    });
  });

  group('ApiConfig URLs', () {
    const config = ApiConfig('https://zapzap.example.org');

    test('apiUri prefixes /api, with or without a leading slash', () {
      expect(
        config.apiUri('/auth/login').toString(),
        'https://zapzap.example.org/api/auth/login',
      );
      expect(
        config.apiUri('party').toString(),
        'https://zapzap.example.org/api/party',
      );
    });

    test('apiUri encodes query parameters', () {
      expect(
        config.apiUri('/party', {'status': 'waiting'}).toString(),
        'https://zapzap.example.org/api/party?status=waiting',
      );
    });

    test('sseUri keeps the backend spelling', () {
      expect(
        config.sseUri.toString(),
        'https://zapzap.example.org/suscribeupdate',
      );
    });
  });
}
