import 'package:flutter/material.dart' hide Page;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../models/json.dart';
import '../providers/auth_provider.dart';
import '../repositories/admin_repository.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'error_banner.dart';

/// The localised text of an admin failure: the backend's message is never
/// shown, only its code or status is read ([ApiException.code]).
String adminErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    // Node answers 400 for oneself and the default admin, without a code.
    ApiErrorCode.badRequest => l10n.adminErrorRefused,
    ApiErrorCode.adminRequired ||
    ApiErrorCode.forbidden => l10n.adminErrorForbidden,
    ApiErrorCode.notFound => l10n.adminErrorUserNotFound,
    _ => l10n.errorGeneric,
  };
}

/// The users tab of the admin screen, the port of
/// `frontend/src/components/Admin/Users/UserList.jsx`: the human accounts,
/// [pageSize] at a time from `GET /admin/users`, a search that filters the
/// page on show, and on every row but the admin's own and [defaultAdmin]'s
/// a toggle of the admin rights and a delete, each confirmed first.
///
/// The backend enforces all of it: hiding the buttons only spares a refusal.
class AdminUsersView extends StatefulWidget {
  const AdminUsersView({super.key});

  /// The rows asked for at a time, as React does.
  static const pageSize = 50;

  /// The account the backends never let anyone delete
  /// (`src/use-cases/admin/DeleteUser.js:46`).
  static const defaultAdmin = 'admin';

  /// A total play time as React writes it: `0h`, `5m`, `2h 5m`.
  static String playTime(int seconds) {
    if (seconds <= 0) return '0h';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return hours == 0 ? '${minutes}m' : '${hours}h ${minutes}m';
  }

  @override
  State<AdminUsersView> createState() => _AdminUsersViewState();
}

class _AdminUsersViewState extends State<AdminUsersView> {
  final _search = TextEditingController();
  int _offset = 0;
  Page<AdminUser>? _page;
  Object? _error;
  bool _loading = true;

  /// The account an action is running on: its buttons give way to a spinner.
  String? _busy;

  /// Tells the latest load apart, so an earlier one answering late is
  /// dropped rather than shown over it.
  int _generation = 0;

  AdminRepository get _admin => context.read<AdminRepository>();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final Page<AdminUser> page;
    try {
      page = await _admin.users(
        limit: AdminUsersView.pageSize,
        offset: _offset,
      );
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    // The last row of a later page deleted: back to the page before.
    if (page.items.isEmpty && _offset > 0) {
      _offset = (_offset - AdminUsersView.pageSize).clamp(0, _offset);
      return _load();
    }
    setState(() {
      _page = page;
      _loading = false;
    });
  }

  void _goTo(int offset) {
    _offset = offset;
    _load();
  }

