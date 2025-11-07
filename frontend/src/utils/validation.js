import { getCardSuit, getCardRankValue, isJoker } from './cards';

/**
 * Validate if cards form a valid play
 * @param {number[]} cards - Array of card IDs
 * @returns {boolean} - True if valid play
 */
export function isValidPlay(cards) {
  if (!cards || cards.length === 0) return false;

  // Validate card IDs
  if (cards.some(c => c < 0 || c > 53)) return false;

  // Single card is always valid (README line 335)
  if (cards.length === 1) return true;

  // Check if it's a valid pair or sequence
  return isValidPair(cards) || isValidSequence(cards);
}

/**
 * Get the type of play
 * @param {number[]} cards - Array of card IDs
 * @returns {string} - 'single', 'pair', 'sequence', or 'invalid'
 */
export function getPlayType(cards) {
  if (!cards || cards.length === 0) return 'invalid';
  if (cards.length === 1) return 'single';

  if (isValidPair(cards)) return 'pair';
  if (isValidSequence(cards)) return 'sequence';

  return 'invalid';
}

/**
 * Check if cards form a valid pair (same rank)
 * @param {number[]} cards - Array of card IDs
 * @returns {boolean}
 */
export function isValidPair(cards) {
  if (cards.length < 2) return false;

  // Separate jokers from regular cards
  const jokers = cards.filter(isJoker);
  const regulars = cards.filter(c => !isJoker(c));

  // All jokers is valid
  if (regulars.length === 0) return true;

  // Check if all regular cards have same rank
  const firstRank = getCardRankValue(regulars[0]);
  const allSameRank = regulars.every(c => getCardRankValue(c) === firstRank);

  // Valid if all regular cards same rank (jokers can substitute)
  return allSameRank;
}

/**
 * Check if cards form a valid sequence (same suit, consecutive)
 * @param {number[]} cards - Array of card IDs
 * @returns {boolean}
 */
export function isValidSequence(cards) {
  // Need at least 3 cards for sequence (README line 362)
  if (cards.length < 3) return false;

  // Separate jokers from regular cards
  const jokers = cards.filter(isJoker);
  const regulars = cards.filter(c => !isJoker(c));

  // Need at least one regular card to determine suit
  if (regulars.length === 0) return false;

  // All regular cards must be same suit (README line 356)
  const firstSuit = getCardSuit(regulars[0]);
  const allSameSuit = regulars.every(c => getCardSuit(c) === firstSuit);
  if (!allSameSuit) return false;

  // Get ranks and sort them
  const ranks = regulars.map(getCardRankValue).sort((a, b) => a - b);

  // Check if we can form a consecutive sequence with available jokers
  let jokersNeeded = 0;
  for (let i = 1; i < ranks.length; i++) {
    const gap = ranks[i] - ranks[i - 1] - 1;

    if (gap < 0) {
      // Duplicate rank in sequence - invalid
      return false;
    }

    jokersNeeded += gap;
  }

  // Can form sequence if we have enough jokers to fill gaps
  return jokersNeeded <= jokers.length;
}

/**
 * Find gaps in a sequence that can be filled by jokers
 * @param {number[]} cards - Array of card IDs
 * @returns {number[]} - Array of rank values where jokers should go
 */
export function findJokerPositions(cards) {
  const jokers = cards.filter(isJoker);
  const regulars = cards.filter(c => !isJoker(c));

  if (regulars.length === 0) return [];

  const ranks = regulars.map(getCardRankValue).sort((a, b) => a - b);
  const gaps = [];

  for (let i = 1; i < ranks.length; i++) {
    const current = ranks[i - 1];
    const next = ranks[i];

    for (let rank = current + 1; rank < next; rank++) {
      gaps.push(rank);
    }
  }

  // Return only as many gaps as we have jokers
  return gaps.slice(0, jokers.length);
}

/**
 * Validate multiple plays (for a full turn)
 * @param {number[][]} plays - Array of card arrays
 * @returns {boolean} - True if all plays are valid
 */
export function isValidTurn(plays) {
  if (!plays || plays.length === 0) return false;

  // All plays must be valid
  return plays.every(isValidPlay);
}

/**
 * Check if cards can form any valid combination
 * @param {number[]} cards - Array of card IDs
 * @returns {Object} - { valid: boolean, type: string, reason: string }
 */
export function analyzePlay(cards) {
  if (!cards || cards.length === 0) {
    return { valid: false, type: 'invalid', reason: 'No cards provided' };
  }

  if (cards.some(c => c < 0 || c > 53)) {
    return { valid: false, type: 'invalid', reason: 'Invalid card IDs' };
  }

  if (cards.length === 1) {
    return { valid: true, type: 'single', reason: 'Single card' };
  }

  if (isValidPair(cards)) {
    return { valid: true, type: 'pair', reason: `Pair of ${getCardRankValue(cards.find(c => !isJoker(c)))}s` };
  }

  if (isValidSequence(cards)) {
    return { valid: true, type: 'sequence', reason: 'Valid sequence' };
  }

  // Try to diagnose why it's invalid
  const jokers = cards.filter(isJoker);
  const regulars = cards.filter(c => !isJoker(c));

  if (regulars.length >= 2) {
    const suits = regulars.map(getCardSuit);
    const uniqueSuits = new Set(suits);
    const ranks = regulars.map(getCardRankValue);
    const uniqueRanks = new Set(ranks);

    if (uniqueRanks.size === 1) {
      return { valid: false, type: 'invalid', reason: 'Not enough cards for pair' };
    }

    if (uniqueSuits.size > 1) {
      return { valid: false, type: 'invalid', reason: 'Mixed suits (sequences must be same suit)' };
    }

    if (cards.length < 3) {
      return { valid: false, type: 'invalid', reason: 'Sequences need at least 3 cards' };
    }

    return { valid: false, type: 'invalid', reason: 'Cards not consecutive' };
  }

  return { valid: false, type: 'invalid', reason: 'Invalid combination' };
}

export default {
  isValidPlay,
  getPlayType,
  isValidPair,
  isValidSequence,
  findJokerPositions,
  isValidTurn,
  analyzePlay,
};
