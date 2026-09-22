import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../utils/app_theme.dart';

/// A party's status, localised.
String partyStatusText(AppLocalizations l10n, String status) =>
    switch (status) {
      PartyStatus.playing => l10n.partyStatusPlaying,
      PartyStatus.finished => l10n.partyStatusFinished,
      _ => l10n.partyStatusWaiting,
    };

/// One party in the list: its name, a Joined badge, how many players out of
/// how many seats, its status, and the one thing to do with it
/// (`PartyList.jsx:160-220`).
class PartyCard extends StatelessWidget {
  const PartyCard({
    super.key,
    required this.party,
    required this.onJoin,
    required this.onOpen,
  });

  final PartySummary party;

  /// Take a seat, then open the lobby.
  final VoidCallback onJoin;

  /// Go back to a party the user is already in: its game when it is
  /// playing, its lobby otherwise.
  final VoidCallback onOpen;

  /// Tailwind `green-400`, the React Joined badge.
  static const _joined = Color(0xFF4ADE80);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playing = party.status == PartyStatus.playing;
    final full = party.playerCount >= party.maxPlayers;
    final open = !playing && party.status != PartyStatus.finished && !full;
    return Card(
      key: Key('party-${party.id}'),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: party.isMember ? _joined : AppColors.slate600),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    party.name,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (party.isMember)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _joined.withValues(alpha: 0.15),
                      border: Border.all(color: _joined),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      l10n.partyJoinedBadge,
                      style: const TextStyle(color: _joined, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _Line(
              label: l10n.partyPlayersLabel,
              value: l10n.partyPlayersCount(
                party.playerCount,
                party.maxPlayers,
              ),
            ),
            const SizedBox(height: 4),
            _Line(
              label: l10n.partyStatusLabel,
              value: partyStatusText(l10n, party.status),
              valueColor: playing ? AppColors.amber400 : _joined,
            ),
            const SizedBox(height: 16),
            if (party.isMember)
              FilledButton(
                key: Key('open-${party.id}'),
                onPressed: onOpen,
                child: Text(
                  playing
                      ? l10n.partyContinueButton
                      : l10n.partyReturnToLobbyButton,
                ),
              )
            else
              FilledButton(
                key: Key('join-${party.id}'),
                onPressed: open ? onJoin : null,
                child: Text(switch (party.status) {
                  PartyStatus.playing => l10n.partyInProgressButton,
                  PartyStatus.finished => l10n.partyStatusFinished,
                  _ when full => l10n.partyFullButton,
                  _ => l10n.partyJoinButton,
                }),
              ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: AppColors.slate400),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.w600),
        ),
      ),
    ],
  );
}
