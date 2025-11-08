/**
 * BotHelper
 * Handles bot management operations for E2E tests
 */

class BotHelper {
    constructor(baseURL) {
        this.baseURL = baseURL;
        this.bots = new Map(); // botId -> bot data
    }

    /**
     * Create a bot user
     * @param {string} username - Bot username
     * @param {string} difficulty - Bot difficulty (easy, medium, hard)
     * @returns {Promise<Object>} Created bot data
     */
    async createBot(username, difficulty) {
        if (!['easy', 'medium', 'hard'].includes(difficulty)) {
            throw new Error(`Invalid difficulty: ${difficulty}. Must be easy, medium, or hard.`);
        }

        const response = await fetch(`${this.baseURL}/api/bots`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, difficulty })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Failed to create bot: ${error.error || error.message}`);
        }

        const data = await response.json();

        // Store bot data
        this.bots.set(data.bot.id, data.bot);

        return data.bot;
    }

    /**
     * List all bots
     * @param {Object} options - Query options
     * @param {string} options.difficulty - Filter by difficulty
     * @returns {Promise<Array>} List of bots
     */
    async listBots(options = {}) {
        const { difficulty } = options;

        const queryParams = new URLSearchParams();
        if (difficulty) queryParams.append('difficulty', difficulty);

        const url = `${this.baseURL}/api/bots${queryParams.toString() ? '?' + queryParams.toString() : ''}`;
        const response = await fetch(url);

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Failed to list bots: ${error.error || error.message}`);
        }

        const data = await response.json();

        // Store bot data
        data.bots.forEach(bot => {
            this.bots.set(bot.id, bot);
        });

        return data.bots;
    }

    /**
     * Delete a bot
     * @param {string} botId - Bot user ID
     * @returns {Promise<Object>} Delete result
     */
    async deleteBot(botId) {
        const response = await fetch(`${this.baseURL}/api/bots/${botId}`, {
            method: 'DELETE'
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Failed to delete bot: ${error.error || error.message}`);
        }

        const data = await response.json();

        // Remove from stored bots
        this.bots.delete(botId);

        return data;
    }

    /**
     * Setup standard test bots
     * Creates 2 bots of each difficulty level
     * @returns {Promise<{easy: Array, medium: Array, hard: Array}>}
     */
    async setupStandardBots() {
        const results = {
            easy: [],
            medium: [],
            hard: []
        };

        // Check if bots already exist
        const existingBots = await this.listBots();

        const botConfigs = [
            { username: 'EasyBot1', difficulty: 'easy' },
            { username: 'EasyBot2', difficulty: 'easy' },
            { username: 'MediumBot1', difficulty: 'medium' },
            { username: 'MediumBot2', difficulty: 'medium' },
            { username: 'HardBot1', difficulty: 'hard' },
            { username: 'HardBot2', difficulty: 'hard' }
        ];

        for (const config of botConfigs) {
            // Check if bot with this username already exists
            const existing = existingBots.find(b => b.username === config.username);

            if (existing) {
                // Use existing bot
                results[config.difficulty].push(existing);
            } else {
                // Create new bot
                try {
                    const bot = await this.createBot(config.username, config.difficulty);
                    results[config.difficulty].push(bot);
                } catch (error) {
                    // If creation fails (bot might exist), fetch it
                    const allBots = await this.listBots();
                    const bot = allBots.find(b => b.username === config.username);
                    if (bot) {
                        results[config.difficulty].push(bot);
                    } else {
                        throw error;
                    }
                }
            }
        }

        return results;
    }

    /**
     * Get bots by difficulty
     * @param {string} difficulty - Bot difficulty (easy, medium, hard)
     * @returns {Promise<Array>} Bots of specified difficulty
     */
    async getBotsByDifficulty(difficulty) {
        return await this.listBots({ difficulty });
    }

    /**
     * Get first N bots of specified difficulty
     * @param {string} difficulty - Bot difficulty
     * @param {number} count - Number of bots to get
     * @returns {Promise<Array>} Bot array
     */
    async getBotsForTest(difficulty, count = 1) {
        const bots = await this.getBotsByDifficulty(difficulty);

        if (bots.length < count) {
            throw new Error(`Not enough ${difficulty} bots available. Found ${bots.length}, need ${count}`);
        }

        return bots.slice(0, count);
    }

    /**
     * Get mix of bots for testing
     * @param {Object} counts - Bot counts by difficulty
     * @param {number} counts.easy - Number of easy bots
     * @param {number} counts.medium - Number of medium bots
     * @param {number} counts.hard - Number of hard bots
     * @returns {Promise<Array>} Mixed bot array
     */
    async getMixedBots(counts = {}) {
        const { easy = 0, medium = 0, hard = 0 } = counts;

        const bots = [];

        if (easy > 0) {
            const easyBots = await this.getBotsForTest('easy', easy);
            bots.push(...easyBots);
        }

        if (medium > 0) {
            const mediumBots = await this.getBotsForTest('medium', medium);
            bots.push(...mediumBots);
        }

        if (hard > 0) {
            const hardBots = await this.getBotsForTest('hard', hard);
            bots.push(...hardBots);
        }

        return bots;
    }

    /**
     * Get bot IDs by difficulty
     * @param {string} difficulty - Bot difficulty
     * @param {number} count - Number of bot IDs to get
     * @returns {Promise<Array<string>>} Bot ID array
     */
    async getBotIds(difficulty, count = 1) {
        const bots = await this.getBotsForTest(difficulty, count);
        return bots.map(bot => bot.id);
    }

    /**
     * Get mixed bot IDs
     * @param {Object} counts - Bot counts by difficulty
     * @returns {Promise<Array<string>>} Mixed bot ID array
     */
    async getMixedBotIds(counts = {}) {
        const bots = await this.getMixedBots(counts);
        return bots.map(bot => bot.id);
    }

    /**
     * Get stored bot data
     * @param {string} botId - Bot ID
     * @returns {Object|null} Stored bot data
     */
    getStoredBot(botId) {
        return this.bots.get(botId);
    }

    /**
     * Get all stored bots
     * @returns {Array<Object>} Array of all stored bots
     */
    getAllStoredBots() {
        return Array.from(this.bots.values());
    }

    /**
     * Get stored bots by difficulty
     * @param {string} difficulty - Bot difficulty
     * @returns {Array<Object>} Filtered bot array
     */
    getStoredBotsByDifficulty(difficulty) {
        return this.getAllStoredBots().filter(bot => bot.botDifficulty === difficulty);
    }

    /**
     * Clear stored bot data
     */
    clear() {
        this.bots.clear();
    }

    /**
     * Get count of stored bots
     * @returns {number} Bot count
     */
    getStoredBotCount() {
        return this.bots.size;
    }

    /**
     * Wait for bot count to be available
     * Useful when bots are being created asynchronously
     * @param {string} difficulty - Bot difficulty
     * @param {number} minCount - Minimum bot count
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Array>} Bots when available
     */
    async waitForBots(difficulty, minCount, timeout = 5000) {
        const startTime = Date.now();

        while (Date.now() - startTime < timeout) {
            const bots = await this.getBotsByDifficulty(difficulty);

            if (bots.length >= minCount) {
                return bots;
            }

            // Wait 100ms before checking again
            await new Promise(resolve => setTimeout(resolve, 100));
        }

        throw new Error(`Timeout waiting for ${minCount} ${difficulty} bots`);
    }
}

/**
 * Create BotHelper instance
 * @param {string} baseURL - Base URL for API
 * @returns {BotHelper} BotHelper instance
 */
function createBotHelper(baseURL) {
    return new BotHelper(baseURL);
}

module.exports = {
    BotHelper,
    createBotHelper
};
