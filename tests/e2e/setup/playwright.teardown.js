/**
 * Playwright Global Teardown
 * Runs once after all tests complete
 */

const { cleanupTestDatabase } = require('./testDatabase');
const logger = require('../../../logger');

module.exports = async function globalTeardown(config) {
    logger.info('[E2E Teardown] Starting global teardown');

    try {
        // Cleanup test database singleton if it exists
        await cleanupTestDatabase();

        logger.info('[E2E Teardown] Global teardown complete');
    } catch (error) {
        logger.error('[E2E Teardown] Error during teardown', { error: error.message });
    }
};
