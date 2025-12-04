/**
 * GetGameDetails Use Case
 * Retrieves detailed information about a finished game including round-by-round scores
 */

const logger = require('../../../logger');

class GetGameDetails {
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
     * @param {Object} request - Get details request
     * @param {string} request.partyId - Party ID
     * @param {string} request.userId - User ID (for access check, optional)
     * @returns {Promise<Object>} Game details result
     */
    async execute({ partyId, userId = null }) {
        try {
            // Validate input
            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            // Get party info
            const party = await this.partyRepository.findById(partyId);
            if (!party) {
                throw new Error('Party not found');
            }

            // Get game result
            const gameResult = await this.partyRepository.getGameResultByPartyId(partyId);
            if (!gameResult) {
                throw new Error('Game result not found - game may not be finished');
            }

            // Get player results
            const playerResults = await this.partyRepository.getPlayerResultsForParty(partyId);

            // Get round scores
            const roundScores = await this.partyRepository.getRoundScoresForParty(partyId);

            // Build user map for usernames
            const userIds = new Set();
            userIds.add(gameResult.winner_user_id);
            playerResults.forEach(p => userIds.add(p.user_id));
            roundScores.forEach(s => userIds.add(s.user_id));

            const userMap = {};
            for (const uid of userIds) {
                const user = await this.userRepository.findById(uid);
                userMap[uid] = user?.username || 'Unknown';
            }

            // Format player results
            const formattedPlayers = playerResults.map(p => ({
                userId: p.user_id,
                username: userMap[p.user_id],
                finalScore: p.final_score,
                finishPosition: p.finish_position,
                roundsPlayed: p.rounds_played,
                totalZapZapCalls: p.total_zapzap_calls,
                successfulZapZaps: p.successful_zapzaps,
                failedZapZaps: p.failed_zapzaps,
                lowestHandCount: p.lowest_hand_count,
                isWinner: p.is_winner === 1
            }));

            // Group round scores by round number
            const roundsMap = {};
            for (const score of roundScores) {
                const roundNum = score.round_number;
                if (!roundsMap[roundNum]) {
                    roundsMap[roundNum] = {
                        roundNumber: roundNum,
                        players: []
                    };
                }
                roundsMap[roundNum].players.push({
                    userId: score.user_id,
                    username: userMap[score.user_id],
                    playerIndex: score.player_index,
                    scoreThisRound: score.score_this_round,
                    totalScoreAfter: score.total_score_after,
                    handPoints: score.hand_points,
                    handCards: score.hand_cards ? JSON.parse(score.hand_cards) : [],
                    isZapZapCaller: score.is_zapzap_caller === 1,
                    zapZapSuccess: score.zapzap_success === 1,
                    wasCounterActed: score.was_counteracted === 1,
                    isLowestHand: score.is_lowest_hand === 1,
                    isEliminated: score.is_eliminated === 1
                });
            }

            // Convert to array and sort by round number
            const rounds = Object.values(roundsMap).sort((a, b) => a.roundNumber - b.roundNumber);

            logger.debug('Game details retrieved', {
                partyId,
                totalRounds: rounds.length,
                playerCount: formattedPlayers.length
            });

            return {
                success: true,
                game: {
                    partyId: party.id,
                    partyName: party.name,
                    visibility: party.visibility,
                    status: party.status,
                    winner: {
                        userId: gameResult.winner_user_id,
                        username: userMap[gameResult.winner_user_id],
                        finalScore: gameResult.winner_final_score
                    },
                    totalRounds: gameResult.total_rounds,
                    wasGoldenScore: gameResult.was_golden_score === 1,
                    playerCount: gameResult.player_count,
                    finishedAt: gameResult.finished_at
                },
                players: formattedPlayers,
                rounds: rounds
            };
        } catch (error) {
            logger.error('Get game details error', {
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetGameDetails;
