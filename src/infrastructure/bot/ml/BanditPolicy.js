/**
 * BanditPolicy
 * Contextual Multi-Armed Bandit with Epsilon-Greedy exploration
 * for online learning in card game decision-making
 */

const FeatureExtractor = require('./FeatureExtractor');

class BanditPolicy {
    /**
     * @param {Object} options - Policy options
     * @param {number} options.epsilon - Initial exploration rate (default: 0.1)
     * @param {number} options.minEpsilon - Minimum epsilon after decay (default: 0.01)
     * @param {number} options.epsilonDecay - Decay rate per update (default: 0.9999)
     * @param {number} options.learningRate - For incremental mean updates (default: 0.1)
     */
    constructor(options = {}) {
        // Optimized hyperparameters for faster convergence
        this.epsilon = options.epsilon || 0.3;           // Reasonable initial exploration
        this.minEpsilon = options.minEpsilon || 0.02;    // Near-pure exploitation after convergence
        this.epsilonDecay = options.epsilonDecay || 0.9999;  // 10x faster decay than before
        this.learningRate = options.learningRate || 0.15;    // Slightly more reactive
        this.trainedMode = false;  // When true, forces low epsilon

        // Q-values stored as: contextKey -> action -> { sum, count, mean }
        this.qValues = {};

        // Action spaces for each decision type
        this.actions = {
            handSize: [4, 5, 6, 7],
            handSizeGolden: [4, 5, 6, 7, 8, 9, 10],
            zapzap: [true, false],
            // Extended play types with joker management
            playType: [
                'optimal',           // Best play minimizing remaining hand value
                'single_high',       // Single highest value card
                'multi_high',        // Multi-card play (pair/sequence)
                'avoid_joker',       // Play without using jokers (keep for later)
                'use_joker_combo'    // Prioritize using jokers in combos
            ],
            drawSource: ['deck', 'played']
        };

        // Statistics
        this.totalUpdates = 0;
        this.explorations = 0;
        this.exploitations = 0;
    }

    /**
     * Select action using epsilon-greedy policy
     * @param {string} decisionType - Type of decision
     * @param {Object} features - Context features
     * @param {Array} availableActions - Optional: restrict to these actions
     * @returns {*} Selected action
     */
    selectAction(decisionType, features, availableActions = null) {
        const contextKey = FeatureExtractor.getContextKey(decisionType, features);

        // Get action space
        let actions;
        if (availableActions) {
            actions = availableActions;
        } else if (decisionType === 'handSize' && features.isGoldenScore) {
            actions = this.actions.handSizeGolden;
        } else {
            actions = this.actions[decisionType] || [];
        }

        if (actions.length === 0) {
            return null;
        }

        // Get effective epsilon (use very low if in trained mode)
        const effectiveEpsilon = this.trainedMode ? 0.02 : this.epsilon;

        // Epsilon-greedy selection
        if (Math.random() < effectiveEpsilon) {
            // Exploration: random action
            this.explorations++;
            return actions[Math.floor(Math.random() * actions.length)];
        }

        // Exploitation: best known action
        this.exploitations++;
        return this.getBestAction(contextKey, actions);
    }

    /**
     * Get the best action for a context based on Q-values
     * @param {string} contextKey - Context key
     * @param {Array} actions - Available actions
     * @returns {*} Best action
     */
    getBestAction(contextKey, actions) {
        const contextQ = this.qValues[contextKey];

        if (!contextQ) {
            // No data for this context - return random
            return actions[Math.floor(Math.random() * actions.length)];
        }

        let bestAction = actions[0];
        let bestValue = -Infinity;

        for (const action of actions) {
            const actionKey = String(action);
            const qData = contextQ[actionKey];

            if (qData && qData.mean > bestValue) {
                bestValue = qData.mean;
                bestAction = action;
            }
        }

        // If no action has data, return random
        if (bestValue === -Infinity) {
            return actions[Math.floor(Math.random() * actions.length)];
        }

        return bestAction;
    }

    /**
     * Update Q-values based on reward
     * @param {string} decisionType - Type of decision
     * @param {Object} features - Context features
     * @param {*} action - Action taken
     * @param {number} reward - Reward received
     */
    update(decisionType, features, action, reward) {
        const contextKey = FeatureExtractor.getContextKey(decisionType, features);
        const actionKey = String(action);

        // Initialize context if needed
        if (!this.qValues[contextKey]) {
            this.qValues[contextKey] = {};
        }

        // Initialize action if needed
        if (!this.qValues[contextKey][actionKey]) {
            this.qValues[contextKey][actionKey] = {
                sum: 0,
                count: 0,
                mean: 0
            };
        }

        const entry = this.qValues[contextKey][actionKey];

        // Incremental mean update (running average)
        entry.count += 1;
        entry.sum += reward;

        // Use exponential moving average for more recent data weight
        if (entry.count === 1) {
            entry.mean = reward;
        } else {
            entry.mean = entry.mean + this.learningRate * (reward - entry.mean);
        }

        // Decay epsilon
        this.epsilon = Math.max(this.minEpsilon, this.epsilon * this.epsilonDecay);

        this.totalUpdates++;
    }

    /**
     * Batch update from multiple decisions
     * @param {Array<Object>} decisions - Array of {type, features, action} objects
     * @param {number} reward - Shared reward for all decisions
     */
    batchUpdate(decisions, reward) {
        for (const decision of decisions) {
            this.update(decision.type, decision.features, decision.action, reward);
        }
    }

