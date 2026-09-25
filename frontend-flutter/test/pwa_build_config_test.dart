import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the PWA image takes the Google client id as a build argument, empty '
      'by default', () {
    final dockerfile = _read('Dockerfile');
    expect(dockerfile, contains('ARG GOOGLE_CLIENT_ID=\n'));
    expect(
      dockerfile,
      contains('--dart-define=GOOGLE_CLIENT_ID="\${GOOGLE_CLIENT_ID}"'),
    );
  });

  test('index.html holds Google\'s GIS script back until the app releases '
      'it, under the name the app calls', () {
    final html = _read('web/index.html');
    expect(html, contains("'https://accounts.google.com/gsi/client'"));
    expect(html, contains('window.zapzapLoadGoogleScript = function'));
    // Before the Flutter bootstrap, which registers the plugin.
    expect(
      html.indexOf('zapzapLoadGoogleScript'),
      lessThan(html.indexOf('flutter_bootstrap.js')),
    );
    expect(
      _read('lib/services/google_sign_in_script_web.dart'),
      contains("'zapzapLoadGoogleScript'"),
    );
  });

  test('both compose files feed it from the .env\'s web client id', () {
    for (final compose in [
      '../docker-compose.yml',
      '../zapzap-rust/docker-compose.yml',
    ]) {
      final text = _read(compose);
      final service = text.substring(text.indexOf('  frontend-flutter:'));
      final block = service.substring(0, service.indexOf('container_name'));
      expect(
        block,
        contains('- GOOGLE_CLIENT_ID=\${VITE_GOOGLE_OAUTH_CLIENT_ID}'),
        reason: compose,
      );
    }
  });
}
