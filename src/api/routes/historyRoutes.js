/**
 * History Routes
 * API endpoints for game history
 */

const express = require('express');
const { createAuthMiddleware } = require('../middleware/authMiddleware');

/**
 * Create history router
 * @param {DIContainer} container - DI container
 * @returns {Router} Express router
 */
function createHistoryRoutes(container) {
    const router = express.Router();

    // Create auth middleware from container
    const validateToken = container.resolve('validateToken');
    const authMiddleware = createAuthMiddleware(validateToken);

    /**
     * GET /api/history
     * Get user's finished games history
     */
    router.get('/', authMiddleware, async (req, res) => {
        try {
            const getGameHistory = container.resolve('getGameHistory');
            const { limit = 20, offset = 0 } = req.query;

            const result = await getGameHistory.execute({
                userId: req.user.id,
                publicOnly: false,
                limit: parseInt(limit, 10),
                offset: parseInt(offset, 10)
            });

            res.json(result);
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * GET /api/history/public
     * Get public finished games history
     */
    router.get('/public', async (req, res) => {
        try {
            const getGameHistory = container.resolve('getGameHistory');
            const { limit = 20, offset = 0 } = req.query;

            const result = await getGameHistory.execute({
                publicOnly: true,
                limit: parseInt(limit, 10),
                offset: parseInt(offset, 10)
            });

            res.json(result);
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * GET /api/history/:partyId
     * Get detailed information about a finished game
     */
    router.get('/:partyId', authMiddleware, async (req, res) => {
        try {
            const getGameDetails = container.resolve('getGameDetails');
            const { partyId } = req.params;

            const result = await getGameDetails.execute({
                partyId,
                userId: req.user.id
            });

            res.json(result);
        } catch (error) {
            if (error.message === 'Party not found' || error.message === 'Game result not found - game may not be finished') {
                res.status(404).json({ error: error.message });
            } else {
                res.status(500).json({ error: error.message });
            }
        }
    });

    return router;
}

module.exports = createHistoryRoutes;
