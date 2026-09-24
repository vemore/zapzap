import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/utils/card_l10n.dart';
import 'package:zapzap/utils/rules.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/game_hand.dart';
import 'package:zapzap/widgets/hand_suggestions.dart';

// J8: the chips above the hand. Card ids: spades 0-12, hearts 13-25, clubs
// 26-38, diamonds 39-51, Ace to King; 52 and 53 the jokers.

/// A hand whose selection lives here, as it lives in `GameProvider`: a card
/// tap toggles, a chip replaces the selection.
class _Board extends StatefulWidget {
  const _Board({
    required this.cards,
    this.disabled = false,
    this.compact = false,
  });

  final List<int> cards;
  final bool disabled;
  final bool compact;

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board> {
  final selected = <int>[];

  @override
  Widget build(BuildContext context) => GameHand(
    cards: widget.cards,
    selectedCards: selected,
    eligibilityValue: handValue(widget.cards),
    penaltyValue: handValue(widget.cards, penalty: true),
    disabled: widget.disabled,
    compact: widget.compact,
    onCardTap: (id) => setState(() {
      if (!selected.remove(id)) selected.add(id);
    }),
    onSelectCards: (cards) => setState(() {
      selected
        ..clear()
        ..addAll(cards);
    }),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget board, {
  String locale = 'fr',
  Size size = const Size(360, 740),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: board,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<int> _selection(WidgetTester tester) =>
    tester.widget<GameHand>(find.byType(GameHand)).selectedCards;

void main() {
  // The mockup's hand: A♠ 2♥ 7♣ 7♦ Q♠ 🃏.
  const mockupHand = [0, 14, 32, 45, 11, 52];

  testWidgets('the chips read the mockup: the pair of 7, the Queen alone', (
    tester,
  ) async {
    await _pump(tester, const _Board(cards: mockupHand));

    expect(find.text('Paire de 7 · −14'), findsOneWidget);
    expect(find.text('Q♠ seule · −12'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const Key('handSuggestions'))).bottom,
      lessThan(tester.getRect(find.byType(CardFan)).top),
      reason: 'the chips sit above the cards',
    );
  });

  testWidgets('a chip selects its cards; a card tap then deselects one', (
    tester,
  ) async {
    await _pump(tester, const _Board(cards: mockupHand));

    await tester.tap(find.byKey(HandSuggestions.chipKey(0)));
    await tester.pumpAndSettle();
    expect(_selection(tester), [32, 45]);
    expect(
      tester.getSemantics(find.byKey(HandSuggestions.chipKey(0))),
      isSemantics(
        isButton: true,
        isSelected: true,
        hasTapAction: true,
        label: 'Paire de 7 · −14',
      ),
    );

    // 7♦ is the fourth card of the hand.
    await tester.tap(find.byKey(CardFan.itemKey(mockupHand.indexOf(45))));
    await tester.pumpAndSettle();
    expect(_selection(tester), [32]);
    expect(
      tester.getSemantics(find.byKey(HandSuggestions.chipKey(0))),
      isSemantics(isSelected: false),
      reason: 'the selection is no longer the pair',
    );

    // Another chip replaces the selection.
    await tester.tap(find.byKey(HandSuggestions.chipKey(1)));
    await tester.pumpAndSettle();
    expect(_selection(tester), [11]);
  });

  testWidgets('a run with a joker is offered, and named with it', (
    tester,
  ) async {
    // 4♥ 6♥ 🃏 2♠.
    await _pump(tester, const _Board(cards: [16, 18, 52, 1]));

    expect(find.text('Suite 4–6♥ avec joker · −10'), findsOneWidget);
    await tester.tap(find.byKey(HandSuggestions.chipKey(0)));
    await tester.pumpAndSettle();
    expect(_selection(tester), [16, 52, 18]);
  });

  testWidgets('no chip while the hand cannot be played, nor in compact', (
    tester,
  ) async {
    await _pump(tester, const _Board(cards: mockupHand, disabled: true));
    expect(find.byType(HandSuggestions), findsNothing);

    await _pump(tester, const _Board(cards: mockupHand, compact: true));
    expect(find.byType(HandSuggestions), findsNothing);

    await _pump(tester, const _Board(cards: [52, 53]));
    expect(find.byType(HandSuggestions), findsNothing);
  });

  test('the labels, both locales', () {
    final fr = lookupAppLocalizations(const Locale('fr'));
    final en = lookupAppLocalizations(const Locale('en'));
    // 5♠ 6♠ 🃏: the joker stands for 7♠.
    final run = PlaySuggestion([4, 5, 52]);
    expect(fr.suggestionLabel(run), 'Suite 5–7♠ avec joker · −11');
    expect(en.suggestionLabel(run), 'Run 5–7♠ with joker · −11');
    // 🃏 J♥ Q♥: a joker at the low end stands for 10♥.
    expect(
      fr.suggestionLabel(PlaySuggestion([52, 23, 24])),
      'Suite 10–Q♥ avec joker · −23',
    );
    expect(
      fr.suggestionLabel(PlaySuggestion([2, 52, 4, 53, 6])),
      'Suite 3–7♠ avec 2 jokers · −15',
    );
    expect(en.suggestionLabel(PlaySuggestion([0, 13, 26])), '3 × A · −3');
    expect(en.suggestionLabel(PlaySuggestion([12, 25])), 'Pair of K · −26');
    expect(en.suggestionLabel(PlaySuggestion([11])), 'Q♠ alone · −12');
  });

  for (final locale in ['fr', 'en']) {
    testWidgets('fits 360×740 at text scale 1.5 ($locale)', (tester) async {
      // Ten cards and three long chips: two runs with jokers, a pair.
      await _pump(
        tester,
        const _Board(cards: [2, 4, 6, 52, 53, 16, 18, 20, 12, 25]),
        locale: locale,
        textScale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(HandSuggestions), findsOneWidget);
      // One line, scrolled sideways to reach a chip it cannot show.
      final screen = Offset.zero & const Size(360, 740);
      final first = tester.getRect(find.byKey(HandSuggestions.chipKey(0)));
      for (var i = 0; i < maxSuggestions; i++) {
        final chip = find.byKey(HandSuggestions.chipKey(i));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        final rect = tester.getRect(chip);
        expect(rect.top, first.top, reason: 'chip $i on the first line');
        expect(screen.contains(rect.topLeft), isTrue);
        expect(rect.right, lessThanOrEqualTo(360));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
