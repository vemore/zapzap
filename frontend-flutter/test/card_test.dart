// Ported from frontend/src/utils/__tests__/cards.test.js, checked against
// GAME_RULES.md (Card Values).
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/card.dart';

void main() {
  group('id mapping (0-53)', () {
    final cases = {
      Suit.spades: [0, 6, 12],
      Suit.hearts: [13, 19, 25],
      Suit.clubs: [26, 32, 38],
      Suit.diamonds: [39, 45, 51],
    };
    cases.forEach((suit, ids) {
      test('${suit.name}: ${ids.first}-${ids.last}', () {
        for (final id in ids) {
          expect(GameCard(id).suit, suit);
        }
        expect(GameCard(ids[0]).rankSymbol, 'A');
        expect(GameCard(ids[1]).rankSymbol, '7');
        expect(GameCard(ids[2]).rankSymbol, 'K');
      });
    });

    test('jokers are 52 and 53, with no suit or rank', () {
      expect(GameCard(52).isJoker, isTrue);
      expect(GameCard(53).isJoker, isTrue);
      expect(GameCard(0).isJoker, isFalse);
      expect(GameCard(51).isJoker, isFalse);
      expect(GameCard(52).suit, isNull);
      expect(GameCard(53).rank, 0);
      expect(GameCard(52).isRedJoker, isTrue);
      expect(GameCard(53).isRedJoker, isFalse);
    });

    test('ranks run Ace 1 to King 13 in every suit', () {
      for (var suit = 0; suit < 4; suit++) {
        for (var r = 0; r < 13; r++) {
          expect(GameCard(suit * 13 + r).rank, r + 1);
        }
      }
    });

    test('red cards are hearts, diamonds and the red joker', () {
      expect(GameCard(0).isRed, isFalse);
      expect(GameCard(13).isRed, isTrue);
      expect(GameCard(26).isRed, isFalse);
      expect(GameCard(39).isRed, isTrue);
      expect(GameCard(52).isRed, isTrue);
      expect(GameCard(53).isRed, isFalse);
    });

    test('valid ids are 0-53', () {
      expect(GameCard.isValidId(0), isTrue);
      expect(GameCard.isValidId(53), isTrue);
      expect(GameCard.isValidId(54), isFalse);
      expect(GameCard.isValidId(-1), isFalse);
    });
  });

  group('values (GAME_RULES.md, Card Values)', () {
    test('Ace is 1', () {
      for (final id in [0, 13, 26, 39]) {
        expect(GameCard(id).value(), 1);
      }
    });

    test('2-10 are their face value', () {
      expect(GameCard(1).value(), 2);
      expect(GameCard(4).value(), 5);
      expect(GameCard(9).value(), 10);
    });

    test('Jack 11, Queen 12, King 13', () {
      expect(GameCard(10).value(), 11);
      expect(GameCard(23).value(), 11);
      expect(GameCard(11).value(), 12);
      expect(GameCard(24).value(), 12);
      expect(GameCard(12).value(), 13);
      expect(GameCard(25).value(), 13);
    });

    test('Joker is 0 in play and 25 in penalty', () {
      for (final id in [52, 53]) {
        expect(GameCard(id).value(), 0);
        expect(GameCard(id).value(penalty: true), 25);
      }
    });

    test('penalty mode changes only jokers', () {
      for (var id = 0; id < 52; id++) {
        expect(GameCard(id).value(penalty: true), GameCard(id).value());
      }
    });
  });

  group('deck', () {
    test('54 cards: 13 per suit and 2 jokers', () {
      expect(GameCard.deck, hasLength(54));
      expect(GameCard.deck.first.id, 0);
      expect(GameCard.deck.last.id, 53);
      for (final suit in Suit.values) {
        expect(GameCard.deck.where((c) => c.suit == suit), hasLength(13));
      }
      expect(GameCard.deck.where((c) => c.isJoker), hasLength(2));
    });

    test('every card has its own face asset', () {
      final paths = GameCard.deck.map((c) => c.assetPath).toSet();
      expect(paths, hasLength(54));
      expect(GameCard(0).assetPath, 'assets/cards/ace_of_spades.svg');
      expect(GameCard(24).assetPath, 'assets/cards/queen_of_hearts.svg');
      expect(GameCard(35).assetPath, 'assets/cards/10_of_clubs.svg');
      expect(GameCard(52).assetPath, 'assets/cards/joker_red.svg');
      expect(GameCard(53).assetPath, 'assets/cards/joker_black.svg');
    });

    test('cards are equal by id', () {
      expect(const GameCard(5), const GameCard(5));
      expect(const GameCard(5).hashCode, const GameCard(5).hashCode);
      expect(const GameCard(5) == const GameCard(6), isFalse);
    });
  });
}
