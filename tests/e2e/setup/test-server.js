/**
 * Test Server
 * Programmatic server control for E2E tests with graceful SSE shutdown
 */

const express = require('express');
const morgan = require('morgan');
const cors = require('cors');
const events = require('events');
const stoppable = require('stoppable');
const { TestDatabase } = require('./testDatabase');
const logger = require('../../../logger');

// Import infrastructure
const DIContainer = require('../../../src/infrastructure/di/DIContainer');
const UserRepository = require('../../../src/infrastructure/database/sqlite/repositories/UserRepository');
const PartyRepository = require('../../../src/infrastructure/database/sqlite/repositories/PartyRepository');
const JwtService = require('../../../src/infrastructure/services/JwtService');

// Import use cases - Authentication
const RegisterUser = require('../../../src/use-cases/auth/RegisterUser');
const LoginUser = require('../../../src/use-cases/auth/LoginUser');
const ValidateToken = require('../../../src/use-cases/auth/ValidateToken');

// Import use cases - Party Management
const CreateParty = require('../../../src/use-cases/party/CreateParty');
const JoinParty = require('../../../src/use-cases/party/JoinParty');
const LeaveParty = require('../../../src/use-cases/party/LeaveParty');
const StartParty = require('../../../src/use-cases/party/StartParty');
const ListPublicParties = require('../../../src/use-cases/party/ListPublicParties');
const GetPartyDetails = require('../../../src/use-cases/party/GetPartyDetails');

// Import use cases - Game Actions
const PlayCards = require('../../../src/use-cases/game/PlayCards');
const DrawCard = require('../../../src/use-cases/game/DrawCard');
const CallZapZap = require('../../../src/use-cases/game/CallZapZap');
const GetGameState = require('../../../src/use-cases/game/GetGameState');

// Import use cases - Bot Management
const CreateBot = require('../../../src/use-cases/bot/CreateBot');
const ListBots = require('../../../src/use-cases/bot/ListBots');
const DeleteBot = require('../../../src/use-cases/bot/DeleteBot');

// Import bot infrastructure
const BotActionService = require('../../../src/infrastructure/bot/BotActionService');
const BotOrchestrator = require('../../../src/infrastructure/bot/BotOrchestrator');

// Import routes
const createApiRouter = require('../../../src/api/routes/index');

class TestServer {
    constructor(options = {}) {
        this.port = options.port || 9999;
        this.logLevel = options.logLevel || 'error'; // Reduce noise during tests
        this.enableBots = options.enableBots !== false; // Enable by default

        this.testDb = null;
        this.container = null;
        this.emitter = null;
        this.app = null;
        this.server = null;
        this.isStarted = false;
    }

    /**
     * Bootstrap test application with test database
     */
    async bootstrap() {
        try {
            logger.info('[TestServer] Bootstrapping test application...');

            // Initialize test database
            this.testDb = new TestDatabase();
            await this.testDb.initialize();

            // Initialize DI container
            this.container = new DIContainer();

            // Register test database
            this.container.register('database', this.testDb.getConnection());

            // Register repositories
            const userRepository = new UserRepository(this.testDb.getConnection());
            const partyRepository = new PartyRepository(this.testDb.getConnection());

            this.container.register('userRepository', userRepository);
            this.container.register('partyRepository', partyRepository);

            // Register services
            const jwtService = new JwtService();
            this.container.register('jwtService', jwtService);

            // Register authentication use cases
            this.container.register('registerUser', new RegisterUser(userRepository, jwtService));
            this.container.register('loginUser', new LoginUser(userRepository, jwtService));
            this.container.register('validateToken', new ValidateToken(userRepository, jwtService));

            // Register party management use cases
            const joinParty = new JoinParty(partyRepository, userRepository);
            this.container.register('joinParty', joinParty);
            this.container.register('createParty', new CreateParty(partyRepository, userRepository, joinParty));
            this.container.register('leaveParty', new LeaveParty(partyRepository, userRepository));
            this.container.register('startParty', new StartParty(partyRepository, userRepository));
            this.container.register('listPublicParties', new ListPublicParties(partyRepository));
            this.container.register('getPartyDetails', new GetPartyDetails(partyRepository, userRepository));

            // Register game action use cases
            this.container.register('playCards', new PlayCards(partyRepository, userRepository));
            this.container.register('drawCard', new DrawCard(partyRepository, userRepository));
            this.container.register('callZapZap', new CallZapZap(partyRepository, userRepository));
            this.container.register('getGameState', new GetGameState(partyRepository, userRepository));

            // Register bot management use cases
            this.container.register('createBot', new CreateBot(userRepository));
            this.container.register('listBots', new ListBots(userRepository));
            this.container.register('deleteBot', new DeleteBot(userRepository));

            // Create event emitter for SSE
            this.emitter = new events.EventEmitter();

            // Register bot infrastructure if enabled
            if (this.enableBots) {
                const botActionService = new BotActionService(
                    {
                        playCards: this.container.resolve('playCards'),
                        drawCard: this.container.resolve('drawCard'),
                        callZapZap: this.container.resolve('callZapZap')
                    },
                    {
                        partyRepository,
                        userRepository
                    }
                );

                const botOrchestrator = new BotOrchestrator(
                    botActionService,
                    partyRepository,
                    userRepository,
                    this.emitter
                );

                this.container.register('botActionService', botActionService);
                this.container.register('botOrchestrator', botOrchestrator);

                // Start bot orchestrator
                botOrchestrator.start();
                logger.info('[TestServer] Bot system initialized');
            }

            logger.info('[TestServer] Bootstrap complete');
        } catch (error) {
            logger.error('[TestServer] Bootstrap failed', { error: error.message });
            throw error;
        }
    }

