import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../providers/auth_provider.dart';
import '../providers/party_provider.dart';
import '../providers/sse_provider.dart';
import '../repositories/party_repository.dart';
import '../router.dart';
import '../utils/app_theme.dart';
import '../utils/navigation.dart';
import '../widgets/error_banner.dart';
import '../widgets/party_card.dart';
import '../widgets/player_seat_tile.dart';
import '../widgets/zapzap_app_bar.dart';

/// One party's lobby (`PartyLobby.jsx`): its settings, its seats — taken
/// and empty —, and start (owner only, 3 players at least), leave and
/// delete (the owner, or the only human at the table).
///
/// The event stream drives it: a player joining or leaving reloads the
/// seats without a refresh, the party starting goes to the game, the party
/// being deleted goes back to the list.
class PartyLobbyScreen extends StatefulWidget {
  const PartyLobbyScreen({super.key, required this.partyId});

  final String partyId;

  @override
  State<PartyLobbyScreen> createState() => _PartyLobbyScreenState();
}

class _PartyLobbyScreenState extends State<PartyLobbyScreen> {
  late final PartyLobbyProvider _lobby;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _lobby = PartyLobbyProvider(
      context.read<PartyRepository>(),
      partyId: widget.partyId,
      events: context.read<SseProvider>().events,
      currentUserId: context.read<AuthProvider>().user?.id,
    );
    _lobby.addListener(_followOutcome);
    _lobby.load();
  }

  @override
  void dispose() {
    _lobby.removeListener(_followOutcome);
    _lobby.dispose();
    super.dispose();
  }

  /// The one place this screen navigates from: whatever set the outcome —
  /// a button here, or an event from another client — leads to the same
  /// route.
  void _followOutcome() {
    if (_left || _lobby.outcome == null || !mounted) return;
    _left = true;
    final outcome = _lobby.outcome!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (outcome) {
        // The game takes the lobby's place, so Back from it returns to the
        // list below, as the game's own back button does.
        case LobbyOutcome.started:
          context.replaceWith(AppRoutes.gamePath(widget.partyId));
        case LobbyOutcome.closed:
          context.popOrGo(AppRoutes.parties);
      }
    });
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('delete-confirm'),
        title: Text(l10n.lobbyDeleteConfirmTitle),
        content: Text(l10n.lobbyDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancelButton),
          ),
          TextButton(
            key: const Key('delete-confirm-ok'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteButton),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await _lobby.delete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: _lobby,
      builder: (context, _) => Scaffold(
        appBar: ZapZapAppBar(
          title: _lobby.details?.party.name ?? l10n.partiesTitle,
          leading: IconButton(
            key: const Key('back-to-parties'),
            tooltip: l10n.lobbyBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.popOrGo(AppRoutes.parties),
          ),
        ),
        body: Builder(
          builder: (context) {
            if (_lobby.loading) {
              return Center(
                child: CircularProgressIndicator(
                  semanticsLabel: l10n.lobbyLoading,
                ),
              );
            }
            final details = _lobby.details;
            if (details == null) return _notFound(context);
            return RefreshIndicator(
              onRefresh: () => _lobby.load(showSpinner: false),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Text(
                    details.party.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _settings(context, details),
                  const SizedBox(height: 24),
                  _seatsHeader(context),
                  const SizedBox(height: 8),
                  ..._seats(),
                  if (_lobby.error != null) ...[
                    const SizedBox(height: 16),
                    ErrorBanner(message: partyErrorText(l10n, _lobby.error!)),
                  ],
                  const SizedBox(height: 24),
                  if (_lobby.isOwner)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: FilledButton.icon(
                        key: const Key('start-party'),
                        onPressed: _lobby.canStart ? _lobby.start : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.lobbyStartButton),
                      ),
                    ),
                  OutlinedButton.icon(
                    key: const Key('leave-party'),
                    onPressed: _lobby.busy ? null : _lobby.leave,
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.lobbyLeaveButton),
                  ),
                  if (_lobby.canDelete)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: OutlinedButton.icon(
                        key: const Key('delete-party'),
                        onPressed: _lobby.busy ? null : _confirmDelete,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(l10n.lobbyDeleteButton),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _notFound(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 56),
            const SizedBox(height: 12),
            Text(
              l10n.lobbyNotFoundTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(l10n.lobbyNotFoundBody, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.popOrGo(AppRoutes.parties),
              child: Text(l10n.lobbyBack),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settings(BuildContext context, PartyDetails details) {
    final l10n = AppLocalizations.of(context);
    return Card(
      color: AppColors.slate700,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, size: 18),
                const SizedBox(width: 8),
                Text(
                  l10n.lobbySettingsTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row(l10n.lobbyMaxPlayers, '${_lobby.maxPlayers}'),
            // Only the Rust backend carries a party hand size; on Node the
            // starting player picks it each round (`GAME_RULES.md`), so
            // there is nothing to show.
            if (details.party.settings.handSize != null)
              _row(l10n.lobbyHandSize, '${details.party.settings.handSize}'),
            _row(
              l10n.partyStatusLabel,
              partyStatusText(l10n, details.party.status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
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
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  Widget _seatsHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          l10n.lobbyPlayersTitle(_lobby.playerCount, _lobby.maxPlayers),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_lobby.missingPlayers > 0)
          Text(
            l10n.lobbyNeedMorePlayers(_lobby.missingPlayers),
            style: const TextStyle(color: AppColors.amber400),
          ),
      ],
    );
  }

  List<Widget> _seats() {
    final ownerId = _lobby.details?.party.ownerId;
    final empty = _lobby.maxPlayers - _lobby.playerCount;
    return [
      for (final player in _lobby.players)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlayerSeatTile(
            player: player,
            isOwner: ownerId != null && player.userId == ownerId,
          ),
        ),
      for (var index = 0; index < empty; index++)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: EmptySeatTile(),
        ),
    ];
  }
}
