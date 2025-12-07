/**
 * ListAllParties Use Case
 * Lists all parties (including private ones) for admin management
 */

const logger = require('../../../logger');

class ListAllParties {
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
     * @param {string} [params.status] - Filter by status (waiting, playing, finished)
     * @param {number} [params.limit=50] - Maximum number of results
     * @param {number} [params.offset=0] - Offset for pagination
     * @returns {Promise<Object>} Parties list with pagination info
     */
    async execute({ status = null, limit = 50, offset = 0 }) {
        try {
            const parties = await this.partyRepository.findAllParties(status, limit, offset);
            const total = await this.partyRepository.countAllParties(status);

            // Enrich with owner info and player count
            const enrichedParties = await Promise.all(parties.map(async (party) => {
                const owner = await this.userRepository.findById(party.ownerId);
                const playerCount = await this.partyRepository.getPlayerCount(party.id);

                return {
                    id: party.id,
                    name: party.name,
                    ownerId: party.ownerId,
                    ownerUsername: owner ? owner.username : 'Unknown',
                    inviteCode: party.inviteCode,
                    visibility: party.visibility,
                    status: party.status,
                    settings: party.settings,
                    currentRoundId: party.currentRoundId,
                    playerCount,
                    createdAt: party.createdAt,
                    updatedAt: party.updatedAt
                };
            }));

            logger.debug('Admin listed parties', { count: parties.length, total, status });

            return {
                success: true,
                parties: enrichedParties,
                pagination: { total, limit, offset }
            };
        } catch (error) {
            logger.error('Failed to list parties', { error: error.message });
            throw new Error(`Failed to list parties: ${error.message}`);
        }
    }
}

module.exports = ListAllParties;
