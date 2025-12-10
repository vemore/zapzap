#!/usr/bin/env node

/**
 * run-simulation.js
 * CLI tool for running ML bot training simulations
 *
 * Usage:
 *   node scripts/run-simulation.js --games 10000 --strategies ml,hard,medium,easy
 *   node scripts/run-simulation.js --games 50000 --strategies ml,hard_vince,hard,medium --model mybot
 *   node scripts/run-simulation.js --games 100000 --parallel --workers 16
 */

const os = require('os');
const path = require('path');
const SimulationRunner = require('../src/simulation/SimulationRunner');
const ParallelSimulationRunner = require('../src/simulation/ParallelSimulationRunner');
const ParallelDRLRunner = require('../src/simulation/ParallelDRLRunner');
const CurriculumDRLRunner = require('../src/simulation/CurriculumDRLRunner');
const ImitationLearner = require('../src/simulation/ImitationLearner');
const BotStrategyFactory = require('../src/infrastructure/bot/strategies/BotStrategyFactory');
const BanditPolicy = require('../src/infrastructure/bot/ml/BanditPolicy');
const ModelStorage = require('../src/infrastructure/bot/ml/ModelStorage');

// Parse command line arguments
function parseArgs(args) {
    // Optimal workers: benchmarks show 12 workers is the sweet spot
    // Beyond 12, serialization overhead reduces performance
    const optimalWorkers = Math.min(12, os.cpus().length);

    const parsed = {
        games: 10000,
        strategies: ['ml', 'hard', 'medium', 'easy'],
        model: 'default',
        batch: 1000,
        save: 5000,
        fair: false,
        verbose: false,
        parallel: false,
        workers: optimalWorkers,
        drl: false,
        trainFreq: 64,
        trainIterations: 4,
        pretrain: false,
        pretrainGames: 1000,
        pretrainIterations: 100,
        curriculum: false,
        curriculumWinRate: 0.20,
        curriculumMinGames: 5000,
        curriculumMaxGames: 20000
    };

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];

        if (arg === '--games' || arg === '-g') {
            parsed.games = parseInt(args[++i], 10);
        } else if (arg === '--strategies' || arg === '-s') {
            parsed.strategies = args[++i].split(',').map(s => s.trim());
        } else if (arg === '--model' || arg === '-m') {
            parsed.model = args[++i];
        } else if (arg === '--batch' || arg === '-b') {
            parsed.batch = parseInt(args[++i], 10);
        } else if (arg === '--save') {
            parsed.save = parseInt(args[++i], 10);
        } else if (arg === '--fair') {
            parsed.fair = true;
        } else if (arg === '--verbose' || arg === '-v') {
            parsed.verbose = true;
        } else if (arg === '--parallel' || arg === '-p') {
            parsed.parallel = true;
        } else if (arg === '--workers' || arg === '-w') {
            parsed.workers = parseInt(args[++i], 10);
        } else if (arg === '--drl') {
            parsed.drl = true;
        } else if (arg === '--train-freq') {
            parsed.trainFreq = parseInt(args[++i], 10);
        } else if (arg === '--train-iterations') {
            parsed.trainIterations = parseInt(args[++i], 10);
        } else if (arg === '--pretrain') {
            parsed.pretrain = true;
        } else if (arg === '--pretrain-games') {
            parsed.pretrainGames = parseInt(args[++i], 10);
        } else if (arg === '--pretrain-iterations') {
            parsed.pretrainIterations = parseInt(args[++i], 10);
        } else if (arg === '--curriculum' || arg === '-c') {
            parsed.curriculum = true;
        } else if (arg === '--curriculum-win-rate') {
            parsed.curriculumWinRate = parseFloat(args[++i]);
        } else if (arg === '--curriculum-min-games') {
            parsed.curriculumMinGames = parseInt(args[++i], 10);
        } else if (arg === '--curriculum-max-games') {
            parsed.curriculumMaxGames = parseInt(args[++i], 10);
        } else if (arg === '--help' || arg === '-h') {
            printHelp();
            process.exit(0);
        }
    }

    return parsed;
}

