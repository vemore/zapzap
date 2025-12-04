/**
 * GetUserStats Use Case
 * Retrieves personal statistics for a user
 */

const logger = require('../../../logger');

class GetUserStats {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     * @param {IUserRepository} userRepository - User repository
     */
    constructor(partyRepository, userRepository) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Get stats request
     * @param {string} request.userId - User ID
     * @returns {Promise<Object>} User statistics result
     */
    async execute({ userId }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            // Verify user exists
            const user = await this.userRepository.findById(userId);
            if (!user) {
                throw new Error('User not found');
            }

            // Get user stats from repository
            const stats = await this.partyRepository.getUserStats(userId);

            logger.debug('User stats retrieved', {
                userId,
                gamesPlayed: stats.gamesPlayed
            });

            return {
                success: true,
                userId: userId,
                username: user.username,
                stats: {
                    gamesPlayed: stats.gamesPlayed,
                    wins: stats.wins,
                    losses: stats.losses,
                    winRate: stats.winRate,
                    averageScore: stats.averageScore,
                    bestScore: stats.bestScore,
                    totalRoundsPlayed: stats.totalRoundsPlayed,
                    zapzaps: stats.zapzaps,
                    lowestHandCount: stats.lowestHandCount
                }
            };
        } catch (error) {
            logger.error('Get user stats error', {
                userId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetUserStats;
