/**
 * LeaveParty Use Case
 * Allows a user to leave a party
 */

const logger = require('../../../logger');

class LeaveParty {
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
     * @param {Object} request - Leave request
     * @param {string} request.userId - User ID attempting to leave
     * @param {string} request.partyId - Party ID
     * @returns {Promise<Object>} Leave result
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

            // Check if user is in party
            const players = await this.partyRepository.getPartyPlayers(partyId);
            const player = players.find(p => p.userId === userId);

            if (!player) {
                throw new Error('User is not in this party');
            }

            // Cannot leave during active game
            if (party.status === 'playing') {
                throw new Error('Cannot leave party during active game');
            }

            // If user is owner and party has other players, transfer ownership
            if (party.ownerId === userId) {
                if (players.length > 1) {
                    // Transfer ownership to next player
                    const nextOwner = players.find(p => p.userId !== userId);
                    party.updateOwner(nextOwner.userId);
                    await this.partyRepository.save(party);

                    logger.info('Party ownership transferred', {
                        partyId: party.id,
                        fromUserId: userId,
                        toUserId: nextOwner.userId
                    });
                } else {
                    // Last player leaving - delete party
                    await this.partyRepository.delete(partyId);

                    logger.info('Party deleted (last player left)', {
                        partyId: partyId,
                        userId: userId
                    });

                    return {
                        success: true,
                        partyDeleted: true
                    };
                }
            }

            // Remove player from party
            await this.partyRepository.removePlayer(partyId, userId);

            logger.info('User left party', {
                userId: userId,
                username: user.username,
                partyId: partyId,
                partyName: party.name
            });

            return {
                success: true,
                partyDeleted: false
            };
        } catch (error) {
            logger.error('Leave party error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = LeaveParty;