    /**
     * Get Q-value for a specific context-action pair
     * @param {string} decisionType
     * @param {Object} features
     * @param {*} action
     * @returns {number|null}
     */
    getQValue(decisionType, features, action) {
        const contextKey = FeatureExtractor.getContextKey(decisionType, features);
        const actionKey = String(action);

        return this.qValues[contextKey]?.[actionKey]?.mean ?? null;
    }

    /**
     * Get all Q-values for a context
     * @param {string} decisionType
     * @param {Object} features
     * @returns {Object|null}
     */
    getContextQValues(decisionType, features) {
        const contextKey = FeatureExtractor.getContextKey(decisionType, features);
        return this.qValues[contextKey] || null;
    }

    /**
     * Get statistics about the policy
     * @returns {Object}
     */
    getStats() {
        const contextCount = Object.keys(this.qValues).length;
        let totalActions = 0;
        let totalSamples = 0;

        for (const context of Object.values(this.qValues)) {
            totalActions += Object.keys(context).length;
            for (const action of Object.values(context)) {
                totalSamples += action.count;
            }
        }

        return {
            epsilon: this.epsilon,
            contextCount,
            totalActions,
            totalSamples,
            totalUpdates: this.totalUpdates,
            explorations: this.explorations,
            exploitations: this.exploitations,
            explorationRate: this.explorations / (this.explorations + this.exploitations || 1)
        };
    }

    /**
     * Export policy to JSON
     * @returns {Object}
     */
    toJSON() {
        return {
            epsilon: this.epsilon,
            minEpsilon: this.minEpsilon,
            epsilonDecay: this.epsilonDecay,
            learningRate: this.learningRate,
            trainedMode: this.trainedMode,
            qValues: this.qValues,
            totalUpdates: this.totalUpdates,
            explorations: this.explorations,
            exploitations: this.exploitations
        };
    }

    /**
     * Import policy from JSON
     * @param {Object} data
     */
    fromJSON(data) {
        this.epsilon = data.epsilon || 0.3;
        this.minEpsilon = data.minEpsilon || 0.02;
        this.epsilonDecay = data.epsilonDecay || 0.9999;
        this.learningRate = data.learningRate || 0.15;
        this.trainedMode = data.trainedMode || false;
        this.qValues = data.qValues || {};
        this.totalUpdates = data.totalUpdates || 0;
        this.explorations = data.explorations || 0;
        this.exploitations = data.exploitations || 0;
    }

    /**
     * Reset the policy
     */
    reset() {
        this.qValues = {};
        this.totalUpdates = 0;
        this.explorations = 0;
        this.exploitations = 0;
        this.epsilon = 0.3;
        this.trainedMode = false;
    }

    /**
     * Set trained mode for pure exploitation
     * Use this after training is complete to maximize performance
     * @param {boolean} enabled - Whether to enable trained mode
     */
    setTrainedMode(enabled) {
        this.trainedMode = enabled;
        if (enabled) {
            // In trained mode, we mostly exploit learned knowledge
            // but keep minimal exploration to adapt to variations
            this.epsilon = 0.02;
        }
    }

    /**
     * Check if policy is in trained mode
     * @returns {boolean}
     */
    isTrainedMode() {
        return this.trainedMode;
    }

    /**
     * Merge Q-values from another policy (for parallel training)
     * Uses weighted average based on sample counts
     * @param {Object} otherQValues - Q-values from another worker
     */
    mergeFrom(otherQValues) {
        if (!otherQValues) return;

        for (const [contextKey, actions] of Object.entries(otherQValues)) {
            if (!this.qValues[contextKey]) {
                this.qValues[contextKey] = {};
            }

            for (const [actionKey, otherData] of Object.entries(actions)) {
                if (!this.qValues[contextKey][actionKey]) {
                    // New entry - copy directly
                    this.qValues[contextKey][actionKey] = {
                        sum: otherData.sum,
                        count: otherData.count,
                        mean: otherData.mean
                    };
                } else {
                    // Existing entry - weighted average
                    const myData = this.qValues[contextKey][actionKey];
                    const totalCount = myData.count + otherData.count;

                    if (totalCount > 0) {
                        myData.mean = (myData.mean * myData.count + otherData.mean * otherData.count) / totalCount;
                        myData.sum += otherData.sum;
                        myData.count = totalCount;
                    }
                }
            }
        }
    }

    /**
     * Batch merge from multiple workers
     * @param {Array<Object>} workerQValues - Array of Q-values from workers
     */
    batchMergeFrom(workerQValues) {
        for (const qValues of workerQValues) {
            this.mergeFrom(qValues);
        }
    }

    /**
     * Get the most effective actions per decision type
     * @returns {Object}
     */
    getBestActions() {
        const bestActions = {};

        for (const [contextKey, actions] of Object.entries(this.qValues)) {
            const [decisionType] = contextKey.split(':');

            if (!bestActions[decisionType]) {
                bestActions[decisionType] = {};
            }

            let bestAction = null;
            let bestMean = -Infinity;

            for (const [actionKey, data] of Object.entries(actions)) {
                if (data.mean > bestMean && data.count >= 10) {
                    bestMean = data.mean;
                    bestAction = actionKey;
                }
            }

            if (bestAction) {
                if (!bestActions[decisionType][bestAction]) {
                    bestActions[decisionType][bestAction] = 0;
                }
                bestActions[decisionType][bestAction]++;
            }
        }

        return bestActions;
    }
}

module.exports = BanditPolicy;
