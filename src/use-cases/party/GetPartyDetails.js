/**
 * GetPartyDetails Use Case
 * Retrieves detailed information about a party
 */

const logger = require('../../../logger');

class GetPartyDetails {
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
     * @param {Object} request - Details request
     * @param {string} request.partyId - Party ID
     * @param {string} [request.userId] - Optional user ID for permission checks
     * @returns {Promise<Object>} Party details
     */
    async execute({ partyId, userId }) {
        try {
            // Validate input
            if (!partyId || typeof partyId !== 'string') {
                throw new Error('Party ID is required');
            }

            // Find party
            const party = await this.partyRepository.findById(partyId);
            if (!party) {
                throw new Error('Party not found');
            }

            // If party is private, verify user is a member
            if (party.visibility === 'private' && userId) {
                const players = await this.partyRepository.getPartyPlayers(partyId);
                const isMember = players.some(p => p.userId === userId);

                if (!isMember) {
                    throw new Error('Access denied. Party is private.');
                }
            }

            // Get party players
            const partyPlayers = await this.partyRepository.getPartyPlayers(partyId);

            // Get user details for each player
            const playersWithDetails = await Promise.all(
                partyPlayers.map(async (player) => {
                    const user = await this.userRepository.findById(player.userId);
                    return {
                        id: player.id,
                        userId: player.userId,
                        username: user ? user.username : 'Unknown',
                        userType: user ? user.userType : 'human',
                        playerIndex: player.playerIndex,
                        joinedAt: player.joinedAt
                    };
                })
            );

            // Get current round if exists
            let currentRound = null;
            if (party.currentRoundId) {
                currentRound = await this.partyRepository.getRoundById(party.currentRoundId);
            }

            // Get game state if round is active
            let gameState = null;
            if (currentRound) {
                gameState = await this.partyRepository.getGameState(currentRound.id);
            }

            logger.debug('Retrieved party details', {
                partyId: party.id,
                playerCount: playersWithDetails.length,
                hasActiveRound: !!currentRound
            });

            return {
                success: true,
                party: {
                    ...party.toPublicObject(),
                    currentPlayers: playersWithDetails.length,
                    maxPlayers: party.settings.playerCount,
                    isFull: playersWithDetails.length >= party.settings.playerCount
                },
                players: playersWithDetails,
                currentRound: currentRound ? {
                    id: currentRound.id,
                    roundNumber: currentRound.roundNumber,
                    currentTurn: currentRound.currentTurn,
                    status: currentRound.status,
                    createdAt: currentRound.createdAt
                } : null,
                gameState: gameState ? gameState.toPublicObject() : null
            };
        } catch (error) {
            logger.error('Get party details error', {
                partyId,
                userId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = GetPartyDetails;
