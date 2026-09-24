import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/field_touch.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';
import '../widgets/google_sign_in_section.dart';

/// Create an account (`Register.jsx`), with the React rules
/// (`utils/validators.dart`): a field shows its refusal once edited and
/// left, or on submit, then live ([FieldTouch]). The button stays active: a
/// click with a field refused says why under it and sends nothing. On
/// success the router, which follows [AuthProvider], leaves this screen.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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

  UsernameError? get _usernameError => validateUsername(_username.text);
  PasswordError? get _passwordError => validatePassword(_password.text);

  Future<void> _submit() async {
    if (_busy) return;
    _usernameTouch.submitted();
    _passwordTouch.submitted();
    if (_usernameError != null || _passwordError != null) {
      setState(() {});
      (_usernameError != null ? _usernameTouch : _passwordTouch).focus
          .requestFocus();
      return;
    }
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
      alternative: GoogleSignInSection.isShown(context)
          ? GoogleSignInSection(
              enabled: !_busy,
              onBusy: (busy) => setState(() => _busy = busy),
              onError: (error) => setState(() => _error = error),
            )
          : null,
      footer: AuthSwitchLink(
        text: l10n.registerHaveAccount,
        link: l10n.registerLoginLink,
        onPressed: _busy ? null : () => context.go(AppRoutes.login),
      ),
      fields: [
        TextField(
          key: const Key('register-username'),
          controller: _username,
          focusNode: _usernameTouch.focus,
          enabled: !_busy,
          autocorrect: false,
          autofillHints: const [AutofillHints.newUsername],
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.authUsernameLabel,
            hintText: l10n.registerUsernameHint,
            helperText: l10n.registerUsernameHelper(
              usernameMinLength,
              usernameMaxLength,
            ),
            errorText: _usernameTouch.touched && usernameError != null
                ? usernameErrorText(l10n, usernameError)
                : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(_usernameTouch.edited),
        ),
        const SizedBox(height: 16),
        AuthPasswordField(
          key: const Key('register-password'),
          controller: _password,
          focusNode: _passwordTouch.focus,
          enabled: !_busy,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: l10n.authPasswordLabel,
            hintText: l10n.registerPasswordHint(passwordMinLength),
            helperText: l10n.registerPasswordHelper(
              passwordMinLength,
              passwordMaxLength,
            ),
            errorText: _passwordTouch.touched && passwordError != null
                ? passwordErrorText(l10n, passwordError)
                : null,
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(_passwordTouch.edited),
          onSubmitted: (_) => _submit(),
        ),
      ],
      submit: AuthSubmitButton(
        key: const Key('register-submit'),
        label: l10n.registerSubmit,
        busyLabel: l10n.registerSubmitting,
        busy: _busy,
        onPressed: _submit,
      ),
    );
  }
}
