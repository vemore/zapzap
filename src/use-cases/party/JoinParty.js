/**
 * JoinParty Use Case
 * Allows a user to join a party via invite code or party ID
 */

const PartyPlayer = require('../../domain/entities/PartyPlayer');
const logger = require('../../../logger');

class JoinParty {
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
     * @param {Object} request - Join request
     * @param {string} request.userId - User ID attempting to join
     * @param {string} [request.partyId] - Party ID (for public parties)
     * @param {string} [request.inviteCode] - Invite code (for private parties)
     * @returns {Promise<Object>} Join result with party and player info
     */
    async execute({ userId, partyId, inviteCode }) {
        try {
            // Validate input
            if (!userId || typeof userId !== 'string') {
                throw new Error('User ID is required');
            }

            if (!partyId && !inviteCode) {
                throw new Error('Either party ID or invite code is required');
            }

            // Verify user exists
            const user = await this.userRepository.findById(userId);
            if (!user) {
                throw new Error('User not found');
            }

            // Find party
            let party;
            if (inviteCode) {
                party = await this.partyRepository.findByInviteCode(inviteCode);
                if (!party) {
                    throw new Error('Invalid invite code');
                }
            } else {
                party = await this.partyRepository.findById(partyId);
                if (!party) {
                    throw new Error('Party not found');
                }

                // Check if party is public
                if (party.visibility !== 'public') {
                    throw new Error('Party is private. Use invite code to join.');
                }
            }

            // Check if party is finished
            if (party.status === 'finished') {
                throw new Error('Cannot join finished party');
            }

            // Check if party is full
            const players = await this.partyRepository.getPartyPlayers(party.id);
            if (players.length >= party.settings.playerCount) {
                throw new Error('Party is full');
            }

            // Check if user is already in party
            const existingPlayer = players.find(p => p.userId === userId);
            if (existingPlayer) {
                throw new Error('User is already in this party');
            }

            // Determine player index
            const playerIndex = players.length;

            // Create party player
            const partyPlayer = PartyPlayer.create(party.id, userId, playerIndex);

            // Add player to party
            const savedPlayer = await this.partyRepository.addPlayer(partyPlayer);

            logger.info('User joined party', {
                userId: userId,
                username: user.username,
                partyId: party.id,
                partyName: party.name,
                playerIndex: playerIndex
            });

            return {
                success: true,
                party: party.toPublicObject(),
                player: {
                    id: savedPlayer.id,
                    userId: savedPlayer.userId,
                    playerIndex: savedPlayer.playerIndex,
                    joinedAt: savedPlayer.joinedAt
                }
            };
        } catch (error) {
            logger.error('Join party error', {
                userId,
                partyId,
                inviteCode,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = JoinParty;
