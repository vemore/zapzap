import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/field_touch.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';

/// Sign in with a username and a password (`Login.jsx`). Only "both are
/// filled in" is checked here, as in React: an account created before the
/// register rules still signs in. The button stays active: a click with a
/// field missing says which one under it ([FieldTouch]). On success the
/// router, which follows [AuthProvider], leaves this screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final _usernameTouch = FieldTouch(_refresh);
  late final _passwordTouch = FieldTouch(_refresh);
  bool _busy = false;
  String? _error;

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameTouch.dispose();
    _passwordTouch.dispose();
    super.dispose();
  }

  bool get _usernameMissing => _username.text.trim().isEmpty;
  bool get _passwordMissing => _password.text.isEmpty;

  Future<void> _submit() async {
    if (_busy) return;
    _usernameTouch.submitted();
    _passwordTouch.submitted();
    if (_usernameMissing || _passwordMissing) {
      setState(() {});
      (_usernameMissing ? _usernameTouch : _passwordTouch).focus.requestFocus();
      return;
    }
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
      fields: [
        TextField(
          key: const Key('login-username'),
          controller: _username,
          focusNode: _usernameTouch.focus,
          enabled: !_busy,
          autocorrect: false,
          autofillHints: const [AutofillHints.username],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authUsernameLabel,
            hintText: l10n.loginUsernameHint,
            errorText: _usernameTouch.touched && _usernameMissing
                ? usernameErrorText(l10n, UsernameError.required)
                : null,
          ),
          onChanged: (_) => setState(_usernameTouch.edited),
        ),
        const SizedBox(height: 16),
        AuthPasswordField(
          key: const Key('login-password'),
          controller: _password,
          focusNode: _passwordTouch.focus,
          enabled: !_busy,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            hintText: l10n.loginPasswordHint,
            errorText: _passwordTouch.touched && _passwordMissing
                ? passwordErrorText(l10n, PasswordError.required)
                : null,
          ),
          onChanged: (_) => setState(_passwordTouch.edited),
          onSubmitted: (_) => _submit(),
        ),
      ],
      submit: AuthSubmitButton(
        key: const Key('login-submit'),
        label: l10n.loginSubmit,
        busyLabel: l10n.loginSubmitting,
        busy: _busy,
        onPressed: _submit,
      ),
    );
  }
}
