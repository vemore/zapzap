import 'package:flutter/material.dart' hide Page;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/json.dart';
import '../models/stats.dart';
import '../providers/auth_provider.dart';
import '../repositories/stats_repository.dart';
import '../router.dart';
import '../widgets/async_section.dart';
import '../widgets/stats_bots.dart';
import '../widgets/stats_common.dart';
import '../widgets/stats_leaderboard.dart';
import '../widgets/stats_personal.dart';

/// The three statistics of the React client
/// (`frontend/src/components/Stats/Statistics.jsx`): the player's own record,
/// the leaderboard with the player's row marked, and the bots by difficulty.
///
/// Each read stands on its own, so a failing leaderboard leaves the rest.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// The leaderboard the React client asks for: everyone with one game,
  /// twenty rows (`Statistics.jsx:39`; the backend defaults to five games).
  static const leaderboardMinGames = 1;
  static const leaderboardLimit = 20;

  Future<UserStats>? _mine;
  Future<Page<LeaderboardEntry>>? _leaderboard;
  Future<BotStats>? _bots;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mine ??= _readMine();
    _leaderboard ??= _readLeaderboard();
    _bots ??= _readBots();
  }

  StatsRepository get _stats => context.read<StatsRepository>();

  Future<UserStats> _readMine() => startRead(_stats.mine());

  Future<Page<LeaderboardEntry>> _readLeaderboard() => startRead(
    _stats.leaderboard(minGames: leaderboardMinGames, limit: leaderboardLimit),
  );

  Future<BotStats> _readBots() => startRead(_stats.bots());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentUserId = context.watch<AuthProvider>().user?.id;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backToParties,
          onPressed: () => context.go(AppRoutes.parties),
        ),
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            key: const Key('stats-history'),
            icon: const Icon(Icons.history),
            tooltip: l10n.historyTitle,
            onPressed: () => context.go(AppRoutes.history),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            icon: Icons.track_changes,
            title: l10n.statsPersonalTitle,
            child: AsyncSection<UserStats>(
              future: _mine!,
              errorMessage: (_) => l10n.statsLoadError,
              onRetry: () => setState(() => _mine = _readMine()),
              builder: (context, stats) => StatsPersonal(stats: stats),
            ),
          ),
          SectionCard(
            icon: Icons.military_tech,
            title: l10n.leaderboardTitle,
            child: Column(
              children: [
                AsyncSection<Page<LeaderboardEntry>>(
                  future: _leaderboard!,
                  errorMessage: (_) => l10n.leaderboardLoadError,
                  onRetry: () =>
                      setState(() => _leaderboard = _readLeaderboard()),
                  isEmpty: (page) => page.items.isEmpty,
                  emptyMessage: l10n.leaderboardEmpty,
                  builder: (context, page) => StatsLeaderboard(
                    entries: page.items,
                    currentUserId: currentUserId,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.leaderboardMinGames(leaderboardMinGames),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          SectionCard(
            icon: Icons.smart_toy,
            iconColor: StatsColors.zapzap,
            title: l10n.botStatsTitle,
            child: AsyncSection<BotStats>(
              future: _bots!,
              errorMessage: (_) => l10n.botStatsLoadError,
              onRetry: () => setState(() => _bots = _readBots()),
              isEmpty: (stats) => stats.byDifficulty.isEmpty,
              emptyMessage: l10n.botStatsEmpty,
              builder: (context, stats) => StatsBots(stats: stats),
            ),
          ),
        ],
      ),
    );
  }
}
