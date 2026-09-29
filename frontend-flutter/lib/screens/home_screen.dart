import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../services/api_exception.dart';
import '../widgets/app_logo.dart';
import '../widgets/error_banner.dart';

/// The landing screen: the logo and the ways in — sign in, or play at once
/// under a guest account ([AuthProvider.playAsGuest]), no form. The router
/// leaves the screen by itself once signed in.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _playAsGuest() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().playAsGuest();
    } catch (error) {
      debugPrint('No guest account: $error');
      if (!mounted) return;
      setState(() => _error = guestErrorText(l10n, error));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(),
              const SizedBox(height: 8),
              Text(
                l10n.homeTagline,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.login),
                icon: const Icon(Icons.login),
                label: Text(l10n.homeLoginButton),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('home-guest'),
                onPressed: _busy ? null : _playAsGuest,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(l10n.homeGuestButton),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Semantics(
                    liveRegion: true,
                    child: ErrorBanner(
                      key: const Key('home-guest-error'),
                      message: _error!,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The text of a refused guest account; the backend's message is never shown.
String guestErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.rateLimited => l10n.homeGuestErrorRateLimited,
    _ => l10n.errorGeneric,
  };
}
