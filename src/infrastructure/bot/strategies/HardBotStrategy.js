/**
 * HardBotStrategy
 * Advanced bot that optimizes hand value minimization and strategic zapzap timing
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');

class HardBotStrategy extends BotStrategy {
    constructor() {
        super('hard');
    }

    /**
     * Select optimal play to minimize remaining hand value
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        // Evaluate each play by resulting hand value
        const evaluatedPlays = validPlays.map(play => {
            const remainingHand = hand.filter(cardId => !play.includes(cardId));
            const remainingValue = CardAnalyzer.calculateHandValue(remainingHand);
            const playValue = CardAnalyzer.calculateHandValue(play);
            const playSize = play.length;

            return {
                cards: play,
                remainingValue,
                playValue,
                playSize,
                // Score: prioritize plays that leave lowest hand value, with bonus for larger plays
                score: -remainingValue + (playSize * 0.5)
            };
        });

        // Sort by score descending (best plays first)
        evaluatedPlays.sort((a, b) => b.score - a.score);

        // Return best play
        return evaluatedPlays[0].cards;
    }

    /**
     * Strategic zapzap decision based on hand value and game context
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Can't zapzap if hand value > 5
        if (handValue > 5) {
            return false;
        }

        // Always zapzap if hand value is 0
        if (handValue === 0) {
            return true;
        }

        // Very confident zapzap at value <= 2
        if (handValue <= 2) {
            return true;
        }

        // Strategic zapzap at value 3-5 based on game state
        // Consider round number: earlier rounds = more conservative
        const roundNumber = gameState.roundNumber || 1;

        if (roundNumber <= 2) {
            // Early game: only zapzap with very low values
            return handValue <= 2;
        } else if (roundNumber <= 4) {
            // Mid game: moderate risk
            return handValue <= 3;
        } else {
            // Late game: more aggressive
            return handValue <= 4;
        }
    }

    /**
     * Intelligent draw decision based on card usefulness
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string}
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        if (!Array.isArray(lastCardsPlayed) || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        // Evaluate each discard card's value
        let bestDiscardCard = null;
        let bestImprovement = 0;

        for (const discardCard of lastCardsPlayed) {
            const improvement = this.evaluateCardValue(discardCard, hand);

            if (improvement > bestImprovement) {
                bestImprovement = improvement;
                bestDiscardCard = discardCard;
            }
        }

        // If any discard card provides significant improvement, take it
        if (bestImprovement > 5) {
            return 'discard';
        }

        // Default to deck
        return 'deck';
    }

    /**
     * Evaluate how valuable a card would be to add to hand
     * @param {number} cardId - Card to evaluate
     * @param {Array<number>} hand - Current hand
     * @returns {number} Value score (higher = better)
     */
    evaluateCardValue(cardId, hand) {
        const testHand = [...hand, cardId];

        // Count how many new multi-card combinations this creates
        const originalPlays = CardAnalyzer.findAllValidPlays(hand);
        const newPlays = CardAnalyzer.findAllValidPlays(testHand);

        const originalMultiCardPlays = originalPlays.filter(p => p.length > 1).length;
        const newMultiCardPlays = newPlays.filter(p => p.length > 1 && p.includes(cardId)).length;

        const combinationBonus = (newMultiCardPlays - originalMultiCardPlays) * 10;

        // Prefer low-value cards (helps with zapzap)
        const cardPoints = CardAnalyzer.getCardPoints(cardId);
        const lowValueBonus = (10 - cardPoints);

        // Prefer cards that complete sequences or sets
        const rank = CardAnalyzer.getRank(cardId);
        const sameRankCount = hand.filter(id =>
            !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === rank
        ).length;

        const setBonus = sameRankCount >= 1 ? sameRankCount * 5 : 0;

        return combinationBonus + lowValueBonus + setBonus;
    }
}

module.exports = HardBotStrategy;
