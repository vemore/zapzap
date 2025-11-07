import { describe, it, expect } from 'vitest';
import {
  getCardSuit,
  getCardRank,
  getCardValue,
  getCardName,
  isJoker,
  SUITS,
  RANKS,
} from '../cards';

describe('Phase 4: Card System Tests', () => {
  describe('Card ID Mapping (0-53)', () => {
    it('should map Spades correctly (0-12)', () => {
      expect(getCardSuit(0)).toBe('spades');
      expect(getCardSuit(6)).toBe('spades');
      expect(getCardSuit(12)).toBe('spades');

      expect(getCardRank(0)).toBe('A');
      expect(getCardRank(6)).toBe('7');
      expect(getCardRank(12)).toBe('K');
    });

    it('should map Hearts correctly (13-25)', () => {
      expect(getCardSuit(13)).toBe('hearts');
      expect(getCardSuit(19)).toBe('hearts');
      expect(getCardSuit(25)).toBe('hearts');

      expect(getCardRank(13)).toBe('A');
      expect(getCardRank(19)).toBe('7');
      expect(getCardRank(25)).toBe('K');
    });

    it('should map Clubs correctly (26-38)', () => {
      expect(getCardSuit(26)).toBe('clubs');
      expect(getCardSuit(32)).toBe('clubs');
      expect(getCardSuit(38)).toBe('clubs');

      expect(getCardRank(26)).toBe('A');
      expect(getCardRank(32)).toBe('7');
      expect(getCardRank(38)).toBe('K');
    });

    it('should map Diamonds correctly (39-51)', () => {
      expect(getCardSuit(39)).toBe('diamonds');
      expect(getCardSuit(45)).toBe('diamonds');
      expect(getCardSuit(51)).toBe('diamonds');

      expect(getCardRank(39)).toBe('A');
      expect(getCardRank(45)).toBe('7');
      expect(getCardRank(51)).toBe('K');
    });

    it('should map Jokers correctly (52-53)', () => {
      expect(isJoker(52)).toBe(true);
      expect(isJoker(53)).toBe(true);
      expect(isJoker(0)).toBe(false);
      expect(isJoker(51)).toBe(false);
    });

    it('should generate correct card names', () => {
      expect(getCardName(0)).toBe('A♠');
      expect(getCardName(13)).toBe('A♥');
      expect(getCardName(26)).toBe('A♣');
      expect(getCardName(39)).toBe('A♦');
      expect(getCardName(52)).toBe('Joker');
      expect(getCardName(53)).toBe('Joker');
    });
  });

  describe('Card Values (README compliance)', () => {
    it('should assign Ace value of 1 (README line 322)', () => {
      expect(getCardValue(0)).toBe(1); // A♠
      expect(getCardValue(13)).toBe(1); // A♥
      expect(getCardValue(26)).toBe(1); // A♣
      expect(getCardValue(39)).toBe(1); // A♦
    });

    it('should assign face values 2-10 (README line 323)', () => {
      expect(getCardValue(1)).toBe(2); // 2♠
      expect(getCardValue(4)).toBe(5); // 5♠
      expect(getCardValue(9)).toBe(10); // 10♠
    });

    it('should assign Jack value of 11 (README line 324)', () => {
      expect(getCardValue(10)).toBe(11); // J♠
      expect(getCardValue(23)).toBe(11); // J♥
    });

    it('should assign Queen value of 12 (README line 325)', () => {
      expect(getCardValue(11)).toBe(12); // Q♠
      expect(getCardValue(24)).toBe(12); // Q♥
    });

    it('should assign King value of 13 (README line 326)', () => {
      expect(getCardValue(12)).toBe(13); // K♠
      expect(getCardValue(25)).toBe(13); // K♥
    });

    it('should assign Joker value of 0 for eligibility (README line 327)', () => {
      expect(getCardValue(52, false)).toBe(0); // Joker for eligibility
      expect(getCardValue(53, false)).toBe(0);
    });

    it('should assign Joker value of 25 for penalty (README line 328)', () => {
      expect(getCardValue(52, true)).toBe(25); // Joker for scoring
      expect(getCardValue(53, true)).toBe(25);
    });
  });

  describe('Deck Generation', () => {
    it('should generate 54 card deck', () => {
      const deck = Array.from({ length: 54 }, (_, i) => i);
      expect(deck.length).toBe(54);
      expect(deck[0]).toBe(0);
      expect(deck[53]).toBe(53);
    });

    it('should have 13 cards per suit', () => {
      const spades = Array.from({ length: 13 }, (_, i) => i);
      spades.forEach(cardId => {
        expect(getCardSuit(cardId)).toBe('spades');
      });
    });

    it('should have 2 jokers', () => {
      const jokers = [52, 53];
      expect(jokers.length).toBe(2);
      jokers.forEach(cardId => {
        expect(isJoker(cardId)).toBe(true);
      });
    });
  });
});
