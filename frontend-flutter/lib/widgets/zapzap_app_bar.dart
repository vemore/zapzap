import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import 'connected_players.dart';
import 'connection_indicator.dart';

/// The app bar of the signed-in screens: who is online, whether the event
/// stream is up, and the way out. Icons only, so it fits a phone.
///
/// Signing out needs no navigation: the router follows [AuthProvider].
class ZapZapAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ZapZapAppBar({super.key, required this.title, this.leading});

  final String title;

  /// A back button, when the screen has somewhere to go back to.
  final Widget? leading;

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
      ],
    );
  }
}
