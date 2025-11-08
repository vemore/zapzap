/**
 * BotStrategy (Base Class)
 * Abstract base class for bot decision-making strategies
 */

const CardAnalyzer = require('../CardAnalyzer');

class BotStrategy {
    /**
     * @param {string} difficulty - Bot difficulty level
     */
    constructor(difficulty) {
        this.difficulty = difficulty;
    }

    /**
     * Decide which cards to play (abstract method)
     * @param {Array<number>} hand - Bot's current hand (card IDs)
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play, or null to skip
     */
    selectPlay(hand, gameState) {
        throw new Error('selectPlay must be implemented by subclass');
    }

    /**
     * Decide whether to call zapzap (abstract method)
     * @param {Array<number>} hand - Bot's current hand (card IDs)
     * @param {Object} gameState - Current game state
     * @returns {boolean} True to call zapzap
     */
    shouldZapZap(hand, gameState) {
        throw new Error('shouldZapZap must be implemented by subclass');
    }

    /**
     * Decide whether to draw from deck or discard pile
     * @param {Array<number>} hand - Bot's current hand (card IDs)
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string} 'deck' or 'discard'
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        // Default: always draw from deck (can be overridden)
        return 'deck';
    }

    /**
     * Get strategy name
     * @returns {string}
     */
    getName() {
        return `${this.difficulty.charAt(0).toUpperCase() + this.difficulty.slice(1)} Bot`;
    }
}

module.exports = BotStrategy;
