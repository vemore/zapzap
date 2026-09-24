import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';
import '../utils/validators.dart';
import 'app_logo.dart';
import 'error_banner.dart';

/// The frame shared by the login and register screens (`Login.jsx`,
/// `Register.jsx`): the logo with its one-line pitch, a title, the fields in
/// one [AutofillGroup] (the password manager fills and saves them together)
/// under the [alternative] sign-in if any (Google, as React puts it),
/// the server's refusal if any just above the submit button, where the eye
/// already is, and the link to the other screen.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    required this.error,
    required this.fields,
    required this.submit,
    required this.footer,
    this.alternative,
  });

  final String title;

  /// The localised refusal of the last submit, `null` for none.
  final String? error;
  final List<Widget> fields;
  final Widget submit;
  final Widget footer;

  /// Another way in, above the fields (`GoogleSignInSection`); `null` for
  /// none.
  final Widget? alternative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppLogo(pitch: true),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (alternative != null) ...[
                      alternative!,
                      const SizedBox(height: 16),
                    ],
                    AutofillGroup(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: fields,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (error != null) ...[
                      _ErrorBanner(error!),
                      const SizedBox(height: 16),
                    ],
                    submit,
                    const SizedBox(height: 24),
                    footer,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The server's refusal, in the soft red card of the other screens
/// ([ErrorBanner]); it stays until the next submit, and a screen reader
/// announces it.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: ErrorBanner(key: const Key('auth-error'), message: message),
    );
  }
}

/// A password field with an eye that shows or hides what was typed. The
/// eye sits inside the field, so it stays there at a large text scale.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.autofillHints,
    required this.decoration,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final Iterable<String> autofillHints;

  /// The label, hint, helper and error; the eye is added here.
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      textInputAction: TextInputAction.done,
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          key: const Key('password-visibility'),
          tooltip: _visible ? l10n.authHidePassword : l10n.authShowPassword,
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: widget.enabled
              ? () => setState(() => _visible = !_visible)
              : null,
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}

/// The submit button: disabled when [onPressed] is `null`, a spinner and
/// [busyLabel] while [busy].
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(busyLabel),
              ],
            )
          : Text(label),
    );
  }
}

/// "No account yet? Sign up" — [text] then a link calling [onPressed].
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.text,
    required this.link,
    required this.onPressed,
  });

  final String text;
  final String link;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(text, style: const TextStyle(color: AppColors.slate400)),
        TextButton(onPressed: onPressed, child: Text(link)),
      ],
    );
  }
}

/// The text of a username refusal.
String usernameErrorText(AppLocalizations l10n, UsernameError error) =>
    switch (error) {
      UsernameError.required => l10n.usernameRequired,
      UsernameError.tooShort => l10n.usernameTooShort(usernameMinLength),
      UsernameError.tooLong => l10n.usernameTooLong(usernameMaxLength),
      UsernameError.invalidCharacters => l10n.usernameInvalidCharacters,
    };

/// The text of a password refusal.
String passwordErrorText(AppLocalizations l10n, PasswordError error) =>
    switch (error) {
      PasswordError.required => l10n.passwordRequired,
      PasswordError.tooShort => l10n.passwordTooShort(passwordMinLength),
      PasswordError.tooLong => l10n.passwordTooLong(passwordMaxLength),
    };

/// The text of a failed login or register, from the [ApiException] code.
String authErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.invalidCredentials => l10n.authErrorInvalidCredentials,
    ApiErrorCode.usernameExists => l10n.authErrorUsernameExists,
    _ => l10n.errorGeneric,
  };
}
