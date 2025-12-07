/**
 * Stats Routes
 * API endpoints for statistics and leaderboard
 */

const express = require('express');
const { createAuthMiddleware } = require('../middleware/authMiddleware');

/**
 * Create stats router
 * @param {DIContainer} container - DI container
 * @returns {Router} Express router
 */
function createStatsRoutes(container) {
    const router = express.Router();

    // Create auth middleware from container
    const validateToken = container.resolve('validateToken');
    const authMiddleware = createAuthMiddleware(validateToken);

    /**
     * GET /api/stats/me
     * Get current user's personal statistics
     */
    router.get('/me', authMiddleware, async (req, res) => {
        try {
            const getUserStats = container.resolve('getUserStats');

            const result = await getUserStats.execute({
                userId: req.user.id
            });

            res.json(result);
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * GET /api/stats/user/:userId
     * Get statistics for a specific user
     */
    router.get('/user/:userId', async (req, res) => {
        try {
            const getUserStats = container.resolve('getUserStats');
            const { userId } = req.params;

            const result = await getUserStats.execute({ userId });

            res.json(result);
        } catch (error) {
            if (error.message === 'User not found') {
                res.status(404).json({ error: error.message });
            } else {
                res.status(500).json({ error: error.message });
            }
        }
    });

    /**
     * GET /api/stats/leaderboard
     * Get global leaderboard sorted by win rate
     */
    router.get('/leaderboard', async (req, res) => {
        try {
            const getLeaderboard = container.resolve('getLeaderboard');
            const { minGames = 5, limit = 50, offset = 0 } = req.query;

            const result = await getLeaderboard.execute({
                minGames: parseInt(minGames, 10),
                limit: parseInt(limit, 10),
                offset: parseInt(offset, 10)
            });

            res.json(result);
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    });

    /**
     * GET /api/stats/bots
     * Get statistics for all bots, grouped by difficulty
     */
    router.get('/bots', async (req, res) => {
        try {
            const getBotStats = container.resolve('getBotStats');

            const result = await getBotStats.execute();

            res.json(result);
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    });

    return router;
}

module.exports = createStatsRoutes;
