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
     */
    constructor(partyRepository, userRepository) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
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
                // Golden Score round finished - winner is player with lowest score
                const [player1, player2] = activePlayers;
                const score1 = scores[player1.playerIndex] || 0;
                const score2 = scores[player2.playerIndex] || 0;

                // Determine winner (lowest score wins, or if tie, neither is eliminated yet)
                if (score1 !== score2) {
                    const winner = score1 < score2 ? player1 : player2;
                    const loser = score1 < score2 ? player2 : player1;

                    party.finish();
                    await this.partyRepository.save(party);

                    logger.info('Golden Score finished', {
                        partyId: partyId,
                        winnerId: winner.userId,
                        loserId: loser.userId,
                        finalScores: scores
                    });

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
                // If scores are tied, continue with another Golden Score round
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

            // Deal cards only to active players (eliminated players get empty hands)
            const handSize = party.settings.handSize || 10;
            const hands = {};

            for (let i = 0; i < players.length; i++) {
                if (eliminatedPlayerIndices.includes(i)) {
                    // Eliminated players get no cards
                    hands[i] = [];
                } else {
                    // Active players get cards
                    hands[i] = deck.splice(0, handSize);
                }
            }

            // Flip first card from deck to discard pile
            const firstDiscardCard = deck.pop();

            // Determine starting player - must be an active player
            // Start from last turn and find next active player
            let nextStartingPlayer = (currentGameState.currentTurn + 1) % players.length;
            while (eliminatedPlayerIndices.includes(nextStartingPlayer)) {
                nextStartingPlayer = (nextStartingPlayer + 1) % players.length;
            }

            // Create new game state preserving scores
            const newGameState = currentGameState.with({
                deck: deck,
                hands: hands,
                currentTurn: nextStartingPlayer,
                currentAction: 'play',
                roundNumber: newRoundNumber,
                lastCardsPlayed: [firstDiscardCard],
                cardsPlayed: [],
                lastAction: null,
                isGoldenScore: isGoldenScore,
                eliminatedPlayers: eliminatedPlayerIndices
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
