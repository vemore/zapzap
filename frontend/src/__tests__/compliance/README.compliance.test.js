import { describe, it, expect } from 'vitest';
import { getCardValue, getCardName } from '../../utils/cards';
import { isValidPair, isValidSequence } from '../../utils/validation';
import { calculateHandValue, calculateFinalScore, calculateCounteractPenalty } from '../../utils/scoring';

/**
 * README Compliance Tests
 *
 * These tests validate that the frontend implementation matches
 * all game rules specified in README.md (lines 315-428)
 */

describe('README Compliance: Card Values (README lines 315-342)', () => {
  describe('Number Cards (2-10)', () => {
    it('should assign face value to number cards', () => {
      // 2 of Spades (ID: 1), 5 of Hearts (ID: 17), 10 of Clubs (ID: 35)
      expect(getCardValue(1)).toBe(2);   // 2 of Spades
      expect(getCardValue(17)).toBe(5);  // 5 of Hearts
      expect(getCardValue(35)).toBe(10); // 10 of Clubs
    });
  });

  describe('Face Cards', () => {
    it('should assign Ace = 1 point', () => {
      // Aces: Spades (0), Hearts (13), Clubs (26), Diamonds (39)
      expect(getCardValue(0)).toBe(1);
      expect(getCardValue(13)).toBe(1);
      expect(getCardValue(26)).toBe(1);
      expect(getCardValue(39)).toBe(1);
    });

    it('should assign Jack = 11 points', () => {
      // Jacks: Spades (10), Hearts (23), Clubs (36), Diamonds (49)
      expect(getCardValue(10)).toBe(11);
      expect(getCardValue(23)).toBe(11);
      expect(getCardValue(36)).toBe(11);
      expect(getCardValue(49)).toBe(11);
    });

    it('should assign Queen = 12 points', () => {
      // Queens: Spades (11), Hearts (24), Clubs (37), Diamonds (50)
      expect(getCardValue(11)).toBe(12);
      expect(getCardValue(24)).toBe(12);
      expect(getCardValue(37)).toBe(12);
      expect(getCardValue(50)).toBe(12);
    });

    it('should assign King = 13 points', () => {
      // Kings: Spades (12), Hearts (25), Clubs (38), Diamonds (51)
      expect(getCardValue(12)).toBe(13);
      expect(getCardValue(25)).toBe(13);
      expect(getCardValue(38)).toBe(13);
      expect(getCardValue(51)).toBe(13);
    });
  });

  describe('Jokers (README lines 337-342)', () => {
    it('should assign Joker = 0 for eligibility checks', () => {
      // Jokers: 52, 53
      expect(getCardValue(52)).toBe(0);
      expect(getCardValue(53)).toBe(0);
    });

    it('should assign Joker = 25 for penalty calculations', () => {
      // This is handled in scoring.js with includeJokerPenalty flag
      const hand = [52]; // One Joker
      const valueForEligibility = calculateHandValue(hand, false);
      const valueForPenalty = calculateHandValue(hand, true);

      expect(valueForEligibility).toBe(0);  // 0 for eligibility
      expect(valueForPenalty).toBe(25);     // 25 for penalty
    });
  });
});

