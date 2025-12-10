/**
 * ImitationLearner
 * Pre-trains DRL policy by learning from "expert" HardVince bot games
 *
 * Strategy:
 * 1. Run games with HardVince bots (expert demonstrations)
 * 2. Extract features at each decision point
 * 3. Record the expert's action choices as positive examples
 * 4. Store transitions with positive rewards in DRL's replay buffer
 *
 * This gives the DRL network a "warm start" by learning from good play
 * before exploring on its own.
 */

const HeadlessGameEngine = require('./HeadlessGameEngine');
const BotStrategyFactory = require('../infrastructure/bot/strategies/BotStrategyFactory');
const BotStrategy = require('../infrastructure/bot/strategies/BotStrategy');
const CardAnalyzer = require('../infrastructure/bot/CardAnalyzer');
const FeatureExtractor = require('../infrastructure/bot/ml/FeatureExtractor');
const SimulationStats = require('./SimulationStats');

// Action mappings (same as DRLPolicy)
const actionMaps = {
    handSize: [4, 5, 6, 7, 8, 9, 10],
    zapzap: [true, false],
    playType: ['optimal', 'single_high', 'multi_high', 'avoid_joker', 'use_joker_combo'],
    drawSource: ['deck', 'played']
};

/**
 * Wrapper strategy that observes an expert bot and records transitions
 */
class ExpertObserverStrategy extends BotStrategy {
    constructor(expertStrategy, playerIndex) {
        super('expert_observer');
        this.expertStrategy = expertStrategy;
        this.playerIndex = playerIndex;
        this.transitions = [];

        // Track pending transitions by type
        this._pendingByType = {
            handSize: null,
            zapzap: null,
            playType: null,
            drawSource: null
        };

        // Track hand state for rewards
        this._lastHandValue = 0;
        this._lastHandSize = 0;
        this._lastKnownScore = 0;
    }

    setPlayerIndex(index) {
        this.playerIndex = index;
        if (this.expertStrategy.setPlayerIndex) {
            this.expertStrategy.setPlayerIndex(index);
        }
    }

    /**
     * Map expert's playType decision to action index
     */
    _classifyPlayType(selectedCards, hand, gameState) {
        if (!selectedCards || selectedCards.length === 0) return 0; // optimal

        const hasJoker = selectedCards.some(c => c >= 52);
        const isMultiCard = selectedCards.length > 1;
        const isSingleCard = selectedCards.length === 1;

        // Check if it's a joker combo (multi-card with joker)
        if (hasJoker && isMultiCard) {
            return 4; // use_joker_combo
        }

        // Check if avoiding joker when jokers are available
        const handHasJoker = hand.some(c => c >= 52);
        if (handHasJoker && !hasJoker) {
            return 3; // avoid_joker
        }

        // Check if playing highest single card
        if (isSingleCard) {
            const cardPoints = CardAnalyzer.getCardPoints(selectedCards[0]);
            const handPoints = hand.map(c => CardAnalyzer.getCardPoints(c));
            const maxPoints = Math.max(...handPoints);

            if (cardPoints === maxPoints && cardPoints >= 10) {
                return 1; // single_high
            }
        }

        // Check if multi-card play that maximizes value reduction
        if (isMultiCard) {
            return 2; // multi_high
        }

        return 0; // optimal (default)
    }

    /**
     * Record a transition with expert's action
     */
    _recordTransition(decisionType, state, actionIdx, action, hand = null) {
        // Calculate intermediate reward based on hand improvement
        let intermediateReward = 0;
        if (hand && (decisionType === 'playType' || decisionType === 'drawSource')) {
            const currentHandValue = CardAnalyzer.calculateHandValue(hand);
            const currentHandSize = hand.length;

            // Reward for reducing hand value
            const valueReduction = (this._lastHandValue - currentHandValue) / 50;
            // Reward for reducing hand size
            const sizeReduction = (this._lastHandSize - currentHandSize) / 7;

            intermediateReward = valueReduction * 0.3 + sizeReduction * 0.1;

            // Bonus for reaching ZapZap territory
            if (currentHandValue <= 5 && this._lastHandValue > 5) {
                intermediateReward += 0.2;
            }

            this._lastHandValue = currentHandValue;
            this._lastHandSize = currentHandSize;
        }

        // Finalize previous transition of same type
        if (this._pendingByType[decisionType]) {
            const pending = this._pendingByType[decisionType];
            pending.nextState = [...state];
            pending.reward += intermediateReward;
            this.transitions.push(pending);
        }

        // Create new pending transition - expert actions get base positive reward
        this._pendingByType[decisionType] = {
            decisionType,
            state: [...state],
            actionIdx,
            action,
            reward: 0.1,  // Small positive base reward for expert actions
            nextState: null,
            done: false
        };
    }

