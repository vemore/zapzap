import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

/// The parties (lobby). A placeholder until the lobby lands: who is signed
/// in, and the way out. Signing out needs no navigation: the router follows
/// [AuthProvider] to the login screen.
class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.watch<AuthProvider>().user;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.partiesTitle),
        actions: [
          IconButton(
            key: const Key('logout'),
            tooltip: l10n.logoutButton,
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (user != null)
              Text(
                l10n.partiesWelcome(user.username),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            const SizedBox(height: 8),
            Text(l10n.partiesComingSoon),
          ],
        ),
      ),
    );
  }
}
