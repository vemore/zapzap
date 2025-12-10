#!/usr/bin/env node

/**
 * optimize-hard-vince.js
 * Parameter optimization script for HardVinceBotStrategy
 *
 * This script systematically tests different parameter values to find
 * the optimal configuration for the hard_vince bot strategy.
 *
 * Usage:
 *   node scripts/optimize-hard-vince.js
 *   node scripts/optimize-hard-vince.js --games 2000 --variations 0.5,0.8,1.2,1.5
 *   node scripts/optimize-hard-vince.js --param jokerPairSetPenalty
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { Worker } = require('worker_threads');
const HeadlessGameEngine = require('../src/simulation/HeadlessGameEngine');
const HardVinceBotStrategy = require('../src/infrastructure/bot/strategies/HardVinceBotStrategy');
const BotStrategyFactory = require('../src/infrastructure/bot/strategies/BotStrategyFactory');

// Parse command line arguments
function parseArgs(args) {
    const parsed = {
        games: 1000,
        variations: [0.5, 0.8, 1.0, 1.2, 1.5],  // Multipliers: -50%, -20%, base, +20%, +50%
        param: null,  // If set, only optimize this parameter
        output: 'data/hard_vince_optimized_params.json',
        verbose: false,
        position: 2,  // Position of hard_vince bot (0-3)
        parallel: false,  // Use parallel workers
        workers: os.cpus().length  // Number of workers
    };

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--games' || arg === '-g') {
            parsed.games = parseInt(args[++i], 10);
        } else if (arg === '--variations' || arg === '-var') {
            parsed.variations = args[++i].split(',').map(v => parseFloat(v.trim()));
        } else if (arg === '--param' || arg === '-p') {
            parsed.param = args[++i];
        } else if (arg === '--output' || arg === '-o') {
            parsed.output = args[++i];
        } else if (arg === '--verbose' || arg === '-v') {
            parsed.verbose = true;
        } else if (arg === '--position') {
            parsed.position = parseInt(args[++i], 10);
        } else if (arg === '--parallel') {
            parsed.parallel = true;
        } else if (arg === '--workers' || arg === '-w') {
            parsed.workers = parseInt(args[++i], 10);
        } else if (arg === '--help' || arg === '-h') {
            printHelp();
            process.exit(0);
        }
    }

    return parsed;
}

function printHelp() {
    console.log(`
HardVince Bot Parameter Optimizer

Usage:
  node scripts/optimize-hard-vince.js [options]

Options:
  --games, -g <n>       Games per configuration (default: 1000)
  --variations, -var    Multipliers to test (default: 0.5,0.8,1.0,1.2,1.5)
  --param, -p <name>    Only optimize this parameter
  --output, -o <file>   Output file (default: data/hard_vince_optimized_params.json)
  --position <n>        Position of hard_vince bot 0-3 (default: 2)
  --parallel            Use parallel workers for faster simulation
  --workers, -w <n>     Number of worker threads (default: CPU count)
  --verbose, -v         Verbose output
  --help, -h            Show this help

Examples:
  # Full optimization with 1000 games per config
  node scripts/optimize-hard-vince.js

  # Quick test with fewer games
  node scripts/optimize-hard-vince.js --games 500

  # Optimize only one parameter
  node scripts/optimize-hard-vince.js --param jokerPairSetPenalty --games 2000

  # Custom variation range
  node scripts/optimize-hard-vince.js --variations 0.25,0.5,1.0,2.0,4.0

  # Parallel mode for faster optimization
  node scripts/optimize-hard-vince.js --parallel --workers 8
`);
}

/**
 * Run simulation with specific parameters
 * @param {Object} params - Parameters for HardVinceBotStrategy
 * @param {number} numGames - Number of games to run
 * @param {number} hardVincePosition - Position of the hard_vince bot
 * @returns {Object} Statistics
 */
function runSimulation(params, numGames, hardVincePosition = 2) {
    let wins = 0;
    let totalScore = 0;
    let gamesPlayed = 0;

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
        gamesPlayed++;
        if (result.winner === hardVincePosition) {
            wins++;
        }

        // Track average score (lower is better in this game)
        if (result.finalScores && result.finalScores[hardVincePosition] !== undefined) {
            totalScore += result.finalScores[hardVincePosition];
        }
    }

    return {
        gamesPlayed,
        wins,
        winRate: wins / gamesPlayed,
        avgScore: totalScore / gamesPlayed
    };
}

/**
 * Calculate new parameter value with variation
 */
function applyVariation(baseValue, multiplier) {
    // For negative values, multiplier affects absolute value
    if (baseValue < 0) {
        return baseValue * multiplier;
    }
    return baseValue * multiplier;
}

/**
 * Worker pool manager for parallel simulations
 */
class WorkerPool {
    constructor(numWorkers) {
        this.numWorkers = numWorkers;
        this.workers = [];
        this.workerPath = path.join(__dirname, '../src/simulation/OptimizationWorker.js');
    }

