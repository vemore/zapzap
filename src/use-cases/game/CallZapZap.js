/**
 * CallZapZap Use Case
 * Handles calling zapzap when player's hand value is low enough
 */

const logger = require('../../../logger');
const CardAnalyzer = require('../../infrastructure/bot/CardAnalyzer');

class CallZapZap {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     * @param {IUserRepository} userRepository - User repository
     * @param {SaveRoundScores} saveRoundScores - SaveRoundScores use case
     */
    constructor(partyRepository, userRepository, saveRoundScores = null) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
        this.saveRoundScores = saveRoundScores;
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

            // Check if player is eliminated
            const eliminatedPlayers = gameState.eliminatedPlayers || [];
            if (eliminatedPlayers.includes(player.playerIndex)) {
                throw new Error('Player is eliminated and cannot call ZapZap');
            }

            // Calculate player's hand points
            const playerHand = gameState.hands[player.playerIndex] || [];
            const handPoints = this.calculateHandPoints(playerHand);

            // Check if hand value is low enough (≤5 points)
            if (handPoints > 5) {
                throw new Error(`Hand value too high (${handPoints} points). Must be ≤5 to call zapzap.`);
            }

            // Calculate all players' base hand values (Joker=0) for ZapZap comparison
            const baseHandPoints = {};
            for (const p of players) {
                const hand = gameState.hands[p.playerIndex] || [];
                baseHandPoints[p.playerIndex] = this.calculateHandPoints(hand);
            }

            // Initialize scores from current game state
            const scores = {};
            for (const p of players) {
                scores[p.playerIndex] = (gameState.scores[p.playerIndex] || 0);
            }

            // Check for counteract (another player has equal or lower base points)
            let counteracted = false;
            let counteractPlayer = null;

            for (const p of players) {
                if (p.playerIndex !== player.playerIndex) {
                    if (baseHandPoints[p.playerIndex] <= handPoints) {
                        counteracted = true;
                        counteractPlayer = p;
                        break;
                    }
                }
            }

            // Find the lowest base hand value to determine who has lowest hand
            const lowestBaseValue = Math.min(...Object.values(baseHandPoints));

            // Calculate actual hand scores with Joker rule (Joker = 25 pts)
            // Note: We calculate with Joker=25 for everyone, lowest hand gets 0 anyway
            const handPointsMap = {};
            for (const p of players) {
                const hand = gameState.hands[p.playerIndex] || [];
                // Calculate with Joker = 25 for display purposes
                handPointsMap[p.playerIndex] = CardAnalyzer.calculateHandScore(hand, false);
            }

            // Calculate score changes according to rules:
            // - Lowest hand player: 0 points
            // - Other players: their hand points (Joker = 25)
            // - If counteracted: caller gets hand_points + (num_players × 5)

            if (counteracted) {
                // ZapZap failed - someone else has lower or equal hand
                // The counteracting player (lowest) gets 0 points
                // Caller gets penalty: their hand points + (num_players × 5)
                // Other players get their hand points (Joker = 25)

                const callerPenalty = handPointsMap[player.playerIndex] + (players.length * 5);

                for (const p of players) {
                    const isLowest = baseHandPoints[p.playerIndex] === lowestBaseValue;

                    if (isLowest) {
                        // Lowest hand gets 0 points this round
                        // scores[p.playerIndex] += 0;
                    } else if (p.playerIndex === player.playerIndex) {
                        // Caller gets penalty
                        scores[p.playerIndex] += callerPenalty;
                    } else {
                        // Other players get their hand points
                        scores[p.playerIndex] += handPointsMap[p.playerIndex];
                    }
                }

                logger.info('ZapZap counteracted', {
                    userId: userId,
                    username: user.username,
                    partyId: partyId,
                    roundId: round.id,
                    callerBasePoints: handPoints,
                    callerPenalty: callerPenalty,
                    counteractPlayerIndex: counteractPlayer.playerIndex,
                    counteractPoints: baseHandPoints[counteractPlayer.playerIndex]
                });
            } else {
                // ZapZap successful - caller has lowest hand
                // Caller (lowest) gets 0 points
                // Other players get their hand points (Joker = 25)

                for (const p of players) {
                    if (p.playerIndex === player.playerIndex) {
                        // Caller (lowest) gets 0 points this round
                        // scores[p.playerIndex] += 0;
                    } else {
                        // Other players get their hand points
                        scores[p.playerIndex] += handPointsMap[p.playerIndex];
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

            // Archive round scores
            if (this.saveRoundScores) {
                // Find the lowest hand player index
                let lowestHandPlayerIndex = player.playerIndex;
                for (const p of players) {
                    if (baseHandPoints[p.playerIndex] === lowestBaseValue) {
                        lowestHandPlayerIndex = p.playerIndex;
                        break;
                    }
                }

                // Calculate score this round for each player
                const playersWithScores = players.map(p => {
                    const isLowest = baseHandPoints[p.playerIndex] === lowestBaseValue;
                    let scoreThisRound = 0;

                    if (isLowest) {
                        scoreThisRound = 0;
                    } else if (counteracted && p.playerIndex === player.playerIndex) {
                        // Caller got penalty
                        scoreThisRound = handPointsMap[p.playerIndex] + (players.length * 5);
                    } else {
                        scoreThisRound = handPointsMap[p.playerIndex];
                    }

                    return {
                        odId: p.userId,
                        playerIndex: p.playerIndex,
                        handPoints: handPointsMap[p.playerIndex],
                        scoreThisRound: scoreThisRound
                    };
                });

                try {
                    await this.saveRoundScores.execute({
                        partyId,
                        roundNumber: round.roundNumber,
                        players: playersWithScores,
                        gameState: newGameState,
                        zapZapCallerIndex: player.playerIndex,
                        wasCounterActed: counteracted,
                        lowestHandPlayerIndex: lowestHandPlayerIndex
                    });
                } catch (archiveError) {
                    logger.error('Failed to archive round scores', {
                        partyId,
                        roundNumber: round.roundNumber,
                        error: archiveError.message
                    });
                    // Don't fail the zapzap if archiving fails
                }
            }

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
