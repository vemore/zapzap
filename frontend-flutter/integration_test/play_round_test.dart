// End to end: the real client against a live backend — no fake, no fixture.
//
// Registers a fresh user, creates a party of three, seats an easy bot by hand
// and fills the last seat as the game starts (« Compléter avec des bots et
// commencer »), then plays until the round ends — four cards when the hand size is this
// player's to pick, the suggestion that takes the most points off the hand, a
// draw from the deck, ZapZap as soon as the hand allows it — then checks the
// end-of-round screen.
//
// The deal is fixed: the backend is a debug build started with
// ZAPZAP_TEST_FIXED_DECK=1, which deals the cards in id order
// (`order_for_deal`, zapzap-rust/src/domain/services/game_service.rs). A
// random deal cannot bound the round, whatever the driver plays: four high
// cards of four ranks and high draws keep a hand over 5 points for good. With
// the fixed deal the round ends by this player's turn [maxTurns]
// ([fixedDealPoints] tells how).
//
// It needs a backend with the bot accounts (`zapzap-backend seed`) and is run
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
import 'package:zapzap/widgets/game_hand_size_selector.dart';
import 'package:zapzap/widgets/game_round_end.dart';
import 'package:zapzap/widgets/hand_suggestions.dart';

/// What this player's hand is worth as its turn 1 starts, with the fixed deal.
/// Seat 0 — this player, who starts round 1 and picks four cards — is dealt
/// A♠ 2♠ 3♠ 4♠; the bots get 5♠–8♠ and 9♠–Q♠; K♠ is flipped. Turn 1 plays
/// the run, the suggestion taking the most points off, and draws A♥ from the
/// deck: 1 point. No bot can touch that hand, so turn 2 calls ZapZap — unless
/// a bot's call ended the round first.
const fixedDealPoints = 10;

/// The turns this player may start before the round must be over.
const maxTurns = 2;

/// How long a round may take, a safety net behind [maxTurns]: the script
/// starts the bots without a pause between their actions.
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

    // Create a party of three: the form asks for the seats only.
    await tap(tester, find.byKey(const Key('create-party')));
    await pumpUntil(tester, find.byKey(const Key('party-name')));
    await chooseOption(tester, find.byKey(const Key('player-count')), '3');
    // The name last: on the web, a focused text field swallows the next tap,
    // and a dropdown tapped then never opens.
    await tester.enterText(
      find.byKey(const Key('party-name')),
      'E2E $username',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.byKey(const Key('create-submit')));

    // The lobby: one easy bot seated by hand, on the first free seat.
    final addBot = find.byKey(const Key('empty-seat-0-add-bot'));
    await pumpUntil(tester, addBot);
    await tap(tester, addBot);
    await pumpUntil(tester, find.byKey(const Key('add-bot-easy')));
    await tester.pump(const Duration(milliseconds: 300));
    await tap(tester, find.byKey(const Key('add-bot-easy')));
    await pumpUntil(tester, find.text('Joueurs (2/3)'));
    log('one bot seated');

    // Then the last seat filled with an easy bot as the game starts.
    await tap(tester, find.byKey(const Key('fill-and-start')));
    await pumpUntil(tester, find.byKey(const Key('fill-level-easy')));
    await tap(tester, find.byKey(const Key('fill-level-easy')));
    await tap(tester, find.byKey(const Key('fill-confirm')));
    log('filled and started');

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

/// Takes this player's moves until the end-of-round screen shows, logging
/// what the hand is worth as each of its turns starts.
Future<void> playUntilRoundEnds(WidgetTester tester) async {
  final roundOver = find.byKey(const Key('roundOver'));
  final handSize = find.byKey(const Key('confirm-hand-size'));
  final zapZap = find.byKey(const Key('call-zapzap'));
  final play = find.byKey(const Key('play-cards'));
  final draw = find.byKey(const Key('draw-card'));
  final smallestHand = find.byKey(GameHandSizeSelector.sizeKey(4));
  final bestPlay = find.byKey(HandSuggestions.chipKey(0));
  final firstCard = find.byKey(CardFan.itemKey(0));
  final myTurn = find.byKey(const Key('turnSteps'));

  var turn = 0;
  // From this player's play step until its draw.
  var inTurn = false;
  final deadline = DateTime.now().add(roundTimeout);
  while (roundOver.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'the round did not end within $roundTimeout (turn $turn)\n'
        '${screenText()}',
      );
    }
    if (handSize.evaluate().isNotEmpty && isEnabled(tester, handSize)) {
      log('choosing the hand size');
      if (smallestHand.evaluate().isNotEmpty) await tap(tester, smallestHand);
      await tap(tester, handSize);
    } else if (myTurn.evaluate().isNotEmpty && play.evaluate().isNotEmpty) {
      if (!inTurn) {
        inTurn = true;
        turn++;
        final points = handPoints();
        log('turn $turn: hand at $points pts');
        if (turn > maxTurns) {
          fail('the round did not end within $maxTurns turns\n${screenText()}');
        }
        if (turn == 1 && points != fixedDealPoints) {
          fail(
            'not the fixed deal ($points pts, not $fixedDealPoints): start '
            'the backend, a debug build, with ZAPZAP_TEST_FIXED_DECK=1\n'
            '${screenText()}',
          );
        }
      }
      if (isEnabled(tester, zapZap)) {
        log('turn $turn: calling ZapZap');
        await tap(tester, zapZap);
        await pumpUntil(tester, find.byKey(const Key('zapzap-confirm')));
        await tap(tester, find.byKey(const Key('zapzap-confirm')));
      } else if (isEnabled(tester, play)) {
        await tap(tester, play);
        log('turn $turn: played');
      } else if (bestPlay.evaluate().isNotEmpty) {
        // The suggestions come most points first.
        await tap(tester, bestPlay);
      } else if (firstCard.evaluate().isNotEmpty) {
        // No suggestion (jokers only): one card alone is always a valid play.
        await tap(tester, firstCard);
      }
    } else if (draw.evaluate().isNotEmpty && isEnabled(tester, draw)) {
      await tap(tester, draw);
      inTurn = false;
      log('turn $turn: drew from the deck');
    }
    // Let the move's answer and the bots' turns arrive.
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// What this player's hand is worth, jokers at 0, read from its title
/// ("Ta main · 10 pts").
int handPoints() {
  final title = find.byKey(const Key('handValue')).evaluate().first.widget;
  final text = (title as Text).data ?? '';
  final points = RegExp(r'\d+').firstMatch(text)?.group(0);
  if (points == null) fail('no value in the hand title "$text"');
  return int.parse(points);
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
