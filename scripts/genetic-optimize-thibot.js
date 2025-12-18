#!/usr/bin/env node

/**
 * genetic-optimize-thibot.js
 * Genetic Algorithm for optimizing ThibotStrategy parameters
 *
 * Uses evolutionary optimization to find parameter combinations that
 * maximize win rate against hard bots using the native Rust engine.
 *
 * Usage:
 *   node scripts/genetic-optimize-thibot.js
 *   node scripts/genetic-optimize-thibot.js --generations 50 --population 20
 *   node scripts/genetic-optimize-thibot.js --elite 4 --mutation 0.15
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// Load native module
const native = require('../native');

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
        output: 'data/thibot_genetic_params.json',
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
Genetic Algorithm Optimizer for ThibotStrategy

Usage:
  node scripts/genetic-optimize-thibot.js [options]

Options:
  --generations, -gen <n>   Number of generations (default: 30)
  --population, -pop <n>    Population size (default: 16)
  --elite, -e <n>           Elite individuals preserved (default: 2)
  --mutation, -m <rate>     Mutation probability (default: 0.1)
  --mutation-range, -mr <r> Mutation range ±% (default: 0.3)
  --crossover, -c <rate>    Crossover probability (default: 0.7)
  --games, -g <n>           Games per fitness evaluation (default: 2000)
  --output, -o <file>       Output file
  --verbose, -v             Verbose output
  --seed, -s <n>            Random seed for reproducibility
  --help, -h                Show this help

Examples:
  # Standard run
  node scripts/genetic-optimize-thibot.js

  # Quick test
  node scripts/genetic-optimize-thibot.js --generations 10 --games 500

  # High precision
  node scripts/genetic-optimize-thibot.js --generations 50 --games 5000 --population 32
`);
}

// Get default parameters from native module
const DEFAULT_PARAMS = native.thibotGetDefaultParams();

// Parameter names
const PARAM_NAMES = Object.keys(DEFAULT_PARAMS);

// Parameter constraints (min, max multipliers relative to default)
// These define the search space for the genetic algorithm
const PARAM_CONSTRAINTS = {
    // Card Potential Evaluation
    jokerKeepScore: { min: 0.5, max: 2.0 },
    existingPairBonus: { min: 0.2, max: 3.0 },
    goodPairChanceBonus: { min: 0.2, max: 3.0 },
    lowPairChanceBonus: { min: 0.2, max: 3.0 },
    deadRankPenalty: { min: 0.2, max: 3.0 },
    sequencePartBonus: { min: 0.2, max: 3.0 },
    potentialSequenceBonus: { min: 0.2, max: 3.0 },
    jokerSequenceBonus: { min: 0.2, max: 3.0 },
    closeWithJokerBonus: { min: 0.2, max: 3.0 },

    // Play Selection (Offensive)
    valueScoreWeight: { min: 0.2, max: 3.0 },
    cardsScoreWeight: { min: 0.2, max: 3.0 },
    potentialDivisor: { min: 1, max: 20, absolute: true },
    jokerPlayPenalty: { min: 0.2, max: 3.0 },
    zapzapPotentialBonus: { min: 0.2, max: 3.0 },

    // Draw Source Evaluation
    discardJokerScore: { min: 0.5, max: 2.0 },
    lowPointsBase: { min: 0.2, max: 3.0 },
    pairCompletionBonus: { min: 0.2, max: 3.0 },
    threeOfKindBonus: { min: 0.2, max: 3.0 },
    sequenceCompletionBonus: { min: 0.2, max: 3.0 },
    deadRankDiscardPenalty: { min: 0.2, max: 3.0 },
    discardThreshold: { min: 0.2, max: 3.0 },

    // Defensive Mode
    defensiveThreshold: { min: 1, max: 5, absolute: true },

    // ZapZap Decision
    zapzapSafeHandSize: { min: 2, max: 6, absolute: true },
    zapzapModerateHandSize: { min: 2, max: 5, absolute: true },
    zapzapModerateValueThreshold: { min: 1, max: 5, absolute: true },
    zapzapRiskyHandSize: { min: 1, max: 4, absolute: true },
    zapzapRiskyValueThreshold: { min: 2, max: 5, absolute: true },
    zapzapSafeValueThreshold: { min: 1, max: 4, absolute: true },
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

            if (constraints.absolute) {
                // Absolute bounds (for integer-like params)
                individual.genes[param] = Math.round(
                    constraints.min + Math.random() * (constraints.max - constraints.min)
                );
            } else {
                const multiplier = constraints.min + Math.random() * (constraints.max - constraints.min);
                individual.genes[param] = Math.round(baseValue * multiplier);
            }
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
            const constraints = PARAM_CONSTRAINTS[param] || { min: 0.5, max: 2.0 };

            if (constraints.absolute) {
                const variation = Math.round((Math.random() * 2 - 1) * variationRange * baseValue);
                individual.genes[param] = Math.max(constraints.min, Math.min(constraints.max, baseValue + variation));
            } else {
                const variation = 1 + (Math.random() * 2 - 1) * variationRange;
                individual.genes[param] = Math.round(baseValue * variation);
            }
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
                const constraints = PARAM_CONSTRAINTS[param] || { min: 0.5, max: 2.0 };

                let newValue;
                if (constraints.absolute) {
                    // For absolute constraints, mutate within bounds
                    const delta = Math.round((Math.random() * 2 - 1) * mutationRange * (constraints.max - constraints.min));
                    newValue = Math.max(constraints.min, Math.min(constraints.max, baseValue + delta));
                } else {
                    const variation = 1 + (Math.random() * 2 - 1) * mutationRange;
                    newValue = baseValue * variation;

                    // Apply constraints
                    const minValue = DEFAULT_PARAMS[param] * constraints.min;
                    const maxValue = DEFAULT_PARAMS[param] * constraints.max;

                    if (DEFAULT_PARAMS[param] < 0) {
                        newValue = Math.max(maxValue, Math.min(minValue, newValue));
                    } else {
                        newValue = Math.max(minValue, Math.min(maxValue, newValue));
                    }
                }

                this.genes[param] = Math.round(newValue);
            }
        }
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

            if (constraints.absolute) {
                child.genes[param] = Math.round(
                    Math.max(constraints.min, Math.min(constraints.max, child.genes[param]))
                );
            } else {
                const minConstraint = DEFAULT_PARAMS[param] * constraints.min;
                const maxConstraint = DEFAULT_PARAMS[param] * constraints.max;

                if (DEFAULT_PARAMS[param] < 0) {
                    child.genes[param] = Math.round(Math.max(maxConstraint, Math.min(minConstraint, child.genes[param])));
                } else {
                    child.genes[param] = Math.round(Math.max(minConstraint, Math.min(maxConstraint, child.genes[param])));
                }
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
 * Evaluate fitness using native module
 */
