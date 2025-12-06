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
                    lowestHandCount: 0,
                    eliminatedAtRound: null  // Track when player was eliminated
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
                    // Track the first round where player was eliminated
                    if (score.is_eliminated && stats.eliminatedAtRound === null) {
                        stats.eliminatedAtRound = score.round_number;
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

            // Sort players by elimination order to determine finish position:
            // 1. Winner (not eliminated) comes first
            // 2. Then by elimination round descending (eliminated later = better rank)
            // 3. If same elimination round, sort by score ascending
            const sortedPlayers = [...players].sort((a, b) => {
                const statsA = playerStatsMap[a.userId] || {};
                const statsB = playerStatsMap[b.userId] || {};
                const isWinnerA = a.userId === winner.userId;
                const isWinnerB = b.userId === winner.userId;

                // Winner always comes first
                if (isWinnerA && !isWinnerB) return -1;
                if (isWinnerB && !isWinnerA) return 1;

                // Non-eliminated players (besides winner) come before eliminated
                const eliminatedA = statsA.eliminatedAtRound;
                const eliminatedB = statsB.eliminatedAtRound;

                // If neither was eliminated, sort by score (lower is better)
                if (eliminatedA === null && eliminatedB === null) {
                    const scoreA = gameState.scores[a.playerIndex] || 0;
                    const scoreB = gameState.scores[b.playerIndex] || 0;
                    return scoreA - scoreB;
                }

                // Non-eliminated comes before eliminated
                if (eliminatedA === null && eliminatedB !== null) return -1;
                if (eliminatedB === null && eliminatedA !== null) return 1;

                // Both eliminated: later elimination = better rank (higher round first)
                if (eliminatedA !== eliminatedB) {
                    return eliminatedB - eliminatedA;  // Descending order
                }

                // Same elimination round: sort by score (lower is better)
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
