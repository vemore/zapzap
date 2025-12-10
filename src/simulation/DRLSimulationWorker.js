/**
 * DRLSimulationWorker
 * Worker thread for parallel DRL training
 *
 * Workers run games using LightweightDQN (pure JS inference)
 * and collect transitions to send back to main thread for training.
 *
 * The main thread periodically syncs trained weights to workers.
 */

const { parentPort, workerData } = require('worker_threads');
const HeadlessGameEngine = require('./HeadlessGameEngine');
const BotStrategyFactory = require('../infrastructure/bot/strategies/BotStrategyFactory');
const BotStrategy = require('../infrastructure/bot/strategies/BotStrategy');
const CardAnalyzer = require('../infrastructure/bot/CardAnalyzer');
const FeatureExtractor = require('../infrastructure/bot/ml/FeatureExtractor');
const LightweightDQN = require('../infrastructure/bot/ml/LightweightDQN');
const SimulationStats = require('./SimulationStats');

// Worker state
let strategyTypes = null;
let workerId = null;
let epsilon = 0.3;
let isInitialized = false;

// Lightweight network for inference (no TensorFlow)
let network = null;
let useNetwork = false;  // Start with random, switch when weights received

// Action mappings (same as DRLPolicy)
const actionMaps = {
    handSize: [4, 5, 6, 7, 8, 9, 10],
    zapzap: [true, false],
    playType: ['optimal', 'single_high', 'multi_high', 'avoid_joker', 'use_joker_combo'],
    drawSource: ['deck', 'played']
};

/**
 * DRL Strategy for workers using LightweightDQN
 * Uses network for exploitation, random for exploration
 */
class WorkerDRLStrategy extends BotStrategy {
    constructor(options = {}) {
        super('drl');
        this.epsilon = options.epsilon || 0.3;
        this.useHardRules = options.useHardRules !== false;
        this.playerIndex = options.playerIndex || 0;
        this.currentGameTransitions = [];
        this._lastKnownScore = 0;

        // Track pending transitions BY TYPE for proper state->nextState linking
        // Each decision type has its own chain of states
        this._pendingByType = {
            handSize: null,
            zapzap: null,
            playType: null,
            drawSource: null
        };

        // Track last features by type for proper nextState
        this._lastFeaturesByType = {
            handSize: null,
            zapzap: null,
            playType: null,
            drawSource: null
        };

        // Track hand state for intermediate rewards
        this._lastHandValue = 0;
        this._lastHandSize = 0;
    }

    setPlayerIndex(index) {
        this.playerIndex = index;
    }

    /**
     * Record a transition for a specific decision type
     * Links to previous transition of SAME TYPE (not mixed types)
     * Includes intermediate rewards based on hand improvement
     */
    _recordTransition(decisionType, state, actionIdx, action, hand = null) {
        // Calculate intermediate reward based on hand improvement
        let intermediateReward = 0;
        if (hand && (decisionType === 'playType' || decisionType === 'drawSource')) {
            const currentHandValue = CardAnalyzer.calculateHandValue(hand);
            const currentHandSize = hand.length;

            // Reward for reducing hand value (normalized by typical hand value ~30-50)
            const valueReduction = (this._lastHandValue - currentHandValue) / 50;
            // Reward for reducing hand size (each card played is good)
            const sizeReduction = (this._lastHandSize - currentHandSize) / 7;

            // Intermediate reward: value reduction matters more than size
            intermediateReward = valueReduction * 0.3 + sizeReduction * 0.1;

            // Bonus for getting close to ZapZap territory
            if (currentHandValue <= 5 && this._lastHandValue > 5) {
                intermediateReward += 0.2;  // Bonus for reaching ZapZap eligibility
            }

            // Update tracking
            this._lastHandValue = currentHandValue;
            this._lastHandSize = currentHandSize;
        }

        // Finalize previous transition of same type with current state
        if (this._pendingByType[decisionType]) {
            const pending = this._pendingByType[decisionType];
            pending.nextState = [...state];
            // Add intermediate reward to previous transition
            pending.reward += intermediateReward;
            this.currentGameTransitions.push(pending);
        }

        // Create new pending transition for this type
        this._pendingByType[decisionType] = {
            decisionType,
            state: [...state],
            actionIdx,
            action,
            reward: 0,  // Will be updated with intermediate or final reward
            nextState: null,
            done: false
        };

        // Track last features for this type
        this._lastFeaturesByType[decisionType] = [...state];
    }

