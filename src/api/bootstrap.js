/**
 * API Bootstrap
 * Initializes the DI container, database, repositories, and use cases
 */

const DIContainer = require('../infrastructure/di/DIContainer');
const DatabaseConnection = require('../infrastructure/database/sqlite/DatabaseConnection');
const UserRepository = require('../infrastructure/database/sqlite/repositories/UserRepository');
const PartyRepository = require('../infrastructure/database/sqlite/repositories/PartyRepository');
const JwtService = require('../infrastructure/services/JwtService');

// Use Cases - Authentication
const RegisterUser = require('../use-cases/auth/RegisterUser');
const LoginUser = require('../use-cases/auth/LoginUser');
const ValidateToken = require('../use-cases/auth/ValidateToken');

// Use Cases - Party Management
const CreateParty = require('../use-cases/party/CreateParty');
const JoinParty = require('../use-cases/party/JoinParty');
const LeaveParty = require('../use-cases/party/LeaveParty');
const StartParty = require('../use-cases/party/StartParty');
const ListPublicParties = require('../use-cases/party/ListPublicParties');
const GetPartyDetails = require('../use-cases/party/GetPartyDetails');
const DeleteParty = require('../use-cases/party/DeleteParty');

// Use Cases - Game Actions
const PlayCards = require('../use-cases/game/PlayCards');
const DrawCard = require('../use-cases/game/DrawCard');
const CallZapZap = require('../use-cases/game/CallZapZap');
const GetGameState = require('../use-cases/game/GetGameState');
const NextRound = require('../use-cases/game/NextRound');
const SaveRoundScores = require('../use-cases/game/SaveRoundScores');
const SaveGameResult = require('../use-cases/game/SaveGameResult');
const SelectHandSize = require('../use-cases/game/SelectHandSize');

// Use Cases - Bot Management
const CreateBot = require('../use-cases/bot/CreateBot');
const ListBots = require('../use-cases/bot/ListBots');
const DeleteBot = require('../use-cases/bot/DeleteBot');

// Use Cases - History
const GetGameHistory = require('../use-cases/history/GetGameHistory');
const GetGameDetails = require('../use-cases/history/GetGameDetails');

// Use Cases - Stats
const GetUserStats = require('../use-cases/stats/GetUserStats');
const GetLeaderboard = require('../use-cases/stats/GetLeaderboard');

// Use Cases - Admin
const CreateDefaultAdmin = require('../use-cases/admin/CreateDefaultAdmin');
const ListUsers = require('../use-cases/admin/ListUsers');
const DeleteUser = require('../use-cases/admin/DeleteUser');
const SetUserAdmin = require('../use-cases/admin/SetUserAdmin');
const ListAllParties = require('../use-cases/admin/ListAllParties');
const StopParty = require('../use-cases/admin/StopParty');
const AdminDeleteParty = require('../use-cases/admin/AdminDeleteParty');
const GetAdminStatistics = require('../use-cases/admin/GetAdminStatistics');

// Bot Infrastructure
const BotActionService = require('../infrastructure/bot/BotActionService');
const BotOrchestrator = require('../infrastructure/bot/BotOrchestrator');

const logger = require('../../logger');

/**
 * Bootstrap the application
 * @param {EventEmitter} emitter - Event emitter for SSE (optional)
 * @returns {Promise<DIContainer>} Initialized DI container
 */
