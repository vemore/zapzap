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

// Use Cases - Game Actions
const PlayCards = require('../use-cases/game/PlayCards');
const DrawCard = require('../use-cases/game/DrawCard');
const CallZapZap = require('../use-cases/game/CallZapZap');
const GetGameState = require('../use-cases/game/GetGameState');

const logger = require('../../logger');

/**
 * Bootstrap the application
 * @returns {Promise<DIContainer>} Initialized DI container
 */
async function bootstrap() {
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
        container.register('createParty', new CreateParty(partyRepository, userRepository));
        container.register('joinParty', new JoinParty(partyRepository, userRepository));
        container.register('leaveParty', new LeaveParty(partyRepository, userRepository));
        container.register('startParty', new StartParty(partyRepository, userRepository));
        container.register('listPublicParties', new ListPublicParties(partyRepository));
        container.register('getPartyDetails', new GetPartyDetails(partyRepository, userRepository));

        // Register game action use cases
        container.register('playCards', new PlayCards(partyRepository, userRepository));
        container.register('drawCard', new DrawCard(partyRepository, userRepository));
        container.register('callZapZap', new CallZapZap(partyRepository, userRepository));
        container.register('getGameState', new GetGameState(partyRepository, userRepository));

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
