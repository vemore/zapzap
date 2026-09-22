import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/api_config.dart';
import 'package:zapzap/utils/app_theme.dart';

const _config = ApiConfig('http://localhost:9999');

void main() {
  testWidgets('home shows the French strings by default and routes to login', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ZapZapApp(apiConfig: _config, locale: Locale('fr')),
    );
    await tester.pumpAndSettle();

    expect(find.text('ZapZap'), findsOneWidget);
    expect(find.text('Le jeu de cartes multijoueur'), findsOneWidget);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Connexion'), findsOneWidget);
    expect(find.text('La connexion arrive bientôt.'), findsOneWidget);
  });

  testWidgets('English strings when the locale is English', (tester) async {
    await tester.pumpWidget(
      const ZapZapApp(apiConfig: _config, locale: Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('The multiplayer card game'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('an unknown path shows the not-found screen', (tester) async {
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: _config,
        locale: const Locale('fr'),
        router: createRouter(initialLocation: '/nowhere'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Page introuvable'), findsOneWidget);
    await tester.tap(find.text("Retour à l'accueil"));
    await tester.pumpAndSettle();
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('the theme is the dark slate and amber of the React client', (
    tester,
  ) async {
    await tester.pumpWidget(const ZapZapApp(apiConfig: _config));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0F172A));
    expect(theme.colorScheme.primary, AppColors.amber400);
  });

  group('resolveLocale', () {
    const supported = [Locale('en'), Locale('fr')];

    test('matches the device language', () {
      expect(
        resolveLocale(const Locale('en', 'US'), supported),
        const Locale('en'),
      );
      expect(
        resolveLocale(const Locale('fr', 'CA'), supported),
        const Locale('fr'),
      );
    });

    test('falls back to French', () {
      expect(resolveLocale(const Locale('de'), supported), const Locale('fr'));
      expect(resolveLocale(null, supported), const Locale('fr'));
    });
  });
}
