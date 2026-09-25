// The felt's action message: a card taken from the discard pile lay face up
// for every player, so the message names it and shows it small; a card drawn
// from the deck is hidden, and stays so even when the server names it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/game_state.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/playing_card.dart';

void main() {
  Future<void> pumpTable(
    WidgetTester tester,
    LastAction action, {
    String locale = 'fr',
    TableStep step = TableStep.play,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GameTableArea(
            cardsPlayed: const [],
            lastCardsPlayed: const [3],
            playerName: (i) => 'Joueur $i',
            step: step,
            deckSize: 30,
            lastAction: action,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String message(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('tableMessage'))).data!;

  testWidgets('a card taken from the discard is named and shown small', (
    tester,
  ) async {
    // 19 is the 7♥.
    await pumpTable(
      tester,
      const LastAction(
        type: 'draw',
        playerIndex: 1,
        source: 'played',
        cardId: 19,
      ),
    );

    expect(message(tester), 'Joueur 1 a pris dans la défausse : 7 de Cœur');
    final card = tester.widget<PlayingCard>(
      find.byKey(const Key('tableMessageCard')),
    );
    expect(card.cardId, 19);
    expect(card.width, GameTableArea.takenCardWidth);
    expect(card.disabled, isTrue);
  });

  testWidgets('in English, and a joker by its name', (tester) async {
    await pumpTable(
      tester,
      const LastAction(
        type: 'draw',
        playerIndex: 2,
        source: 'played',
        cardId: 53,
      ),
      locale: 'en',
    );

    expect(message(tester), startsWith('Joueur 2 took the '));
    expect(message(tester), endsWith(' joker from the discard pile'));
    expect(
      tester
          .widget<PlayingCard>(find.byKey(const Key('tableMessageCard')))
          .cardId,
      53,
    );
  });

  testWidgets('a deck draw names no card, even one the server sent', (
    tester,
  ) async {
    await pumpTable(
      tester,
      const LastAction(
        type: 'draw',
        playerIndex: 1,
        source: 'deck',
        cardId: 19,
      ),
    );

    expect(message(tester), 'Joueur 1 a pioché');
    expect(find.byKey(const Key('tableMessageCard')), findsNothing);
    expect(find.textContaining('Cœur'), findsNothing);
  });

  testWidgets('a discard take without its card keeps the plain message', (
    tester,
  ) async {
    await pumpTable(
      tester,
      const LastAction(type: 'draw', playerIndex: 1, source: 'played'),
    );

    expect(message(tester), 'Joueur 1 a pris une carte de la défausse');
    expect(find.byKey(const Key('tableMessageCard')), findsNothing);
  });

  testWidgets('no picture while this player draws: the hint takes the line', (
    tester,
  ) async {
    await pumpTable(
      tester,
      const LastAction(
        type: 'draw',
        playerIndex: 1,
        source: 'played',
        cardId: 19,
      ),
      step: TableStep.draw,
    );

    expect(find.byKey(const Key('tableMessage')), findsNothing);
    expect(find.byKey(const Key('tableMessageCard')), findsNothing);
  });
}
