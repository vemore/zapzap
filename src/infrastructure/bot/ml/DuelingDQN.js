/**
 * DuelingDQN
 * Multi-head Deep Q-Network for ZapZap bot decisions
 *
 * Simplified architecture without custom layers to avoid tfjs-node issues.
 * Uses standard layers only.
 *
 * Architecture:
 * - Shared encoder: Input → Dense(128) → Dense(64)
 * - 4 decision heads:
 *   - handSize: 7 actions [4,5,6,7,8,9,10]
 *   - zapzap: 2 actions [true, false]
 *   - playType: 5 actions [optimal, single_high, multi_high, avoid_joker, use_joker_combo]
 *   - drawSource: 2 actions [deck, played]
 */

const tf = require('@tensorflow/tfjs');

class DuelingDQN {
    /**
     * @param {Object} config - Network configuration
     * @param {number} config.inputDim - Input feature dimension (default: 45)
     * @param {Array<number>} config.hiddenUnits - Hidden layer sizes (default: [128, 64])
     * @param {number} config.learningRate - Learning rate (default: 0.0005)
     */
    constructor(config = {}) {
        this.inputDim = config.inputDim || 45;
        // Increased network capacity for better learning against hard opponents
        this.hiddenUnits = config.hiddenUnits || [256, 128, 64];
        this.learningRate = config.learningRate || 0.0003;

        // Action dimensions for each decision type
        this.actionDims = {
            handSize: 7,      // [4,5,6,7,8,9,10]
            zapzap: 2,        // [true, false]
            playType: 5,      // [optimal, single_high, multi_high, avoid_joker, use_joker_combo]
            drawSource: 2     // [deck, played]
        };

        this.decisionTypes = Object.keys(this.actionDims);

        // Build separate models for each decision type (avoids multi-output issues)
        this.models = {};
        this.targetModels = {};
        this.optimizers = {};

        for (const [name, actionDim] of Object.entries(this.actionDims)) {
            this.models[name] = this._buildSingleModel(name, actionDim);
            this.targetModels[name] = this._buildSingleModel(`${name}_target`, actionDim);
            this.optimizers[name] = tf.train.adam(this.learningRate);
        }

        // Sync target networks
        this.updateTargetNetwork();
    }

    /**
     * Build a simple Q-network for one decision type
     */
    _buildSingleModel(name, actionDim) {
        // Build deeper network with 3 hidden layers for better representation
        const layers = [
            tf.layers.dense({
                units: this.hiddenUnits[0],  // 256
                activation: 'relu',
                inputShape: [this.inputDim],
                kernelInitializer: 'heNormal'
            }),
            tf.layers.dense({
                units: this.hiddenUnits[1],  // 128
                activation: 'relu',
                kernelInitializer: 'heNormal'
            }),
            tf.layers.dense({
                units: this.hiddenUnits[2] || 64,  // 64
                activation: 'relu',
                kernelInitializer: 'heNormal'
            }),
            tf.layers.dense({
                units: 32,
                activation: 'relu',
                kernelInitializer: 'heNormal'
            }),
            tf.layers.dense({
                units: actionDim,
                kernelInitializer: 'heNormal'
            })
        ];

        const model = tf.sequential({ name, layers });
        return model;
    }

    /**
     * Predict Q-values for a single state and decision type
     * @param {Array<number>} state - Feature vector
     * @param {string} decisionType - One of: handSize, zapzap, playType, drawSource
     * @returns {Array<number>} Q-values for each action
     */
    predict(state, decisionType) {
        return tf.tidy(() => {
            const stateTensor = tf.tensor2d([state], [1, this.inputDim]);
            const predictions = this.models[decisionType].predict(stateTensor);
            return Array.from(predictions.dataSync());
        });
    }

    /**
     * Predict Q-values for a batch of states
     * @param {Array<Array<number>>} states - Batch of feature vectors
     * @param {string} decisionType - Decision type
     * @returns {tf.Tensor} Q-values tensor
     */
    predictBatch(states, decisionType) {
        return tf.tidy(() => {
            const stateTensor = tf.tensor2d(states);
            return this.models[decisionType].predict(stateTensor);
        });
    }

    /**
     * Predict Q-values using target network
     */
    predictTarget(states, decisionType) {
        return tf.tidy(() => {
            const stateTensor = tf.tensor2d(states);
            return this.targetModels[decisionType].predict(stateTensor);
        });
    }

