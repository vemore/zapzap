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
     * @param {SaveGameResult} saveGameResult - SaveGameResult use case
     */
    constructor(partyRepository, userRepository, saveRoundScores = null, saveGameResult = null) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
        this.saveRoundScores = saveRoundScores;
        this.saveGameResult = saveGameResult;
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

            // Filter out eliminated players - they don't participate in scoring
            const activePlayers = players.filter(p => !eliminatedPlayers.includes(p.playerIndex));

            // Calculate player's hand points
            const playerHand = gameState.hands[player.playerIndex] || [];
            const handPoints = this.calculateHandPoints(playerHand);

            // Check if hand value is low enough (≤5 points)
            if (handPoints > 5) {
                throw new Error(`Hand value too high (${handPoints} points). Must be ≤5 to call zapzap.`);
            }

            // Calculate all players' base hand values (Joker=0) for ZapZap comparison
            // Only for active (non-eliminated) players
            const baseHandPoints = {};
            for (const p of activePlayers) {
                const hand = gameState.hands[p.playerIndex] || [];
                baseHandPoints[p.playerIndex] = this.calculateHandPoints(hand);
            }

            // Initialize scores from current game state (for all players, including eliminated)
            const scores = {};
            for (const p of players) {
                scores[p.playerIndex] = (gameState.scores[p.playerIndex] || 0);
            }

            // Check for counteract (another ACTIVE player has equal or lower base points)
            let counteracted = false;
            let counteractPlayer = null;

            for (const p of activePlayers) {
                if (p.playerIndex !== player.playerIndex) {
                    if (baseHandPoints[p.playerIndex] <= handPoints) {
                        counteracted = true;
                        counteractPlayer = p;
                        break;
                    }
                }
            }

            // Find the lowest base hand value among ACTIVE players to determine who has lowest hand
            const lowestBaseValue = Math.min(...Object.values(baseHandPoints));

            // Calculate actual hand scores with Joker rule (Joker = 25 pts)
            // Only for active players - eliminated players don't get scored
            const handPointsMap = {};
            for (const p of activePlayers) {
                const hand = gameState.hands[p.playerIndex] || [];
                // Calculate with Joker = 25 for display purposes
                handPointsMap[p.playerIndex] = CardAnalyzer.calculateHandScore(hand, false);
            }

            // Calculate score changes according to rules:
            // - Lowest hand player (not the caller if counteracted): 0 points
            // - Other active players: their hand points (Joker = 25)
            // - If counteracted: caller gets hand_points + ((num_active_players - 1) × 5)
            // - Eliminated players: no score change (they're out of the game)

            if (counteracted) {
                // ZapZap failed - someone else has lower or equal hand
                // The counteracting player (lowest, not the caller) gets 0 points
                // Caller gets penalty: their hand points + ((num_active_players - 1) × 5)
                // Other active players get their hand points (Joker = 25)

                // Penalty is based on other active players (excluding the caller)
                const callerPenalty = handPointsMap[player.playerIndex] + ((activePlayers.length - 1) * 5);

                for (const p of activePlayers) {
                    if (p.playerIndex === player.playerIndex) {
                        // Caller always gets penalty when counteracted (even if tied for lowest)
                        scores[p.playerIndex] += callerPenalty;
                    } else {
                        const isLowest = baseHandPoints[p.playerIndex] === lowestBaseValue;
                        if (isLowest) {
                            // Lowest hand (not the caller) gets 0 points this round
                            // scores[p.playerIndex] += 0;
                        } else {
                            // Other active players get their hand points
                            scores[p.playerIndex] += handPointsMap[p.playerIndex];
                        }
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
                // Other active players get their hand points (Joker = 25)

                for (const p of activePlayers) {
                    if (p.playerIndex === player.playerIndex) {
                        // Caller (lowest) gets 0 points this round
                        // scores[p.playerIndex] += 0;
                    } else {
                        // Other active players get their hand points
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

            // Calculate round scores (points gained this round) for each player
            // Eliminated players get 0 for this round (they don't participate)
            const roundScores = {};
            for (const p of players) {
                // Eliminated players get 0 - they're out of the game
                if (eliminatedPlayers.includes(p.playerIndex)) {
                    roundScores[p.playerIndex] = 0;
                    continue;
                }

                if (counteracted && p.playerIndex === player.playerIndex) {
                    // Caller always gets penalty when counteracted (even if tied for lowest)
                    // Penalty is based on other active players (excluding the caller)
                    roundScores[p.playerIndex] = handPointsMap[p.playerIndex] + ((activePlayers.length - 1) * 5);
                } else {
                    const isLowest = baseHandPoints[p.playerIndex] === lowestBaseValue;
                    if (isLowest) {
                        roundScores[p.playerIndex] = 0;
                    } else {
                        roundScores[p.playerIndex] = handPointsMap[p.playerIndex];
                    }
                }
            }

            // Check if game is finished after this round
            // Recalculate active players based on NEW scores (after this round)
            // Combine previously eliminated players with newly eliminated ones
            const allEliminatedIndices = [...eliminatedPlayers];
            const stillActivePlayers = [];
            for (const p of players) {
                const playerScore = scores[p.playerIndex] || 0;
                if (playerScore > 100 && !eliminatedPlayers.includes(p.playerIndex)) {
                    // Newly eliminated this round
                    allEliminatedIndices.push(p.playerIndex);
                }
                if (playerScore <= 100) {
                    stillActivePlayers.push(p);
                }
            }

            // Check if game should end
            let gameFinished = false;
            let winner = null;

            if (stillActivePlayers.length <= 1) {
                // Game is finished - only 1 or 0 players remaining
                gameFinished = true;
                if (stillActivePlayers.length === 1) {
                    winner = stillActivePlayers[0];
                } else {
                    // All players eliminated - winner is lowest score
                    winner = players.reduce((lowest, p) => {
                        const pScore = scores[p.playerIndex] || 0;
                        const lowestScore = scores[lowest.playerIndex] || 0;
                        return pScore < lowestScore ? p : lowest;
                    }, players[0]);
                }
            } else if (gameState.isGoldenScore && stillActivePlayers.length === 2) {
                // Golden Score mode - check if there's a clear winner
                const [p1, p2] = stillActivePlayers;
                const score1 = scores[p1.playerIndex] || 0;
                const score2 = scores[p2.playerIndex] || 0;

                if (score1 !== score2) {
                    gameFinished = true;
                    winner = score1 < score2 ? p1 : p2;
                }
            }

            // Update party status if game is finished
            if (gameFinished) {
                party.finish();
                await this.partyRepository.save(party);

                logger.info('Game finished after ZapZap', {
                    partyId: partyId,
                    winnerId: winner?.userId,
                    finalScores: scores,
                    wasGoldenScore: gameState.isGoldenScore
                });

                // Archive game result
                if (this.saveGameResult && winner) {
                    try {
                        await this.saveGameResult.execute({
                            partyId,
                            winner: {
                                userId: winner.userId,
                                playerIndex: winner.playerIndex,
                                finalScore: scores[winner.playerIndex] || 0
                            },
                            totalRounds: round.roundNumber,
                            wasGoldenScore: gameState.isGoldenScore,
                            players: players,
                            gameState: gameState.withUpdates({ scores })
                        });
                    } catch (archiveError) {
                        logger.error('Failed to archive game result after ZapZap', {
                            partyId,
                            error: archiveError.message
                        });
                        // Don't fail the zapzap if archiving fails
                    }
                }
            }

            // Update game state with final scores and zapzap action info
            const newGameState = gameState.withUpdates({
                scores: scores,
                currentAction: 'finished',
                eliminatedPlayers: allEliminatedIndices,
                lastAction: {
                    type: 'zapzap',
                    playerIndex: player.playerIndex,
                    wasCounterActed: counteracted,
                    counterActedByPlayerIndex: counteracted ? counteractPlayer.playerIndex : null,
                    callerHandPoints: handPoints,
                    roundScores: roundScores,
                    timestamp: Date.now()
                }
            });

            await this.partyRepository.saveGameState(partyId, newGameState);

            // Archive round scores
            if (this.saveRoundScores) {
                // Find the lowest hand player index (among active players)
                let lowestHandPlayerIndex = player.playerIndex;
                for (const p of activePlayers) {
                    if (baseHandPoints[p.playerIndex] === lowestBaseValue) {
                        lowestHandPlayerIndex = p.playerIndex;
                        break;
                    }
                }

                // Calculate score this round for each player
                const playersWithScores = players.map(p => {
                    // Eliminated players get 0 and no hand points
                    if (eliminatedPlayers.includes(p.playerIndex)) {
                        return {
                            userId: p.userId,
                            playerIndex: p.playerIndex,
                            handPoints: 0,
                            scoreThisRound: 0
                        };
                    }

                    let scoreThisRound = 0;

                    if (counteracted && p.playerIndex === player.playerIndex) {
                        // Caller always gets penalty when counteracted (even if tied for lowest)
                        // Penalty is based on other active players (excluding the caller)
                        scoreThisRound = handPointsMap[p.playerIndex] + ((activePlayers.length - 1) * 5);
                    } else {
                        const isLowest = baseHandPoints[p.playerIndex] === lowestBaseValue;
                        if (isLowest) {
                            scoreThisRound = 0;
                        } else {
                            scoreThisRound = handPointsMap[p.playerIndex];
                        }
                    }

                    return {
                        userId: p.userId,
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

            // Ace = 1
            if (rank === 0) {
                points += 1;
            }
            // 2-10 = face value (rank 1-9 → points 2-10)
            else if (rank <= 9) {
                points += rank + 1;
            }
            // J = 11, Q = 12, K = 13 points
            else if (rank === 10) {
                points += 11; // Jack
            } else if (rank === 11) {
                points += 12; // Queen
            } else {
                points += 13; // King
            }
        }

        return points;
    }
}

module.exports = CallZapZap;
