#!/usr/bin/env node

/**
 * genetic-optimize-hard-vince.js
 * Genetic Algorithm for optimizing HardVinceBotStrategy parameters
 *
 * Uses evolutionary optimization to find parameter combinations that
 * maximize win rate against hard bots.
 *
 * Usage:
 *   node scripts/genetic-optimize-hard-vince.js
 *   node scripts/genetic-optimize-hard-vince.js --generations 50 --population 20
 *   node scripts/genetic-optimize-hard-vince.js --elite 4 --mutation 0.15
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { Worker } = require('worker_threads');
const HardVinceBotStrategy = require('../src/infrastructure/bot/strategies/HardVinceBotStrategy');

// Parse command line arguments
function parseArgs(args) {
    const parsed = {
        generations: 30,           // Number of generations
        population: 16,            // Population size (should be even)
        elite: 2,                  // Number of elite individuals to preserve
        mutation: 0.1,             // Mutation probability per gene
        mutationRange: 0.3,        // Mutation range (±30% of value)
        crossoverRate: 0.7,        // Crossover probability
        games: 2000,               // Games per fitness evaluation
        workers: os.cpus().length, // Number of parallel workers
        output: 'data/hard_vince_genetic_params.json',
        verbose: false,
        seed: null                 // Random seed for reproducibility
    };

    for (let i = 0; i < args.length; i++) {
        const arg = args[i];
        if (arg === '--generations' || arg === '-gen') {
            parsed.generations = parseInt(args[++i], 10);
        } else if (arg === '--population' || arg === '-pop') {
            parsed.population = parseInt(args[++i], 10);
        } else if (arg === '--elite' || arg === '-e') {
            parsed.elite = parseInt(args[++i], 10);
        } else if (arg === '--mutation' || arg === '-m') {
            parsed.mutation = parseFloat(args[++i]);
        } else if (arg === '--mutation-range' || arg === '-mr') {
            parsed.mutationRange = parseFloat(args[++i]);
        } else if (arg === '--crossover' || arg === '-c') {
            parsed.crossoverRate = parseFloat(args[++i]);
        } else if (arg === '--games' || arg === '-g') {
            parsed.games = parseInt(args[++i], 10);
        } else if (arg === '--workers' || arg === '-w') {
            parsed.workers = parseInt(args[++i], 10);
        } else if (arg === '--output' || arg === '-o') {
            parsed.output = args[++i];
        } else if (arg === '--verbose' || arg === '-v') {
            parsed.verbose = true;
        } else if (arg === '--seed' || arg === '-s') {
            parsed.seed = parseInt(args[++i], 10);
        } else if (arg === '--help' || arg === '-h') {
            printHelp();
            process.exit(0);
        }
    }

    // Ensure population is even
    if (parsed.population % 2 !== 0) {
        parsed.population++;
    }

    return parsed;
}

function printHelp() {
    console.log(`
Genetic Algorithm Optimizer for HardVinceBotStrategy

Usage:
  node scripts/genetic-optimize-hard-vince.js [options]

Options:
  --generations, -gen <n>   Number of generations (default: 30)
  --population, -pop <n>    Population size (default: 16)
  --elite, -e <n>           Elite individuals preserved (default: 2)
  --mutation, -m <rate>     Mutation probability (default: 0.1)
  --mutation-range, -mr <r> Mutation range ±% (default: 0.3)
  --crossover, -c <rate>    Crossover probability (default: 0.7)
  --games, -g <n>           Games per fitness evaluation (default: 2000)
  --workers, -w <n>         Parallel workers (default: CPU count)
  --output, -o <file>       Output file
  --verbose, -v             Verbose output
  --seed, -s <n>            Random seed for reproducibility
  --help, -h                Show this help

Examples:
  # Standard run
  node scripts/genetic-optimize-hard-vince.js

  # Quick test
  node scripts/genetic-optimize-hard-vince.js --generations 10 --games 500

  # High precision
  node scripts/genetic-optimize-hard-vince.js --generations 50 --games 5000 --population 32
`);
}

// Get parameter names and their constraints
const PARAM_NAMES = Object.keys(HardVinceBotStrategy.DEFAULT_PARAMS);
const DEFAULT_PARAMS = HardVinceBotStrategy.DEFAULT_PARAMS;

// Parameter constraints (min, max multipliers relative to default)
const PARAM_CONSTRAINTS = {
    goldenScoreJokerPenalty: { min: 0.2, max: 2.0 },
    goldenScoreJokerPickupBonus: { min: 0.2, max: 3.0 },
    jokerPairSetPenalty: { min: 0.2, max: 2.0 },
    jokerSequencePenalty: { min: 0.2, max: 3.0 },
    jokerPairSetBonusLateGame: { min: 0.2, max: 3.0 },
    jokerSequenceBonusEarly: { min: 0.2, max: 3.0 },
    jokerPenaltyNearZapZap: { min: 0.2, max: 2.0 },
    opponentWantsBonusMultiplier: { min: 0.5, max: 4.0 },
    intermediateCardBonusMultiplier: { min: 0.2, max: 3.0 },
    highCardPairBreakingPenalty: { min: 0.2, max: 3.0 },
    singleHighCardRetentionPenalty: { min: 0.1, max: 5.0 },
    highCardPairPreservationBonusMultiplier: { min: 0.2, max: 4.0 },
    combinationBonusMultiplier: { min: 0.2, max: 3.0 },
    setBonusMultiplier: { min: 0.2, max: 3.0 },
    setBonusReduction: { min: 0.2, max: 3.0 },
    combinationBonusReduction: { min: 0.2, max: 3.0 },
    discardPickupThreshold: { min: 0.2, max: 4.0 }
};

/**
 * Individual in the population (chromosome = set of parameters)
 */
