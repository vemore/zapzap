/**
 * LLMBotMemory
 * Manages strategic memory for LLM bots - stores learned strategies and tracks decisions
 */

const fs = require('fs').promises;
const path = require('path');
const logger = require('../../../logger');

// Strategy categories
const CATEGORIES = {
    PLAY_STRATEGY: 'play_strategy',
    ZAPZAP_TIMING: 'zapzap_timing',
    DRAW_DECISION: 'draw_decision',
    GOLDEN_SCORE: 'golden_score',
    OPPONENT_READING: 'opponent_reading'
};

// Limits
const MAX_STRATEGIES = 20;
const MAX_PER_CATEGORY = 5;
const MAX_RECENT_DECISIONS = 50;

class LLMBotMemory {
    /**
     * @param {string} botUserId - Bot user ID
     * @param {string} baseDir - Base directory for storage (default: data/bot-strategies)
     */
    constructor(botUserId, baseDir = null) {
        this.botUserId = botUserId;
        this.baseDir = baseDir || path.join(process.cwd(), 'data', 'bot-strategies');
        this.filePath = path.join(this.baseDir, `${botUserId}.json`);

        // In-memory data
        this.data = this._getEmptyData();
        this.loaded = false;
        this.dirty = false;
    }

    /**
     * Get empty data structure
     * @private
     */
    _getEmptyData() {
        return {
            botUserId: this.botUserId,
            createdAt: Date.now(),
            lastUpdatedAt: Date.now(),
            totalGamesAnalyzed: 0,
            totalRoundsAnalyzed: 0,
            strategies: [],
            roundDecisions: {},
            gameHistory: []
        };
    }

