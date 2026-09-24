import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/models/admin.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/admin_screen.dart';
import 'package:zapzap/widgets/admin_stats.dart';

import 'admin_helpers.dart';
import 'fixtures.dart';
import 'history_helpers.dart' show phoneSize;

/// A canvas that counts the bars (`drawRect`) and the grid lines, and
/// ignores the rest (the text).
class _RecordingCanvas implements Canvas {
  final rects = <Rect>[];
  var lines = 0;

  @override
  void drawRect(Rect rect, Paint paint) => rects.add(rect);

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  Future<FakeAdminBackend> pumpStats(
    WidgetTester tester, {
    FakeAdminBackend? backend,
    Size size = const Size(1000, 2000),
    double textScale = 1,
  }) => pumpAdmin(
    tester,
    backend: backend,
    location: AppRoutes.adminTab(AdminTab.statistics),
    size: size,
    textScale: textScale,
  );

  Finder inKey(String key, Finder matching) =>
      find.descendant(of: find.byKey(Key(key)), matching: matching);

  group('the 30 days', () {
    test('oldest first, today last, the missing days at 0', () {
      final days = DailyGamesChart.lastDays(const [
        GamePeriod(period: '2026-09-22', count: 3),
        GamePeriod(period: '2026-08-26', count: 2),
        // Out of the window: dropped.
        GamePeriod(period: '2026-08-25', count: 9),
      ], DateTime.utc(2026, 9, 24, 23, 59));

      expect(days, hasLength(30));
      expect(days.first.period, '2026-08-26');
      expect(days.first.count, 2);
      expect(days.last.period, '2026-09-24');
      expect(days[days.length - 3].count, 3);
      expect(days.fold(0, (sum, d) => sum + d.count), 5);
    });

    test('the days are UTC days, across a month end', () {
      final days = DailyGamesChart.lastDays(
        const [],
        DateTime.utc(2026, 3, 1, 0, 30),
      );
      expect(days.last.period, '2026-03-01');
      expect(days[days.length - 2].period, '2026-02-28');
    });

    test('the painter paints 30 bars, the tallest the full height', () {
      final days = [
        for (var i = 0; i < 30; i++)
          GamePeriod(period: '2026-09-${i + 1}', count: i % 7),
      ];
      final painter = DailyGamesPainter(days: days);
      final canvas = _RecordingCanvas();
      const size = Size(328, 200);
      painter.paint(canvas, size);

      expect(canvas.rects, hasLength(30));
      expect(canvas.rects, painter.barRects(size));
      // The grid: five lines, 0 to the maximum.
      expect(canvas.lines, 5);
      // Left to right, inside the canvas.
      for (var i = 1; i < 30; i++) {
        expect(canvas.rects[i].left, greaterThan(canvas.rects[i - 1].left));
      }
      expect(canvas.rects.last.right, lessThanOrEqualTo(size.width));
      // A day without games is a stub; the busiest day the tallest bar.
      final tallest = canvas.rects[6].height;
      expect(canvas.rects[0].height, 2);
      for (final rect in canvas.rects) {
        expect(rect.height, lessThanOrEqualTo(tallest));
        expect(rect.bottom, canvas.rects.first.bottom);
      }
    });

    test('an empty chart paints 30 stubs', () {
      final days = DailyGamesChart.lastDays(
        const [],
        DateTime.utc(2026, 9, 24),
      );
      final canvas = _RecordingCanvas();
      DailyGamesPainter(days: days).paint(canvas, const Size(300, 200));
      expect(canvas.rects, hasLength(30));
      expect(canvas.rects.every((r) => r.height == 2), isTrue);
    });
  });

  testWidgets('the cards, the breakdown, the chart and the most active', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final backend = await pumpStats(tester);

    expect(
      backend.requests.where((r) => r.url.path == '/api/admin/statistics'),
      hasLength(1),
    );
    expect(inKey('admin-stats-users', find.text('8')), findsOneWidget);
    expect(
      inKey('admin-stats-users', find.text('Utilisateurs')),
      findsOneWidget,
    );
    expect(inKey('admin-stats-parties', find.text('2')), findsOneWidget);
    expect(inKey('admin-stats-rounds', find.text('5')), findsOneWidget);
    expect(inKey('admin-stats-completion', find.text('50%')), findsOneWidget);

    expect(inKey('admin-stats-waiting', find.text('1')), findsOneWidget);
    expect(inKey('admin-stats-playing', find.text('0')), findsOneWidget);
    expect(inKey('admin-stats-finished', find.text('1')), findsOneWidget);

    expect(find.byKey(const Key('admin-stats-chart')), findsOneWidget);
    expect(find.text('Parties terminées (30 derniers jours)'), findsOneWidget);
    expect(
      find.bySemanticsLabel('1 partie terminée sur les 30 derniers jours'),
      findsOneWidget,
    );

    final vincent = find.byKey(Key('admin-stats-user-$vincentId'));
    expect(
      find.descendant(of: vincent, matching: find.text('Vincent')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: vincent,
        matching: find.text('1 partie · 0 victoire · 0%'),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('a completion rate keeps one decimal at most', (tester) async {
    final stats = FakeAdminBackend.fixtureStatistics();
    // Rust sends the raw ratio.
    ((stats['stats'] as Map)['parties'] as Map)['completionRate'] = 33.33333333;
    await pumpStats(
      tester,
      backend: FakeAdminBackend.fixture(statistics: stats),
    );
    expect(inKey('admin-stats-completion', find.text('33.3%')), findsOneWidget);
  });

  testWidgets('no daily games (Rust) and no active player say so', (
    tester,
  ) async {
    final stats = fixture('admin_statistics');
    final body = stats['stats'] as Map;
    (body['gamesOverTime'] as Map)['daily'] = [];
    body['mostActiveUsers'] = [];
    await pumpStats(
      tester,
      backend: FakeAdminBackend.fixture(statistics: stats),
    );

    expect(find.byKey(const Key('admin-stats-chart')), findsNothing);
    expect(find.text('Pas assez de données'), findsOneWidget);
    expect(
      find.text('Aucun joueur avec des parties terminées'),
      findsOneWidget,
    );
  });

  testWidgets('a failed load says so, and Retry reads again', (tester) async {
    final error = errorFixture('error_admin_required');
    var fail = true;
    await pumpStats(
      tester,
      backend: FakeAdminBackendWith(FakeAdminBackend.fixture(), (request) {
        if (fail && request.url.path == '/api/admin/statistics') {
          return http.Response(
            error.body,
            error.status,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      }),
    );

    expect(find.byKey(const Key('admin-stats-error')), findsOneWidget);
    expect(find.text('Réservé aux administrateurs.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-stats-chart')), findsOneWidget);
  });

  group('phone width', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the statistics tab fits 360×740 at a $scale text scale', (
        tester,
      ) async {
        await pumpStats(tester, size: phoneSize, textScale: scale);

        await scrollTo(
          tester,
          find.byKey(Key('admin-stats-user-$vincentId')),
          listKey: 'admin-stats-list',
        );
        expect(find.byKey(const Key('admin-stats-active')), findsOneWidget);
      });
    }
  });
}