class Individual {
    constructor(genes = null) {
        if (genes) {
            this.genes = { ...genes };
        } else {
            // Initialize with default parameters
            this.genes = { ...DEFAULT_PARAMS };
        }
        this.fitness = null;
        this.winRate = null;
        this.avgScore = null;
    }

    /**
     * Create a random individual within constraints
     */
    static createRandom() {
        const individual = new Individual();
        for (const param of PARAM_NAMES) {
            const baseValue = DEFAULT_PARAMS[param];
            const constraints = PARAM_CONSTRAINTS[param] || { min: 0.5, max: 2.0 };
            const multiplier = constraints.min + Math.random() * (constraints.max - constraints.min);
            individual.genes[param] = baseValue * multiplier;
        }
        return individual;
    }

    /**
     * Create individual from default params with small variations
     */
    static createNearDefault(variationRange = 0.2) {
        const individual = new Individual();
        for (const param of PARAM_NAMES) {
            const baseValue = DEFAULT_PARAMS[param];
            const variation = 1 + (Math.random() * 2 - 1) * variationRange;
            individual.genes[param] = baseValue * variation;
        }
        return individual;
    }

    /**
     * Mutate this individual
     */
    mutate(mutationRate, mutationRange) {
        for (const param of PARAM_NAMES) {
            if (Math.random() < mutationRate) {
                const baseValue = this.genes[param];
                const variation = 1 + (Math.random() * 2 - 1) * mutationRange;
                let newValue = baseValue * variation;

                // Apply constraints
                const constraints = PARAM_CONSTRAINTS[param] || { min: 0.5, max: 2.0 };
                const minValue = DEFAULT_PARAMS[param] * constraints.min;
                const maxValue = DEFAULT_PARAMS[param] * constraints.max;

                // Handle negative values (constraints are relative to absolute value)
                if (DEFAULT_PARAMS[param] < 0) {
                    newValue = Math.max(maxValue, Math.min(minValue, newValue));
                } else {
                    newValue = Math.max(minValue, Math.min(maxValue, newValue));
                }

                this.genes[param] = newValue;
            }
        }
    }

    /**
     * Crossover with another individual (uniform crossover)
     */
    crossover(other) {
        const child1 = new Individual();
        const child2 = new Individual();

        for (const param of PARAM_NAMES) {
            if (Math.random() < 0.5) {
                child1.genes[param] = this.genes[param];
                child2.genes[param] = other.genes[param];
            } else {
                child1.genes[param] = other.genes[param];
                child2.genes[param] = this.genes[param];
            }
        }

        return [child1, child2];
    }