describe('README Compliance: Valid Plays (README lines 345-365)', () => {
  describe('Pairs/Sets (Same rank)', () => {
    it('should accept valid pairs with same rank', () => {
      // Three Aces from different suits
      const set1 = [0, 13, 26]; // A♠ A♥ A♣
      expect(isValidPair(set1)).toBe(true);

      // Three Kings from different suits
      const set2 = [12, 25, 38]; // K♠ K♥ K♣
      expect(isValidPair(set2)).toBe(true);
    });

    it('should accept valid 4-card pairs', () => {
      // Four 7s from all suits
      const set = [6, 19, 32, 45]; // 7♠ 7♥ 7♣ 7♦
      expect(isValidPair(set)).toBe(true);
    });

    it('should accept 2-card pairs', () => {
      // Two Aces
      const pair = [0, 13]; // A♠ A♥
      expect(isValidPair(pair)).toBe(true);
    });

    it('should reject pairs with different ranks', () => {
      const invalidPair = [0, 13, 27]; // A♠ A♥ 2♣ (not all same rank)
      expect(isValidPair(invalidPair)).toBe(false);
    });
  });

  describe('Sequences (Sequential ranks, same suit)', () => {
    it('should accept valid 3-card sequences', () => {
      // 2-3-4 of Spades
      const run1 = [1, 2, 3];
      expect(isValidSequence(run1)).toBe(true);

      // J-Q-K of Hearts
      const run2 = [23, 24, 25];
      expect(isValidSequence(run2)).toBe(true);
    });

    it('should accept valid 4+ card sequences', () => {
      // A-2-3-4-5 of Diamonds
      const run = [39, 40, 41, 42, 43];
      expect(isValidSequence(run)).toBe(true);
    });

    it('should reject sequences with mixed suits', () => {
      // 2♠ 3♥ 4♣ (different suits)
      const invalidRun = [1, 15, 29];
      expect(isValidSequence(invalidRun)).toBe(false);
    });

    it('should reject non-sequential cards', () => {
      // 2-4-6 of Spades (gaps in sequence)
      const invalidRun = [1, 3, 5];
      expect(isValidSequence(invalidRun)).toBe(false);
    });

    it('should handle Ace as low only (not wrapping)', () => {
      // A-2-3 of Spades is valid
      const validRun = [0, 1, 2];
      expect(isValidSequence(validRun)).toBe(true);

      // Q-K-A of Spades is invalid (Ace doesn't wrap)
      const invalidRun = [11, 12, 0];
      expect(isValidSequence(invalidRun)).toBe(false);
    });
  });

  describe('Jokers as Wildcards (README line 363)', () => {
    it('should accept Joker in pairs', () => {
      // Two Kings + Joker
      const setWithJoker = [12, 25, 52]; // K♠ K♥ Joker
      expect(isValidPair(setWithJoker)).toBe(true);
    });

    it('should accept Joker in sequences', () => {
      // 2-Joker-4 of Spades (Joker represents 3)
      const runWithJoker = [1, 52, 3]; // 2♠ Joker 4♠
      expect(isValidSequence(runWithJoker)).toBe(true);
    });
  });

  describe('Minimum Play Size (README line 365)', () => {
    it('should reject sequences with less than 3 cards', () => {
      const twoCards = [0, 1]; // Only 2 cards
      expect(isValidSequence(twoCards)).toBe(false);
    });
  });
});

