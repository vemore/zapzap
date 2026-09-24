import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/admin_screen.dart';
import 'package:zapzap/screens/not_found_screen.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/widgets/admin_users.dart';

import 'auth_helpers.dart';
import 'fixtures.dart';
import 'history_helpers.dart' show phoneSize;
import 'sse_fakes.dart';

const _vincentId = 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e';
const _adminId = 'b40fa968-ebee-4af4-8117-342d47e3eff3';
const _simonId = 'e88614f8-13ac-45ca-a4b2-2e6a26b797fd';
const _json = {'content-type': 'application/json; charset=utf-8'};

/// `GET /admin/users` over [users], paged by the request's `limit` and
/// `offset` as the backend pages it; `POST .../admin` and `DELETE` change
/// [users], or answer [refusal] when set.
class _FakeAdminBackend {
  _FakeAdminBackend(this.users);

  /// The users of `test/fixtures/admin_users.json`, [extra] more after them
  /// (`user000`, `user001`...).
  factory _FakeAdminBackend.fixture({int extra = 0}) {
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
    return _FakeAdminBackend(users);
  }

  final List<JsonMap> users;
  final List<http.Request> requests = [];
  ({int status, JsonMap body})? refusal;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path == '/api/admin/users' && request.method == 'GET') {
      final limit = int.parse(request.url.queryParameters['limit'] ?? '50');
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      final page = users.skip(offset).take(limit).toList();
      return _answer({
        'success': true,
        'users': page,
        'pagination': {'total': users.length, 'limit': limit, 'offset': offset},
      });
    }
    final toggle = RegExp(r'^/api/admin/users/([^/]+)/admin$').firstMatch(path);
    final delete = RegExp(r'^/api/admin/users/([^/]+)$').firstMatch(path);
    final refused = refusal;
    if ((toggle != null || delete != null) && refused != null) {
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
    if (path == '/api/party') return _answer({'success': true, 'parties': []});
    if (path == '/api/players/connected') return _answer({'players': []});
    return _answer({'error': 'Route not found'}, 404);
  }

  static http.Response _answer(Object body, [int status = 200]) =>
      http.Response(jsonEncode(body), status, headers: _json);
}

/// A stored session for Vincent, admin or not.
MemoryTokenStorage _session({required bool isAdmin}) => MemoryTokenStorage({
  TokenStorage.tokenKey: jwtExpiringIn(
    const Duration(hours: 24),
    userId: _vincentId,
  ),
  TokenStorage.userKey: jsonEncode({
    'id': _vincentId,
    'username': 'Vincent',
    'isAdmin': isAdmin,
  }),
});

