/**
 * CurriculumDRLRunner
 * Progressive difficulty training for Deep RL
 *
 * Starts training against easy opponents, then gradually increases difficulty.
 * This helps the DRL bot learn winning patterns before facing strong opponents.
 *
 * Curriculum Phases:
 * 1. DRL vs 3 easy bots (learn basic winning)
 * 2. DRL vs 2 easy + 1 medium (introduce challenge)
 * 3. DRL vs 1 easy + 2 medium (more challenge)
 * 4. DRL vs 3 medium (intermediate level)
 * 5. DRL vs 2 medium + 1 hard (harder opponents)
 * 6. DRL vs 1 medium + 2 hard (near final)
 * 7. DRL vs 3 hard_vince (final difficulty)
 */

const ParallelDRLRunner = require('./ParallelDRLRunner');
const SimulationStats = require('./SimulationStats');

class CurriculumDRLRunner {
    /**
     * @param {Object} options
     * @param {number} options.totalGames - Total games across all phases
     * @param {number} options.numWorkers - Worker threads
     * @param {Function} options.onProgress - Progress callback
     * @param {Function} options.onPhaseChange - Phase change callback
     * @param {number} options.winRateThreshold - Win rate to advance phase (default: 0.20)
     * @param {number} options.minGamesPerPhase - Minimum games per phase (default: 5000)
     * @param {number} options.maxGamesPerPhase - Maximum games per phase (default: 20000)
     */
    constructor(options = {}) {
        this.totalGames = options.totalGames || 100000;
        this.numWorkers = options.numWorkers || 12;
        this.onProgress = options.onProgress || (() => {});
        this.onPhaseChange = options.onPhaseChange || (() => {});

        // Curriculum parameters
        this.winRateThreshold = options.winRateThreshold || 0.20; // 20% win rate to advance
        this.minGamesPerPhase = options.minGamesPerPhase || 5000;
        this.maxGamesPerPhase = options.maxGamesPerPhase || 20000;

        // Define curriculum phases (DRL is always at position 0)
        this.phases = [
            {
                name: 'Phase 1: Easy Opponents',
                strategies: ['drl', 'easy', 'easy', 'easy'],
                description: 'Learn basic winning patterns'
            },
            {
                name: 'Phase 2: Easy + Medium',
                strategies: ['drl', 'easy', 'easy', 'medium'],
                description: 'Introduce some challenge'
            },
            {
                name: 'Phase 3: More Medium',
                strategies: ['drl', 'easy', 'medium', 'medium'],
                description: 'Increase difficulty'
            },
            {
                name: 'Phase 4: All Medium',
                strategies: ['drl', 'medium', 'medium', 'medium'],
                description: 'Intermediate level'
            },
            {
                name: 'Phase 5: Medium + Hard',
                strategies: ['drl', 'medium', 'medium', 'hard'],
                description: 'Introduce hard opponents'
            },
            {
                name: 'Phase 6: More Hard',
                strategies: ['drl', 'medium', 'hard', 'hard'],
                description: 'Mostly hard opponents'
            },
            {
                name: 'Phase 7: Final - HardVince',
                strategies: ['drl', 'hard_vince', 'hard_vince', 'hard'],
                description: 'Final difficulty level'
            }
        ];

        this.currentPhase = 0;
        this.policy = null;
        this.totalGamesPlayed = 0;
        this.phaseHistory = [];
    }

    /**
     * Set a pre-trained policy
     * @param {DRLPolicy} policy
     */
    setPolicy(policy) {
        this.policy = policy;
    }

    /**
     * Run curriculum training
     * @returns {Promise<Object>} Training results
     */
    async run() {
        console.log('\n====================================');
        console.log('  Curriculum Learning DRL Training');
        console.log('====================================\n');
        console.log(`Total target games: ${this.totalGames.toLocaleString()}`);
        console.log(`Win rate threshold to advance: ${(this.winRateThreshold * 100).toFixed(0)}%`);
        console.log(`Games per phase: ${this.minGamesPerPhase.toLocaleString()} - ${this.maxGamesPerPhase.toLocaleString()}`);
        console.log(`Phases: ${this.phases.length}\n`);

        const startTime = Date.now();
        const overallStats = new SimulationStats();

        while (this.totalGamesPlayed < this.totalGames && this.currentPhase < this.phases.length) {
            const phase = this.phases[this.currentPhase];
            const phaseResult = await this._runPhase(phase);

            this.phaseHistory.push({
                phase: this.currentPhase,
                name: phase.name,
                gamesPlayed: phaseResult.gamesPlayed,
                winRate: phaseResult.winRate,
                advanced: phaseResult.advanced
            });

            // Merge stats
            if (phaseResult.stats) {
                overallStats.merge(phaseResult.stats);
            }

            // Check if we should advance
            if (phaseResult.advanced && this.currentPhase < this.phases.length - 1) {
                this.currentPhase++;
                this.onPhaseChange({
                    phase: this.currentPhase,
                    name: this.phases[this.currentPhase].name,
                    totalGamesPlayed: this.totalGamesPlayed
                });
            }
        }

        const duration = (Date.now() - startTime) / 1000;

        console.log('\n====================================');
        console.log('  Curriculum Training Complete!');
        console.log('====================================\n');
        console.log(`Total games: ${this.totalGamesPlayed.toLocaleString()}`);
        console.log(`Duration: ${duration.toFixed(1)}s`);
        console.log(`Final phase: ${this.phases[this.currentPhase].name}`);
        console.log('\nPhase History:');
        for (const ph of this.phaseHistory) {
            const status = ph.advanced ? '✓ Advanced' : '→ Continued';
            console.log(`  ${ph.name}: ${ph.gamesPlayed} games, ${(ph.winRate * 100).toFixed(1)}% win rate ${status}`);
        }

        return {
            policy: this.policy,
            stats: overallStats,
            totalGamesPlayed: this.totalGamesPlayed,
            finalPhase: this.currentPhase,
            phaseHistory: this.phaseHistory,
            duration
        };
    }