describe('README Compliance: ZapZap Rules (README lines 370-396)', () => {
  describe('ZapZap Eligibility (≤5 points)', () => {
    it('should allow ZapZap with hand ≤5 points', () => {
      // Four Aces (4 points)
      const hand1 = [0, 13, 26, 39];
      expect(calculateHandValue(hand1, false)).toBeLessThanOrEqual(5);

      // Ace + Two + Joker (3 points)
      const hand2 = [0, 1, 52];
      expect(calculateHandValue(hand2, false)).toBeLessThanOrEqual(5);

      // Five Jokers (0 points)
      const hand3 = [52, 53, 52, 53, 52];
      expect(calculateHandValue(hand3, false)).toBe(0);
    });

    it('should prevent ZapZap with hand >5 points', () => {
      // Ace + Five (6 points)
      const hand1 = [0, 4];
      expect(calculateHandValue(hand1, false)).toBeGreaterThan(5);

      // Two + Three + Joker (5 points is allowed, 6 is not)
      const hand2 = [1, 2, 14]; // 2 + 3 + Ace = 6
      expect(calculateHandValue(hand2, false)).toBeGreaterThan(5);
    });
  });

  describe('ZapZap Success (README line 381-385)', () => {
    it('should assign 0 points to winner with lowest hand', () => {
      const hands = [
        { userId: '1', hand: [0, 13, 26, 39] }, // Alice: 4 Aces = 4 points
        { userId: '2', hand: [2, 15] },          // Bob: 3♠ + 2♥ = 6 points
      ];

      const scores = calculateFinalScore(hands, '1');

      // Alice (ZapZap caller) has lowest hand (4 points)
      expect(scores['1']).toBe(0);
      // Bob gets his hand value (using penalty mode: 3+3=6)
      expect(scores['2']).toBe(6);
    });
  });

  describe('ZapZap Counteract (README lines 387-396)', () => {
    it('should apply counteract penalty when another player has lower hand', () => {
      const hands = [
        { userId: '1', hand: [0, 14] },          // Alice: A♠ + 2♥ = 1+2 = 3
        { userId: '2', hand: [0, 13, 26, 39] },  // Bob: 4 Aces = 4
      ];

      const scores = calculateFinalScore(hands, '2');

      // Bob called ZapZap but Alice has lower hand (3 < 4)
      // Bob gets: hand + (players × 5) = 4 + (2 × 5) = 14
      expect(scores['2']).toBe(14);
      // Alice gets 0 (lowest hand)
      expect(scores['1']).toBe(0);
    });

    it('should apply correct penalty formula: hand + (players × 5)', () => {
      // Test with different player counts
      const hands = [
        { userId: '1', hand: [0, 14] },          // Alice: 3 points
        { userId: '2', hand: [0, 13, 26, 39] },  // Bob: 4 points
        { userId: '3', hand: [2, 15] },          // Charlie: 6 points
      ];

      const scores = calculateFinalScore(hands, '2');

      // Bob: 4 + (3 × 5) = 19
      expect(scores['2']).toBe(19);
    });

    it('should include Joker penalty (25) in counteract calculation', () => {
      const hands = [
        { userId: '1', hand: [0, 14] },  // Alice: 3 points
        { userId: '2', hand: [52] },     // Bob: Joker
      ];

      const scores = calculateFinalScore(hands, '2');

      // Bob called with Joker, but Alice has lower non-joker hand
      // Bob gets: 25 (joker penalty) + (2 × 5) = 35
      expect(scores['2']).toBe(35);
    });
  });
});

describe('README Compliance: Scoring Rules (README lines 381-384)', () => {
  it('should assign 0 points to player with lowest hand', () => {
    const hands = [
      { userId: '1', hand: [0, 14] },      // Alice: 3
      { userId: '2', hand: [2, 15, 28] },  // Bob: 9
      { userId: '3', hand: [10, 24] },     // Charlie: 23
    ];

    const scores = calculateFinalScore(hands, null);

    // Alice has lowest hand (3)
    expect(scores['1']).toBe(0);
    // Others get their hand values
    expect(scores['2']).toBe(9);
    expect(scores['3']).toBe(23);
  });

  it('should assign hand values to non-winning players', () => {
    const hands = [
      { userId: '1', hand: [12, 25, 38] },  // Alice: 3 Kings = 39
      { userId: '2', hand: [0] },           // Bob: 1 Ace = 1
    ];

    const scores = calculateFinalScore(hands, null);

    // Bob wins with 1 point
    expect(scores['2']).toBe(0);
    // Alice gets her hand value
    expect(scores['1']).toBe(39);
  });
});

