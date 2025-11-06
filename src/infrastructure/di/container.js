/**
 * Dependency Injection Container
 * Manages service instantiation and dependencies following Clean Architecture
 */

const logger = require('../../../logger');

class Container {
    constructor() {
        this.services = new Map();
        this.factories = new Map();
        this.singletons = new Map();
    }

    /**
     * Register a service factory
     * @param {string} name - Service name
     * @param {Function} factory - Factory function that creates service instance
     * @param {boolean} singleton - Whether service should be singleton
     */
    register(name, factory, singleton = true) {
        if (this.factories.has(name)) {
            logger.warn('Overwriting existing service registration', { name });
        }

        this.factories.set(name, { factory, singleton });

        logger.debug('Service registered', {
            name,
            singleton
        });
    }

    /**
     * Register a singleton service instance directly
     * @param {string} name - Service name
     * @param {*} instance - Service instance
     */
    registerInstance(name, instance) {
        this.singletons.set(name, instance);

        logger.debug('Service instance registered', { name });
    }

    /**
     * Get service instance
     * @param {string} name - Service name
     * @returns {*} Service instance
     * @throws {Error} If service not registered
     */
    get(name) {
        // Check if singleton instance exists
        if (this.singletons.has(name)) {
            return this.singletons.get(name);
        }

        // Check if factory exists
        if (!this.factories.has(name)) {
            throw new Error(`Service '${name}' not registered in container`);
        }

        const { factory, singleton } = this.factories.get(name);

        // Create instance
        const instance = factory(this);

        // Store if singleton
        if (singleton) {
            this.singletons.set(name, instance);
        }

        return instance;
    }

    /**
     * Check if service is registered
     * @param {string} name - Service name
     * @returns {boolean}
     */
    has(name) {
        return this.factories.has(name) || this.singletons.has(name);
    }

    /**
     * Clear all registrations (useful for testing)
     */
    clear() {
        this.services.clear();
        this.factories.clear();
        this.singletons.clear();

        logger.debug('Container cleared');
    }

    /**
     * Get all registered service names
     * @returns {Array<string>}
     */
    getServiceNames() {
        const factoryNames = Array.from(this.factories.keys());
        const singletonNames = Array.from(this.singletons.keys());
        return [...new Set([...factoryNames, ...singletonNames])];
    }
}

// Create singleton container instance
const container = new Container();

/**
 * Initialize and register all application services
 * @param {Object} config - Configuration options
 */
function initializeContainer(config = {}) {
    // Clear existing registrations
    container.clear();

    // Infrastructure Layer
    // Database connection (singleton)
    container.register('database', (c) => {
        const { getConnection } = require('../database/sqlite/connection');
        return getConnection(config.dbPath);
    }, true);

    // JWT Service (singleton)
    container.register('jwtService', (c) => {
        const JwtService = require('../auth/JwtService');
        return new JwtService(config.jwt || {});
    }, true);

    // Repositories (singletons)
    container.register('userRepository', (c) => {
        const UserRepository = require('../database/sqlite/repositories/UserRepository');
        const db = c.get('database');
        return new UserRepository(db);
    }, true);

    container.register('partyRepository', (c) => {
        const PartyRepository = require('../database/sqlite/repositories/PartyRepository');
        const db = c.get('database');
        return new PartyRepository(db);
    }, true);

    // Use Cases (not singletons - fresh instance per request)
    // Auth Use Cases
    container.register('registerUserUseCase', (c) => {
        const RegisterUser = require('../../use-cases/auth/RegisterUser');
        return new RegisterUser(
            c.get('userRepository'),
            c.get('jwtService')
        );
    }, false);

    container.register('loginUserUseCase', (c) => {
        const LoginUser = require('../../use-cases/auth/LoginUser');
        return new LoginUser(
            c.get('userRepository'),
            c.get('jwtService')
        );
    }, false);

    container.register('validateTokenUseCase', (c) => {
        const ValidateToken = require('../../use-cases/auth/ValidateToken');
        return new ValidateToken(
            c.get('userRepository'),
            c.get('jwtService')
        );
    }, false);

    // Party Use Cases
    container.register('createPartyUseCase', (c) => {
        const CreateParty = require('../../use-cases/party/CreateParty');
        return new CreateParty(
            c.get('partyRepository'),
            c.get('userRepository')
        );
    }, false);

    container.register('joinPartyUseCase', (c) => {
        const JoinParty = require('../../use-cases/party/JoinParty');
        return new JoinParty(
            c.get('partyRepository'),
            c.get('userRepository')
        );
    }, false);

    container.register('leavePartyUseCase', (c) => {
        const LeaveParty = require('../../use-cases/party/LeaveParty');
        return new LeaveParty(
            c.get('partyRepository')
        );
    }, false);

    container.register('listPublicPartiesUseCase', (c) => {
        const ListPublicParties = require('../../use-cases/party/ListPublicParties');
        return new ListPublicParties(
            c.get('partyRepository')
        );
    }, false);

    container.register('getPartyDetailsUseCase', (c) => {
        const GetPartyDetails = require('../../use-cases/party/GetPartyDetails');
        return new GetPartyDetails(
            c.get('partyRepository')
        );
    }, false);

    // Game Use Cases
    container.register('playCardsUseCase', (c) => {
        const PlayCards = require('../../use-cases/game/PlayCards');
        return new PlayCards(
            c.get('partyRepository')
        );
    }, false);

    container.register('drawCardUseCase', (c) => {
        const DrawCard = require('../../use-cases/game/DrawCard');
        return new DrawCard(
            c.get('partyRepository')
        );
    }, false);

    container.register('callZapZapUseCase', (c) => {
        const CallZapZap = require('../../use-cases/game/CallZapZap');
        return new CallZapZap(
            c.get('partyRepository')
        );
    }, false);

    container.register('getGameStateUseCase', (c) => {
        const GetGameState = require('../../use-cases/game/GetGameState');
        return new GetGameState(
            c.get('partyRepository')
        );
    }, false);

    logger.info('Dependency injection container initialized', {
        services: container.getServiceNames().length
    });
}

module.exports = {
    Container,
    container,
    initializeContainer
};
