import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_exception.dart';
import '../services/google_sign_in_service.dart';
import '../utils/app_theme.dart';
import 'google_sign_in_section.dart';

/// Asks for the confirmation of `DELETE /auth/me` and sends it
/// ([AuthProvider.deleteAccount]). An account with a password confirms with
/// it; a Google account (`User.isGoogleUser`) with a fresh Google ID token,
/// obtained the way the login screen obtains one. When Google does not get
/// ready ([GoogleSignInSection.watchReady]: its script blocked, no route to
/// Google, no client id), the button gives way to a notice.
///
/// On success the session is erased and the router, which follows
/// [AuthProvider], shows the login screen; the dialog goes with the screen
/// under it. A refusal stays in the dialog, still signed in.
Future<void> showDeleteAccountDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const DeleteAccountDialog(),
);

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  late final AuthProvider _auth;
  late final bool _isGoogle;
  GoogleSignInService? _google;
  StreamSubscription<String>? _tokens;
  Widget? _platformButton;
  bool _googleAvailable = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _isGoogle = _auth.user?.isGoogleUser ?? false;
    if (_isGoogle) {
      final google = context.read<GoogleSignInService>();
      _google = google;
      _tokens = google.idTokens.listen(
        (token) => _delete(credential: token),
        onError: (Object error) => _refused(error),
      );
      _googleAvailable = GoogleSignInSection.mayBeAvailable(google);
      if (google.enabled) {
        GoogleSignInSection.watchReady(google, (available) {
          if (mounted && available != _googleAvailable) {
            setState(() => _googleAvailable = available);
          }
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Google's web button, built once: a new one re-renders its iframe.
    if (_isGoogle && _platformButton == null) {
      _platformButton = _google?.platformButton(context);
    }
  }

  @override
  void dispose() {
    _tokens?.cancel();
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete({String? password, String? credential}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.deleteAccount(password: password, credential: credential);
      // Signed out: the router has replaced the screens, this dialog with
      // them — unless it is still there.
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _refused(error);
    }
  }

  void _refused(Object error) {
    debugPrint('Account not deleted: $error');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = deleteAccountErrorText(AppLocalizations.of(context), error);
    });
  }

  Future<void> _startGoogle() async {
    try {
      await _google?.signIn();
    } catch (error) {
      _refused(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canSubmitPassword = !_busy && _password.text.isNotEmpty;
    return AlertDialog(
      key: const Key('delete-account-dialog'),
      title: Text(l10n.deleteAccountTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.deleteAccountBody),
            const SizedBox(height: 16),
            if (_isGoogle) ...[
              if (_googleAvailable) ...[
                Text(l10n.deleteAccountGoogleHint),
                const SizedBox(height: 12),
                _platformButton ??
                    OutlinedButton.icon(
                      key: const Key('delete-account-google'),
                      onPressed: _busy ? null : _startGoogle,
                      icon: const Text(
                        'G',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      label: Text(l10n.deleteAccountGoogleButton),
                    ),
              ] else
                Text(
                  l10n.deleteAccountGoogleUnavailable,
                  key: const Key('delete-account-google-unavailable'),
                ),
            ] else
              TextField(
                key: const Key('delete-account-password'),
                controller: _password,
                obscureText: true,
                enabled: !_busy,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: l10n.deleteAccountPasswordLabel,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (value) {
                  if (canSubmitPassword) _delete(password: value);
                },
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('delete-account-error'),
                style: const TextStyle(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('delete-account-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancelButton),
        ),
        if (!_isGoogle)
          TextButton(
            key: const Key('delete-account-confirm'),
            onPressed: canSubmitPassword
                ? () => _delete(password: _password.text)
                : null,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.deleteAccountConfirm),
          ),
      ],
    );
  }
}

/// The text of a refused deletion; the backend's message is never shown.
String deleteAccountErrorText(AppLocalizations l10n, Object error) {
  if (error is GoogleSignInFailure) return l10n.deleteAccountErrorGoogle;
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.invalidPassword ||
    ApiErrorCode.missingConfirmation => l10n.deleteAccountErrorPassword,
    ApiErrorCode.googleAuthFailed => l10n.deleteAccountErrorGoogle,
    ApiErrorCode.activeParty => l10n.deleteAccountErrorActiveParty,
    ApiErrorCode.lastAdmin => l10n.deleteAccountErrorLastAdmin,
    _ => l10n.errorGeneric,
  };
}
