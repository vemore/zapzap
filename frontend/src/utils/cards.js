/**
 * Card ID System (0-53)
 * 0-12: Spades (A-K)
 * 13-25: Hearts (A-K)
 * 26-38: Clubs (A-K)
 * 39-51: Diamonds (A-K)
 * 52-53: Jokers
 */

export const SUITS = ['spades', 'hearts', 'clubs', 'diamonds'];
export const RANKS = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

export const SUIT_SYMBOLS = {
  spades: '♠',
  hearts: '♥',
  clubs: '♣',
  diamonds: '♦',
};

/**
 * Get card suit from ID
 * @param {number} cardId - Card ID (0-53)
 * @returns {string} - Suit name
 */
export function getCardSuit(cardId) {
  if (cardId >= 52) return 'joker';
  if (cardId >= 39) return 'diamonds';
  if (cardId >= 26) return 'clubs';
  if (cardId >= 13) return 'hearts';
  return 'spades';
}

/**
 * Get card rank from ID
 * @param {number} cardId - Card ID (0-53)
 * @returns {string} - Rank (A, 2-10, J, Q, K)
 */
export function getCardRank(cardId) {
  if (cardId >= 52) return 'Joker';
  const rankIndex = cardId % 13;
  return RANKS[rankIndex];
}

/**
 * Get numeric rank value (for sequences)
 * @param {number} cardId - Card ID (0-53)
 * @returns {number} - Rank value (1-13)
 */
export function getCardRankValue(cardId) {
  if (cardId >= 52) return 0; // Joker
  return (cardId % 13) + 1; // A=1, 2=2, ..., K=13
}

/**
 * Get card point value
 * @param {number} cardId - Card ID (0-53)
 * @param {boolean} penaltyMode - True for final scoring (Joker=25), false for eligibility (Joker=0)
 * @returns {number} - Point value
 */
export function getCardValue(cardId, penaltyMode = false) {
  if (cardId >= 52) {
    // Joker: 0 for eligibility, 25 for penalty scoring (README line 327-328)
    return penaltyMode ? 25 : 0;
  }

  const rankValue = getCardRankValue(cardId);

  // Card values: A=1, 2-10=face, J=11, Q=12, K=13 (README lines 322-326)
  if (rankValue === 1) return 1; // Ace
  if (rankValue >= 2 && rankValue <= 10) return rankValue; // Number cards
  if (rankValue === 11) return 11; // Jack
  if (rankValue === 12) return 12; // Queen
  if (rankValue === 13) return 13; // King

  return 0;
}

/**
 * Check if card is a Joker
 * @param {number} cardId - Card ID (0-53)
 * @returns {boolean}
 */
export function isJoker(cardId) {
  return cardId === 52 || cardId === 53;
}

/**
 * Get card display name
 * @param {number} cardId - Card ID (0-53)
 * @returns {string} - Card name (e.g., "A♠", "K♥", "Joker")
 */
export function getCardName(cardId) {
  if (isJoker(cardId)) return 'Joker';

  const rank = getCardRank(cardId);
  const suit = getCardSuit(cardId);
  const symbol = SUIT_SYMBOLS[suit];

  return `${rank}${symbol}`;
}

/**
 * Generate a shuffled deck of 54 cards
 * @returns {number[]} - Array of card IDs
 */
export function createDeck() {
  const deck = Array.from({ length: 54 }, (_, i) => i);
  return shuffleDeck(deck);
}

/**
 * Shuffle deck using Fisher-Yates algorithm
 * @param {number[]} deck - Array of card IDs
 * @returns {number[]} - Shuffled deck
 */
export function shuffleDeck(deck) {
  const shuffled = [...deck];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

/**
 * Sort cards by suit and rank
 * @param {number[]} cards - Array of card IDs
 * @returns {number[]} - Sorted cards
 */
export function sortCards(cards) {
  return [...cards].sort((a, b) => {
    // Jokers last
    if (isJoker(a)) return 1;
    if (isJoker(b)) return -1;

    // Sort by suit first, then rank
    const suitA = Math.floor(a / 13);
    const suitB = Math.floor(b / 13);

    if (suitA !== suitB) {
      return suitA - suitB;
    }

    return (a % 13) - (b % 13);
  });
}

export default {
  SUITS,
  RANKS,
  SUIT_SYMBOLS,
  getCardSuit,
  getCardRank,
  getCardRankValue,
  getCardValue,
  isJoker,
  getCardName,
  createDeck,
  shuffleDeck,
  sortCards,
};
