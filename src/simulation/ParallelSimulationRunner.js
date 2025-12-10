/**
 * ParallelSimulationRunner
 * Orchestrates parallel game simulations using worker threads
 * Distributes batches to workers and merges results
 */

const { Worker } = require('worker_threads');
const os = require('os');
const path = require('path');
const SimulationStats = require('./SimulationStats');

class ParallelSimulationRunner {
    /**
     * @param {Object} options - Runner options
     * @param {number} options.numWorkers - Number of worker threads (default: CPU count)
     * @param {number} options.batchPerWorker - Games per worker per batch (default: 64)
     * @param {Function} options.onProgress - Progress callback
     * @param {Function} options.onBatchComplete - Batch complete callback
     */
    constructor(options = {}) {
        this.numWorkers = options.numWorkers || os.cpus().length;
        this.batchPerWorker = options.batchPerWorker || 64;
        this.onProgress = options.onProgress || (() => {});
        this.onBatchComplete = options.onBatchComplete || (() => {});

        this.workers = [];
        this.stats = new SimulationStats();
        this.isRunning = false;
    }

    /**
     * Run parallel simulations
     * @param {number} numGames - Total games to run
     * @param {Array<string>} strategyTypes - Strategy types for players
     * @param {BanditPolicy} sharedPolicy - Shared ML policy for learning
     * @returns {Promise<SimulationStats>}
     */
    async runSimulations(numGames, strategyTypes, sharedPolicy = null) {
        this.isRunning = true;
        this.stats.reset();

        const startTime = Date.now();

        try {
            // 1. Initialize worker pool
            await this.initWorkerPool(strategyTypes, sharedPolicy);

            // 2. Calculate batch distribution
            const gamesPerBatch = this.numWorkers * this.batchPerWorker;
            let completed = 0;

            // 3. Main simulation loop
            while (completed < numGames && this.isRunning) {
                const remainingGames = numGames - completed;
                const batchSize = Math.min(this.batchPerWorker, Math.ceil(remainingGames / this.numWorkers));

                // Run batch on all workers in parallel
                const batchPromises = this.workers.map(worker =>
                    this.runWorkerBatch(worker, batchSize)
                );

                // Wait for all workers to complete their batch
                const results = await Promise.all(batchPromises);

                // 4. Merge results from all workers
                for (const result of results) {
                    if (result.stats) {
                        this.stats.merge(result.stats);
                    }

                    // Merge Q-values into shared policy
                    if (sharedPolicy && result.deltaQValues) {
                        sharedPolicy.mergeFrom(result.deltaQValues);
                    }
                }

                completed += results.reduce((sum, r) => sum + (r.gamesPlayed || 0), 0);

                // 5. Report progress
                const elapsed = (Date.now() - startTime) / 1000;
                const gps = completed / elapsed;

                this.onProgress({
                    completed,
                    total: numGames,
                    stats: this.stats,
                    elapsed,
                    gamesPerSecond: gps
                });

                this.onBatchComplete({
                    batchGames: results.reduce((sum, r) => sum + (r.gamesPlayed || 0), 0),
                    totalCompleted: completed
                });

                // 6. Periodically sync policy to workers (every 10 batches)
                if (sharedPolicy && completed % (gamesPerBatch * 10) === 0) {
                    await this.syncPolicyToWorkers(sharedPolicy);
                }
            }
        } finally {
            // 7. Cleanup workers
            await this.terminateWorkers();
            this.isRunning = false;
        }

        return this.stats;
    }

    /**
     * Initialize worker pool
     * @param {Array<string>} strategyTypes
     * @param {BanditPolicy} policy
     */
    async initWorkerPool(strategyTypes, policy) {
        const workerPath = path.join(__dirname, 'SimulationWorker.js');

        const workerPromises = [];

        for (let i = 0; i < this.numWorkers; i++) {
            const workerData = {
                strategyTypes,
                policyState: policy ? policy.toJSON() : null,
                workerId: i
            };

            const worker = new Worker(workerPath, { workerData });

            // Wait for worker to be ready
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
            workerPromises.push(readyPromise);
        }

        // Wait for all workers to be ready
        await Promise.all(workerPromises);
    }

    /**
     * Run a batch on a single worker
     * @param {Worker} worker
     * @param {number} batchSize
     * @returns {Promise<Object>}
     */
    runWorkerBatch(worker, batchSize) {
        return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
                cleanup();
                reject(new Error('Worker batch timeout'));
            }, 60000); // 60 second timeout

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

            worker.postMessage({ type: 'runBatch', batchSize });
        });
    }

    /**
     * Sync policy state to all workers
     * @param {BanditPolicy} policy
     */
    async syncPolicyToWorkers(policy) {
        const policyState = policy.toJSON();

        const syncPromises = this.workers.map(worker => {
            return new Promise((resolve, reject) => {
                const timeout = setTimeout(() => {
                    reject(new Error('Policy sync timeout'));
                }, 5000);

                const handler = (msg) => {
                    if (msg.type === 'policyUpdated') {
                        clearTimeout(timeout);
                        worker.removeListener('message', handler);
                        resolve();
                    }
                };

                worker.on('message', handler);
                worker.postMessage({ type: 'updatePolicy', policyState });
            });
        });

        await Promise.all(syncPromises);
    }

    /**
     * Terminate all workers
     */
    async terminateWorkers() {
        const terminatePromises = this.workers.map(worker => worker.terminate());
        await Promise.all(terminatePromises);
        this.workers = [];
    }

    /**
     * Stop the simulation
     */
    stop() {
        this.isRunning = false;
    }

    /**
     * Get current statistics
     * @returns {SimulationStats}
     */
    getStats() {
        return this.stats;
    }
}

module.exports = ParallelSimulationRunner;
