import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/token_storage.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'sse_fakes.dart';

const vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';
const _json = {'content-type': 'application/json; charset=utf-8'};

/// The `/api/admin` routes over lists it holds, as the backend answers them:
///
/// - `GET /admin/users` over [users], paged by `limit` and `offset`;
///   `POST .../admin` and `DELETE` change [users];
/// - `GET /admin/parties` over [parties], filtered by `status` and paged;
///   `POST .../stop` finishes a party, `DELETE` removes it;
/// - `GET /admin/statistics` answers [statistics].
///
/// A user or party action answers [refusal] instead when it is set.
class FakeAdminBackend {
  FakeAdminBackend(this.users, {List<JsonMap>? parties, JsonMap? statistics})
    : parties = parties ?? _fixtureParties(),
      statistics = statistics ?? fixtureStatistics();

  /// The users of `test/fixtures/admin_users.json`, [extra] more after them
  /// (`user000`, `user001`...).
  factory FakeAdminBackend.fixture({int extra = 0, JsonMap? statistics}) {
    final users = Json.list(
      fixture('admin_users'),
      'users',
      (json) => Map<String, dynamic>.of(json),
    );
    final template = users.first;
    for (var i = 0; i < extra; i++) {
      final n = i.toString().padLeft(3, '0');
      users.add({...template, 'id': 'extra-$n', 'username': 'user$n'});
    }
    return FakeAdminBackend(users, statistics: statistics);
  }

  /// The parties of `test/fixtures/admin_parties.json`.
  static List<JsonMap> _fixtureParties() => Json.list(
    fixture('admin_parties'),
    'parties',
    (json) => Map<String, dynamic>.of(json),
  );

  /// `test/fixtures/admin_statistics.json`, its one day of games moved to
  /// two days before today (UTC) so it stays in the chart's 30 days.
  static JsonMap fixtureStatistics() {
    final json = fixture('admin_statistics');
    final day = DateTime.now().toUtc().subtract(const Duration(days: 2));
    final period =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    ((json['stats'] as Map)['gamesOverTime'] as Map)['daily'] = [
      {'period': period, 'count': 1},
    ];
    return json;
  }

  final List<JsonMap> users;
  final List<JsonMap> parties;
  JsonMap statistics;
  final List<http.Request> requests = [];
  ({int status, JsonMap body})? refusal;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    final query = request.url.queryParameters;
    final limit = int.parse(query['limit'] ?? '50');
    final offset = int.parse(query['offset'] ?? '0');
    if (path == '/api/admin/users' && request.method == 'GET') {
      final page = users.skip(offset).take(limit).toList();
      return _answer({
        'success': true,
        'users': page,
        'pagination': {'total': users.length, 'limit': limit, 'offset': offset},
      });
    }
    if (path == '/api/admin/parties' && request.method == 'GET') {
      final status = query['status'];
      final matching = [
        for (final party in parties)
          if (status == null || party['status'] == status) party,
      ];
      return _answer({
        'success': true,
        'parties': matching.skip(offset).take(limit).toList(),
        'pagination': {
          'total': matching.length,
          'limit': limit,
          'offset': offset,
        },
      });
    }
    if (path == '/api/admin/statistics' && request.method == 'GET') {
      return _answer(statistics);
    }
    final toggle = RegExp(r'^/api/admin/users/([^/]+)/admin$').firstMatch(path);
    final delete = RegExp(r'^/api/admin/users/([^/]+)$').firstMatch(path);
    final stop = RegExp(r'^/api/admin/parties/([^/]+)/stop$').firstMatch(path);
    final deleteParty = RegExp(r'^/api/admin/parties/([^/]+)$')
        .firstMatch(path);
    final refused = refusal;
    if ((toggle ?? delete ?? stop ?? deleteParty) != null && refused != null) {
      return _answer(refused.body, refused.status);
    }
    if (toggle != null && request.method == 'POST') {
      final user = users.firstWhere((u) => u['id'] == toggle[1]);
      user['isAdmin'] = (jsonDecode(request.body) as Map)['isAdmin'];
      return _answer({
        'success': true,
        'userId': user['id'],
        'username': user['username'],
        'isAdmin': user['isAdmin'],
      });
    }
    if (delete != null && request.method == 'DELETE') {
      users.removeWhere((u) => u['id'] == delete[1]);
      return _answer({'success': true});
    }
    if (stop != null && request.method == 'POST') {
      parties.firstWhere((p) => p['id'] == stop[1])['status'] = 'finished';
      return _answer({'success': true, 'partyId': stop[1]});
    }
    if (deleteParty != null && request.method == 'DELETE') {
      parties.removeWhere((p) => p['id'] == deleteParty[1]);
      return _answer({'success': true});
    }
    if (path == '/api/party') return _answer({'success': true, 'parties': []});
    if (path == '/api/players/connected') return _answer({'players': []});
    return _answer({'error': 'Route not found'}, 404);
  }

  static http.Response _answer(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _json);
}

/// [FakeAdminBackend] with [answerFirst] answering first, when it answers.
class FakeAdminBackendWith extends FakeAdminBackend {
  FakeAdminBackendWith(FakeAdminBackend inner, this.answerFirst)
    : super(inner.users, parties: inner.parties, statistics: inner.statistics);

  final http.Response? Function(http.Request request) answerFirst;

  @override
  Future<http.Response> handle(http.Request request) async =>
      answerFirst(request) ?? await super.handle(request);
}

/// A stored session for Vincent, admin or not.
MemoryTokenStorage adminSession({required bool isAdmin}) => MemoryTokenStorage({
  TokenStorage.tokenKey: jwtExpiringIn(
    const Duration(hours: 24),
    userId: vincentId,
  ),
  TokenStorage.userKey: jsonEncode({
    'id': vincentId,
    'username': 'Vincent',
    'isAdmin': isAdmin,
  }),
});

/// The app on [location], signed in as Vincent. The window is tall by
/// default, so a page of 50 rows is built whole.
Future<FakeAdminBackend> pumpAdmin(
  WidgetTester tester, {
  FakeAdminBackend? backend,
  String location = AppRoutes.admin,
  bool isAdmin = true,
  Size size = const Size(1000, 9000),
  double textScale = 1,
}) async {
  final fake = backend ?? FakeAdminBackend.fixture();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (textScale != 1) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    ZapZapApp(
      apiConfig: testConfig,
      locale: const Locale('fr'),
      initialLocation: location,
      apiClient: fakeApi(fake.handle),
      tokenStorage: adminSession(isAdmin: isAdmin),
      sseTransport: FakeSseTransport(),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// Scrolls the list keyed [listKey] until [finder] is built and on show.
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  required String listKey,
}) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byKey(Key(listKey)),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}
