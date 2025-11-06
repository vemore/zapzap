/**
 * CallZapZap Use Case
 * Handles calling zapzap when player's hand value is low enough
 */

const logger = require('../../../logger');

class CallZapZap {
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
     * @param {Object} request - ZapZap request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @returns {Promise<Object>} ZapZap result with scores
     */
    async execute({ userId, partyId }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            // Verify user exists
            const user = await this.userRepository.findById(userId);
            if (!user) {
                throw new Error('User not found');
            }

            // Find party
            const party = await this.partyRepository.findById(partyId);
            if (!party) {
                throw new Error('Party not found');
            }

            // Check party is playing
            if (party.status !== 'playing') {
                throw new Error('Party is not in playing state');
            }

            // Get current round
            if (!party.currentRoundId) {
                throw new Error('No active round');
            }

            const round = await this.partyRepository.getRoundById(party.currentRoundId);
            if (!round) {
                throw new Error('Round not found');
            }

            // Get game state
            const gameState = await this.partyRepository.getGameState(partyId);
            if (!gameState) {
                throw new Error('Game state not found');
            }

            // Get player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);
            if (!player) {
                throw new Error('User is not in this party');
            }

            // Check if it's player's turn
            if (gameState.currentTurn !== player.playerIndex) {
                throw new Error('Not your turn');
            }

            // Check current action allows zapzap
            if (gameState.currentAction !== 'zapzap' && gameState.currentAction !== 'play') {
                throw new Error('Cannot call zapzap at this time');
            }

            // Calculate player's hand points
            const playerHand = gameState.hands[player.playerIndex] || [];
            const handPoints = this.calculateHandPoints(playerHand);

            // Check if hand value is low enough (≤5 points)
            if (handPoints > 5) {
                throw new Error(`Hand value too high (${handPoints} points). Must be ≤5 to call zapzap.`);
            }

            // Calculate all players' scores
            const scores = {};
            const handPointsMap = {};

            for (const p of players) {
                const hand = gameState.hands[p.playerIndex] || [];
                const points = this.calculateHandPoints(hand);
                handPointsMap[p.playerIndex] = points;
                scores[p.playerIndex] = (gameState.scores[p.playerIndex] || 0);
            }

            // Check for counteract (another player has equal or lower points)
            let counteracted = false;
            let counteractPlayer = null;

            for (const p of players) {
                if (p.playerIndex !== player.playerIndex) {
                    if (handPointsMap[p.playerIndex] <= handPoints) {
                        counteracted = true;
                        counteractPlayer = p;
                        break;
                    }
                }
            }

            // Calculate score changes
            if (counteracted) {
                // Zapzap failed - caller gets points from all players
                for (const p of players) {
                    if (p.playerIndex !== player.playerIndex) {
                        scores[player.playerIndex] += handPointsMap[p.playerIndex];
                    }
                }

                logger.info('ZapZap counteracted', {
                    userId: userId,
                    username: user.username,
                    partyId: partyId,
                    roundId: round.id,
                    callerPoints: handPoints,
                    counteractPlayerIndex: counteractPlayer.playerIndex,
                    counteractPoints: handPointsMap[counteractPlayer.playerIndex]
                });
            } else {
                // Zapzap successful - all other players get caller's points
                for (const p of players) {
                    if (p.playerIndex !== player.playerIndex) {
                        scores[p.playerIndex] += handPoints;
                    }
                }

                logger.info('ZapZap successful', {
                    userId: userId,
                    username: user.username,
                    partyId: partyId,
                    roundId: round.id,
                    callerPoints: handPoints
                });
            }

            // Update round status
            round.finish();
            await this.partyRepository.saveRound(round);

            // Update game state with final scores
            const newGameState = gameState.withUpdates({
                scores: scores,
                currentAction: 'finished'
            });

            await this.partyRepository.saveGameState(partyId, newGameState);

            return {
                success: true,
                zapzapSuccess: !counteracted,
                counteracted: counteracted,
                counteractedBy: counteracted ? counteractPlayer.playerIndex : null,
                scores: scores,
                handPoints: handPointsMap,
                callerPoints: handPoints
            };
        } catch (error) {
            logger.error('Call zapzap error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Calculate hand points
     * @param {number[]} hand - Card IDs
     * @returns {number} Total points
     * @private
     */
    calculateHandPoints(hand) {
        let points = 0;

        for (const cardId of hand) {
            // Jokers (52, 53) = 0 points
            if (cardId >= 52) {
                continue;
            }

            // Get rank (0-12 for A-K)
            const rank = cardId % 13;

            // Ace = 1, 2-9 = face value, 10-K = 10
            if (rank === 0) {
                points += 1; // Ace
            } else if (rank <= 8) {
                points += rank + 1; // 2-9
            } else {
                points += 10; // 10, J, Q, K
            }
        }

        return points;
    }
}

module.exports = CallZapZap;