    /**
     * Create Express application
     */
    createApp() {
        const app = express();

        // Middleware
        app.use(express.json());
        app.use(express.urlencoded({ extended: true }));

        // Only log in verbose mode
        if (this.logLevel === 'verbose') {
            app.use(morgan('dev'));
        }

        // CORS - permissive for tests
        app.use(cors({
            origin: true,
            credentials: true,
            methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
            allowedHeaders: ['Content-Type', 'Authorization']
        }));

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

            this.emitter.on('event', onEvent);

            // Clear heartbeat and listener on disconnect
            req.on('close', () => {
                clearInterval(hbt);
                this.emitter.removeListener('event', onEvent);
            });
        });

        // Mount API routes
        app.use('/api', createApiRouter(this.container, this.emitter));

        // Health check
        app.get('/health', (req, res) => {
            res.json({
                status: 'ok',
                timestamp: new Date().toISOString(),
                mode: 'test',
                database: this.testDb.getDbPath()
            });
        });

        // 404 handler
        app.use((req, res) => {
            res.status(404).json({
                error: 'Not Found',
                code: 'ROUTE_NOT_FOUND',
                path: req.path
            });
        });

        // Error handler
        app.use((err, req, res, next) => {
            logger.error('[TestServer] Unhandled error', {
                error: err.message,
                path: req.path
            });

            res.status(500).json({
                error: 'Internal Server Error',
                code: 'INTERNAL_ERROR',
                message: err.message
            });
        });

        return app;
    }

    /**
     * Start test server
     */
    async start() {
        if (this.isStarted) {
            logger.warn('[TestServer] Server already started');
            return;
        }

        try {
            // Bootstrap
            await this.bootstrap();

            // Create app
            this.app = this.createApp();

            // Start listening
            await new Promise((resolve, reject) => {
                const httpServer = this.app.listen(this.port, (err) => {
                    if (err) {
                        reject(err);
                    } else {
                        logger.info(`[TestServer] Started on port ${this.port}`);
                        resolve();
                    }
                });

                // Wrap with stoppable for graceful shutdown with SSE
                this.server = stoppable(httpServer, 5000); // 5s grace period
            });

            this.isStarted = true;

            return {
                baseURL: `http://localhost:${this.port}`,
                port: this.port,
                testDb: this.testDb,
                container: this.container,
                emitter: this.emitter
            };
        } catch (error) {
            logger.error('[TestServer] Failed to start', { error: error.message });
            throw error;
        }
    }

    /**
     * Stop test server gracefully
     */
    async stop() {
        if (!this.isStarted) {
            return;
        }

        try {
            logger.info('[TestServer] Stopping server...');

            // Stop bot orchestrator
            if (this.container && this.container.has('botOrchestrator')) {
                const botOrchestrator = this.container.resolve('botOrchestrator');
                botOrchestrator.stop();
            }

            // Close server (stoppable will wait for SSE connections)
            if (this.server) {
                await new Promise((resolve, reject) => {
                    this.server.stop((err) => {
                        if (err) {
                            reject(err);
                        } else {
                            logger.info('[TestServer] HTTP server stopped');
                            resolve();
                        }
                    });
                });
            }

            // Close database
            if (this.testDb) {
                await this.testDb.close();
            }

            this.isStarted = false;
            logger.info('[TestServer] Stopped successfully');
        } catch (error) {
            logger.error('[TestServer] Error during stop', { error: error.message });
            throw error;
        }
    }

    /**
     * Reset test database
     */
    async resetDatabase() {
        if (this.testDb) {
            await this.testDb.clean();
        }
    }

    /**
     * Get base URL
     */
    getBaseURL() {
        return `http://localhost:${this.port}`;
    }

    /**
     * Get test database
     */
    getDatabase() {
        return this.testDb;
    }

    /**
     * Get event emitter
     */
    getEmitter() {
        return this.emitter;
    }

    /**
     * Check if server is running
     */
    isRunning() {
        return this.isStarted;
    }
}

/**
 * Create and start test server
 * @param {Object} options - Server options
 * @returns {Promise<TestServer>} Started test server
 */
async function createTestServer(options = {}) {
    const server = new TestServer(options);
    await server.start();
    return server;
}

// If run directly, start server (for manual testing or playwright.config.js)
if (require.main === module) {
    const server = new TestServer({ logLevel: 'info' });
    server.start()
        .then(() => {
            console.log('\n✅ Test server running');
            console.log(`   URL: ${server.getBaseURL()}`);
            console.log(`   Database: ${server.getDatabase().getDbPath()}\n`);
        })
        .catch((error) => {
            console.error('❌ Failed to start test server:', error);
            process.exit(1);
        });

    // Graceful shutdown
    process.on('SIGTERM', async () => {
        await server.stop();
        process.exit(0);
    });

    process.on('SIGINT', async () => {
        await server.stop();
        process.exit(0);
    });
}

module.exports = {
    TestServer,
    createTestServer
};