    selectHandSize(activePlayerCount, isGoldenScore) {
        const features = FeatureExtractor.extractHandSizeFeatures(
            activePlayerCount,
            isGoldenScore,
            this._lastKnownScore
        );
        const featureArray = FeatureExtractor.toArray(features);

        // Select action using network or random
        const actionIdx = this._selectAction('handSize', featureArray);
        const action = actionMaps.handSize[actionIdx];

        // Record transition (will be finalized with nextState later)
        this._recordTransition('handSize', featureArray, actionIdx, action);

        return Math.max(4, Math.min(isGoldenScore ? 10 : 7, action));
    }

    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);
        if (handValue > 5) return false;
        if (handValue === 0) return true;

        const features = this._getFeatures(gameState, hand);
        const featureArray = FeatureExtractor.toArray(features);

        const actionIdx = this._selectAction('zapzap', featureArray);
        const action = actionMaps.zapzap[actionIdx];

        // Record transition (will be finalized with nextState later)
        this._recordTransition('zapzap', featureArray, actionIdx, action);

        return action;
    }

    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) return null;

        // Initialize hand tracking on first play decision
        if (this._lastHandValue === 0 && this._lastHandSize === 0) {
            this._lastHandValue = CardAnalyzer.calculateHandValue(hand);
            this._lastHandSize = hand.length;
        }

        const features = this._getFeatures(gameState, hand);
        const featureArray = FeatureExtractor.toArray(features);

        const actionIdx = this._selectAction('playType', featureArray);
        const playType = actionMaps.playType[actionIdx];
        let cards = this._executePlayType(playType, hand, gameState);

        if (this.useHardRules && cards) {
            cards = this._applyHardRules(cards, hand, gameState, features);
        }

        // Calculate hand AFTER playing cards for intermediate reward
        const handAfterPlay = cards ? hand.filter(c => !cards.includes(c)) : hand;

        // Record transition with hand state for intermediate rewards
        this._recordTransition('playType', featureArray, actionIdx, playType, handAfterPlay);

        return cards;
    }

    selectDrawSource(hand, lastCardsPlayed, gameState) {
        if (!lastCardsPlayed || lastCardsPlayed.length === 0) return 'deck';

        const features = this._getFeatures(gameState, hand);
        const featureArray = FeatureExtractor.toArray(features);

        // Hard rules override (don't record transition for hard-coded decisions)
        if (this.useHardRules && gameState.isGoldenScore) {
            if (lastCardsPlayed.some(c => c >= 52)) return 'played';
        }
        if (this.useHardRules && features.shouldKeepJokers && features.discardHasJoker) {
            return 'played';
        }

        const actionIdx = this._selectAction('drawSource', featureArray);
        const action = actionMaps.drawSource[actionIdx];

        // Record transition with current hand for intermediate rewards
        this._recordTransition('drawSource', featureArray, actionIdx, action, hand);

        return action;
    }

    /**
     * Select action using epsilon-greedy with network
     */
    _selectAction(decisionType, featureArray) {
        const actionCount = actionMaps[decisionType].length;

        // Exploration
        if (Math.random() < this.epsilon) {
            return Math.floor(Math.random() * actionCount);
        }

        // Exploitation using network (if available)
        if (useNetwork && network) {
            try {
                return network.selectAction(featureArray, decisionType, 0);
            } catch (e) {
                // Fallback to random if network fails
                return Math.floor(Math.random() * actionCount);
            }
        }

        // Default: random
        return Math.floor(Math.random() * actionCount);
    }

    onGameEnd(result, playerIndex) {
        // Finalize all pending transitions by type with terminal state
        const terminalState = new Array(45).fill(0);

        for (const decisionType of Object.keys(this._pendingByType)) {
            if (this._pendingByType[decisionType]) {
                const pending = this._pendingByType[decisionType];
                pending.nextState = terminalState;
                pending.done = true;
                this.currentGameTransitions.push(pending);
                this._pendingByType[decisionType] = null;
            }
        }

        const finalRewards = this._calculateReward(result, playerIndex);

        // Update rewards for all transitions
        // ADD final reward to existing intermediate rewards (don't replace)
        const lastIndexByType = {};
        for (let i = 0; i < this.currentGameTransitions.length; i++) {
            const t = this.currentGameTransitions[i];
            lastIndexByType[t.decisionType] = i;
        }

        for (let i = 0; i < this.currentGameTransitions.length; i++) {
            const t = this.currentGameTransitions[i];
            // Keep intermediate reward, add final reward scaled down for non-terminal transitions
            const finalReward = finalRewards[t.decisionType] || finalRewards.base;
            const isTerminal = i === lastIndexByType[t.decisionType];

            if (isTerminal) {
                // Terminal transition gets full final reward
                t.reward += finalReward;
            } else {
                // Non-terminal: intermediate reward is primary, small portion of final reward
                t.reward += finalReward * 0.1;
            }

            t.done = isTerminal;
        }

        this._lastKnownScore = result.finalScores?.[playerIndex] || 0;

        // Reset tracking for next game
        for (const type of Object.keys(this._lastFeaturesByType)) {
            this._lastFeaturesByType[type] = null;
        }
        this._lastHandValue = 0;
        this._lastHandSize = 0;
    }

    _getFeatures(gameState, hand) {
        return FeatureExtractor.extract(gameState, this.playerIndex, hand);
    }

    _calculateReward(gameResult, playerIndex) {
        const finalScores = gameResult.finalScores || {};
        const myScore = finalScores[playerIndex] || 0;
        const playerCount = Object.keys(finalScores).length;

        const allScores = Object.entries(finalScores)
            .map(([idx, score]) => ({ idx: parseInt(idx), score }))
            .sort((a, b) => a.score - b.score);

        let myRank = allScores.findIndex(s => s.idx === playerIndex);
        const minScore = allScores[0]?.score || 0;
        const maxScore = allScores[allScores.length - 1]?.score || 0;
        const avgScore = Object.values(finalScores).reduce((a, b) => a + b, 0) / playerCount;

        // Strong rank-based reward (primary signal)
        // Win = +1, 2nd = +0.2, 3rd = -0.5, 4th = -1
        let rankReward;
        switch (myRank) {
            case 0: rankReward = 1.0; break;
            case 1: rankReward = 0.2; break;
            case 2: rankReward = -0.5; break;
            case 3: rankReward = -1.0; break;
            default: rankReward = -1.0;
        }

        // Score-relative reward (how good was our score relative to others)
        // Positive if below average, negative if above
        const scoreRelative = maxScore > minScore
            ? (avgScore - myScore) / (maxScore - minScore)
            : 0;

        // Dominance reward (how much did we beat the worst player by)
        const dominance = maxScore > 0
            ? (maxScore - myScore) / maxScore
            : 0;

        // Combined base reward with stronger differentiation
        const baseReward = rankReward * 0.7 + scoreRelative * 0.2 + dominance * 0.1;

        // Decision-type specific rewards with meaningful differentiation
        return {
            base: baseReward,

            // HandSize: small impact, mainly matters for risk management
            // Good handSize choice = lower variance in outcomes
            handSize: baseReward * 0.4,

            // ZapZap: CRITICAL decision - calling at wrong time is devastating
            // Extra reward for correct ZapZap timing (win or counteracted)
            zapzap: myRank === 0 ? baseReward * 2.0 : baseReward * 1.5,

            // PlayType: core gameplay - how efficiently we reduce hand value
            playType: baseReward * 1.0,

            // DrawSource: situational importance - matters for joker collection
            drawSource: baseReward * 0.6
        };
    }

    _executePlayType(playType, hand, gameState) {
        const validPlays = CardAnalyzer.findAllValidPlays(hand);
        if (validPlays.length === 0) return this._findHighestSingleCard(hand);

        const evaluatedPlays = validPlays.map(play => ({
            cards: play,
            remainingValue: CardAnalyzer.calculateHandValue(hand.filter(c => !play.includes(c))),
            playValue: CardAnalyzer.calculateHandValue(play),
            playSize: play.length,
            hasJoker: play.some(c => c >= 52)
        }));

        switch (playType) {
            case 'single_high':
                const singles = evaluatedPlays.filter(p => p.playSize === 1);
                if (singles.length > 0) {
                    singles.sort((a, b) => b.playValue - a.playValue);
                    return singles[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'multi_high':
                const multis = evaluatedPlays.filter(p => p.playSize > 1);
                if (multis.length > 0) {
                    multis.sort((a, b) => a.remainingValue - b.remainingValue);
                    return multis[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'avoid_joker':
                const noJoker = evaluatedPlays.filter(p => !p.hasJoker);
                if (noJoker.length > 0) {
                    noJoker.sort((a, b) => a.remainingValue - b.remainingValue);
                    return noJoker[0].cards;
                }
                return evaluatedPlays[0].cards;

            case 'use_joker_combo':
                const jokerCombos = evaluatedPlays.filter(p => p.hasJoker && p.playSize > 1);
                if (jokerCombos.length > 0) {
                    jokerCombos.sort((a, b) => a.remainingValue - b.remainingValue);
                    return jokerCombos[0].cards;
                }
                return evaluatedPlays[0].cards;

            case 'optimal':
            default:
                evaluatedPlays.sort((a, b) => a.remainingValue - b.remainingValue);
                return evaluatedPlays[0].cards;
        }
    }

    _applyHardRules(play, hand, gameState, features) {
        if (gameState.isGoldenScore) {
            const playHasJoker = play.some(c => c >= 52);
            if (playHasJoker) {
                const validPlays = CardAnalyzer.findAllValidPlays(hand);
                const jokerFree = validPlays.filter(p => !p.some(c => c >= 52));
                if (jokerFree.length > 0) {
                    jokerFree.sort((a, b) => {
                        const ra = CardAnalyzer.calculateHandValue(hand.filter(c => !a.includes(c)));
                        const rb = CardAnalyzer.calculateHandValue(hand.filter(c => !b.includes(c)));
                        return ra - rb;
                    });
                    return jokerFree[0];
                }
            }
        }
        return play;
    }

    _findHighestSingleCard(hand) {
        let highest = hand[0];
        let highestPoints = CardAnalyzer.getCardPoints(hand[0]);
        for (const c of hand) {
            const points = CardAnalyzer.getCardPoints(c);
            if (points > highestPoints) {
                highestPoints = points;
                highest = c;
            }
        }
        return [highest];
    }

    getName() { return 'Worker DRL Bot'; }
}

/**
 * Initialize worker
 */
function initialize(data) {
    workerId = data.workerId;
    strategyTypes = data.strategyTypes;
    epsilon = data.epsilon || 0.3;

    // Initialize lightweight network
    network = new LightweightDQN({ inputDim: 45 });

    // If weights provided, load them
    if (data.weights) {
        network.setWeights(data.weights);
        useNetwork = true;
    }

    isInitialized = true;
    parentPort.postMessage({ type: 'initialized', workerId });
}

/**
 * Run a batch of games
 */
function runBatch(batchSize) {
    if (!isInitialized) {
        parentPort.postMessage({ type: 'error', error: 'Worker not initialized' });
        return;
    }

    const stats = new SimulationStats();
    const allTransitions = [];

    for (let i = 0; i < batchSize; i++) {
        try {
            const strategies = strategyTypes.map((type, index) => {
                if (type === 'drl') {
                    const s = new WorkerDRLStrategy({ epsilon, playerIndex: index });
                    s.setPlayerIndex(index);
                    return s;
                }
                return BotStrategyFactory.create(type);
            });

            const engine = new HeadlessGameEngine(strategies);
            const result = engine.runGame();

            stats.recordGame(result, strategyTypes);

            // Collect transitions from DRL strategies
            strategies.forEach((s, index) => {
                if (s instanceof WorkerDRLStrategy) {
                    s.onGameEnd(result, index);
                    for (const t of s.currentGameTransitions) {
                        allTransitions.push({ ...t, playerIndex: index });
                    }
                }
            });
        } catch (error) {
            console.error(`[Worker ${workerId}] Game error:`, error.message);
        }
    }

    parentPort.postMessage({
        type: 'batchComplete',
        workerId,
        stats: stats.toJSON(),
        transitions: allTransitions,
        gamesPlayed: batchSize
    });
}

/**
 * Update weights and epsilon from main thread
 */
function updateWeights(data) {
    if (data.epsilon !== undefined) {
        epsilon = data.epsilon;
    }

    if (data.weights) {
        if (!network) {
            network = new LightweightDQN({ inputDim: 45 });
        }
        network.setWeights(data.weights);
        useNetwork = true;
    }

    parentPort.postMessage({ type: 'weightsUpdated', workerId });
}

// Message handler
parentPort.on('message', (msg) => {
    switch (msg.type) {
        case 'init':
            initialize(msg.data);
            break;
        case 'runBatch':
            runBatch(msg.batchSize);
            break;
        case 'updateWeights':
            updateWeights(msg);
            break;
        case 'shutdown':
            parentPort.postMessage({ type: 'shutdown', workerId });
            process.exit(0);
            break;
        default:
            console.warn(`[Worker ${workerId}] Unknown message type:`, msg.type);
    }
});

process.on('uncaughtException', (error) => {
    console.error(`[Worker ${workerId}] Uncaught exception:`, error);
    parentPort.postMessage({ type: 'error', workerId, error: error.message });
});

process.on('unhandledRejection', (reason) => {
    console.error(`[Worker ${workerId}] Unhandled rejection:`, reason);
    parentPort.postMessage({ type: 'error', workerId, error: String(reason) });
});
