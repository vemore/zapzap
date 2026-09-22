import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'providers/auth_provider.dart';
import 'router.dart';
import 'services/api_client.dart';
import 'services/api_config.dart';
import 'services/sse_transport.dart';
import 'services/token_storage.dart';
import 'utils/app_theme.dart';

/// The root widget: providers, theme, localisation and routes.
class ZapZapApp extends StatefulWidget {
  const ZapZapApp({
    super.key,
    required this.apiConfig,
    this.locale,
    this.initialLocation = AppRoutes.home,
    this.apiClient,
    this.tokenStorage,
    this.sseTransport,
  });

  final ApiConfig apiConfig;

  /// Forces a locale; `null` follows the device (French when unsupported).
  final Locale? locale;

  /// Where the router starts (a deep link on the web; tests).
  final String initialLocation;

  /// Replace the real HTTP client, session storage and real-time transport,
  /// for tests.
  final ApiClient? apiClient;
  final TokenStorage? tokenStorage;
  final SseTransport? sseTransport;

  @override
  State<ZapZapApp> createState() => _ZapZapAppState();
}

class _ZapZapAppState extends State<ZapZapApp> {
  // Built once: a router rebuilt on every frame would lose the navigation
  // stack. Built lazily, below the providers, because it follows the session.
  GoRouter? _router;

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders(
        apiConfig: widget.apiConfig,
        apiClient: widget.apiClient,
        tokenStorage: widget.tokenStorage,
        sseTransport: widget.sseTransport,
      ),
      builder: (context, _) => MaterialApp.router(
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
        routerConfig: _router ??= createRouter(
          auth: context.read<AuthProvider>(),
          initialLocation: widget.initialLocation,
        ),
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
