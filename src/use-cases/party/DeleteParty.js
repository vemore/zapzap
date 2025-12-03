/**
 * DeleteParty Use Case
 * Allows a user to delete a party if they are the owner or the only human player
 */

const logger = require('../../../logger');

class DeleteParty {
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
     * @param {Object} request - Delete request
     * @param {string} request.userId - User ID attempting to delete
     * @param {string} request.partyId - Party ID to delete
     * @returns {Promise<Object>} Delete result
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

            // Get all players in the party
            const players = await this.partyRepository.getPartyPlayers(partyId);

            // Check if user is in the party
            const userPlayer = players.find(p => p.userId === userId);
            if (!userPlayer) {
                throw new Error('User is not in this party');
            }

            // Check authorization: user must be owner OR the only human player
            const isOwner = party.ownerId === userId;

            // Count human players in the party
            let humanPlayers = [];
            for (const player of players) {
                const playerUser = await this.userRepository.findById(player.userId);
                if (playerUser && playerUser.isHuman()) {
                    humanPlayers.push(player);
                }
            }

            const isOnlyHuman = humanPlayers.length === 1 && humanPlayers[0].userId === userId;

            if (!isOwner && !isOnlyHuman) {
                throw new Error('Only the party owner or the only human player can delete the party');
            }

            // Cannot delete during active game (unless forced by being only human)
            if (party.status === 'playing' && !isOnlyHuman) {
                throw new Error('Cannot delete party during active game');
            }

            // Delete the party (cascade deletes handle players, rounds, game state)
            await this.partyRepository.delete(partyId);

            logger.info('Party deleted', {
                partyId: partyId,
                partyName: party.name,
                deletedBy: userId,
                deletedByUsername: user.username,
                wasOwner: isOwner,
                wasOnlyHuman: isOnlyHuman
            });

            return {
                success: true,
                deletedPartyId: partyId,
                deletedPartyName: party.name
            };
        } catch (error) {
            logger.error('Delete party error', {
                userId,
                partyId,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = DeleteParty;
