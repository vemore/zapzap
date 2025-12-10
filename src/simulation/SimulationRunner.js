/**
 * SimulationRunner
 * Orchestrates multiple game simulations for ML training
 */

const HeadlessGameEngine = require('./HeadlessGameEngine');
const SimulationStats = require('./SimulationStats');
const BotStrategyFactory = require('../infrastructure/bot/strategies/BotStrategyFactory');

class SimulationRunner {
    /**
     * @param {Object} options - Runner options
     * @param {Function} options.onProgress - Progress callback
     * @param {Function} options.onGameEnd - Called after each game with strategies
     * @param {number} options.batchSize - Games per batch (default: 1000)
     */
    constructor(options = {}) {
        this.onProgress = options.onProgress || (() => {});
        this.onGameEnd = options.onGameEnd || (() => {});
        this.batchSize = options.batchSize || 1000;
        this.stats = new SimulationStats();
    }

    /**
     * Run N simulations with specified strategies
     * @param {number} numGames - Number of games to simulate
     * @param {Array<string>} strategyTypes - Strategy types for each player
     * @param {Object} options - Additional options
     * @param {Object} options.sharedStrategies - Pre-created strategy instances to reuse
     * @returns {Object} Results with statistics
     */
    async runSimulations(numGames, strategyTypes, options = {}) {
        const startTime = Date.now();
        const sharedStrategies = options.sharedStrategies || null;

        for (let completed = 0; completed < numGames; completed += this.batchSize) {
            const batchCount = Math.min(this.batchSize, numGames - completed);
            this.runBatch(batchCount, strategyTypes, sharedStrategies);

            // Report progress
            this.onProgress({
                completed: completed + batchCount,
                total: numGames,
                stats: this.stats.getSummary(),
                gamesPerSecond: (completed + batchCount) / ((Date.now() - startTime) / 1000)
            });

            // Allow event loop to process (for long-running simulations)
            if (completed % 10000 === 0 && completed > 0) {
                await new Promise(resolve => setImmediate(resolve));
            }
        }

        const duration = (Date.now() - startTime) / 1000;

        return {
            results: this.stats.getSummary(),
            duration,
            gamesPerSecond: numGames / duration
        };
    }

    /**
     * Run a batch of games
     * @param {number} count - Number of games in batch
     * @param {Array<string>} strategyTypes - Strategy types
     * @param {Object} sharedStrategies - Optional shared strategy instances
     */
    runBatch(count, strategyTypes, sharedStrategies = null) {
        for (let i = 0; i < count; i++) {
            // Create or reuse strategy instances
            let strategies;
            if (sharedStrategies) {
                strategies = strategyTypes.map((type, idx) =>
                    sharedStrategies[idx] || BotStrategyFactory.create(type)
                );
            } else {
                strategies = strategyTypes.map(type => BotStrategyFactory.create(type));
            }

            // Run single game
            const engine = new HeadlessGameEngine(strategies);
            const result = engine.runGame();

            // Record statistics
            this.stats.recordGame(result, strategyTypes);

            // Notify strategies of game outcome (for ML learning)
            strategies.forEach((strategy, index) => {
                if (strategy.onGameEnd) {
                    strategy.onGameEnd(result, index);
                }
            });

            // Custom callback
            this.onGameEnd(result, strategies, strategyTypes);
        }
    }

    /**
     * Run simulations with rotating player positions
     * This ensures fair comparison by having each strategy play from each position
     * @param {number} gamesPerRotation - Games per position rotation
     * @param {Array<string>} strategyTypes - Strategy types
     * @param {Object} options - Additional options
     * @returns {Object} Results
     */
    async runFairSimulations(gamesPerRotation, strategyTypes, options = {}) {
        const startTime = Date.now();
        const totalGames = gamesPerRotation * strategyTypes.length;
        let completed = 0;

        // Run games with each rotation
        for (let rotation = 0; rotation < strategyTypes.length; rotation++) {
            // Rotate strategies
            const rotatedTypes = [
                ...strategyTypes.slice(rotation),
                ...strategyTypes.slice(0, rotation)
            ];

            for (let i = 0; i < gamesPerRotation; i++) {
                const strategies = rotatedTypes.map(type => BotStrategyFactory.create(type));
                const engine = new HeadlessGameEngine(strategies);
                const result = engine.runGame();

                this.stats.recordGame(result, rotatedTypes);

                // Notify strategies
                strategies.forEach((strategy, index) => {
                    if (strategy.onGameEnd) {
                        strategy.onGameEnd(result, index);
                    }
                });

                completed++;

                if (completed % this.batchSize === 0) {
                    this.onProgress({
                        completed,
                        total: totalGames,
                        stats: this.stats.getSummary(),
                        gamesPerSecond: completed / ((Date.now() - startTime) / 1000)
                    });
                }
            }
        }

        const duration = (Date.now() - startTime) / 1000;

        return {
            results: this.stats.getSummary(),
            duration,
            gamesPerSecond: totalGames / duration,
            totalGames
        };
    }

    /**
     * Run ML training simulations with a learning strategy
     * @param {number} numGames - Number of games
     * @param {Object} mlStrategy - ML strategy instance (will be reused)
     * @param {Array<string>} opponentTypes - Opponent strategy types
     * @param {Object} options - Additional options
     * @returns {Object} Results
     */
    async runMLTraining(numGames, mlStrategy, opponentTypes, options = {}) {
        const startTime = Date.now();
        const playerCount = opponentTypes.length + 1;
        const mlPosition = options.mlPosition !== undefined ? options.mlPosition : 0;

        // Build strategy types array with ML at specified position
        const strategyTypes = [];
        let oppIndex = 0;
        for (let i = 0; i < playerCount; i++) {
            if (i === mlPosition) {
                strategyTypes.push('ml');
            } else {
                strategyTypes.push(opponentTypes[oppIndex++]);
            }
        }

        for (let completed = 0; completed < numGames; completed++) {
            // Create opponent strategies (new each game to avoid state)
            const strategies = [];
            oppIndex = 0;
            for (let i = 0; i < playerCount; i++) {
                if (i === mlPosition) {
                    strategies.push(mlStrategy);
                } else {
                    strategies.push(BotStrategyFactory.create(opponentTypes[oppIndex++]));
                }
            }

            // Run game
            const engine = new HeadlessGameEngine(strategies);
            const result = engine.runGame();

            // Record stats
            this.stats.recordGame(result, strategyTypes);

            // Notify ML strategy of outcome
            if (mlStrategy.onGameEnd) {
                mlStrategy.onGameEnd(result, mlPosition);
            }

            // Progress reporting
            if ((completed + 1) % Math.min(1000, this.batchSize) === 0) {
                this.onProgress({
                    completed: completed + 1,
                    total: numGames,
                    stats: this.stats.getSummary(),
                    gamesPerSecond: (completed + 1) / ((Date.now() - startTime) / 1000)
                });

                // Allow event loop
                await new Promise(resolve => setImmediate(resolve));
            }
        }

        const duration = (Date.now() - startTime) / 1000;

        return {
            results: this.stats.getSummary(),
            duration,
            gamesPerSecond: numGames / duration,
            mlWinRate: this.stats.getWinRates()['ml'] || 0
        };
    }

    /**
     * Get current statistics
     * @returns {SimulationStats}
     */
    getStats() {
        return this.stats;
    }

    /**
     * Reset statistics
     */
    resetStats() {
        this.stats.reset();
    }
}

module.exports = SimulationRunner;
