/**
 * SaveRoundScores Use Case
 * Archives player scores at the end of each round
 */

const logger = require('../../../logger');

class SaveRoundScores {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     */
    constructor(partyRepository) {
        this.partyRepository = partyRepository;
    }

    /**
     * Execute the use case
     * @param {Object} request - Save scores request
     * @param {string} request.partyId - Party ID
     * @param {number} request.roundNumber - Round number
     * @param {Array} request.players - Array of player data with scores
     * @param {Object} request.gameState - Current game state
     * @param {number|null} request.zapZapCallerIndex - Player index who called ZapZap (if any)
     * @param {boolean} request.wasCounterActed - Whether ZapZap was counteracted
     * @param {number} request.lowestHandPlayerIndex - Player index with lowest hand
     * @returns {Promise<Object>} Result
     */
    async execute({ partyId, roundNumber, players, gameState, zapZapCallerIndex, wasCounterActed, lowestHandPlayerIndex }) {
        try {
            // Validate input
            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            if (!roundNumber || typeof roundNumber !== 'number') {
                throw new Error('Round number is required');
            }

            if (!Array.isArray(players) || players.length === 0) {
                throw new Error('Players data is required');
            }

            if (!gameState) {
                throw new Error('Game state is required');
            }

            // Prepare player scores for archiving
            const playerScores = players.map(player => {
                const playerIndex = player.playerIndex;
                const hand = gameState.hands[playerIndex] || [];
                const handPoints = player.handPoints || 0;
                const scoreThisRound = player.scoreThisRound || 0;
                const totalScoreAfter = gameState.scores[playerIndex] || 0;
                const isZapZapCaller = zapZapCallerIndex === playerIndex;
                const zapZapSuccess = isZapZapCaller && !wasCounterActed;
                const isLowestHand = lowestHandPlayerIndex === playerIndex;
                const isEliminated = totalScoreAfter > 100;

                return {
                    odId: player.userId,
                    playerIndex: playerIndex,
                    scoreThisRound: scoreThisRound,
                    totalScoreAfter: totalScoreAfter,
                    handPoints: handPoints,
                    isZapZapCaller: isZapZapCaller ? 1 : 0,
                    zapZapSuccess: zapZapSuccess ? 1 : 0,
                    wasCounterActed: isZapZapCaller && wasCounterActed ? 1 : 0,
                    handCards: JSON.stringify(hand),
                    isLowestHand: isLowestHand ? 1 : 0,
                    isEliminated: isEliminated ? 1 : 0
                };
            });

            // Save to database
            await this.partyRepository.saveRoundScores(partyId, roundNumber, playerScores);

            logger.info('Round scores archived', {
                partyId,
                roundNumber,
                playerCount: players.length,
                zapZapCaller: zapZapCallerIndex,
                wasCounterActed
            });

            return {
                success: true,
                partyId,
                roundNumber,
                playerScores
            };
        } catch (error) {
            logger.error('Save round scores error', {
                partyId,
                roundNumber,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = SaveRoundScores;
