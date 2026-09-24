import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../utils/app_theme.dart';
import 'player_slot_selector.dart';

/// The green of "online" and of a waiting party, as the parties list's
/// "Joined" (`PartyCard.joined`).
const Color _online = Color(0xFF4ADE80);

/// A small rounded label: a lobby setting, a bot's level.
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.text,
    this.color = AppColors.slate100,
    this.background = AppColors.slate700,
  });

  /// Colours of a bot's level: amber on a faint amber.
  const InfoChip.amber({super.key, required this.text})
    : color = AppColors.amber400,
      background = const Color(0x26FBBF24);

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );
}

/// A seat of a party lobby: the player, then what tells them apart — a
/// green dot for a human who is online, a chip with a bot's level, the
/// owner's crown (`PartyLobby.jsx:243-268`, S3 of the UX study).
class PlayerSeatTile extends StatelessWidget {
  const PlayerSeatTile({
    super.key,
    required this.player,
    required this.isOwner,
    this.online = false,
  });

  final PartyPlayer player;
  final bool isOwner;

  /// The player is connected (`ConnectedPlayersProvider`). Only shown for a
  /// human: a bot is always there.
  final bool online;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final badges = [
      if (online && !player.isBot)
        Row(
          key: Key('online-${player.userId}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.circle, size: 10, color: _online),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                l10n.lobbySeatOnline,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _online, fontSize: 13),
              ),
            ),
          ],
        ),
      if (player.isBot && player.botDifficulty != null)
        InfoChip.amber(
          key: Key('level-${player.userId}'),
          text: botDifficultyLabel(l10n, player.botDifficulty!),
        ),
      if (isOwner)
        Row(
          key: Key('host-${player.userId}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium,
              size: 16,
              color: AppColors.amber400,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                l10n.lobbySeatHost,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.amber400, fontSize: 13),
              ),
            ),
          ],
        ),
    ];
    return Card(
      key: Key('seat-${player.userId}'),
      color: AppColors.slate700,
      margin: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                player.isBot ? Icons.smart_toy : Icons.person,
                size: 18,
                color: player.isBot ? AppColors.amber400 : AppColors.slate400,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: Text(
                  player.username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              if (badges.isNotEmpty)
                Flexible(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    // Right-aligned even when narrower than its share.
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: badges,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A seat nobody holds yet. There is no "add a bot" here: neither backend
/// can seat a bot in a party that exists, so [showInviteHint] points at the
/// invite code above instead.
class EmptySeatTile extends StatelessWidget {
  const EmptySeatTile({super.key, this.showInviteHint = false});

  final bool showInviteHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate600),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.slate400),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.lobbyEmptySlot,
                  style: const TextStyle(color: AppColors.slate400),
                ),
                if (showInviteHint)
                  Text(
                    l10n.lobbyEmptySlotHint,
                    style: const TextStyle(
                      color: AppColors.slate400,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
