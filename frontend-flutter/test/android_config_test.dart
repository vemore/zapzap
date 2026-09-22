import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

const _app = 'android/app';

void main() {
  test(
    'the application id, namespace and MainActivity package are com.zapzap.app',
    () {
      final gradle = _read('$_app/build.gradle.kts');
      expect(gradle, contains('applicationId = "com.zapzap.app"'));
      expect(gradle, contains('namespace = "com.zapzap.app"'));
      expect(
        _read('$_app/src/main/kotlin/com/zapzap/app/MainActivity.kt'),
        startsWith('package com.zapzap.app\n'),
      );
    },
  );

  test('the main manifest grants INTERNET and allows no cleartext', () {
    final main = _read('$_app/src/main/AndroidManifest.xml');
    expect(main, contains('android.permission.INTERNET'));
    expect(main, contains('android:label="ZapZap"'));
    expect(main, isNot(contains('networkSecurityConfig')));
    expect(main, isNot(contains('usesCleartextTraffic')));
    expect(
      _read('$_app/src/profile/AndroidManifest.xml'),
      isNot(contains('networkSecurityConfig')),
    );
  });

  test('only the debug build allows cleartext HTTP', () {
    expect(
      _read('$_app/src/debug/AndroidManifest.xml'),
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(
      _read('$_app/src/debug/res/xml/network_security_config.xml'),
      contains('cleartextTrafficPermitted="true"'),
    );
    expect(
      File('$_app/src/main/res/xml/network_security_config.xml').existsSync(),
      isFalse,
    );
  });
}
