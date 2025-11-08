/**
 * DeleteBot Use Case
 * Deletes a bot user
 */

const logger = require('../../../logger');

class DeleteBot {
    /**
     * @param {IUserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Delete bot request
     * @param {string} request.botId - Bot user ID to delete
     * @returns {Promise<Object>} Deletion result
     */
    async execute({ botId }) {
        try {
            // Validate input
            if (!botId || typeof botId !== 'string') {
                throw new Error('Bot ID is required');
            }

            // Find bot
            const bot = await this.userRepository.findById(botId);
            if (!bot) {
                throw new Error('Bot not found');
            }

            // Verify it's actually a bot
            if (!bot.isBot()) {
                throw new Error('User is not a bot - cannot delete human users via this endpoint');
            }

            // Delete bot
            const deleted = await this.userRepository.delete(botId);

            if (!deleted) {
                throw new Error('Failed to delete bot');
            }

            logger.info('Bot deleted', {
                botId,
                username: bot.username
            });

            return {
                success: true,
                deletedBotId: botId
            };
        } catch (error) {
            logger.error('Delete bot error', {
                botId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = DeleteBot;
