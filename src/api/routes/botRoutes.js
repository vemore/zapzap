/**
 * Bot Management Routes
 * API endpoints for managing bot users
 */

const express = require('express');
const logger = require('../../../logger');

/**
 * Create bot management router
 * @param {DIContainer} container - DI container
 * @returns {express.Router} Express router
 */
function createBotRouter(container) {
    const router = express.Router();

    /**
     * POST /api/bots
     * Create a new bot user
     */
    router.post('/', async (req, res) => {
        try {
            const { username, difficulty } = req.body;

            const createBot = container.resolve('createBot');
            const result = await createBot.execute({ username, difficulty });

            res.status(201).json(result);
        } catch (error) {
            logger.error('POST /api/bots error', {
                body: req.body,
                error: error.message
            });

            res.status(400).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * GET /api/bots
     * List all bots (optionally filtered by difficulty)
     */
    router.get('/', async (req, res) => {
        try {
            const { difficulty } = req.query;

            const listBots = container.resolve('listBots');
            const result = await listBots.execute({ difficulty });

            res.json(result);
        } catch (error) {
            logger.error('GET /api/bots error', {
                query: req.query,
                error: error.message
            });

            res.status(400).json({
                success: false,
                error: error.message
            });
        }
    });

    /**
     * DELETE /api/bots/:botId
     * Delete a bot user
     */
    router.delete('/:botId', async (req, res) => {
        try {
            const { botId } = req.params;

            const deleteBot = container.resolve('deleteBot');
            const result = await deleteBot.execute({ botId });

            res.json(result);
        } catch (error) {
            logger.error('DELETE /api/bots/:botId error', {
                params: req.params,
                error: error.message
            });

            res.status(400).json({
                success: false,
                error: error.message
            });
        }
    });

    return router;
}

module.exports = createBotRouter;
