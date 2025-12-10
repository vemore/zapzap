/**
 * LightweightDQN
 * Pure JavaScript neural network inference for worker threads
 *
 * This module performs forward propagation WITHOUT TensorFlow.js
 * to enable network inference in worker threads where tfjs-node fails.
 *
 * Architecture matches DuelingDQN:
 * - Input: 45 features
 * - Hidden: Dense(256, relu) -> Dense(128, relu) -> Dense(64, relu) -> Dense(32, relu)
 * - Output: Action Q-values per decision type
 */

class LightweightDQN {
    constructor(config = {}) {
        this.inputDim = config.inputDim || 45;
        this.actionDims = {
            handSize: 7,
            zapzap: 2,
            playType: 5,
            drawSource: 2
        };
        this.decisionTypes = Object.keys(this.actionDims);

        // Network weights per decision type
        // Structure: { decisionType: [layer0_weights, layer0_bias, layer1_weights, ...] }
        this.weights = {};

        // Initialize with random weights
        for (const name of this.decisionTypes) {
            this.weights[name] = this._initializeRandomWeights(name);
        }
    }

    /**
     * Initialize random weights for a decision type
     */
    _initializeRandomWeights(decisionType) {
        const actionDim = this.actionDims[decisionType];

        // Layer sizes: 45 -> 256 -> 128 -> 64 -> 32 -> actionDim (matches new DuelingDQN)
        const layers = [
            { in: this.inputDim, out: 256 },  // layer 0
            { in: 256, out: 128 },             // layer 1
            { in: 128, out: 64 },              // layer 2
            { in: 64, out: 32 },               // layer 3
            { in: 32, out: actionDim }         // layer 4 (output)
        ];

        const weights = [];
        for (const layer of layers) {
            // He initialization
            const scale = Math.sqrt(2.0 / layer.in);
            const w = this._randomMatrix(layer.out, layer.in, scale);
            const b = new Array(layer.out).fill(0);
            weights.push(w, b);
        }

        return weights;
    }

    /**
     * Create random matrix with given scale
     */
    _randomMatrix(rows, cols, scale = 1.0) {
        const matrix = [];
        for (let i = 0; i < rows; i++) {
            const row = [];
            for (let j = 0; j < cols; j++) {
                row.push((Math.random() * 2 - 1) * scale);
            }
            matrix.push(row);
        }
        return matrix;
    }

    /**
     * Set weights from compact format (from main thread)
     * @param {Object} compactWeights - Weights from DuelingDQN.getCompactWeights()
     */
    setWeights(compactWeights) {
        for (const [name, layerWeights] of Object.entries(compactWeights)) {
            if (!this.weights[name]) continue;

            const reconstructed = [];
            for (const layer of layerWeights) {
                const { shape, data } = layer;
                const reshaped = this._reshapeArray(data, shape);
                reconstructed.push(reshaped);
            }
            this.weights[name] = reconstructed;
        }
    }

    /**
     * Reshape flat array to given shape
     * TensorFlow uses [in, out] format, we need [out, in] for our matmul
     */
    _reshapeArray(flat, shape) {
        if (shape.length === 1) {
            // Bias vector
            return Array.from(flat.slice(0, shape[0]));
        } else if (shape.length === 2) {
            // Weight matrix from TF: [in, out] -> we need [out, in] (transposed)
            const [inSize, outSize] = shape;
            const matrix = [];
            // Transpose: create outSize rows, each with inSize columns
            for (let o = 0; o < outSize; o++) {
                const row = [];
                for (let i = 0; i < inSize; i++) {
                    // Original index in flat array: i * outSize + o
                    row.push(flat[i * outSize + o]);
                }
                matrix.push(row);
            }
            return matrix;
        }
        return Array.from(flat);
    }

    /**
     * Forward pass through the network
     * @param {Array<number>} input - 45-dimensional feature vector
     * @param {string} decisionType - Decision type
     * @returns {Array<number>} Q-values for each action
     */
    predict(input, decisionType) {
        const layerWeights = this.weights[decisionType];
        if (!layerWeights) {
            throw new Error(`Unknown decision type: ${decisionType}`);
        }

        let activation = input;

        // Process each layer
        for (let i = 0; i < layerWeights.length; i += 2) {
            const weights = layerWeights[i];
            const bias = layerWeights[i + 1];

            // Matrix multiplication: output = weights @ input + bias
            const output = this._matmul(weights, activation);
            for (let j = 0; j < output.length; j++) {
                output[j] += bias[j];
            }

            // ReLU activation for all layers except the last
            if (i < layerWeights.length - 2) {
                for (let j = 0; j < output.length; j++) {
                    output[j] = Math.max(0, output[j]);
                }
            }

            activation = output;
        }

        return activation;
    }

    /**
     * Matrix-vector multiplication
     * @param {Array<Array<number>>} matrix - [rows, cols] matrix
     * @param {Array<number>} vector - [cols] vector
     * @returns {Array<number>} [rows] result vector
     */
    _matmul(matrix, vector) {
        const result = [];
        for (let i = 0; i < matrix.length; i++) {
            let sum = 0;
            const row = matrix[i];
            for (let j = 0; j < row.length; j++) {
                sum += row[j] * (vector[j] || 0);
            }
            result.push(sum);
        }
        return result;
    }

    /**
     * Select action using epsilon-greedy policy
     * @param {Array<number>} input - Feature vector
     * @param {string} decisionType - Decision type
     * @param {number} epsilon - Exploration rate
     * @returns {number} Selected action index
     */
    selectAction(input, decisionType, epsilon = 0.1) {
        const actionDim = this.actionDims[decisionType];

        // Exploration
        if (Math.random() < epsilon) {
            return Math.floor(Math.random() * actionDim);
        }

        // Exploitation - greedy action
        const qValues = this.predict(input, decisionType);
        let bestAction = 0;
        let bestValue = qValues[0];
        for (let i = 1; i < qValues.length; i++) {
            if (qValues[i] > bestValue) {
                bestValue = qValues[i];
                bestAction = i;
            }
        }
        return bestAction;
    }

    /**
     * Get Q-values for all actions
     * @param {Array<number>} input - Feature vector
     * @param {string} decisionType - Decision type
     * @returns {Array<number>} Q-values
     */
    getQValues(input, decisionType) {
        return this.predict(input, decisionType);
    }

    /**
     * Check if weights have been loaded
     * @returns {boolean}
     */
    hasWeights() {
        // Check if weights look non-random (biases not all zero after training)
        for (const name of this.decisionTypes) {
            const layerWeights = this.weights[name];
            if (layerWeights && layerWeights.length > 1) {
                const bias = layerWeights[1];
                if (Array.isArray(bias)) {
                    const nonZero = bias.some(b => Math.abs(b) > 0.001);
                    if (nonZero) return true;
                }
            }
        }
        return false;
    }
}

module.exports = LightweightDQN;
