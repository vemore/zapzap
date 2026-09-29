import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/widgets/game_round_end.dart';
import 'package:zapzap/widgets/victory_confetti.dart';

/// The winner's celebration on the game-over screen: confetti and a popping
/// banner for the winner alone, none with reduced motion.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool winnerIsMe,
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: GameRoundEnd(
              roundNumber: 3,
              players: const [
                RoundEndPlayer(
                  playerIndex: 0,
                  name: 'Vincent',
                  hand: [1, 2],
                  roundScore: 0,
                  totalScore: 40,
                  isMe: true,
                ),
              ],
              onNextRound: null,
              onBackToParties: () {},
              gameFinished: true,
              winnerName: 'Vincent',
              winnerScore: 40,
              winnerIsMe: winnerIsMe,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a win plays the confetti once, then paints nothing', (
    tester,
  ) async {
    await pump(tester, winnerIsMe: true);
    expect(find.byKey(const Key('victoryAnimation')), findsOneWidget);
    expect(find.byKey(const Key('winnerBanner')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(tester.takeException(), isNull);
    await tester.pump(VictoryConfetti.duration);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a loss has no animation', (tester) async {
    await pump(tester, winnerIsMe: false);
    expect(find.byKey(const Key('victoryAnimation')), findsNothing);
    expect(find.byKey(const Key('winnerBanner')), findsOneWidget);
  });

  testWidgets('reduced motion shows the banner without animation', (
    tester,
  ) async {
    await pump(tester, winnerIsMe: true, disableAnimations: true);
    expect(find.byKey(const Key('victoryAnimation')), findsNothing);
    expect(find.byKey(const Key('winnerBanner')), findsOneWidget);
    expect(find.byType(VictoryPop), findsNothing);
  });
}
