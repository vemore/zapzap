import { describe, it, expect } from 'vitest';
import { isValidPlay, getPlayType } from '../validation';

describe('Phase 4: Card Validation Tests (README compliance)', () => {
  describe('Single Cards (README line 335)', () => {
    it('should accept any single card', () => {
      expect(isValidPlay([0])).toBe(true); // A♠
      expect(isValidPlay([25])).toBe(true); // K♥
      expect(isValidPlay([52])).toBe(true); // Joker
    });

    it('should identify single card play type', () => {
      expect(getPlayType([0])).toBe('single');
      expect(getPlayType([52])).toBe('single');
    });
  });

  describe('Pairs - Same Rank (README line 338)', () => {
    it('should accept 2+ cards of same rank', () => {
      // Pair of Kings: K♠ K♥
      expect(isValidPlay([12, 25])).toBe(true);

      // Triple Aces: A♠ A♥ A♣
      expect(isValidPlay([0, 13, 26])).toBe(true);

      // Four of a kind: A♠ A♥ A♣ A♦
      expect(isValidPlay([0, 13, 26, 39])).toBe(true);
    });

    it('should accept pair with Joker (README line 342)', () => {
      // 6♠ 6♥ Joker (as third 6)
      expect(isValidPlay([5, 18, 52])).toBe(true);
    });

    it('should reject mixed ranks', () => {
      // A♠ K♥ (different ranks)
      expect(isValidPlay([0, 25])).toBe(false);

      // 5♠ 6♠ (different ranks)
      expect(isValidPlay([4, 5])).toBe(false);
    });

    it('should identify pair play type', () => {
      expect(getPlayType([12, 25])).toBe('pair');
      expect(getPlayType([0, 13, 26])).toBe('pair');
    });
  });

  describe('Sequences - Same Suit (README line 343)', () => {
    it('should accept 3+ consecutive cards of same suit', () => {
      // 5♠ 6♠ 7♠
      expect(isValidPlay([4, 5, 6])).toBe(true);

      // 10♣ J♣ Q♣ K♣
      expect(isValidPlay([35, 36, 37, 38])).toBe(true);

      // 2♥ 3♥ 4♥ 5♥ 6♥
      expect(isValidPlay([14, 15, 16, 17, 18])).toBe(true);
    });

    it('should accept sequence with Joker (README line 349)', () => {
      // 5♠ Joker 7♠ (Joker = 6♠)
      expect(isValidPlay([4, 52, 6])).toBe(true);

      // 10♣ J♣ Joker K♣ (Joker = Q♣)
      expect(isValidPlay([35, 36, 52, 38])).toBe(true);
    });

    it('should reject mixed suits (README line 356)', () => {
      // 5♠ 6♥ 7♣ (different suits)
      expect(isValidPlay([4, 18, 32])).toBe(false);
    });

    it('should reject non-consecutive (README line 359)', () => {
      // 5♠ 7♠ 9♠ (missing 6♠ and 8♠)
      expect(isValidPlay([4, 6, 8])).toBe(false);
    });

    it('should reject 2-card sequence (README line 362)', () => {
      // 5♠ 6♠ (need minimum 3)
      expect(isValidPlay([4, 5])).toBe(false);
    });

    it('should identify sequence play type', () => {
      expect(getPlayType([4, 5, 6])).toBe('sequence');
      expect(getPlayType([14, 15, 16, 17])).toBe('sequence');
    });
  });

  describe('Joker Wildcard Rules', () => {
    it('should accept Joker as wildcard in pairs', () => {
      // K♠ Joker (Joker as K)
      expect(isValidPlay([12, 52])).toBe(true);
    });

    it('should accept Joker as wildcard in sequences', () => {
      // A♠ 2♠ Joker 4♠ (Joker as 3♠)
      expect(isValidPlay([0, 1, 52, 3])).toBe(true);
    });

    it('should accept multiple Jokers', () => {
      // 5♠ Joker Joker 8♠ (Jokers as 6♠ 7♠)
      expect(isValidPlay([4, 52, 53, 7])).toBe(true);
    });

    it('should play single Joker as valid', () => {
      expect(isValidPlay([52])).toBe(true);
      expect(isValidPlay([53])).toBe(true);
    });
  });

  describe('Invalid Plays', () => {
    it('should reject empty array', () => {
      expect(isValidPlay([])).toBe(false);
    });

    it('should reject invalid card IDs', () => {
      expect(isValidPlay([54])).toBe(false); // Beyond valid range
      expect(isValidPlay([-1])).toBe(false); // Negative
    });

    it('should reject mixed play types', () => {
      // Can't mix pair and sequence logic
      // 5♠ 5♥ 6♠ (trying to be both pair and sequence)
      expect(isValidPlay([4, 17, 5])).toBe(false);
    });
  });

  describe('Edge Cases', () => {
    it('should handle Ace in sequences', () => {
      // A♠ 2♠ 3♠ (Ace low)
      expect(isValidPlay([0, 1, 2])).toBe(true);

      // Q♠ K♠ A♠ (Ace high) - depends on game rules
      // For now, rejecting wraparound
      expect(isValidPlay([11, 12, 0])).toBe(false);
    });

    it('should handle King at end of sequence', () => {
      // J♠ Q♠ K♠
      expect(isValidPlay([10, 11, 12])).toBe(true);
    });

    it('should validate all cards in same suit for sequences', () => {
      // 3♠ 4♠ 5♠ 6♥ (last card different suit)
      expect(isValidPlay([2, 3, 4, 18])).toBe(false);
    });
  });
});
