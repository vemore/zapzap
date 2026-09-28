import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../models/bot.dart';
import '../utils/app_theme.dart';

/// A bot difficulty, localised; an unknown one (`ml`, `drl`) shows the
/// backend's own word.
String botDifficultyLabel(AppLocalizations l10n, String difficulty) =>
    switch (difficulty) {
      'easy' => l10n.botDifficultyEasy,
      'medium' => l10n.botDifficultyMedium,
      'hard' => l10n.botDifficultyHard,
      'hard_vince' => l10n.botDifficultyHardVince,
      'llm' => l10n.botDifficultyLlm,
      'thibot' => l10n.botDifficultyThibot,
      _ => difficulty,
    };

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

/// A seat nobody holds yet. For the host ([onAddBot] given) it carries « Ajouter
/// un bot », a menu of [botDifficulties]: one whose bots all sit elsewhere
/// ([availableBots] 0) is shown disabled, "none available". [showInviteHint]
/// points at the invite code above.
class EmptySeatTile extends StatelessWidget {
  const EmptySeatTile({
    super.key,
    this.showInviteHint = false,
    this.onAddBot,
    this.availableBots,
    this.enabled = true,
    this.addBotKey,
  });

  final bool showInviteHint;

  /// Seats a bot of the difficulty picked; `null` hides the button.
  final void Function(String difficulty)? onAddBot;

  /// How many bots of a difficulty are free to sit here.
  final int Function(String difficulty)? availableBots;

  /// `false` while another lobby action runs.
  final bool enabled;

  /// The key of the « Ajouter un bot » button.
  final Key? addBotKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onAddBot = this.onAddBot;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate600),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, size: 18, color: AppColors.slate400),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
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
          ),
          if (onAddBot != null)
            Flexible(
              // At the seat's right edge, however narrow the button is
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PopupMenuButton<String>(
                  key: addBotKey,
                  enabled: enabled,
                  tooltip: l10n.lobbyAddBot,
                  onSelected: onAddBot,
                  itemBuilder: (context) => [
                    for (final difficulty in botDifficulties)
                      _difficultyItem(l10n, difficulty),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 18,
                          color: enabled
                              ? AppColors.amber400
                              : AppColors.slate600,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            l10n.lobbyAddBot,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: enabled
                                  ? AppColors.amber400
                                  : AppColors.slate600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _difficultyItem(
    AppLocalizations l10n,
    String difficulty,
  ) {
    final free = (availableBots?.call(difficulty) ?? 0) > 0;
    final label = botDifficultyLabel(l10n, difficulty);
    return PopupMenuItem(
      key: Key('add-bot-$difficulty'),
      value: difficulty,
      enabled: free,
      child: Text(free ? label : l10n.lobbyAddBotUnavailable(label)),
    );
  }
}
