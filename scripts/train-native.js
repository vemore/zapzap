#!/usr/bin/env node
/**
 * train-native.js - Native Rust simulation runner for ZapZap
 *
 * Runs batch game simulations using the high-performance Rust engine.
 * Achieves ~5000 games/sec (20x faster than JS implementation).
 *
 * Usage:
 *   node scripts/train-native.js [options]
 *
 * Options:
 *   --games <n>       Number of games to simulate (default: 1000)
 *   --strategies <s>  Comma-separated strategy list (default: hard,hard,hard,hard)
 *   --seed <n>        Random seed for reproducibility (optional)
 *   --quiet           Minimal output
 *   --help            Show this help
 *
 * Examples:
 *   node scripts/train-native.js --games 10000
 *   node scripts/train-native.js --games 50000 --strategies hard,hard,hard,hard
 *   node scripts/train-native.js --games 100 --seed 42
 */

const path = require('path');

// Parse command line arguments
function parseArgs(argv) {
    const args = {
        games: 1000,
        strategies: ['hard', 'hard', 'hard', 'hard'],
        seed: null,
        quiet: false,
        help: false
    };

    for (let i = 2; i < argv.length; i++) {
        const arg = argv[i];

        if (arg === '--help' || arg === '-h') {
            args.help = true;
        } else if (arg === '--quiet' || arg === '-q') {
            args.quiet = true;
        } else if (arg === '--games' || arg === '-g') {
            args.games = parseInt(argv[++i], 10);
        } else if (arg === '--strategies' || arg === '-s') {
            args.strategies = argv[++i].split(',').map(s => s.trim().toLowerCase());
        } else if (arg === '--seed') {
            args.seed = parseInt(argv[++i], 10);
        }
    }

    return args;
}

function showHelp() {
    console.log(`
train-native.js - Native Rust simulation runner for ZapZap

Usage:
  node scripts/train-native.js [options]

Options:
  --games, -g <n>       Number of games to simulate (default: 1000)
  --strategies, -s <s>  Comma-separated strategy list (default: hard,hard,hard,hard)
                        Available: hard, random
  --seed <n>            Random seed for reproducibility (optional)
  --quiet, -q           Minimal output
  --help, -h            Show this help

Examples:
  node scripts/train-native.js --games 10000
  node scripts/train-native.js --games 50000 --strategies hard,hard,hard,hard
  node scripts/train-native.js --games 100 --seed 42
`);
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

    // Return stats for programmatic use
    return stats;
}

// Run if called directly
if (require.main === module) {
    main().catch(err => {
        console.error('Error:', err.message);
        process.exit(1);
    });
}

module.exports = { main, parseArgs };
