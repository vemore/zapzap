import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/card.dart';
import 'package:zapzap/utils/app_theme.dart';
import 'package:zapzap/widgets/card_back.dart';
import 'package:zapzap/widgets/card_fan.dart';
import 'package:zapzap/widgets/playing_card.dart';

Widget _app(Widget child, {Size size = const Size(1024, 768)}) => MediaQuery(
  data: MediaQueryData(size: size),
  child: MaterialApp(
    locale: const Locale('fr'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  ),
);

BoxDecoration _decoration(WidgetTester tester, Finder card) {
  final box = tester.widget<AnimatedContainer>(
    find.descendant(of: card, matching: find.byType(AnimatedContainer)),
  );
  return box.decoration! as BoxDecoration;
}

void main() {
  group('card faces', () {
    testWidgets('every asset of the 54 ids loads and parses', (tester) async {
      await tester.runAsync(() async {
        for (final card in GameCard.deck) {
          final bytes = await SvgAssetLoader(card.assetPath).loadBytes(null);
          expect(bytes.lengthInBytes, greaterThan(0), reason: card.assetPath);
        }
      });
    });

    testWidgets('all 54 ids render without error', (tester) async {
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: Wrap(
              children: [
                for (final card in GameCard.deck)
                  PlayingCard(cardId: card.id, width: 40),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PlayingCard), findsNWidgets(54));
      expect(find.byType(SvgPicture), findsNWidgets(54));
    });
  });

  group('jokers', () {
    const jokers = [52, 53];

    test('share the faces\' 360 × 540 frame, with nothing flutter_svg '
        'might not draw', () async {
      for (final id in jokers) {
        final path = GameCard(id).assetPath;
        final svg = await rootBundle.loadString(path);
        expect(svg, contains('viewBox="0 0 360 540"'), reason: path);
        expect(
          svg,
          contains('<rect width="359" height="539" x=".5" y=".5" '),
          reason: '$path: the faces\' card outline',
        );
        for (final unsupported in ['<use', '<text', '<style', '<filter']) {
          expect(svg, isNot(contains(unsupported)), reason: path);
        }
      }
    });

    for (final width in [38.0, 80.0]) {
      testWidgets('red and black render beside a face at $width px', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final id in [12, ...jokers])
                  PlayingCard(cardId: id, width: width),
              ],
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final sizes = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .map((svg) => Size(svg.width!, svg.height!))
            .toSet();
        expect(sizes, {Size(width, PlayingCard.heightFor(width))});
      });
    }
  });

  group('PlayingCard', () {
    testWidgets('height is width × 1.4', (tester) async {
      await tester.pumpWidget(_app(const PlayingCard(cardId: 0, width: 50)));
      expect(
        tester.getSize(find.byType(AnimatedContainer)),
        const Size(50, 70),
      );
      expect(PlayingCard.heightFor(80), 112);
      expect(PlayingCard.radiusFor(20), 2);
      expect(PlayingCard.radiusFor(80), 4);
    });

    testWidgets('a selected card takes an amber edge and glows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const PlayingCard(cardId: 0, selected: true)),
      );
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PlayingCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      final edge = (box.foregroundDecoration! as BoxDecoration).border!;
      expect(edge.top.color, AppColors.amber400);
      expect(edge.top.width, CardSizes.selectedBorder);
      final shadow = _decoration(tester, find.byType(PlayingCard)).boxShadow!;
      expect(shadow.single.color, AppColors.amber400.withValues(alpha: 0.7));

      await tester.pumpWidget(_app(const PlayingCard(cardId: 0)));
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .foregroundDecoration,
        isNull,
      );
    });

    testWidgets('a screen reader selects the card as a tap does', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        _app(PlayingCard(cardId: 19, onTap: () => taps++)),
      );
      final card = find.bySemanticsLabel('7 de Cœur');
      expect(
        tester.getSemantics(card),
        matchesSemantics(
          label: '7 de Cœur',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('7 de Cœur'));
      expect(taps, 1);

      // Disabled, it offers no tap at all.
      await tester.pumpWidget(
        _app(PlayingCard(cardId: 19, disabled: true, onTap: () => taps++)),
      );
      expect(
        tester.getSemantics(card),
        matchesSemantics(
          label: '7 de Cœur',
          isButton: true,
          hasEnabledState: true,
          hasSelectedState: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('a tap calls onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(PlayingCard(cardId: 0, onTap: () => taps++)),
      );
      await tester.tap(find.byType(PlayingCard));
      expect(taps, 1);
    });

    testWidgets('a disabled card is half transparent and ignores taps', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(PlayingCard(cardId: 0, disabled: true, onTap: () => taps++)),
      );
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(PlayingCard),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.5);
      await tester.tap(find.byType(PlayingCard), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('screen readers get the localised card name', (tester) async {
      await tester.pumpWidget(
        _app(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayingCard(cardId: 0),
              PlayingCard(cardId: 24),
              PlayingCard(cardId: 52),
            ],
          ),
        ),
      );
      expect(find.bySemanticsLabel('A de Pique'), findsOneWidget);
      expect(find.bySemanticsLabel('Q de Cœur'), findsOneWidget);
      expect(find.bySemanticsLabel('Joker rouge'), findsOneWidget);
    });
  });

  group('CardBack', () {
    testWidgets('sizes follow CardBack.jsx', (tester) async {
      for (final size in CardBackSize.values) {
        await tester.pumpWidget(_app(CardBack(size: size)));
        expect(
          tester.getSize(find.byType(CardBack)),
          Size(size.width, PlayingCard.heightFor(size.width)),
        );
      }
      expect(CardBackSize.md.width, 60);
      expect(find.bySemanticsLabel('Carte face cachée'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CardFan', () {
    const hand = [0, 13, 26, 39, 52];

    Finder cardAt(int index) => find.descendant(
      of: find.byKey(CardFan.itemKey(index)),
      matching: find.byType(PlayingCard),
    );

    /// A fan in a box [width] wide, as the hand gives it.
    Widget fan(double width, CardFan child) =>
        _app(SizedBox(width: width, child: child));

    testWidgets('renders nothing for an empty hand', (tester) async {
      await tester.pumpWidget(_app(const CardFan(cards: [])));
      expect(find.byType(PlayingCard), findsNothing);
    });

    test('cards are a quarter of the width, from 76 to 96 px', () {
      expect(CardFan.layoutFor(5, 328).cardWidth, 82);
      expect(CardFan.layoutFor(5, 280).cardWidth, CardSizes.handMin);
      expect(CardFan.layoutFor(5, 900).cardWidth, CardSizes.handMax);
    });

    test('a hand that cannot leave 48 px of each card goes onto two rows, '
        'balanced', () {
      // 360 px phone: 328 px for the hand.
      expect(CardFan.layoutFor(6, 328).rowLengths, [6]);
      expect(CardFan.layoutFor(7, 328).rowLengths, [4, 3]);
      expect(CardFan.layoutFor(10, 328).rowLengths, [5, 5]);
      expect(CardFan.layoutFor(13, 328).rowLengths, [5, 4, 4]);
      for (final count in [1, 4, 5, 6, 7, 10, 13]) {
        for (final width in [300.0, 328.0, 358.0, 600.0]) {
          final fan = CardFan.layoutFor(count, width);
          for (var i = 0; i < count; i++) {
            final visible = fan.visibleRect(i);
            expect(
              visible.width,
              greaterThanOrEqualTo(CardSizes.handMinVisible),
              reason: '$count cards on $width px, card $i',
            );
            expect(
              visible.height,
              greaterThanOrEqualTo(CardSizes.handMinVisible),
            );
            expect(fan.cardRect(i).left, greaterThanOrEqualTo(0));
            expect(fan.cardRect(i).right, lessThanOrEqualTo(width + 0.01));
          }
        }
      }
    });

    test(
      'a compact fan is one row of small cards, with no room for a lift',
      () {
        for (final count in [1, 4, 7, 10]) {
          for (final width in [300.0, 328.0, 358.0]) {
            final fan = CardFan.layoutFor(count, width, compact: true);
            expect(fan.rowLengths, [count]);
            expect(fan.cardWidth, CardSizes.handCompact);
            expect(fan.height, fan.cardHeight);
            for (var i = 0; i < count; i++) {
              expect(fan.cardRect(i).top, 0);
              // The rank and suit corner, a sixth of the width, stays in view.
              expect(
                fan.visibleRect(i).width,
                greaterThanOrEqualTo(fan.cardWidth / 2),
              );
              expect(fan.cardRect(i).right, lessThanOrEqualTo(width + 0.01));
            }
          }
        }
      },
    );

    testWidgets('each card takes a tap at the centre of its visible part', (
      tester,
    ) async {
      const seven = [0, 13, 26, 40, 51, 6, 19];
      final tapped = <int>[];
      await tester.pumpWidget(
        fan(328, CardFan(cards: seven, onCardTap: tapped.add)),
      );
      final layout = CardFan.layoutFor(seven.length, 328);
      final origin = tester.getTopLeft(find.byType(CardFan));
      for (var i = 0; i < seven.length; i++) {
        expect(tester.getSize(cardAt(i)).width, greaterThanOrEqualTo(76));
        await tester.tapAt(origin + layout.visibleRect(i).center);
      }
      expect(tapped, seven);
    });

    testWidgets('a selected card rises 20 px and keeps its place', (
      tester,
    ) async {
      await tester.pumpWidget(fan(328, const CardFan(cards: hand)));
      final resting = tester.getRect(cardAt(2));
      await tester.pumpWidget(
        fan(328, const CardFan(cards: hand, selectedCards: {26})),
      );
      final lifted = tester.getRect(cardAt(2));
      expect(resting.top - lifted.top, CardSizes.selectedLift);
      expect(lifted.left, resting.left);

      // Still under the card after it: that one's visible part stays whole.
      final stack = tester.widget<Stack>(
        find.descendant(of: find.byType(CardFan), matching: find.byType(Stack)),
      );
      expect(stack.children[2].key, CardFan.itemKey(2));
      expect(tester.widget<PlayingCard>(cardAt(2)).selected, isTrue);
    });

    testWidgets('a tap reports the card id; disabled reports nothing', (
      tester,
    ) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        fan(328, CardFan(cards: hand, onCardTap: tapped.add)),
      );
      await tester.tap(cardAt(4));
      expect(tapped, [52]);

      await tester.pumpWidget(
        fan(328, CardFan(cards: hand, onCardTap: tapped.add, disabled: true)),
      );
      await tester.tap(cardAt(4), warnIfMissed: false);
      expect(tapped, [52]);
    });
  });
}
