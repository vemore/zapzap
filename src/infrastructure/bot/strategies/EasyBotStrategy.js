/**
 * EasyBotStrategy
 * Simple bot that makes random valid plays
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');

class EasyBotStrategy extends BotStrategy {
    constructor() {
        super('easy');
    }

    /**
     * Select a random valid play
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // Find all valid plays
        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        // Select random play (excluding single cards if better plays exist)
        const multiCardPlays = validPlays.filter(play => play.length > 1);

        if (multiCardPlays.length > 0) {
            const randomIndex = Math.floor(Math.random() * multiCardPlays.length);
            return multiCardPlays[randomIndex];
        }

        // Fallback to any valid play
        const randomIndex = Math.floor(Math.random() * validPlays.length);
        return validPlays[randomIndex];
    }

    /**
     * Call zapzap immediately when hand value <= 5
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        return CardAnalyzer.canCallZapZap(hand);
    }

    /**
     * Always draw from deck (simple strategy)
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string}
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        return 'deck';
    }

    /**
     * Select random hand size within valid range
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        const minHandSize = 4;
        const maxHandSize = isGoldenScore ? 10 : 7;
        // Random selection within range
        return minHandSize + Math.floor(Math.random() * (maxHandSize - minHandSize + 1));
    }
}

module.exports = EasyBotStrategy;
