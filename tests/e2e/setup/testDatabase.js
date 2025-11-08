/**
 * Test Database Utilities
 * Manages test database lifecycle and seeding for E2E tests
 */

const path = require('path');
const fs = require('fs');
const DatabaseConnection = require('../../../src/infrastructure/database/sqlite/DatabaseConnection');
const UserRepository = require('../../../src/infrastructure/database/sqlite/repositories/UserRepository');
const User = require('../../../src/domain/entities/User');

// Test database path
const TEST_DB_PATH = path.join(__dirname, '../../../data/zapzap.test.db');

class TestDatabase {
    constructor() {
        this.db = null;
        this.userRepository = null;
    }

    /**
     * Initialize test database with fresh schema
     */
    async initialize() {
        // Delete existing test database
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }

        // Create new database connection
        this.db = new DatabaseConnection(TEST_DB_PATH);
        await this.db.initialize();

        // Initialize repositories
        this.userRepository = new UserRepository(this.db);

        return this;
    }

    /**
     * Clean all data from database (keeps schema)
     */
    async clean() {
        if (!this.db) {
            throw new Error('Database not initialized');
        }

        await this.db.exec(`
            DELETE FROM game_state;
            DELETE FROM rounds;
            DELETE FROM party_players;
            DELETE FROM parties;
            DELETE FROM users;
        `);
    }

    /**
     * Reset database (drop and recreate)
     */
    async reset() {
        await this.close();
        await this.initialize();
    }

    /**
     * Close database connection
     */
    async close() {
        if (this.db) {
            await this.db.close();
            this.db = null;
            this.userRepository = null;
        }
    }

    /**
     * Seed test users
     * @param {number} count - Number of users to create (default: 5)
     * @returns {Promise<Array<User>>} Created users
     */
    async seedUsers(count = 5) {
        const users = [];
        const baseNames = ['Alice', 'Bob', 'Charlie', 'Diana', 'Eve', 'Frank', 'Grace', 'Henry'];

        for (let i = 0; i < count; i++) {
            const username = baseNames[i] || `TestUser${i + 1}`;
            const user = await User.create(username, 'test123');
            const savedUser = await this.userRepository.save(user);
            users.push(savedUser);
        }

        return users;
    }

    /**
     * Seed bot users
     * @param {Object} options - Bot creation options
     * @param {number} options.easy - Number of easy bots (default: 2)
     * @param {number} options.medium - Number of medium bots (default: 2)
     * @param {number} options.hard - Number of hard bots (default: 2)
     * @returns {Promise<Array<User>>} Created bots
     */
    async seedBots({ easy = 2, medium = 2, hard = 2 } = {}) {
        const bots = [];

        // Create easy bots
        for (let i = 0; i < easy; i++) {
            const bot = await User.createBot(`EasyBot${i + 1}`, 'easy');
            const savedBot = await this.userRepository.save(bot);
            bots.push(savedBot);
        }

        // Create medium bots
        for (let i = 0; i < medium; i++) {
            const bot = await User.createBot(`MediumBot${i + 1}`, 'medium');
            const savedBot = await this.userRepository.save(bot);
            bots.push(savedBot);
        }

        // Create hard bots
        for (let i = 0; i < hard; i++) {
            const bot = await User.createBot(`HardBot${i + 1}`, 'hard');
            const savedBot = await this.userRepository.save(bot);
            bots.push(savedBot);
        }

        return bots;
    }

    /**
     * Create a specific user
     * @param {string} username - Username
     * @param {string} password - Password
     * @returns {Promise<User>} Created user
     */
    async createUser(username, password = 'test123') {
        const user = await User.create(username, password);
        return await this.userRepository.save(user);
    }

    /**
     * Create a specific bot
     * @param {string} username - Bot username
     * @param {string} difficulty - Bot difficulty (easy, medium, hard)
     * @returns {Promise<User>} Created bot
     */
    async createBot(username, difficulty) {
        const bot = await User.createBot(username, difficulty);
        return await this.userRepository.save(bot);
    }

    /**
     * Get user by username
     * @param {string} username - Username
     * @returns {Promise<User|null>} User or null
     */
    async getUserByUsername(username) {
        return await this.userRepository.findByUsername(username);
    }

    /**
     * Get user by ID
     * @param {string} userId - User ID
     * @returns {Promise<User|null>} User or null
     */
    async getUserById(userId) {
        return await this.userRepository.findById(userId);
    }

    /**
     * Get all bots
     * @returns {Promise<Array<User>>} All bots
     */
    async getAllBots() {
        return await this.userRepository.findBots();
    }

    /**
     * Get direct database connection (for advanced queries)
     * @returns {DatabaseConnection} Database connection
     */
    getConnection() {
        return this.db;
    }

    /**
     * Get user repository
     * @returns {UserRepository} User repository
     */
    getUserRepository() {
        return this.userRepository;
    }

    /**
     * Seed complete test scenario
     * Creates users and bots for typical test scenarios
     * @returns {Promise<{users: Array<User>, bots: Array<User>}>}
     */
    async seedTestScenario() {
        const users = await this.seedUsers(5);
        const bots = await this.seedBots({ easy: 2, medium: 2, hard: 2 });

        return { users, bots };
    }

    /**
     * Get database path
     * @returns {string} Database file path
     */
    getDbPath() {
        return TEST_DB_PATH;
    }

    /**
     * Check if database exists
     * @returns {boolean} True if database file exists
     */
    exists() {
        return fs.existsSync(TEST_DB_PATH);
    }

    /**
     * Delete test database file
     */
    delete() {
        if (this.exists()) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    }
}

/**
 * Create and initialize test database
 * @returns {Promise<TestDatabase>} Initialized test database
 */
async function createTestDatabase() {
    const testDb = new TestDatabase();
    await testDb.initialize();
    return testDb;
}

/**
 * Get or create singleton test database instance
 * Useful for sharing database across tests in same process
 */
let singletonInstance = null;

async function getTestDatabase() {
    if (!singletonInstance) {
        singletonInstance = await createTestDatabase();
    }
    return singletonInstance;
}

/**
 * Cleanup singleton instance
 */
async function cleanupTestDatabase() {
    if (singletonInstance) {
        await singletonInstance.close();
        singletonInstance.delete();
        singletonInstance = null;
    }
}

module.exports = {
    TestDatabase,
    createTestDatabase,
    getTestDatabase,
    cleanupTestDatabase,
    TEST_DB_PATH
};
