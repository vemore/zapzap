#!/usr/bin/env node
/**
 * train-native.js - Native Rust DRL Training & Simulation Runner
 *
 * Modes:
 *   --train    Full Rust DRL training (8000+ games/sec)
 *   --bench    Run performance benchmark
 *   (default)  Run batch game simulations (~5000 games/sec)
 *
 * Usage:
 *   node scripts/train-native.js [options]
 *
 * Simulation Options:
 *   --games <n>       Number of games to simulate (default: 1000)
 *   --strategies <s>  Comma-separated strategy list (default: hard,hard,hard,hard)
 *   --seed <n>        Random seed for reproducibility (optional)
 *   --quiet           Minimal output
 *
 * Training Options:
 *   --train           Enable DRL training mode
 *   --batch-size <n>  Training batch size (default: 64)
 *   --lr <n>          Learning rate (default: 0.0005)
 *   --save-path <p>   Model save path (default: data/models/rust-drl)
 *   --load <p>        Load existing model for continued training
 *
 * Examples:
 *   node scripts/train-native.js --games 10000
 *   node scripts/train-native.js --train --games 100000 --save-path data/models/my-bot
 *   node scripts/train-native.js --bench
 */

const path = require('path');

// Parse command line arguments
function parseArgs(argv) {
    const args = {
        // Modes
        train: false,
        bench: false,

        // Simulation
        games: 1000,
        strategies: ['hard', 'hard', 'hard', 'hard'],
        seed: null,
        quiet: false,
        help: false,

        // Training
        batchSize: 64,
        learningRate: 0.0005,
        epsilonStart: 1.0,
        epsilonEnd: 0.01,
        epsilonDecay: 50000,
        gamma: 0.99,
        tau: 0.005,
        savePath: 'data/models/rust-drl',
        loadPath: null,
        saveInterval: 10000,
        gamesPerBatch: 100
    };

    for (let i = 2; i < argv.length; i++) {
        const arg = argv[i];

        // Modes
        if (arg === '--train' || arg === '-t') {
            args.train = true;
        } else if (arg === '--bench' || arg === '--benchmark') {
            args.bench = true;
        }
        // Help & quiet
        else if (arg === '--help' || arg === '-h') {
            args.help = true;
        } else if (arg === '--quiet' || arg === '-q') {
            args.quiet = true;
        }
        // Simulation
        else if (arg === '--games' || arg === '-g') {
            args.games = parseInt(argv[++i], 10);
        } else if (arg === '--strategies' || arg === '-s') {
            args.strategies = argv[++i].split(',').map(s => s.trim().toLowerCase());
        } else if (arg === '--seed') {
            args.seed = parseInt(argv[++i], 10);
        }
        // Training
        else if (arg === '--batch-size' || arg === '-b') {
            args.batchSize = parseInt(argv[++i], 10);
        } else if (arg === '--lr' || arg === '--learning-rate') {
            args.learningRate = parseFloat(argv[++i]);
        } else if (arg === '--epsilon-start') {
            args.epsilonStart = parseFloat(argv[++i]);
        } else if (arg === '--epsilon-end') {
            args.epsilonEnd = parseFloat(argv[++i]);
        } else if (arg === '--epsilon-decay') {
            args.epsilonDecay = parseInt(argv[++i], 10);
        } else if (arg === '--gamma') {
            args.gamma = parseFloat(argv[++i]);
        } else if (arg === '--tau') {
            args.tau = parseFloat(argv[++i]);
        } else if (arg === '--save-path' || arg === '-o') {
            args.savePath = argv[++i];
        } else if (arg === '--load' || arg === '-l') {
            args.loadPath = argv[++i];
        } else if (arg === '--save-interval') {
            args.saveInterval = parseInt(argv[++i], 10);
        } else if (arg === '--games-per-batch') {
            args.gamesPerBatch = parseInt(argv[++i], 10);
        }
    }

    return args;
}

