/**
 * Playwright Global Setup
 * Runs once before all tests
 */

const logger = require('../../../logger');

module.exports = async function globalSetup(config) {
    logger.info('[E2E Setup] Starting global setup');

    // Set test environment
    process.env.NODE_ENV = 'test';
    process.env.LOG_LEVEL = 'error'; // Reduce noise during tests

    // Note: TestServer and database are started by playwright.config.js webServer
    // This setup file is for any additional global configuration

    logger.info('[E2E Setup] Global setup complete');
};
