/**
 * DRLPolicy
 * Deep Reinforcement Learning Policy using Double DQN with Prioritized Experience Replay
 *
 * This policy wraps the DuelingDQN network and PrioritizedReplayBuffer
 * to provide action selection and training functionality.
 */

const DuelingDQN = require('./DuelingDQN');
const PrioritizedReplayBuffer = require('./PrioritizedReplayBuffer');

class DRLPolicy {
    /**
     * @param {Object} config - Policy configuration
     * @param {number} config.inputDim - Feature dimension (default: 45)
     * @param {number} config.bufferSize - Replay buffer capacity (default: 100000)
     * @param {number} config.batchSize - Training batch size (default: 64)
     * @param {number} config.gamma - Discount factor (default: 0.99)
     * @param {number} config.epsilon - Initial exploration rate (default: 0.3)
     * @param {number} config.minEpsilon - Minimum exploration rate (default: 0.02)
     * @param {number} config.epsilonDecay - Epsilon decay rate (default: 0.9999)
     * @param {number} config.targetUpdateFreq - Target network update frequency (default: 1000)
     * @param {number} config.learningRate - Network learning rate (default: 0.0005)
     */
    constructor(config = {}) {
        this.config = {
            inputDim: config.inputDim || 45,
            bufferSize: config.bufferSize || 100000,
            batchSize: config.batchSize || 64,
            gamma: config.gamma || 0.99,
            epsilon: config.epsilon || 0.3,
            minEpsilon: config.minEpsilon || 0.02,
            epsilonDecay: config.epsilonDecay || 0.95,
            targetUpdateFreq: config.targetUpdateFreq || 1000,
            learningRate: config.learningRate || 0.0005,
            minBufferSize: config.minBufferSize || 256
        };

        // Initialize network
        this.network = new DuelingDQN({
            inputDim: this.config.inputDim,
            learningRate: this.config.learningRate
        });

        // Initialize replay buffer
        this.replayBuffer = new PrioritizedReplayBuffer(
            this.config.bufferSize,
            0.6, // alpha
            0.4  // beta
        );

        // Training state
        this.epsilon = this.config.epsilon;
        this.trainSteps = 0;
        this.trainedMode = false;

        // Action mappings
        this.actionMaps = {
            handSize: [4, 5, 6, 7, 8, 9, 10],
            zapzap: [true, false],
            playType: ['optimal', 'single_high', 'multi_high', 'avoid_joker', 'use_joker_combo'],
            drawSource: ['deck', 'played']
        };

        // Reverse mappings for action indices
        this.actionToIdx = {};
        for (const [type, actions] of Object.entries(this.actionMaps)) {
            this.actionToIdx[type] = {};
            actions.forEach((action, idx) => {
                this.actionToIdx[type][action] = idx;
            });
        }

        // Statistics
        this.stats = {
            totalDecisions: 0,
            explorations: 0,
            trainings: 0,
            avgLoss: 0,
            avgTdError: 0
        };
    }

    /**
     * Select an action using epsilon-greedy policy
     * @param {string} decisionType - Type of decision
     * @param {Array<number>} features - Feature vector
     * @returns {*} Selected action value
     */
    selectAction(decisionType, features) {
        this.stats.totalDecisions++;
        const actions = this.actionMaps[decisionType];
        const eps = this.trainedMode ? this.config.minEpsilon : this.epsilon;

        // Epsilon-greedy exploration
        if (Math.random() < eps) {
            this.stats.explorations++;
            return actions[Math.floor(Math.random() * actions.length)];
        }

        // Exploit: select action with highest Q-value
        const qValues = this.network.predict(features, decisionType);
        const actionIdx = qValues.indexOf(Math.max(...qValues));
        return actions[actionIdx];
    }

    /**
     * Get action index for a given action value
     * @param {string} decisionType - Type of decision
     * @param {*} action - Action value
     * @returns {number} Action index
     */
    getActionIdx(decisionType, action) {
        return this.actionToIdx[decisionType][action];
    }

    /**
     * Store a transition in the replay buffer
     * @param {Object} transition - {state, action, reward, nextState, done, decisionType}
     */
    storeTransition(transition) {
        // Convert action to index
        const actionIdx = this.getActionIdx(transition.decisionType, transition.action);
        this.replayBuffer.add({
            state: transition.state,
            actionIdx,
            reward: transition.reward,
            nextState: transition.nextState,
            done: transition.done,
            decisionType: transition.decisionType
        });
    }

    /**
     * Store multiple transitions (batch)
     * @param {Array<Object>} transitions
     */
    storeTransitions(transitions) {
        for (const transition of transitions) {
            this.storeTransition(transition);
        }
    }

