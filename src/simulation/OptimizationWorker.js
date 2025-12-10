/**
 * OptimizationWorker
 * Worker thread for parallel HardVince parameter optimization
 * Runs batches of games with custom parameters and returns win statistics
 */

const { parentPort, workerData } = require('worker_threads');

const HeadlessGameEngine = require('./HeadlessGameEngine');
const HardVinceBotStrategy = require('../infrastructure/bot/strategies/HardVinceBotStrategy');
const BotStrategyFactory = require('../infrastructure/bot/strategies/BotStrategyFactory');

// Worker ID for debugging
const workerId = workerData.workerId || 0;

/**
 * Run a batch of games with specific parameters
 * @param {Object} params - HardVinceBotStrategy parameters
 * @param {number} numGames - Number of games to run
 * @param {number} hardVincePosition - Position of hard_vince bot (0-3)
 * @returns {Object} Statistics
 */
function runBatch(params, numGames, hardVincePosition) {
    let wins = 0;
    let totalScore = 0;

    for (let i = 0; i < numGames; i++) {
        // Create strategies: 3 hard bots + 1 hard_vince with custom params
        const strategies = [];
        for (let pos = 0; pos < 4; pos++) {
            if (pos === hardVincePosition) {
                strategies.push(new HardVinceBotStrategy(params));
            } else {
                strategies.push(BotStrategyFactory.create('hard'));
            }
        }

        // Run game
        const engine = new HeadlessGameEngine(strategies);
        const result = engine.runGame();

        // Track results
        if (result.winner === hardVincePosition) {
            wins++;
        }

        // Track average score (lower is better)
        if (result.finalScores && result.finalScores[hardVincePosition] !== undefined) {
            totalScore += result.finalScores[hardVincePosition];
        }
    }

    return {
        gamesPlayed: numGames,
        wins,
        winRate: wins / numGames,
        avgScore: totalScore / numGames,
        workerId
    };
}

// Listen for messages from main thread
parentPort.on('message', (msg) => {
    switch (msg.type) {
        case 'runBatch':
            try {
                const result = runBatch(msg.params, msg.numGames, msg.hardVincePosition);
                parentPort.postMessage({ type: 'batchComplete', result });
            } catch (error) {
                parentPort.postMessage({
                    type: 'error',
                    error: error.message,
                    stack: error.stack
                });
            }
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
