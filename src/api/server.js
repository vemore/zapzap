/**
 * ZapZap Server with New API
 * Integrates clean architecture API with existing legacy endpoints
 */

const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const events = require('events');
const { bootstrap, shutdown } = require('./bootstrap');
const createApiRouter = require('./routes/index');
const logger = require('../../logger');

/**
 * Create and configure Express application
 * @param {DIContainer} container - DI container
 * @param {EventEmitter} emitter - Event emitter for SSE
 * @returns {express.Application}
 */
function createApp(container, emitter) {
    const app = express();

    // Middleware
    app.use(express.json());
    app.use(express.urlencoded({ extended: true }));
    app.use(morgan('dev'));

    // CORS configuration - allow frontend to communicate with backend
    const allowedOrigins = process.env.NODE_ENV === 'production'
        ? (process.env.ALLOWED_ORIGINS || '').split(',')
        : ['http://localhost:5173', 'http://localhost:5174'];

    app.use(cors({
        origin: (origin, callback) => {
            // Allow requests with no origin (mobile apps, curl, etc.)
            if (!origin) return callback(null, true);

            if (allowedOrigins.includes(origin)) {
                callback(null, true);
            } else {
                callback(new Error('Not allowed by CORS'));
            }
        },
        credentials: true,  // Allow cookies and Authorization headers
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization']
    }));

    // Static files
    app.use('/node_modules/deck-of-cards', express.static('node_modules/deck-of-cards'));
    app.use('/node_modules/jquery/dist', express.static('node_modules/jquery/dist'));
    app.use('/public', express.static('public'));

    // Set view engine
    app.set('view engine', 'ejs');
    app.set('views', './views');

    // SSE endpoint for real-time updates
    app.get('/suscribeupdate', (req, res) => {
        res.writeHead(200, {
            'Content-Type': 'text/event-stream',
            'Cache-Control': 'no-cache',
            Connection: 'keep-alive'
        });

        // Heartbeat
        const nln = () => res.write('\n');
        const hbt = setInterval(nln, 15000);

        const onEvent = (data) => {
            res.write('retry: 500\n');
            res.write('event: event\n');
            res.write(`data: ${JSON.stringify(data)}\n\n`);
        };

        emitter.on('event', onEvent);

        // Clear heartbeat and listener on disconnect
        req.on('close', () => {
            clearInterval(hbt);
            emitter.removeListener('event', onEvent);
        });
    });

    // Mount new API routes under /api prefix
    app.use('/api', createApiRouter(container, emitter));

    // Health check
    app.get('/health', (req, res) => {
        res.json({
            status: 'ok',
            timestamp: new Date().toISOString(),
            api: 'v2 (Clean Architecture)'
        });
    });

    // Legacy routes can be mounted here if needed
    // For now, we'll keep them in the old app.js

    // 404 handler
    app.use((req, res) => {
        res.status(404).json({
            error: 'Not Found',
            code: 'ROUTE_NOT_FOUND',
            path: req.path,
            message: 'The requested endpoint does not exist'
        });
    });

    // Error handler
    app.use((err, req, res, next) => {
        logger.error('Unhandled error', {
            error: err.message,
            stack: err.stack,
            path: req.path
        });

        res.status(500).json({
            error: 'Internal Server Error',
            code: 'INTERNAL_ERROR',
            message: process.env.NODE_ENV === 'development' ? err.message : 'An error occurred'
        });
    });

    return app;
}

/**
 * Start the server
 * @param {number} port - Port to listen on
 * @returns {Promise<{app: express.Application, container: DIContainer, server: http.Server}>}
 */
async function startServer(port = process.env.PORT || 9999) {
    try {
        logger.info('Starting ZapZap server...');

        // Create event emitter for SSE
        const emitter = new events.EventEmitter();

        // Bootstrap application (with emitter for bot orchestrator)
        const container = await bootstrap(emitter);

        // Create Express app
        const app = createApp(container, emitter);

        // Start listening
        const server = app.listen(port, () => {
            logger.info('ZapZap server started', {
                port,
                environment: process.env.NODE_ENV || 'development',
                api: 'v2 (Clean Architecture)'
            });

            console.log('\n🃏 ZapZap Game Server Running');
            console.log(`   Port: ${port}`);
            console.log(`   API: Clean Architecture v2`);
            console.log('');
            console.log('   New API Endpoints:');
            console.log(`   - POST http://localhost:${port}/api/auth/register`);
            console.log(`   - POST http://localhost:${port}/api/auth/login`);
            console.log(`   - GET  http://localhost:${port}/api/party`);
            console.log(`   - POST http://localhost:${port}/api/party`);
            console.log(`   - POST http://localhost:${port}/api/party/:id/join`);
            console.log(`   - POST http://localhost:${port}/api/party/:id/start`);
            console.log(`   - GET  http://localhost:${port}/api/game/:partyId/state`);
            console.log(`   - POST http://localhost:${port}/api/game/:partyId/play`);
            console.log(`   - POST http://localhost:${port}/api/game/:partyId/draw`);
            console.log(`   - POST http://localhost:${port}/api/game/:partyId/zapzap`);
            console.log('');
        });

        // Graceful shutdown
        const gracefulShutdown = async (signal) => {
            logger.info(`${signal} received, shutting down gracefully...`);

            server.close(async () => {
                logger.info('HTTP server closed');

                await shutdown(container);

                process.exit(0);
            });

            // Force shutdown after 10 seconds
            setTimeout(() => {
                logger.error('Forced shutdown after timeout');
                process.exit(1);
            }, 10000);
        };

        process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
        process.on('SIGINT', () => gracefulShutdown('SIGINT'));

        return { app, container, server, emitter };
    } catch (error) {
        logger.error('Failed to start server', {
            error: error.message,
            stack: error.stack
        });
        process.exit(1);
    }
}

// Start server if called directly
if (require.main === module) {
    startServer();
}

module.exports = { createApp, startServer };
