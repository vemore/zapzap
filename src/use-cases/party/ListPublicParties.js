/**
 * ListPublicParties Use Case
 * Lists all public parties that are available to join
 */

const logger = require('../../../logger');

class ListPublicParties {
    /**
     * @param {IPartyRepository} partyRepository - Party repository
     */
    constructor(partyRepository) {
        this.partyRepository = partyRepository;
    }

    /**
     * Execute the use case
     * @param {Object} [request] - List request options
     * @param {string} [request.status] - Filter by status ('waiting', 'playing', 'finished')
     * @param {number} [request.limit] - Maximum number of results
     * @param {number} [request.offset] - Offset for pagination
     * @returns {Promise<Object>} List result with parties
     */
    async execute({ status, limit = 50, offset = 0 } = {}) {
        try {
            // Validate input
            if (status && !['waiting', 'playing', 'finished'].includes(status)) {
                throw new Error('Invalid status filter');
            }

            if (typeof limit !== 'number' || limit < 1 || limit > 100) {
                throw new Error('Limit must be between 1 and 100');
            }

            if (typeof offset !== 'number' || offset < 0) {
                throw new Error('Offset must be non-negative');
            }

            // Get public parties
            const parties = await this.partyRepository.findPublicParties(status, limit, offset);

            // For each party, get player count
            const partiesWithDetails = await Promise.all(
                parties.map(async (party) => {
                    const players = await this.partyRepository.getPartyPlayers(party.id);

                    return {
                        ...party.toPublicObject(),
                        currentPlayers: players.length,
                        maxPlayers: party.settings.playerCount,
                        isFull: players.length >= party.settings.playerCount
                    };
                })
            );

            logger.debug('Listed public parties', {
                count: partiesWithDetails.length,
                status: status || 'all',
                limit,
                offset
            });

            return {
                success: true,
                parties: partiesWithDetails,
                pagination: {
                    limit,
                    offset,
                    count: partiesWithDetails.length
                }
            };
        } catch (error) {
            logger.error('List public parties error', {
                status,
                limit,
                offset,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = ListPublicParties;
