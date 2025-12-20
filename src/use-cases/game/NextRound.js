/**
 * NextRound Use Case
 * Handles starting the next round after a round ends
 */

const Round = require('../../domain/entities/Round');
const logger = require('../../../logger');

class NextRound {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     * @param {IUserRepository} userRepository - User repository
     * @param {SaveGameResult} saveGameResult - SaveGameResult use case
     */
    constructor(partyRepository, userRepository, saveGameResult = null) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
        this.saveGameResult = saveGameResult;
    }

    /**
     * Execute the use case
     * @param {Object} request - Next round request
     * @param {string} request.userId - User ID requesting next round
     * @param {string} request.partyId - Party ID
     * @returns {Promise<Object>} Next round result
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

            // Get player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);
            if (!player) {
                throw new Error('User is not in this party');
            }

            // Get current game state
            const currentGameState = await this.partyRepository.getGameState(partyId);
            if (!currentGameState) {
                throw new Error('Game state not found');
            }

            // Check if current round is finished
            if (currentGameState.currentAction !== 'finished') {
                throw new Error('Current round is not finished');
            }

            // Get current round
            const currentRound = await this.partyRepository.getRoundById(party.currentRoundId);
            if (!currentRound) {
                throw new Error('Current round not found');
            }

            // Check if any player is eliminated (score > 100, strictly greater)
            const scores = currentGameState.scores || {};
            const eliminatedPlayers = [];
            const activePlayers = [];

            for (const p of players) {
                const playerScore = scores[p.playerIndex] || 0;
                if (playerScore > 100) {
                    eliminatedPlayers.push(p);
                } else {
                    activePlayers.push(p);
                }
            }

            // Get eliminated player indices for game state
            const eliminatedPlayerIndices = eliminatedPlayers.map(p => p.playerIndex);

            // Check if we're already in Golden Score mode and this round just ended
            const wasGoldenScore = currentGameState.isGoldenScore;

            // Check if game should end
            if (activePlayers.length <= 1) {
                // Game is finished - only 1 player remaining
                party.finish();
                await this.partyRepository.save(party);

                const winner = activePlayers[0] || players.reduce((lowest, p) => {
                    const pScore = scores[p.playerIndex] || 0;
                    const lowestScore = scores[lowest.playerIndex] || 0;
                    return pScore < lowestScore ? p : lowest;
                }, players[0]);

                logger.info('Game finished', {
                    partyId: partyId,
                    winnerId: winner.userId,
                    finalScores: scores,
                    wasGoldenScore: wasGoldenScore
                });

                // Archive game result
                if (this.saveGameResult) {
                    try {
                        await this.saveGameResult.execute({
                            partyId,
                            winner: {
                                userId: winner.userId,
                                playerIndex: winner.playerIndex,
                                finalScore: scores[winner.playerIndex] || 0
                            },
                            totalRounds: currentRound.roundNumber,
                            wasGoldenScore: wasGoldenScore,
                            players: players,
                            gameState: currentGameState
                        });
                    } catch (archiveError) {
                        logger.error('Failed to archive game result', {
                            partyId,
                            error: archiveError.message
                        });
                    }
                }

                return {
                    success: true,
                    gameFinished: true,
                    winner: {
                        userId: winner.userId,
                        playerIndex: winner.playerIndex,
                        score: scores[winner.playerIndex] || 0
                    },
                    finalScores: scores,
                    eliminatedPlayers: eliminatedPlayers.map(p => ({
                        userId: p.userId,
                        playerIndex: p.playerIndex,
                        score: scores[p.playerIndex] || 0
                    }))
                };
            }

            // If Golden Score round just ended (2 players were playing), determine winner
            if (wasGoldenScore && activePlayers.length === 2) {
                // Golden Score round finished - winner is player with lowest hand this round
                // Get the round scores to find who had the lowest hand
                const roundScores = await this.partyRepository.getRoundScoresForParty(partyId);
                const lastRoundScores = roundScores.filter(rs => rs.round_number === currentRound.roundNumber);

                const [player1, player2] = activePlayers;

                // Find hand points from round scores
                const p1RoundScore = lastRoundScores.find(rs => rs.player_index === player1.playerIndex);
                const p2RoundScore = lastRoundScores.find(rs => rs.player_index === player2.playerIndex);

                const hand1 = p1RoundScore?.hand_points ?? 0;
                const hand2 = p2RoundScore?.hand_points ?? 0;

                // Determine winner (lowest hand wins, or if tie, use total score as tiebreaker)
                if (hand1 !== hand2) {
                    const winner = hand1 < hand2 ? player1 : player2;
                    const loser = hand1 < hand2 ? player2 : player1;

                    party.finish();
                    await this.partyRepository.save(party);

                    logger.info('Golden Score finished (lowest hand wins)', {
                        partyId: partyId,
                        winnerId: winner.userId,
                        loserId: loser.userId,
                        winnerHand: hand1 < hand2 ? hand1 : hand2,
                        loserHand: hand1 < hand2 ? hand2 : hand1,
                        finalScores: scores
                    });

                    // Archive game result
                    if (this.saveGameResult) {
                        try {
                            await this.saveGameResult.execute({
                                partyId,
                                winner: {
                                    userId: winner.userId,
                                    playerIndex: winner.playerIndex,
                                    finalScore: scores[winner.playerIndex] || 0
                                },
                                totalRounds: currentRound.roundNumber,
                                wasGoldenScore: true,
                                players: players,
                                gameState: currentGameState
                            });
                        } catch (archiveError) {
                            logger.error('Failed to archive Golden Score result', {
                                partyId,
                                error: archiveError.message
                            });
                        }
                    }

                    return {
                        success: true,
                        gameFinished: true,
                        goldenScoreResult: true,
                        winner: {
                            userId: winner.userId,
                            playerIndex: winner.playerIndex,
                            score: scores[winner.playerIndex] || 0
                        },
                        finalScores: scores,
                        eliminatedPlayers: [...eliminatedPlayers, loser].map(p => ({
                            userId: p.userId,
                            playerIndex: p.playerIndex,
                            score: scores[p.playerIndex] || 0
                        }))
                    };
                } else {
                    // Hands are tied - ZapZap caller was counteracted and loses
                    // Find who called ZapZap from round scores
                    const p1WasZapZapCaller = p1RoundScore?.is_zapzap_caller === 1;
                    const p2WasZapZapCaller = p2RoundScore?.is_zapzap_caller === 1;

                    // Determine winner: the player who did NOT call ZapZap wins (they counteracted)
                    // If neither called ZapZap (shouldn't happen in Golden Score ending), use score tiebreaker
                    let winner, loser;
                    if (p1WasZapZapCaller && !p2WasZapZapCaller) {
                        // Player 1 called ZapZap and was counteracted - Player 2 wins
                        winner = player2;
                        loser = player1;
                    } else if (p2WasZapZapCaller && !p1WasZapZapCaller) {
                        // Player 2 called ZapZap and was counteracted - Player 1 wins
                        winner = player1;
                        loser = player2;
                    } else {
                        // Fallback: use total score as tiebreaker (shouldn't happen normally)
                        const score1 = scores[player1.playerIndex] || 0;
                        const score2 = scores[player2.playerIndex] || 0;
                        if (score1 !== score2) {
                            winner = score1 < score2 ? player1 : player2;
                            loser = score1 < score2 ? player2 : player1;
                        } else {
                            // If both hand and score are tied, continue with another Golden Score round
                            logger.info('Golden Score tie - continuing with another round', {
                                partyId: partyId,
                                hand1,
                                hand2,
                                scores
                            });
                            // Fall through to create new round
                            winner = null;
                        }
                    }

                    if (winner) {
                        party.finish();
                        await this.partyRepository.save(party);

                        logger.info('Golden Score finished (hand tie, ZapZap caller loses)', {
                            partyId: partyId,
                            winnerId: winner.userId,
                            loserId: loser.userId,
                            hand1,
                            hand2,
                            p1WasZapZapCaller,
                            p2WasZapZapCaller,
                            finalScores: scores
                        });

                        // Archive game result
                        if (this.saveGameResult) {
                            try {
                                await this.saveGameResult.execute({
                                    partyId,
                                    winner: {
                                        userId: winner.userId,
                                        playerIndex: winner.playerIndex,
                                        finalScore: scores[winner.playerIndex] || 0
                                    },
                                    totalRounds: currentRound.roundNumber,
                                    wasGoldenScore: true,
                                    players: players,
                                    gameState: currentGameState
                                });
                            } catch (archiveError) {
                                logger.error('Failed to archive Golden Score result (tie)', {
                                    partyId,
                                    error: archiveError.message
                                });
                            }
                        }

                        return {
                            success: true,
                            gameFinished: true,
                            goldenScoreResult: true,
                            winner: {
                                userId: winner.userId,
                                playerIndex: winner.playerIndex,
                                score: scores[winner.playerIndex] || 0
                            },
                            finalScores: scores,
                            eliminatedPlayers: [...eliminatedPlayers, loser].map(p => ({
                                userId: p.userId,
                                playerIndex: p.playerIndex,
                                score: scores[p.playerIndex] || 0
                            }))
                        };
                    }
                }
            }

            // Check if entering Golden Score mode (exactly 2 players remaining)
            const enteringGoldenScore = activePlayers.length === 2 && !wasGoldenScore;
            const isGoldenScore = activePlayers.length === 2;

            if (enteringGoldenScore) {
                logger.info('Entering Golden Score mode', {
                    partyId: partyId,
                    players: activePlayers.map(p => ({ userId: p.userId, playerIndex: p.playerIndex })),
                    scores: scores
                });
            }

            // Create new round
            const newRoundNumber = currentRound.roundNumber + 1;
            const newRound = Round.create(partyId, newRoundNumber);

            // Initialize new deck with 54 cards
            const deck = Array.from({ length: 54 }, (_, i) => i);

            // Shuffle deck (Fisher-Yates)
            for (let i = deck.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [deck[i], deck[j]] = [deck[j], deck[i]];
            }

            // Initialize empty hands - cards will be dealt when starting player selects handSize
            const hands = {};
            for (let i = 0; i < players.length; i++) {
                hands[i] = [];
            }

            // Determine starting player - must be an active player
            // Start from last turn and find next active player
            let nextStartingPlayer = (currentGameState.currentTurn + 1) % players.length;
            while (eliminatedPlayerIndices.includes(nextStartingPlayer)) {
                nextStartingPlayer = (nextStartingPlayer + 1) % players.length;
            }

            // Create new game state preserving scores
            // Starting player must select hand size before playing
            const newGameState = currentGameState.with({
                deck: deck,
                hands: hands,
                currentTurn: nextStartingPlayer,
                currentAction: 'selectHandSize',
                roundNumber: newRoundNumber,
                lastCardsPlayed: [],
                cardsPlayed: [],
                discardPile: [],
                lastAction: null,
                isGoldenScore: isGoldenScore,
                eliminatedPlayers: eliminatedPlayerIndices,
                startingPlayer: nextStartingPlayer
                // scores are preserved from previous state
            });

            // Save new round
            await this.partyRepository.saveRound(newRound);

            // Save new game state
            await this.partyRepository.saveGameState(partyId, newGameState);

            // Update party with new round ID
            party.startNewRound(newRound.id);
            await this.partyRepository.save(party);

            logger.info('Next round started', {
                userId: userId,
                partyId: partyId,
                roundId: newRound.id,
                roundNumber: newRoundNumber,
                startingPlayer: nextStartingPlayer
            });

            return {
                success: true,
                gameFinished: false,
                round: {
                    id: newRound.id,
                    roundNumber: newRound.roundNumber,
                    status: newRound.status
                },
                startingPlayer: nextStartingPlayer,
                scores: scores,
                isGoldenScore: isGoldenScore,
                enteringGoldenScore: enteringGoldenScore,
                eliminatedPlayers: eliminatedPlayers.map(p => ({
                    userId: p.userId,
                    playerIndex: p.playerIndex,
                    score: scores[p.playerIndex] || 0
                })),
                activePlayers: activePlayers.map(p => ({
                    userId: p.userId,
                    playerIndex: p.playerIndex,
                    score: scores[p.playerIndex] || 0
                }))
            };
        } catch (error) {
            logger.error('Next round error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = NextRound;
