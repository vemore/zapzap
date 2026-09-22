import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';

/// Create an account (`Register.jsx`), with the React rules checked live
/// (`utils/validators.dart`): each field shows its refusal once edited, and
/// submit stays disabled until both pass. On success the router, which
/// follows [AuthProvider], leaves this screen.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _usernameTouched = false;
  bool _passwordTouched = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  UsernameError? get _usernameError => validateUsername(_username.text);
  PasswordError? get _passwordError => validatePassword(_password.text);
  bool get _canSubmit =>
      !_busy && _usernameError == null && _passwordError == null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.register(_username.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorText(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final usernameError = _usernameError;
    final passwordError = _passwordError;
    return AuthCard(
      title: l10n.registerTitle,
      error: _error,
      footer: AuthSwitchLink(
        text: l10n.registerHaveAccount,
        link: l10n.registerLoginLink,
        onPressed: _busy ? null : () => context.go(AppRoutes.login),
      ),
      children: [
        TextField(
          key: const Key('register-username'),
          controller: _username,
          enabled: !_busy,
          autofillHints: const [AutofillHints.newUsername],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authUsernameLabel,
            hintText: l10n.registerUsernameHint,
            helperText: l10n.registerUsernameHelper(
              usernameMinLength,
              usernameMaxLength,
            ),
            errorText: _usernameTouched && usernameError != null
                ? usernameErrorText(l10n, usernameError)
                : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => _usernameTouched = true),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('register-password'),
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            hintText: l10n.registerPasswordHint(passwordMinLength),
            helperText: l10n.registerPasswordHelper(
              passwordMinLength,
              passwordMaxLength,
            ),
            errorText: _passwordTouched && passwordError != null
                ? passwordErrorText(l10n, passwordError)
                : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => _passwordTouched = true),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        AuthSubmitButton(
          key: const Key('register-submit'),
          label: l10n.registerSubmit,
          busyLabel: l10n.registerSubmitting,
          busy: _busy,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
