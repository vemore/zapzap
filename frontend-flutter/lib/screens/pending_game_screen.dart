import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../router.dart';
import '../widgets/zapzap_app_bar.dart';

/// Stands in for the game board at `/game/:id` until it exists: the lobby
/// has to have somewhere to send a started party. The game-board pull
/// request replaces this route's builder with the real screen.
class PendingGameScreen extends StatelessWidget {
  const PendingGameScreen({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(
        title: l10n.gamePlaceholderTitle,
        leading: IconButton(
          key: const Key('back-to-parties'),
          tooltip: l10n.lobbyBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.parties),
        ),
      ),
      body: Center(child: Text(l10n.gamePlaceholderBody)),
    );
  }
}
