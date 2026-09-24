// The parties screen of the UX study (P1–P4, wip
// 2026-09-23-flutter-ux-parties-screen): my games first, compact cards with
// one action, a Create button that covers nothing, and the loading, empty
// and failed states — on a 360x740 phone at text scales 1.0 and 1.5.
//
// The text is laid out in Roboto, the font the app is drawn in on Android
// and in the PWA: the test font's square glyphs are about twice as wide, and
// would make a compact card's second line wrap into four.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/create_party_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/party_card.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  setUpAll(() async {
    // `flutter test` sets FLUTTER_ROOT; the SDK ships Roboto for Material.
    final fonts =
        '${Platform.environment['FLUTTER_ROOT']}'
        '/bin/cache/artifacts/material_fonts';
    final loader = FontLoader('Roboto');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      final bytes = File('$fonts/Roboto-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });

  /// The parties screen signed in as Vincent (`u1`), over [backend].
  Future<void> pumpApp(
    WidgetTester tester,
    FakeLobbyBackend backend, {
    required Size size,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.parties,
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  // The UX study's parties screen (P1–P4), on a phone.
  group('parties UX', () {
    const phone = Size(360, 740);

    /// A lobby of mine, a running game of mine listed after it, and two
    /// parties of someone else's.
    List<JsonMap> mixed() => [
      partySummaryJson(id: 'o1', name: 'Soirée du jeudi', ownerId: 'u2'),
      partySummaryJson(
        id: 'm1',
        name: 'Table de Vincent',
        playerCount: 4,
        isMember: true,
      ),
      partySummaryJson(
        id: 'o2',
        name: 'Apéro cartes',
        ownerId: 'u3',
        playerCount: 5,
        maxPlayers: 5,
      ),
      partySummaryJson(
        id: 'm2',
        name: 'Revanche',
        ownerId: 'u2',
        status: 'playing',
        playerCount: 4,
        maxPlayers: 4,
        isMember: true,
      ),
    ];

    double top(WidgetTester tester, String key) =>
        tester.getTopLeft(find.byKey(Key(key))).dy;

    Color border(WidgetTester tester, String key) =>
        ((tester.widget<Card>(find.byKey(Key(key))).shape!
                    as RoundedRectangleBorder)
                .side)
            .color;

    for (final scale in [1.0, 1.5]) {
      group('at a $scale text scale', () {
        testWidgets('P1: my games come first, a running one on top with an '
            '"In progress" badge', (tester) async {
          await pumpApp(
            tester,
            FakeLobbyBackend(parties: mixed()),
            size: phone,
            textScale: scale,
          );

          expect(find.text('Mes parties'), findsOneWidget);
          expect(
            top(tester, 'parties-heading-mine'),
            lessThan(top(tester, 'party-m2')),
          );
          expect(top(tester, 'party-m2'), lessThan(top(tester, 'party-m1')));
          expect(
            top(tester, 'party-m1'),
            lessThan(top(tester, 'parties-heading-open')),
          );
          expect(
            top(tester, 'parties-heading-open'),
            lessThan(top(tester, 'party-o1')),
          );
          expect(find.byKey(const Key('in-progress-m2')), findsOneWidget);
          expect(find.byKey(const Key('joined-m1')), findsOneWidget);
          expect(border(tester, 'party-m2'), AppColors.amber400);
          expect(border(tester, 'party-m1'), PartyCard.joined);
          expect(border(tester, 'party-o1'), AppColors.slate600);
          // No backend says whose turn it is: no such badge.
          expect(find.textContaining('ton tour'), findsNothing);
          // The host is told so; someone else's party is not mine to host.
          expect(
            find.textContaining("4 / 5 · En attente · tu es l'hôte"),
            findsOneWidget,
          );
          expect(find.textContaining('4 / 4'), findsOneWidget);
        });

        testWidgets('P2: two lines per card and one action, Resume filled '
            'and the others outlined', (tester) async {
          await pumpApp(
            tester,
            FakeLobbyBackend(parties: mixed()),
            size: phone,
            textScale: scale,
          );

          for (final id in ['m1', 'm2', 'o1', 'o2']) {
            final card = find.byKey(Key('party-$id'));
            expect(
              find.descendant(
                of: card,
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
              findsOneWidget,
              reason: 'one button on $id',
            );
            // The old card was ~160 px with Players / Status labels: 3.5
            // parties a screen. At 100 px, six fit under the app bar.
            expect(
              tester.getSize(card).height,
              lessThanOrEqualTo(scale == 1.0 ? 100 : 130),
              reason: '$id is compact',
            );
            // The details and the button share the second line.
            final details = tester.getRect(
              find.byKey(Key('party-details-$id')),
            );
            final button = tester.getRect(
              find.descendant(
                of: card,
                matching: find.bySubtype<ButtonStyleButton>(),
              ),
            );
            expect(details.top, lessThan(button.bottom), reason: id);
            expect(button.top, lessThan(details.bottom), reason: id);
          }
          expect(find.text('Joueurs'), findsNothing);
          expect(find.text('Statut'), findsNothing);
          expect(
            tester.widget(find.byKey(const Key('open-m2'))),
            isA<FilledButton>(),
          );
          expect(find.text('Reprendre'), findsOneWidget);
          expect(
            tester.widget(find.byKey(const Key('open-m1'))),
            isA<OutlinedButton>(),
          );
          expect(find.text('Salon'), findsOneWidget);
          expect(
            tester.widget(find.byKey(const Key('join-o1'))),
            isA<OutlinedButton>(),
          );
          expect(enabled(tester, 'join-o1'), isTrue);
          expect(enabled(tester, 'join-o2'), isFalse);
          expect(find.text('Complète'), findsOneWidget);
        });

        testWidgets('P3: the amber Create button never covers the last '
            "card's button", (tester) async {
          await pumpApp(
            tester,
            FakeLobbyBackend(
              parties: [
                for (var i = 0; i < 10; i++)
                  partySummaryJson(id: 'p$i', name: 'Partie $i', ownerId: 'u2'),
              ],
            ),
            size: phone,
            textScale: scale,
          );

          final fab = tester.widget<FloatingActionButton>(
            find.byKey(const Key('create-party')),
          );
          expect(fab.backgroundColor, AppColors.amber400);

          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -5000),
          );
          await tester.pumpAndSettle();
          final last = tester.getRect(find.byKey(const Key('join-p9')));
          final create = tester.getRect(find.byKey(const Key('create-party')));
          expect(last.bottom, lessThanOrEqualTo(create.top));
          expect(PartiesScreen.fabClearance, greaterThanOrEqualTo(88));
        });

        testWidgets('P4: skeleton cards while the list loads', (tester) async {
          final backend = FakeLobbyBackend(parties: mixed())
            ..partiesGate = Completer<void>();
          await pumpApp(tester, backend, size: phone, textScale: scale);

          expect(find.byKey(const Key('party-skeleton')), findsNWidgets(3));
          expect(
            find.bySemanticsLabel('Chargement des parties…'),
            findsOneWidget,
          );
          expect(find.byType(CircularProgressIndicator), findsNothing);

          backend.partiesGate!.complete();
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('party-skeleton')), findsNothing);
          expect(find.byKey(const Key('party-m2')), findsOneWidget);
        });

        testWidgets('P4: no open party ends on an invitation that opens the '
            'form', (tester) async {
          await pumpApp(
            tester,
            FakeLobbyBackend(parties: [mixed()[3]]),
            size: phone,
            textScale: scale,
          );

          expect(find.byKey(const Key('parties-invite')), findsOneWidget);
          expect(find.text("Pas d'autre partie ouverte."), findsOneWidget);
          expect(
            find.text('Tire vers le bas pour actualiser.'),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const Key('parties-invite-create')));
          await tester.pumpAndSettle();
          expect(find.byType(CreatePartyScreen), findsOneWidget);
        });
      });
    }

    testWidgets('P4: no party at all says so, and pulling down reloads', (
      tester,
    ) async {
      final backend = FakeLobbyBackend();
      await pumpApp(tester, backend, size: phone);
      expect(find.text('Aucune partie disponible'), findsOneWidget);
      expect(find.byKey(const Key('parties-invite-create')), findsOneWidget);

      int loads() => backend.requests
          .where((request) => request.url.path == '/api/party')
          .length;
      final before = loads();
      backend.parties = [partySummaryJson(id: 'p1', name: 'Nouvelle')];
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();
      expect(loads(), before + 1);
      expect(find.text('Nouvelle'), findsOneWidget);
      expect(find.byKey(const Key('parties-invite')), findsNothing);
    });

    testWidgets('P4: a failed load keeps the list it had under the banner, '
        'without the invitation', (tester) async {
      final backend = FakeLobbyBackend(parties: [mixed()[3]]);
      await pumpApp(tester, backend, size: phone);
      backend.failures['GET /api/party'] = (
        status: 500,
        body: {'error': 'boom'},
      );
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Une erreur est survenue. Réessaie.'), findsOneWidget);
      expect(find.byKey(const Key('party-m2')), findsOneWidget);
      expect(find.byKey(const Key('parties-invite')), findsNothing);
    });
  });
}