    /**
     * Run a single curriculum phase
     * @param {Object} phase - Phase configuration
     * @returns {Promise<Object>} Phase results
     */
    async _runPhase(phase) {
        console.log(`\n--- ${phase.name} ---`);
        console.log(`Strategies: ${phase.strategies.join(', ')}`);
        console.log(`Description: ${phase.description}`);

        // Calculate games for this phase
        const remainingGames = this.totalGames - this.totalGamesPlayed;
        const gamesForPhase = Math.min(
            this.maxGamesPerPhase,
            Math.max(this.minGamesPerPhase, Math.floor(remainingGames / (this.phases.length - this.currentPhase)))
        );

        console.log(`Games for phase: ${gamesForPhase.toLocaleString()}`);

        // Create runner for this phase
        const runner = new ParallelDRLRunner({
            numWorkers: this.numWorkers,
            batchPerWorker: 16,
            trainEveryNGames: 64,
            trainIterations: 4,
            syncEveryNTrains: 1,
            onProgress: (progress) => {
                const drlWinRate = progress.stats?.winsByStrategy?.drl / progress.gamesCompleted || 0;
                this.onProgress({
                    ...progress,
                    phase: this.currentPhase,
                    phaseName: phase.name,
                    totalGamesPlayed: this.totalGamesPlayed + progress.gamesCompleted,
                    drlWinRate
                });
            }
        });

        // Use existing policy or let runner create one
        if (this.policy) {
            runner.setPolicy(this.policy);
        }

        // Run the phase
        const result = await runner.runSimulations(gamesForPhase, phase.strategies, {});

        // Store the policy for next phase
        this.policy = result.policy;
        this.totalGamesPlayed += result.gamesCompleted;

        // Calculate DRL win rate
        const drlWins = result.stats?.winsByStrategy?.drl || 0;
        const winRate = drlWins / result.gamesCompleted;

        console.log(`\nPhase ${this.currentPhase + 1} complete:`);
        console.log(`  Games: ${result.gamesCompleted.toLocaleString()}`);
        console.log(`  DRL Win Rate: ${(winRate * 100).toFixed(1)}%`);
        console.log(`  Threshold: ${(this.winRateThreshold * 100).toFixed(0)}%`);

        // Check if we should advance to next phase
        const shouldAdvance = winRate >= this.winRateThreshold;

        if (shouldAdvance) {
            console.log(`  → Advancing to next phase!`);
        } else if (this.currentPhase === this.phases.length - 1) {
            console.log(`  → Final phase, continuing training`);
        } else {
            console.log(`  → Win rate below threshold, staying in phase`);
        }

        return {
            gamesPlayed: result.gamesCompleted,
            winRate,
            advanced: shouldAdvance,
            stats: result.stats?.toJSON ? result.stats.toJSON() : result.stats
        };
    }

    /**
     * Get current training state
     */
    getState() {
        return {
            currentPhase: this.currentPhase,
            phaseName: this.phases[this.currentPhase]?.name,
            totalGamesPlayed: this.totalGamesPlayed,
            phaseHistory: this.phaseHistory,
            policyStats: this.policy?.getStats()
        };
    }

    /**
     * Save training state
     */
    async saveState(basePath) {
        const fs = require('fs');

        // Save policy model
        if (this.policy) {
            await this.policy.saveModel(`${basePath}/model`);
        }

        // Save curriculum state
        fs.writeFileSync(`${basePath}/curriculum_state.json`, JSON.stringify({
            currentPhase: this.currentPhase,
            totalGamesPlayed: this.totalGamesPlayed,
            phaseHistory: this.phaseHistory,
            policyStats: this.policy?.getStats()
        }, null, 2));
    }

    /**
     * Load training state
     */
    async loadState(basePath) {
        const fs = require('fs');
        const DRLPolicy = require('../infrastructure/bot/ml/DRLPolicy');

        // Load curriculum state
        const statePath = `${basePath}/curriculum_state.json`;
        if (fs.existsSync(statePath)) {
            const state = JSON.parse(fs.readFileSync(statePath, 'utf-8'));
            this.currentPhase = state.currentPhase || 0;
            this.totalGamesPlayed = state.totalGamesPlayed || 0;
            this.phaseHistory = state.phaseHistory || [];
        }

        // Load policy model
        const modelPath = `${basePath}/model`;
        if (fs.existsSync(`${modelPath}/weights.json`)) {
            this.policy = new DRLPolicy({ inputDim: 45 });
            await this.policy.loadModel(modelPath);
            console.log(`Loaded policy from ${modelPath}`);
        }
    }
}

module.exports = CurriculumDRLRunner;
