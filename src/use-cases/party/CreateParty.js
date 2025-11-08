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
     * @param {JoinParty} joinPartyUseCase - JoinParty use case for adding bots
     */
    constructor(partyRepository, userRepository, joinPartyUseCase) {
        this.partyRepository = partyRepository;
        this.userRepository = userRepository;
        this.joinPartyUseCase = joinPartyUseCase;
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
     * @param {string[]} [request.botIds] - Array of bot user IDs to auto-join
     * @returns {Promise<Object>} Creation result with party
     */
    async execute({ ownerId, name, visibility, settings, botIds = [] }) {
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

            // Validate botIds if provided
            if (botIds && botIds.length > 0) {
                // Check botIds is array
                if (!Array.isArray(botIds)) {
                    throw new Error('botIds must be an array');
                }

                // Check for duplicates
                const uniqueBotIds = new Set(botIds);
                if (uniqueBotIds.size !== botIds.length) {
                    throw new Error('Duplicate bot IDs detected');
                }

                // Check total players doesn't exceed player count (owner + bots)
                if (botIds.length + 1 > partySettings.playerCount) {
                    throw new Error(`Total players (${botIds.length + 1}) exceeds party player count (${partySettings.playerCount})`);
                }

                // Verify all bot IDs exist and are actual bots
                for (const botId of botIds) {
                    const bot = await this.userRepository.findById(botId);
                    if (!bot) {
                        throw new Error(`Bot with ID ${botId} not found`);
                    }
                    if (!bot.isBot()) {
                        throw new Error(`User ${botId} is not a bot`);
                    }
                }
            }

            // Create party
            const party = Party.create(trimmedName, ownerId, visibility, partySettings);

            // Save party
            const savedParty = await this.partyRepository.save(party);

            logger.info('Party created successfully', {
                partyId: savedParty.id,
                name: savedParty.name,
                ownerId: savedParty.ownerId,
                visibility: savedParty.visibility,
                botCount: botIds.length
            });

            // Auto-join bots if provided
            if (botIds && botIds.length > 0 && this.joinPartyUseCase) {
                logger.info('Auto-joining bots to party', {
                    partyId: savedParty.id,
                    botIds
                });

                const joinedBots = [];
                for (const botId of botIds) {
                    try {
                        await this.joinPartyUseCase.execute({
                            userId: botId,
                            partyId: savedParty.id
                        });
                        joinedBots.push(botId);
                        logger.info('Bot joined party', { botId, partyId: savedParty.id });
                    } catch (error) {
                        logger.error('Failed to auto-join bot', {
                            botId,
                            partyId: savedParty.id,
                            error: error.message
                        });
                        // Continue with other bots even if one fails
                    }
                }

                // Reload party to get updated player list
                const updatedParty = await this.partyRepository.findById(savedParty.id);

                // Ensure party stays in 'waiting' status even if all slots filled
                // (User requirement: always wait for manual start)
                if (updatedParty.status === 'playing') {
                    updatedParty.status = 'waiting';
                    await this.partyRepository.save(updatedParty);
                }

                logger.info('Bots auto-joined successfully', {
                    partyId: savedParty.id,
                    requestedCount: botIds.length,
                    joinedCount: joinedBots.length
                });

                return {
                    success: true,
                    party: updatedParty.toPublicObject(),
                    botsJoined: joinedBots.length
                };
            }

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