    /**
     * Train the network on a batch from the replay buffer
     * @returns {number} Average TD error (0 if not enough samples)
     */
    async train() {
        // Check if buffer has enough samples
        if (!this.replayBuffer.isReady(this.config.minBufferSize)) {
            return 0;
        }

        // Sample batch
        const { batch, indices, weights } = this.replayBuffer.sample(this.config.batchSize);

        // Group transitions by decision type
        const batchesByType = {};
        const indicesByType = {};
        const weightsByType = {};

        for (let i = 0; i < batch.length; i++) {
            const t = batch[i];
            if (!t) continue;

            const type = t.decisionType;
            if (!batchesByType[type]) {
                batchesByType[type] = [];
                indicesByType[type] = [];
                weightsByType[type] = [];
            }
            batchesByType[type].push(t);
            indicesByType[type].push(indices[i]);
            weightsByType[type].push(weights[i]);
        }

        // Train each decision type
        const allTdErrors = [];
        const allIndices = [];

        for (const [type, typeBatch] of Object.entries(batchesByType)) {
            const typeWeights = new Float32Array(weightsByType[type]);
            const tdErrors = await this.network.trainOnBatch(
                typeBatch,
                typeWeights,
                this.config.gamma,
                type
            );

            allTdErrors.push(...tdErrors);
            allIndices.push(...indicesByType[type]);
        }

        // Update priorities
        if (allTdErrors.length > 0 && allIndices.length > 0) {
            this.replayBuffer.updatePriorities(allIndices, allTdErrors);
        }

        // Update training state
        this.trainSteps++;
        this.epsilon = Math.max(
            this.config.minEpsilon,
            this.epsilon * this.config.epsilonDecay
        );

        // Update target network periodically
        if (this.trainSteps % this.config.targetUpdateFreq === 0) {
            this.network.updateTargetNetwork();
        }

        // Update stats
        const avgTdError = allTdErrors.length > 0
            ? allTdErrors.reduce((a, b) => a + Math.abs(b), 0) / allTdErrors.length
            : 0;
        this.stats.trainings++;
        this.stats.avgTdError = avgTdError;

        return avgTdError;
    }

    /**
     * Train multiple times
     * @param {number} iterations - Number of training iterations
     */
    async trainMultiple(iterations) {
        for (let i = 0; i < iterations; i++) {
            await this.train();
        }
    }

    /**
     * Set trained mode (low exploration)
     * @param {boolean} enabled
     */
    setTrainedMode(enabled) {
        this.trainedMode = enabled;
        if (enabled) {
            this.epsilon = this.config.minEpsilon;
        }
    }

    /**
     * Reset exploration rate
     */
    resetExploration() {
        this.epsilon = this.config.epsilon;
    }

    /**
     * Get Q-values for all actions of a decision type
     * @param {string} decisionType
     * @param {Array<number>} features
     * @returns {Object} Map of action to Q-value
     */
    getQValues(decisionType, features) {
        const qValues = this.network.predict(features, decisionType);
        const actions = this.actionMaps[decisionType];
        const result = {};
        actions.forEach((action, idx) => {
            result[action] = qValues[idx];
        });
        return result;
    }

    /**
     * Get network weights for saving or worker sync
     */
    async getWeights() {
        return await this.network.getWeights();
    }

    /**
     * Set network weights (from loading or worker sync)
     */
    setWeights(weights) {
        this.network.setWeights(weights);
    }

    /**
     * Export policy state for saving
     */
    async toJSON() {
        return {
            config: this.config,
            weights: await this.getWeights(),
            epsilon: this.epsilon,
            trainSteps: this.trainSteps,
            stats: this.stats,
            bufferStats: this.replayBuffer.getStats()
        };
    }

    /**
     * Import policy state from saved data
     */
    fromJSON(data) {
        if (data.config) {
            Object.assign(this.config, data.config);
        }
        if (data.weights) {
            this.setWeights(data.weights);
        }
        if (data.epsilon !== undefined) {
            this.epsilon = data.epsilon;
        }
        if (data.trainSteps !== undefined) {
            this.trainSteps = data.trainSteps;
        }
        if (data.stats) {
            Object.assign(this.stats, data.stats);
        }
    }

    /**
     * Save model to file
     */
    async saveModel(path) {
        await this.network.saveModel(path);
    }

    /**
     * Load model from file
     */
    async loadModel(path) {
        await this.network.loadModel(path);
    }

    /**
     * Get policy statistics
     */
    getStats() {
        return {
            ...this.stats,
            epsilon: this.epsilon,
            trainSteps: this.trainSteps,
            bufferSize: this.replayBuffer.size(),
            trainedMode: this.trainedMode,
            explorationRate: this.stats.totalDecisions > 0
                ? this.stats.explorations / this.stats.totalDecisions
                : 0
        };
    }

    /**
     * Reset statistics
     */
    resetStats() {
        this.stats = {
            totalDecisions: 0,
            explorations: 0,
            trainings: 0,
            avgLoss: 0,
            avgTdError: 0
        };
    }

    /**
     * Clear replay buffer
     */
    clearBuffer() {
        this.replayBuffer.clear();
    }

    /**
     * Dispose of resources
     */
    dispose() {
        this.network.dispose();
    }
}

module.exports = DRLPolicy;
