/**
 * GetGameHistory Use Case
 * Retrieves finished games for a user or public games
 */

const logger = require('../../../logger');

class GetGameHistory {
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
     * @param {Object} request - Get history request
     * @param {string} request.userId - User ID (optional, for personal history)
     * @param {boolean} request.publicOnly - If true, get only public finished games
     * @param {number} request.limit - Max results (default 20)
     * @param {number} request.offset - Offset for pagination (default 0)
     * @returns {Promise<Object>} Game history result
     */
    async execute({ userId = null, publicOnly = false, limit = 20, offset = 0 }) {
        try {
            let games;

            if (publicOnly) {
                // Get public finished games
                games = await this.partyRepository.getPublicFinishedGames(limit, offset);
            } else if (userId) {
                // Verify user exists
                const user = await this.userRepository.findById(userId);
                if (!user) {
                    throw new Error('User not found');
                }

                // Get user's finished games
                games = await this.partyRepository.getFinishedGamesForUser(userId, limit, offset);
            } else {
                throw new Error('Either userId or publicOnly must be specified');
            }

            // Enrich games with winner username
            const enrichedGames = await Promise.all(games.map(async (game) => {
                const winnerUser = await this.userRepository.findById(game.winner_user_id);
                return {
                    id: game.id,
                    partyId: game.party_id,
                    partyName: game.party_name,
                    winnerUserId: game.winner_user_id,
                    winnerUsername: winnerUser?.username || 'Unknown',
                    winnerFinalScore: game.winner_final_score,
                    totalRounds: game.total_rounds,
                    wasGoldenScore: game.was_golden_score === 1,
                    playerCount: game.player_count,
                    finishedAt: game.finished_at,
                    visibility: game.visibility
                };
            }));

            logger.debug('Game history retrieved', {
                userId,
                publicOnly,
                count: enrichedGames.length
            });

            return {
                success: true,
                games: enrichedGames,
                pagination: {
                    limit,
                    offset,
                    hasMore: games.length === limit
                }
            };
        } catch (error) {
            logger.error('Get game history error', {
                userId,
                publicOnly,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetGameHistory;
