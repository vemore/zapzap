import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/history.dart';
import '../repositories/history_repository.dart';
import '../router.dart';
import '../services/api_exception.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import '../utils/navigation.dart';
import '../widgets/async_section.dart';
import '../widgets/history_rounds_table.dart';
import '../widgets/history_standings.dart';
import '../widgets/stats_common.dart';
import '../widgets/zapzap_app_bar.dart';

/// One finished game (`GET /history/:partyId`): its summary, the final
/// standings and the round-by-round table. The port of
/// `frontend/src/components/History/GameDetails.jsx`.
class GameDetailsScreen extends StatefulWidget {
  const GameDetailsScreen({super.key, required this.partyId});

  final String partyId;

  @override
  State<GameDetailsScreen> createState() => _GameDetailsScreenState();
}

class _GameDetailsScreenState extends State<GameDetailsScreen> {
  Future<GameDetails>? _details;

  /// The name shown in the app bar, known only once the game is read.
  String? _title;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _details ??= _read();
  }

  @override
  void didUpdateWidget(GameDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partyId != widget.partyId) _reload();
  }

  Future<GameDetails> _read() => startRead(_load());

  Future<GameDetails> _load() async {
    final details = await context.read<HistoryRepository>().details(
      widget.partyId,
    );
    // Rebuilding from a build is forbidden, so the title waits a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _title = details.game.partyName);
    });
    return details;
  }

  void _reload() => setState(() {
    _title = null;
    _details = _read();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ZapZapAppBar(
        title: _title ?? l10n.gameDetailsTitle,
        leading: BackButton(
          key: const Key('back'),
          onPressed: () => context.popOrGo(AppRoutes.history),
        ),
      ),
      body: AsyncSection<GameDetails>(
        future: _details!,
        errorMessage: (error) => _errorMessage(error, l10n),
        onRetry: _reload,
        builder: (context, details) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Summary(game: details.game),
            SectionCard(
              icon: Icons.leaderboard,
              title: l10n.standingsTitle,
              child: HistoryStandings(players: details.players),
            ),
            SectionCard(
              icon: Icons.table_chart,
              title: l10n.roundsTitle,
              child: HistoryRoundsTable(
                players: details.players,
                rounds: details.rounds,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The summary card: the winner, then the four figures of the game.
class _Summary extends StatelessWidget {
  const _Summary({required this.game});

  final GameSummary game;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final winner = game.winnerUsername;
    final score = game.winnerFinalScore;
    return SectionCard(
      icon: Icons.emoji_events,
      title: l10n.gameSummaryTitle,
      trailing: game.wasGoldenScore
          ? const GoldenScoreChip(finish: true)
          : null,
      child: Column(
        children: [
          if (winner != null)
            Container(
              key: const Key('game-winner'),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.amber400.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.amber400, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.workspace_premium,
                        color: AppColors.amber400,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          l10n.gameWinnerLabel,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.amber400,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    winner,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.gameFinalScore(score),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.amber400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 16),
          StatTileGrid(
            tiles: [
              StatTile(
                icon: Icons.group,
                label: l10n.gameInfoPlayers,
                value: '${game.playerCount}',
              ),
              StatTile(
                icon: Icons.flag,
                label: l10n.gameInfoRounds,
                value: '${game.totalRounds}',
              ),
              StatTile(
                icon: Icons.event,
                label: l10n.gameInfoFinished,
                value: Formats.dateTime(game.finishedAt, locale),
              ),
              StatTile(
                icon: Icons.visibility,
                label: l10n.gameInfoVisibility,
                value: switch (game.visibility) {
                  'public' => l10n.visibilityPublic,
                  'private' => l10n.visibilityPrivate,
                  final other => other ?? Formats.missing,
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A game that is neither this user's nor public answers 404 with `{error}`
/// alone, so the code comes from the status; anything else is a plain
/// failure.
String _errorMessage(Object error, AppLocalizations l10n) =>
    error is ApiException && error.code == ApiErrorCode.notFound
    ? l10n.gameDetailsNotFound
    : l10n.gameDetailsLoadError;
