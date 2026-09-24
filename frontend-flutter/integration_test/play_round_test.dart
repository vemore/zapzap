// End to end: the real client against a live backend — no fake, no fixture.
//
// Registers a fresh user, creates a party of three with two easy bots, starts
// it and plays until the round ends — the hand size when it is this player's
// to pick, the first card of the hand, a draw from the deck, ZapZap as soon as
// the hand allows it — then checks the end-of-round screen.
//
// It needs a backend with the bot accounts (`npm run init-bots`) and is run
// with `flutter drive`, never `flutter test`: scripts/flutter_e2e.sh does both
// (CI runs it); the procedure, and the `API_BASE_URL` it takes, are in
// .llmwiki/Testing.md.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/services/api_config.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_round_end.dart';

/// How long a round may take: the bots answer within a second or two, and a
/// round of three is a few dozen turns.
const roundTimeout = Duration(minutes: 5);

/// How long one screen may take to answer (HTTP, then the event stream).
const stepTimeout = Duration(seconds: 30);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a fresh user plays a round against two bots', (tester) async {
    const api = ApiConfig.definedBaseUrl;
    expect(
      api,
      isNotEmpty,
      reason: 'run with --dart-define=API_BASE_URL=http://localhost:<port>',
    );
    // Unique per run, within the 30 characters and [a-zA-Z0-9_-] the
    // register form accepts.
    final username =
        'e2e_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: ApiConfig.fromEnvironment(),
        locale: const Locale('fr'),
        initialLocation: AppRoutes.register,
      ),
    );

    // Register: the session opens on the parties list.
    await pumpUntil(tester, find.byKey(const Key('register-username')));
    await tester.enterText(
      find.byKey(const Key('register-username')),
      username,
    );
    await tester.enterText(
      find.byKey(const Key('register-password')),
      'e2e-password',
    );
    await tap(tester, find.byKey(const Key('register-submit')));
    await pumpUntil(tester, find.byKey(const Key('create-party')));
    log('registered $username');

    // Create a party of three: this player and two easy bots.
    await tap(tester, find.byKey(const Key('create-party')));
    await pumpUntil(tester, find.byKey(const Key('party-name')));
    await chooseOption(tester, find.byKey(const Key('player-count')), '3');
    await pumpUntil(tester, find.byKey(const Key('slot-1')));
    await chooseOption(
      tester,
      find.byKey(const Key('slot-0-type')),
      'Bot — Facile',
    );
    await chooseOption(
      tester,
      find.byKey(const Key('slot-1-type')),
      'Bot — Facile',
    );
    expect(find.text('Humains : 1 · Bots : 2'), findsOneWidget);
    // The name last: on the web, a focused text field swallows the next tap,
    // and a dropdown tapped then never opens.
    await tester.enterText(
      find.byKey(const Key('party-name')),
      'E2E $username',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.byKey(const Key('create-submit')));

    // The lobby: the bots are seated, the owner starts.
    final start = find.byKey(const Key('start-party'));
    await pumpUntil(tester, start);
    await pumpUntilTrue(tester, () => isEnabled(tester, start));
    log('lobby full, starting');
    await tap(tester, start);

    // The board.
    await pumpUntil(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w.key == const Key('confirm-hand-size') ||
            w.key == const Key('play-cards') ||
            w.key == const Key('turnBanner'),
      ),
    );
    log('on the board');

    await playUntilRoundEnds(tester);

    // The end of the round: three rows, this player's marked, a ZapZap
    // banner (a round only ends on a call), and the way on.
    expect(find.byKey(const Key('roundOver')), findsOneWidget);
    expect(find.byKey(const Key('roundEndTable')), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      expect(find.byKey(GameRoundEnd.playerKey(index)), findsOneWidget);
    }
    expect(find.byKey(const Key('roundEndMe')), findsOneWidget);
    expect(find.byKey(const Key('zapZapBanner')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key == const Key('next-round') ||
            w.key == const Key('back-to-parties'),
      ),
      findsOneWidget,
    );
    log('round over');
    // `flutter drive` writes it to build/integration_response_data.json.
    binding.reportData = {'steps': _log};
  });
}

/// Takes this player's moves until the end-of-round screen shows.
Future<void> playUntilRoundEnds(WidgetTester tester) async {
  final roundOver = find.byKey(const Key('roundOver'));
  final handSize = find.byKey(const Key('confirm-hand-size'));
  final zapZap = find.byKey(const Key('call-zapzap'));
  final play = find.byKey(const Key('play-cards'));
  final draw = find.byKey(const Key('draw-card'));
  final firstCard = find.byKey(CardFan.itemKey(0));
  final myTurn = find.byKey(const Key('turnSteps'));

  var moves = 0;
  final deadline = DateTime.now().add(roundTimeout);
  while (roundOver.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'the round did not end within $roundTimeout ($moves moves)\n'
        '${screenText()}',
      );
    }
    if (handSize.evaluate().isNotEmpty && isEnabled(tester, handSize)) {
      log('choosing the hand size');
      await tap(tester, handSize);
    } else if (myTurn.evaluate().isNotEmpty && isEnabled(tester, zapZap)) {
      log('calling ZapZap');
      await tap(tester, zapZap);
      await pumpUntil(tester, find.byKey(const Key('zapzap-confirm')));
      await tap(tester, find.byKey(const Key('zapzap-confirm')));
      moves++;
    } else if (draw.evaluate().isNotEmpty && isEnabled(tester, draw)) {
      await tap(tester, draw);
      moves++;
      log('turn ${moves ~/ 2}: played and drew');
    } else if (myTurn.evaluate().isNotEmpty && play.evaluate().isNotEmpty) {
      if (isEnabled(tester, play)) {
        await tap(tester, play);
        moves++;
      } else if (firstCard.evaluate().isNotEmpty) {
        // Nothing selected yet: one card alone is always a valid play.
        await tap(tester, firstCard);
      }
    }
    // Let the move's answer and the bots' turns arrive.
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Pumps real time until [finder] finds something.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = stepTimeout,
}) => pumpUntilTrue(
  tester,
  () => finder.evaluate().isNotEmpty,
  timeout: timeout,
  what: finder.describeMatch(Plurality.one),
);

/// Pumps real time until [condition] holds.
Future<void> pumpUntilTrue(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = stepTimeout,
  String what = 'the condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out after $timeout waiting for $what\n${screenText()}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Whether the button [finder] finds can be pressed.
bool isEnabled(WidgetTester tester, Finder finder) =>
    tester.widget<ButtonStyleButton>(finder).enabled;

/// Scrolls [finder] into view, taps it and lets a frame through.
Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Opens the dropdown [field] and picks the item labelled [option].
Future<void> chooseOption(
  WidgetTester tester,
  Finder field,
  String option,
) async {
  // The open menu holds a second copy of the selected label: the last one is
  // the menu's.
  await tap(tester, field);
  await pumpUntil(tester, find.text(option));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.text(option).last);
  await tester.pump(const Duration(milliseconds: 300));
}

/// What the run went through, in the failure message: `flutter drive` on the
/// web does not relay the browser's console.
final _log = <String>[];

void log(String message) {
  _log.add(message);
  debugPrint('[e2e] $message');
}

/// The steps so far and the text on screen, to tell why a wait timed out.
String screenText() {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .join(' | ');
  return 'steps: ${_log.join(' > ')}\non screen: $texts';
}
