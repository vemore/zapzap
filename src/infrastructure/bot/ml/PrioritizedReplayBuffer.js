/**
 * PrioritizedReplayBuffer
 * Experience replay buffer with prioritized sampling based on TD-error
 * Uses SumTree data structure for efficient O(log n) sampling
 */

/**
 * SumTree for efficient priority-based sampling
 * Each leaf stores a priority, internal nodes store sums
 */
class SumTree {
    constructor(capacity) {
        this.capacity = capacity;
        // Tree size: 2 * capacity - 1 (binary tree with capacity leaves)
        this.tree = new Float64Array(2 * capacity - 1);
        this.data = new Array(capacity);
        this.write = 0;
        this.size = 0;
    }

    /**
     * Propagate priority change up the tree
     */
    _propagate(idx, change) {
        let parent = Math.floor((idx - 1) / 2);
        this.tree[parent] += change;
        if (parent !== 0) {
            this._propagate(parent, change);
        }
    }

    /**
     * Retrieve leaf index for a given value
     */
    _retrieve(idx, s) {
        const left = 2 * idx + 1;
        const right = left + 1;

        if (left >= this.tree.length) {
            return idx;
        }

        if (s <= this.tree[left]) {
            return this._retrieve(left, s);
        } else {
            return this._retrieve(right, s - this.tree[left]);
        }
    }

    /**
     * Add a new experience with priority
     */
    add(priority, data) {
        const idx = this.write + this.capacity - 1;
        this.data[this.write] = data;
        this.update(idx, priority);

        this.write = (this.write + 1) % this.capacity;
        this.size = Math.min(this.size + 1, this.capacity);
    }

    /**
     * Update priority at index
     */
    update(idx, priority) {
        const change = priority - this.tree[idx];
        this.tree[idx] = priority;
        this._propagate(idx, change);
    }

    /**
     * Get experience for a given priority value
     */
    get(s) {
        const idx = this._retrieve(0, s);
        const dataIdx = idx - this.capacity + 1;
        return {
            idx,
            priority: this.tree[idx],
            data: this.data[dataIdx]
        };
    }

    /**
     * Get total priority sum
     */
    total() {
        return this.tree[0];
    }

    /**
     * Get minimum priority in the tree
     */
    min() {
        let minPriority = Infinity;
        for (let i = 0; i < this.size; i++) {
            const idx = i + this.capacity - 1;
            if (this.tree[idx] > 0 && this.tree[idx] < minPriority) {
                minPriority = this.tree[idx];
            }
        }
        return minPriority === Infinity ? 1 : minPriority;
    }
}

class PrioritizedReplayBuffer {
    /**
     * @param {number} capacity - Maximum buffer size
     * @param {number} alpha - Priority exponent (0 = uniform, 1 = full prioritization)
     * @param {number} beta - Importance sampling exponent (annealed to 1)
     */
    constructor(capacity = 100000, alpha = 0.6, beta = 0.4) {
        this.capacity = capacity;
        this.alpha = alpha;
        this.beta = beta;
        this.betaIncrement = 0.001;
        this.epsilon = 0.01; // Small constant to avoid zero priorities
        this.maxPriority = 1.0;
        this.tree = new SumTree(capacity);
    }

    /**
     * Add a transition to the buffer
     * @param {Object} transition - {state, action, reward, nextState, done, decisionType, actionIdx}
     */
    add(transition) {
        // New experiences get max priority to ensure they're sampled at least once
        const priority = Math.pow(this.maxPriority, this.alpha);
        this.tree.add(priority, transition);
    }

    /**
     * Sample a batch with prioritized sampling
     * @param {number} batchSize - Number of samples
     * @returns {Object} {batch, indices, weights}
     */
    sample(batchSize) {
        const batch = [];
        const indices = [];
        const priorities = [];

        // Segment total priority
        const segment = this.tree.total() / batchSize;

        // Anneal beta towards 1
        this.beta = Math.min(1.0, this.beta + this.betaIncrement);

        for (let i = 0; i < batchSize; i++) {
            // Sample uniformly from each segment
            const a = segment * i;
            const b = segment * (i + 1);
            const s = Math.random() * (b - a) + a;

            const { idx, priority, data } = this.tree.get(s);

            if (data) {
                batch.push(data);
                indices.push(idx);
                priorities.push(priority);
            }
        }

        // Calculate importance sampling weights
        const totalPriority = this.tree.total();
        const minPriority = this.tree.min();
        const maxWeight = Math.pow(this.tree.size * minPriority / totalPriority, -this.beta);

        const weights = new Float32Array(batch.length);
        for (let i = 0; i < batch.length; i++) {
            const prob = priorities[i] / totalPriority;
            const weight = Math.pow(this.tree.size * prob, -this.beta);
            weights[i] = weight / maxWeight; // Normalize
        }

        return { batch, indices, weights };
    }

    /**
     * Update priorities based on TD errors
     * @param {Array<number>} indices - Tree indices
     * @param {Array<number>} tdErrors - Absolute TD errors
     */
    updatePriorities(indices, tdErrors) {
        for (let i = 0; i < indices.length; i++) {
            const priority = Math.pow(Math.abs(tdErrors[i]) + this.epsilon, this.alpha);
            this.tree.update(indices[i], priority);
            this.maxPriority = Math.max(this.maxPriority, priority);
        }
    }

    /**
     * Get current buffer size
     */
    size() {
        return this.tree.size;
    }

    /**
     * Check if buffer has enough samples for training
     * @param {number} minSize - Minimum required samples
     */
    isReady(minSize) {
        return this.tree.size >= minSize;
    }

    /**
     * Export buffer state for saving
     */
    toJSON() {
        const experiences = [];
        for (let i = 0; i < this.tree.size; i++) {
            if (this.tree.data[i]) {
                experiences.push({
                    data: this.tree.data[i],
                    priority: this.tree.tree[i + this.capacity - 1]
                });
            }
        }
        return {
            capacity: this.capacity,
            alpha: this.alpha,
            beta: this.beta,
            maxPriority: this.maxPriority,
            experiences
        };
    }

    /**
     * Import buffer state from saved data
     */
    fromJSON(data) {
        this.capacity = data.capacity || this.capacity;
        this.alpha = data.alpha || this.alpha;
        this.beta = data.beta || this.beta;
        this.maxPriority = data.maxPriority || 1.0;

        if (data.experiences) {
            for (const exp of data.experiences) {
                const priority = exp.priority || Math.pow(this.maxPriority, this.alpha);
                this.tree.add(priority, exp.data);
            }
        }
    }

    /**
     * Clear the buffer
     */
    clear() {
        this.tree = new SumTree(this.capacity);
        this.maxPriority = 1.0;
        this.beta = 0.4;
    }

    /**
     * Get buffer statistics
     */
    getStats() {
        return {
            size: this.tree.size,
            capacity: this.capacity,
            totalPriority: this.tree.total(),
            maxPriority: this.maxPriority,
            beta: this.beta,
            fillRatio: this.tree.size / this.capacity
        };
    }
}

module.exports = PrioritizedReplayBuffer;
