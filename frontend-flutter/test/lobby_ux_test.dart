// The lobby of the UX study (S1–S4, wip 2026-09-23-flutter-ux-lobby-screen):
// the invite code big and copyable, the settings as one line of chips,
// seats that say who is online and each bot's level — a free seat as text
// pointing at the code, no "add a bot" —, and Start first with the reason
// it is (or is not) active, Delete in the ⋮ menu — on a 360x740 phone at
// text scales 1.0 and 1.5.
//
// The text is laid out in Roboto, as in `parties_ux_test.dart`: the test
// font's square glyphs are about twice as wide.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/router.dart';

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

  const phone = Size(360, 740);

  /// The lobby of `p1`, signed in as Vincent (`u1`), on a phone.
  Future<void> pumpLobby(
    WidgetTester tester,
    FakeLobbyBackend backend, {
    double textScale = 1,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.partyPath('p1'),
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ButtonStyleButton>(find.byKey(Key(key))).onPressed != null;

  final vincent = partyPlayerJson(
    userId: 'u1',
    username: 'Vincent',
    playerIndex: 0,
  );
  final lyo = partyPlayerJson(userId: 'u2', username: 'Lyo', playerIndex: 1);
  final hardBot = partyPlayerJson(
    userId: 'b1',
    username: 'HardBot1',
    playerIndex: 2,
    userType: 'bot',
    botDifficulty: 'hard',
  );
  final alice = partyPlayerJson(
    userId: 'u3',
    username: 'Alice',
    playerIndex: 3,
  );

  /// "Table de Vincent": Vincent hosts, Lyo is online, Alice is not known
  /// to be, a hard bot — four of five seats.
  FakeLobbyBackend table({List<JsonMap>? players, String ownerId = 'u1'}) =>
      FakeLobbyBackend(
        details: partyDetailsJson(
          id: 'p1',
          name: 'Table de Vincent',
          ownerId: ownerId,
          players: players ?? [vincent, lyo, hardBot, alice],
        ),
        connected: [
          connectedPlayerJson('u1', 'Vincent'),
          connectedPlayerJson('u2', 'Lyo', status: 'party'),
        ],
      );

  for (final scale in [1.0, 1.5]) {
    group('lobby UX at a $scale text scale', () {
      testWidgets('S1: the invite code is shown big, and Copy puts it on '
          'the clipboard', (tester) async {
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await pumpLobby(tester, table(), textScale: scale);

        expect(find.text("CODE D'INVITATION"), findsOneWidget);
        final code = tester.widget<SelectableText>(
          find.byKey(const Key('invite-code')),
        );
        expect(code.data, 'BGJARGH7');
        expect(code.style!.fontSize, 26);
        // It opens the screen, above the seats.
        expect(
          tester.getRect(find.byKey(const Key('lobby-invite'))).bottom,
          lessThan(
            tester.getTopLeft(find.byKey(const Key('lobby-settings'))).dy,
          ),
        );

        await tester.tap(find.byKey(const Key('copy-invite-code')));
        await tester.pump();
        expect(copied, ['BGJARGH7']);
        expect(find.text('Code copié : envoie-le à tes amis.'), findsOneWidget);
      });

      testWidgets('S2: the settings are one line of chips — seats, host, '
          'status', (tester) async {
        await pumpLobby(tester, table(), textScale: scale);

        final settings = find.byKey(const Key('lobby-settings'));
        for (final text in ['5 places', "Tu es l'hôte", 'En attente']) {
          expect(
            find.descendant(of: settings, matching: find.text(text)),
            findsOneWidget,
          );
        }
        // One line: every chip on the same row, where the "Settings" card
        // took 120 px.
        final tops = {
          for (final text in ['5 places', "Tu es l'hôte", 'En attente'])
            tester.getTopLeft(find.text(text)).dy,
        };
        expect(tops, hasLength(1));
        expect(tester.getSize(settings).height, lessThan(40));
        expect(find.text('Paramètres'), findsNothing);
      });

      testWidgets('S2: someone who does not host sees no "you host" chip', (
        tester,
      ) async {
        await pumpLobby(tester, table(ownerId: 'u2'), textScale: scale);
        expect(find.text('5 places'), findsOneWidget);
        expect(find.text("Tu es l'hôte"), findsNothing);
      });

      testWidgets('S3: a green dot for who is online, the bot level as a '
          'chip, the free seat as text pointing at the invite code', (
        tester,
      ) async {
        await pumpLobby(tester, table(), textScale: scale);

        // Me, and Lyo whom the presence list has; Alice it does not.
        expect(find.byKey(const Key('online-u1')), findsOneWidget);
        expect(find.byKey(const Key('online-u2')), findsOneWidget);
        expect(find.byKey(const Key('online-u3')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('seat-u2')),
            matching: find.text('en ligne'),
          ),
          findsOneWidget,
        );
        // A bot is always there: a level, no dot.
        expect(find.byKey(const Key('online-b1')), findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const Key('level-b1')),
            matching: find.text('Difficile'),
          ),
          findsOneWidget,
        );
        // Every badge sits at the seat's right edge, however narrow.
        for (final (badge, seat) in [
          ('level-b1', 'seat-b1'),
          ('online-u2', 'seat-u2'),
        ]) {
          expect(
            tester.getRect(find.byKey(Key(seat))).right -
                tester.getRect(find.byKey(Key(badge))).right,
            lessThanOrEqualTo(12.5),
          );
        }
        expect(find.byKey(const Key('host-u1')), findsOneWidget);
        expect(find.byKey(const Key('host-u2')), findsNothing);

        final list = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('empty-seat-0')),
          100,
          scrollable: list,
        );
        final free = find.byKey(const Key('empty-seat-0'));
        expect(
          find.descendant(
            of: free,
            matching: find.text("En attente d'un joueur…"),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: free,
            matching: find.text(
              'Envoie le code d\'invitation pour la remplir.',
            ),
          ),
          findsOneWidget,
        );
        // No route seats a bot in an existing party: no such button.
        expect(find.textContaining('Ajouter'), findsNothing);
        expect(
          find.descendant(of: free, matching: find.byType(ButtonStyleButton)),
          findsNothing,
        );
      });

      testWidgets('S4: Start comes first, named with the player count and '
          'its reason above it; Delete is in the ⋮ menu', (tester) async {
        final backend = table();
        await pumpLobby(tester, backend, textScale: scale);

        final start = find.byKey(const Key('start-party'));
        final leave = find.byKey(const Key('leave-party'));
        final reason = find.byKey(const Key('start-reason'));
        expect(
          find.descendant(
            of: start,
            matching: find.text('Lancer la partie (4 joueurs)'),
          ),
          findsOneWidget,
        );
        expect(enabled(tester, 'start-party'), isTrue);
        expect(
          find.descendant(
            of: reason,
            matching: find.text(
              'Au moins 3 joueurs : la partie peut commencer.',
            ),
          ),
          findsOneWidget,
        );
        // Reason, Start, Leave, in that order, all on screen without a
        // scroll.
        expect(
          tester.getRect(reason).bottom,
          lessThanOrEqualTo(tester.getTopLeft(start).dy),
        );
        expect(
          tester.getRect(start).bottom,
          lessThanOrEqualTo(tester.getTopLeft(leave).dy),
        );
        expect(tester.getRect(leave).bottom, lessThanOrEqualTo(phone.height));
        // Delete is not a thumb away from Leave any more.
        expect(find.byKey(const Key('delete-party')), findsNothing);
        expect(find.text('Supprimer la partie'), findsNothing);

        await tester.tap(find.byKey(const Key('app-bar-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('delete-party')));
        await tester.pumpAndSettle();
        // It still asks first.
        expect(find.byKey(const Key('delete-confirm')), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(
          backend.requests.where((request) => request.method == 'DELETE'),
          isEmpty,
        );
      });

      testWidgets('S4: below three players the reason says how many are '
          'missing, and Start stays off', (tester) async {
        await pumpLobby(
          tester,
          table(players: [vincent, hardBot]),
          textScale: scale,
        );

        expect(enabled(tester, 'start-party'), isFalse);
        expect(find.text('Lancer la partie (2 joueurs)'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('start-reason')),
            matching: find.text('Encore 1 joueur pour démarrer'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('S4: a guest sees why there is no Start for them', (
        tester,
      ) async {
        await pumpLobby(tester, table(ownerId: 'u2'), textScale: scale);

        expect(find.byKey(const Key('start-party')), findsNothing);
        expect(find.text("L'hôte peut lancer la partie."), findsOneWidget);
        expect(find.byKey(const Key('leave-party')), findsOneWidget);
      });
    });
  }
}
