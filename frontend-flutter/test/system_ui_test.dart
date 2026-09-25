import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/services/api_config.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/utils/app_theme.dart';

const _config = ApiConfig('http://localhost:9999');

/// The style the framework last sent to the platform, once the frame's
/// system-UI update (a microtask) has run.
Future<SystemUiOverlayStyle?> _sentStyle(WidgetTester tester) async {
  await tester.pump();
  return SystemChrome.latestStyle;
}

void _expectDarkBars(SystemUiOverlayStyle? style) {
  expect(style, isNotNull);
  expect(style!.systemNavigationBarColor, AppColors.slate900);
  expect(style.systemNavigationBarIconBrightness, Brightness.light);
  expect(style.systemNavigationBarContrastEnforced, isFalse);
  expect(style.statusBarIconBrightness, Brightness.light);
}

void main() {
  // SystemChrome.latestStyle outlives a test: start each from a light style,
  // so a pass is this test's own.
  setUp(() async {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    await Future<void>.delayed(Duration.zero);
    expect(SystemChrome.latestStyle, SystemUiOverlayStyle.dark);
  });

  test(
    'the overlay style: dark navigation bar = app background, light icons',
    () {
      const style = AppTheme.systemOverlayStyle;
      expect(style.systemNavigationBarColor, AppColors.slate900);
      expect(style.systemNavigationBarDividerColor, AppColors.slate900);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(AppTheme.dark().appBarTheme.systemOverlayStyle, style);
    },
  );

  testWidgets('the login screen sends the dark navigation bar', (tester) async {
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: _config,
        locale: const Locale('fr'),
        initialLocation: '/login',
        tokenStorage: MemoryTokenStorage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connexion'), findsOneWidget);
    _expectDarkBars(await _sentStyle(tester));
  });

  testWidgets('a screen with an app bar keeps it dark too', (tester) async {
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: _config,
        locale: const Locale('fr'),
        initialLocation: '/nowhere',
        tokenStorage: MemoryTokenStorage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    _expectDarkBars(await _sentStyle(tester));
  });

  test(
    'the Android window themes draw the same bar before the first frame',
    () {
      for (final dir in ['values', 'values-night']) {
        final xml = File('android/app/src/main/res/$dir/styles.xml')
            .readAsStringSync();
        expect(
          '<item name="android:navigationBarColor">#FF0F172A</item>'
              .allMatches(xml)
              .length,
          2,
          reason: '$dir: LaunchTheme and NormalTheme',
        );
        expect(xml, contains('"android:windowLightNavigationBar"'));
        expect(xml, contains('"android:enforceNavigationBarContrast"'));
      }
    },
  );
}
