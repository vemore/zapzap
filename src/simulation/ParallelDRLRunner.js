/**
 * ParallelDRLRunner
 * Orchestrator for parallel Deep RL training using worker threads
 *
 * Architecture:
 * - Main thread: Centralized replay buffer, network training, weight sync
 * - Workers: Run games (inference only), collect transitions
 */

const { Worker } = require('worker_threads');
const os = require('os');
const path = require('path');
const SimulationStats = require('./SimulationStats');
const DRLPolicy = require('../infrastructure/bot/ml/DRLPolicy');

class ParallelDRLRunner {
    /**
     * @param {Object} options
     * @param {number} options.numWorkers - Number of worker threads (default: CPU count)
     * @param {number} options.batchPerWorker - Games per worker batch (default: 16)
     * @param {number} options.trainEveryNGames - Training frequency (default: 64)
     * @param {number} options.trainIterations - Training iterations per cycle (default: 4)
     * @param {number} options.syncEveryNTrains - Weight sync frequency (default: 5)
     * @param {Function} options.onProgress - Progress callback
     */
    constructor(options = {}) {
        this.numWorkers = options.numWorkers || Math.max(1, os.cpus().length - 1);
        this.batchPerWorker = options.batchPerWorker || 16;
        this.trainEveryNGames = options.trainEveryNGames || 64;
        this.trainIterations = options.trainIterations || 4;
        this.syncEveryNTrains = options.syncEveryNTrains || 1;
        this.onProgress = options.onProgress || (() => {});

        this.workers = [];
        this.stats = new SimulationStats();
        this.policy = null;

        this.gamesCompleted = 0;
        this.trainingsCompleted = 0;
        this.syncsPending = 0;
        this.isRunning = false;
    }

    /**
     * Set a pre-trained policy (for imitation learning warm start)
     * @param {DRLPolicy} policy - Pre-trained policy
     */
    setPolicy(policy) {
        this.policy = policy;
    }

    /**
     * Run DRL training simulations
     * @param {number} numGames - Total number of games to run
     * @param {Array<string>} strategyTypes - Strategy types for players
     * @param {Object} policyConfig - Policy configuration
     * @returns {Promise<Object>} Training results
     */
    async runSimulations(numGames, strategyTypes, policyConfig = {}) {
        console.log(`\nStarting DRL parallel training with ${this.numWorkers} workers`);
        console.log(`Target: ${numGames} games, strategies: ${strategyTypes.join(', ')}`);

        // Initialize main policy if not already set (e.g., by pre-training)
        if (!this.policy) {
            this.policy = new DRLPolicy(policyConfig);
        } else {
            console.log(`Using pre-trained policy (buffer: ${this.policy.replayBuffer.size()}, epsilon: ${this.policy.epsilon.toFixed(4)})`);
        }

        this.stats = new SimulationStats();
        this.gamesCompleted = 0;
        this.trainingsCompleted = 0;
        this.isRunning = true;

        const startTime = Date.now();

        try {
            // Initialize workers
            await this._initWorkers(strategyTypes);

            // Main training loop
            while (this.gamesCompleted < numGames && this.isRunning) {
                // Run batch on all workers in parallel
                const batchResults = await this._runWorkerBatches();

                // Process results
                for (const result of batchResults) {
                    // Merge stats
                    this.stats.merge(result.stats);

                    // Store transitions in main replay buffer
                    for (const transition of result.transitions) {
                        this.policy.storeTransition(transition);
                    }

                    this.gamesCompleted += result.gamesPlayed;
                }

                // Train periodically
                if (this.gamesCompleted >= (this.trainingsCompleted + 1) * this.trainEveryNGames) {
                    await this._trainNetwork();
                    this.trainingsCompleted++;

                    // Sync weights to workers periodically
                    if (this.trainingsCompleted % this.syncEveryNTrains === 0) {
                        await this._syncWeightsToWorkers();
                    }
                }

                // Progress callback
                this.onProgress({
                    gamesCompleted: this.gamesCompleted,
                    totalGames: numGames,
                    progress: this.gamesCompleted / numGames,
                    stats: this.stats.getSummary(),
                    policyStats: this.policy.getStats(),
                    elapsed: Date.now() - startTime
                });
            }
        } finally {
            // Shutdown workers
            await this._shutdownWorkers();
        }

        const duration = (Date.now() - startTime) / 1000;
        const gamesPerSec = this.gamesCompleted / duration;

        console.log(`\nTraining complete!`);
        console.log(`Games: ${this.gamesCompleted}, Duration: ${duration.toFixed(1)}s`);
        console.log(`Speed: ${gamesPerSec.toFixed(1)} games/sec`);

        return {
            stats: this.stats,
            policy: this.policy,
            gamesCompleted: this.gamesCompleted,
            duration,
            gamesPerSec
        };
    }

    /**
     * Initialize worker threads
     */
    async _initWorkers(strategyTypes) {
        const workerPath = path.resolve(__dirname, 'DRLSimulationWorker.js');

        const initPromises = [];

        for (let i = 0; i < this.numWorkers; i++) {
            const worker = new Worker(workerPath);
            this.workers.push(worker);

            const promise = new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    reject(new Error(`Worker ${i} initialization timeout`));
                }, 30000);

                worker.once('message', (msg) => {
                    if (msg.type === 'initialized') {
                        clearTimeout(timeout);
                        resolve();
                    } else if (msg.type === 'error') {
                        clearTimeout(timeout);
                        reject(new Error(msg.error));
                    }
                });

