import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../utils/app_theme.dart';
import 'player_slot_selector.dart';

/// A seat of a party lobby: the player, a bot badge with its difficulty,
/// and the owner's crown (`PartyLobby.jsx:243-268`).
class PlayerSeatTile extends StatelessWidget {
  const PlayerSeatTile({
    super.key,
    required this.player,
    required this.isOwner,
  });

  final PartyPlayer player;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: Key('seat-${player.userId}'),
      color: AppColors.slate700,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              player.isBot ? Icons.smart_toy : Icons.person,
              size: 18,
              color: player.isBot ? AppColors.amber400 : AppColors.slate400,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(player.username, overflow: TextOverflow.ellipsis),
            ),
            if (player.isBot && player.botDifficulty != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  botDifficultyLabel(l10n, player.botDifficulty!),
                  style: const TextStyle(
                    color: AppColors.amber400,
                    fontSize: 12,
                  ),
                ),
              ),
            if (isOwner)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: l10n.createPartyOwnerBadge,
                  child: const Icon(
                    Icons.workspace_premium,
                    size: 18,
                    color: AppColors.amber400,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A seat nobody holds yet.
class EmptySeatTile extends StatelessWidget {
  const EmptySeatTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate600),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.slate600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.lobbyEmptySlot,
              style: const TextStyle(color: AppColors.slate400),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
