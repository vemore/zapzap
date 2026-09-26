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

  test('the release build signs with key.properties, else the debug key, and runs R8', () {
    final gradle = _read('$_app/build.gradle.kts');
    expect(gradle, contains('rootProject.file("key.properties")'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    // CI and worktrees have no key.properties: the build must still sign.
    expect(gradle, contains('signingConfigs.getByName("debug")'));
    expect(gradle, contains('isMinifyEnabled = true'));
    expect(gradle, contains('isShrinkResources = true'));
    expect(gradle, contains('"proguard-rules.pro"'));
    // Only an APK falls back: a release bundle without key.properties is refused
    // (the CI step "Release bundle without key.properties is refused" runs it).
    expect(gradle, contains('if ("bundleRelease" in names)'));
    expect(gradle, contains('throw GradleException('));
    // A partly filled key.properties names the missing key.
    expect(gradle, contains('error("android/key.properties: missing \$key'));
    expect(gradle, isNot(contains('as String')));
  });

  test('the keep rules cover Flutter and google_sign_in', () {
    final rules = _read('$_app/proguard-rules.pro');
    expect(rules, contains('-keep class io.flutter.embedding.** { *; }'));
    expect(rules, contains('-keep class io.flutter.plugins.** { *; }'));
    expect(
      rules,
      contains('-keep class androidx.credentials.playservices.** { *; }'),
    );
    expect(
      rules,
      contains('-keep class com.google.android.libraries.identity.googleid.**'),
    );
  });

  test(
    'key.properties and keystores are gitignored; the template names the alias',
    () {
      final ignore = _read('android/.gitignore');
      expect(ignore, contains('key.properties'));
      expect(ignore, contains('**/*.jks'));
      expect(ignore, contains('**/*.keystore'));
      // Gradle's root build directory: a failed build writes a report there.
      expect(ignore.split('\n'), contains('/build/'));
      final template = _read('android/key.properties.template');
      expect(template, contains('keyAlias=zapzap-upload'));
      for (final key in ['storeFile=', 'storePassword=', 'keyPassword=']) {
        expect(template, contains(key));
      }
      // The Play API key, optional and commented out (scripts/play_publish.py).
      expect(
        template,
        contains(
          '#playServiceAccount=/home/USER/.config/zapzap/play-service-account.json',
        ),
      );
    },
  );
}