    async init() {
        const initPromises = [];

        for (let i = 0; i < this.numWorkers; i++) {
            const worker = new Worker(this.workerPath, {
                workerData: { workerId: i }
            });

            const readyPromise = new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    reject(new Error(`Worker ${i} failed to initialize`));
                }, 10000);

                worker.once('message', (msg) => {
                    if (msg.type === 'ready') {
                        clearTimeout(timeout);
                        resolve();
                    }
                });

                worker.once('error', (err) => {
                    clearTimeout(timeout);
                    reject(err);
                });
            });

            this.workers.push(worker);
            initPromises.push(readyPromise);
        }

        await Promise.all(initPromises);
    }

    async runSimulation(params, numGames, hardVincePosition) {
        // Distribute games across workers
        const gamesPerWorker = Math.ceil(numGames / this.numWorkers);
        let remainingGames = numGames;

        const batchPromises = this.workers.map((worker, index) => {
            const workerGames = Math.min(gamesPerWorker, remainingGames);
            remainingGames -= workerGames;

            if (workerGames <= 0) {
                return Promise.resolve({ gamesPlayed: 0, wins: 0, avgScore: 0 });
            }

            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    cleanup();
                    reject(new Error(`Worker ${index} batch timeout`));
                }, 120000); // 2 minute timeout

                const cleanup = () => {
                    clearTimeout(timeout);
                    worker.removeListener('message', messageHandler);
                    worker.removeListener('error', errorHandler);
                };

                const messageHandler = (msg) => {
                    if (msg.type === 'batchComplete') {
                        cleanup();
                        resolve(msg.result);
                    } else if (msg.type === 'error') {
                        cleanup();
                        reject(new Error(msg.error));
                    }
                };

                const errorHandler = (err) => {
                    cleanup();
                    reject(err);
                };

                worker.on('message', messageHandler);
                worker.once('error', errorHandler);

                worker.postMessage({
                    type: 'runBatch',
                    params,
                    numGames: workerGames,
                    hardVincePosition
                });
            });
        });

        // Wait for all workers
        const results = await Promise.all(batchPromises);

        // Merge results
        let totalGames = 0;
        let totalWins = 0;
        let totalScore = 0;

        for (const result of results) {
            totalGames += result.gamesPlayed;
            totalWins += result.wins;
            totalScore += result.avgScore * result.gamesPlayed;
        }

        return {
            gamesPlayed: totalGames,
            wins: totalWins,
            winRate: totalWins / totalGames,
            avgScore: totalScore / totalGames
        };
    }

    async terminate() {
        const terminatePromises = this.workers.map(worker => worker.terminate());
        await Promise.all(terminatePromises);
        this.workers = [];
    }
}

/**
 * Main optimization loop
 */
