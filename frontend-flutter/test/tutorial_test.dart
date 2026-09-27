import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/providers/tutorial_game.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/home_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/screens/tutorial_screen.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/services/tutorial_offer_store.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/game_table_area.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

void main() {
  /// The app signed out on [location], on a 400x860 phone; every HTTP
  /// request lands in the list returned, and is refused.
  Future<List<http.Request>> pumpSignedOut(
    WidgetTester tester, {
    String location = AppRoutes.tutorial,
    Locale locale = const Locale('fr'),
    TutorialOfferStore? offer,
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
        apiClient: fakeApi(
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
    } else if (step.draws) {
      await tap(tester, find.byKey(const Key('draw-deck')));
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
