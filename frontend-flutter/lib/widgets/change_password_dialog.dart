import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_exception.dart';
import '../services/google_sign_in_service.dart';
import '../utils/app_theme.dart';
import '../utils/validators.dart';
import 'auth_form.dart';
import 'google_confirmation.dart';

/// Asks for a new password and sends it ([AuthProvider.changePassword]),
/// confirmed as the account deletion is: by the current password
/// ([User.hasPassword]), or for any Google account ([User.isGoogleUser]) by
/// a fresh Google ID token ([GoogleConfirmation]) — which sets a Google
/// account's first password, and replaces one it has forgotten. The new
/// password follows the sign-up form's rules ([validatePassword]).
///
/// `true` once the password is changed; a refusal stays in the dialog.
Future<bool> showChangePasswordDialog(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => const ChangePasswordDialog(),
    ) ??
    false;

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _newFocus = FocusNode();
  late final AuthProvider _auth;
  late final bool _hasPassword;

  /// Google can confirm: whatever the password, the account is Google's.
  late final bool _isGoogle;

  /// The new password was edited: its refusal may show.
  bool _touched = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _hasPassword = _auth.user?.hasPassword ?? true;
    _isGoogle = _auth.user?.isGoogleUser ?? false;
  }

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _newFocus.dispose();
    super.dispose();
  }

  bool get _newValid => validatePassword(_new.text) == null;

  bool get _canSubmit => !_busy && _current.text.isNotEmpty && _newValid;

  Future<void> _submit({String? credential}) async {
    if (_busy) return;
    // Google's own web button cannot be disabled: a token may come before
    // the new password is acceptable.
    if (!_newValid) {
      setState(() => _touched = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.changePassword(
        newPassword: _new.text,
        // Google's confirmation stands alone: a password sent beside it is
        // the one the backend would check, and it may be the forgotten one.
        currentPassword: credential == null ? _current.text : null,
        credential: credential,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      _refused(error);
    }
  }

  void _refused(Object error) {
    debugPrint('Password not changed: $error');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = changePasswordErrorText(AppLocalizations.of(context), error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final newError = _touched ? validatePassword(_new.text) : null;
    return AlertDialog(
      key: const Key('change-password-dialog'),
      title: Text(
        _hasPassword ? l10n.accountPasswordChange : l10n.accountPasswordSet,
      ),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasPassword) ...[
                TextField(
                  key: const Key('change-password-current'),
                  controller: _current,
                  obscureText: true,
                  enabled: !_busy,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: l10n.accountPasswordCurrentLabel,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              AuthPasswordField(
                key: const Key('change-password-new'),
                controller: _new,
                focusNode: _newFocus,
                enabled: !_busy,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: l10n.accountPasswordNewLabel,
                  errorText: newError == null
                      ? null
                      : passwordErrorText(l10n, newError),
                  errorMaxLines: 3,
                ),
                onChanged: (_) => setState(() => _touched = true),
                onSubmitted: (_) {
                  if (_hasPassword && _canSubmit) _submit();
                },
              ),
              if (_isGoogle) ...[
                const SizedBox(height: 16),
                GoogleConfirmation(
                  hint: _hasPassword
                      ? l10n.accountPasswordForgotGoogleHint
                      : l10n.accountPasswordGoogleHint,
                  unavailable: l10n.accountPasswordGoogleUnavailable,
                  buttonKey: const Key('change-password-google'),
                  unavailableKey: const Key(
                    'change-password-google-unavailable',
                  ),
                  enabled: !_busy && _newValid,
                  onCredential: (token) => _submit(credential: token),
                  onError: _refused,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  key: const Key('change-password-error'),
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('change-password-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        if (_hasPassword)
          FilledButton(
            key: const Key('change-password-confirm'),
            onPressed: _canSubmit ? _submit : null,
            child: Text(l10n.saveButton),
          ),
      ],
    );
  }
}

/// The text of a refused password change; the backend's message is never
/// shown.
String changePasswordErrorText(AppLocalizations l10n, Object error) {
  if (error is GoogleSignInFailure) return l10n.errorGoogleConfirmation;
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.invalidPassword ||
    ApiErrorCode.missingConfirmation => l10n.errorWrongPassword,
    ApiErrorCode.googleAuthFailed => l10n.errorGoogleConfirmation,
    _ => l10n.errorGeneric,
  };
}
