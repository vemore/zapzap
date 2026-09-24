import 'package:flutter/material.dart' hide Page;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../models/json.dart';
import '../models/party.dart';
import '../repositories/admin_repository.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'admin_common.dart';
import 'error_banner.dart';
import 'stats_common.dart';

/// The parties tab of the admin screen, the port of
/// `frontend/src/components/Admin/Parties/AdminPartyList.jsx`: every party,
/// [pageSize] at a time from `GET /admin/parties`, a status filter the
/// backend applies (`?status=`), and on each row a stop (unless finished)
/// and a delete, each confirmed first.
class AdminPartiesView extends StatefulWidget {
  const AdminPartiesView({super.key});

  /// The rows asked for at a time, as React does.
  static const pageSize = 50;

  /// The filter choices, null for every status.
  static const filters = <String?>[
    null,
    PartyStatus.waiting,
    PartyStatus.playing,
    PartyStatus.finished,
  ];

  @override
  State<AdminPartiesView> createState() => _AdminPartiesViewState();
}

class _AdminPartiesViewState extends State<AdminPartiesView> {
  String? _status;
  int _offset = 0;
  Page<AdminParty>? _page;
  Object? _error;
  bool _loading = true;

  /// The party an action is running on: its buttons give way to a spinner.
  String? _busy;

  /// Tells the latest load apart, so an earlier one answering late (a
  /// filter changed quickly) is dropped rather than shown over it.
  int _generation = 0;