function printHelp() {
    console.log(`
ZapZap ML Training Simulator

Usage:
  node scripts/run-simulation.js [options]

Options:
  --games, -g <n>       Number of games to simulate (default: 10000)
  --strategies, -s <s>  Comma-separated strategy types (default: ml,hard,medium,easy)
                        Available: easy, medium, hard, hard_vince, ml, drl
  --model, -m <id>      Model ID for saving/loading (default: 'default')
  --batch, -b <n>       Batch size for progress reporting (default: 1000)
  --save <n>            Save model every N games (default: 5000)
  --fair                Run fair simulations (rotate positions)
  --parallel, -p        Enable parallel execution using worker threads
  --workers, -w <n>     Number of worker threads (default: 12 or CPU count if less)
  --drl                 Use Deep RL training (Double DQN with Prioritized Replay)
  --train-freq <n>      Training frequency for DRL (default: 64 games)
  --train-iterations <n> Training iterations per cycle for DRL (default: 4)
  --pretrain            Pre-train DRL with expert demonstrations (HardVince games)
  --pretrain-games <n>  Number of games for pre-training (default: 1000)
  --pretrain-iterations <n> Training iterations for pre-training (default: 100)
  --curriculum, -c      Use curriculum learning (progressive difficulty)
  --curriculum-win-rate <r> Win rate threshold to advance phase (default: 0.20)
  --curriculum-min-games <n> Minimum games per phase (default: 5000)
  --curriculum-max-games <n> Maximum games per phase (default: 20000)
  --verbose, -v         Verbose output
  --help, -h            Show this help

Examples:
  # Train ML bot (bandit) against all difficulties
  node scripts/run-simulation.js --games 50000

  # ML bot vs hard_vince only
  node scripts/run-simulation.js -g 20000 -s ml,hard_vince,hard_vince,hard_vince

  # Compare all bots (no ML)
  node scripts/run-simulation.js -g 10000 -s easy,medium,hard,hard_vince

  # Fair comparison with position rotation
  node scripts/run-simulation.js -g 10000 -s ml,hard,medium,easy --fair

  # Parallel execution with 16 workers
  node scripts/run-simulation.js -g 100000 -s ml,hard,hard,hard --parallel

  # Parallel execution with custom worker count
  node scripts/run-simulation.js -g 100000 --parallel --workers 8

  # Deep RL training (parallel)
  node scripts/run-simulation.js -g 100000 -s drl,hard_vince,hard,hard --drl

  # Deep RL with custom training parameters
  node scripts/run-simulation.js -g 50000 -s drl,hard_vince,hard_vince,hard --drl --train-freq 32

  # Deep RL with pre-training from HardVince games
  node scripts/run-simulation.js -g 50000 -s drl,hard_vince,hard_vince,hard --drl --pretrain --pretrain-games 2000

  # Curriculum learning (progressive difficulty: easy → medium → hard → hard_vince)
  node scripts/run-simulation.js -g 100000 --curriculum

  # Curriculum learning with custom thresholds
  node scripts/run-simulation.js -g 200000 --curriculum --curriculum-win-rate 0.25 --curriculum-min-games 10000
`);
}

