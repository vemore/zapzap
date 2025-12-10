/**
 * CreateBot Use Case
 * Creates a new bot user
 */

const User = require('../../domain/entities/User');
const logger = require('../../../logger');

class CreateBot {
    /**
     * @param {IUserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Create bot request
     * @param {string} request.username - Bot username
     * @param {string} request.difficulty - Bot difficulty ('easy', 'medium', 'hard')
     * @returns {Promise<Object>} Created bot user
     */
    async execute({ username, difficulty }) {
        try {
            // Validate input
            if (!username || typeof username !== 'string') {
                throw new Error('Username is required');
            }

            const validDifficulties = ['easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm'];
            if (!difficulty || !validDifficulties.includes(difficulty.toLowerCase())) {
                throw new Error(`Difficulty must be one of: ${validDifficulties.join(', ')}`);
            }

            const trimmedUsername = username.trim();

            // Check if username already exists
            const existingUser = await this.userRepository.findByUsername(trimmedUsername);
            if (existingUser) {
                throw new Error(`Username "${trimmedUsername}" already exists`);
            }

            // Create bot user
            const bot = await User.createBot(trimmedUsername, difficulty.toLowerCase());

            // Save to database
            const savedBot = await this.userRepository.save(bot);

            logger.info('Bot created', {
                botId: savedBot.id,
                username: savedBot.username,
                difficulty: savedBot.botDifficulty
            });

            return {
                success: true,
                bot: savedBot.toPublicObject()
            };
        } catch (error) {
            logger.error('Create bot error', {
                username,
                difficulty,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = CreateBot;