    selectHandSize(activePlayerCount, isGoldenScore) {
        const action = this.expertStrategy.selectHandSize(activePlayerCount, isGoldenScore);

        // Extract features
        const features = FeatureExtractor.extractHandSizeFeatures(
            activePlayerCount,
            isGoldenScore,
            this._lastKnownScore
        );
        const featureArray = FeatureExtractor.toArray(features);

        // Map action to index
        const actionIdx = actionMaps.handSize.indexOf(action);

        this._recordTransition('handSize', featureArray, actionIdx, action);

        return action;
    }

    shouldZapZap(hand, gameState) {
        const action = this.expertStrategy.shouldZapZap(hand, gameState);

        // Only record if we actually have a choice (hand value <= 5)
        const handValue = CardAnalyzer.calculateHandValue(hand);
        if (handValue <= 5) {
            const features = FeatureExtractor.extract(gameState, this.playerIndex, hand);
            const featureArray = FeatureExtractor.toArray(features);

            const actionIdx = action ? 0 : 1;  // true=0, false=1

            this._recordTransition('zapzap', featureArray, actionIdx, action);
        }

        return action;
    }

    selectPlay(hand, gameState) {
        // Initialize hand tracking
        if (this._lastHandValue === 0 && this._lastHandSize === 0) {
            this._lastHandValue = CardAnalyzer.calculateHandValue(hand);
            this._lastHandSize = hand.length;
        }

        const selectedCards = this.expertStrategy.selectPlay(hand, gameState);

        if (selectedCards && selectedCards.length > 0) {
            const features = FeatureExtractor.extract(gameState, this.playerIndex, hand);
            const featureArray = FeatureExtractor.toArray(features);

            // Classify what type of play this is
            const actionIdx = this._classifyPlayType(selectedCards, hand, gameState);
            const action = actionMaps.playType[actionIdx];

            // Calculate hand after play
            const handAfterPlay = hand.filter(c => !selectedCards.includes(c));

            this._recordTransition('playType', featureArray, actionIdx, action, handAfterPlay);
        }

        return selectedCards;
    }

    selectDrawSource(hand, lastCardsPlayed, gameState) {
        const action = this.expertStrategy.selectDrawSource(hand, lastCardsPlayed, gameState);

        if (lastCardsPlayed && lastCardsPlayed.length > 0) {
            const features = FeatureExtractor.extract(gameState, this.playerIndex, hand);
            const featureArray = FeatureExtractor.toArray(features);

            const actionIdx = action === 'deck' ? 0 : 1;

            this._recordTransition('drawSource', featureArray, actionIdx, action, hand);
        }

        return action;
    }

    onGameEnd(result, playerIndex) {
        // Finalize all pending transitions
        const terminalState = new Array(45).fill(0);

        for (const decisionType of Object.keys(this._pendingByType)) {
            if (this._pendingByType[decisionType]) {
                const pending = this._pendingByType[decisionType];
                pending.nextState = terminalState;
                pending.done = true;
                this.transitions.push(pending);
                this._pendingByType[decisionType] = null;
            }
        }

        // Calculate final rewards based on game result
        const finalScores = result.finalScores || {};
        const myScore = finalScores[playerIndex] || 0;
        const playerCount = Object.keys(finalScores).length;

        const allScores = Object.entries(finalScores)
            .map(([idx, score]) => ({ idx: parseInt(idx), score }))
            .sort((a, b) => a.score - b.score);

        const myRank = allScores.findIndex(s => s.idx === playerIndex);

        // Expert gets stronger rewards when winning
        let rankBonus;
        switch (myRank) {
            case 0: rankBonus = 1.0; break;   // Win = strong positive
            case 1: rankBonus = 0.3; break;   // 2nd = moderate positive
            case 2: rankBonus = 0.0; break;   // 3rd = neutral
            case 3: rankBonus = -0.2; break;  // 4th = slight negative
            default: rankBonus = -0.3;
        }

        // Apply rewards to all transitions
        // Expert transitions get positive rewards (especially for wins)
        const lastIndexByType = {};
        for (let i = 0; i < this.transitions.length; i++) {
            lastIndexByType[this.transitions[i].decisionType] = i;
        }

        for (let i = 0; i < this.transitions.length; i++) {
            const t = this.transitions[i];
            const isTerminal = i === lastIndexByType[t.decisionType];

            // Add rank-based reward
            if (isTerminal) {
                t.reward += rankBonus;
            } else {
                t.reward += rankBonus * 0.1;
            }

            t.done = isTerminal;
        }

        this._lastKnownScore = myScore;

        // Reset for next game
        this._lastHandValue = 0;
        this._lastHandSize = 0;
    }

