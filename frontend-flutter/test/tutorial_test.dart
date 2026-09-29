import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/card.dart';
import 'package:zapzap/models/game_state.dart';
import 'package:zapzap/providers/tutorial_game.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/home_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/screens/tutorial_screen.dart';
import 'package:zapzap/services/api_client.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/services/tutorial_offer_store.dart';
import 'package:zapzap/widgets/card_back.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/utils/card_l10n.dart';
import 'package:zapzap/utils/rules.dart' as rules;
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_player_table.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/playing_card.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';
import 'wide_screen_helpers.dart';

void main() {
  /// The app signed out on [location], on a 400x860 phone; every HTTP
  /// request lands in the list returned, and is refused.
  Future<List<http.Request>> pumpSignedOut(
    WidgetTester tester, {
    String location = AppRoutes.tutorial,
    Locale locale = const Locale('fr'),
    TutorialOfferStore? offer,
    ApiClient? api,
    Size size = const Size(400, 860),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (textScale != 1) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final requests = <http.Request>[];
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: locale,
        initialLocation: location,
        apiClient:
            api ??
            fakeApi(
              (request) => throw StateError('unexpected ${request.url}'),
              requests: requests,
            ),
        tokenStorage: MemoryTokenStorage(),
        sseTransport: FakeSseTransport(),
        tutorialOffer: offer,
      ),
    );
    await tester.pumpAndSettle();
    return requests;
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(TutorialScreen)));

  String coach(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('tutorialText'))).data!;

  String? hint(WidgetTester tester) {
    final found = find.byKey(const Key('tutorialHint'));
    return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps card [id] of the hand on its left edge, which the next card of
  /// the fan never covers.
  Future<void> tapCard(WidgetTester tester, int id) async {
    final index = tester
        .widget<GameHand>(find.byType(GameHand))
        .cards
        .indexOf(id);
    final card = find.byKey(CardFan.itemKey(index));
    await tester.ensureVisible(card);
    await tester.tapAt(tester.getTopLeft(card) + const Offset(6, 30));
    await tester.pumpAndSettle();
  }

  /// Plays the opponent's turn out, one move after [TutorialGame.opponentPause].
  Future<void> opponentTurn(WidgetTester tester) async {
    for (var move = 0; move < 2; move++) {
      await tester.pump(TutorialGame.opponentPause);
      await tester.pumpAndSettle();
    }
  }

  /// The move [step] asks for.
  Future<void> playStep(WidgetTester tester, TutorialStep step) async {
    if (step.isInfo) {
      await tap(
        tester,
        find.byKey(
          Key(step == TutorialStep.end ? 'tutorial-finish' : 'tutorial-next'),
        ),
      );
    } else if (step.play != null) {
      for (final id in step.play!) {
        await tapCard(tester, id);
      }
      await tap(tester, find.byKey(const Key('play-cards')));
    } else if (step.take != null) {
      await tap(tester, find.byKey(GameTableArea.discardKey(step.take!)));
      await tap(tester, find.byKey(const Key('draw-card')));
      await opponentTurn(tester);
    } else if (step.draws) {
      await tap(tester, find.byKey(const Key('draw-deck')));
      await opponentTurn(tester);
    } else {
      await tap(tester, find.byKey(const Key('call-zapzap')));
      await tap(tester, find.byKey(const Key('zapzap-confirm')));
    }
  }

  String handValue(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('handValue'))).data!;

  group('the example game', () {
    testWidgets('plays from the first step to the last with the scripted '
        'moves, and never calls the API', (tester) async {
      final requests = await pumpSignedOut(tester);
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(handValue(tester), 'Ta main · 40 pts');

      final seen = <String>{};
      for (final step in TutorialStep.values) {
        expect(find.byKey(const Key('tutorialCoach')), findsOneWidget);
        expect(seen.add(coach(tester)), isTrue, reason: '$step');
        if (step == TutorialStep.zapZap) {
          expect(handValue(tester), 'Ta main · 4 pts');
        }
        await playStep(tester, step);
        expect(hint(tester), isNull, reason: '$step');
      }

      // Finish leaves it, for home (signed out).
      expect(find.byType(TutorialScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(requests, isEmpty);
    });

    // A 360x740 phone: a bubble that does not fit throws a layout error.
    for (final locale in AppLocalizations.supportedLocales) {
      for (final scale in [1.0, if (locale.languageCode == 'de') 1.5]) {
        testWidgets('every step fits a 360x740 phone in $locale at text '
            'scale $scale', (tester) async {
          await pumpSignedOut(
            tester,
            locale: locale,
            size: const Size(360, 740),
            textScale: scale,
          );
          for (final step in TutorialStep.values) {
            expect(find.byKey(const Key('tutorialCoach')), findsOneWidget);
            await playStep(tester, step);
          }
          expect(find.byType(TutorialScreen), findsNothing);
        });
      }
    }

    group('wide screen', () {
      // The phone column, centred ([TutorialScreen.maxWidth]), played
      // through on a laptop, a desktop monitor and a portrait tablet.
      for (final MapEntry(key: name, value: size) in wideScreens.entries) {
        for (final scale in wideTextScales) {
          testWidgets('every step fits $name at text scale $scale', (
            tester,
          ) async {
            await pumpSignedOut(tester, size: size, textScale: scale);
            final board = tester.getRect(find.byType(GameTableArea));
            expect(board.center.dx, closeTo(size.width / 2, 1));
            for (final step in TutorialStep.values) {
              expect(find.byKey(const Key('tutorialCoach')), findsOneWidget);
              await playStep(tester, step);
            }
            expect(find.byType(TutorialScreen), findsNothing);
          });
        }
      }
    });

    testWidgets('a move other than the one asked for is refused with the '
        "step's hint, and the step stays", (tester) async {
      await pumpSignedOut(tester);
      await playStep(tester, TutorialStep.intro);
      final text = l10n(tester);

      // The single card asks for K♠: 9♥ is refused.
      final single = coach(tester);
      await tapCard(tester, TutorialGame.nineHearts);
      await tap(tester, find.byKey(const Key('play-cards')));
      expect(hint(tester), text.tutorialPlaySingleHint('K♠'));
      expect(coach(tester), single);
      expect(handValue(tester), 'Ta main · 40 pts');

      await tap(tester, find.byKey(const Key('clear-selection')));
      await playStep(tester, TutorialStep.playSingle);
      expect(hint(tester), isNull);

      // The draw asks for the deck: the flipped 8♠ is refused.
      await tap(
        tester,
        find.byKey(GameTableArea.discardKey(TutorialGame.eightSpades)),
      );
      await tap(tester, find.byKey(const Key('draw-card')));
      expect(hint(tester), text.tutorialDrawDeckHint);
      expect(coach(tester), text.tutorialDrawDeck);

      // Unpicked, the deck is taken.
      await tap(
        tester,
        find.byKey(GameTableArea.discardKey(TutorialGame.eightSpades)),
      );
      await playStep(tester, TutorialStep.drawDeck);
      await playStep(tester, TutorialStep.playPair);

      // The take asks for A♣ from the pile: the deck is refused.
      await tap(tester, find.byKey(const Key('draw-deck')));
      expect(hint(tester), text.tutorialTakePileHint('A♣'));

      await playStep(tester, TutorialStep.takePile);
      await playStep(tester, TutorialStep.playRun);
      await playStep(tester, TutorialStep.drawAgain);

      // ZapZap's step: a play is refused.
      await tapCard(tester, TutorialGame.twoDiamonds);
      await tap(tester, find.byKey(const Key('play-cards')));
      expect(hint(tester), text.tutorialZapZapHint);
      expect(handValue(tester), 'Ta main · 4 pts');
    });

    for (final step in TutorialStep.values) {
      testWidgets('Skip leaves it at step ${step.name}, back to the login '
          'screen it was opened from', (tester) async {
        await pumpSignedOut(tester, location: AppRoutes.login);
        await tap(tester, find.byKey(const Key('login-tutorial')));
        expect(find.byType(TutorialScreen), findsOneWidget);

        for (final before in TutorialStep.values.take(step.index)) {
          await playStep(tester, before);
        }
        await tap(tester, find.byKey(const Key('tutorial-skip')));

        expect(find.byType(TutorialScreen), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
      });
    }

    /// The card drawn under a leaving card's key, which moves.
    Finder image(Finder finder) => find.descendant(
      of: finder,
      matching: find.byWidgetPredicate(
        (widget) => widget is PlayingCard || widget is CardBack,
      ),
    );

    GameTableArea felt(WidgetTester tester) =>
        tester.widget<GameTableArea>(find.byType(GameTableArea));

    testWidgets("the felt sees the player's take on its own, the A♣ leaving "
        "down toward the hand, then Alex's play, then Alex's draw", (
      tester,
    ) async {
      await pumpSignedOut(tester);
      for (final step in TutorialStep.values.take(
        TutorialStep.takePile.index,
      )) {
        await playStep(tester, step);
      }
      final text = l10n(tester);
      await tap(
        tester,
        find.byKey(GameTableArea.discardKey(TutorialGame.aceClubs)),
      );
      await tester.ensureVisible(find.byKey(const Key('draw-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw-card')));
      await tester.pump();

      // The player's take, and nothing else yet.
      final take = felt(tester).lastAction!;
      expect(
        (take.type, take.playerIndex, take.source, take.cardId),
        ('draw', TutorialGame.me, 'played', TutorialGame.aceClubs),
      );
      expect(felt(tester).playedByMe, isTrue);
      expect(
        find.text(
          text.gameActionTookDiscardCard(
            text.tutorialGuestName,
            text.cardName(const GameCard(TutorialGame.aceClubs)),
          ),
        ),
        findsOneWidget,
      );
      expect(coach(tester), text.tutorialOpponentTurn('Alex'));
      final leaving = find.byKey(
        GameTableArea.leavingKey(TutorialGame.aceClubs),
      );
      final start = tester.getTopLeft(image(leaving)).dy;
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getTopLeft(image(leaving)).dy, greaterThan(start));

      // Nothing is taken while Alex moves.
      await tester.pumpAndSettle();
      expect(felt(tester).onDeckTap, isNull);
      expect(tester.takeException(), isNull);

      await tester.pump(TutorialGame.opponentPause);
      final play = felt(tester).lastAction!;
      expect((play.type, play.playerIndex), ('play', TutorialGame.opponent));
      expect(play.cardIds, [TutorialGame.eightClubs]);
      expect(felt(tester).playedByMe, isFalse);
      await tester.pumpAndSettle();

      await tester.pump(TutorialGame.opponentPause);
      final draw = felt(tester).lastAction!;
      expect(
        (draw.type, draw.playerIndex, draw.source),
        ('draw', TutorialGame.opponent, 'deck'),
      );
      await tester.pumpAndSettle();
      expect(coach(tester), isNot(text.tutorialOpponentTurn('Alex')));
      expect(find.byKey(const Key('play-cards')), findsOneWidget);
    });

    testWidgets("the player's deck draw leaves the deck down toward the "
        'hand, before Alex moves', (tester) async {
      await pumpSignedOut(tester);
      for (final step in TutorialStep.values.take(
        TutorialStep.drawDeck.index,
      )) {
        await playStep(tester, step);
      }
      await tester.ensureVisible(find.byKey(const Key('draw-deck')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw-deck')));
      await tester.pump();
      final draw = felt(tester).lastAction!;
      expect(
        (draw.type, draw.playerIndex, draw.source),
        ('draw', TutorialGame.me, 'deck'),
      );
      expect(felt(tester).playedByMe, isTrue);
      final leaving = find.byKey(GameTableArea.deckLeavingKey);
      final start = tester.getTopLeft(image(leaving)).dy;
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getTopLeft(image(leaving)).dy, greaterThan(start));
      await opponentTurn(tester);
    });

    testWidgets("once ZapZap has held, Alex's score is his hand's points, "
        'as the bubble says', (tester) async {
      await pumpSignedOut(tester);
      int score(int player) => tester
          .widget<GamePlayerTable>(find.byType(GamePlayerTable))
          .seats
          .singleWhere((seat) => seat.playerIndex == player)
          .score;
      for (final step in TutorialStep.values.take(TutorialStep.held.index)) {
        expect(score(TutorialGame.opponent), 0, reason: '$step');
        await playStep(tester, step);
      }
      final points = rules.handValue(
        TutorialGame.opponentFinalHand,
        penalty: true,
      );
      expect(points, greaterThan(rules.zapZapThreshold));
      expect(score(TutorialGame.opponent), points);
      expect(score(TutorialGame.me), 0);
      expect(coach(tester), l10n(tester).tutorialHeld('Alex'));
      await playStep(tester, TutorialStep.held);
      expect(score(TutorialGame.opponent), points);
    });

    testWidgets('the values it states are those of GAME_RULES.md', (
      tester,
    ) async {
      final rules = File('../GAME_RULES.md').readAsStringSync();
      expect(rules, contains('must be **5 points or less**'));
      expect(rules, contains('Players above **100 points** are eliminated'));

      await pumpSignedOut(tester, locale: const Locale('en'));
      expect(coach(tester), contains('bring it down to 5 points or less'));
      for (final step in TutorialStep.values.take(TutorialStep.end.index)) {
        await playStep(tester, step);
      }
      expect(coach(tester), contains('plus 5 for each other player'));
      expect(
        coach(tester),
        contains('Above 100 points, a player is eliminated.'),
      );
    });
  });

  group('TutorialGame', () {
    /// The moves the script asks for, on [game] with no board.
    void playAll(TutorialGame game, FakeAsync async) {
      for (final step in TutorialStep.values) {
        if (step.isInfo) {
          game.next();
        } else if (step.play != null) {
          game.selectCards(step.play!.toList());
          game.play();
        } else if (step.draws) {
          if (step.take != null) game.selectDiscardCard(step.take!);
          game.draw();
          async.elapse(TutorialGame.opponentPause * 2);
        } else {
          game.zapZap();
        }
        expect(game.refused, isFalse, reason: '$step');
      }
    }

    test('a draw is heard on its own, then Alex plays, then Alex draws: '
        'one notification each, in turn', () {
      fakeAsync((async) {
        final game = TutorialGame();
        final seen = <LastAction>[];
        game.addListener(() {
          final action = game.lastAction;
          if (action != null && (seen.isEmpty || seen.last != action)) {
            seen.add(action);
          }
        });
        game.next();
        game.selectCards([TutorialGame.kingSpades]);
        game.play();
        seen.clear();

        game.draw(fromDeck: true);
        expect(seen.map((a) => (a.type, a.playerIndex)), [
          ('draw', TutorialGame.me),
        ]);
        expect(game.opponentMoving, isTrue);
        expect(game.step, TutorialStep.drawDeck);
        // A second draw meanwhile is ignored, not refused.
        game.draw(fromDeck: true);
        expect(game.refused, isFalse);
        expect(game.hand, hasLength(6));

        async.elapse(TutorialGame.opponentPause);
        expect(seen.map((a) => (a.type, a.playerIndex)), [
          ('draw', TutorialGame.me),
          ('play', TutorialGame.opponent),
        ]);
        async.elapse(TutorialGame.opponentPause);
        expect(seen.map((a) => (a.type, a.playerIndex)), [
          ('draw', TutorialGame.me),
          ('play', TutorialGame.opponent),
          ('draw', TutorialGame.opponent),
        ]);
        expect(game.opponentMoving, isFalse);
        expect(game.step, TutorialStep.playPair);
        game.dispose();
      });
    });

    test('the deck starts at 54 less two hands of six and the flipped card, '
        'and loses one card a draw', () {
      fakeAsync((async) {
        final game = TutorialGame();
        expect(game.deckSize, 54 - 2 * 6 - 1);
        expect(TutorialGame.startingDeck, 41);
        playAll(game, async);
        // Two deck draws of the player's, three of Alex's.
        expect(game.deckSize, 41 - 2 - 3);
        game.dispose();
      });
    });

    test("disposed during Alex's turn, nothing fires after", () {
      fakeAsync((async) {
        final game = TutorialGame()
          ..next()
          ..selectCards([TutorialGame.kingSpades])
          ..play()
          ..draw(fromDeck: true);
        game.dispose();
        async.elapse(TutorialGame.opponentPause * 3);
        expect(async.pendingTimers, isEmpty);
      });
    });
  });

  group('the first opening', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> relaunch(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await pumpSignedOut(
        tester,
        location: AppRoutes.home,
        offer: PreferencesTutorialOfferStore(),
      );
    }

    for (final start in [true, false]) {
      testWidgets('offers the example game once: after '
          '${start ? 'Start' : 'Later'}, a relaunch does not', (tester) async {
        await pumpSignedOut(
          tester,
          location: AppRoutes.home,
          offer: PreferencesTutorialOfferStore(),
        );
        expect(find.byKey(const Key('tutorial-offer')), findsOneWidget);
        expect(
          find.text("Apprendre avec une partie d'exemple ?"),
          findsOneWidget,
        );

        await tap(
          tester,
          find.byKey(
            Key(start ? 'tutorial-offer-start' : 'tutorial-offer-later'),
          ),
        );
        expect(find.byKey(const Key('tutorial-offer')), findsNothing);
        expect(
          find.byType(TutorialScreen),
          start ? findsOneWidget : findsNothing,
        );
        expect(
          (await SharedPreferences.getInstance()).getBool(
            PreferencesTutorialOfferStore.key,
          ),
          isTrue,
        );

        await relaunch(tester);
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byKey(const Key('tutorial-offer')), findsNothing);
      });
    }

    Future<bool?> flag() async => (await SharedPreferences.getInstance())
        .getBool(PreferencesTutorialOfferStore.key);

    // Every tester signed in before the update: the offer is marked made,
    // so a later sign-out does not bring it up either.
    testWidgets('a signed-in user is not offered it, and it is marked '
        'offered', (tester) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ZapZapApp(
          apiConfig: testConfig,
          locale: const Locale('fr'),
          initialLocation: AppRoutes.parties,
          apiClient: FakeLobbyBackend().client(),
          tokenStorage: storedSession(validToken),
          sseTransport: FakeSseTransport(),
          tutorialOffer: PreferencesTutorialOfferStore(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(find.byKey(const Key('tutorial-offer')), findsNothing);
      expect(await flag(), isTrue);
    });

    testWidgets('opening on /tutorial offers nothing over it, and marks it '
        'offered', (tester) async {
      await pumpSignedOut(tester, offer: PreferencesTutorialOfferStore());
      expect(find.byType(TutorialScreen), findsOneWidget);
      expect(find.byKey(const Key('tutorial-offer')), findsNothing);
      expect(await flag(), isTrue);
    });

    testWidgets('a store that cannot be read offers nothing, with no '
        'uncaught error', (tester) async {
      await pumpSignedOut(
        tester,
        location: AppRoutes.home,
        offer: _FailingStore(read: true),
      );
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const Key('tutorial-offer')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a store that cannot be written still takes the answer, '
        'with no uncaught error', (tester) async {
      final store = _FailingStore(write: true);
      await pumpSignedOut(tester, location: AppRoutes.home, offer: store);
      await tap(tester, find.byKey(const Key('tutorial-offer-later')));
      expect(find.byKey(const Key('tutorial-offer')), findsNothing);
      expect(store.writes, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the tutorial link is disabled while signing in, as the '
      'register link is', (tester) async {
    final answer = Completer<http.Response>();
    await pumpSignedOut(
      tester,
      location: AppRoutes.login,
      api: fakeApi((_) => answer.future),
    );
    TextButton link() => tester.widget<TextButton>(
      find.descendant(
        of: find.byKey(const Key('login-tutorial')),
        matching: find.byType(TextButton),
        matchRoot: true,
      ),
    );
    expect(link().onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('login-username')), 'Vincent');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    expect(link().onPressed, isNull);
    await tester.tap(find.byKey(const Key('login-tutorial')));
    await tester.pump();
    expect(find.byType(TutorialScreen), findsNothing);

    answer.complete(http.Response('{"error":"x"}', 500));
    await tester.pumpAndSettle();
    expect(link().onPressed, isNotNull);
  });

  group('signed in', () {
    for (final location in [AppRoutes.parties, AppRoutes.history]) {
      testWidgets('the ⋮ menu of $location opens the tutorial, and Skip '
          'returns', (tester) async {
        tester.view.physicalSize = const Size(400, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ZapZapApp(
            apiConfig: testConfig,
            locale: const Locale('fr'),
            initialLocation: location,
            apiClient: FakeLobbyBackend().client(),
            tokenStorage: storedSession(validToken),
            sseTransport: FakeSseTransport(),
          ),
        );
        await tester.pumpAndSettle();

        await tap(tester, find.byKey(const Key('app-bar-menu')));
        await tap(tester, find.byKey(const Key('menu-tutorial')));

        expect(find.byType(TutorialScreen), findsOneWidget);
        final router = GoRouter.of(tester.element(find.byType(TutorialScreen)));
        expect(router.state.uri.path, AppRoutes.tutorial);
        // The player's own name on the table, not the guest's.
        expect(find.text('Vincent'), findsWidgets);

        await tap(tester, find.byKey(const Key('tutorial-skip')));
        expect(find.byType(TutorialScreen), findsNothing);
        expect(
          GoRouter.of(tester.element(find.byType(Scaffold).first))
              .state
              .uri
              .path,
          location,
        );
        if (location == AppRoutes.parties) {
          expect(find.byType(PartiesScreen), findsOneWidget);
        }
      });
    }
  });
}

/// A store whose read, or write, fails as `shared_preferences` can.
class _FailingStore implements TutorialOfferStore {
  _FailingStore({this.read = false, this.write = false});

  final bool read;
  final bool write;
  int writes = 0;

  @override
  Future<bool> wasOffered() async {
    if (read) throw StateError('storage unavailable');
    return false;
  }

  @override
  Future<void> markOffered() async {
    writes++;
    if (write) throw StateError('storage unavailable');
  }
}
