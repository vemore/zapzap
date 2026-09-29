import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';
import '../utils/navigation.dart';
import '../utils/validators.dart';
import '../widgets/auth_form.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/delete_account_dialog.dart';
import '../widgets/guest_banner.dart';
import '../widgets/zapzap_app_bar.dart';

/// The signed-in player's account ([AppRoutes.account], from the ⋮ menu):
/// who they are and how they sign in, then their username
/// ([AuthProvider.rename], the sign-up form's rules), their password
/// ([showChangePasswordDialog]: change it, or for a Google account set a
/// first one), and the account deletion ([showDeleteAccountDialog]), which
/// Google Play wants reachable in the app. The React client has no such page
/// (`.llmwiki/Api.md`). A guest ([AuthProvider.isGuest]) reads the guest
/// warning ([GuestBanner]) first, and claims the account by choosing a
/// password: the generated one confirms it, unseen.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  /// The page's width at most: a form, not a board.
  static const maxWidth = 560.0;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final TextEditingController _username;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _username = TextEditingController(
      text: context.read<AuthProvider>().user?.username ?? '',
    );
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  String get _wanted => _username.text.trim();

  Future<void> _rename(AuthProvider auth) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await auth.rename(_wanted);
      if (!mounted) return;
      _username.text = _wanted;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.accountUsernameSaved)),
      );
    } catch (error) {
      debugPrint('Username not changed: $error');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = renameErrorText(l10n, error);
      });
    }
  }

  Future<void> _changePassword() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final wasGuest = context.read<AuthProvider>().isGuest;
    if (await showChangePasswordDialog(context)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            wasGuest ? l10n.accountGuestClaimed : l10n.accountPasswordSaved,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return Scaffold(
      appBar: ZapZapAppBar(
        title: l10n.accountTitle,
        leading: BackButton(
          key: const Key('back'),
          onPressed: () => context.popOrGo(AppRoutes.parties),
        ),
      ),
      // Signed out (a deletion, a 401): the router is leaving the screen.
      body: user == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AccountScreen.maxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (user.isGuest) ...[
                          const GuestBanner(showButton: false),
                          const SizedBox(height: 12),
                        ],
                        _identity(l10n, user),
                        const SizedBox(height: 12),
                        _usernameSection(l10n, auth, user),
                        const SizedBox(height: 12),
                        _passwordSection(l10n, user),
                        const SizedBox(height: 24),
                        OutlinedButton.icon(
                          key: const Key('account-delete'),
                          onPressed: () => showDeleteAccountDialog(context),
                          icon: const Icon(Icons.person_remove),
                          label: Text(l10n.deleteAccountButton),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Who is signed in, and how they sign in.
  Widget _identity(AppLocalizations l10n, User user) {
    final method = user.isGuest
        ? l10n.accountSignInGuest
        : !user.isGoogleUser
        ? l10n.accountSignInPassword
        : user.hasPassword
        ? l10n.accountSignInGoogleAndPassword
        : l10n.accountSignInGoogle;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.account_circle, size: 40),
        title: Text(
          user.username,
          key: const Key('account-current-username'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [method, ?user.email].join('\n'),
          key: const Key('account-sign-in-method'),
        ),
      ),
    );
  }

  Widget _usernameSection(AppLocalizations l10n, AuthProvider auth, User user) {
    final edited = _wanted != user.username;
    final invalid = edited ? validateUsername(_username.text) : null;
    final canSave = !_busy && edited && invalid == null;
    return _Section(
      title: l10n.authUsernameLabel,
      children: [
        TextField(
          key: const Key('account-username'),
          controller: _username,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: usernameMaxLength,
          autofillHints: const [AutofillHints.username],
          decoration: InputDecoration(
            helperText: l10n.accountUsernameHelper,
            helperMaxLines: 2,
            errorText: invalid == null
                ? null
                : usernameErrorText(l10n, invalid),
            errorMaxLines: 3,
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) {
            if (canSave) _rename(auth);
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            key: const Key('account-username-error'),
            style: const TextStyle(color: AppColors.error),
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('account-username-save'),
            onPressed: canSave ? () => _rename(auth) : null,
            child: Text(l10n.saveButton),
          ),
        ),
      ],
    );
  }

  Widget _passwordSection(AppLocalizations l10n, User user) => _Section(
    title: l10n.authPasswordLabel,
    children: [
      if (user.isGuest) ...[
        Text(l10n.accountGuestPasswordHint),
        const SizedBox(height: 12),
      ] else if (!user.hasPassword) ...[
        Text(l10n.accountPasswordSetHint),
        const SizedBox(height: 12),
      ],
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const Key('account-password'),
          onPressed: _changePassword,
          icon: const Icon(Icons.lock),
          label: Text(
            user.hasPassword && !user.isGuest
                ? l10n.accountPasswordChange
                : l10n.accountPasswordSet,
          ),
        ),
      ),
    ],
  );
}

/// One card of the page: a heading, then its content.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

/// The text of a refused rename; the backend's message is never shown.
String renameErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.usernameExists => l10n.authErrorUsernameExists,
    _ => l10n.errorGeneric,
  };
}
