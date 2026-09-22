import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'router.dart';
import 'services/api_config.dart';
import 'utils/app_theme.dart';

/// The root widget: providers, theme, localisation and routes.
class ZapZapApp extends StatefulWidget {
  const ZapZapApp({
    super.key,
    required this.apiConfig,
    this.locale,
    this.router,
  });

  final ApiConfig apiConfig;

  /// Forces a locale; `null` follows the device (French when unsupported).
  final Locale? locale;

  /// Replaces the default router, for tests that start elsewhere.
  final GoRouter? router;

  @override
  State<ZapZapApp> createState() => _ZapZapAppState();
}

class _ZapZapAppState extends State<ZapZapApp> {
  // Built once: a router rebuilt on every frame would lose the navigation stack.
  late final GoRouter _router = widget.router ?? createRouter();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders(apiConfig: widget.apiConfig),
      child: MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        locale: widget.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: resolveLocale,
        routerConfig: _router,
      ),
    );
  }
}

/// The supported locale matching the device's language, else French.
Locale resolveLocale(Locale? device, Iterable<Locale> supported) {
  for (final locale in supported) {
    if (locale.languageCode == device?.languageCode) return locale;
  }
  return const Locale('fr');
}