void main() {
  /// The app on [location], signed in as Vincent. The window is tall, so a
  /// page of 50 rows is built whole.
  Future<_FakeAdminBackend> pumpAdmin(
    WidgetTester tester, {
    _FakeAdminBackend? backend,
    String location = AppRoutes.admin,
    bool isAdmin = true,
    Size size = const Size(1000, 9000),
    double textScale = 1,
  }) async {
    final fake = backend ?? _FakeAdminBackend.fixture();
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
        tokenStorage: _session(isAdmin: isAdmin),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  String locationOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path;

  Finder rows() => find.byType(AdminUserTile);

  Finder row(String id) => find.byKey(Key('admin-user-$id'));

  group('the guard', () {
    testWidgets('a non-admin opening /admin lands on the parties', (
      tester,
    ) async {
      final backend = await pumpAdmin(tester, isAdmin: false);

      expect(locationOf(tester), AppRoutes.parties);
      expect(find.byType(AdminScreen), findsNothing);
      expect(
        backend.requests.where((r) => r.url.path.startsWith('/api/admin')),
        isEmpty,
      );
    });

    testWidgets('nor does /admin/users let a non-admin in', (tester) async {
      await pumpAdmin(tester, isAdmin: false, location: '/admin/users');

      expect(locationOf(tester), AppRoutes.parties);
    });

    testWidgets('an admin gets the three tabs, on Users', (tester) async {
      await pumpAdmin(tester);

      expect(find.byType(AdminScreen), findsOneWidget);
      expect(find.byKey(const Key('admin-tab-users')), findsOneWidget);
      expect(find.byKey(const Key('admin-tab-parties')), findsOneWidget);
      expect(find.byKey(const Key('admin-tab-statistics')), findsOneWidget);
      expect(rows(), findsNWidgets(8));
    });

    testWidgets('/admin/statistics opens that tab', (tester) async {
      await pumpAdmin(
        tester,
        location: AppRoutes.adminTab(AdminTab.statistics),
      );
      expect(
        find.byKey(const Key('admin-statistics-placeholder')),
        findsOneWidget,
      );
      expect(find.text('Bientôt disponible.'), findsOneWidget);
    });

    testWidgets('an unknown admin tab is not found', (tester) async {
      await pumpAdmin(tester, location: '/admin/nope');
      expect(find.byType(NotFoundScreen), findsOneWidget);
    });

    testWidgets('the other tabs are placeholders for now', (tester) async {
      await pumpAdmin(tester);

      await tester.tap(find.byKey(const Key('admin-tab-parties')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('admin-parties-placeholder')),
        findsOneWidget,
      );
      expect(rows(), findsNothing);

      // Back on Users, the list is still there: no second load.
      await tester.tap(find.byKey(const Key('admin-tab-users')));
      await tester.pumpAndSettle();
      expect(rows(), findsNWidgets(8));
    });
  });

  group('users', () {
    testWidgets('the rows come from GET /admin/users, 50 at a time', (
      tester,
    ) async {
      final backend = await pumpAdmin(tester);

      final get = backend.requests.firstWhere(
        (r) => r.url.path == '/api/admin/users',
      );
      expect(get.url.queryParameters, {'limit': '50', 'offset': '0'});
      expect(find.text('8 utilisateurs'), findsOneWidget);
      expect(find.text('Vincent'), findsOneWidget);
      expect(find.text('Jamais connecté'), findsNWidgets(6));
      // No pager for a single page.
      expect(find.byKey(const Key('admin-users-next')), findsNothing);
    });

    testWidgets('a page holds 50 rows, and Next and Previous page through', (
      tester,
    ) async {
      await pumpAdmin(tester, backend: _FakeAdminBackend.fixture(extra: 112));

      expect(rows(), findsNWidgets(50));
      expect(find.text('120 utilisateurs'), findsOneWidget);
      expect(find.text('1–50 sur 120'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const Key('admin-users-previous')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('admin-users-next')));
      await tester.pumpAndSettle();
      expect(rows(), findsNWidgets(50));
      expect(find.text('51–100 sur 120'), findsOneWidget);
      expect(row('extra-042'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin-users-next')));
      await tester.pumpAndSettle();
      expect(rows(), findsNWidgets(20));
      expect(find.text('101–120 sur 120'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('admin-users-next')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const Key('admin-users-previous')));
      await tester.pumpAndSettle();
      expect(find.text('51–100 sur 120'), findsOneWidget);
    });

    testWidgets('the search filters the page, whatever the case', (
      tester,
    ) async {
      await pumpAdmin(tester, backend: _FakeAdminBackend.fixture(extra: 112));

      await tester.enterText(
        find.byKey(const Key('admin-users-search')),
        'USER04',
      );
      await tester.pump();
      // user040..user041 are on the first page (8 + 42 = 50 rows).
      expect(rows(), findsNWidgets(2));
      expect(row('extra-040'), findsOneWidget);
      expect(row('extra-041'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('admin-users-search')),
        'nobody',
      );
      await tester.pump();
      expect(rows(), findsNothing);
      expect(find.text('Aucun utilisateur trouvé'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('admin-users-search')), '');
      await tester.pump();
      expect(rows(), findsNWidgets(50));
    });

    testWidgets('my own row and admin\'s have no actions', (tester) async {
      await pumpAdmin(tester);

      for (final id in [_vincentId, _adminId]) {
        expect(find.byKey(Key('admin-toggle-$id')), findsNothing);
        expect(find.byKey(Key('admin-delete-$id')), findsNothing);
      }
      expect(
        find.descendant(
          of: row(_vincentId),
          matching: find.byKey(const Key('admin-user-you')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row(_adminId),
          matching: find.byKey(const Key('admin-user-admin')),
        ),
        findsOneWidget,
      );
      // Every other row has both.
      expect(find.byKey(Key('admin-toggle-$_simonId')), findsOneWidget);
      expect(find.byKey(Key('admin-delete-$_simonId')), findsOneWidget);
    });

    testWidgets('granting admin asks first, then posts and reloads', (
      tester,
    ) async {
      final backend = await pumpAdmin(tester);

      await tester.tap(find.byKey(Key('admin-toggle-$_simonId')));
      await tester.pumpAndSettle();
      expect(find.text('Donner les droits admin à Simon ?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin-confirm-ok')));
      await tester.pumpAndSettle();

      final post = backend.requests.lastWhere((r) => r.method == 'POST');
      expect(post.url.path, '/api/admin/users/$_simonId/admin');
      expect(jsonDecode(post.body), {'isAdmin': true});
      expect(
        find.descendant(
          of: row(_simonId),
          matching: find.byKey(const Key('admin-user-admin')),
        ),
        findsOneWidget,
      );

      // And back: revoking says so.
      await tester.tap(find.byKey(Key('admin-toggle-$_simonId')));
      await tester.pumpAndSettle();
      expect(find.text('Retirer les droits admin de Simon ?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-confirm-ok')));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(backend.requests.lastWhere((r) => r.method == 'POST').body),
        {'isAdmin': false},
      );
    });

    testWidgets('cancelling sends nothing', (tester) async {
      final backend = await pumpAdmin(tester);

      await tester.tap(find.byKey(Key('admin-delete-$_simonId')));
      await tester.pumpAndSettle();
      expect(
        find.text('Supprimer Simon ? Cette action est définitive.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
      expect(row(_simonId), findsOneWidget);
    });

    testWidgets('deleting removes the row', (tester) async {
      final backend = await pumpAdmin(tester);

      await tester.tap(find.byKey(Key('admin-delete-$_simonId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-confirm-ok')));
      await tester.pumpAndSettle();

      final delete = backend.requests.lastWhere((r) => r.method == 'DELETE');
      expect(delete.url.path, '/api/admin/users/$_simonId');
      expect(row(_simonId), findsNothing);
      expect(find.text('7 utilisateurs'), findsOneWidget);
    });

    testWidgets('a refusal is a snack bar, and the list stays', (tester) async {
      final backend = await pumpAdmin(tester);
      backend.refusal = (
        status: 400,
        body: {
          'success': false,
          'error': 'Cannot delete the default admin account',
        },
      );

      await tester.tap(find.byKey(Key('admin-delete-$_simonId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin-confirm-ok')));
      await tester.pumpAndSettle();

      expect(find.text('Action refusée pour ce compte.'), findsOneWidget);
      expect(rows(), findsNWidgets(8));
    });

    testWidgets('a failed load says so, and Retry reads again', (tester) async {
      final error = errorFixture('error_admin_required');
      var fail = true;
      final fake = _FakeAdminBackend.fixture();
      await pumpAdmin(
        tester,
        backend: _FakeAdminBackendWith(fake, (request) {
          if (fail && request.url.path == '/api/admin/users') {
            return http.Response(error.body, error.status, headers: _json);
          }
          return null;
        }),
      );

      expect(find.byKey(const Key('admin-users-error')), findsOneWidget);
      expect(
        find.text('Impossible de charger les utilisateurs.'),
        findsOneWidget,
      );

      fail = false;
      await tester.tap(find.text('Réessayer'));
      await tester.pumpAndSettle();
      expect(rows(), findsNWidgets(8));
    });
  });

  group('phone width', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the users tab fits 360×740 at a $scale text scale', (
        tester,
      ) async {
        await pumpAdmin(
          tester,
          backend: _FakeAdminBackend.fixture(extra: 112),
          size: phoneSize,
          textScale: scale,
        );

        expect(find.byType(AdminScreen), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const Key('admin-users-next')),
          500,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('admin-users-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('admin-users-range')), findsOneWidget);
      });
    }
  });
}

/// [_FakeAdminBackend] with [answerFirst] answering first, when it answers.
class _FakeAdminBackendWith extends _FakeAdminBackend {
  _FakeAdminBackendWith(_FakeAdminBackend inner, this.answerFirst)
    : super(inner.users);

  final http.Response? Function(http.Request request) answerFirst;

  @override
  Future<http.Response> handle(http.Request request) async =>
      answerFirst(request) ?? await super.handle(request);
}