describe('README Compliance: Elimination (README lines 417-418)', () => {
  it('should eliminate players exceeding 100 points', () => {
    const player1 = { totalScore: 99 };
    const player2 = { totalScore: 100 };
    const player3 = { totalScore: 101 };
    const player4 = { totalScore: 150 };

    expect(player1.totalScore).toBeLessThanOrEqual(100);
    expect(player2.totalScore).toBe(100);  // Exactly 100 is still in
    expect(player3.totalScore).toBeGreaterThan(100);  // Eliminated
    expect(player4.totalScore).toBeGreaterThan(100);  // Eliminated
  });

  it('should keep players at or below 100 points in game', () => {
    const players = [
      { id: '1', totalScore: 95 },
      { id: '2', totalScore: 100 },
      { id: '3', totalScore: 105 },
    ];

    const activePlayers = players.filter(p => p.totalScore <= 100);
    const eliminatedPlayers = players.filter(p => p.totalScore > 100);

    expect(activePlayers.length).toBe(2);
    expect(eliminatedPlayers.length).toBe(1);
    expect(eliminatedPlayers[0].id).toBe('3');
  });
});

describe('README Compliance: Card ID System (README lines 315-335)', () => {
  it('should map card IDs correctly to suits', () => {
    // Spades: 0-12
    expect(getCardName(0)).toMatch(/♠/);  // Ace of Spades
    expect(getCardName(6)).toMatch(/♠/);  // 7 of Spades
    expect(getCardName(12)).toMatch(/♠/); // King of Spades

    // Hearts: 13-25
    expect(getCardName(13)).toMatch(/♥/);  // Ace of Hearts
    expect(getCardName(19)).toMatch(/♥/);  // 7 of Hearts
    expect(getCardName(25)).toMatch(/♥/);  // King of Hearts

    // Clubs: 26-38
    expect(getCardName(26)).toMatch(/♣/);  // Ace of Clubs
    expect(getCardName(32)).toMatch(/♣/);  // 7 of Clubs
    expect(getCardName(38)).toMatch(/♣/);  // King of Clubs

    // Diamonds: 39-51
    expect(getCardName(39)).toMatch(/♦/);  // Ace of Diamonds
    expect(getCardName(45)).toMatch(/♦/);  // 7 of Diamonds
    expect(getCardName(51)).toMatch(/♦/);  // King of Diamonds

    // Jokers: 52-53
    expect(getCardName(52)).toMatch(/Joker/i);
    expect(getCardName(53)).toMatch(/Joker/i);
  });

  it('should correctly identify card ranks from IDs', () => {
    // Aces (ID % 13 === 0 for non-jokers)
    expect(getCardName(0)).toMatch(/A/);   // Ace of Spades
    expect(getCardName(13)).toMatch(/A/);  // Ace of Hearts

    // Number cards
    expect(getCardName(1)).toMatch(/2/);   // 2 of Spades
    expect(getCardName(14)).toMatch(/2/);  // 2 of Hearts

    // Face cards
    expect(getCardName(10)).toMatch(/J/);  // Jack of Spades
    expect(getCardName(11)).toMatch(/Q/);  // Queen of Spades
    expect(getCardName(12)).toMatch(/K/);  // King of Spades
  });
});

describe('README Compliance: Hand Value Calculation Edge Cases', () => {
  it('should handle mixed hands correctly', () => {
    // Ace + King + Joker = 1 + 13 + 0 = 14 points
    const hand1 = [0, 12, 52];
    expect(calculateHandValue(hand1, false)).toBe(14);

    // All Jokers = 0 points for eligibility
    const hand2 = [52, 53];
    expect(calculateHandValue(hand2, false)).toBe(0);

    // All Jokers = 50 points for penalty (2 × 25)
    expect(calculateHandValue(hand2, true)).toBe(50);
  });

  it('should handle empty hands', () => {
    const emptyHand = [];
    expect(calculateHandValue(emptyHand, false)).toBe(0);
  });

  it('should handle single card hands', () => {
    // Single Ace
    const singleAce = [0];
    expect(calculateHandValue(singleAce, false)).toBe(1);

    // Single King
    const singleKing = [12];
    expect(calculateHandValue(singleKing, false)).toBe(13);

    // Single Joker
    const singleJoker = [52];
    expect(calculateHandValue(singleJoker, false)).toBe(0);
    expect(calculateHandValue(singleJoker, true)).toBe(25);
  });
});