    getTransitions() {
        return this.transitions;
    }

    clearTransitions() {
        this.transitions = [];
        for (const type of Object.keys(this._pendingByType)) {
            this._pendingByType[type] = null;
        }
    }

    getName() {
        return `Expert Observer (${this.expertStrategy.getName()})`;
    }
}

/**
 * Imitation Learner - collects expert demonstrations
 */
class ImitationLearner {
    constructor(options = {}) {
        this.expertType = options.expertType || 'hard_vince';
        this.numExperts = options.numExperts || 4;  // All players are experts
        this.onProgress = options.onProgress || (() => {});
    }

    /**
     * Collect expert demonstrations by running games
     * @param {number} numGames - Number of games to run
     * @returns {Object} { transitions, stats }
     */
    collectDemonstrations(numGames) {
        console.log(`\nCollecting ${numGames} expert demonstrations from ${this.expertType}...`);

        const allTransitions = [];
        const stats = new SimulationStats();
        const strategyTypes = Array(this.numExperts).fill(this.expertType);

        for (let i = 0; i < numGames; i++) {
            try {
                // Create expert strategies wrapped in observers
                const observers = [];
                for (let j = 0; j < this.numExperts; j++) {
                    const expert = BotStrategyFactory.create(this.expertType);
                    const observer = new ExpertObserverStrategy(expert, j);
                    observers.push(observer);
                }

                // Run game
                const engine = new HeadlessGameEngine(observers);
                const result = engine.runGame();

                // Record stats
                stats.recordGame(result, strategyTypes);

                // Collect transitions from all observers
                observers.forEach((obs, idx) => {
                    obs.onGameEnd(result, idx);
                    const transitions = obs.getTransitions();

                    // Only collect transitions from winning players
                    // This biases the dataset toward winning behaviors
                    const myRank = this._getRank(result, idx);
                    if (myRank <= 1) {  // Top 2 players
                        for (const t of transitions) {
                            allTransitions.push({
                                ...t,
                                playerIndex: idx,
                                isWinner: myRank === 0
                            });
                        }
                    }
                });

                // Progress callback
                if ((i + 1) % 100 === 0) {
                    this.onProgress({
                        gamesCompleted: i + 1,
                        totalGames: numGames,
                        transitionsCollected: allTransitions.length
                    });
                    console.log(`[Imitation] ${i + 1}/${numGames} games, ${allTransitions.length} transitions`);
                }

            } catch (error) {
                console.error(`[Imitation] Game ${i} error:`, error.message);
            }
        }

        console.log(`\nCollected ${allTransitions.length} expert transitions from ${numGames} games`);

        // Analyze transition distribution
        this._analyzeTransitions(allTransitions);

        return {
            transitions: allTransitions,
            stats: stats.getSummary()
        };
    }

    _getRank(result, playerIndex) {
        const finalScores = result.finalScores || {};
        const allScores = Object.entries(finalScores)
            .map(([idx, score]) => ({ idx: parseInt(idx), score }))
            .sort((a, b) => a.score - b.score);

        return allScores.findIndex(s => s.idx === playerIndex);
    }

