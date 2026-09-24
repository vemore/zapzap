import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/party.dart';
import '../providers/auth_provider.dart';
import '../providers/connected_players_provider.dart';
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

/// One party's lobby (`PartyLobby.jsx`, S1–S4 of the UX study): the invite
/// code and a Copy button, the settings as chips, its seats — taken, with who
/// is online and each bot's level, and empty —, then, pinned at the bottom,
/// why Start is or is not active, Start (owner only, 3 players at least) and
/// Leave. Delete (the owner, or the only human at the table) is in the ⋮
/// menu.
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

  Future<void> _copyInviteCode(String code) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(l10n.lobbyInviteCodeCopied)));
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
          // Delete sits in the ⋮ menu, away from the thumb (S4); it still
          // asks first.
          actions: [
            if (_lobby.canDelete)
              AppBarMenuAction(
                id: 'delete-party',
                key: const Key('delete-party'),
                icon: Icons.delete_outline,
                label: l10n.lobbyDeleteButton,
                color: AppColors.error,
                enabled: !_lobby.busy,
                onSelected: _confirmDelete,
              ),
          ],
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
            final inviteCode = details.party.inviteCode;
            return Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _lobby.load(showSpinner: false),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      children: [
                        if (inviteCode != null && inviteCode.isNotEmpty) ...[
                          _inviteCode(context, inviteCode),
                          const SizedBox(height: 12),
                        ],
                        _settings(context, details),
                        const SizedBox(height: 20),
                        _seatsHeader(context),
                        const SizedBox(height: 8),
                        ..._seats(
                          inviteHint:
                              inviteCode != null && inviteCode.isNotEmpty,
                        ),
                      ],
                    ),
                  ),
                ),
                _actions(context),
              ],
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

  /// S1: the code a friend types to join, big, and one tap to copy it.
  Widget _inviteCode(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    return Card(
      key: const Key('lobby-invite'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.lobbyInviteCodeLabel.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.slate400,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.96,
                  ),
                ),
                SelectableText(
                  code,
                  key: const Key('invite-code'),
                  style: const TextStyle(
                    color: AppColors.amber400,
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Roboto Mono', 'Courier'],
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.6,
                    height: 1.2,
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              key: const Key('copy-invite-code'),
              onPressed: () => _copyInviteCode(code),
              icon: const Icon(Icons.copy, size: 18),
              label: Text(l10n.lobbyCopyInviteCode),
            ),
          ],
        ),
      ),
    );
  }

  /// S2: the settings as one line of chips — seats, the hand size where the
  /// party carries one, "you host", the status.
  Widget _settings(BuildContext context, PartyDetails details) {
    final l10n = AppLocalizations.of(context);
    final status = details.party.status;
    return Wrap(
      key: const Key('lobby-settings'),
      spacing: 8,
      runSpacing: 8,
      children: [
        InfoChip(text: l10n.lobbySeatsChip(_lobby.maxPlayers)),
        // Only the Rust backend carries a party hand size; on Node the
        // starting player picks it each round (`GAME_RULES.md`), so there
        // is nothing to show.
        if (details.party.settings.handSize != null)
          InfoChip(
            text: l10n.lobbyHandSizeChip(details.party.settings.handSize!),
          ),
        if (_lobby.isOwner) InfoChip(text: l10n.lobbyYouHostChip),
        InfoChip(
          key: const Key('lobby-status'),
          text: partyStatusText(l10n, status),
          color: status == PartyStatus.waiting
              ? PartyCard.joined
              : AppColors.slate100,
        ),
      ],
    );
  }

  Widget _seatsHeader(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      l10n.lobbyPlayersTitle(_lobby.playerCount, _lobby.maxPlayers),
      key: const Key('lobby-seats-header'),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }

  /// S3: a human who is online wears a green dot. The signed-in player is
  /// online by definition; the others, when `ConnectedPlayersProvider` has
  /// them — it holds five at most, so an absent dot means "not known to be
  /// online", and nothing says "offline".
  List<Widget> _seats({required bool inviteHint}) {
    final ownerId = _lobby.details?.party.ownerId;
    final me = _lobby.currentUserId;
    final online = {
      for (final player in context.watch<ConnectedPlayersProvider>().players)
        player.userId,
      ?me,
    };
    final empty = _lobby.maxPlayers - _lobby.playerCount;
    return [
      for (final player in _lobby.players)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PlayerSeatTile(
            player: player,
            isOwner: ownerId != null && player.userId == ownerId,
            online: online.contains(player.userId),
          ),
        ),
      for (var index = 0; index < empty; index++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          // The hint once, on the first free seat: repeated on each it
          // would be noise.
          child: EmptySeatTile(
            key: Key('empty-seat-$index'),
            showInviteHint: inviteHint && index == 0,
          ),
        ),
    ];
  }

  /// S4: why Start is (or is not) active, Start itself for the owner, then
  /// Leave — pinned under the list, so they never scroll away.
  Widget _actions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final missing = _lobby.missingPlayers;
    final reason = missing > 0
        ? l10n.lobbyNeedMorePlayers(missing)
        : _lobby.isOwner
        ? l10n.lobbyCanStart(minPartyPlayers)
        : l10n.lobbyWaitingForHost;
    return Material(
      color: AppColors.slate800,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lobby.error != null) ...[
                ErrorBanner(message: partyErrorText(l10n, _lobby.error!)),
                const SizedBox(height: 8),
              ],
              Row(
                key: const Key('start-reason'),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    missing > 0 ? Icons.hourglass_empty : Icons.check,
                    size: 16,
                    color: missing > 0
                        ? AppColors.amber400
                        : AppColors.slate400,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: missing > 0
                            ? AppColors.amber400
                            : AppColors.slate400,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_lobby.isOwner) ...[
                FilledButton.icon(
                  key: const Key('start-party'),
                  onPressed: _lobby.canStart ? _lobby.start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.lobbyStartWithCount(_lobby.playerCount)),
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                key: const Key('leave-party'),
                onPressed: _lobby.busy ? null : _lobby.leave,
                icon: const Icon(Icons.logout),
                label: Text(l10n.lobbyLeaveButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
