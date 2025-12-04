/**
 * Party Routes
 * Handles party management operations
 */

const express = require('express');
const logger = require('../../../logger');

/**
 * Create party router
 * @param {DIContainer} container - DI container
 * @param {Function} authMiddleware - Authentication middleware
 * @param {Function} optionalAuthMiddleware - Optional authentication middleware
 * @param {EventEmitter} emitter - Event emitter for SSE
 * @returns {express.Router}
 */
function createPartyRouter(container, authMiddleware, optionalAuthMiddleware, emitter) {
    const router = express.Router();

    const createParty = container.resolve('createParty');
    const joinParty = container.resolve('joinParty');
    const leaveParty = container.resolve('leaveParty');
    const startParty = container.resolve('startParty');
    const listPublicParties = container.resolve('listPublicParties');
    const getPartyDetails = container.resolve('getPartyDetails');
    const deleteParty = container.resolve('deleteParty');

    /**
     * POST /api/party
     * Create a new party
     * Body: { name, visibility, settings, botIds? }
     */
    router.post('/', authMiddleware, async (req, res) => {
        try {
            const { name, visibility, settings, botIds } = req.body;

            if (!name) {
                return res.status(400).json({
                    error: 'Party name is required',
                    code: 'MISSING_PARTY_NAME'
                });
            }

            const result = await createParty.execute({
                ownerId: req.user.id,
                name,
                visibility: visibility || 'public',
                settings: settings || {},
                botIds: botIds || []
            });

            logger.info('Party created', {
                userId: req.user.id,
                partyId: result.party.id,
                partyName: result.party.name,
                botCount: botIds?.length || 0,
                botsJoined: result.botsJoined || 0
            });

            res.status(201).json({
                success: true,
                party: {
                    id: result.party.id,
                    name: result.party.name,
                    ownerId: result.party.ownerId,
                    inviteCode: result.party.inviteCode,
                    visibility: result.party.visibility,
                    status: result.party.status,
                    settings: result.party.settings,
                    createdAt: result.party.createdAt
                },
                botsJoined: result.botsJoined || 0
            });
        } catch (error) {
            logger.error('Create party error', {
                error: error.message,
                userId: req.user.id
            });

            res.status(500).json({
                error: 'Failed to create party',
                code: 'CREATE_PARTY_ERROR',
                details: error.message
            });
        }
    });

    /**
     * GET /api/party
     * Get list of public parties
     */
    router.get('/', optionalAuthMiddleware, async (req, res) => {
        try {
            const { status, limit, offset } = req.query;

            const result = await listPublicParties.execute({
                status: status || null,
                limit: parseInt(limit) || 50,
                offset: parseInt(offset) || 0,
                userId: req.user?.id || null
            });

            res.json({
                success: true,
                parties: result.parties.map(p => ({
                    id: p.id,
                    name: p.name,
                    ownerId: p.ownerId,
                    inviteCode: p.inviteCode,
                    status: p.status,
                    playerCount: p.currentPlayers || 0,
                    maxPlayers: p.maxPlayers,
                    isMember: p.isMember || false,
                    createdAt: p.createdAt
                })),
                total: result.total,
                limit: result.limit,
                offset: result.offset
            });
        } catch (error) {
            logger.error('Get public parties error', {
                error: error.message
            });

            res.status(500).json({
                error: 'Failed to get parties',
                code: 'GET_PARTIES_ERROR',
                details: error.message
            });
        }
    });

    /**
     * GET /api/party/:partyId
     * Get party details
     */
    router.get('/:partyId', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await getPartyDetails.execute({
                userId: req.user.id,
                partyId
            });

            res.json({
                success: true,
                party: {
                    id: result.party.id,
                    name: result.party.name,
                    ownerId: result.party.ownerId,
                    inviteCode: result.party.inviteCode,
                    visibility: result.party.visibility,
                    status: result.party.status,
                    settings: result.party.settings,
                    currentRoundId: result.party.currentRoundId,
                    createdAt: result.party.createdAt,
                    updatedAt: result.party.updatedAt
                },
                players: result.players.map(p => ({
                    id: p.id,
                    userId: p.userId,
                    username: p.username,
                    userType: p.userType,
                    botDifficulty: p.botDifficulty,
                    playerIndex: p.playerIndex,
                    joinedAt: p.joinedAt
                })),
                isOwner: result.isOwner,
                userPlayerIndex: result.userPlayerIndex
            });
        } catch (error) {
            logger.error('Get party details error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            res.status(500).json({
                error: 'Failed to get party details',
                code: 'GET_PARTY_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/party/:partyId/join
     * Join a party
     */
    router.post('/:partyId/join', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;
            const { inviteCode } = req.body;

            const result = await joinParty.execute({
                userId: req.user.id,
                partyId,
                inviteCode
            });

            logger.info('User joined party', {
                userId: req.user.id,
                partyId: result.party.id,
                playerIndex: result.playerIndex
            });

            // Emit SSE event for real-time updates
            if (emitter) {
                emitter.emit('event', {
                    partyId,
                    userId: req.user.id,
                    action: 'playerJoined',
                    playerIndex: result.playerIndex
                });
            }

            res.json({
                success: true,
                party: {
                    id: result.party.id,
                    name: result.party.name,
                    status: result.party.status
                },
                playerIndex: result.playerIndex
            });
        } catch (error) {
            logger.error('Join party error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found' || error.message === 'Party does not exist') {
                return res.status(404).json({
                    error: 'Party not found',
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message.includes('full')) {
                return res.status(409).json({
                    error: error.message,
                    code: 'PARTY_FULL'
                });
            }

            if (error.message.includes('already in party')) {
                return res.status(409).json({
                    error: error.message,
                    code: 'ALREADY_IN_PARTY'
                });
            }

            if (error.message.includes('already started')) {
                return res.status(409).json({
                    error: error.message,
                    code: 'PARTY_STARTED'
                });
            }

            res.status(500).json({
                error: 'Failed to join party',
                code: 'JOIN_PARTY_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/party/:partyId/leave
     * Leave a party
     */
    router.post('/:partyId/leave', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await leaveParty.execute({
                userId: req.user.id,
                partyId
            });

            logger.info('User left party', {
                userId: req.user.id,
                partyId
            });

            // Emit SSE event for real-time updates
            if (emitter) {
                emitter.emit('event', {
                    partyId,
                    userId: req.user.id,
                    action: 'playerLeft',
                    newOwner: result.newOwner || null
                });
            }

            res.json({
                success: true,
                message: 'Left party successfully',
                newOwner: result.newOwner || null
            });
        } catch (error) {
            logger.error('Leave party error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            res.status(500).json({
                error: 'Failed to leave party',
                code: 'LEAVE_PARTY_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/party/:partyId/start
     * Start a party
     */
    router.post('/:partyId/start', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await startParty.execute({
                userId: req.user.id,
                partyId
            });

            logger.info('Party started', {
                userId: req.user.id,
                partyId: result.party.id,
                roundId: result.round.id
            });

            // Emit SSE event for real-time updates
            if (emitter) {
                emitter.emit('event', {
                    partyId,
                    userId: req.user.id,
                    action: 'partyStarted',
                    roundId: result.round.id
                });
            }

            res.json({
                success: true,
                party: {
                    id: result.party.id,
                    status: result.party.status,
                    currentRoundId: result.party.currentRoundId
                },
                round: {
                    id: result.round.id,
                    roundNumber: result.round.roundNumber,
                    status: result.round.status
                }
            });
        } catch (error) {
            logger.error('Start party error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'Only the party owner can start the game') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_OWNER'
                });
            }

            if (error.message.includes('already playing')) {
                return res.status(409).json({
                    error: error.message,
                    code: 'PARTY_ALREADY_PLAYING'
                });
            }

            res.status(500).json({
                error: 'Failed to start party',
                code: 'START_PARTY_ERROR',
                details: error.message
            });
        }
    });

    /**
     * DELETE /api/party/:partyId
     * Delete a party (owner or only human player can delete)
     */
    router.delete('/:partyId', authMiddleware, async (req, res) => {
        try {
            const { partyId } = req.params;

            const result = await deleteParty.execute({
                userId: req.user.id,
                partyId
            });

            logger.info('Party deleted via API', {
                userId: req.user.id,
                partyId,
                partyName: result.deletedPartyName
            });

            // Emit SSE event for real-time updates
            if (emitter) {
                emitter.emit('event', {
                    partyId,
                    userId: req.user.id,
                    action: 'partyDeleted'
                });
            }

            res.json({
                success: true,
                message: 'Party deleted successfully',
                deletedPartyId: result.deletedPartyId,
                deletedPartyName: result.deletedPartyName
            });
        } catch (error) {
            logger.error('Delete party error', {
                error: error.message,
                userId: req.user.id,
                partyId: req.params.partyId
            });

            if (error.message === 'Party not found') {
                return res.status(404).json({
                    error: error.message,
                    code: 'PARTY_NOT_FOUND'
                });
            }

            if (error.message === 'User is not in this party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_IN_PARTY'
                });
            }

            if (error.message === 'Only the party owner or the only human player can delete the party') {
                return res.status(403).json({
                    error: error.message,
                    code: 'NOT_AUTHORIZED'
                });
            }

            if (error.message === 'Cannot delete party during active game') {
                return res.status(409).json({
                    error: error.message,
                    code: 'PARTY_PLAYING'
                });
            }

            res.status(500).json({
                error: 'Failed to delete party',
                code: 'DELETE_PARTY_ERROR',
                details: error.message
            });
        }
    });

    return router;
}

module.exports = createPartyRouter;
