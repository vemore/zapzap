import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/admin.dart';
import '../repositories/admin_repository.dart';
import '../utils/app_theme.dart';
import '../utils/date_format.dart';
import 'admin_common.dart';
import 'error_banner.dart';
import 'stats_common.dart';

/// The statistics tab of the admin screen, the port of
/// `frontend/src/components/Admin/Statistics/AdminStats.jsx`: four figures,
/// the parties by status, the games finished on each of the last
/// [DailyGamesChart.span] days, and the most active players — all from
/// `GET /admin/statistics`.
class AdminStatisticsView extends StatefulWidget {
  const AdminStatisticsView({super.key, this.now = DateTime.now});

  /// The clock the chart's last day is read from.
  final DateTime Function() now;

  @override
  State<AdminStatisticsView> createState() => _AdminStatisticsViewState();
}

class _AdminStatisticsViewState extends State<AdminStatisticsView> {
  AdminStatistics? _stats;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stats = await context.read<AdminRepository>().statistics();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = _stats;
    final error = _error;
    if (stats == null) {
      if (error == null) {
        return Center(
          child: CircularProgressIndicator(semanticsLabel: l10n.loading),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorBanner(
          key: const Key('admin-stats-error'),
          message: adminErrorText(l10n, error),
          onRetry: _load,
        ),
      );
    }

    final days = DailyGamesChart.lastDays(stats.daily, widget.now());
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              key: const Key('admin-stats-list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (error != null) ...[
                  ErrorBanner(
                    key: const Key('admin-stats-error'),
                    message: adminErrorText(l10n, error),
                    onRetry: _load,
                  ),
                  const SizedBox(height: 12),
                ],
                StatTileGrid(
                  key: const Key('admin-stats-cards'),
                  tiles: [
                    StatTile(
                      key: const Key('admin-stats-users'),
                      icon: Icons.people,
                      label: l10n.adminStatsUsers,
                      value: '${stats.totalUsers}',
                      color: AppColors.amber400,
                    ),
                    StatTile(
                      key: const Key('admin-stats-parties'),
                      icon: Icons.sports_esports,
                      label: l10n.adminStatsParties,
                      value: '${stats.totalParties}',
                      color: StatsColors.info,
                    ),
                    StatTile(
                      key: const Key('admin-stats-rounds'),
                      icon: Icons.adjust,
                      label: l10n.adminStatsRounds,
                      value: '${stats.totalRounds}',
                      color: StatsColors.success,
                    ),
                    StatTile(
                      key: const Key('admin-stats-completion'),
                      icon: Icons.trending_up,
                      label: l10n.adminStatsCompletion,
                      // Node rounds to one decimal, Rust does not.
                      value: '${Formats.number(stats.completionRate)}%',
                      color: StatsColors.zapzap,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionCard(
                  key: const Key('admin-stats-breakdown'),
                  icon: Icons.donut_small,
                  title: l10n.adminStatsBreakdown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (key, label, value, color) in [
                        (
                          'waiting',
                          l10n.partyStatusWaiting,
                          stats.waitingParties,
                          AppColors.amber400,
                        ),
                        (
                          'playing',
                          l10n.partyStatusPlaying,
                          stats.playingParties,
                          StatsColors.success,
                        ),
                        (
                          'finished',
                          l10n.partyStatusFinished,
                          stats.finishedParties,
                          AppColors.slate400,
                        ),
                      ])
                        Expanded(
                          child: MiniStat(
                            key: Key('admin-stats-$key'),
                            label: label,
                            value: '$value',
                            color: color,
                          ),
                        ),
                    ],
                  ),
                ),
                SectionCard(
                  key: const Key('admin-stats-chart-card'),
                  icon: Icons.bar_chart,
                  title: l10n.adminStatsChartTitle(DailyGamesChart.span),
                  child: days.every((d) => d.count == 0)
                      ? Text(
                          l10n.adminStatsChartEmpty,
                          key: const Key('admin-stats-chart-empty'),
                          style: const TextStyle(color: AppColors.slate400),
                        )
                      : DailyGamesChart(
                          key: const Key('admin-stats-chart'),
                          days: days,
                        ),
                ),
                SectionCard(
                  key: const Key('admin-stats-active'),
                  icon: Icons.emoji_events,
                  iconColor: AppColors.amber400,
                  title: l10n.adminStatsMostActive,
                  child: stats.mostActiveUsers.isEmpty
                      ? Text(
                          l10n.adminStatsNoActive,
                          key: const Key('admin-stats-no-active'),
                          style: const TextStyle(color: AppColors.slate400),
                        )
                      : Column(
                          children: [
                            for (final (i, user)
                                in stats.mostActiveUsers.indexed)
                              _ActiveUserRow(
                                key: Key('admin-stats-user-${user.userId}'),
                                rank: i + 1,
                                user: user,
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of the most active players: rank, name, games, wins and win rate.
class _ActiveUserRow extends StatelessWidget {
  const _ActiveUserRow({super.key, required this.rank, required this.user});

  final int rank;
  final ActiveUser user;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rate = user.gamesPlayed > 0
        ? '${(user.wins * 100 / user.gamesPlayed).round()}%'
        : Formats.missing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          RankBadge(rank: rank),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${l10n.gameCount(user.gamesPlayed)} · '
                  '${l10n.adminStatsWins(user.wins)} · $rate',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The games finished on each of the last [days] days as bars, the port of
/// React's canvas chart: a [CustomPaint] of [DailyGamesPainter].
class DailyGamesChart extends StatelessWidget {
  const DailyGamesChart({super.key, required this.days, this.height = 200});

  /// The days the chart spans, today included.
  static const span = 30;

  /// The last [days] UTC days up to [now], oldest first, each with the
  /// count [daily] gives it (`2026-09-22`) or 0. The backends group the
  /// games by UTC day (`strftime('%Y-%m-%d', datetime(finished_at,
  /// 'unixepoch'))`) and send only the days that have some.
  static List<GamePeriod> lastDays(
    List<GamePeriod> daily,
    DateTime now, {
    int count = span,
  }) {
    final counts = {for (final d in daily) d.period: d.count};
    final utc = now.toUtc();
    final today = DateTime.utc(utc.year, utc.month, utc.day);
    return [
      for (var i = count - 1; i >= 0; i--)
        () {
          final day = today.subtract(Duration(days: i));
          final period =
              '${day.year.toString().padLeft(4, '0')}-'
              '${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}';
          return GamePeriod(period: period, count: counts[period] ?? 0);
        }(),
    ];
  }

  final List<GamePeriod> days;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = days.fold(0, (sum, d) => sum + d.count);
    return Semantics(
      container: true,
      label: l10n.adminStatsChartSemantics(total, days.length),
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: DailyGamesPainter(
            days: days,
            textScaler: MediaQuery.textScalerOf(context),
          ),
        ),
      ),
    );
  }
}

/// Paints [days] as bars over a four-step grid: a bar per day — a thin stub
/// for a day without games, so each of them shows — its count above it when
/// the bars are wide enough, and a `dd/MM` label under every fifth day and
/// the last one.
class DailyGamesPainter extends CustomPainter {
  DailyGamesPainter({
    required this.days,
    this.textScaler = TextScaler.noScaling,
  });

  final List<GamePeriod> days;
  final TextScaler textScaler;

  static const _left = 32.0;
  static const _right = 4.0;
  static const _top = 16.0;
  static const _stub = 2.0;
  static const _gridSteps = 4;

  /// The largest count, at least 1 so an empty chart has a scale.
  int get maxCount => days.fold(1, (m, d) => math.max(m, d.count));

  /// The rectangle of each bar in a canvas of [size], in [days] order.
  List<Rect> barRects(Size size) {
    if (days.isEmpty) return const [];
    final bottom = size.height - _labelHeight;
    final chartHeight = math.max(0.0, bottom - _top);
    final slot = math.max(0.0, size.width - _left - _right) / days.length;
    final width = math.max(1.0, slot * 0.7);
    return [
      for (final (i, day) in days.indexed)
        () {
          final height = day.count == 0
              ? _stub
              : math.max(_stub, day.count / maxCount * chartHeight);
          final x = _left + i * slot + (slot - width) / 2;
          return Rect.fromLTWH(x, bottom - height, width, height);
        }(),
    ];
  }

  double get _labelHeight => textScaler.scale(10) + 8;

  TextPainter _text(
    String text,
    double fontSize,
    Color color, {
    bool bold = false,
  }) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - _labelHeight;
    final chartHeight = math.max(0.0, bottom - _top);
    final max = maxCount;

    // The grid and its scale, 0 to [max] in four steps.
    final grid = Paint()
      ..color = AppColors.slate700
      ..strokeWidth = 1;
    for (var i = 0; i <= _gridSteps; i++) {
      final y = bottom - chartHeight * i / _gridSteps;
      canvas.drawLine(Offset(_left, y), Offset(size.width - _right, y), grid);
      final label = _text(
        '${(max * i / _gridSteps).round()}',
        10,
        AppColors.slate400,
      );
      label.paint(
        canvas,
        Offset(_left - 6 - label.width, y - label.height / 2),
      );
    }

    final rects = barRects(size);
    final showValues = rects.isNotEmpty && rects.first.width >= 12;
    final bar = Paint()..color = AppColors.amber500;
    final empty = Paint()..color = AppColors.slate600;
    for (final (i, rect) in rects.indexed) {
      final day = days[i];
      canvas.drawRect(rect, day.count == 0 ? empty : bar);
      if (showValues && day.count > 0) {
        final value = _text('${day.count}', 10, AppColors.amber400, bold: true);
        value.paint(
          canvas,
          Offset(rect.center.dx - value.width / 2, rect.top - value.height - 2),
        );
      }
      if (i % 5 == 0 || i == days.length - 1) {
        // `2026-09-22` → `22/09`.
        final parts = day.period.split('-');
        final text = parts.length == 3 ? '${parts[2]}/${parts[1]}' : day.period;
        final label = _text(text, 10, AppColors.slate400);
        final x = (rect.center.dx - label.width / 2)
            .clamp(0.0, math.max(0.0, size.width - label.width))
            .toDouble();
        label.paint(canvas, Offset(x, bottom + 4));
      }
    }
  }

  @override
  bool shouldRepaint(DailyGamesPainter oldDelegate) =>
      oldDelegate.days != days || oldDelegate.textScaler != textScaler;
}
