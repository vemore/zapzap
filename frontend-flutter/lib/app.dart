import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'providers/auth_provider.dart';
import 'router.dart';
import 'services/api_client.dart';
import 'services/api_config.dart';
import 'services/google_sign_in_service.dart';
import 'services/sse_transport.dart';
import 'services/token_storage.dart';
import 'services/tutorial_offer_store.dart';
import 'utils/app_theme.dart';
import 'widgets/tutorial_offer.dart';

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
    this.googleSignIn,
    this.tutorialOffer,
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

  /// Replaces Google sign-in, for tests.
  final GoogleSignInService? googleSignIn;

  /// Remembers that the example game was offered; `null` never offers it
  /// (the tests that are not about it). `main.dart` passes the device's.
  final TutorialOfferStore? tutorialOffer;

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
        googleSignIn: widget.googleSignIn,
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
        // Under every screen, so the navigation bar at the bottom is dark
        // whatever the route; app bars set the same style at the top.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppTheme.systemOverlayStyle,
          child: _withOffer(child ?? const SizedBox.shrink()),
        ),
        routerConfig: _router ??= createRouter(
          auth: context.read<AuthProvider>(),
          initialLocation: widget.initialLocation,
        ),
      ),
    );
  }

  /// [child] under the first opening's offer of the example game.
  Widget _withOffer(Widget child) {
    final store = widget.tutorialOffer;
    if (store == null) return child;
    return TutorialOffer(
      store: store,
      onStart: () => _router?.push(AppRoutes.tutorial),
      child: child,
    );
  }
}

/// The supported locale matching the device's language, whatever its region
/// (`pt_BR` and `pt_PT` both get `pt`, written in Brazilian Portuguese), else
/// French.
Locale resolveLocale(Locale? device, Iterable<Locale> supported) {
  for (final locale in supported) {
    if (locale.languageCode == device?.languageCode) return locale;
  }
  return const Locale('fr');
}
