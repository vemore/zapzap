import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';
import '../utils/validators.dart';
import 'app_logo.dart';

/// The frame shared by the login and register screens (`Login.jsx`,
/// `Register.jsx`): the logo, a title, the server's refusal if any, the
/// form, and the link to the other screen.
class AuthCard extends StatelessWidget {
  const AuthCard({
    super.key,
    required this.title,
    required this.error,
    required this.children,
    required this.footer,
  });

  final String title;

  /// The localised refusal of the last submit, `null` for none.
  final String? error;
  final List<Widget> children;
  final Widget footer;

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
                    const AppLogo(),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (error != null) ...[
                      _ErrorBanner(error!),
                      const SizedBox(height: 16),
                    ],
                    ...children,
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
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
  if (error is! ApiException) return l10n.authErrorGeneric;
  if (error.isConnectivity) return l10n.authErrorNetwork;
  return switch (error.code) {
    ApiErrorCode.invalidCredentials => l10n.authErrorInvalidCredentials,
    ApiErrorCode.usernameExists => l10n.authErrorUsernameExists,
    _ => l10n.authErrorGeneric,
  };
}
