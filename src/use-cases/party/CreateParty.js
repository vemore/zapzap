/**
 * CreateParty Use Case
 * Creates a new party with specified settings
 */

const Party = require('../../domain/entities/Party');
const PartySettings = require('../../domain/value-objects/PartySettings');
const logger = require('../../../logger');

class CreateParty {
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
     * @param {Object} request - Party creation request
     * @param {string} request.ownerId - User ID of party owner
     * @param {string} request.name - Party name
     * @param {string} request.visibility - 'public' or 'private'
     * @param {Object} request.settings - Party settings
     * @param {number} request.settings.playerCount - Number of players (3-8)
     * @param {number} request.settings.handSize - Cards per hand (5-7)
     * @param {boolean} [request.settings.allowSpectators] - Allow spectators
     * @param {number} [request.settings.roundTimeLimit] - Time limit per round in seconds
     * @returns {Promise<Object>} Creation result with party
     */
    async execute({ ownerId, name, visibility, settings }) {
        try {
            // Validate input
            if (!ownerId || typeof ownerId !== 'string') {
                throw new Error('Owner ID is required');
            }

            if (!name || typeof name !== 'string') {
                throw new Error('Party name is required');
            }

            const trimmedName = name.trim();
            if (trimmedName.length < 3) {
                throw new Error('Party name must be at least 3 characters long');
            }

            if (trimmedName.length > 50) {
                throw new Error('Party name must not exceed 50 characters');
            }

            if (!visibility || !['public', 'private'].includes(visibility)) {
                throw new Error('Visibility must be either "public" or "private"');
            }

            if (!settings || typeof settings !== 'object') {
                throw new Error('Settings are required');
            }

            // Verify owner exists
            const owner = await this.userRepository.findById(ownerId);
            if (!owner) {
                throw new Error('Owner not found');
            }

            // Create party settings
            const partySettings = new PartySettings({
                playerCount: settings.playerCount,
                handSize: settings.handSize,
                allowSpectators: settings.allowSpectators || false,
                roundTimeLimit: settings.roundTimeLimit || 0
            });

            // Create party
            const party = Party.create(trimmedName, ownerId, visibility, partySettings);

            // Save party
            const savedParty = await this.partyRepository.save(party);

            logger.info('Party created successfully', {
                partyId: savedParty.id,
                name: savedParty.name,
                ownerId: savedParty.ownerId,
                visibility: savedParty.visibility
            });

            return {
                success: true,
                party: savedParty.toPublicObject()
            };
        } catch (error) {
            logger.error('Party creation error', {
                ownerId,
                name,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = CreateParty;
