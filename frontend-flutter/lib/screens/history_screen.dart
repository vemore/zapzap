import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../models/json.dart';
import '../repositories/history_repository.dart';
import '../router.dart';
import '../widgets/async_section.dart';
import '../widgets/history_game_tile.dart';

/// Which listing the history screen shows.
enum HistoryTab { mine, public }

/// The finished games, mine (`GET /history`) or everyone's public ones
/// (`GET /history/public`), each opening its details. The port of
/// `frontend/src/components/History/GameHistory.jsx`.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  HistoryTab _tab = HistoryTab.mine;
  Future<Page<GameHistoryEntry>>? _games;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The repository comes from the tree, so the first read waits for it.
    _games ??= _read();
  }

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
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backToParties,
          onPressed: () => context.go(AppRoutes.parties),
        ),
        title: Text(l10n.historyTitle),
        actions: [
          IconButton(
            key: const Key('history-stats'),
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.statsTitle,
            onPressed: () => context.go(AppRoutes.stats),
          ),
        ],
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
              isEmpty: (page) => page.items.isEmpty,
              emptyMessage: _tab == HistoryTab.mine
                  ? l10n.historyEmptyMine
                  : l10n.historyEmptyPublic,
              builder: (context, page) => ListView.builder(
                key: const Key('history-list'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: page.items.length,
                itemBuilder: (context, index) {
                  final game = page.items[index];
                  return HistoryGameTile(
                    key: Key('history-game-${game.partyId}'),
                    game: game,
                    onTap: () =>
                        context.go(AppRoutes.gameDetails(game.partyId)),
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