function showHelp() {
    console.log(`
train-native.js - Native Rust DRL Training & Simulation Runner

MODES:
  --train, -t         Enable DRL training mode (Full Rust)
  --bench             Run performance benchmark
  (default)           Run batch simulations

SIMULATION OPTIONS:
  --games, -g <n>       Number of games (default: 1000)
  --strategies, -s <s>  Comma-separated strategy list
                        Available: hard, hard_vince, random, drl
  --seed <n>            Random seed for reproducibility
  --quiet, -q           Minimal output

TRAINING OPTIONS:
  --batch-size, -b <n>  Training batch size (default: 64)
  --lr <n>              Learning rate (default: 0.0005)
  --epsilon-start <n>   Initial exploration (default: 1.0)
  --epsilon-end <n>     Final exploration (default: 0.01)
  --epsilon-decay <n>   Steps to decay epsilon (default: 50000)
  --gamma <n>           Discount factor (default: 0.99)
  --tau <n>             Target network soft update (default: 0.005)
  --save-path, -o <p>   Model save path (default: data/models/rust-drl)
  --load, -l <p>        Load model for continued training
  --save-interval <n>   Save every N games (default: 10000)

EXAMPLES:
  # Run simulation benchmark
  node scripts/train-native.js --games 10000

  # Run performance benchmark
  node scripts/train-native.js --bench

  # Start DRL training
  node scripts/train-native.js --train --games 100000

  # Continue training from checkpoint
  node scripts/train-native.js --train --games 50000 --load data/models/rust-drl
`);
}

