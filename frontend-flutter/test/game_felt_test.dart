// The casino felt of the game board: a radial green under a painted
// texture and the ZapZap watermark, in a dark wood rim — and the amber edge
// of the draw step still reads over that rim. The deck beside the pile:
// a card of the same size, labelled above as the pile is, over a stack.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/card_back.dart';
import 'package:zapzap/widgets/felt_painter.dart';
import 'package:zapzap/widgets/game_table_area.dart';
import 'package:zapzap/widgets/playing_card.dart';

void main() {
  Future<void> pumpFelt(
    WidgetTester tester, {
    required TableStep step,
    double textScale = 1,
    double cardWidth = CardSizes.tablePhone,
    int deckSize = 38,
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              height: 300,
              child: GameTableArea(
                cardsPlayed: const [34],
                lastCardsPlayed: const [17, 18, 19],
                playerName: (i) => 'Joueur $i',
                step: step,
                deckSize: deckSize,
                cardWidth: cardWidth,
                onDiscardTap: step == TableStep.draw ? (_) {} : null,
                onDeckTap: step == TableStep.draw ? () {} : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration decorationOf(WidgetTester tester, String key) =>
      tester.widget<Container>(find.byKey(Key(key))).decoration!
          as BoxDecoration;

  /// The WCAG contrast ratio of two colours.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  testWidgets('the felt is a radial green in a 6 px dark wood rim', (
    tester,
  ) async {
    await pumpFelt(tester, step: TableStep.play);

    final felt = decorationOf(tester, 'gameTable');
    expect(felt.gradient, isA<RadialGradient>());
    expect(felt.gradient!.colors, [AppColors.feltCenter, AppColors.feltEdge]);
    // Lit at the centre, dark at the edges.
    expect(
      AppColors.feltCenter.computeLuminance(),
      greaterThan(AppColors.feltEdge.computeLuminance()),
    );
    expect((felt.border! as Border).top.color, AppColors.rimInlay);

    final rim = decorationOf(tester, 'feltRim');
    expect(rim.gradient!.colors, [AppColors.rimLight, AppColors.rimDark]);
    expect(rim.boxShadow, isNotEmpty);
    final rimRect = tester.getRect(find.byKey(const Key('feltRim')));
    final feltRect = tester.getRect(find.byKey(const Key('gameTable')));
    expect(feltRect, rimRect.deflate(GameTableArea.rimWidth));
    expect(GameTableArea.rimWidth, 6);
  });

  testWidgets('the texture and the watermark are painted, no image', (
    tester,
  ) async {
    await pumpFelt(tester, step: TableStep.play);

    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const Key('gameTable')),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is FeltPainter,
        ),
      ),
    );
    expect((paint.painter! as FeltPainter).watermark, 'ZapZap');
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the painter repaints only when what it shows changes', (
    tester,
  ) async {
    const painter = FeltPainter(watermark: 'ZapZap', radius: 7);
    expect(
      painter.shouldRepaint(const FeltPainter(watermark: 'ZapZap', radius: 7)),
      isFalse,
    );
    expect(
      painter.shouldRepaint(const FeltPainter(watermark: 'ZapZap', radius: 6)),
      isTrue,
    );
  });

  testWidgets('during Piocher the amber edge lies on the rim and reads '
      'over it', (tester) async {
    await pumpFelt(tester, step: TableStep.draw);

    final edge = (decorationOf(tester, 'gameTable').border! as Border).top;
    expect(edge.color, GameTableArea.drawEdgeColor);
    expect(edge.width, 2);
    // The amber edge is the felt's outer line, right against the rim's
    // inner lip, and stands out from either end of the wood's gradient.
    for (final wood in [AppColors.rimLight, AppColors.rimDark]) {
      expect(contrast(GameTableArea.drawEdgeColor, wood), greaterThan(4.5));
    }
    // The rim glows amber too.
    final glow = decorationOf(tester, 'feltRim').boxShadow!.single;
    expect(glow.color.r, closeTo(GameTableArea.drawEdgeColor.r, 0.01));
    expect(glow.color.g, closeTo(GameTableArea.drawEdgeColor.g, 0.01));
  });

  for (final step in [TableStep.play, TableStep.draw]) {
    testWidgets('360x740 at a text scale of 1.5, ${step.name}: no overflow', (
      tester,
    ) async {
      await pumpFelt(tester, step: step, textScale: 1.5);
      expect(tester.takeException(), isNull);
    });
  }

  group('the deck', () {
    for (final width in [CardSizes.tablePhone, CardSizes.tableWide]) {
      testWidgets('at $width px: as big as a pile card, labelled above it, '
          'tops in line', (tester) async {
        await pumpFelt(
          tester,
          step: TableStep.draw,
          cardWidth: width,
          size: const Size(1280, 800),
        );
        final pileCard = tester.getRect(
          find.byKey(GameTableArea.discardKey(19)),
        );
        final deckCard = tester.getRect(find.byType(CardBack));
        expect(deckCard.size, pileCard.size);
        expect(deckCard.size, Size(width, PlayingCard.heightFor(width)));
        expect(deckCard.top, pileCard.top);

        final deckLabel = find.byKey(const Key('deckLabel'));
        final pileLabel = find.byKey(const Key('discardLabel'));
        expect(tester.getRect(deckLabel).bottom, lessThan(deckCard.top));
        expect(tester.getRect(deckLabel).top, tester.getRect(pileLabel).top);
        // The same style, as rendered: the button's text style is not
        // merged into the deck's label.
        TextStyle rendered(Finder text) =>
            tester.renderObject<RenderParagraph>(text).text.style!;
        expect(rendered(deckLabel), rendered(pileLabel));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a stack under the top card, thinner as the deck runs low', (
      tester,
    ) async {
      Future<int> layers(int deckSize) async {
        await pumpFelt(tester, step: TableStep.draw, deckSize: deckSize);
        return find
            .byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith('deckLayer'),
            )
            .evaluate()
            .length;
      }

      expect(await layers(38), 2);
      final top = tester.getRect(find.byType(CardBack));
      final under = tester.getRect(find.byKey(const Key('deckLayer2')));
      expect(under.topLeft - top.topLeft, const Offset(4, 4));
      // Inside the deck's own box, so inside the felt.
      final stack = tester.getRect(find.byKey(const Key('deckStack')));
      expect(
        stack.contains(under.bottomRight - const Offset(0.1, 0.1)),
        isTrue,
      );
      expect(await layers(5), 1);
      expect(await layers(1), 0);
    });

    testWidgets('its colours in either step; the edge of a target when '
        'drawable', (tester) async {
      Border? edge() =>
          (tester
                          .widget<Container>(find.byKey(const Key('deckTop')))
                          .foregroundDecoration
                      as BoxDecoration?)
                  ?.border
              as Border?;
      for (final step in [TableStep.play, TableStep.draw]) {
        await pumpFelt(tester, step: step);
        expect(find.byType(ColorFiltered), findsNothing);
        if (step == TableStep.draw) {
          expect(edge()!.top.color, AppColors.amber200);
          expect(edge()!.top.width, CardSizes.playableBorder);
        } else {
          expect(edge(), isNull);
        }
      }
    });
  });
}
