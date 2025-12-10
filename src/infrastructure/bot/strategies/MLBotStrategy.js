/**
 * MLBotStrategy
 * Machine Learning powered bot strategy using Contextual Multi-Armed Bandit
 * Learns optimal actions through online reinforcement learning
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');
const BanditPolicy = require('../ml/BanditPolicy');
const FeatureExtractor = require('../ml/FeatureExtractor');
const MCTSEvaluator = require('../ml/MCTSEvaluator');

class MLBotStrategy extends BotStrategy {
    /**
     * @param {Object} options - Strategy options
     * @param {BanditPolicy} options.policy - Shared policy instance (for learning across games)
     * @param {number} options.epsilon - Initial exploration rate
     * @param {boolean} options.useHardRules - Enable HardVince-inspired hard rules (default: true)
     * @param {boolean} options.useMCTS - Enable MCTS evaluation for play selection (default: false)
     * @param {number} options.mctsSimulations - Number of MCTS simulations (default: 30)
     */
    constructor(options = {}) {
        super('ml');

        // Use shared policy or create new one
        this.policy = options.policy || new BanditPolicy({
            epsilon: options.epsilon || 0.3,
            minEpsilon: options.minEpsilon || 0.02,
            epsilonDecay: options.epsilonDecay || 0.9999
        });

        // Enable hard rules for critical situations (HardVince-inspired)
        this.useHardRules = options.useHardRules !== false;

        // Enable MCTS for play evaluation
        this.useMCTS = options.useMCTS || false;
        if (this.useMCTS) {
            this.mctsEvaluator = new MCTSEvaluator({
                simulations: options.mctsSimulations || 30,
                maxDepth: options.mctsMaxDepth || 8
            });
        }

        // Track decisions made this game for batch learning
        this.currentGameDecisions = [];

        // Cache for features within a turn
        this._featureCache = null;
        this._featureCacheKey = null;
    }

    /**
     * Select hand size at the start of a round
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        const features = FeatureExtractor.extractHandSizeFeatures(
            activePlayerCount,
            isGoldenScore,
            this._lastKnownScore || 0
        );

        let handSize = this.policy.selectAction('handSize', features);

        // Validate bounds
        const minHandSize = 4;
        const maxHandSize = isGoldenScore ? 10 : 7;
        handSize = Math.max(minHandSize, Math.min(maxHandSize, handSize));

        // Record decision
        this.currentGameDecisions.push({
            type: 'handSize',
            features: { ...features },
            action: handSize
        });

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
            this.currentGameDecisions.push({
                type: 'zapzap',
                features: { handValue: 0 },
                action: true
            });
            return true;
        }

        const features = this._getFeatures(gameState, hand);
        const shouldCall = this.policy.selectAction('zapzap', features);

        // Record decision
        this.currentGameDecisions.push({
            type: 'zapzap',
            features: { ...features },
            action: shouldCall
        });

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

        const features = this._getFeatures(gameState, hand);
        let cards;
        let playType;

        // Use MCTS if enabled for play evaluation
        if (this.useMCTS && this.mctsEvaluator) {
            cards = this.mctsEvaluator.getBestPlay(hand, gameState, gameState.currentTurn);
            playType = 'mcts'; // Track that MCTS was used
        } else {
            // Use bandit for strategy selection
            playType = this.policy.selectAction('playType', features);
            // Convert play type to actual cards
            cards = this._executePlayType(playType, hand, gameState);
        }

        // Apply hard rules as post-selection safety nets
        if (this.useHardRules && cards) {
            cards = this._applyHardRules(cards, hand, gameState, features);
        }

        // Record decision
        this.currentGameDecisions.push({
            type: 'playType',
            features: { ...features },
            action: playType
        });

        return cards;
    }

    /**
     * HARD RULES: Apply HardVince-inspired rules for critical situations
     * These override bandit decisions when specific conditions are met
     * @param {Array<number>} play - Selected play
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Game state
     * @param {Object} features - Extracted features
     * @returns {Array<number>} Final play
     */
    _applyHardRules(play, hand, gameState, features) {
        // HARD RULE 1: Golden Score Joker Strategy
        // In Golden Score, NEVER play jokers (keep them to deny opponent)
        if (gameState.isGoldenScore) {
            play = this._applyGoldenScoreJokerRule(play, hand);
        }

        // HARD RULE 2: Opponent Close to Win - Release Jokers
        // If opponent has ≤2 cards, use jokers aggressively in combos
        if (features.opponentCloseToWin && !gameState.isGoldenScore) {
            play = this._applyJokerReleaseRule(play, hand, features);
        }

        return play;
    }

    /**
     * HARD RULE 1: Golden Score Joker Strategy
     * In Golden Score, ALWAYS keep jokers - find alternative play without jokers
     * @param {Array<number>} play - Selected play
     * @param {Array<number>} hand - Current hand
     * @returns {Array<number>} Play without jokers if possible
     */
    _applyGoldenScoreJokerRule(play, hand) {
        const playHasJoker = play.some(cardId => cardId >= 52);
        if (!playHasJoker) {
            return play;
        }

        // Try to find an alternative play without jokers
        const validPlays = CardAnalyzer.findAllValidPlays(hand);
        const jokerFreePlays = validPlays.filter(p => !p.some(c => c >= 52));

        if (jokerFreePlays.length > 0) {
            // Sort by remaining hand value (best first)
            jokerFreePlays.sort((a, b) => {
                const remainingA = CardAnalyzer.calculateHandValue(hand.filter(c => !a.includes(c)));
                const remainingB = CardAnalyzer.calculateHandValue(hand.filter(c => !b.includes(c)));
                return remainingA - remainingB;
            });
            return jokerFreePlays[0];
        }

        // If no joker-free plays, find highest non-joker single card
        const nonJokerCard = this._findHighestNonJokerCard(hand);
        if (nonJokerCard) {
            return [nonJokerCard];
        }

        // Last resort: play original (only jokers in hand)
        return play;
    }

    /**
     * HARD RULE 2: Joker Release when opponent close to winning
     * If opponent has ≤2 cards, play jokers aggressively in combos
     * @param {Array<number>} play - Selected play
     * @param {Array<number>} hand - Current hand
     * @param {Object} features - Features
     * @returns {Array<number>} Play with jokers in combos if available
     */
    _applyJokerReleaseRule(play, hand, features) {
        // Check if we have jokers to release
        const jokersInHand = hand.filter(c => c >= 52);
        if (jokersInHand.length === 0) {
            return play;
        }

        // Look for multi-card plays that use jokers
        const validPlays = CardAnalyzer.findAllValidPlays(hand);
        const jokerCombos = validPlays.filter(p =>
            p.length >= 2 && p.some(c => c >= 52)
        );

        if (jokerCombos.length > 0) {
            // Prefer combos that minimize remaining hand value
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

        const features = this._getFeatures(gameState, hand);

        // HARD RULE 3: Golden Score Joker Pickup
        // In Golden Score, ALWAYS pick up jokers from discard (hoard them)
        if (this.useHardRules && gameState.isGoldenScore) {
            const discardHasJoker = lastCardsPlayed.some(c => c >= 52);
            if (discardHasJoker) {
                // Record decision with forced action
                this.currentGameDecisions.push({
                    type: 'drawSource',
                    features: { ...features },
                    action: 'played'
                });
                this._featureCache = null;
                this._featureCacheKey = null;
                return 'played';
            }
        }

        // HARD RULE 4: Priority Joker Pickup (when opponents have many cards)
        // If opponents have > 3 cards, prioritize picking up jokers
        if (this.useHardRules && features.shouldKeepJokers && features.discardHasJoker) {
            this.currentGameDecisions.push({
                type: 'drawSource',
                features: { ...features },
                action: 'played'
            });
            this._featureCache = null;
            this._featureCacheKey = null;
            return 'played';
        }

        // Use bandit for normal decision
        const source = this.policy.selectAction('drawSource', features);

        // Record decision
        this.currentGameDecisions.push({
            type: 'drawSource',
            features: { ...features },
            action: source
        });

        // Clear feature cache after turn completes
        this._featureCache = null;
        this._featureCacheKey = null;

        return source;
    }

    /**
     * Called at end of game to update policy based on outcome
     * Uses differentiated rewards by decision type
     * @param {Object} gameResult - Result of the game
     * @param {number} playerIndex - This bot's player index
     */
    onGameEnd(gameResult, playerIndex) {
        // Calculate differentiated rewards by decision type
        const rewards = this._calculateReward(gameResult, playerIndex);

        // Update policy with type-specific rewards
        for (const decision of this.currentGameDecisions) {
            // Use type-specific reward, fall back to base
            const reward = rewards[decision.type] || rewards.base;
            this.policy.update(decision.type, decision.features, decision.action, reward);
        }

        // Store last known score for next game's hand size decision
        this._lastKnownScore = gameResult.finalScores?.[playerIndex] || 0;

        // Reset for next game
        this.currentGameDecisions = [];
        this._featureCache = null;
        this._featureCacheKey = null;
    }

    /**
     * Calculate differentiated rewards from game result
     * Different decision types receive different reward signals
     * @param {Object} gameResult
     * @param {number} playerIndex
     * @returns {Object} Rewards by decision type { base, zapzap, playType, drawSource, handSize }
     */
    _calculateReward(gameResult, playerIndex) {
        const finalScores = gameResult.finalScores || {};
        const myScore = finalScores[playerIndex] || 0;
        const playerCount = Object.keys(finalScores).length;

        // Calculate ranking (0 = best, playerCount-1 = worst)
        const allScores = Object.entries(finalScores)
            .map(([idx, score]) => ({ idx: parseInt(idx), score }))
            .sort((a, b) => a.score - b.score);

        let myRank = 0;
        for (let i = 0; i < allScores.length; i++) {
            if (allScores[i].idx === playerIndex) {
                myRank = i;
                break;
            }
        }

        // Base reward from ranking position (stronger differentiation)
        // 1st: +15, 2nd: +5, 3rd: -3, 4th: -8
        let baseReward;
        switch (myRank) {
            case 0: baseReward = 15; break;   // 1st place - increased
            case 1: baseReward = 5; break;    // 2nd place - increased
            case 2: baseReward = -3; break;   // 3rd place
            case 3: baseReward = -8; break;   // 4th place - harsher penalty
            default: baseReward = -10;
        }

        // Score quality bonus (stronger signal)
        const avgScore = Object.values(finalScores).reduce((a, b) => a + b, 0) / playerCount;
        const scoreQuality = (avgScore - myScore) / 20;  // Increased divisor impact

        // Win/elimination bonuses
        const won = gameResult.winner === playerIndex;
        const eliminated = gameResult.eliminatedPlayers?.includes(playerIndex);

        if (won) {
            baseReward += 3;
        }
        if (eliminated) {
            baseReward -= 3;
        }

        // Bonus for low absolute score
        if (myScore < 40) {
            baseReward += 2;
        } else if (myScore > 100) {
            baseReward -= 2;
        }

        // Return differentiated rewards by decision type
        return {
            base: baseReward + scoreQuality,
            // ZapZap decisions are CRITICAL - strongest reward signal
            zapzap: won ? (baseReward + scoreQuality) * 1.5 : (baseReward + scoreQuality) * 0.8,
            // PlayType decisions are important - full reward
            playType: baseReward + scoreQuality,
            // DrawSource decisions are moderately important
            drawSource: (baseReward + scoreQuality) * 0.9,
            // HandSize decision (initial) is less critical
            handSize: (baseReward + scoreQuality) * 0.7
        };
    }

    /**
     * Get or compute features for current state
     */
    _getFeatures(gameState, hand) {
        const cacheKey = `${gameState.currentTurn}_${gameState.roundNumber}_${hand.length}`;

        if (this._featureCacheKey === cacheKey && this._featureCache) {
            return this._featureCache;
        }

        const playerIndex = gameState.currentTurn;
        this._featureCache = FeatureExtractor.extract(gameState, playerIndex, hand);
        this._featureCacheKey = cacheKey;

        return this._featureCache;
    }

    /**
     * Convert play type to actual cards
     * Uses optimal evaluation like HardBotStrategy with Joker management from HardVince
     * @param {string} playType
     * @param {Array<number>} hand
     * @param {Object} gameState
     * @returns {Array<number>}
     */
    _executePlayType(playType, hand, gameState) {
        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return this._findHighestSingleCard(hand);
        }

        // Evaluate ALL plays by resulting hand value (like HardBotStrategy)
        const evaluatedPlays = validPlays.map(play => {
            const remainingHand = hand.filter(cardId => !play.includes(cardId));
            const remainingValue = CardAnalyzer.calculateHandValue(remainingHand);
            const playValue = CardAnalyzer.calculateHandValue(play);
            const playSize = play.length;

            // Check if play contains jokers
            const hasJoker = play.some(cardId => cardId >= 52);
            const jokerCount = play.filter(cardId => cardId >= 52).length;

            return {
                cards: play,
                remainingValue,
                playValue,
                playSize,
                isMulti: playSize > 1,
                hasJoker,
                jokerCount
            };
        });

        switch (playType) {
            case 'single_high':
                // Single card that removes most points
                const singlePlays = evaluatedPlays.filter(p => p.playSize === 1);
                if (singlePlays.length > 0) {
                    singlePlays.sort((a, b) => b.playValue - a.playValue);
                    return singlePlays[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'multi_high':
                // Multi-card play that minimizes remaining hand value
                const multiPlays = evaluatedPlays.filter(p => p.isMulti);
                if (multiPlays.length > 0) {
                    multiPlays.sort((a, b) => a.remainingValue - b.remainingValue);
                    return multiPlays[0].cards;
                }
                return this._findHighestSingleCard(hand);

            case 'avoid_joker':
                // Play without using jokers - keep them for later (like HardVince when opponents have many cards)
                const noJokerPlays = evaluatedPlays.filter(p => !p.hasJoker);
                if (noJokerPlays.length > 0) {
                    // Among non-joker plays, prefer ones that minimize remaining value
                    noJokerPlays.sort((a, b) => {
                        const scoreA = -a.remainingValue + (a.playSize * 0.5);
                        const scoreB = -b.remainingValue + (b.playSize * 0.5);
                        return scoreB - scoreA;
                    });
                    return noJokerPlays[0].cards;
                }
                // If all plays have jokers, find highest single non-joker
                const nonJokerCard = this._findHighestNonJokerCard(hand);
                if (nonJokerCard) {
                    return [nonJokerCard];
                }
                // Last resort: play optimal
                return this._executePlayType('optimal', hand, gameState);

            case 'use_joker_combo':
                // Prioritize using jokers in combos (like HardVince when opponent close to winning)
                const jokerCombos = evaluatedPlays.filter(p => p.hasJoker && p.isMulti);
                if (jokerCombos.length > 0) {
                    // Prefer combos that use jokers and minimize remaining hand value
                    jokerCombos.sort((a, b) => a.remainingValue - b.remainingValue);
                    return jokerCombos[0].cards;
                }
                // No joker combos available, fall back to multi_high
                return this._executePlayType('multi_high', hand, gameState);

            case 'optimal':
            default:
                // Best overall play (minimize remaining hand value, bonus for multi-card)
                evaluatedPlays.sort((a, b) => {
                    const scoreA = -a.remainingValue + (a.playSize * 0.5);
                    const scoreB = -b.remainingValue + (b.playSize * 0.5);
                    return scoreB - scoreA;
                });
                return evaluatedPlays[0].cards;
        }
    }

    /**
     * Find highest value non-joker card
     */
    _findHighestNonJokerCard(hand) {
        let highest = null;
        let highestPoints = -1;

        for (const cardId of hand) {
            if (cardId >= 52) continue; // Skip jokers
            const points = CardAnalyzer.getCardPoints(cardId);
            if (points > highestPoints) {
                highestPoints = points;
                highest = cardId;
            }
        }

        return highest;
    }

    /**
     * Find highest value single card
     */
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
     * Find lowest value single card
     */
    _findLowestSingleCard(hand) {
        let lowest = hand[0];
        let lowestPoints = CardAnalyzer.getCardPoints(hand[0]);

        for (const cardId of hand) {
            const points = CardAnalyzer.getCardPoints(cardId);
            if (points < lowestPoints) {
                lowestPoints = points;
                lowest = cardId;
            }
        }

        return [lowest];
    }

    /**
     * Find best multi-card play (removes most points)
     */
    _findBestMultiPlay(plays) {
        if (plays.length === 0) return null;

        let best = plays[0];
        let bestValue = CardAnalyzer.calculateHandValue(plays[0]);

        for (const play of plays) {
            const value = CardAnalyzer.calculateHandValue(play);
            if (value > bestValue) {
                bestValue = value;
                best = play;
            }
        }

        return best;
    }

    /**
     * Get the underlying policy
     * @returns {BanditPolicy}
     */
    getPolicy() {
        return this.policy;
    }

    /**
     * Get strategy statistics
     * @returns {Object}
     */
    getStats() {
        return {
            policyStats: this.policy.getStats(),
            currentGameDecisions: this.currentGameDecisions.length
        };
    }

    /**
     * Get strategy name
     * @returns {string}
     */
    getName() {
        return 'ML Bot (Bandit)';
    }
}

module.exports = MLBotStrategy;
