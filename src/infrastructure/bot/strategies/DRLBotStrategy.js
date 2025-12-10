/**
 * DRLBotStrategy
 * Deep Reinforcement Learning powered bot strategy using Double DQN
 * with Prioritized Experience Replay
 *
 * This strategy replaces the Multi-Armed Bandit approach with a neural network
 * that can generalize across similar states and learn more complex patterns.
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');
const DRLPolicy = require('../ml/DRLPolicy');
const FeatureExtractor = require('../ml/FeatureExtractor');

class DRLBotStrategy extends BotStrategy {
    /**
     * @param {Object} options - Strategy options
     * @param {DRLPolicy} options.policy - Shared DRL policy instance
     * @param {boolean} options.useHardRules - Enable HardBot-inspired hard rules (default: true)
     * @param {boolean} options.training - Whether in training mode (default: true)
     * @param {boolean} options.hybrid - Enable hybrid mode where DRL can override heuristics (default: false)
     * @param {number} options.hybridOverrideProb - Probability of DRL overriding heuristics in hybrid mode (default: 0.3)
     */
    constructor(options = {}) {
        super('drl');

        // Use shared policy or create new one
        this.policy = options.policy || new DRLPolicy({
            inputDim: 45,
            epsilon: options.epsilon || 0.3,
            minEpsilon: options.minEpsilon || 0.02,
            epsilonDecay: options.epsilonDecay || 0.9999
        });

        // Enable hard rules for critical situations (HardBot-inspired)
        this.useHardRules = options.useHardRules !== false;

        // Hybrid mode: use heuristics as base but let DRL override sometimes
        this.hybrid = options.hybrid || false;
        this.hybridOverrideProb = options.hybridOverrideProb || 0.3;

        // Training mode
        this.training = options.training !== false;

        // Track transitions for experience replay
        this.currentGameTransitions = [];
        this.currentState = null;
        this.lastDecision = null;

        // Track game statistics
        this._lastKnownScore = 0;
        this.playerIndex = null;

        // Feature cache
        this._featureCache = null;
        this._featureCacheKey = null;
    }

    /**
     * Set the player index for this strategy instance
     * @param {number} index
     */
    setPlayerIndex(index) {
        this.playerIndex = index;
    }

    /**
     * Select hand size at the start of a round
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        // HARD RULE: Use HardBot's proven strategy - fewer cards for faster ZapZap
        // This is the main advantage of the hard bot (4-5 cards vs 6-7)
        if (this.useHardRules) {
            if (isGoldenScore) {
                // Golden Score: prefer 4-6 cards
                return 4 + Math.floor(Math.random() * 3);
            }
            // Normal game: prefer 4-5 cards (minimum or near minimum)
            return 4 + Math.floor(Math.random() * 2);
        }

        const features = FeatureExtractor.extractHandSizeFeatures(
            activePlayerCount,
            isGoldenScore,
            this._lastKnownScore || 0
        );

        const featureArray = this._featuresToArray(features);
        let handSize = this.policy.selectAction('handSize', featureArray);

        // Validate bounds
        const minHandSize = 4;
        const maxHandSize = isGoldenScore ? 10 : 7;
        handSize = Math.max(minHandSize, Math.min(maxHandSize, handSize));

        // Record for training
        if (this.training) {
            this.lastDecision = {
                type: 'handSize',
                state: featureArray,
                action: handSize
            };
        }

        return handSize;
    }

    /**
     * Decide whether to call ZapZap
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Cannot ZapZap if hand > 5
        if (handValue > 5) {
            return false;
        }

        // Always ZapZap if hand value is 0 (guaranteed win)
        if (handValue === 0) {
            if (this.training) {
                this._recordTransition('zapzap', null, true, 1.0);
            }
            return true;
        }

        // HARD RULE: Use HardBot's proven ZapZap strategy
        // Very confident at value <= 2, then increasingly aggressive based on round
        if (this.useHardRules) {
            if (handValue <= 2) {
                return true;
            }

            const roundNumber = gameState.roundNumber || 1;
            if (roundNumber <= 2) {
                return handValue <= 2;
            } else if (roundNumber <= 4) {
                return handValue <= 3;
            } else {
                return handValue <= 4;
            }
        }

        const features = this._getFeatures(gameState, hand);
        const featureArray = this._featuresToArray(features);
        const shouldCall = this.policy.selectAction('zapzap', featureArray);

        // Record for training
        if (this.training) {
            this.lastDecision = {
                type: 'zapzap',
                state: featureArray,
                action: shouldCall
            };
        }

        return shouldCall;
    }

    /**
     * Select cards to play
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // HARD RULE: Use HardBot's proven play selection strategy
        // Enhanced with Golden Score Joker Strategy from HardVince
        if (this.useHardRules) {
            const validPlays = CardAnalyzer.findAllValidPlays(hand);

            if (validPlays.length === 0) {
                return null;
            }

            const isGoldenScore = gameState.isGoldenScore || false;
            const minOpponentCards = this._getMinOpponentHandSize(gameState);

            // Evaluate each play by resulting hand value (HardBot base)
            const evaluatedPlays = validPlays.map(play => {
                const remainingHand = hand.filter(cardId => !play.includes(cardId));
                const remainingValue = CardAnalyzer.calculateHandValue(remainingHand);
                const playValue = CardAnalyzer.calculateHandValue(play);
                const playSize = play.length;

                // Check if play contains jokers
                const hasJokerInPlay = play.some(cardId => cardId >= 52);

                // Base score: prioritize plays that leave lowest hand value
                let score = -remainingValue + (playSize * 0.5);

                // GOLDEN SCORE JOKER STRATEGY (from HardVince):
                // In Golden Score, NEVER play Jokers - hoard them to deny to opponent
                if (hasJokerInPlay && isGoldenScore) {
                    score -= 500; // Massive penalty - effectively blocks joker plays
                }

                // JOKER MANAGEMENT (from HardVince):
                // If opponents have many cards, keep jokers for sequences
                // If opponents close to zapzap, release jokers
                if (hasJokerInPlay && !isGoldenScore) {
                    if (minOpponentCards > 3) {
                        // Opponents have many cards - slightly penalize joker plays
                        score -= 20;
                    } else {
                        // Opponents close to zapzap - bonus for releasing jokers
                        score += 30;
                    }
                }

                return {
                    cards: play,
                    remainingValue,
                    playValue,
                    playSize,
                    hasJokerInPlay,
                    score
                };
            });

            // Sort by score descending (best plays first)
            evaluatedPlays.sort((a, b) => b.score - a.score);

            return evaluatedPlays[0].cards;
        }

        const features = this._getFeatures(gameState, hand);
        const featureArray = this._featuresToArray(features);

        // Use network for strategy selection
        const playType = this.policy.selectAction('playType', featureArray);

        // Convert play type to actual cards
        let cards = this._executePlayType(playType, hand, gameState);

        // Apply hard rules as post-selection safety nets
        if (cards) {
            cards = this._applyHardRules(cards, hand, gameState, features);
        }

        // Record for training
        if (this.training) {
            this.lastDecision = {
                type: 'playType',
                state: featureArray,
                action: playType
            };
        }

        return cards;
    }

    /**
     * Select draw source
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string} 'deck' or 'played'
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        // Can't draw from played if empty
        if (!lastCardsPlayed || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        // HARD RULE: Use HardBot's proven draw strategy
        // Enhanced with Golden Score Joker Pickup from HardVince
        if (this.useHardRules) {
            const isGoldenScore = gameState.isGoldenScore || false;
            const minOpponentCards = this._getMinOpponentHandSize(gameState);

            // Check for jokers in discard
            const jokersInDiscard = lastCardsPlayed.filter(cardId => cardId >= 52);

            // GOLDEN SCORE JOKER PICKUP (from HardVince):
            // In Golden Score, ALWAYS pick up Jokers - hoard them!
            if (jokersInDiscard.length > 0 && isGoldenScore) {
                this._clearCache();
                return 'played';
            }

            // PRIORITY JOKER PICKUP (from HardVince):
            // If opponents have many cards, pick up jokers
            if (jokersInDiscard.length > 0 && minOpponentCards > 3) {
                this._clearCache();
                return 'played';
            }

            // Evaluate each discard card's value
            let bestDiscardCard = null;
            let bestImprovement = 0;

            for (const discardCard of lastCardsPlayed) {
                const improvement = this._evaluateCardValueForDraw(discardCard, hand);

                if (improvement > bestImprovement) {
                    bestImprovement = improvement;
                    bestDiscardCard = discardCard;
                }
            }

            // If any discard card provides significant improvement, take it
            if (bestImprovement > 5) {
                this._clearCache();
                return 'played';
            }

            // Default to deck
            this._clearCache();
            return 'deck';
        }

        const features = this._getFeatures(gameState, hand);
        const featureArray = this._featuresToArray(features);

        // Use network for normal decision
        const source = this.policy.selectAction('drawSource', featureArray);

        // Record for training
        if (this.training) {
            this.lastDecision = {
                type: 'drawSource',
                state: featureArray,
                action: source
            };
        }

        this._clearCache();
        return source;
    }

    /**
     * Get minimum hand size among opponents
     */
    _getMinOpponentHandSize(gameState) {
        const hands = gameState.hands || {};
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        const currentTurn = gameState.currentTurn;
        let minSize = Infinity;

        for (const [indexStr, hand] of Object.entries(hands)) {
            const playerIndex = parseInt(indexStr, 10);
            if (playerIndex !== currentTurn && !eliminatedPlayers.includes(playerIndex)) {
                if (Array.isArray(hand)) {
                    minSize = Math.min(minSize, hand.length);
                }
            }
        }

        return minSize === Infinity ? 0 : minSize;
    }

    /**
     * Evaluate how valuable a card would be to add to hand (HardBot style)
     */
    _evaluateCardValueForDraw(cardId, hand) {
        const testHand = [...hand, cardId];

        // Count how many new multi-card combinations this creates
        const originalPlays = CardAnalyzer.findAllValidPlays(hand);
        const newPlays = CardAnalyzer.findAllValidPlays(testHand);

        const originalMultiCardPlays = originalPlays.filter(p => p.length > 1).length;
        const newMultiCardPlays = newPlays.filter(p => p.length > 1 && p.includes(cardId)).length;

        const combinationBonus = (newMultiCardPlays - originalMultiCardPlays) * 10;

        // Prefer low-value cards (helps with zapzap)
        const cardPoints = CardAnalyzer.getCardPoints(cardId);
        const lowValueBonus = (10 - cardPoints);

        // Prefer cards that complete sequences or sets
        const rank = CardAnalyzer.getRank(cardId);
        const sameRankCount = hand.filter(id =>
            !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === rank
        ).length;

        const setBonus = sameRankCount >= 1 ? sameRankCount * 5 : 0;

        return combinationBonus + lowValueBonus + setBonus;
    }

    /**
     * Called when a turn completes - provides intermediate reward signal
     * @param {Object} turnResult - Result of the turn
     * @param {Array<number>} newHand - Hand after turn
     */
    onTurnComplete(turnResult, newHand) {
        if (!this.training || !this.lastDecision) return;

        // Calculate intermediate reward based on hand improvement
        const handValue = CardAnalyzer.calculateHandValue(newHand);
        const normalizedHandValue = Math.min(handValue / 100, 1);

        // Small negative reward proportional to hand value (lower is better)
        const intermediateReward = -normalizedHandValue * 0.1;

        // Get next state
        const nextState = this._getNextState(newHand, turnResult.gameState);

        // Record transition
        this._recordTransition(
            this.lastDecision.type,
            this.lastDecision.state,
            this.lastDecision.action,
            intermediateReward,
            nextState,
            false
        );

        this.lastDecision = null;
    }

    /**
     * Called at end of game to finalize training
     * @param {Object} gameResult - Result of the game
     * @param {number} playerIndex - This bot's player index
     */
    onGameEnd(gameResult, playerIndex) {
        if (!this.training) return;

        // Calculate final rewards
        const rewards = this._calculateReward(gameResult, playerIndex);

        // Finalize any pending decision as terminal
        if (this.lastDecision) {
            const reward = rewards[this.lastDecision.type] || rewards.base;
            this._recordTransition(
                this.lastDecision.type,
                this.lastDecision.state,
                this.lastDecision.action,
                reward,
                null, // No next state for terminal
                true  // Done
            );
        }

        // Update all transitions with final game outcome as additional reward
        this._finalizeGameTransitions(rewards);

        // Store transitions in replay buffer
        for (const transition of this.currentGameTransitions) {
            this.policy.storeTransition(transition);
        }

        // Store last known score for next game
        this._lastKnownScore = gameResult.finalScores?.[playerIndex] || 0;

        // Reset for next game
        this.currentGameTransitions = [];
        this.lastDecision = null;
        this._clearCache();
    }

    /**
     * Record a transition for training
     */
    _recordTransition(type, state, action, reward, nextState = null, done = false) {
        if (!state) return;

        this.currentGameTransitions.push({
            decisionType: type,
            state: state,
            action: action,
            reward: reward,
            nextState: nextState || state, // Use same state if no next state
            done: done
        });
    }

    /**
     * Finalize game transitions with outcome bonus
     */
    _finalizeGameTransitions(rewards) {
        // Add outcome bonus to all transitions (discounted by recency)
        const gamma = 0.99;
        let discount = 1.0;

        for (let i = this.currentGameTransitions.length - 1; i >= 0; i--) {
            const transition = this.currentGameTransitions[i];
            const outcomeBonus = (rewards[transition.decisionType] || rewards.base) * discount;
            transition.reward += outcomeBonus;
            discount *= gamma;
        }
    }

    /**
     * Get next state features
     */
    _getNextState(hand, gameState) {
        if (!gameState) return null;
        const features = FeatureExtractor.extract(gameState, this.playerIndex || 0, hand);
        return this._featuresToArray(features);
    }

    /**
     * Calculate rewards from game result
     */
    _calculateReward(gameResult, playerIndex) {
        const finalScores = gameResult.finalScores || {};
        const myScore = finalScores[playerIndex] || 0;
        const playerCount = Object.keys(finalScores).length;

        // Calculate ranking
        const allScores = Object.entries(finalScores)
            .map(([idx, score]) => ({ idx: parseInt(idx), score }))
            .sort((a, b) => a.score - b.score);

        let myRank = allScores.findIndex(s => s.idx === playerIndex);

        // Base reward from ranking
        let baseReward;
        switch (myRank) {
            case 0: baseReward = 1.0; break;   // 1st place
            case 1: baseReward = 0.3; break;   // 2nd place
            case 2: baseReward = -0.3; break;  // 3rd place
            case 3: baseReward = -0.7; break;  // 4th place
            default: baseReward = -1.0;
        }

        // Score quality bonus
        const avgScore = Object.values(finalScores).reduce((a, b) => a + b, 0) / playerCount;
        const scoreQuality = (avgScore - myScore) / 100;  // Normalized

        // Win/elimination bonuses
        const won = gameResult.winner === playerIndex;
        const eliminated = gameResult.eliminatedPlayers?.includes(playerIndex);

        if (won) baseReward += 0.5;
        if (eliminated) baseReward -= 0.5;

        return {
            base: baseReward + scoreQuality,
            zapzap: (baseReward + scoreQuality) * 1.5,  // Critical decisions
            playType: baseReward + scoreQuality,
            drawSource: (baseReward + scoreQuality) * 0.8,
            handSize: (baseReward + scoreQuality) * 0.5
        };
    }

    /**
     * Convert features object to array for neural network
     */
    _featuresToArray(features) {
        // Use FeatureExtractor's toArray method if available
        if (typeof FeatureExtractor.toArray === 'function') {
            return FeatureExtractor.toArray(features);
        }

        // Fallback: manual conversion (45 features)
        return [
            // Hand features (10)
            features.handValue || 0,
            features.handSize || 0,
            features.jokerCount || 0,
            features.hasPairs ? 1 : 0,
            features.hasSequences ? 1 : 0,
            features.canZapZap ? 1 : 0,
            features.bestPlayValue || 0,
            features.avgCardValue || 0,
            features.handEntropy || 0,
            features.zapZapPotential || 0,

            // Game state (10)
            features.roundNumber || 0,
            features.deckSize || 0,
            features.deckRatio || 0,
            features.turnInRound || 0,
            features.turnsRemaining || 0,
            features.gameProgress || 0,
            features.earlyGame ? 1 : 0,
            features.midGame ? 1 : 0,
            features.lateGame ? 1 : 0,
            features.isGoldenScore ? 1 : 0,

            // Scoring (8)
            features.myScore || 0,
            features.normalizedScore || 0,
            features.minOpponentScore || 0,
            features.maxOpponentScore || 0,
            features.scoreGap || 0,
            features.eliminationRisk || 0,
            features.winningPosition ? 1 : 0,
            features.avgOpponentScore || 0,

            // Opponent modeling (10)
            features.activePlayerCount || 0,
            features.minOpponentHandSize || 0,
            features.maxOpponentHandSize || 0,
            features.avgOpponentHandSize || 0,
            features.opponentCloseToWin ? 1 : 0,
            features.opponentsThreatLevel || 0,
            features.nearestOpponentDistance || 0,
            features.playersWithLowHands || 0,
            features.playersWithHighHands || 0,
            features.opponentHandSizeVariance || 0,

            // Position (5)
            features.position || 0,
            features.relativePosition || 0,
            features.isFirstPosition ? 1 : 0,
            features.isLastPosition ? 1 : 0,
            features.positionBucket || 0,

            // Strategic flags (2)
            features.shouldKeepJokers ? 1 : 0,
            features.discardHasJoker ? 1 : 0
        ];
    }

    /**
     * HARD RULES: Apply HardVince-inspired rules
     */
    _applyHardRules(play, hand, gameState, features) {
        // HARD RULE 1: Golden Score Joker Strategy
        if (gameState.isGoldenScore) {
            play = this._applyGoldenScoreJokerRule(play, hand);
        }

        // HARD RULE 2: Opponent Close to Win - Release Jokers
        if (features.opponentCloseToWin && !gameState.isGoldenScore) {
            play = this._applyJokerReleaseRule(play, hand, features);
        }

        return play;
    }

    /**
     * Golden Score: Keep jokers, find alternative play
     */
    _applyGoldenScoreJokerRule(play, hand) {
        const playHasJoker = play.some(cardId => cardId >= 52);
        if (!playHasJoker) return play;

        const validPlays = CardAnalyzer.findAllValidPlays(hand);
        const jokerFreePlays = validPlays.filter(p => !p.some(c => c >= 52));

        if (jokerFreePlays.length > 0) {
            jokerFreePlays.sort((a, b) => {
                const remainingA = CardAnalyzer.calculateHandValue(hand.filter(c => !a.includes(c)));
                const remainingB = CardAnalyzer.calculateHandValue(hand.filter(c => !b.includes(c)));
                return remainingA - remainingB;
            });
            return jokerFreePlays[0];
        }

        const nonJokerCard = this._findHighestNonJokerCard(hand);
        if (nonJokerCard) return [nonJokerCard];

        return play;
    }

    /**
     * Release jokers when opponent close to winning
     */
    _applyJokerReleaseRule(play, hand, features) {
        const jokersInHand = hand.filter(c => c >= 52);
        if (jokersInHand.length === 0) return play;

        const validPlays = CardAnalyzer.findAllValidPlays(hand);
        const jokerCombos = validPlays.filter(p =>
            p.length >= 2 && p.some(c => c >= 52)
        );

        if (jokerCombos.length > 0) {
            jokerCombos.sort((a, b) => {
                const remainingA = CardAnalyzer.calculateHandValue(hand.filter(c => !a.includes(c)));
                const remainingB = CardAnalyzer.calculateHandValue(hand.filter(c => !b.includes(c)));
                return remainingA - remainingB;
            });
            return jokerCombos[0];
        }

        return play;
    }

    /**
     * Execute play type strategy
     */
    _executePlayType(playType, hand, gameState) {
        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return this._findHighestSingleCard(hand);
        }

        const evaluatedPlays = validPlays.map(play => {
            const remainingHand = hand.filter(cardId => !play.includes(cardId));
            const remainingValue = CardAnalyzer.calculateHandValue(remainingHand);
            const playValue = CardAnalyzer.calculateHandValue(play);
            const hasJoker = play.some(cardId => cardId >= 52);

            return {
                cards: play,
                remainingValue,
                playValue,
                playSize: play.length,
                isMulti: play.length > 1,
                hasJoker
            };
        });

        switch (playType) {
            case 'single_high':
                const singlePlays = evaluatedPlays.filter(p => p.playSize === 1);
                if (singlePlays.length > 0) {
                    singlePlays.sort((a, b) => b.playValue - a.playValue);
                    return singlePlays[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'multi_high':
                const multiPlays = evaluatedPlays.filter(p => p.isMulti);
                if (multiPlays.length > 0) {
                    multiPlays.sort((a, b) => a.remainingValue - b.remainingValue);
                    return multiPlays[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'avoid_joker':
                const noJokerPlays = evaluatedPlays.filter(p => !p.hasJoker);
                if (noJokerPlays.length > 0) {
                    noJokerPlays.sort((a, b) => a.remainingValue - b.remainingValue);
                    return noJokerPlays[0].cards;
                }
                const nonJokerCard = this._findHighestNonJokerCard(hand);
                if (nonJokerCard) return [nonJokerCard];
                return this._executePlayType('optimal', hand, gameState);

            case 'use_joker_combo':
                const jokerCombos = evaluatedPlays.filter(p => p.hasJoker && p.isMulti);
                if (jokerCombos.length > 0) {
                    jokerCombos.sort((a, b) => a.remainingValue - b.remainingValue);
                    return jokerCombos[0].cards;
                }
                return this._executePlayType('multi_high', hand, gameState);

            case 'optimal':
            default:
                evaluatedPlays.sort((a, b) => {
                    const scoreA = -a.remainingValue + (a.playSize * 0.5);
                    const scoreB = -b.remainingValue + (b.playSize * 0.5);
                    return scoreB - scoreA;
                });
                return evaluatedPlays[0].cards;
        }
    }

    /**
     * Get or compute features
     */
    _getFeatures(gameState, hand) {
        const cacheKey = `${gameState.currentTurn}_${gameState.roundNumber}_${hand.length}`;

        if (this._featureCacheKey === cacheKey && this._featureCache) {
            return this._featureCache;
        }

        const playerIndex = this.playerIndex || gameState.currentTurn;
        this._featureCache = FeatureExtractor.extract(gameState, playerIndex, hand);
        this._featureCacheKey = cacheKey;

        return this._featureCache;
    }

    _clearCache() {
        this._featureCache = null;
        this._featureCacheKey = null;
    }

    _findHighestNonJokerCard(hand) {
        let highest = null;
        let highestPoints = -1;

        for (const cardId of hand) {
            if (cardId >= 52) continue;
            const points = CardAnalyzer.getCardPoints(cardId);
            if (points > highestPoints) {
                highestPoints = points;
                highest = cardId;
            }
        }

        return highest;
    }

    _findHighestSingleCard(hand) {
        let highest = hand[0];
        let highestPoints = CardAnalyzer.getCardPoints(hand[0]);

        for (const cardId of hand) {
            const points = CardAnalyzer.getCardPoints(cardId);
            if (points > highestPoints) {
                highestPoints = points;
                highest = cardId;
            }
        }

        return [highest];
    }

    /**
     * Get the underlying policy
     */
    getPolicy() {
        return this.policy;
    }

    /**
     * Get strategy statistics
     */
    getStats() {
        return {
            policyStats: this.policy.getStats(),
            pendingTransitions: this.currentGameTransitions.length
        };
    }

    /**
     * Get strategy name
     */
    getName() {
        return 'DRL Bot (Double DQN)';
    }
}

module.exports = DRLBotStrategy;