// Format number with commas
function formatNumber(n) {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

// Run performance benchmark
async function runBenchmark(native) {
    console.log('\n=== Native Rust Performance Benchmark ===\n');

    // Benchmark game simulation
    console.log('Benchmarking game simulation...');
    const simResult = native.benchmarkSimulation(1000, ['hard', 'hard', 'hard', 'hard']);
    console.log(`  Games/sec: ${formatNumber(Math.round(simResult.gamesPerSecond))}`);
    console.log(`  Total time: ${simResult.totalMs.toFixed(1)}ms for 1000 games`);

    // Benchmark feature extraction
    console.log('\nBenchmarking feature extraction...');
    const featureResult = native.benchmarkFeatureExtraction(10000);
    console.log(`  Ops/sec: ${formatNumber(Math.round(featureResult.opsPerSecond))}`);
    console.log(`  Total time: ${featureResult.totalMs.toFixed(1)}ms for 10000 ops`);

    // Benchmark DQN inference
    console.log('\nBenchmarking DQN inference...');
    native.dqnInit();
    const dqnResult = native.benchmarkDqnInference(10000);
    console.log(`  Ops/sec: ${formatNumber(Math.round(dqnResult.opsPerSecond))}`);
    console.log(`  Total time: ${dqnResult.totalMs.toFixed(1)}ms for 10000 ops`);

    console.log('\n=== Benchmark Complete ===\n');
}

// Run DRL training (Full Rust)
async function runTraining(native, args) {
    console.log('\n=== Full Rust DRL Training ===\n');
    console.log('Configuration:');
    console.log(`  Total games: ${formatNumber(args.games)}`);
    console.log(`  Batch size: ${args.batchSize}`);
    console.log(`  Learning rate: ${args.learningRate}`);
    console.log(`  Epsilon: ${args.epsilonStart} -> ${args.epsilonEnd} over ${formatNumber(args.epsilonDecay)} steps`);
    console.log(`  Gamma: ${args.gamma}`);
    console.log(`  Tau: ${args.tau}`);
    console.log(`  Strategies: ${args.strategies.join(', ')}`);
    console.log(`  Save path: ${args.savePath}`);
    console.log('');

    // Create training config
    const trainingConfig = {
        totalGames: args.games,
        gamesPerBatch: args.gamesPerBatch,
        batchSize: args.batchSize,
        learningRate: args.learningRate,
        epsilonStart: args.epsilonStart,
        epsilonEnd: args.epsilonEnd,
        epsilonDecay: args.epsilonDecay,
        gamma: args.gamma,
        tau: args.tau,
        bufferCapacity: 1000000,    // 1M transitions
        targetUpdateFreq: 1000,     // Update target network every 1000 steps
    };

    // Create trainer
    const trainerId = native.trainerCreate(trainingConfig);
    if (trainerId < 0) {
        console.error('Failed to create trainer');
        process.exit(1);
    }
    console.log(`Trainer created (ID: ${trainerId})`);

    // Load existing model if specified
    if (args.loadPath) {
        const modelPath = args.loadPath.endsWith('.safetensors')
            ? args.loadPath
            : args.loadPath + '.safetensors';

        if (native.modelExists(modelPath)) {
            console.log(`Loading model from: ${modelPath}`);
            const weights = native.modelLoad(modelPath);
            if (weights) {
                native.trainerSetWeights(trainerId, weights);
                console.log(`Loaded ${formatNumber(weights.length)} weights`);
            }
        } else {
            console.log(`Model not found at: ${modelPath}`);
        }
    }

    // Run simulation to demonstrate performance
    console.log('\nRunning simulation benchmark...\n');
    const simStart = Date.now();
    const results = native.runGamesBatch(args.strategies, Math.min(args.games, 10000), Date.now());
    const simElapsed = Date.now() - simStart;

    console.log('Simulation Results:');
    console.log(`  Games: ${formatNumber(results.gamesPlayed)}`);
    console.log(`  Time: ${(simElapsed / 1000).toFixed(2)}s`);
    console.log(`  Speed: ${formatNumber(Math.round(results.gamesPerSecond))} games/sec`);
    console.log('');
    console.log('Win Distribution:');
    for (let i = 0; i < results.wins.length; i++) {
        const winRate = (results.wins[i] / results.gamesPlayed * 100).toFixed(1);
        const strategy = args.strategies[i] || `Player ${i}`;
        console.log(`  ${strategy}: ${formatNumber(results.wins[i])} wins (${winRate}%)`);
    }

    // Get trainer state
    const state = native.trainerGetState(trainerId);
    if (state) {
        console.log('\nTrainer State:');
        console.log(`  Buffer size: ${native.trainerBufferSize(trainerId)}`);
        console.log(`  Games played: ${formatNumber(state.gamesPlayed)}`);
        console.log(`  Steps: ${formatNumber(state.steps)}`);
        console.log(`  Epsilon: ${state.epsilon.toFixed(4)}`);
    }

    console.log(`\nModel save path: ${args.savePath}.safetensors`);
    console.log('(Full training loop integration in progress)');
    console.log('\n=== Training Session Complete ===\n');
}

// Run simulation
async function runSimulation(native, args) {
    const { games, strategies, seed, quiet } = args;

    if (!quiet) {
        console.log('========================================');
        console.log('ZapZap Native Simulation Runner');
        console.log('========================================');
        console.log(`Games:      ${games.toLocaleString()}`);
        console.log(`Strategies: [${strategies.join(', ')}]`);
        console.log(`Seed:       ${seed !== null ? seed : 'random'}`);
        console.log('----------------------------------------');
    }

    // Run simulation
    const startTime = Date.now();
    const stats = native.runGamesBatch(strategies, games, seed);
    const elapsedMs = Date.now() - startTime;

    // Calculate win percentages
    const winPercentages = stats.wins.map(w => ((w / games) * 100).toFixed(1));

    if (!quiet) {
        console.log('\nResults:');
        console.log('----------------------------------------');
        console.log(`Games played:    ${stats.gamesPlayed.toLocaleString()}`);
        console.log(`Total time:      ${(stats.totalTimeMs / 1000).toFixed(2)}s`);
        console.log(`Speed:           ${stats.gamesPerSecond.toFixed(0)} games/sec`);
        console.log(`Avg rounds/game: ${stats.avgRounds.toFixed(1)}`);
        console.log('');
        console.log('Win distribution:');
        stats.wins.forEach((wins, i) => {
            const pct = winPercentages[i];
            const bar = '█'.repeat(Math.round(pct / 5));
            console.log(`  Player ${i}: ${wins.toString().padStart(6)} wins (${pct.padStart(5)}%) ${bar}`);
        });
        console.log('========================================');
    } else {
        // Quiet mode: just print JSON
        console.log(JSON.stringify({
            games: stats.gamesPlayed,
            wins: stats.wins,
            winPct: winPercentages.map(p => parseFloat(p)),
            avgRounds: parseFloat(stats.avgRounds.toFixed(1)),
            gamesPerSec: Math.round(stats.gamesPerSecond),
            timeMs: Math.round(stats.totalTimeMs)
        }));
    }

    // Verify balanced distribution (warn if unbalanced)
    const maxWinPct = Math.max(...winPercentages.map(p => parseFloat(p)));
    const minWinPct = Math.min(...winPercentages.map(p => parseFloat(p)));

    if (maxWinPct - minWinPct > 20 && !quiet) {
        console.log('\n⚠️  Warning: Win distribution appears unbalanced.');
        console.log('   This may indicate a bug in the strategy implementation.');
    }

    return stats;
}

async function main() {
    const args = parseArgs(process.argv);

    if (args.help) {
        showHelp();
        process.exit(0);
    }

    // Load native module
    let native;
    try {
        native = require(path.join(__dirname, '../native/index.js'));
    } catch (err) {
        console.error('Error: Native module not found.');
        console.error('Please build it first: cd native && npm run build');
        console.error(`Details: ${err.message}`);
        process.exit(1);
    }

    // Dispatch to appropriate handler
    if (args.bench) {
        await runBenchmark(native);
    } else if (args.train) {
        await runTraining(native, args);
    } else {
        return await runSimulation(native, args);
    }
}

// Run if called directly
if (require.main === module) {
    main().catch(err => {
        console.error('Error:', err.message);
        process.exit(1);
    });
}

module.exports = { main, parseArgs };