    /**
     * Blend crossover (BLX-alpha)
     */
    blendCrossover(other, alpha = 0.5) {
        const child = new Individual();

        for (const param of PARAM_NAMES) {
            const val1 = this.genes[param];
            const val2 = other.genes[param];
            const min = Math.min(val1, val2);
            const max = Math.max(val1, val2);
            const range = max - min;

            // Blend with extension
            const blendMin = min - alpha * range;
            const blendMax = max + alpha * range;
            child.genes[param] = blendMin + Math.random() * (blendMax - blendMin);

            // Apply constraints
            const constraints = PARAM_CONSTRAINTS[param] || { min: 0.5, max: 2.0 };
            const minConstraint = DEFAULT_PARAMS[param] * constraints.min;
            const maxConstraint = DEFAULT_PARAMS[param] * constraints.max;

            if (DEFAULT_PARAMS[param] < 0) {
                child.genes[param] = Math.max(maxConstraint, Math.min(minConstraint, child.genes[param]));
            } else {
                child.genes[param] = Math.max(minConstraint, Math.min(maxConstraint, child.genes[param]));
            }
        }

        return child;
    }

    clone() {
        const clone = new Individual(this.genes);
        clone.fitness = this.fitness;
        clone.winRate = this.winRate;
        clone.avgScore = this.avgScore;
        return clone;
    }
}

/**
 * Worker pool for parallel fitness evaluation
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

    async evaluateFitness(params, numGames) {
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
                }, 120000);

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
                    hardVincePosition: 2
                });
            });
        });

        const results = await Promise.all(batchPromises);

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
        await Promise.all(this.workers.map(w => w.terminate()));
        this.workers = [];
    }
}

/**
 * Genetic Algorithm
 */
class GeneticAlgorithm {
    constructor(options) {
        this.populationSize = options.population;
        this.generations = options.generations;
        this.eliteCount = options.elite;
        this.mutationRate = options.mutation;
        this.mutationRange = options.mutationRange;
        this.crossoverRate = options.crossoverRate;
        this.gamesPerEval = options.games;
        this.verbose = options.verbose;

        this.population = [];
        this.bestIndividual = null;
        this.generationStats = [];
        this.workerPool = null;
    }

    async init(workerPool) {
        this.workerPool = workerPool;

        // Initialize population
        // Include default params and variations
        this.population.push(new Individual()); // Default params
        this.population.push(Individual.createNearDefault(0.1)); // Small variation

        // Fill rest with diverse random individuals
        while (this.population.length < this.populationSize) {
            if (Math.random() < 0.5) {
                this.population.push(Individual.createNearDefault(0.3));
            } else {
                this.population.push(Individual.createRandom());
            }
        }
    }

    /**
     * Evaluate fitness for all individuals that need it
     */
    async evaluatePopulation() {
        const toEvaluate = this.population.filter(ind => ind.fitness === null);

        for (let i = 0; i < toEvaluate.length; i++) {
            const ind = toEvaluate[i];
            const result = await this.workerPool.evaluateFitness(ind.genes, this.gamesPerEval);

            ind.winRate = result.winRate;
            ind.avgScore = result.avgScore;
            // Fitness = win rate (primary) - normalized score (secondary tiebreaker)
            ind.fitness = result.winRate - (result.avgScore / 10000);

            if (this.verbose) {
                process.stdout.write(`  Evaluating ${i + 1}/${toEvaluate.length}: ${(result.winRate * 100).toFixed(2)}%\r`);
            }
        }

        // Sort by fitness (descending)
        this.population.sort((a, b) => b.fitness - a.fitness);

        // Update best individual
        if (!this.bestIndividual || this.population[0].fitness > this.bestIndividual.fitness) {
            this.bestIndividual = this.population[0].clone();
        }
    }

    /**
     * Tournament selection
     */
    tournamentSelect(tournamentSize = 3) {
        const tournament = [];
        for (let i = 0; i < tournamentSize; i++) {
            const idx = Math.floor(Math.random() * this.population.length);
            tournament.push(this.population[idx]);
        }
        tournament.sort((a, b) => b.fitness - a.fitness);
        return tournament[0];
    }

