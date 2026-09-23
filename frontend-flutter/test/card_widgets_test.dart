import 'dart:math' as math;

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

    testWidgets('a selected card glows amber', (tester) async {
      await tester.pumpWidget(
        _app(const PlayingCard(cardId: 0, selected: true)),
      );
      final shadow = _decoration(tester, find.byType(PlayingCard)).boxShadow!;
      expect(shadow.single.color, AppColors.amber400.withValues(alpha: 0.7));
      expect(shadow.single.blurRadius, 20);
      expect(shadow.single.spreadRadius, 8);
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

    /// The rotation of the card at [index], in degrees.
    double angleOf(WidgetTester tester, int index) {
      final m = tester.widget<Transform>(find.byKey(CardFan.itemKey(index)));
      final t = m.transform;
      return math.atan2(t.entry(1, 0), t.entry(0, 0)) * 180 / math.pi;
    }

    Finder cardAt(int index) => find.descendant(
      of: find.byKey(CardFan.itemKey(index)),
      matching: find.byType(PlayingCard),
    );

    testWidgets('renders nothing for an empty hand', (tester) async {
      await tester.pumpWidget(_app(const CardFan(cards: [])));
      expect(find.byType(PlayingCard), findsNothing);
    });

    testWidgets('desktop: 70 px cards on a 150 px fan, spread both ways', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const CardFan(cards: hand)));
      expect(find.byType(PlayingCard), findsNWidgets(5));
      expect(tester.getSize(find.byType(CardFan)).height, 150);
      final card = tester.widget<PlayingCard>(find.byType(PlayingCard).first);
      expect(card.width, 70);
      expect(angleOf(tester, 0), lessThan(0));
      expect(angleOf(tester, 2).abs(), lessThan(1e-9));
      expect(angleOf(tester, 4), greaterThan(0));
    });

    testWidgets('mobile (< 640 px): 50 px cards on a 100 px fan', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const CardFan(cards: hand), size: const Size(400, 800)),
      );
      expect(tester.getSize(find.byType(CardFan)).height, 100);
      final card = tester.widget<PlayingCard>(find.byType(PlayingCard).first);
      expect(card.width, 50);
    });

    testWidgets('a selected card is lifted, drawn on top and glows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(const CardFan(cards: hand, selectedCards: {26})),
      );
      final lifted = tester.getRect(cardAt(2));
      await tester.pumpWidget(_app(const CardFan(cards: hand)));
      final resting = tester.getRect(cardAt(2));
      expect(resting.top - lifted.top, closeTo(25, 0.01));

      await tester.pumpWidget(
        _app(const CardFan(cards: hand, selectedCards: {26})),
      );
      final stack = tester.widget<Stack>(
        find.descendant(of: find.byType(CardFan), matching: find.byType(Stack)),
      );
      expect(stack.children.last.key, CardFan.itemKey(2));
      final selected = tester.widget<PlayingCard>(cardAt(2));
      expect(selected.selected, isTrue);
    });

    testWidgets('a tap reports the card id; disabled reports nothing', (
      tester,
    ) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        _app(CardFan(cards: hand, onCardTap: tapped.add)),
      );
      await tester.tap(cardAt(4));
      expect(tapped, [52]);

      await tester.pumpWidget(
        _app(CardFan(cards: hand, onCardTap: tapped.add, disabled: true)),
      );
      await tester.tap(cardAt(4), warnIfMissed: false);
      expect(tapped, [52]);
    });

    testWidgets('the spread is capped at maxSpreadAngle', (tester) async {
      final many = List.generate(10, (i) => i);
      await tester.pumpWidget(_app(CardFan(cards: many)));
      // 10 × 12° > 75°, so the fan runs from -37.5° to +37.5°.
      expect(angleOf(tester, 0), closeTo(-37.5, 1e-6));
      expect(angleOf(tester, 9), closeTo(37.5, 1e-6));
    });
  });
}