async function bootstrap(emitter = null) {
    try {
        logger.info('Bootstrapping application...');

        // Initialize DI container
        const container = new DIContainer();

        // Initialize database
        const db = new DatabaseConnection();
        await db.initialize();
        container.register('database', db);

        logger.info('Database initialized');

        // Register repositories
        const userRepository = new UserRepository(db);
        const partyRepository = new PartyRepository(db);

        container.register('userRepository', userRepository);
        container.register('partyRepository', partyRepository);

        // Register services
        const jwtService = new JwtService();
        container.register('jwtService', jwtService);

        logger.info('Repositories and services registered');

        // Register authentication use cases
        container.register('registerUser', new RegisterUser(userRepository, jwtService));
        container.register('loginUser', new LoginUser(userRepository, jwtService));
        container.register('validateToken', new ValidateToken(userRepository, jwtService));

        // Register party management use cases
        // Note: JoinParty must be registered before CreateParty for dependency injection
        const joinParty = new JoinParty(partyRepository, userRepository);
        container.register('joinParty', joinParty);
        container.register('createParty', new CreateParty(partyRepository, userRepository, joinParty));
        container.register('leaveParty', new LeaveParty(partyRepository, userRepository));
        container.register('startParty', new StartParty(partyRepository, userRepository));
        container.register('listPublicParties', new ListPublicParties(partyRepository));
        container.register('getPartyDetails', new GetPartyDetails(partyRepository, userRepository));
        container.register('deleteParty', new DeleteParty(partyRepository, userRepository));

        // Register game action use cases
        // Note: SaveRoundScores and SaveGameResult are created first for dependency injection
        const saveRoundScores = new SaveRoundScores(partyRepository);
        const saveGameResult = new SaveGameResult(partyRepository);

        container.register('saveRoundScores', saveRoundScores);
        container.register('saveGameResult', saveGameResult);
        container.register('playCards', new PlayCards(partyRepository, userRepository));
        container.register('drawCard', new DrawCard(partyRepository, userRepository));
        container.register('callZapZap', new CallZapZap(partyRepository, userRepository, saveRoundScores, saveGameResult));
        container.register('getGameState', new GetGameState(partyRepository, userRepository));
        container.register('nextRound', new NextRound(partyRepository, userRepository, saveGameResult));
        container.register('selectHandSize', new SelectHandSize(partyRepository, userRepository));

        // Register bot management use cases
        container.register('createBot', new CreateBot(userRepository));
        container.register('listBots', new ListBots(userRepository));
        container.register('deleteBot', new DeleteBot(userRepository));

        // Register history use cases
        container.register('getGameHistory', new GetGameHistory(partyRepository, userRepository));
        container.register('getGameDetails', new GetGameDetails(partyRepository, userRepository));

        // Register stats use cases
        container.register('getUserStats', new GetUserStats(partyRepository, userRepository));
        container.register('getLeaderboard', new GetLeaderboard(partyRepository, userRepository));

        // Register admin use cases
        container.register('createDefaultAdmin', new CreateDefaultAdmin(userRepository));
        container.register('listUsers', new ListUsers(userRepository));
        container.register('deleteUser', new DeleteUser(userRepository, partyRepository));
        container.register('setUserAdmin', new SetUserAdmin(userRepository));
        container.register('listAllParties', new ListAllParties(partyRepository, userRepository));
        container.register('stopParty', new StopParty(partyRepository, userRepository));
        container.register('adminDeleteParty', new AdminDeleteParty(partyRepository, userRepository));
        container.register('getAdminStatistics', new GetAdminStatistics(partyRepository, userRepository));

        // Create default admin user on startup
        const adminPassword = process.env.ADMIN_PASSWORD || 'zapzap123';
        const createDefaultAdmin = container.resolve('createDefaultAdmin');
        try {
            const adminResult = await createDefaultAdmin.execute({ password: adminPassword });
            if (adminResult.created) {
                logger.info('Default admin user created');
            }
        } catch (adminError) {
            logger.error('Failed to create default admin', { error: adminError.message });
        }

        // Register bot infrastructure (if emitter is provided)
        if (emitter) {
            const botActionService = new BotActionService(
                {
                    playCards: container.resolve('playCards'),
                    drawCard: container.resolve('drawCard'),
                    callZapZap: container.resolve('callZapZap'),
                    selectHandSize: container.resolve('selectHandSize')
                },
                {
                    partyRepository,
                    userRepository
                }
            );

            // Bot action delay configurable via environment variable (default: 1000ms)
            const botActionDelayMs = parseInt(process.env.BOT_ACTION_DELAY_MS, 10) || 1000;

            const botOrchestrator = new BotOrchestrator(
                botActionService,
                partyRepository,
                userRepository,
                emitter,
                { actionDelayMs: botActionDelayMs }
            );

            logger.info('Bot orchestrator configured', { actionDelayMs: botActionDelayMs });

            container.register('botActionService', botActionService);
            container.register('botOrchestrator', botOrchestrator);

            // Start bot orchestrator
            botOrchestrator.start();
            logger.info('Bot system initialized and started');
        }

        logger.info('Use cases registered');
        logger.info('Application bootstrap complete');

        return container;
    } catch (error) {
        logger.error('Bootstrap failed', { error: error.message, stack: error.stack });
        throw error;
    }
}

/**
 * Shutdown the application gracefully
 * @param {DIContainer} container - DI container
 */
async function shutdown(container) {
    try {
        logger.info('Shutting down application...');

        // Stop bot orchestrator if running
        if (container.has('botOrchestrator')) {
            const botOrchestrator = container.resolve('botOrchestrator');
            if (botOrchestrator) {
                botOrchestrator.stop();
                logger.info('Bot orchestrator stopped');
            }
        }

        const db = container.resolve('database');
        if (db) {
            await db.close();
            logger.info('Database connection closed');
        }

        logger.info('Application shutdown complete');
    } catch (error) {
        logger.error('Shutdown error', { error: error.message });
        throw error;
    }
}

module.exports = { bootstrap, shutdown };