  Future<bool> _confirm({
    required Key key,
    required String message,
    required String confirmLabel,
    Color? confirmColor,
  }) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: key,
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            key: const Key('admin-confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _toggleAdmin(AdminUser user) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      key: const Key('admin-toggle-confirm'),
      message: user.isAdmin
          ? l10n.adminRevokeConfirm(user.username)
          : l10n.adminGrantConfirm(user.username),
      confirmLabel: l10n.adminConfirmButton,
    );
    if (!confirmed || !mounted) return;
    await _act(user, () => _admin.setAdmin(user.id, isAdmin: !user.isAdmin));
  }

  Future<void> _delete(AdminUser user) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await _confirm(
      key: const Key('admin-delete-confirm'),
      message: l10n.adminDeleteUserConfirm(user.username),
      confirmLabel: l10n.deleteButton,
      confirmColor: AppColors.error,
    );
    if (!confirmed || !mounted) return;
    await _act(user, () => _admin.deleteUser(user.id));
  }

  /// Runs [action] on [user], then reloads the page; a refusal is a snack
  /// bar and the list stays.
  Future<void> _act(AdminUser user, Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = user.id);
    try {
      await action();
      if (mounted) await _load();
    } on Object catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(adminErrorText(l10n, error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final page = _page;
    final error = _error;
    if (page == null) {
      if (error == null) {
        return Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.loading),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(
          key: const Key('admin-users-error'),
          message: l10n.adminUsersLoadError,
          onRetry: _load,
        ),
      );
    }

    final myId = context.watch<AuthProvider>().user?.id;
    final query = _search.text.trim().toLowerCase();
    final users = [
      for (final user in page.items)
        if (user.username.toLowerCase().contains(query)) user,
    ];
    final total = page.total ?? page.items.length;
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            key: const Key('admin-users-list'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Text(
                l10n.adminUsersCount(total),
                key: const Key('admin-users-count'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('admin-users-search'),
                controller: _search,
                decoration: InputDecoration(
                  hintText: l10n.adminUsersSearch,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (error != null) ...[
                ErrorBanner(
                  key: const Key('admin-users-error'),
                  message: adminErrorText(l10n, error),
                  onRetry: _load,
                ),
                const SizedBox(height: 12),
              ],
              if (users.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    query.isEmpty
                        ? l10n.adminUsersEmpty
                        : l10n.adminUsersNoMatch,
                    key: const Key('admin-users-empty'),
                    textAlign: TextAlign.center,
                  ),
                ),
              for (final user in users)
                AdminUserTile(
                  key: Key('admin-user-${user.id}'),
                  user: user,
                  isSelf: user.id == myId,
                  busy: _busy == user.id,
                  onToggleAdmin: _busy == null
                      ? () => _toggleAdmin(user)
                      : null,
                  onDelete: _busy == null ? () => _delete(user) : null,
                ),
              if (total > AdminUsersView.pageSize)
                _Pager(
                  offset: _offset,
                  total: total,
                  onPage: _loading ? null : _goTo,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Previous, the rows on show, next.
class _Pager extends StatelessWidget {
  const _Pager({
    required this.offset,
    required this.total,
    required this.onPage,
  });

  final int offset;
  final int total;

  /// Null while a page loads.
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const size = AdminUsersView.pageSize;
    final last = (offset + size).clamp(0, total);
    final onPage = this.onPage;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            key: const Key('admin-users-previous'),
            onPressed: onPage == null || offset == 0
                ? null
                : () => onPage((offset - size).clamp(0, offset)),
            child: Text(l10n.adminPreviousPage),
          ),
          Text(
            l10n.adminPageRange(offset + 1, last, total),
            key: const Key('admin-users-range'),
          ),
          OutlinedButton(
            key: const Key('admin-users-next'),
            onPressed: onPage == null || last >= total
                ? null
                : () => onPage(offset + size),
            child: Text(l10n.adminNextPage),
          ),
        ],
      ),
    );
  }
}

/// One account: its name and badges, its dates and play, and — unless it is
/// [isSelf] or the default admin — its two actions.
class AdminUserTile extends StatelessWidget {
  const AdminUserTile({
    super.key,
    required this.user,
    required this.isSelf,
    required this.busy,
    this.onToggleAdmin,
    this.onDelete,
  });

  final AdminUser user;
  final bool isSelf;

  /// An action on this account is running.
  final bool busy;
  final VoidCallback? onToggleAdmin;
  final VoidCallback? onDelete;

  /// Whether the actions show: never on one's own row nor on the default
  /// admin's, as in React.
  bool get hasActions =>
      !isSelf && user.username != AdminUsersView.defaultAdmin;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.slate400,
    );
    final lastLogin = user.lastLoginAt;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        user.username,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isSelf)
                        _Badge(
                          key: const Key('admin-user-you'),
                          label: l10n.adminUserYou,
                        ),
                      if (user.isAdmin)
                        _Badge(
                          key: const Key('admin-user-admin'),
                          label: l10n.adminUserAdminBadge,
                          icon: Icons.shield,
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.adminUserCreated(
                      Formats.dateTime(user.createdAt, locale),
                    ),
                    style: muted,
                  ),
                  Text(
                    lastLogin == null
                        ? l10n.adminUserNeverLoggedIn
                        : l10n.adminUserLastLogin(
                            Formats.dateTime(lastLogin, locale),
                          ),
                    style: muted,
                  ),
                  Text(
                    '${l10n.gameCount(user.gamesPlayed)} · '
                    '${l10n.adminUserPlayTime(AdminUsersView.playTime(user.totalPlayTimeSeconds))}',
                    style: muted,
                  ),
                ],
              ),
            ),
            if (hasActions)
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else ...[
                IconButton(
                  key: Key('admin-toggle-${user.id}'),
                  tooltip: user.isAdmin
                      ? l10n.adminRevokeAdmin
                      : l10n.adminGrantAdmin,
                  icon: Icon(
                    user.isAdmin ? Icons.remove_moderator : Icons.add_moderator,
                  ),
                  color: AppColors.amber400,
                  onPressed: onToggleAdmin,
                ),
                IconButton(
                  key: Key('admin-delete-${user.id}'),
                  tooltip: l10n.adminDeleteUser,
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.error,
                  onPressed: onDelete,
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amber400.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.amber400),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: AppColors.amber400),
            ),
          ),
        ],
      ),
    );
  }
}
