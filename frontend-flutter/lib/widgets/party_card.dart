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

/// One party in the list, in two lines: its name and a badge, then
/// "players · status" and the one thing to do with it
/// (`PartyList.jsx:160-220`, made compact).
///
/// A running game of mine is the card that stands out: an amber border, an
/// "In progress" badge and the only filled button, Resume. Its lobby and
/// someone else's party get an outlined button, Lobby or Join.
class PartyCard extends StatelessWidget {
  const PartyCard({
    super.key,
    required this.party,
    required this.onJoin,
    required this.onOpen,
    this.isHost = false,
  });

  final PartySummary party;

  /// Take a seat, then open the lobby.
  final VoidCallback onJoin;

  /// Go back to a party the user is already in: its game when it is
  /// playing, its lobby otherwise.
  final VoidCallback onOpen;

  /// The signed-in user created this party: the second line says so.
  final bool isHost;

  /// Tailwind `green-400`, the React Joined badge.
  static const joined = Color(0xFF4ADE80);

  /// The one button's size: 44 px high, a tap target, and no wider than its
  /// label — the theme's 200 px minimum is a form's full-width button.
  static const _buttonSize = Size(64, 44);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final playing = party.status == PartyStatus.playing;
    final full = party.playerCount >= party.maxPlayers;
    final open = !playing && party.status != PartyStatus.finished && !full;
    final resume = party.isMember && playing;
    final details = [
      l10n.partyPlayersCount(party.playerCount, party.maxPlayers),
      // The badge already says "In progress".
      if (!resume) partyStatusText(l10n, party.status),
      if (isHost) l10n.partyCardHost,
    ].join(' · ');
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.slate400,
    );
    return Card(
      key: Key('party-${party.id}'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: resume
            ? const BorderSide(color: AppColors.amber400, width: 2)
            : BorderSide(color: party.isMember ? joined : AppColors.slate600),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    party.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (resume)
                  _Badge(
                    key: Key('in-progress-${party.id}'),
                    text: l10n.partyInProgressBadge,
                    color: AppColors.slate900,
                    background: AppColors.amber400,
                  )
                else if (party.isMember)
                  _Badge(
                    key: Key('joined-${party.id}'),
                    text: l10n.partyJoinedBadge,
                    color: joined,
                    background: joined.withValues(alpha: 0.15),
                    border: joined,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  // "players" is an icon, so the line fits beside the
                  // button on a phone.
                  child: Text.rich(
                    key: Key('party-details-${party.id}'),
                    TextSpan(
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.group_outlined,
                              size: 16,
                              color: AppColors.slate400,
                              semanticLabel: l10n.partyPlayersLabel,
                            ),
                          ),
                        ),
                        TextSpan(text: details),
                      ],
                    ),
                    style: muted,
                  ),
                ),
                const SizedBox(width: 8),
                _action(l10n, playing: playing, full: full, open: open),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _action(
    AppLocalizations l10n, {
    required bool playing,
    required bool full,
    required bool open,
  }) {
    if (party.isMember && playing) {
      return FilledButton(
        key: Key('open-${party.id}'),
        style: FilledButton.styleFrom(minimumSize: _buttonSize),
        onPressed: onOpen,
        child: Text(l10n.partyResumeButton),
      );
    }
    final outlined = OutlinedButton.styleFrom(
      minimumSize: _buttonSize,
      foregroundColor: AppColors.amber400,
      side: const BorderSide(color: AppColors.slate600),
    );
    if (party.isMember) {
      return OutlinedButton(
        key: Key('open-${party.id}'),
        style: outlined,
        onPressed: onOpen,
        child: Text(l10n.partyLobbyButton),
      );
    }
    return OutlinedButton(
      key: Key('join-${party.id}'),
      style: outlined,
      onPressed: open ? onJoin : null,
      child: Text(switch (party.status) {
        PartyStatus.playing => l10n.partyInProgressBadge,
        PartyStatus.finished => l10n.partyStatusFinished,
        _ when full => l10n.partyFullButton,
        _ => l10n.partyJoinButton,
      }),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    super.key,
    required this.text,
    required this.color,
    required this.background,
    this.border,
  });

  final String text;
  final Color color;
  final Color background;
  final Color? border;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        border: border == null ? null : Border.all(color: border!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
