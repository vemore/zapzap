/**
 * AdminDeleteParty Use Case
 * Deletes a party and all associated data (rounds, scores, game state)
 */

const logger = require('../../../logger');

class AdminDeleteParty {
    /**
     * @param {PartyRepository} partyRepository - Party repository
     * @param {UserRepository} userRepository - User repository
     */
    constructor(partyRepository, userRepository) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} params
     * @param {string} params.adminUserId - Admin performing the action
     * @param {string} params.partyId - Party to delete
     * @returns {Promise<Object>} Result
     */
    async execute({ adminUserId, partyId }) {
        try {
            // Validate admin
            const admin = await this.userRepository.findById(adminUserId);
            if (!admin || !admin.isAdminUser()) {
                throw new Error('Admin access required');
            }

            const party = await this.partyRepository.findById(partyId);
            if (!party) {
                throw new Error('Party not found');
            }

            const partyName = party.name;

            // Delete the party (CASCADE will handle related records:
            // party_players, rounds, game_state, round_scores, game_results, player_game_results)
            await this.partyRepository.delete(partyId);

            logger.info('Party deleted by admin', {
                adminId: adminUserId,
                partyId,
                partyName
            });

            return {
                success: true,
                partyId,
                partyName,
                deleted: true
            };
        } catch (error) {
            logger.error('Failed to delete party', {
                adminUserId,
                partyId,
                error: error.message
            });
            throw error;
        }
    }
}

module.exports = AdminDeleteParty;
