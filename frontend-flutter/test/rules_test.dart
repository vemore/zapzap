// Ported from frontend/src/utils/__tests__/validation.test.js and
// scoring.test.js (the hand-value and eligibility cases), checked against
// GAME_RULES.md (Valid Card Combinations, ZapZap Eligibility).
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/utils/rules.dart';

void main() {
  group('single cards', () {
    test('any single card is valid, jokers included', () {
      expect(isValidPlay([0]), isTrue);
      expect(isValidPlay([25]), isTrue);
      expect(isValidPlay([52]), isTrue);
      expect(isValidPlay([53]), isTrue);
    });

    test('type is single', () {
      expect(playType([0]), PlayType.single);
      expect(playType([52]), PlayType.single);
    });
  });

  group('same rank', () {
    test('2 or more cards of one rank', () {
      expect(isValidPlay([12, 25]), isTrue); // K♠ K♥
      expect(isValidPlay([0, 13, 26]), isTrue); // A♠ A♥ A♣
      expect(isValidPlay([0, 13, 26, 39]), isTrue); // A♠ A♥ A♣ A♦
    });

    test('a joker as the third card (GAME_RULES.md: 6♠ 6♥ 🃏)', () {
      expect(isValidPlay([5, 18, 52]), isTrue);
    });

    test('a joker completes a pair (K♠ 🃏)', () {
      expect(isValidPlay([12, 52]), isTrue);
      expect(playType([12, 52]), PlayType.sameRank);
    });

    test('two jokers are a same-rank play, as the backend accepts', () {
      expect(playType([52, 53]), PlayType.sameRank);
    });

    test('mixed ranks are refused', () {
      expect(isValidPlay([0, 25]), isFalse); // A♠ K♥
      expect(isValidPlay([4, 5]), isFalse); // 5♠ 6♠
    });

    test('type is sameRank', () {
      expect(playType([12, 25]), PlayType.sameRank);
      expect(playType([0, 13, 26]), PlayType.sameRank);
    });
  });

  group('sequences', () {
    test('3 or more consecutive cards of one suit', () {
      expect(isValidPlay([4, 5, 6]), isTrue); // 5♠ 6♠ 7♠
      expect(isValidPlay([35, 36, 37, 38]), isTrue); // 10♣ J♣ Q♣ K♣
      expect(isValidPlay([14, 15, 16, 17, 18]), isTrue); // 2♥ .. 6♥
    });

    test('in any order', () {
      expect(isValidPlay([6, 4, 5]), isTrue);
    });

    test('jokers fill gaps (GAME_RULES.md: 5♠ 🃏 7♠, 10♣ J♣ 🃏 K♣)', () {
      expect(isValidPlay([4, 52, 6]), isTrue);
      expect(isValidPlay([35, 36, 52, 38]), isTrue);
      expect(isValidPlay([0, 1, 52, 3]), isTrue); // A♠ 2♠ 🃏 4♠
      expect(isValidPlay([4, 52, 53, 7]), isTrue); // 5♠ 🃏 🃏 8♠
    });

    test('a joker may extend a run at either end', () {
      expect(isValidPlay([4, 5, 52]), isTrue); // 5♠ 6♠ 🃏
      expect(isValidPlay([11, 12, 52]), isTrue); // Q♠ K♠ 🃏 = J Q K
      expect(isValidPlay([0, 1, 53]), isTrue); // A♠ 2♠ 🃏 = A 2 3
    });

    test('not enough jokers for the gaps', () {
      expect(isValidPlay([4, 52, 8]), isFalse); // 5♠ 🃏 9♠
      expect(analyzePlay([4, 52, 8]).error, PlayError.notConsecutive);
    });

    test('mixed suits are refused (5♠ 6♥ 7♣)', () {
      expect(isValidPlay([4, 18, 32]), isFalse);
      expect(analyzePlay([4, 18, 32]).error, PlayError.mixedSuits);
    });

    test('non-consecutive cards are refused (5♠ 7♠ 9♠)', () {
      expect(isValidPlay([4, 6, 8]), isFalse);
      expect(analyzePlay([4, 6, 8]).error, PlayError.notConsecutive);
    });

    test('two cards are not a sequence (5♠ 6♠)', () {
      expect(isValidPlay([4, 5]), isFalse);
      expect(analyzePlay([4, 5]).error, PlayError.sequenceTooShort);
    });

    test('type is sequence', () {
      expect(playType([4, 5, 6]), PlayType.sequence);
      expect(playType([14, 15, 16, 17]), PlayType.sequence);
    });

    test('Ace is low only: A♠ 2♠ 3♠ is valid, Q♠ K♠ A♠ is not', () {
      expect(isValidPlay([0, 1, 2]), isTrue);
      expect(isValidPlay([11, 12, 0]), isFalse);
      expect(isValidPlay([12, 0, 1]), isFalse); // K♠ A♠ 2♠
    });

    test('a King ends a sequence (J♠ Q♠ K♠)', () {
      expect(isValidPlay([10, 11, 12]), isTrue);
    });

    test('one card of another suit breaks it (3♠ 4♠ 5♠ 6♥)', () {
      expect(isValidPlay([2, 3, 4, 18]), isFalse);
    });

    test('a run cannot be longer than Ace to King', () {
      final allSpades = List.generate(13, (i) => i);
      expect(isValidPlay(allSpades), isTrue);
      expect(isValidPlay([...allSpades, 52]), isFalse);
    });
  });

  group('invalid plays', () {
    test('no card', () {
      expect(isValidPlay([]), isFalse);
      expect(analyzePlay([]).error, PlayError.empty);
    });

    test('ids outside 0-53', () {
      expect(isValidPlay([54]), isFalse);
      expect(isValidPlay([-1]), isFalse);
      expect(analyzePlay([54]).error, PlayError.unknownCard);
    });

    test('a card cannot be both a pair and a sequence (5♠ 5♥ 6♠)', () {
      expect(isValidPlay([4, 17, 5]), isFalse);
      expect(analyzePlay([4, 17, 5]).error, PlayError.mixedSuits);
    });

    test('the same card twice is refused', () {
      expect(analyzePlay([4, 4]).error, PlayError.duplicateCard);
      expect(analyzePlay([4, 4, 4]).error, PlayError.duplicateCard);
      expect(analyzePlay([52, 52]).error, PlayError.duplicateCard);
    });

    test('an invalid play has type invalid, a valid one no error', () {
      expect(analyzePlay([4, 6, 8]).type, PlayType.invalid);
      expect(analyzePlay([4, 5, 6]).error, isNull);
      expect(analyzePlay([4, 5, 6]).isValid, isTrue);
    });
  });

  group('hand value', () {
    test('Aces count 1 (A♠ 2♥ 3♣ = 6)', () {
      expect(handValue([0, 14, 28]), 6);
    });

    test('face cards (J♠ Q♥ K♣ = 36)', () {
      expect(handValue([10, 24, 38]), 36);
    });

    test('a joker is 0 in play and 25 in penalty (🃏 3♦ 2♠)', () {
      expect(handValue([52, 41, 1]), 5);
      expect(handValue([52, 41, 1], penalty: true), 30);
    });

    test('a mixed hand (A♠ 5♥ J♣ = 17)', () {
      expect(handValue([0, 17, 36]), 17);
    });

    test('an empty hand is 0', () {
      expect(handValue([]), 0);
    });

    test('display gives both values', () {
      final value = handValueDisplay([52, 13]); // 🃏 A♥
      expect(value.eligibility, 1);
      expect(value.penalty, 26);
    });
  });

  group('ZapZap eligibility (GAME_RULES.md table)', () {
    test('5 points or less', () {
      expect(isZapZapEligible([0, 14, 27]), isTrue); // A♠ 2♥ 2♣ = 5
      expect(isZapZapEligible([0, 13, 26, 39]), isTrue); // four Aces = 4
    });

    test('jokers count 0', () {
      expect(isZapZapEligible([52, 41, 1]), isTrue); // 🃏 3♦ 2♠ = 5
      expect(isZapZapEligible([0, 13, 26, 39, 52]), isTrue); // = 4
    });

    test('more than 5 points', () {
      expect(isZapZapEligible([2, 15]), isFalse); // 3♠ 3♥ = 6
      expect(isZapZapEligible([5]), isFalse); // 6♠
    });

    test('exactly 5 points', () {
      expect(isZapZapEligible([4]), isTrue); // 5♠
      expect(isZapZapEligible([0, 16]), isTrue); // A♠ 4♥
    });
  });

  group('the ZapZap gauge and the counteract penalty', () {
    test('the gauge is full at 5 or under, threshold / value above', () {
      expect(zapZapProgress(0), 1);
      expect(zapZapProgress(5), 1);
      expect(zapZapProgress(29), closeTo(5 / 29, 1e-9));
    });

    test('a joker is what makes the two values differ', () {
      expect(hasJoker([0, 52]), isTrue);
      expect(hasJoker([0, 13]), isFalse);
    });

    test('(active players − 1) × 5 (GAME_RULES.md, Final Scoring)', () {
      expect(counteractPenalty(4), 15);
      expect(counteractPenalty(3), 10);
      expect(counteractPenalty(2), 5);
      expect(counteractPenalty(1), 0);
    });
  });

  group('sorting', () {
    test('by suit then rank, jokers last', () {
      expect(sortCards([53, 13, 12, 0, 52, 40]), [0, 12, 13, 40, 52, 53]);
    });
  });
}