    /**
     * Train on a batch of transitions for a specific decision type
     * Uses Keras-style fit with custom loss calculation
     * @param {Array<Object>} batch - Transitions {state, actionIdx, reward, nextState, done}
     * @param {Float32Array} weights - Importance sampling weights
     * @param {number} gamma - Discount factor
     * @param {string} decisionType - Decision type
     * @returns {Array<number>} TD errors for priority updates
     */
    async trainOnBatch(batch, weights, gamma, decisionType) {
        if (batch.length === 0) return [];

        const states = batch.map(t => t.state);
        const nextStates = batch.map(t => t.nextState);
        const actions = batch.map(t => t.actionIdx);
        const rewards = batch.map(t => t.reward);
        const dones = batch.map(t => t.done ? 0 : 1);

        const model = this.models[decisionType];
        const targetModel = this.targetModels[decisionType];

        // Calculate TD targets using Double DQN
        const statesTensor = tf.tensor2d(states);
        const nextStatesTensor = tf.tensor2d(nextStates);

        // Current Q-values
        const qCurrent = model.predict(statesTensor);
        const qCurrentData = qCurrent.arraySync();

        // Q(s', a) from online network - select best action
        const qNextOnline = model.predict(nextStatesTensor);
        const bestActions = qNextOnline.argMax(1).arraySync();

        // Q(s', a*) from target network - evaluate action
        const qNextTarget = targetModel.predict(nextStatesTensor);
        const qTargetData = qNextTarget.arraySync();

        // Build target Q-values array and compute TD errors
        const targetQ = [];
        const tdErrors = [];

        for (let i = 0; i < batch.length; i++) {
            // Get max Q for next state using Double DQN
            const bestAction = bestActions[i];
            const qNext = qTargetData[i][bestAction];

            // TD target: r + gamma * Q_target(s', argmax_a Q_online(s', a)) * (1 - done)
            const tdTarget = rewards[i] + gamma * qNext * dones[i];

            // Current Q for taken action
            const qTaken = qCurrentData[i][actions[i]];

            // TD error
            tdErrors.push(Math.abs(tdTarget - qTaken));

            // Build target array: copy current Q-values, update only the taken action
            const target = [...qCurrentData[i]];
            target[actions[i]] = tdTarget;
            targetQ.push(target);
        }

        const targetQValues = tf.tensor2d(targetQ);

        // Cleanup intermediate tensors
        nextStatesTensor.dispose();
        qCurrent.dispose();
        qNextOnline.dispose();
        qNextTarget.dispose();

        // Compile model if not already done
        if (!model.optimizer) {
            model.compile({
                optimizer: tf.train.adam(this.learningRate),
                loss: 'meanSquaredError'
            });
        }

        // Single training step
        await model.fit(statesTensor, targetQValues, {
            epochs: 1,
            batchSize: batch.length,
            verbose: 0
        });

        // Cleanup
        statesTensor.dispose();
        targetQValues.dispose();

        return tdErrors;
    }

    /**
     * Update target network with current network weights
     */
    updateTargetNetwork() {
        for (const name of this.decisionTypes) {
            const weights = this.models[name].getWeights();
            this.targetModels[name].setWeights(weights);
        }
    }

    /**
     * Soft update target network (Polyak averaging)
     * @param {number} tau - Update rate (0-1)
     */
    softUpdateTargetNetwork(tau = 0.005) {
        for (const name of this.decisionTypes) {
            const modelWeights = this.models[name].getWeights();
            const targetWeights = this.targetModels[name].getWeights();

            const newWeights = modelWeights.map((w, i) => {
                return tf.tidy(() => {
                    return w.mul(tau).add(targetWeights[i].mul(1 - tau));
                });
            });

            this.targetModels[name].setWeights(newWeights);
            newWeights.forEach(w => w.dispose());
        }
    }

    /**
     * Get model weights for saving
     */
    async getWeights() {
        const allWeights = {};
        for (const name of this.decisionTypes) {
            const weights = [];
            for (const w of this.models[name].getWeights()) {
                weights.push({
                    name: w.name,
                    data: await w.array(),
                    shape: w.shape
                });
            }
            allWeights[name] = weights;
        }
        return allWeights;
    }

    /**
     * Get weights in compact format for worker transfer
     * Flattens nested arrays for efficient serialization
     * @returns {Object} Compact weights object
     */
    async getCompactWeights() {
        const compactWeights = {};
        for (const name of this.decisionTypes) {
            const layerWeights = [];
            for (const w of this.models[name].getWeights()) {
                const data = await w.array();
                layerWeights.push({
                    shape: w.shape,
                    data: this._flattenArray(data)
                });
            }
            compactWeights[name] = layerWeights;
        }
        return compactWeights;
    }

    /**
     * Flatten nested array to 1D
     */
    _flattenArray(arr) {
        if (!Array.isArray(arr)) return [arr];
        return arr.flat(Infinity);
    }

    /**
     * Set model weights from saved data
     */
    setWeights(allWeights) {
        for (const [name, weights] of Object.entries(allWeights)) {
            if (this.models[name] && weights) {
                const tensors = weights.map(w => tf.tensor(w.data, w.shape));
                this.models[name].setWeights(tensors);
                this.targetModels[name].setWeights(tensors);
                tensors.forEach(t => t.dispose());
            }
        }
    }

    /**
     * Save models to directory using JSON weights
     */
    async saveModel(basePath) {
        const fs = require('fs');
        const path = require('path');

        if (!fs.existsSync(basePath)) {
            fs.mkdirSync(basePath, { recursive: true });
        }

        // Save weights as JSON
        const weights = await this.getWeights();
        const weightsPath = path.join(basePath, 'weights.json');
        fs.writeFileSync(weightsPath, JSON.stringify(weights));

        // Save config
        const config = {
            inputDim: this.inputDim,
            hiddenUnits: this.hiddenUnits,
            learningRate: this.learningRate,
            actionDims: this.actionDims
        };
        const configPath = path.join(basePath, 'config.json');
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
    }

    /**
     * Load models from directory using JSON weights
     */
    async loadModel(basePath) {
        const fs = require('fs');
        const path = require('path');

        const weightsPath = path.join(basePath, 'weights.json');
        if (fs.existsSync(weightsPath)) {
            const weights = JSON.parse(fs.readFileSync(weightsPath, 'utf-8'));
            this.setWeights(weights);
        } else {
            console.warn(`No weights file found at ${weightsPath}`);
        }
    }

    /**
     * Get model summary
     */
    summary() {
        for (const name of this.decisionTypes) {
            console.log(`\n=== ${name} ===`);
            this.models[name].summary();
        }
    }

    /**
     * Dispose of model resources
     */
    dispose() {
        for (const name of this.decisionTypes) {
            this.models[name].dispose();
            this.targetModels[name].dispose();
        }
    }
}

module.exports = DuelingDQN;