    /**
     * Create next generation
     */
    createNextGeneration() {
        const newPopulation = [];

        // Elitism: preserve best individuals
        for (let i = 0; i < this.eliteCount; i++) {
            newPopulation.push(this.population[i].clone());
        }

        // Fill rest with offspring
        while (newPopulation.length < this.populationSize) {
            const parent1 = this.tournamentSelect();
            const parent2 = this.tournamentSelect();

            let offspring;
            if (Math.random() < this.crossoverRate) {
                // Blend crossover produces better results for continuous parameters
                offspring = parent1.blendCrossover(parent2, 0.3);
            } else {
                // Clone one parent
                offspring = Math.random() < 0.5 ? parent1.clone() : parent2.clone();
            }

            // Mutate
            offspring.mutate(this.mutationRate, this.mutationRange);
            offspring.fitness = null; // Needs re-evaluation

            newPopulation.push(offspring);
        }

        this.population = newPopulation;
    }

    /**
     * Run the genetic algorithm
     */
    async run(onProgress) {
        console.log('Generation 0: Evaluating initial population...');
        await this.evaluatePopulation();

        const best = this.population[0];
        console.log(`  Best: ${(best.winRate * 100).toFixed(2)}% | Avg: ${best.avgScore.toFixed(1)}`);

        this.generationStats.push({
            generation: 0,
            bestFitness: best.fitness,
            bestWinRate: best.winRate,
            avgFitness: this.population.reduce((s, i) => s + i.fitness, 0) / this.population.length,
            diversity: this.calculateDiversity()
        });

        for (let gen = 1; gen <= this.generations; gen++) {
            const genStart = Date.now();

            // Create next generation
            this.createNextGeneration();

            // Evaluate new individuals
            console.log(`\nGeneration ${gen}/${this.generations}: Evaluating...`);
            await this.evaluatePopulation();

            const best = this.population[0];
            const avgFitness = this.population.reduce((s, i) => s + i.fitness, 0) / this.population.length;
            const diversity = this.calculateDiversity();
            const elapsed = ((Date.now() - genStart) / 1000).toFixed(1);

            console.log(`  Best: ${(best.winRate * 100).toFixed(2)}% | Avg fitness: ${avgFitness.toFixed(4)} | Diversity: ${diversity.toFixed(3)} | ${elapsed}s`);

            if (this.bestIndividual && best.winRate > this.bestIndividual.winRate) {
                console.log(`  *** New best: ${(best.winRate * 100).toFixed(2)}% ***`);
            }

            this.generationStats.push({
                generation: gen,
                bestFitness: best.fitness,
                bestWinRate: best.winRate,
                avgFitness,
                diversity
            });

            if (onProgress) {
                onProgress({
                    generation: gen,
                    totalGenerations: this.generations,
                    bestWinRate: this.bestIndividual.winRate,
                    currentBest: best.winRate
                });
            }

            // Early stopping if diversity is too low
            if (diversity < 0.01) {
                console.log('\nWarning: Low diversity detected. Injecting random individuals...');
                // Replace worst individuals with random ones
                for (let i = this.populationSize - 3; i < this.populationSize; i++) {
                    this.population[i] = Individual.createRandom();
                }
            }
        }

        return this.bestIndividual;
    }

    /**
     * Calculate population diversity (coefficient of variation across all genes)
     */
    calculateDiversity() {
        let totalCV = 0;

        for (const param of PARAM_NAMES) {
            const values = this.population.map(ind => ind.genes[param]);
            const mean = values.reduce((s, v) => s + v, 0) / values.length;
            const variance = values.reduce((s, v) => s + Math.pow(v - mean, 2), 0) / values.length;
            const stdDev = Math.sqrt(variance);
            const cv = mean !== 0 ? Math.abs(stdDev / mean) : 0;
            totalCV += cv;
        }

        return totalCV / PARAM_NAMES.length;
    }
}

/**
 * Main function
 */
