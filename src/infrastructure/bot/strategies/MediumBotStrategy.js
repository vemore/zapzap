/**
 * MediumBotStrategy
 * Bot that prioritizes playing high-value cards (Kings, Queens, Jacks, 10s)
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');

class MediumBotStrategy extends BotStrategy {
    constructor() {
        super('medium');
    }

    /**
     * Select play that removes the most high-value cards
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // Try to play high-value cards (10=10, J=11, Q=12, K=13 points)
        const highValuePlay = CardAnalyzer.findHighValuePlay(hand);

        if (highValuePlay && highValuePlay.length > 0) {
            return highValuePlay;
        }

        // Fallback to random valid play
        return CardAnalyzer.findRandomPlay(hand);
    }

    /**
     * Call zapzap when hand value <= 3 (more conservative than easy)
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);
        return handValue <= 3;
    }

    /**
     * Draw from discard if it helps complete a set/sequence
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string}
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        if (!Array.isArray(lastCardsPlayed) || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        // Check if any discard card would help form a combination
        for (const discardCard of lastCardsPlayed) {
            const testHand = [...hand, discardCard];
            const playsWithDiscard = CardAnalyzer.findAllValidPlays(testHand);
            const playsWithoutDiscard = CardAnalyzer.findAllValidPlays(hand);

            // If adding discard card creates new multi-card plays, take it
            const newMultiCardPlays = playsWithDiscard.filter(play =>
                play.length > 1 && play.includes(discardCard)
            );

            if (newMultiCardPlays.length > 0) {
                return 'played';
            }
        }

        // Default to deck
        return 'deck';
    }

    /**
     * Select moderate hand size (5-6 cards)
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        const minHandSize = 4;
        const maxHandSize = isGoldenScore ? 10 : 7;
        // Prefer moderate values (5-6 for normal, 6-7 for Golden Score)
        if (isGoldenScore) {
            return 6 + Math.floor(Math.random() * 2); // 6 or 7
        }
        return 5 + Math.floor(Math.random() * 2); // 5 or 6
    }
}

module.exports = MediumBotStrategy;
