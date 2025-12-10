/**
 * ZapZap Game Server Entry Point
 *
 * This is the main entry point for the ZapZap card game server.
 * It uses the new clean architecture implementation.
 *
 * For the legacy server, see app.legacy.js
 */

// Load environment variables from .env file
require('dotenv').config();

const { startServer } = require('./src/api/server');
const logger = require('./logger');

// Get port from environment or use default
const PORT = process.env.PORT || 9999;

// Start the server
startServer(PORT)
    .then(({ server, container }) => {
        logger.info('ZapZap server started successfully', {
            port: PORT,
            environment: process.env.NODE_ENV || 'development'
        });
    })
    .catch((error) => {
        logger.error('Failed to start server', {
            error: error.message,
            stack: error.stack
        });
        process.exit(1);
    });
