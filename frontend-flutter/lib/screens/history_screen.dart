import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../models/json.dart';
import '../models/stats.dart';
import '../providers/auth_provider.dart';
import '../repositories/history_repository.dart';
import '../repositories/stats_repository.dart';
import '../router.dart';
import '../utils/navigation.dart';
import '../widgets/async_section.dart';
import '../widgets/history_game_tile.dart';
import '../widgets/history_summary.dart';
import '../widgets/zapzap_app_bar.dart';

/// Which listing the history screen shows.
enum HistoryTab { mine, public }

/// The finished games, mine (`GET /history`) or everyone's public ones
/// (`GET /history/public`), each opening its details. The port of
/// `frontend/src/components/History/GameHistory.jsx`.
///
/// My games opens on a summary — games and wins from `GET /stats/me`, the
/// whole record rather than the page of entries, and my best place — that
/// leads to the statistics; a list shorter than [inviteBelow] ends on the
/// way to a game against bots.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  /// A My games list with fewer entries ends on [HistoryInvite].
  static const inviteBelow = 3;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryTab _tab = HistoryTab.mine;
  Future<Page<GameHistoryEntry>>? _games;
  Future<UserStats>? _stats;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The repository comes from the tree, so the first read waits for it.
    _games ??= _read();
    _stats ??= _readStats();
  }

  Future<UserStats> _readStats() =>
      startRead(context.read<StatsRepository>().mine());

  Future<Page<GameHistoryEntry>> _read() {
    final history = context.read<HistoryRepository>();
    return startRead(switch (_tab) {
      HistoryTab.mine => history.mine(),
      HistoryTab.public => history.public(),
    });
  }

  void _reload([HistoryTab? tab]) => setState(() {
    if (tab != null) _tab = tab;
    _games = _read();
    if (_tab == HistoryTab.mine) _stats = _readStats();
  });

  /// My games: the summary, the entries, and the invitation when the list is
  /// short — alone when it is empty.
  Widget _mine(BuildContext context, List<GameHistoryEntry> games) {
    final userId = context.watch<AuthProvider>().user?.id;
    final invite = HistoryInvite(
      // `push`: Back from the form returns to the history.
      onPlay: () => context.push(AppRoutes.createParty),
    );
    return ListView(
      key: const Key('history-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (games.isNotEmpty) ...[
          FutureBuilder<UserStats>(
            future: _stats,
            builder: (context, snapshot) {
              final stats = snapshot.data;
              return HistorySummary(
                gamesPlayed: stats?.gamesPlayed,
                wins: stats?.wins,
                bestPlace: _bestPlace(games, userId, stats),
                // `push`, never `go`: Back returns to the history.
                onOpenStats: () => context.push(AppRoutes.stats),
              );
            },
          ),
          for (final game in games)
            HistoryGameTile(
              key: Key('history-game-${game.partyId}'),
              game: game,
              currentUserId: userId,
              // `push`: the system Back returns to this list.
              onTap: () => context.push(AppRoutes.gameDetails(game.partyId)),
            ),
        ],
        if (games.length < HistoryScreen.inviteBelow) invite,
      ],
    );
  }

  /// The best place among [games] — first as soon as the record holds a
  /// win, even one past this page of entries.
  static int? _bestPlace(
    List<GameHistoryEntry> games,
    String? userId,
    UserStats? stats,
  ) {
    if ((stats?.wins ?? 0) > 0) return 1;
    int? best;
    for (final game in games) {
      final place = myPlacement(game, userId);
      if (place != null && (best == null || place < best)) best = place;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(
        title: l10n.historyTitle,
        leading: BackButton(
          key: const Key('back'),
          onPressed: () => context.popOrGo(AppRoutes.parties),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SegmentedButton<HistoryTab>(
              key: const Key('history-tabs'),
              segments: [
                ButtonSegment(
                  value: HistoryTab.mine,
                  icon: const Icon(Icons.person),
                  label: Text(l10n.historyTabMine),
                ),
                ButtonSegment(
                  value: HistoryTab.public,
                  icon: const Icon(Icons.public),
                  label: Text(l10n.historyTabPublic),
                ),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => _reload(selection.first),
            ),
          ),
          Expanded(
            child: AsyncSection<Page<GameHistoryEntry>>(
              future: _games!,
              errorMessage: (_) => l10n.historyLoadError,
              onRetry: _reload,
              // My games has its own empty state ([HistoryInvite]).
              isEmpty: (page) =>
                  _tab == HistoryTab.public && page.items.isEmpty,
              emptyMessage: l10n.historyEmptyPublic,
              builder: (context, page) => _tab == HistoryTab.mine
                  ? _mine(context, page.items)
                  : ListView.builder(
                      key: const Key('history-list'),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: page.items.length,
                      itemBuilder: (context, index) {
                        final game = page.items[index];
                        return HistoryGameTile(
                          key: Key('history-game-${game.partyId}'),
                          game: game,
                          // `push`: the system Back returns to this list.
                          onTap: () =>
                              context.push(AppRoutes.gameDetails(game.partyId)),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
