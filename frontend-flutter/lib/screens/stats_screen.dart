import 'package:flutter/material.dart' hide Page;
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/json.dart';
import '../models/stats.dart';
import '../providers/auth_provider.dart';
import '../repositories/stats_repository.dart';
import '../router.dart';
import '../utils/navigation.dart';
import '../widgets/async_section.dart';
import '../widgets/content_column.dart';
import '../widgets/stats_bots.dart';
import '../widgets/stats_common.dart';
import '../widgets/stats_leaderboard.dart';
import '../widgets/stats_personal.dart';
import '../widgets/zapzap_app_bar.dart';

/// The three statistics of the React client
/// (`frontend/src/components/Stats/Statistics.jsx`): the player's own record,
/// the leaderboard with the player's row marked, and the bots by difficulty.
///
/// Each read stands on its own, so a failing leaderboard leaves the rest.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  /// From this content width on, the leaderboard stands in a column of its
  /// own beside the personal figures and the bots.
  static const twoColumnsFrom = 880.0;

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
      appBar: ZapZapAppBar(
        title: l10n.statsTitle,
        leading: BackButton(
          key: const Key('back'),
          onPressed: () => context.popOrGo(AppRoutes.parties),
        ),
      ),
      body: ContentColumn(
        builder: (context, padding) => ListView(
          padding: padding,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final personal = SectionCard(
                  icon: Icons.track_changes,
                  title: l10n.statsPersonalTitle,
                  child: AsyncSection<UserStats>(
                    future: _mine!,
                    errorMessage: (_) => l10n.statsLoadError,
                    onRetry: () => setState(() => _mine = _readMine()),
                    builder: (context, stats) => StatsPersonal(stats: stats),
                  ),
                );
                final leaderboard = SectionCard(
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
                );
                final bots = SectionCard(
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
                );
                if (box.maxWidth < StatsScreen.twoColumnsFrom) {
                  return Column(children: [personal, leaderboard, bots]);
                }
                // Twenty leaderboard rows are as tall as the other two
                // sections together: they get a column of their own.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: [personal, bots])),
                    const SizedBox(width: 16),
                    Expanded(child: leaderboard),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
