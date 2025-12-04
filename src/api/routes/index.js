/**
 * Main API Router
 * Combines all route modules
 */

const express = require('express');
const { createAuthMiddleware, createOptionalAuthMiddleware } = require('../middleware/authMiddleware');
const createAuthRouter = require('./authRoutes');
const createPartyRouter = require('./partyRoutes');
const createGameRouter = require('./gameRoutes');
const createBotRouter = require('./botRoutes');

/**
 * Create main API router
 * @param {DIContainer} container - DI container
 * @param {EventEmitter} emitter - Event emitter for SSE
 * @returns {express.Router}
 */
function createApiRouter(container, emitter) {
    const router = express.Router();

    // Create auth middleware
    const validateToken = container.resolve('validateToken');
    const authMiddleware = createAuthMiddleware(validateToken);
    const optionalAuthMiddleware = createOptionalAuthMiddleware(validateToken);

    // Mount route modules
    router.use('/auth', createAuthRouter(container));
    router.use('/party', createPartyRouter(container, authMiddleware, optionalAuthMiddleware, emitter));
    router.use('/game', createGameRouter(container, authMiddleware, emitter));
    router.use('/bots', createBotRouter(container)); // Bot management (admin endpoints)

    // Health check endpoint
    router.get('/health', (req, res) => {
        res.json({
            status: 'ok',
            timestamp: new Date().toISOString(),
            uptime: process.uptime()
        });
    });

    return router;
}

module.exports = createApiRouter;
