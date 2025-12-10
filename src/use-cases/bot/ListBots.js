/**
 * ListBots Use Case
 * Lists all available bot users
 */

const logger = require('../../../logger');

class ListBots {
    /**
     * @param {IUserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - List bots request
     * @param {string} request.difficulty - Optional difficulty filter
     * @returns {Promise<Object>} List of bots
     */
    async execute({ difficulty = null } = {}) {
        try {
            // Validate difficulty if provided
            const validDifficulties = ['easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm'];
            if (difficulty && !validDifficulties.includes(difficulty.toLowerCase())) {
                throw new Error(`Invalid difficulty filter. Must be one of: ${validDifficulties.join(', ')}`);
            }

            // Get bots from repository
            const bots = await this.userRepository.findBots(
                difficulty ? difficulty.toLowerCase() : null
            );

            logger.debug('Bots listed', {
                count: bots.length,
                difficulty: difficulty || 'all'
            });

            return {
                success: true,
                bots: bots.map(bot => bot.toPublicObject()),
                count: bots.length
            };
        } catch (error) {
            logger.error('List bots error', {
                difficulty,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = ListBots;
