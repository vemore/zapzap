/**
 * Card Adapter - Conversion between ZapZap numeric IDs and cardmeister cid format
 *
 * ZapZap Card ID System (0-53):
 * - 0-12: Spades (A-K)
 * - 13-25: Hearts (A-K)
 * - 26-38: Clubs (A-K)
 * - 39-51: Diamonds (A-K)
 * - 52-53: Jokers
 *
 * Cardmeister cid format: rank + suit letter
 * - Ranks: A, 2-10, J, Q, K
 * - Suits: s (spades), h (hearts), c (clubs), d (diamonds)
 * - Examples: As (Ace of Spades), Qh (Queen of Hearts), 10d (10 of Diamonds)
 */

// Suit mapping: ZapZap suit index → cardmeister suit letter
const SUIT_MAP = ['s', 'h', 'c', 'd']; // spades, hearts, clubs, diamonds

// Rank mapping: ZapZap rank index → cardmeister rank
const RANK_MAP = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

/**
 * Convert ZapZap numeric card ID to cardmeister cid format
 * @param {number} cardId - Card ID (0-53)
 * @returns {string|null} - cardmeister cid (e.g., "As", "Qh") or null for Jokers
 */
export function cardIdToCid(cardId) {
  if (cardId >= 52) return null; // Joker - not supported by cardmeister

  const suitIndex = Math.floor(cardId / 13);
  const rankIndex = cardId % 13;

  const suit = SUIT_MAP[suitIndex];
  const rank = RANK_MAP[rankIndex];

  return `${rank}${suit}`;
}

/**
 * Check if card ID is a Joker
 * @param {number} cardId - Card ID (0-53)
 * @returns {boolean}
 */
export function isJoker(cardId) {
  return cardId >= 52;
}

/**
 * Get Joker type (red or black)
 * @param {number} cardId - Card ID (52 or 53)
 * @returns {'red'|'black'|null}
 */
export function getJokerType(cardId) {
  if (cardId === 52) return 'red';
  if (cardId === 53) return 'black';
  return null;
}

export default {
  cardIdToCid,
  isJoker,
  getJokerType,
};