async function main() {
    const args = parseArgs(process.argv.slice(2));

    console.log('\n====================================');
    console.log('  ZapZap ML Training Simulator');
    console.log('====================================\n');

    console.log('Configuration:');
    console.log(`  Games: ${args.games.toLocaleString()}`);
    console.log(`  Strategies: ${args.strategies.join(', ')}`);
    console.log(`  Model ID: ${args.model}`);
    console.log(`  Batch size: ${args.batch}`);
    console.log(`  Fair mode: ${args.fair}`);
    console.log(`  Parallel mode: ${args.parallel}${args.parallel ? ` (${args.workers} workers)` : ''}`);
    console.log(`  DRL mode: ${args.drl}`);
    console.log(`  Pre-train: ${args.pretrain}${args.pretrain ? ` (${args.pretrainGames} games, ${args.pretrainIterations} iterations)` : ''}`);
    console.log(`  Curriculum: ${args.curriculum}${args.curriculum ? ` (win rate: ${(args.curriculumWinRate * 100).toFixed(0)}%, ${args.curriculumMinGames}-${args.curriculumMaxGames} games/phase)` : ''}`);
    console.log('');

    // Validate strategies
    const validStrategies = BotStrategyFactory.getAvailableDifficulties();
    for (const strategy of args.strategies) {
        if (!validStrategies.includes(strategy)) {
            console.error(`Error: Invalid strategy '${strategy}'`);
            console.error(`Valid strategies: ${validStrategies.join(', ')}`);
            process.exit(1);
        }
    }

    // Check if ML or DRL is included
    const hasML = args.strategies.includes('ml');
    const hasDRL = args.strategies.includes('drl') || args.drl;

    // Load existing model if available
    const storage = new ModelStorage();
    let policy = new BanditPolicy();
    let drlPolicy = null;

    if (hasML && !args.drl) {
        const existingModel = await storage.load(args.model);
        if (existingModel) {
            console.log(`Loaded existing model: ${args.model}`);
            console.log(`  Previous games: ${existingModel.weights?.totalUpdates || 0}`);
            policy.fromJSON(existingModel.weights);
        } else {
            console.log(`Creating new model: ${args.model}`);
        }

        // Set shared policy for ML bots
        BotStrategyFactory.setSharedMLPolicy(policy);
    }

    // DRL mode uses neural network, not bandit
    if (hasDRL || args.drl) {
        // Replace 'ml' with 'drl' in strategies if using DRL mode
        if (args.drl && args.strategies.includes('ml')) {
            args.strategies = args.strategies.map(s => s === 'ml' ? 'drl' : s);
            console.log(`DRL mode: Replaced 'ml' with 'drl' in strategies`);
        }
    }

    // Create progress callback
    let lastSaveGames = 0;
    const onProgress = async (progress) => {
        const pct = (progress.completed / progress.total * 100).toFixed(1);
        const winRates = progress.stats.getWinRates ? progress.stats.getWinRates() : progress.stats.winRates || {};
        const mlWinRate = winRates.ml || 0;
        const gps = progress.gamesPerSecond?.toFixed(0) || '?';

        // Clear line and print progress
        process.stdout.write(`\rProgress: ${progress.completed.toLocaleString()}/${progress.total.toLocaleString()} (${pct}%) | ML: ${(mlWinRate * 100).toFixed(1)}% | ${gps} games/sec    `);

        // Save periodically
        if (hasML && progress.completed - lastSaveGames >= args.save) {
            lastSaveGames = progress.completed;
            await storage.save(args.model, policy.toJSON(), {
                gamesPlayed: progress.completed,
                strategies: args.strategies,
                winRates
            });
            if (args.verbose) {
                console.log(`\n  [Saved model at ${progress.completed} games]`);
            }
        }
    };

    // Create runner based on mode
    let runner;
    let isDRLRunner = false;
    let isCurriculumRunner = false;

    if (args.curriculum) {
        // Curriculum learning mode
        isCurriculumRunner = true;
        isDRLRunner = true;

        runner = new CurriculumDRLRunner({
            totalGames: args.games,
            numWorkers: args.workers,
            winRateThreshold: args.curriculumWinRate,
            minGamesPerPhase: args.curriculumMinGames,
            maxGamesPerPhase: args.curriculumMaxGames,
            onProgress: (progress) => {
                const pct = (progress.totalGamesPlayed / args.games * 100).toFixed(1);
                const drlWinRate = progress.drlWinRate || 0;
                const phaseName = progress.phaseName || 'Phase ?';

                process.stdout.write(`\r[${phaseName}] ${progress.gamesCompleted.toLocaleString()} games | DRL: ${(drlWinRate * 100).toFixed(1)}% | Total: ${progress.totalGamesPlayed.toLocaleString()}/${args.games.toLocaleString()} (${pct}%)    `);
            },
            onPhaseChange: (phaseInfo) => {
                console.log(`\n\n>>> Advancing to ${phaseInfo.name} (total games: ${phaseInfo.totalGamesPlayed.toLocaleString()})`);
            }
        });

        // Pre-training with expert demonstrations if requested
        if (args.pretrain) {
            console.log('\n====================================');
            console.log('  Pre-training with Expert Demonstrations');
            console.log('====================================\n');

            const DRLPolicy = require('../src/infrastructure/bot/ml/DRLPolicy');
            const pretrainPolicy = new DRLPolicy({
                inputDim: 45,
                bufferSize: 100000,
                batchSize: 64,
                epsilon: 0.15,
                minEpsilon: 0.02,
                learningRate: 0.0005
            });

            const imitationLearner = new ImitationLearner({
                expertType: 'hard_vince',
                numExperts: 4,
                onProgress: (p) => {
                    process.stdout.write(`\rCollecting: ${p.gamesCompleted}/${p.totalGames} games | ${p.transitionsCollected} transitions    `);
                }
            });

            const { transitions } = imitationLearner.collectDemonstrations(args.pretrainGames);
            await imitationLearner.preTrain(pretrainPolicy, transitions, args.pretrainIterations);
            runner.setPolicy(pretrainPolicy);

            console.log('\nPre-training complete. Starting curriculum training...\n');
        }
    } else if (hasDRL || args.drl) {
        // Use DRL parallel runner
        isDRLRunner = true;
        runner = new ParallelDRLRunner({
            numWorkers: args.workers,
            batchPerWorker: 16,
            trainEveryNGames: args.trainFreq,
            trainIterations: args.trainIterations,
            onProgress: (progress) => {
                const pct = (progress.gamesCompleted / progress.totalGames * 100).toFixed(1);
                const winRates = progress.stats?.winRates || {};
                const drlWinRate = winRates.drl || 0;
                const elapsed = (progress.elapsed / 1000).toFixed(0);
                const gps = progress.gamesCompleted / (progress.elapsed / 1000) || 0;
                const bufferSize = progress.policyStats?.bufferSize || 0;
                const epsilon = progress.policyStats?.epsilon?.toFixed(3) || '?';

                process.stdout.write(`\rProgress: ${progress.gamesCompleted.toLocaleString()}/${progress.totalGames.toLocaleString()} (${pct}%) | DRL: ${(drlWinRate * 100).toFixed(1)}% | Buffer: ${bufferSize} | ε: ${epsilon} | ${gps.toFixed(0)} g/s    `);
            }
        });

        // Pre-training with expert demonstrations (HardVince)
        if (args.pretrain) {
            console.log('\n====================================');
            console.log('  Pre-training with Expert Demonstrations');
            console.log('====================================\n');

            const DRLPolicy = require('../src/infrastructure/bot/ml/DRLPolicy');
            const pretrainPolicy = new DRLPolicy({
                inputDim: 45,
                bufferSize: 100000,
                batchSize: 64,
                epsilon: 0.15,  // Start with moderate exploration after pre-training
                minEpsilon: 0.02,
                learningRate: 0.0005
            });

            const imitationLearner = new ImitationLearner({
                expertType: 'hard_vince',
                numExperts: 4,
                onProgress: (p) => {
                    process.stdout.write(`\rCollecting: ${p.gamesCompleted}/${p.totalGames} games | ${p.transitionsCollected} transitions    `);
                }
            });

            // Collect expert demonstrations
            const { transitions } = imitationLearner.collectDemonstrations(args.pretrainGames);

            // Pre-train the policy
            await imitationLearner.preTrain(pretrainPolicy, transitions, args.pretrainIterations);

            // Set the pre-trained policy on the runner
            runner.setPolicy(pretrainPolicy);

            console.log('\nPre-training complete. Starting main training...\n');
        }
    } else if (args.parallel) {
        runner = new ParallelSimulationRunner({
            numWorkers: args.workers,
            batchPerWorker: 64,
            onProgress
        });
    } else {
        runner = new SimulationRunner({
            batchSize: args.batch,
            onProgress
        });
    }

    console.log(`\nStarting ${args.games.toLocaleString()} game simulation...\n`);
    const startTime = Date.now();

    // Run simulations
    let statsOrResult;
    if (isCurriculumRunner) {
        // Curriculum learning mode
        const curriculumResult = await runner.run();
        statsOrResult = curriculumResult.stats;
        drlPolicy = curriculumResult.policy;
    } else if (isDRLRunner) {
        // DRL mode
        const drlResult = await runner.runSimulations(args.games, args.strategies, {
            inputDim: 45,
            bufferSize: 100000,
            batchSize: 64,
            epsilon: 0.3,
            minEpsilon: 0.02,
            learningRate: 0.0005
        });
        statsOrResult = drlResult.stats;
        drlPolicy = drlResult.policy;
    } else if (args.parallel) {
        // Parallel mode - returns SimulationStats directly
        statsOrResult = await runner.runSimulations(args.games, args.strategies, policy);
    } else if (args.fair) {
        const gamesPerRotation = Math.ceil(args.games / args.strategies.length);
        statsOrResult = await runner.runFairSimulations(gamesPerRotation, args.strategies);
    } else {
        statsOrResult = await runner.runSimulations(args.games, args.strategies);
    }

    const duration = (Date.now() - startTime) / 1000;

    // Get summary from stats - handle both SimulationStats object and result object
    let summary;
    if (statsOrResult.getSummary) {
        // It's a SimulationStats object (parallel mode)
        summary = statsOrResult.getSummary();
    } else if (statsOrResult.results) {
        // It's a result object from sequential mode
        summary = statsOrResult.results;
    } else {
        summary = statsOrResult;
    }

    // Clear progress line
    console.log('\n');

    // Print results
    console.log('====================================');
    console.log('  Simulation Complete!');
    console.log('====================================\n');

    console.log(`Total games: ${summary.gamesPlayed.toLocaleString()}`);
    console.log(`Duration: ${duration.toFixed(1)}s`);
    console.log(`Speed: ${(summary.gamesPlayed / duration).toFixed(0)} games/sec`);
    console.log(`Average rounds per game: ${summary.avgRounds.toFixed(1)}`);

    console.log('\nWin Rates by Strategy:');
    const sortedWinRates = Object.entries(summary.winRates)
        .sort((a, b) => b[1] - a[1]);

    for (const [strategy, rate] of sortedWinRates) {
        const bar = '█'.repeat(Math.round(rate * 40));
        console.log(`  ${strategy.padEnd(12)} ${(rate * 100).toFixed(1).padStart(5)}% ${bar}`);
    }

    console.log('\nWin Rates by Position:');
    for (const [pos, rate] of Object.entries(summary.winRatesByPosition)) {
        console.log(`  Player ${pos}: ${(rate * 100).toFixed(1)}%`);
    }

    console.log('\nAverage Final Scores:');
    const sortedScores = Object.entries(summary.avgScores)
        .sort((a, b) => a[1] - b[1]);

    for (const [strategy, score] of sortedScores) {
        console.log(`  ${strategy.padEnd(12)} ${score.toFixed(1)}`);
    }

    // Save final model
    if (hasML && !isDRLRunner) {
        await storage.save(args.model, policy.toJSON(), {
            gamesPlayed: summary.gamesPlayed,
            strategies: args.strategies,
            winRates: summary.winRates,
            avgScores: summary.avgScores,
            duration,
            completedAt: new Date().toISOString()
        });
        console.log(`\nModel saved: ${args.model}`);

        // Print policy stats
        const policyStats = policy.getStats();
        console.log('\nML Policy Statistics:');
        console.log(`  Unique contexts: ${policyStats.contextCount.toLocaleString()}`);
        console.log(`  Total actions: ${policyStats.totalActions.toLocaleString()}`);
        console.log(`  Total samples: ${policyStats.totalSamples.toLocaleString()}`);
        console.log(`  Final epsilon: ${policyStats.epsilon.toFixed(4)}`);
        console.log(`  Exploration rate: ${(policyStats.explorationRate * 100).toFixed(1)}%`);
    }

    // Save DRL model
    if (isDRLRunner && drlPolicy) {
        const modelPath = path.join(__dirname, '..', 'data', 'models', args.model);
        const fs = require('fs');
        if (!fs.existsSync(path.dirname(modelPath))) {
            fs.mkdirSync(path.dirname(modelPath), { recursive: true });
        }
        try {
            await drlPolicy.saveModel(modelPath);
            console.log(`\nDRL model saved: ${modelPath}`);
        } catch (err) {
            console.log(`\nNote: Could not save DRL model: ${err.message}`);
        }

        // Print DRL policy stats
        const policyStats = drlPolicy.getStats();
        console.log('\nDRL Policy Statistics:');
        console.log(`  Buffer size: ${policyStats.bufferSize.toLocaleString()}`);
        console.log(`  Train steps: ${policyStats.trainSteps.toLocaleString()}`);
        console.log(`  Final epsilon: ${policyStats.epsilon.toFixed(4)}`);
        console.log(`  Total decisions: ${policyStats.totalDecisions.toLocaleString()}`);
        console.log(`  Exploration rate: ${(policyStats.explorationRate * 100).toFixed(1)}%`);
    }

    console.log('\nDone!\n');
}

// Run
main().catch(error => {
    console.error('\nError:', error.message);
    if (process.env.DEBUG) {
        console.error(error.stack);
    }
    process.exit(1);
});
