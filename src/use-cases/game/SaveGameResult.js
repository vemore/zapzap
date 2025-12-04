/**
 * SaveGameResult Use Case
 * Archives final game results when a game finishes
 */

const logger = require('../../../logger');

class SaveGameResult {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     */
    constructor(partyRepository) {
        this.partyRepository = partyRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Save game result request
     * @param {string} request.partyId - Party ID
     * @param {Object} request.winner - Winner data { userId, playerIndex, finalScore }
     * @param {number} request.totalRounds - Total rounds played
     * @param {boolean} request.wasGoldenScore - Whether game ended in Golden Score
     * @param {Array} request.players - Array of player data with final stats
     * @param {Object} request.gameState - Final game state
     * @returns {Promise<Object>} Result
     */
    async execute({ partyId, winner, totalRounds, wasGoldenScore, players, gameState }) {
        try {
            // Validate input
            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            if (!winner || !winner.userId) {
                throw new Error('Winner data is required');
            }

            if (!totalRounds || typeof totalRounds !== 'number') {
                throw new Error('Total rounds is required');
            }

            if (!Array.isArray(players) || players.length === 0) {
                throw new Error('Players data is required');
            }

            // Get round scores to calculate ZapZap stats per player
            const roundScores = await this.partyRepository.getRoundScoresForParty(partyId);

            // Calculate player stats from round scores
            const playerStatsMap = {};
            for (const player of players) {
                playerStatsMap[player.userId] = {
                    totalZapZapCalls: 0,
                    successfulZapZaps: 0,
                    failedZapZaps: 0,
                    lowestHandCount: 0
                };
            }

            // Aggregate stats from round scores
            for (const score of roundScores) {
                const stats = playerStatsMap[score.user_id];
                if (stats) {
                    if (score.is_zapzap_caller) {
                        stats.totalZapZapCalls++;
                        if (score.zapzap_success) {
                            stats.successfulZapZaps++;
                        } else {
                            stats.failedZapZaps++;
                        }
                    }
                    if (score.is_lowest_hand) {
                        stats.lowestHandCount++;
                    }
                }
            }

            // Save game result
            const gameResult = {
                partyId,
                winnerUserId: winner.userId,
                winnerFinalScore: winner.finalScore || gameState.scores[winner.playerIndex] || 0,
                totalRounds,
                wasGoldenScore: wasGoldenScore ? 1 : 0,
                playerCount: players.length,
                finishedAt: Date.now()
            };

            await this.partyRepository.saveGameResult(gameResult);

            // Sort players by score to determine finish position
            const sortedPlayers = [...players].sort((a, b) => {
                const scoreA = gameState.scores[a.playerIndex] || 0;
                const scoreB = gameState.scores[b.playerIndex] || 0;
                return scoreA - scoreB;
            });

            // Prepare player results
            const playerResults = sortedPlayers.map((player, index) => {
                const stats = playerStatsMap[player.userId] || {};
                const finalScore = gameState.scores[player.playerIndex] || 0;
                const isWinner = player.userId === winner.userId;

                return {
                    userId: player.userId,
                    finalScore,
                    finishPosition: index + 1,
                    roundsPlayed: totalRounds,
                    totalZapZapCalls: stats.totalZapZapCalls || 0,
                    successfulZapZaps: stats.successfulZapZaps || 0,
                    failedZapZaps: stats.failedZapZaps || 0,
                    lowestHandCount: stats.lowestHandCount || 0,
                    isWinner: isWinner ? 1 : 0
                };
            });

            await this.partyRepository.savePlayerGameResults(partyId, playerResults);

            logger.info('Game result archived', {
                partyId,
                winnerId: winner.userId,
                totalRounds,
                wasGoldenScore,
                playerCount: players.length
            });

            return {
                success: true,
                partyId,
                gameResult,
                playerResults
            };
        } catch (error) {
            logger.error('Save game result error', {
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = SaveGameResult;