async function main() {
    const args = parseArgs(process.argv.slice(2));

    console.log('\n====================================');
    console.log('  HardVince Parameter Optimizer');
    console.log('====================================\n');

    const defaultParams = HardVinceBotStrategy.DEFAULT_PARAMS;
    const paramNames = args.param ? [args.param] : Object.keys(defaultParams);

    // Validate parameter name if specified
    if (args.param && !defaultParams.hasOwnProperty(args.param)) {
        console.error(`Error: Unknown parameter '${args.param}'`);
        console.error(`Valid parameters: ${Object.keys(defaultParams).join(', ')}`);
        process.exit(1);
    }

    console.log('Configuration:');
    console.log(`  Games per config: ${args.games}`);
    console.log(`  Variations: ${args.variations.join(', ')}`);
    console.log(`  Parameters to optimize: ${paramNames.length}`);
    console.log(`  HardVince position: ${args.position}`);
    console.log(`  Total configurations: ${paramNames.length * args.variations.length}`);
    console.log(`  Estimated total games: ${(paramNames.length * args.variations.length * args.games).toLocaleString()}`);
    console.log(`  Parallel mode: ${args.parallel ? `Yes (${args.workers} workers)` : 'No'}`);
    console.log('');

    // Initialize worker pool if parallel mode
    let workerPool = null;
    if (args.parallel) {
        console.log(`Initializing ${args.workers} worker threads...`);
        workerPool = new WorkerPool(args.workers);
        await workerPool.init();
        console.log('Workers ready.\n');
    }

    // Helper function to run simulation (sequential or parallel)
    const simulate = async (params, numGames) => {
        if (workerPool) {
            return await workerPool.runSimulation(params, numGames, args.position);
        } else {
            return runSimulation(params, numGames, args.position);
        }
    };

    // First, establish baseline
    console.log('Establishing baseline with default parameters...');
    const baseline = await simulate(defaultParams, args.games);
    console.log(`Baseline: Win rate = ${(baseline.winRate * 100).toFixed(2)}%, Avg score = ${baseline.avgScore.toFixed(1)}`);
    console.log('');

    // Track best parameters
    const optimizedParams = { ...defaultParams };
    const results = {
        baseline: {
            params: { ...defaultParams },
            winRate: baseline.winRate,
            avgScore: baseline.avgScore,
            games: args.games
        },
        parameterResults: {},
        optimized: null,
        timestamp: new Date().toISOString()
    };

    // Optimize each parameter
    const startTime = Date.now();
    let configsCompleted = 0;
    const totalConfigs = paramNames.length * args.variations.length;

    for (const paramName of paramNames) {
        const baseValue = defaultParams[paramName];
        let bestValue = baseValue;
        let bestWinRate = baseline.winRate;

        console.log(`\nOptimizing: ${paramName} (base: ${baseValue})`);
        console.log('-'.repeat(50));

        const paramResults = [];

        for (const multiplier of args.variations) {
            const testValue = applyVariation(baseValue, multiplier);
            const testParams = { ...optimizedParams, [paramName]: testValue };

            // Run simulation
            const result = await simulate(testParams, args.games);
            configsCompleted++;

            const improvement = ((result.winRate - baseline.winRate) * 100).toFixed(2);
            const sign = improvement >= 0 ? '+' : '';
            const elapsed = ((Date.now() - startTime) / 1000).toFixed(0);
            const eta = ((totalConfigs - configsCompleted) * (Date.now() - startTime) / configsCompleted / 1000).toFixed(0);

            console.log(`  ${multiplier.toFixed(1)}x (${testValue.toFixed(1).padStart(8)}): ${(result.winRate * 100).toFixed(2)}% (${sign}${improvement}%) | Score: ${result.avgScore.toFixed(1)} | [${configsCompleted}/${totalConfigs}] ${elapsed}s elapsed, ~${eta}s remaining`);

            paramResults.push({
                multiplier,
                value: testValue,
                winRate: result.winRate,
                avgScore: result.avgScore,
                improvement: result.winRate - baseline.winRate
            });

            // Track best
            if (result.winRate > bestWinRate) {
                bestWinRate = result.winRate;
                bestValue = testValue;
            }
        }

        // Update optimized params if improvement found
        if (bestValue !== baseValue) {
            console.log(`  => Best: ${bestValue} (was ${baseValue}), improvement: +${((bestWinRate - baseline.winRate) * 100).toFixed(2)}%`);
            optimizedParams[paramName] = bestValue;
        } else {
            console.log(`  => Keeping default: ${baseValue}`);
        }

        results.parameterResults[paramName] = {
            baseValue,
            bestValue,
            bestWinRate,
            variations: paramResults
        };
    }

    // Final validation with all optimized parameters
    console.log('\n' + '='.repeat(50));
    console.log('Validating optimized parameters...');
    const finalResult = await simulate(optimizedParams, args.games * 2);
    console.log(`Final: Win rate = ${(finalResult.winRate * 100).toFixed(2)}%, Avg score = ${finalResult.avgScore.toFixed(1)}`);
    console.log(`Improvement over baseline: ${((finalResult.winRate - baseline.winRate) * 100).toFixed(2)}%`);

    results.optimized = {
        params: optimizedParams,
        winRate: finalResult.winRate,
        avgScore: finalResult.avgScore,
        games: args.games * 2,
        improvementOverBaseline: finalResult.winRate - baseline.winRate
    };

    // Save results
    const outputPath = path.resolve(args.output);
    const outputDir = path.dirname(outputPath);
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }
    fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
    console.log(`\nResults saved to: ${outputPath}`);

    // Print summary of changes
    console.log('\n====================================');
    console.log('  Optimized Parameters Summary');
    console.log('====================================\n');

    const changes = [];
    for (const [key, value] of Object.entries(optimizedParams)) {
        if (value !== defaultParams[key]) {
            changes.push({ key, old: defaultParams[key], new: value });
            console.log(`  ${key}: ${defaultParams[key]} -> ${value}`);
        }
    }

    if (changes.length === 0) {
        console.log('  No parameter changes recommended.');
    } else {
        console.log(`\n  Total changes: ${changes.length}`);
    }

    // Print code to update DEFAULT_PARAMS
    if (changes.length > 0) {
        console.log('\n====================================');
        console.log('  Code Update (if desired)');
        console.log('====================================\n');
        console.log('Update HardVinceBotStrategy.DEFAULT_PARAMS:');
        for (const change of changes) {
            console.log(`  ${change.key}: ${change.new},`);
        }
    }

    // Cleanup workers
    if (workerPool) {
        await workerPool.terminate();
    }

    const totalDuration = ((Date.now() - startTime) / 1000).toFixed(1);
    const totalGames = configsCompleted * args.games + args.games * 2;
    console.log(`\nTotal duration: ${totalDuration}s`);
    console.log(`Total games: ${totalGames.toLocaleString()}`);
    console.log(`Speed: ${(totalGames / parseFloat(totalDuration)).toFixed(0)} games/sec`);
    console.log('\nDone!\n');
}

// Run
main().catch(error => {
    console.error('\nError:', error.message);
    console.error(error.stack);
    process.exit(1);
});
