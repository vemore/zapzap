import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import 'connected_players.dart';
import 'connection_indicator.dart';
import 'delete_account_dialog.dart';

/// The app bar of the signed-in screens: who is online, whether the event
/// stream is up, where else to go, and the way out. Icons only, so it fits a
/// phone.
///
/// Signing out needs no navigation: the router follows [AuthProvider].
class ZapZapAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ZapZapAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  final String title;

  /// A back button, when the screen has somewhere to go back to.
  final Widget? leading;

  /// The screen's own entries of the ⋮ menu, below the destinations: what
  /// should be reachable but not a thumb away (the lobby's Delete).
  final List<AppBarMenuAction> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppBar(
      leading: leading,
      title: Text(title, overflow: TextOverflow.ellipsis),
      titleSpacing: leading == null ? null : 0,
      actions: [
        const ConnectedPlayers(),
        const ConnectionIndicator(),
        IconButton(
          key: const Key('logout'),
          tooltip: l10n.logoutButton,
          icon: const Icon(Icons.logout),
          onPressed: () => context.read<AuthProvider>().logout(),
        ),
        _NavigationMenu(actions: actions),
      ],
    );
  }
}

/// The screens the app bar leads to, as a menu rather than one button each:
/// on Android there is no URL bar, and four more icons would not fit a 360 px
/// bar at a large system font.
///
/// Admins get an Admin entry too ([AppRoutes.admin]); for anyone else the
/// router would send it back to the parties. Last, on every signed-in
/// screen, "Delete my account" ([showDeleteAccountDialog]): Google Play wants
/// it reachable from the app.
class _NavigationMenu extends StatelessWidget {
  const _NavigationMenu({required this.actions});

  final List<AppBarMenuAction> actions;

  /// The id of the "Delete my account" entry: not a route.
  static const _deleteAccount = 'delete-account';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('app-bar-menu'),
      tooltip: l10n.appBarMenu,
      position: PopupMenuPosition.under,
      // `push`, not `go`: the destination goes on top of the screen the
      // player came from, so the Android system Back button returns to it.
      onSelected: (route) {
        if (route == _deleteAccount) {
          showDeleteAccountDialog(context);
          return;
        }
        final action = actions.where((action) => action.id == route);
        if (action.isNotEmpty) {
          action.first.onSelected();
        } else {
          context.push(route);
        }
      },
      itemBuilder: (context) => [
        _item(
          key: const Key('menu-history'),
          route: AppRoutes.history,
          icon: Icons.history,
          label: l10n.historyTitle,
        ),
        _item(
          key: const Key('menu-stats'),
          route: AppRoutes.stats,
          icon: Icons.bar_chart,
          label: l10n.statsTitle,
        ),
        if (context.read<AuthProvider>().isAdmin)
          _item(
            key: const Key('menu-admin'),
            route: AppRoutes.admin,
            icon: Icons.admin_panel_settings,
            label: l10n.adminTitle,
          ),
        if (actions.isNotEmpty) const PopupMenuDivider(),
        for (final action in actions)
          _item(
            key: action.key,
            route: action.id,
            icon: action.icon,
            label: action.label,
            color: action.color,
            enabled: action.enabled,
          ),
        const PopupMenuDivider(),
        _item(
          key: const Key('menu-delete-account'),
          route: _deleteAccount,
          icon: Icons.person_remove,
          label: l10n.deleteAccountMenu,
          color: AppColors.error,
        ),
      ],
    );
  }

  /// One destination. [Flexible] around the label so a long translation at a
  /// large system font wraps instead of overflowing the menu.
  PopupMenuItem<String> _item({
    required Key key,
    required String route,
    required IconData icon,
    required String label,
    Color? color,
    bool enabled = true,
  }) => PopupMenuItem<String>(
    key: key,
    value: route,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label, style: TextStyle(color: color)),
        ),
      ],
    ),
  );
}

/// An entry a screen adds to the app bar's ⋮ menu.
class AppBarMenuAction {
  const AppBarMenuAction({
    required this.id,
    required this.key,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.color,
    this.enabled = true,
  });

  /// Tells it apart from the destinations, which are routes: never one
  /// starting with `/`.
  final String id;
  final Key key;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final Color? color;
  final bool enabled;
}
