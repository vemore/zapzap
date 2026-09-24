import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_exception.dart';
import '../services/google_sign_in_service.dart';
import '../utils/app_theme.dart';

/// "Continue with Google", then an "or" rule, above the fields of the login
/// and register screens (`Login.jsx`, `Register.jsx`). Each ID token Google
/// hands over is posted as `credential` to `POST /auth/google`
/// ([AuthProvider.loginWithGoogle]); on success the router, which follows
/// [AuthProvider], leaves the screen. Absent when the build has no client
/// id ([GoogleSignInSection.isShown]).
class GoogleSignInSection extends StatefulWidget {
  const GoogleSignInSection({
    super.key,
    required this.enabled,
    required this.onBusy,
    required this.onError,
  });

  /// Whether this build shows the section at all.
  static bool isShown(BuildContext context) =>
      context.read<GoogleSignInService>().enabled;

  /// `false` while the screen's own form is being sent.
  final bool enabled;

  /// `true` while the token is being posted, then `false`.
  final ValueChanged<bool> onBusy;

  /// The localised refusal, or `null` to clear the previous one.
  final ValueChanged<String?> onError;

  @override
  State<GoogleSignInSection> createState() => _GoogleSignInSectionState();
}

class _GoogleSignInSectionState extends State<GoogleSignInSection> {
  late final GoogleSignInService _google;
  StreamSubscription<String>? _tokens;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _google = context.read<GoogleSignInService>();
    _tokens = _google.idTokens.listen(_signIn, onError: _failed);
  }

  @override
  void dispose() {
    _tokens?.cancel();
    super.dispose();
  }

  Future<void> _signIn(String idToken) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    _setBusy(true);
    widget.onError(null);
    try {
      await auth.loginWithGoogle(idToken);
    } catch (error) {
      if (mounted) widget.onError(googleAuthErrorText(l10n, error));
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  void _failed(Object error) {
    debugPrint('Google sign-in failed: $error');
    if (mounted) {
      widget.onError(googleAuthErrorText(AppLocalizations.of(context), error));
    }
  }

  void _setBusy(bool busy) {
    setState(() => _busy = busy);
    widget.onBusy(busy);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final button =
        _google.platformButton(context) ??
        OutlinedButton.icon(
          key: const Key('google-sign-in'),
          onPressed: widget.enabled && !_busy ? _google.signIn : null,
          icon: const Text(
            'G',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          label: Text(l10n.loginWithGoogle),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.slate600)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.loginOr,
                style: const TextStyle(color: AppColors.slate400),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.slate600)),
          ],
        ),
      ],
    );
  }
}

/// The text of a failed Google sign-in: Google's side, or the backend's
/// refusal of the token.
String googleAuthErrorText(AppLocalizations l10n, Object error) =>
    error is ApiException && error.isConnectivity
    ? l10n.errorNetwork
    : l10n.authErrorGoogle;