                worker.once('error', (err) => {
                    clearTimeout(timeout);
                    reject(err);
                });
            });

            // Send init message (no weights - workers use random policy)
            worker.postMessage({
                type: 'init',
                data: {
                    workerId: i,
                    strategyTypes,
                    epsilon: this.policy.epsilon
                }
            });

            initPromises.push(promise);
        }

        await Promise.all(initPromises);
        console.log(`Initialized ${this.numWorkers} workers`);
    }

    /**
     * Run a batch on all workers in parallel
     */
    async _runWorkerBatches() {
        const batchPromises = this.workers.map((worker, idx) => {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    reject(new Error(`Worker ${idx} batch timeout`));
                }, 120000); // 2 minute timeout per batch

                const handler = (msg) => {
                    if (msg.type === 'batchComplete' && msg.workerId === idx) {
                        clearTimeout(timeout);
                        worker.off('message', handler);
                        resolve({
                            stats: msg.stats,
                            transitions: msg.transitions,
                            gamesPlayed: msg.gamesPlayed
                        });
                    } else if (msg.type === 'error' && msg.workerId === idx) {
                        clearTimeout(timeout);
                        worker.off('message', handler);
                        reject(new Error(msg.error));
                    }
                };

                worker.on('message', handler);
                worker.postMessage({
                    type: 'runBatch',
                    batchSize: this.batchPerWorker
                });
            });
        });

        return Promise.all(batchPromises);
    }

    /**
     * Train the network
     */
    async _trainNetwork() {
        const bufferSize = this.policy.replayBuffer.size();

        if (bufferSize < this.policy.config.minBufferSize) {
            return; // Not enough samples yet
        }

        let totalTdError = 0;
        for (let i = 0; i < this.trainIterations; i++) {
            const tdError = await this.policy.train();
            totalTdError += tdError;
        }

        const avgTdError = totalTdError / this.trainIterations;
        if (this.trainingsCompleted % 10 === 0) {
            console.log(`[Train ${this.trainingsCompleted}] Buffer: ${bufferSize}, Avg TD Error: ${avgTdError.toFixed(4)}, Epsilon: ${this.policy.epsilon.toFixed(4)}`);
        }
    }

    /**
     * Sync network weights and epsilon to all workers
     * Workers use LightweightDQN for inference with synced weights
     */
    async _syncWeightsToWorkers() {
        // Get compact weights from the trained network
        let compactWeights = null;
        try {
            compactWeights = await this.policy.network.getCompactWeights();
        } catch (e) {
            console.warn(`[Sync] Could not get weights: ${e.message}`);
        }

        const syncPromises = this.workers.map((worker, idx) => {
            return new Promise((resolve) => {
                const timeout = setTimeout(() => {
                    console.warn(`[Sync] Worker ${idx} timeout`);
                    resolve();
                }, 10000);

                const handler = (msg) => {
                    if (msg.type === 'weightsUpdated' && msg.workerId === idx) {
                        clearTimeout(timeout);
                        worker.off('message', handler);
                        resolve();
                    }
                };

                worker.on('message', handler);
                worker.postMessage({
                    type: 'updateWeights',
                    epsilon: this.policy.epsilon,
                    weights: compactWeights
                });
            });
        });

        await Promise.all(syncPromises);

        if (this.trainingsCompleted % 10 === 0) {
            console.log(`[Sync ${this.trainingsCompleted}] Weights synced to ${this.workers.length} workers`);
        }
    }

    /**
     * Shutdown all workers
     */
    async _shutdownWorkers() {
        const shutdownPromises = this.workers.map((worker, idx) => {
            return new Promise((resolve) => {
                const timeout = setTimeout(() => {
                    worker.terminate();
                    resolve();
                }, 5000);

                worker.once('message', (msg) => {
                    if (msg.type === 'shutdown') {
                        clearTimeout(timeout);
                        resolve();
                    }
                });

                worker.postMessage({ type: 'shutdown' });
            });
        });

        await Promise.all(shutdownPromises);
        this.workers = [];
    }

    /**
     * Stop training
     */
    stop() {
        this.isRunning = false;
    }

    /**
     * Get current training statistics
     */
    getStats() {
        return {
            gamesCompleted: this.gamesCompleted,
            trainingsCompleted: this.trainingsCompleted,
            bufferSize: this.policy?.replayBuffer.size() || 0,
            policyStats: this.policy?.getStats() || {},
            gameStats: this.stats?.getSummary() || {}
        };
    }

    /**
     * Save training state
     */
    async saveState(basePath) {
        if (!this.policy) return;

        // Save model
        await this.policy.saveModel(`${basePath}/model`);

        // Save stats
        const fs = require('fs');
        fs.writeFileSync(
            `${basePath}/stats.json`,
            JSON.stringify({
                gamesCompleted: this.gamesCompleted,
                trainingsCompleted: this.trainingsCompleted,
                stats: this.stats.toJSON(),
                policyStats: this.policy.getStats()
            }, null, 2)
        );
    }

    /**
     * Load training state
     */
    async loadState(basePath) {
        if (!this.policy) {
            this.policy = new DRLPolicy();
        }

        // Load model
        await this.policy.loadModel(`${basePath}/model`);

        // Load stats
        const fs = require('fs');
        const stateFile = `${basePath}/stats.json`;
        if (fs.existsSync(stateFile)) {
            const state = JSON.parse(fs.readFileSync(stateFile, 'utf-8'));
            this.gamesCompleted = state.gamesCompleted || 0;
            this.trainingsCompleted = state.trainingsCompleted || 0;
            if (state.stats) {
                this.stats.fromJSON(state.stats);
            }
        }
    }
}

module.exports = ParallelDRLRunner;
