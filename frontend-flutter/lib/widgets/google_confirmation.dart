import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/google_sign_in_service.dart';
import 'google_sign_in_section.dart';

/// A fresh Google ID token confirming an account change a Google account
/// has no password for: deleting it ([DeleteAccountDialog]), setting its
/// first password ([ChangePasswordDialog]). The token is obtained the way the
/// login screen obtains one — [hint], then "Confirm with Google", Google's
/// own button on the web — and handed to [onCredential]; a failure of
/// Google's to [onError].
///
/// When Google does not get ready ([GoogleSignInSection.watchReady]: its
/// script blocked, no route to Google, no client id), the button gives way to
/// [unavailable]. One such widget listens to Google's tokens at a time: the
/// dialog that shows it.
class GoogleConfirmation extends StatefulWidget {
  const GoogleConfirmation({
    super.key,
    required this.hint,
    required this.unavailable,
    required this.buttonKey,
    required this.unavailableKey,
    required this.onCredential,
    required this.onError,
    this.enabled = true,
  });

  final String hint;

  /// Why Google cannot confirm, and what to do instead.
  final String unavailable;
  final Key buttonKey;
  final Key unavailableKey;
  final ValueChanged<String> onCredential;
  final ValueChanged<Object> onError;

  /// `false` while the confirmation is being sent. Google's own web button
  /// cannot be disabled: [onCredential] may still be called.
  final bool enabled;

  @override
  State<GoogleConfirmation> createState() => _GoogleConfirmationState();
}

class _GoogleConfirmationState extends State<GoogleConfirmation> {
  late final GoogleSignInService _google;
  late final StreamSubscription<String> _tokens;
  Widget? _platformButton;
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _google = context.read<GoogleSignInService>();
    _tokens = _google.idTokens.listen(
      (token) => widget.onCredential(token),
      onError: (Object error) => widget.onError(error),
    );
    _available = GoogleSignInSection.mayBeAvailable(_google);
    if (_google.enabled) {
      GoogleSignInSection.watchReady(_google, (available) {
        if (mounted && available != _available) {
          setState(() => _available = available);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Google's web button, built once: a new one re-renders its iframe.
    _platformButton ??= _google.platformButton(context);
  }

  @override
  void dispose() {
    _tokens.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      await _google.signIn();
    } catch (error) {
      widget.onError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) {
      return Text(widget.unavailable, key: widget.unavailableKey);
    }
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.hint),
        const SizedBox(height: 12),
        _platformButton ??
            OutlinedButton.icon(
              key: widget.buttonKey,
              onPressed: widget.enabled ? _start : null,
              icon: const Text(
                'G',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              label: Text(l10n.googleConfirmButton),
            ),
      ],
    );
  }
}
