import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../providers/connected_players_provider.dart';
import '../utils/app_theme.dart';

/// Who is online, as an app-bar button showing how many, opening the list
/// with each one's status (`ConnectedPlayers.jsx`).
class ConnectedPlayers extends StatelessWidget {
  const ConnectedPlayers({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = context.watch<ConnectedPlayersProvider>();
    final players = online.players;
    return PopupMenuButton<void>(
      key: const Key('connected-players'),
      tooltip: l10n.connectedPlayersTitle,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: Text(
            l10n.connectedPlayersTitle,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (players.isEmpty)
          PopupMenuItem<void>(
            enabled: false,
            child: Text(l10n.connectedPlayersEmpty),
          )
        else
          for (final player in players)
            PopupMenuItem<void>(
              enabled: false,
              child: _PlayerRow(player: player),
            ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group, size: 18),
            const SizedBox(width: 4),
            // No count before the first answer, nor after a failed one:
            // "0" would claim nobody is online (React renders nothing while
            // loading, `ConnectedPlayers.jsx`).
            Text(
              online.loaded ? '${players.length}' : '–',
              key: const Key('connected-players-count'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player});

  final ConnectedPlayer player;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = switch (player.status) {
      'party' => (l10n.playerStatusParty, AppColors.amber400),
      'game' => (l10n.playerStatusGame, AppColors.error),
      _ => (l10n.playerStatusLobby, _online),
    };
    return Row(
      children: [
        Expanded(child: Text(player.username, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}

/// Tailwind `green-400`, the React `bg-green-500` dot of the lobby status.
const Color _online = Color(0xFF4ADE80);