  AdminRepository get _admin => context.read<AdminRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    final Page<AdminParty> page;
    try {
      page = await _admin.parties(
        status: _status,
        limit: AdminPartiesView.pageSize,
        offset: _offset,
      );
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
      return;
    }
    if (!mounted || generation != _generation) return;
    // The last row of a later page deleted: back to the page before.
    if (page.items.isEmpty && _offset > 0) {
      _offset = (_offset - AdminPartiesView.pageSize).clamp(0, _offset);
      return _load();
    }
    setState(() {
      _page = page;
      _loading = false;
    });
  }

  void _filter(String? status) {
    if (status == _status) return;
    _status = status;
    _offset = 0;
    _load();
  }

  void _goTo(int offset) {
    _offset = offset;
    _load();
  }

  Future<void> _stop(AdminParty party) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmAdminAction(
      context,
      key: const Key('admin-party-stop-confirm'),
      message: l10n.adminStopPartyConfirm(party.name),
      confirmLabel: l10n.adminStopParty,
      confirmColor: AppColors.amber400,
    );
    if (!confirmed || !mounted) return;
    await _act(party, () => _admin.stopParty(party.id));
  }

  Future<void> _delete(AdminParty party) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await confirmAdminAction(
      context,
      key: const Key('admin-party-delete-confirm'),
      message: l10n.adminDeletePartyConfirm(party.name),
      confirmLabel: l10n.deleteButton,
      confirmColor: AppColors.error,
    );
    if (!confirmed || !mounted) return;
    await _act(party, () => _admin.deleteParty(party.id));
  }

  /// Runs [action] on [party], then reloads the page; a refusal is a snack
  /// bar and the list stays.
  Future<void> _act(AdminParty party, Future<void> Function() action) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = party.id);
    try {
      await action();
      if (mounted) await _load();
    } on Object catch (error) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(_errorText(l10n, error))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static String _errorText(AppLocalizations l10n, Object error) =>
      adminErrorText(
        l10n,
        error,
        // Node answers 400 when stopping a finished party.
        refused: l10n.adminErrorPartyRefused,
        notFound: l10n.errorPartyNotFound,
      );

  String _filterLabel(AppLocalizations l10n, String? status) =>
      switch (status) {
        PartyStatus.waiting => l10n.partyStatusWaiting,
        PartyStatus.playing => l10n.partyStatusPlaying,
        PartyStatus.finished => l10n.partyStatusFinished,
        _ => l10n.adminPartiesAllStatuses,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final page = _page;
    final error = _error;
    if (page == null) {
      if (error == null) {
        return Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.loading),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(
          key: const Key('admin-parties-error'),
          message: l10n.adminPartiesLoadError,
          onRetry: _load,
        ),
      );
    }

    final total = page.total ?? page.items.length;
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              key: const Key('admin-parties-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  l10n.adminPartiesCount(total),
                  key: const Key('admin-parties-count'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('admin-parties-filter'),
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final status in AdminPartiesView.filters)
                      ChoiceChip(
                        key: Key('admin-parties-filter-${status ?? 'all'}'),
                        label: Text(_filterLabel(l10n, status)),
                        selected: _status == status,
                        onSelected: (_) => _filter(status),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (error != null) ...[
                  ErrorBanner(
                    key: const Key('admin-parties-error'),
                    message: _errorText(l10n, error),
                    onRetry: _load,
                  ),
                  const SizedBox(height: 12),
                ],
                if (page.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      l10n.adminPartiesEmpty,
                      key: const Key('admin-parties-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final party in page.items)
                  AdminPartyTile(
                    key: Key('admin-party-${party.id}'),
                    party: party,
                    busy: _busy == party.id,
                    onStop: _busy == null ? () => _stop(party) : null,
                    onDelete: _busy == null ? () => _delete(party) : null,
                  ),
                if (total > AdminPartiesView.pageSize)
                  AdminPager(
                    keyPrefix: 'admin-parties',
                    pageSize: AdminPartiesView.pageSize,
                    offset: _offset,
                    total: total,
                    onPage: _loading ? null : _goTo,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One party: its name and invite code, its status, owner, seats,
/// visibility and creation date, and its actions — no stop once finished.
class AdminPartyTile extends StatelessWidget {
  const AdminPartyTile({
    super.key,
    required this.party,
    required this.busy,
    this.onStop,
    this.onDelete,
  });

  final AdminParty party;

  /// An action on this party is running.
  final bool busy;
  final VoidCallback? onStop;
  final VoidCallback? onDelete;

  /// The seats of [party] as React writes them: `3 / 5`, `3 / ?` when its
  /// settings name no player count (Rust settings, or unreadable JSON).
  static String seats(AdminParty party) =>
      '${party.playerCount} / ${party.settings.playerCount ?? '?'}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.slate400,
    );
    final inviteCode = party.inviteCode;
    final visibility = party.visibility;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        party.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      AdminStatusBadge(
                        key: const Key('admin-party-status'),
                        status: party.status,
                      ),
                    ],
                  ),
                  if (inviteCode != null) Text(inviteCode, style: muted),
                  const SizedBox(height: 4),
                  Text(
                    l10n.adminPartyOwner(
                      party.ownerUsername ?? Formats.missing,
                    ),
                    style: muted,
                  ),
                  Text(
                    [
                      l10n.adminPartyPlayers(seats(party)),
                      if (visibility != null)
                        visibility == 'public'
                            ? l10n.visibilityPublic
                            : l10n.visibilityPrivate,
                    ].join(' · '),
                    key: const Key('admin-party-seats'),
                    style: muted,
                  ),
                  Text(
                    l10n.adminPartyCreated(
                      Formats.dateTime(party.createdAt, locale),
                    ),
                    style: muted,
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...[
              if (party.status != PartyStatus.finished)
                IconButton(
                  key: Key('admin-party-stop-${party.id}'),
                  tooltip: l10n.adminStopParty,
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: AppColors.amber400,
                  onPressed: onStop,
                ),
              IconButton(
                key: Key('admin-party-delete-${party.id}'),
                tooltip: l10n.adminDeleteParty,
                icon: const Icon(Icons.delete_outline),
                color: AppColors.error,
                onPressed: onDelete,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A party status in React's colours: yellow waiting, green playing, grey
/// finished.
class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = switch (status) {
      PartyStatus.playing => (l10n.partyStatusPlaying, StatsColors.success),
      PartyStatus.finished => (l10n.partyStatusFinished, AppColors.slate400),
      PartyStatus.waiting => (l10n.partyStatusWaiting, AppColors.amber400),
      _ => (status, AppColors.amber400),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