function evaluateFitness(params, numGames, seed = null) {
    // Set the params in native module
    native.thibotSetParams(params);

    // Run games: thibot vs 3 hard bots
    const result = native.runGamesBatch(
        ['thibot', 'hard', 'hard', 'hard'],
        numGames,
        seed
    );

    const winRate = result.wins[0] / result.gamesPlayed;

    // Calculate average score (lower is better for thibot)
    // We don't have detailed scores, so use win rate as primary metric

    return {
        gamesPlayed: result.gamesPlayed,
        wins: result.wins[0],
        winRate: winRate,
        avgRounds: result.avgRounds
    };
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
        this.seed = options.seed;

        this.population = [];
        this.bestIndividual = null;
        this.generationStats = [];
    }

    init() {
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
    evaluatePopulation() {
        const toEvaluate = this.population.filter(ind => ind.fitness === null);

        for (let i = 0; i < toEvaluate.length; i++) {
            const ind = toEvaluate[i];
            const seed = this.seed !== null ? this.seed + i : null;
            const result = evaluateFitness(ind.genes, this.gamesPerEval, seed);

            ind.winRate = result.winRate;
            ind.avgScore = result.avgRounds; // Use avg rounds as proxy for game length
            // Fitness = win rate (primary)
            ind.fitness = result.winRate;

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
    run(onProgress) {
        console.log('Generation 0: Evaluating initial population...');
        this.evaluatePopulation();

        const best = this.population[0];
        console.log(`  Best: ${(best.winRate * 100).toFixed(2)}% | Avg rounds: ${best.avgScore.toFixed(1)}`);

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
            this.evaluatePopulation();

            const best = this.population[0];
            const avgFitness = this.population.reduce((s, i) => s + i.fitness, 0) / this.population.length;
            const diversity = this.calculateDiversity();
            const elapsed = ((Date.now() - genStart) / 1000).toFixed(1);

            console.log(`  Best: ${(best.winRate * 100).toFixed(2)}% | Avg fitness: ${(avgFitness * 100).toFixed(2)}% | Diversity: ${diversity.toFixed(3)} | ${elapsed}s`);

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
    console.log('  for ThibotStrategy (Native Rust)');
    console.log('====================================\n');

    console.log('Configuration:');
    console.log(`  Generations: ${args.generations}`);
    console.log(`  Population: ${args.population}`);
    console.log(`  Elite: ${args.elite}`);
    console.log(`  Mutation rate: ${(args.mutation * 100).toFixed(0)}%`);
    console.log(`  Mutation range: ±${(args.mutationRange * 100).toFixed(0)}%`);
    console.log(`  Crossover rate: ${(args.crossoverRate * 100).toFixed(0)}%`);
    console.log(`  Games per eval: ${args.games.toLocaleString()}`);
    console.log(`  Parameters: ${PARAM_NAMES.length}`);
    console.log('');

    const totalEvaluations = args.population + args.generations * (args.population - args.elite);
    const totalGames = totalEvaluations * args.games;
    console.log(`Estimated total evaluations: ${totalEvaluations.toLocaleString()}`);
    console.log(`Estimated total games: ${totalGames.toLocaleString()}`);
    console.log('');

    // Establish baseline
    console.log('Establishing baseline with default parameters...');
    native.thibotSetParams(DEFAULT_PARAMS);
    const baseline = evaluateFitness(DEFAULT_PARAMS, args.games, args.seed);
    console.log(`Baseline: Win rate = ${(baseline.winRate * 100).toFixed(2)}%, Avg rounds = ${baseline.avgRounds.toFixed(1)}`);
    console.log('');

    // Run genetic algorithm
    const startTime = Date.now();

    const ga = new GeneticAlgorithm(args);
    ga.init();

    const best = ga.run();

    // Final validation with more games
    console.log('\n' + '='.repeat(50));
    console.log('Final validation with 2x games...');
    const finalResult = evaluateFitness(best.genes, args.games * 2, args.seed);
    console.log(`Final: Win rate = ${(finalResult.winRate * 100).toFixed(2)}%, Avg rounds = ${finalResult.avgRounds.toFixed(1)}`);
    console.log(`Improvement over baseline: ${((finalResult.winRate - baseline.winRate) * 100).toFixed(2)}%`);

    // Save results
    const results = {
        baseline: {
            params: DEFAULT_PARAMS,
            winRate: baseline.winRate,
            avgRounds: baseline.avgRounds,
            games: args.games
        },
        optimized: {
            params: best.genes,
            winRate: finalResult.winRate,
            avgRounds: finalResult.avgRounds,
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
        if (Math.abs(value - defaultVal) > 0.5) {
            changes.push({ key, old: defaultVal, new: value, pctChange });
            console.log(`  ${key}: ${defaultVal} -> ${value} (${pctChange}%)`);
        }
    }

    if (changes.length === 0) {
        console.log('  No significant changes from defaults.');
    }

    // Print code snippet for Rust
    console.log('\n====================================');
    console.log('  Code Update (copy to thibot.rs ThibotParams::default())');
    console.log('====================================\n');
    console.log('impl Default for ThibotParams {');
    console.log('    fn default() -> Self {');
    console.log('        Self {');

    // Convert camelCase to snake_case for Rust
    const toSnakeCase = (str) => str.replace(/[A-Z]/g, letter => `_${letter.toLowerCase()}`);

    for (const param of PARAM_NAMES) {
        const value = best.genes[param];
        const rustName = toSnakeCase(param);
        console.log(`            ${rustName}: ${value},`);
    }
    console.log('        }');
    console.log('    }');
    console.log('}');

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
