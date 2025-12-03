/**
 * GetGameState Use Case
 * Retrieves current game state for a player
 */

const logger = require('../../../logger');

class GetGameState {
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
     * @param {Object} request - Get state request
     * @param {string} request.userId - User ID
     * @param {string} request.partyId - Party ID
     * @returns {Promise<Object>} Game state result
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

            // Get player
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);
            if (!player) {
                throw new Error('User is not in this party');
            }

            // Fetch usernames for all players
            const playersWithNames = await Promise.all(
                players.map(async (p) => {
                    const playerUser = await this.userRepository.findById(p.userId);
                    return {
                        playerIndex: p.playerIndex,
                        userId: p.userId,
                        username: playerUser?.username || `Player ${p.playerIndex + 1}`
                    };
                })
            );

            // Get party details
            const partyDetails = {
                id: party.id,
                name: party.name,
                status: party.status,
                currentRoundId: party.currentRoundId
            };

            // If party is not playing, return basic info
            if (party.status !== 'playing') {
                return {
                    success: true,
                    party: partyDetails,
                    players: playersWithNames,
                    round: null,
                    gameState: null
                };
            }

            // Get current round
            if (!party.currentRoundId) {
                return {
                    success: true,
                    party: partyDetails,
                    players: playersWithNames,
                    round: null,
                    gameState: null
                };
            }

            const round = await this.partyRepository.getRoundById(party.currentRoundId);
            if (!round) {
                throw new Error('Round not found');
            }

            // Get game state
            const gameState = await this.partyRepository.getGameState(partyId);

            // Prepare player-specific view
            const playerHand = gameState ? (gameState.hands[player.playerIndex] || []) : [];
            const otherPlayersHandSizes = {};

            if (gameState) {
                for (const p of players) {
                    if (p.playerIndex !== player.playerIndex) {
                        otherPlayersHandSizes[p.playerIndex] = (gameState.hands[p.playerIndex] || []).length;
                    }
                }
            }

            logger.debug('Game state retrieved', {
                userId: userId,
                partyId: partyId,
                roundId: round.id,
                playerIndex: player.playerIndex
            });

            return {
                success: true,
                party: partyDetails,
                players: playersWithNames,
                round: {
                    id: round.id,
                    roundNumber: round.roundNumber,
                    status: round.status
                },
                gameState: gameState ? {
                    currentTurn: gameState.currentTurn,
                    currentAction: gameState.currentAction,
                    deckSize: gameState.deck.length,
                    lastCardsPlayed: gameState.lastCardsPlayed,
                    cardsPlayed: gameState.cardsPlayed,
                    scores: gameState.scores,
                    playerHand: playerHand,
                    otherPlayersHandSizes: otherPlayersHandSizes,
                    lastAction: gameState.lastAction
                } : null
            };
        } catch (error) {
            logger.error('Get game state error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetGameState;
