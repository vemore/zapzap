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

            // Enrich with usernames
            const enrichedLeaderboard = await Promise.all(leaderboard.map(async (entry, index) => {
                const user = await this.userRepository.findById(entry.user_id);
                return {
                    rank: offset + index + 1,
                    userId: entry.user_id,
                    username: user?.username || 'Unknown',
                    gamesPlayed: entry.games_played,
                    wins: entry.wins,
                    winRate: entry.win_rate,
                    averageScore: entry.average_score,
                    totalZapZaps: entry.total_zapzaps,
                    successfulZapZaps: entry.successful_zapzaps
                };
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