async function main() {
    const args = parseArgs(process.argv.slice(2));

    console.log('\n====================================');
    console.log('  Genetic Algorithm Optimizer');
    console.log('  for HardVinceBotStrategy');
    console.log('====================================\n');

    console.log('Configuration:');
    console.log(`  Generations: ${args.generations}`);
    console.log(`  Population: ${args.population}`);
    console.log(`  Elite: ${args.elite}`);
    console.log(`  Mutation rate: ${(args.mutation * 100).toFixed(0)}%`);
    console.log(`  Mutation range: ±${(args.mutationRange * 100).toFixed(0)}%`);
    console.log(`  Crossover rate: ${(args.crossoverRate * 100).toFixed(0)}%`);
    console.log(`  Games per eval: ${args.games.toLocaleString()}`);
    console.log(`  Workers: ${args.workers}`);
    console.log(`  Parameters: ${PARAM_NAMES.length}`);
    console.log('');

    const totalEvaluations = args.population + args.generations * (args.population - args.elite);
    const totalGames = totalEvaluations * args.games;
    console.log(`Estimated total evaluations: ${totalEvaluations.toLocaleString()}`);
    console.log(`Estimated total games: ${totalGames.toLocaleString()}`);
    console.log('');

    // Initialize worker pool
    console.log(`Initializing ${args.workers} worker threads...`);
    const workerPool = new WorkerPool(args.workers);
    await workerPool.init();
    console.log('Workers ready.\n');

    // Establish baseline
    console.log('Establishing baseline with default parameters...');
    const baseline = await workerPool.evaluateFitness(DEFAULT_PARAMS, args.games);
    console.log(`Baseline: Win rate = ${(baseline.winRate * 100).toFixed(2)}%, Avg score = ${baseline.avgScore.toFixed(1)}`);
    console.log('');

    // Run genetic algorithm
    const startTime = Date.now();

    const ga = new GeneticAlgorithm(args);
    await ga.init(workerPool);

    const best = await ga.run();

    // Final validation with more games
    console.log('\n' + '='.repeat(50));
    console.log('Final validation with 2x games...');
    const finalResult = await workerPool.evaluateFitness(best.genes, args.games * 2);
    console.log(`Final: Win rate = ${(finalResult.winRate * 100).toFixed(2)}%, Avg score = ${finalResult.avgScore.toFixed(1)}`);
    console.log(`Improvement over baseline: ${((finalResult.winRate - baseline.winRate) * 100).toFixed(2)}%`);

    // Cleanup
    await workerPool.terminate();

    // Save results
    const results = {
        baseline: {
            params: DEFAULT_PARAMS,
            winRate: baseline.winRate,
            avgScore: baseline.avgScore,
            games: args.games
        },
        optimized: {
            params: best.genes,
            winRate: finalResult.winRate,
            avgScore: finalResult.avgScore,
            games: args.games * 2,
            improvementOverBaseline: finalResult.winRate - baseline.winRate
        },
        config: {
            generations: args.generations,
            population: args.population,
            elite: args.elite,
            mutationRate: args.mutation,
            mutationRange: args.mutationRange,
            crossoverRate: args.crossoverRate,
            gamesPerEval: args.games
        },
        generationStats: ga.generationStats,
        timestamp: new Date().toISOString()
    };

    const outputPath = path.resolve(args.output);
    const outputDir = path.dirname(outputPath);
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }
    fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
    console.log(`\nResults saved to: ${outputPath}`);

    // Print optimized parameters
    console.log('\n====================================');
    console.log('  Optimized Parameters');
    console.log('====================================\n');

    const changes = [];
    for (const [key, value] of Object.entries(best.genes)) {
        const defaultVal = DEFAULT_PARAMS[key];
        const pctChange = ((value - defaultVal) / Math.abs(defaultVal) * 100).toFixed(1);
        if (Math.abs(value - defaultVal) > 0.01) {
            changes.push({ key, old: defaultVal, new: value, pctChange });
            console.log(`  ${key}: ${defaultVal} -> ${value.toFixed(2)} (${pctChange}%)`);
        }
    }

    if (changes.length === 0) {
        console.log('  No significant changes from defaults.');
    }

    // Print code snippet
    console.log('\n====================================');
    console.log('  Code Update (copy to HardVinceBotStrategy.js)');
    console.log('====================================\n');
    console.log('static DEFAULT_PARAMS = {');
    for (const param of PARAM_NAMES) {
        const value = best.genes[param];
        // Round to reasonable precision
        const rounded = Math.abs(value) > 10 ? Math.round(value * 100) / 100 : Math.round(value * 1000) / 1000;
        console.log(`    ${param}: ${rounded},`);
    }
    console.log('};');

    const totalDuration = ((Date.now() - startTime) / 1000).toFixed(1);
    console.log(`\nTotal duration: ${totalDuration}s`);
    console.log(`Total games: ${totalGames.toLocaleString()}`);
    console.log('\nDone!\n');
}

// Run
main().catch(error => {
    console.error('\nError:', error.message);
    console.error(error.stack);
    process.exit(1);
});
