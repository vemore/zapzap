/**
 * GetLeaderboard Use Case
 * Retrieves global leaderboard sorted by win rate
 */

const logger = require('../../../logger');

class GetLeaderboard {
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
     * @param {Object} request - Get leaderboard request
     * @param {number} request.minGames - Minimum games played to appear (default 5)
     * @param {number} request.limit - Max results (default 50)
     * @param {number} request.offset - Offset for pagination (default 0)
     * @returns {Promise<Object>} Leaderboard result
     */
    async execute({ minGames = 5, limit = 50, offset = 0 }) {
        try {
            // Get leaderboard from repository
            const leaderboard = await this.partyRepository.getLeaderboard(minGames, limit, offset);

            // The repository already returns enriched data with usernames
            const enrichedLeaderboard = leaderboard.map((entry) => ({
                rank: entry.rank,
                userId: entry.userId,
                username: entry.username || 'Unknown',
                gamesPlayed: entry.gamesPlayed,
                wins: entry.wins,
                winRate: entry.winRate,
                averageScore: entry.avgScore
            }));

            logger.debug('Leaderboard retrieved', {
                minGames,
                count: enrichedLeaderboard.length
            });

            return {
                success: true,
                leaderboard: enrichedLeaderboard,
                criteria: {
                    minGames,
                    sortBy: 'winRate'
                },
                pagination: {
                    limit,
                    offset,
                    hasMore: leaderboard.length === limit
                }
            };
        } catch (error) {
            logger.error('Get leaderboard error', {
                minGames,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetLeaderboard;
