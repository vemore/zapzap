/**
 * SimulationWorker
 * Worker thread code for parallel simulation
 * Runs batches of games independently and returns results for merging
 */

const { parentPort, workerData } = require('worker_threads');
const path = require('path');

// Set up module paths for worker thread
const HeadlessGameEngine = require('./HeadlessGameEngine');
const SimulationStats = require('./SimulationStats');
const BanditPolicy = require('../infrastructure/bot/ml/BanditPolicy');
const BotStrategyFactory = require('../infrastructure/bot/strategies/BotStrategyFactory');

// Initialize local policy from main thread data
const localPolicy = new BanditPolicy();
if (workerData.policyState) {
    localPolicy.fromJSON(workerData.policyState);
}

// Set up local shared policy for ML bots in this worker
BotStrategyFactory.setSharedMLPolicy(localPolicy);

// Strategy types for this simulation
const strategyTypes = workerData.strategyTypes || ['easy', 'easy', 'easy', 'easy'];

// Worker ID for debugging
const workerId = workerData.workerId || 0;

/**
 * Run a batch of games
 * @param {number} batchSize - Number of games to run
 * @param {boolean} trackDecisions - Whether to track ML decisions for merge
 * @returns {Object} Batch results
 */
function runBatch(batchSize, trackDecisions = true) {
    const stats = new SimulationStats();
    const startQValues = JSON.parse(JSON.stringify(localPolicy.qValues));

    for (let i = 0; i < batchSize; i++) {
        // Create fresh strategies for each game
        const strategies = strategyTypes.map(type => {
            if (type === 'ml') {
                // Use local policy for ML bots
                return BotStrategyFactory.create('ml', { policy: localPolicy, useSharedPolicy: false });
            }
            return BotStrategyFactory.create(type);
        });

        // Run the game
        const engine = new HeadlessGameEngine(strategies);
        const result = engine.runGame();

        // Record stats
        stats.recordGame(result, strategyTypes);

        // Trigger ML learning (updates local policy)
        strategies.forEach((strategy, index) => {
            if (strategy.onGameEnd) {
                strategy.onGameEnd(result, index);
            }
        });
    }

    // Calculate delta Q-values (only changes from this batch)
    const deltaQValues = {};
    for (const [contextKey, actions] of Object.entries(localPolicy.qValues)) {
        const startActions = startQValues[contextKey] || {};

        for (const [actionKey, data] of Object.entries(actions)) {
            const startData = startActions[actionKey];

            // Only include if there are new samples
            if (!startData || data.count > startData.count) {
                if (!deltaQValues[contextKey]) {
                    deltaQValues[contextKey] = {};
                }

                if (!startData) {
                    // Completely new entry
                    deltaQValues[contextKey][actionKey] = { ...data };
                } else {
                    // Calculate delta
                    const deltaCount = data.count - startData.count;
                    if (deltaCount > 0) {
                        const deltaSum = data.sum - startData.sum;
                        const deltaMean = deltaSum / deltaCount;
                        deltaQValues[contextKey][actionKey] = {
                            sum: deltaSum,
                            count: deltaCount,
                            mean: deltaMean
                        };
                    }
                }
            }
        }
    }

    return {
        stats: stats.toJSON(),
        deltaQValues,
        gamesPlayed: batchSize,
        workerId
    };
}

// Listen for messages from main thread
parentPort.on('message', (msg) => {
    switch (msg.type) {
        case 'runBatch':
            try {
                const result = runBatch(msg.batchSize, msg.trackDecisions);
                parentPort.postMessage({ type: 'batchComplete', result });
            } catch (error) {
                parentPort.postMessage({
                    type: 'error',
                    error: error.message,
                    stack: error.stack
                });
            }
            break;

        case 'updatePolicy':
            // Sync policy from main thread
            if (msg.policyState) {
                localPolicy.fromJSON(msg.policyState);
            }
            parentPort.postMessage({ type: 'policyUpdated' });
            break;

        case 'getStats':
            parentPort.postMessage({
                type: 'stats',
                stats: {
                    epsilon: localPolicy.epsilon,
                    contextCount: Object.keys(localPolicy.qValues).length,
                    totalUpdates: localPolicy.totalUpdates
                }
            });
            break;

        case 'ping':
            parentPort.postMessage({ type: 'pong', workerId });
            break;

        default:
            parentPort.postMessage({
                type: 'error',
                error: `Unknown message type: ${msg.type}`
            });
    }
});

// Signal ready
parentPort.postMessage({ type: 'ready', workerId });
