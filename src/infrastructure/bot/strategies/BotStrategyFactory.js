/**
 * BotStrategyFactory
 * Factory for creating bot strategy instances based on difficulty
 */

const EasyBotStrategy = require('./EasyBotStrategy');
const MediumBotStrategy = require('./MediumBotStrategy');
const HardBotStrategy = require('./HardBotStrategy');
const HardVinceBotStrategy = require('./HardVinceBotStrategy');

class BotStrategyFactory {
    /**
     * Create a bot strategy instance
     * @param {string} difficulty - Bot difficulty ('easy', 'medium', 'hard')
     * @returns {BotStrategy} Strategy instance
     */
    static create(difficulty) {
        switch (difficulty.toLowerCase()) {
            case 'easy':
                return new EasyBotStrategy();
            case 'medium':
                return new MediumBotStrategy();
            case 'hard':
                return new HardBotStrategy();
            case 'hard_vince':
                return new HardVinceBotStrategy();
            default:
                throw new Error(`Unknown bot difficulty: ${difficulty}`);
        }
    }

    /**
     * Get all available difficulty levels
     * @returns {Array<string>}
     */
    static getAvailableDifficulties() {
        return ['easy', 'medium', 'hard', 'hard_vince'];
    }

    /**
     * Validate difficulty level
     * @param {string} difficulty
     * @returns {boolean}
     */
    static isValidDifficulty(difficulty) {
        return this.getAvailableDifficulties().includes(difficulty.toLowerCase());
    }
}

module.exports = BotStrategyFactory;
