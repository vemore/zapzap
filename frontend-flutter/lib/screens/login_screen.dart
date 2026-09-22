import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';

/// Sign in with a username and a password (`Login.jsx`). Only "both are
/// filled in" is checked here, as in React: an account created before the
/// register rules still signs in. On success the router, which follows
/// [AuthProvider], leaves this screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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

  bool get _usernameMissing => _username.text.trim().isEmpty;
  bool get _passwordMissing => _password.text.isEmpty;
  bool get _canSubmit => !_busy && !_usernameMissing && !_passwordMissing;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.login(_username.text.trim(), _password.text);
    } catch (error) {
      if (mounted) setState(() => _error = authErrorText(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthCard(
      title: l10n.loginTitle,
      error: _error,
      footer: AuthSwitchLink(
        text: l10n.loginNoAccount,
        link: l10n.loginRegisterLink,
        onPressed: _busy ? null : () => context.go(AppRoutes.register),
      ),
      children: [
        TextField(
          key: const Key('login-username'),
          controller: _username,
          enabled: !_busy,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authUsernameLabel,
            hintText: l10n.loginUsernameHint,
            errorText: _usernameTouched && _usernameMissing
                ? usernameErrorText(l10n, UsernameError.required)
                : null,
          ),
          onChanged: (_) => setState(() => _usernameTouched = true),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('login-password'),
          controller: _password,
          enabled: !_busy,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            hintText: l10n.loginPasswordHint,
            errorText: _passwordTouched && _passwordMissing
                ? passwordErrorText(l10n, PasswordError.required)
                : null,
          ),
          onChanged: (_) => setState(() => _passwordTouched = true),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        AuthSubmitButton(
          key: const Key('login-submit'),
          label: l10n.loginSubmit,
          busyLabel: l10n.loginSubmitting,
          busy: _busy,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