    _analyzeTransitions(transitions) {
        const byType = {};
        const byAction = {};
        let positiveReward = 0;
        let negativeReward = 0;

        for (const t of transitions) {
            byType[t.decisionType] = (byType[t.decisionType] || 0) + 1;

            const actionKey = `${t.decisionType}:${t.action}`;
            byAction[actionKey] = (byAction[actionKey] || 0) + 1;

            if (t.reward > 0) positiveReward++;
            else negativeReward++;
        }

        console.log('\nTransition analysis:');
        console.log('By decision type:', byType);
        console.log(`Rewards: ${positiveReward} positive, ${negativeReward} negative`);

        console.log('\nTop actions by frequency:');
        const sortedActions = Object.entries(byAction)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 10);
        for (const [action, count] of sortedActions) {
            console.log(`  ${action}: ${count}`);
        }
    }

    /**
     * Pre-fill a DRL policy's replay buffer with expert transitions
     * Only fills a portion of the buffer to leave room for new experiences
     * @param {DRLPolicy} policy - The DRL policy to pre-train
     * @param {Array} transitions - Expert transitions
     * @param {number} maxFillRatio - Max proportion of buffer to fill (default: 0.3)
     */
    fillReplayBuffer(policy, transitions, maxFillRatio = 0.3) {
        const bufferCapacity = policy.config.bufferSize || 100000;
        const maxFill = Math.floor(bufferCapacity * maxFillRatio);

        // Sort transitions by reward (prefer high-reward examples)
        const sortedTransitions = [...transitions].sort((a, b) => b.reward - a.reward);

        // Take only the best transitions up to maxFill
        const selectedTransitions = sortedTransitions.slice(0, maxFill);

        console.log(`\nFilling replay buffer with ${selectedTransitions.length} expert transitions (top ${(maxFillRatio * 100).toFixed(0)}% of buffer)...`);
        console.log(`(Selected from ${transitions.length} total, keeping highest-reward examples)`);

        let added = 0;
        for (const t of selectedTransitions) {
            // Boost rewards for expert demonstrations
            // Winner transitions get extra boost
            let boostedReward = t.reward;
            if (t.isWinner) {
                boostedReward += 0.2;  // Extra boost for winning plays
            }

            policy.storeTransition({
                state: t.state,
                action: t.action,
                reward: boostedReward,
                nextState: t.nextState,
                done: t.done,
                decisionType: t.decisionType
            });
            added++;
        }

        console.log(`Added ${added} transitions to replay buffer`);
        console.log(`Buffer size: ${policy.replayBuffer.size()} / ${bufferCapacity}`);
    }

    /**
     * Pre-train the policy on expert demonstrations
     * Uses supervised learning approach: expert action = correct action
     * @param {DRLPolicy} policy - The DRL policy to pre-train
     * @param {number} numIterations - Training iterations
     * @param {number} postPretrainEpsilon - Epsilon to set after pre-training (default: 0.15)
     */
    async preTrain(policy, transitions, numIterations = 100, postPretrainEpsilon = 0.15) {
        console.log(`\nPre-training on ${transitions.length} expert transitions for ${numIterations} iterations...`);

        // First fill the buffer
        this.fillReplayBuffer(policy, transitions);

        // Save original epsilon settings
        const originalEpsilon = policy.epsilon;
        const originalMinEpsilon = policy.config.minEpsilon;

        // Disable epsilon decay during pre-training by setting min to current
        policy.config.minEpsilon = originalEpsilon;

        // Then train (epsilon won't decay because min = current)
        let totalTdError = 0;
        for (let i = 0; i < numIterations; i++) {
            const tdError = await policy.train();
            totalTdError += tdError;

            if ((i + 1) % 20 === 0) {
                console.log(`[Pre-train ${i + 1}/${numIterations}] Avg TD Error: ${(totalTdError / (i + 1)).toFixed(4)}`);
            }
        }

        // Restore epsilon settings and set exploration rate for main training
        policy.config.minEpsilon = originalMinEpsilon;
        policy.epsilon = postPretrainEpsilon;

        console.log(`\nPre-training complete. Final avg TD error: ${(totalTdError / numIterations).toFixed(4)}`);
        console.log(`Epsilon set to ${postPretrainEpsilon} for main training (will decay to ${originalMinEpsilon})`);
    }
}

module.exports = ImitationLearner;
