/**
 * Admin Routes
 * Routes for admin panel operations
 */

const express = require('express');
const { createAuthMiddleware } = require('../middleware/authMiddleware');
const { createAdminMiddleware } = require('../middleware/adminMiddleware');
const logger = require('../../../logger');

/**
 * Create admin routes
 * @param {DIContainer} container - Dependency injection container
 * @returns {Router} Express router
 */
function createAdminRoutes(container) {
    const router = express.Router();

    const validateToken = container.resolve('validateToken');
    const userRepository = container.resolve('userRepository');

    const authMiddleware = createAuthMiddleware(validateToken);
    const adminMiddleware = createAdminMiddleware(userRepository);

    // All admin routes require authentication + admin privileges
    router.use(authMiddleware);
    router.use(adminMiddleware);

    // ============================================
    // USER MANAGEMENT
    // ============================================

    /**
     * GET /api/admin/users
     * List all human users with stats
     */
    router.get('/users', async (req, res) => {
        try {
            const listUsers = container.resolve('listUsers');
            const { limit = 50, offset = 0 } = req.query;

            const result = await listUsers.execute({
                limit: parseInt(limit, 10),
                offset: parseInt(offset, 10)
            });

            res.json(result);
        } catch (error) {
            logger.error('Error listing users', { error: error.message });
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * DELETE /api/admin/users/:userId
     * Delete a user
     */
    router.delete('/users/:userId', async (req, res) => {
        try {
            const deleteUser = container.resolve('deleteUser');
            const { userId } = req.params;

            const result = await deleteUser.execute({
                adminUserId: req.user.id,
                targetUserId: userId
            });

            res.json(result);
        } catch (error) {
            logger.error('Error deleting user', { userId: req.params.userId, error: error.message });
            const statusCode = error.message.includes('not found') ? 404 :
                             error.message.includes('Cannot delete') ? 400 : 500;
            res.status(statusCode).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /api/admin/users/:userId/admin
     * Grant or revoke admin rights
     */
    router.post('/users/:userId/admin', async (req, res) => {
        try {
            const setUserAdmin = container.resolve('setUserAdmin');
            const { userId } = req.params;
            const { isAdmin } = req.body;

            if (typeof isAdmin !== 'boolean') {
                return res.status(400).json({
                    success: false,
                    error: 'isAdmin must be a boolean'
                });
            }

            const result = await setUserAdmin.execute({
                adminUserId: req.user.id,
                targetUserId: userId,
                isAdmin
            });

            res.json(result);
        } catch (error) {
            logger.error('Error setting admin status', { userId: req.params.userId, error: error.message });
            const statusCode = error.message.includes('not found') ? 404 :
                             error.message.includes('Cannot') ? 400 : 500;
            res.status(statusCode).json({
                success: false,
                error: error.message
            });
        }
    });

    // ============================================
    // PARTY MANAGEMENT
    // ============================================

    /**
     * GET /api/admin/parties
     * List all parties
     */
    router.get('/parties', async (req, res) => {
        try {
            const listAllParties = container.resolve('listAllParties');
            const { status, limit = 50, offset = 0 } = req.query;

            const result = await listAllParties.execute({
                status: status || null,
                limit: parseInt(limit, 10),
                offset: parseInt(offset, 10)
            });

            res.json(result);
        } catch (error) {
            logger.error('Error listing parties', { error: error.message });
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * POST /api/admin/parties/:partyId/stop
     * Force stop a party
     */
    router.post('/parties/:partyId/stop', async (req, res) => {
        try {
            const stopParty = container.resolve('stopParty');
            const { partyId } = req.params;

            const result = await stopParty.execute({
                adminUserId: req.user.id,
                partyId
            });

            res.json(result);
        } catch (error) {
            logger.error('Error stopping party', { partyId: req.params.partyId, error: error.message });
            const statusCode = error.message.includes('not found') ? 404 :
                             error.message.includes('already finished') ? 400 : 500;
            res.status(statusCode).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * DELETE /api/admin/parties/:partyId
     * Delete a party
     */
    router.delete('/parties/:partyId', async (req, res) => {
        try {
            const adminDeleteParty = container.resolve('adminDeleteParty');
            const { partyId } = req.params;

            const result = await adminDeleteParty.execute({
                adminUserId: req.user.id,
                partyId
            });

            res.json(result);
        } catch (error) {
            logger.error('Error deleting party', { partyId: req.params.partyId, error: error.message });
            const statusCode = error.message.includes('not found') ? 404 : 500;
            res.status(statusCode).json({
                success: false,
                error: error.message
            });
        }
    });

    // ============================================
    // STATISTICS
    // ============================================

    /**
     * GET /api/admin/statistics
     * Get platform statistics
     */
    router.get('/statistics', async (req, res) => {
        try {
            const getAdminStatistics = container.resolve('getAdminStatistics');

            const result = await getAdminStatistics.execute();

            res.json(result);
        } catch (error) {
            logger.error('Error getting statistics', { error: error.message });
            res.status(500).json({
                success: false,
                error: error.message
            });
        }
    });

    return router;
}

module.exports = createAdminRoutes;