    /**
     * Generate unique strategy ID
     * @private
     */
    _generateId() {
        return `strat_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    /**
     * Load strategies from file
     * @returns {Promise<void>}
     */
    async load() {
        try {
            // Ensure directory exists
            await fs.mkdir(this.baseDir, { recursive: true });

            // Try to read existing file
            const content = await fs.readFile(this.filePath, 'utf8');
            this.data = JSON.parse(content);
            this.loaded = true;

            logger.debug('LLMBotMemory loaded', {
                botUserId: this.botUserId,
                strategiesCount: this.data.strategies.length
            });
        } catch (error) {
            if (error.code === 'ENOENT') {
                // File doesn't exist - start fresh
                this.data = this._getEmptyData();
                this.loaded = true;
                logger.debug('LLMBotMemory initialized (new bot)', { botUserId: this.botUserId });
            } else {
                logger.error('Failed to load LLMBotMemory', {
                    botUserId: this.botUserId,
                    error: error.message
                });
                // Start fresh on error
                this.data = this._getEmptyData();
                this.loaded = true;
            }
        }
    }

    /**
     * Load strategies synchronously (for use in constructor contexts)
     */
    loadSync() {
        try {
            const fsSync = require('fs');

            // Ensure directory exists
            if (!fsSync.existsSync(this.baseDir)) {
                fsSync.mkdirSync(this.baseDir, { recursive: true });
            }

            if (fsSync.existsSync(this.filePath)) {
                const content = fsSync.readFileSync(this.filePath, 'utf8');
                this.data = JSON.parse(content);
            } else {
                this.data = this._getEmptyData();
            }
            this.loaded = true;
        } catch (error) {
            logger.error('Failed to load LLMBotMemory sync', {
                botUserId: this.botUserId,
                error: error.message
            });
            this.data = this._getEmptyData();
            this.loaded = true;
        }
    }

    /**
     * Save strategies to file
     * @returns {Promise<void>}
     */
    async save() {
        if (!this.dirty) {
            return; // Nothing to save
        }

        try {
            // Ensure directory exists
            await fs.mkdir(this.baseDir, { recursive: true });

            this.data.lastUpdatedAt = Date.now();

            // Write atomically (write to temp file, then rename)
            const tempPath = `${this.filePath}.tmp`;
            await fs.writeFile(tempPath, JSON.stringify(this.data, null, 2), 'utf8');
            await fs.rename(tempPath, this.filePath);

            this.dirty = false;

            logger.debug('LLMBotMemory saved', {
                botUserId: this.botUserId,
                strategiesCount: this.data.strategies.length
            });
        } catch (error) {
            logger.error('Failed to save LLMBotMemory', {
                botUserId: this.botUserId,
                error: error.message
            });
            throw error;
        }
    }

    /**
     * Check if bot has any strategies
     * @returns {boolean}
     */
    hasStrategies() {
        return this.data.strategies.length > 0;
    }

    /**
     * Get top strategies by confidence
     * @param {number} limit - Max number of strategies to return
     * @returns {Array} Top strategies
     */
    getTopStrategies(limit = 10) {
        return [...this.data.strategies]
            .sort((a, b) => b.confidence - a.confidence)
            .slice(0, limit);
    }

    /**
     * Get all strategies
     * @returns {Array}
     */
    getAllStrategies() {
        return this.data.strategies;
    }

    /**
     * Add a new strategy
     * @param {string} insight - Strategy insight text
     * @param {string} category - Strategy category
     * @param {Object} context - Source context (partyId, roundNumber, outcome)
     * @param {number} confidence - Initial confidence (0-1, default 0.5)
     * @returns {Object} Added strategy
     */
    addStrategy(insight, category, context = {}, confidence = 0.5) {
        // Validate category
        if (!Object.values(CATEGORIES).includes(category)) {
            logger.warn('Invalid strategy category', { category, insight });
            category = CATEGORIES.PLAY_STRATEGY;
        }

        // Check for duplicate insights
        const isDuplicate = this.data.strategies.some(s =>
            s.insight.toLowerCase() === insight.toLowerCase()
        );
        if (isDuplicate) {
            logger.debug('Duplicate strategy ignored', { insight });
            return null;
        }

        const strategy = {
            id: this._generateId(),
            insight: insight.substring(0, 150), // Limit to 150 chars
            category,
            confidence,
            createdAt: Date.now(),
            sourceContext: context,
            usageCount: 0
        };

        this.data.strategies.push(strategy);
        this.dirty = true;

        // Prune if over limit
        this._prune();

        logger.info('Strategy added', {
            botUserId: this.botUserId,
            insight: strategy.insight,
            category
        });

        return strategy;
    }

    /**
     * Update strategy confidence based on outcome
     * @param {string} strategyId - Strategy ID
     * @param {boolean} success - Whether the strategy led to success
     */
    updateConfidence(strategyId, success) {
        const strategy = this.data.strategies.find(s => s.id === strategyId);
        if (!strategy) return;

        // Adjust confidence based on outcome
        const adjustment = success ? 0.05 : -0.05;
        strategy.confidence = Math.max(0, Math.min(1, strategy.confidence + adjustment));
        strategy.usageCount++;
        this.dirty = true;
    }

    /**
     * Track a decision made during gameplay
     * @param {Object} decision - Decision data
     * @param {number} decision.roundNumber - Round number
     * @param {string} decision.type - Decision type (play, draw, zapzap)
     * @param {Object} decision.details - Decision details
     */
    trackDecision(decision) {
        const roundKey = String(decision.roundNumber);

        if (!this.data.roundDecisions[roundKey]) {
            this.data.roundDecisions[roundKey] = [];
        }

        this.data.roundDecisions[roundKey].push({
            type: decision.type,
            details: decision.details,
            timestamp: Date.now()
        });

        this.dirty = true;

        // Limit decisions per round
        if (this.data.roundDecisions[roundKey].length > MAX_RECENT_DECISIONS) {
            this.data.roundDecisions[roundKey] =
                this.data.roundDecisions[roundKey].slice(-MAX_RECENT_DECISIONS);
        }
    }

    /**
     * Get decisions for a specific round
     * @param {number} roundNumber
     * @returns {Array}
     */
    getDecisionsForRound(roundNumber) {
        return this.data.roundDecisions[String(roundNumber)] || [];
    }

    /**
     * Get all tracked decisions
     * @returns {Object}
     */
    getAllDecisions() {
        return this.data.roundDecisions;
    }

    /**
     * Clear decisions for a round (after reflection)
     * @param {number} roundNumber
     */
    clearRoundDecisions(roundNumber) {
        delete this.data.roundDecisions[String(roundNumber)];
        this.dirty = true;
    }

    /**
     * Clear all decisions (after game reflection)
     */
    clearAllDecisions() {
        this.data.roundDecisions = {};
        this.dirty = true;
    }

    /**
     * Increment games analyzed counter
     */
    incrementGamesAnalyzed() {
        this.data.totalGamesAnalyzed++;
        this.dirty = true;
    }

    /**
     * Increment rounds analyzed counter
     */
    incrementRoundsAnalyzed() {
        this.data.totalRoundsAnalyzed++;
        this.dirty = true;
    }

    /**
     * Add game to history (for game-level reflection)
     * @param {Object} gameSummary
     */
    addGameHistory(gameSummary) {
        this.data.gameHistory.push({
            ...gameSummary,
            timestamp: Date.now()
        });

        // Keep only last 10 games
        if (this.data.gameHistory.length > 10) {
            this.data.gameHistory = this.data.gameHistory.slice(-10);
        }

        this.dirty = true;
    }

    /**
     * Prune strategies to stay within limits
     * @private
     */
    _prune() {
        // First, enforce per-category limits
        const byCategory = {};
        for (const strategy of this.data.strategies) {
            if (!byCategory[strategy.category]) {
                byCategory[strategy.category] = [];
            }
            byCategory[strategy.category].push(strategy);
        }

        // Keep only top N per category
        const kept = [];
        for (const [category, strategies] of Object.entries(byCategory)) {
            const sorted = strategies.sort((a, b) => b.confidence - a.confidence);
            kept.push(...sorted.slice(0, MAX_PER_CATEGORY));
        }

        // If still over total limit, remove lowest confidence
        if (kept.length > MAX_STRATEGIES) {
            kept.sort((a, b) => b.confidence - a.confidence);
            this.data.strategies = kept.slice(0, MAX_STRATEGIES);
        } else {
            this.data.strategies = kept;
        }

        this.dirty = true;
    }

    /**
     * Get statistics about the bot's learning
     * @returns {Object}
     */
    getStats() {
        return {
            totalStrategies: this.data.strategies.length,
            totalGamesAnalyzed: this.data.totalGamesAnalyzed,
            totalRoundsAnalyzed: this.data.totalRoundsAnalyzed,
            strategiesByCategory: this._countByCategory(),
            averageConfidence: this._averageConfidence()
        };
    }

    /**
     * Count strategies by category
     * @private
     */
    _countByCategory() {
        const counts = {};
        for (const s of this.data.strategies) {
            counts[s.category] = (counts[s.category] || 0) + 1;
        }
        return counts;
    }

    /**
     * Calculate average confidence
     * @private
     */
    _averageConfidence() {
        if (this.data.strategies.length === 0) return 0;
        const sum = this.data.strategies.reduce((acc, s) => acc + s.confidence, 0);
        return sum / this.data.strategies.length;
    }
}

// Export class and constants
module.exports = LLMBotMemory;
module.exports.CATEGORIES = CATEGORIES;
module.exports.MAX_STRATEGIES = MAX_STRATEGIES;
