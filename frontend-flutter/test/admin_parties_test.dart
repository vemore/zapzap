import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:zapzap/models/admin.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/admin_screen.dart';
import 'package:zapzap/widgets/admin_parties.dart';

import 'admin_helpers.dart';
import 'history_helpers.dart' show phoneSize;

const _finishedId = 'da33c689-6f43-49d4-ba89-953f105e7960';
const _waitingId = 'f9d11bf6-2a4c-4e45-a8d3-4ef3863f02e9';

void main() {
  Future<FakeAdminBackend> pumpParties(
    WidgetTester tester, {
    FakeAdminBackend? backend,
    Size size = const Size(1000, 2000),
    double textScale = 1,
  }) => pumpAdmin(
    tester,
    backend: backend,
    location: AppRoutes.adminTab(AdminTab.parties),
    size: size,
    textScale: textScale,
  );

  Finder rows() => find.byType(AdminPartyTile);

  Finder row(String id) => find.byKey(Key('admin-party-$id'));

  Finder inRow(String id, Finder matching) =>
      find.descendant(of: row(id), matching: matching);

  List<http.Request> actions(FakeAdminBackend backend) => [
    for (final r in backend.requests)
      if (r.method != 'GET') r,
  ];

  testWidgets('the rows come from GET /admin/parties, 50 at a time', (
    tester,
  ) async {
    final backend = await pumpParties(tester);

    final get = backend.requests.firstWhere(
      (r) => r.url.path == '/api/admin/parties',
    );
    expect(get.url.queryParameters, {'limit': '50', 'offset': '0'});
    expect(find.text('2 parties'), findsOneWidget);
    expect(rows(), findsNWidgets(2));
    expect(inRow(_finishedId, find.text('Fixture party')), findsOneWidget);
    expect(inRow(_finishedId, find.text('BGJARGH7')), findsOneWidget);
    expect(inRow(_finishedId, find.text('Terminée')), findsOneWidget);
    expect(inRow(_waitingId, find.text('En attente')), findsOneWidget);
    expect(inRow(_waitingId, find.text('Créée par Vincent')), findsOneWidget);
  });

  testWidgets('the seats read the settings JSON string', (tester) async {
    await pumpParties(tester);

    // `settings` arrives as `"{\"playerCount\":5,...}"`: 4 of 5 seats.
    expect(
      inRow(_waitingId, find.text('Joueurs : 4 / 5 · Publique')),
      findsOneWidget,
    );
    expect(
      inRow(_finishedId, find.text('Joueurs : 3 / 3 · Publique')),
      findsOneWidget,
    );
  });

  test('seats without a player count in the settings', () {
    AdminParty party(Object? settings) => AdminParty.fromJson({
      'id': 'p',
      'name': 'P',
      'status': 'waiting',
      'playerCount': 2,
      'settings': settings,
    });
    expect(AdminPartyTile.seats(party('not json')), '2 / ?');
    expect(AdminPartyTile.seats(party({'handSize': 7})), '2 / ?');
    expect(AdminPartyTile.seats(party('{"playerCount":4}')), '2 / 4');
  });

  testWidgets('the status filter asks the backend and narrows the list', (
    tester,
  ) async {
    final backend = await pumpParties(tester);

    await tester.tap(find.byKey(const Key('admin-parties-filter-finished')));
    await tester.pumpAndSettle();
    expect(backend.requests.last.url.queryParameters, {
      'status': 'finished',
      'limit': '50',
      'offset': '0',
    });
    expect(rows(), findsOneWidget);
    expect(row(_finishedId), findsOneWidget);
    expect(find.text('1 partie'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-parties-filter-playing')));
    await tester.pumpAndSettle();
    expect(rows(), findsNothing);
    expect(find.text('Aucune partie trouvée'), findsOneWidget);

    await tester.tap(find.byKey(const Key('admin-parties-filter-all')));
    await tester.pumpAndSettle();
    expect(
      backend.requests.last.url.queryParameters.containsKey('status'),
      isFalse,
    );
    expect(rows(), findsNWidgets(2));
  });

  testWidgets('a finished party has no stop, every party a delete', (
    tester,
  ) async {
    await pumpParties(tester);

    expect(
      find.byKey(const Key('admin-party-stop-$_finishedId')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('admin-party-stop-$_waitingId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin-party-delete-$_finishedId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('admin-party-delete-$_waitingId')),
      findsOneWidget,
    );
  });

  testWidgets('cancelling a stop or a delete sends nothing', (tester) async {
    final backend = await pumpParties(tester);

    await tester.tap(find.byKey(const Key('admin-party-stop-$_waitingId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-party-stop-confirm')), findsOneWidget);
    expect(
      find.text(
        'Arrêter la partie « Demo Game » ? Elle sera marquée comme terminée.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin-party-delete-$_waitingId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('admin-party-delete-confirm')), findsOneWidget);
    // Dismissed by a tap outside: a cancel too.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(actions(backend), isEmpty);
    expect(inRow(_waitingId, find.text('En attente')), findsOneWidget);
  });

  testWidgets('stopping posts, and the party reads finished', (tester) async {
    final backend = await pumpParties(tester);

    await tester.tap(find.byKey(const Key('admin-party-stop-$_waitingId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pumpAndSettle();

    final post = actions(backend).single;
    expect(post.method, 'POST');
    expect(post.url.path, '/api/admin/parties/$_waitingId/stop');
    expect(inRow(_waitingId, find.text('Terminée')), findsOneWidget);
    expect(find.byKey(const Key('admin-party-stop-$_waitingId')), findsNothing);
  });

  testWidgets('deleting removes the row', (tester) async {
    final backend = await pumpParties(tester);

    await tester.tap(find.byKey(const Key('admin-party-delete-$_finishedId')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Supprimer la partie « Fixture party » et toutes ses données ? '
        'Cette action est définitive.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pumpAndSettle();

    final delete = actions(backend).single;
    expect(delete.method, 'DELETE');
    expect(delete.url.path, '/api/admin/parties/$_finishedId');
    expect(row(_finishedId), findsNothing);
    expect(find.text('1 partie'), findsOneWidget);
  });

  testWidgets('a refusal is a snack bar, and the list stays', (tester) async {
    final backend = await pumpParties(tester);
    backend.refusal = (
      status: 400,
      body: {'success': false, 'error': 'Party is already finished'},
    );

    await tester.tap(find.byKey(const Key('admin-party-stop-$_waitingId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-confirm-ok')));
    await tester.pumpAndSettle();

    expect(find.text('Action refusée pour cette partie.'), findsOneWidget);
    expect(rows(), findsNWidgets(2));
  });

  testWidgets('a failed load says so, and Retry reads again', (tester) async {
    var fail = true;
    await pumpParties(
      tester,
      backend: FakeAdminBackendWith(FakeAdminBackend.fixture(), (request) {
        if (fail && request.url.path == '/api/admin/parties') {
          return http.Response('{"error":"boom"}', 500);
        }
        return null;
      }),
    );

    expect(find.text('Impossible de charger les parties.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pumpAndSettle();
    expect(rows(), findsNWidgets(2));
  });

  group('phone width', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('the parties tab fits 360×740 at a $scale text scale', (
        tester,
      ) async {
        final backend = FakeAdminBackend.fixture();
        // A long name, to wrap next to the badge and the two actions.
        backend.parties.first['name'] =
            'Une partie au nom vraiment très long pour un téléphone';
        await pumpParties(
          tester,
          backend: backend,
          size: phoneSize,
          textScale: scale,
        );

        await scrollTo(tester, row(_waitingId), listKey: 'admin-parties-list');
        expect(
          find.byKey(const Key('admin-party-delete-$_waitingId')),
          findsOneWidget,
        );
      });
    }
  });
}
