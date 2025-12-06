import { getCardValue, isJoker } from './cards';

/**
 * Calculate total value of a hand
 * @param {number[]} hand - Array of card IDs
 * @param {boolean} penaltyMode - True for final scoring (Joker=25), false for eligibility (Joker=0)
 * @returns {number} - Total hand value
 */
export function calculateHandValue(hand, penaltyMode = false) {
  if (!hand || hand.length === 0) return 0;

  return hand.reduce((sum, cardId) => {
    return sum + getCardValue(cardId, penaltyMode);
  }, 0);
}

/**
 * Check if hand is eligible for ZapZap
 * @param {number[]} hand - Array of card IDs
 * @returns {boolean} - True if hand value ≤5 (with Joker=0)
 */
export function isZapZapEligible(hand) {
  // Calculate hand value with Joker=0 (README line 368)
  const handValue = calculateHandValue(hand, false);

  // Eligible if hand value ≤5 points (README line 368-376)
  return handValue <= 5;
}

/**
 * Calculate counteract penalty
 * @param {number} handValue - Player's hand value
 * @param {number} numActivePlayers - Number of active (non-eliminated) players
 * @returns {number} - Penalty = hand + ((activePlayers - 1) × 5)
 */
export function calculateCounteractPenalty(handValue, numActivePlayers) {
  // Penalty is hand points + (other active players × 5)
  // The caller is excluded from the count
  return handValue + ((numActivePlayers - 1) * 5);
}

/**
 * Calculate final scores for all players
 * @param {Object[]} hands - Array of { userId, hand, value }
 * @param {string|null} zapZapCallerId - User ID who called ZapZap (null if no one)
 * @returns {Object} - Map of userId to final score
 */
export function calculateFinalScore(hands, zapZapCallerId = null) {
  if (!hands || hands.length === 0) return {};

  const numPlayers = hands.length;
  const scores = {};

  // Calculate hand values with penalty mode (Joker=25)
  const handValues = hands.map(h => ({
    userId: h.userId,
    value: calculateHandValue(h.hand, true),
  }));

  // Find lowest hand value
  const lowestValue = Math.min(...handValues.map(h => h.value));

  // Calculate scores
  handValues.forEach(({ userId, value }) => {
    if (value === lowestValue) {
      // Lowest hand gets 0 points (README line 381-382)
      scores[userId] = 0;
    } else {
      // Others get their hand value (README line 383-384)
      scores[userId] = value;
    }
  });

  // Check for counteract if someone called ZapZap
  if (zapZapCallerId) {
    const caller = handValues.find(h => h.userId === zapZapCallerId);
    // Check if another player has equal or lower value (counteract condition)
    const otherPlayersLowerOrEqual = handValues.some(
      h => h.userId !== zapZapCallerId && h.value <= caller.value
    );

    if (caller && otherPlayersLowerOrEqual) {
      // Caller is counteracted! Apply penalty
      // The caller always gets penalty when counteracted (even if tied for lowest)
      scores[zapZapCallerId] = calculateCounteractPenalty(caller.value, numPlayers);
    }
  }

  return scores;
}

/**
 * Check if ZapZap call will be successful
 * @param {number[]} callerHand - Caller's hand
 * @param {number[][]} otherHands - Array of other players' hands
 * @returns {Object} - { success: boolean, lowestPlayer: number|null }
 */
export function checkZapZapSuccess(callerHand, otherHands) {
  const callerValue = calculateHandValue(callerHand, true);

  const otherValues = otherHands.map(hand => calculateHandValue(hand, true));
  const lowestOther = Math.min(...otherValues);

  if (callerValue < lowestOther) {
    // Caller has strictly lowest - success!
    return { success: true, lowestPlayer: null };
  } else {
    // Someone has lower or equal - counteracted!
    // Equality means counteract (the other player with equal score gets 0, caller gets penalty)
    const lowestPlayerIndex = otherValues.indexOf(lowestOther);
    return { success: false, lowestPlayer: lowestPlayerIndex };
  }
}

/**
 * Get hand value for display purposes
 * @param {number[]} hand - Array of card IDs
 * @returns {Object} - { eligibility: number, penalty: number }
 */
export function getHandValueDisplay(hand) {
  return {
    eligibility: calculateHandValue(hand, false), // Joker = 0
    penalty: calculateHandValue(hand, true), // Joker = 25
  };
}

/**
 * Check if player is eliminated
 * @param {number} totalScore - Player's cumulative score
 * @returns {boolean} - True if score > 100 (README line 417)
 */
export function isEliminated(totalScore) {
  return totalScore > 100;
}

/**
 * Get remaining players (not eliminated)
 * @param {Object} playerScores - Map of userId to total score
 * @returns {string[]} - Array of remaining player IDs
 */
export function getRemainingPlayers(playerScores) {
  return Object.entries(playerScores)
    .filter(([_, score]) => score <= 100)
    .map(([userId]) => userId);
}

/**
 * Check if game should enter Golden Score (last 2 players)
 * @param {Object} playerScores - Map of userId to total score
 * @returns {boolean} - True if exactly 2 players remain (README line 418)
 */
export function isGoldenScore(playerScores) {
  const remaining = getRemainingPlayers(playerScores);
  return remaining.length === 2;
}

/**
 * Calculate score breakdown for display
 * @param {Object[]} hands - Array of { userId, hand, value }
 * @param {string|null} zapZapCallerId - User ID who called ZapZap
 * @returns {Object} - Detailed scoring information
 */
export function getScoreBreakdown(hands, zapZapCallerId = null) {
  const finalScores = calculateFinalScore(hands, zapZapCallerId);
  const numPlayers = hands.length;

  const handValues = hands.map(h => ({
    userId: h.userId,
    eligibilityValue: calculateHandValue(h.hand, false),
    penaltyValue: calculateHandValue(h.hand, true),
    jokerCount: h.hand.filter(cardId => isJoker(cardId)).length,
  }));

  const lowestValue = Math.min(...handValues.map(h => h.penaltyValue));
  const lowestUserId = handValues.find(h => h.penaltyValue === lowestValue)?.userId;

  const isCounterActed = zapZapCallerId && finalScores[zapZapCallerId] > handValues.find(h => h.userId === zapZapCallerId)?.penaltyValue;

  return {
    finalScores,
    handValues,
    lowestValue,
    lowestUserId,
    zapZapCallerId,
    isCounterActed,
    numPlayers,
  };
}

export default {
  calculateHandValue,
  isZapZapEligible,
  calculateCounteractPenalty,
  calculateFinalScore,
  checkZapZapSuccess,
  getHandValueDisplay,
  isEliminated,
  getRemainingPlayers,
  isGoldenScore,
  getScoreBreakdown,
};
