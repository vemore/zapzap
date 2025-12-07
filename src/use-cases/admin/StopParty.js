/**
 * StopParty Use Case
 * Forces a party to stop immediately (status -> finished)
 */

const logger = require('../../../logger');

class StopParty {
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
     * @param {string} params.partyId - Party to stop
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

            // Can only stop parties that are not already finished
            if (party.status === 'finished') {
                throw new Error('Party is already finished');
            }

            // Update party status to finished
            party.finish();
            await this.partyRepository.save(party);

            logger.info('Party stopped by admin', {
                adminId: adminUserId,
                partyId,
                partyName: party.name,
                previousStatus: party.status
            });

            return {
                success: true,
                partyId,
                partyName: party.name,
                stopped: true
            };
        } catch (error) {
            logger.error('Failed to stop party', {
                adminUserId,
                partyId,
                error: error.message
            });
            throw error;
        }
    }
}

module.exports = StopParty;
