import { describe, it, expect } from 'vitest';
import {
  calculateHandValue,
  isZapZapEligible,
  calculateFinalScore,
  calculateCounteractPenalty,
} from '../scoring';

describe('Phase 4: Scoring System Tests (README compliance)', () => {
  describe('Hand Value Calculation', () => {
    it('should calculate hand with Aces as 1 point', () => {
      // A♠ 2♥ 3♣ = 1 + 2 + 3 = 6
      expect(calculateHandValue([0, 14, 28])).toBe(6);
    });

    it('should calculate hand with face cards', () => {
      // J♠ Q♥ K♣ = 11 + 12 + 13 = 36
      expect(calculateHandValue([10, 24, 38])).toBe(36);
    });

    it('should calculate hand with Joker as 0 for eligibility (README line 368)', () => {
      // Joker 3♦ 2♠ = 0 + 3 + 2 = 5
      expect(calculateHandValue([52, 41, 1], false)).toBe(5);
    });

    it('should calculate hand with Joker as 25 for penalty (README line 328)', () => {
      // Joker 3♦ 2♠ = 25 + 3 + 2 = 30
      expect(calculateHandValue([52, 41, 1], true)).toBe(30);
    });

    it('should handle mixed hand correctly', () => {
      // A♠ 5♥ J♣ = 1 + 5 + 11 = 17
      expect(calculateHandValue([0, 17, 36])).toBe(17);
    });
  });

  describe('ZapZap Eligibility (README line 368-376)', () => {
    it('should be eligible with hand value ≤5 points', () => {
      // A♠ 2♥ 2♣ = 1 + 2 + 2 = 5
      expect(isZapZapEligible([0, 14, 27])).toBe(true);

      // A♠ A♥ A♣ A♦ = 4 points
      expect(isZapZapEligible([0, 13, 26, 39])).toBe(true);
    });

    it('should be eligible with Joker (counted as 0)', () => {
      // Joker 3♦ 2♠ = 0 + 3 + 2 = 5
      expect(isZapZapEligible([52, 41, 1])).toBe(true);

      // A♠ A♥ A♣ A♦ Joker = 1+1+1+1+0 = 4
      expect(isZapZapEligible([0, 13, 26, 39, 52])).toBe(true);
    });

    it('should NOT be eligible with hand value >5', () => {
      // 3♠ 3♥ = 3 + 3 = 6
      expect(isZapZapEligible([2, 15])).toBe(false);

      // 6♠ = 6
      expect(isZapZapEligible([5])).toBe(false);
    });

    it('should be eligible at exactly 5 points', () => {
      // 5♠ = 5
      expect(isZapZapEligible([4])).toBe(true);

      // A♠ 4♥ = 1 + 4 = 5
      expect(isZapZapEligible([0, 16])).toBe(true);
    });
  });

  describe('Final Scoring (README line 379-391)', () => {
    it('should assign 0 points to lowest hand', () => {
      const hands = [
        { userId: '1', hand: [0, 14], value: 3 }, // A♠ 2♥ = 3
        { userId: '2', hand: [15, 28], value: 6 }, // 3♥ 3♣ = 6
        { userId: '3', hand: [10, 24], value: 23 }, // J♠ Q♥ = 23
      ];

      const scores = calculateFinalScore(hands, null);

      expect(scores['1']).toBe(0); // Lowest hand
      expect(scores['2']).toBe(6); // Sum of hand
      expect(scores['3']).toBe(23); // Sum of hand
    });

    it('should count Joker as 25 in final scoring', () => {
      const hands = [
        { userId: '1', hand: [0], value: 1 }, // A♠ = 1
        { userId: '2', hand: [52, 14], value: 27 }, // Joker 2♥ = 25 + 2 = 27
      ];

      const scores = calculateFinalScore(hands, null);

      expect(scores['1']).toBe(0); // Lowest
      expect(scores['2']).toBe(27); // Joker as 25 + 2
    });
  });

  describe('Counteract Penalty (README line 388)', () => {
    it('should calculate penalty as hand + (players × 5)', () => {
      // Player has 4 points, 5 players total
      // Penalty = 4 + (5 × 5) = 29
      expect(calculateCounteractPenalty(4, 5)).toBe(29);

      // Player has 5 points, 5 players total
      // Penalty = 5 + (5 × 5) = 30
      expect(calculateCounteractPenalty(5, 5)).toBe(30);
    });

    it('should apply penalty when ZapZap caller is counteracted', () => {
      const hands = [
        { userId: '1', hand: [0], value: 1 }, // A♠ = 1 (lower!)
        { userId: '2', hand: [0, 13], value: 2 }, // A♠ A♥ = 2 (ZapZap caller)
        { userId: '3', hand: [14, 15], value: 5 }, // 2♥ 3♥ = 5
      ];

      const scores = calculateFinalScore(hands, '2'); // Player 2 called ZapZap
      const numPlayers = 3;

      // Player 1 has lower hand (1 < 2), so Player 2 is counteracted
      // Player 2 penalty: 2 + (3 × 5) = 17
      expect(scores['2']).toBe(17);
      expect(scores['1']).toBe(0); // Lowest hand
      expect(scores['3']).toBe(5); // Normal score
    });

    it('should NOT apply penalty if ZapZap caller has lowest hand', () => {
      const hands = [
        { userId: '1', hand: [0], value: 1 }, // A♠ = 1 (ZapZap caller, lowest)
        { userId: '2', hand: [14, 15], value: 5 }, // 2♥ 3♥ = 5
        { userId: '3', hand: [10, 11], value: 23 }, // J♠ Q♠ = 23
      ];

      const scores = calculateFinalScore(hands, '1'); // Player 1 called ZapZap

      expect(scores['1']).toBe(0); // Successful ZapZap
      expect(scores['2']).toBe(5);
      expect(scores['3']).toBe(23);
    });
  });

  describe('Elimination (README line 417)', () => {
    it('should identify players above 100 points as eliminated', () => {
      const totalScores = {
        '1': 95,
        '2': 105, // Eliminated
        '3': 110, // Eliminated
        '4': 50,
      };

      const eliminated = Object.entries(totalScores)
        .filter(([_, score]) => score > 100)
        .map(([userId]) => userId);

      expect(eliminated).toContain('2');
      expect(eliminated).toContain('3');
      expect(eliminated).not.toContain('1');
      expect(eliminated).not.toContain('4');
    });
  });

  describe('Example from README (lines 393-413)', () => {
    it('should match the README scoring example', () => {
      // Game with 5 players
      // Final scoring uses Joker=25 for penalty calculation
      const hands = [
        { userId: '0', hand: [0, 14, 28], value: 6 }, // A♠ 2♥ 3♣ = 1 + 2 + 3 = 6
        { userId: '1', hand: [52, 13], value: 26 }, // Joker A♦ = 25 + 1 = 26 (penalty mode)
        { userId: '2', hand: [0, 26, 1], value: 4 }, // A♠ A♣ 2♠ = 1+1+2 = 4 (ZapZap caller, LOWEST)
        { userId: '3', hand: [12, 24], value: 25 }, // K♠ Q♥ = 13 + 12 = 25
        { userId: '4', hand: [17, 30], value: 10 }, // 5♥ 5♣ = 5 + 5 = 10
      ];

      const scores = calculateFinalScore(hands, '2'); // Player 2 called ZapZap

      // Player 2 has lowest hand (4 points) and called ZapZap → successful ZapZap
      expect(scores['2']).toBe(0); // Successful ZapZap (lowest hand)
      expect(scores['0']).toBe(6);
      expect(scores['4']).toBe(10);
      expect(scores['3']).toBe(25);
      expect(scores['1']).toBe(26);
    });
  });
});
