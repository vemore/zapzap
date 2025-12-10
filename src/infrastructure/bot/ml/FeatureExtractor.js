/**
 * FeatureExtractor
 * Converts GameState to numerical features for ML decision-making
 */

const CardAnalyzer = require('../CardAnalyzer');

class FeatureExtractor {
    /**
     * Extract features for a player's decision
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player making the decision
     * @param {Array<number>} hand - Player's current hand (optional, uses gameState if not provided)
     * @returns {Object} Feature vector
     */
    static extract(gameState, playerIndex, hand = null) {
        const playerHand = hand || gameState.getPlayerHand?.(playerIndex) || gameState.hands?.[playerIndex] || [];
        const scores = gameState.scores || {};
        const eliminatedPlayers = gameState.eliminatedPlayers || [];

        // POSITION-AWARE: Extract position features
        const positionFeatures = this.extractPositionFeatures(gameState, playerIndex, eliminatedPlayers);

        // Hand features
        const handValue = CardAnalyzer.calculateHandValue(playerHand);
        const handSize = playerHand.length;
        const jokerCount = playerHand.filter(c => c >= 52).length;
        const highCardCount = playerHand.filter(c => c < 52 && (c % 13) >= 9).length; // 10, J, Q, K
        const lowCardCount = playerHand.filter(c => c < 52 && (c % 13) < 4).length; // A, 2, 3, 4

        // Potential plays
        const validPlays = CardAnalyzer.findAllValidPlays(playerHand);
        const sameRankPlays = CardAnalyzer.findSameRankPlays(playerHand);
        const sequencePlays = CardAnalyzer.findSequencePlays(playerHand);

        // Score features
        const myScore = scores[playerIndex] || 0;
        const opponentScores = this.getOpponentScores(scores, playerIndex, eliminatedPlayers);
        const minOpponentScore = opponentScores.length > 0 ? Math.min(...opponentScores) : 0;
        const maxOpponentScore = opponentScores.length > 0 ? Math.max(...opponentScores) : 0;
        const avgOpponentScore = opponentScores.length > 0
            ? opponentScores.reduce((a, b) => a + b, 0) / opponentScores.length
            : 0;
        const scoreGap = minOpponentScore - myScore;

        // Opponent hand sizes
        const opponentHandSizes = this.getOpponentHandSizes(gameState, playerIndex, eliminatedPlayers);
        const minOpponentHandSize = opponentHandSizes.length > 0 ? Math.min(...opponentHandSizes) : 0;
        const avgOpponentHandSize = opponentHandSizes.length > 0
            ? opponentHandSizes.reduce((a, b) => a + b, 0) / opponentHandSizes.length
            : 0;

        // Game context
        const roundNumber = gameState.roundNumber || 1;
        const deckSize = gameState.deck?.length || gameState.getDeckSize?.() || 0;
        const discardSize = gameState.lastCardsPlayed?.length || 0;
        const activePlayerCount = this.getActivePlayerCount(gameState, eliminatedPlayers);
        const isGoldenScore = gameState.isGoldenScore ? 1 : 0;

        // Discard pile analysis (if available)
        const lastCardsPlayed = gameState.lastCardsPlayed || [];
        const discardHasJoker = lastCardsPlayed.some(c => c >= 52) ? 1 : 0;
        const discardHasLowCard = lastCardsPlayed.some(c => c < 52 && (c % 13) < 4) ? 1 : 0;

        // Joker-specific features (critical for advanced strategy)
        const myJokerCount = jokerCount;
        const opponentCloseToWin = minOpponentHandSize <= 2 ? 1 : 0;
        const shouldKeepJokers = minOpponentHandSize > 3 && !gameState.isGoldenScore ? 1 : 0;

        // Game phase indicators
        const earlyGame = roundNumber <= 2 ? 1 : 0;
        const midGame = roundNumber > 2 && roundNumber <= 5 ? 1 : 0;
        const lateGame = roundNumber > 5 ? 1 : 0;

        // Hand quality indicators
        const hasMultiCardPlays = validPlays.filter(p => p.length > 1).length > 0 ? 1 : 0;
        const bestPlaySize = validPlays.reduce((max, p) => Math.max(max, p.length), 0);

        // NEW: Advanced hand quality metrics
        const suitCounts = this.getSuitCounts(playerHand);
        const maxSuitCount = Math.max(...Object.values(suitCounts), 0);
        const suitConcentration = handSize > 0 ? maxSuitCount / handSize : 0;

        // Rank spread for sequence potential
        const ranks = playerHand.filter(c => c < 52).map(c => c % 13);
        const minRank = ranks.length > 0 ? Math.min(...ranks) : 0;
        const maxRank = ranks.length > 0 ? Math.max(...ranks) : 0;
        const rankSpread = ranks.length > 1 ? (maxRank - minRank) / 12 : 0;

        // Longest run potential (consecutive ranks)
        const longestRunPotential = this.calculateLongestRunPotential(playerHand);

        // NEW: Risk metrics
        const eliminationProximity = Math.max(0, (100 - myScore) / 100);
        const eliminationRisk = myScore > 90 ? 2 : (myScore > 75 ? 1 : 0);

        // NEW: Opponent pressure
        const opponentsUnder3Cards = opponentHandSizes.filter(s => s <= 3).length;
        const opponentPressure = opponentsUnder3Cards / Math.max(opponentHandSizes.length, 1);

        // OPPONENT MODELING: Analyze opponent behavior patterns
        const opponentModeling = this.extractOpponentModelingFeatures(gameState, playerIndex, eliminatedPlayers);

        return {
            // Hand features
            handValue,
            handSize,
            jokerCount,
            highCardCount,
            lowCardCount,

            // Play potential
            hasPairs: sameRankPlays.length > 0 ? 1 : 0,
            hasSequences: sequencePlays.length > 0 ? 1 : 0,
            multiCardPlayCount: validPlays.filter(p => p.length > 1).length,
            canZapZap: handValue <= 5 ? 1 : 0,

            // Score features
            myScore,
            minOpponentScore,
            maxOpponentScore,
            avgOpponentScore,
            scoreGap,
            scoreRisk: myScore > 80 ? 1 : (myScore > 60 ? 0.5 : 0),

            // Opponent features
            minOpponentHandSize,
            avgOpponentHandSize,
            opponentCloseToZapZap: minOpponentHandSize <= 3 ? 1 : 0,

            // Game context
            roundNumber,
            deckSize,
            discardSize,
            activePlayerCount,
            isGoldenScore,

            // Discard analysis
            discardHasJoker,
            discardHasLowCard,

            // Joker strategy features (from HardVince)
            opponentCloseToWin,
            shouldKeepJokers,

            // Game phase
            earlyGame,
            midGame,
            lateGame,

            // Hand quality
            hasMultiCardPlays,
            bestPlaySize,

            // NEW: Advanced hand quality
            suitConcentration,
            rankSpread,
            longestRunPotential,

            // NEW: Risk metrics
            eliminationProximity,
            eliminationRisk,

            // NEW: Opponent pressure
            opponentPressure,

            // POSITION-AWARE features
            ...positionFeatures,

            // OPPONENT MODELING features
            ...opponentModeling
        };
    }

    /**
     * Extract features specifically for hand size decision (BEFORE cards are dealt)
     * Returns a full 45-feature object compatible with toArray()
     * @param {number} activePlayerCount
     * @param {boolean} isGoldenScore
     * @param {number} myScore
     * @returns {Object} Full feature object with sensible defaults for pre-deal state
     */
    static extractHandSizeFeatures(activePlayerCount, isGoldenScore, myScore = 0) {
        const scoreRisk = myScore > 80 ? 1 : (myScore > 60 ? 0.5 : 0);
        const eliminationRisk = myScore > 90 ? 2 : (myScore > 75 ? 1 : 0);
        const eliminationProximity = Math.max(0, (100 - myScore) / 100);

        // Return full feature object with defaults for unknown values
        // These represent the "pre-deal" state where we don't know our hand yet
        return {
            // Hand features - unknown at this point, use neutral defaults
            handValue: 0,
            handSize: 0,
            jokerCount: 0,
            highCardCount: 0,
            lowCardCount: 0,
            hasPairs: 0,
            hasSequences: 0,
            multiCardPlayCount: 0,
            canZapZap: 0,
            bestPlaySize: 1,

            // Game state - what we know
            roundNumber: 1,
            deckSize: 54,
            discardSize: 0,
            activePlayerCount,
            isGoldenScore: isGoldenScore ? 1 : 0,
            earlyGame: 1,  // Assume early since we're selecting hand size
            midGame: 0,
            lateGame: 0,
            discardHasJoker: 0,
            discardHasLowCard: 0,

            // Scoring features
            myScore,
            minOpponentScore: myScore,  // Assume similar scores at start
            maxOpponentScore: myScore,
            avgOpponentScore: myScore,
            scoreGap: 0,
            scoreRisk,
            eliminationRisk,
            eliminationProximity,

            // Opponent features - defaults based on player count
            minOpponentHandSize: isGoldenScore ? 10 : 7,  // Starting hand size
            avgOpponentHandSize: isGoldenScore ? 10 : 7,
            opponentCloseToZapZap: 0,
            opponentCloseToWin: 0,
            shouldKeepJokers: 0,
            zapZapThreats: 0,
            eliminationThreats: 0,
            dangerousOpponentNext: 0,
            isScoreLeader: 0,
            isScoreTrailer: 0,

            // Position features - unknown or default
            position: 0,
            relativePosition: 0,
            isFirstPosition: 0,
            isLastPosition: 0,
            positionBucket: 0,

            // Advanced hand quality - unknown
            suitConcentration: 0,
            rankSpread: 0
        };
    }

    /**
     * Get discretized context key for bandit bucketing
     * @param {string} decisionType - Type of decision
     * @param {Object} features - Feature vector
     * @returns {string} Context key
     */
    static getContextKey(decisionType, features) {
        // Discretize continuous features into buckets
        const buckets = {};

        switch (decisionType) {
            case 'handSize':
                buckets.activePlayerCount = features.activePlayerCount;
                buckets.isGoldenScore = features.isGoldenScore;
                buckets.scoreRiskBucket = Math.floor(features.scoreRisk * 2);
                break;

            case 'zapzap':
                buckets.handValueBucket = Math.min(features.handValue, 5);
                buckets.roundBucket = Math.min(Math.floor(features.roundNumber / 2), 5);
                buckets.minOppHandBucket = Math.min(Math.floor(features.minOpponentHandSize / 2), 3);
                buckets.isGoldenScore = features.isGoldenScore;
                buckets.scoreGapBucket = Math.sign(features.scoreGap);
                // POSITION-AWARE: Simplified
                buckets.isFirstPosition = features.isFirstPosition || 0;
                break;

            case 'playType':
                buckets.handValueBucket = Math.min(Math.floor(features.handValue / 5), 10);
                buckets.handSizeBucket = Math.min(features.handSize, 10);
                buckets.hasPairs = features.hasPairs;
                buckets.hasSequences = features.hasSequences;
                buckets.jokerCount = Math.min(features.jokerCount, 2);
                buckets.minOppHandBucket = Math.min(Math.floor(features.minOpponentHandSize / 2), 3);
                buckets.opponentCloseToWin = features.opponentCloseToWin || 0;
                buckets.isGoldenScore = features.isGoldenScore || 0;
                // Game phase and risk
                buckets.gamePhase = features.earlyGame ? 0 : (features.midGame ? 1 : 2);
                buckets.eliminationRisk = features.eliminationRisk || 0;
                // OPPONENT MODELING
                buckets.zapZapThreats = features.zapZapThreats || 0;
                buckets.isScoreLeader = features.isScoreLeader || 0;
                // POSITION-AWARE: Simplified - just first vs others
                buckets.isFirstPosition = features.isFirstPosition || 0;
                break;

            case 'drawSource':
                buckets.handValueBucket = Math.min(Math.floor(features.handValue / 5), 10);
                buckets.discardHasJoker = features.discardHasJoker;
                buckets.discardHasLowCard = features.discardHasLowCard;
                buckets.discardSize = Math.min(features.discardSize, 4);
                buckets.isGoldenScore = features.isGoldenScore || 0;
                buckets.opponentCloseToWin = features.opponentCloseToWin || 0;
                buckets.shouldKeepJokers = features.shouldKeepJokers || 0;
                // OPPONENT MODELING
                buckets.lastPlayHadJoker = features.lastPlayHadJoker || 0;
                buckets.dangerousOpponentNext = features.dangerousOpponentNext || 0;
                // POSITION-AWARE: Simplified
                buckets.isFirstPosition = features.isFirstPosition || 0;
                break;

            default:
                buckets.default = 0;
        }

        return `${decisionType}:${JSON.stringify(buckets)}`;
    }

    /**
     * Get opponent scores (excluding eliminated)
     */
    static getOpponentScores(scores, playerIndex, eliminatedPlayers) {
        const oppScores = [];
        for (const [idx, score] of Object.entries(scores)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i)) {
                oppScores.push(score);
            }
        }
        return oppScores;
    }

    /**
     * Get opponent hand sizes
     */
    static getOpponentHandSizes(gameState, playerIndex, eliminatedPlayers) {
        const sizes = [];
        const hands = gameState.hands || {};

        for (const [idx, hand] of Object.entries(hands)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i) && hand) {
                sizes.push(hand.length);
            }
        }
        return sizes;
    }

    /**
     * Get active player count
     */
    static getActivePlayerCount(gameState, eliminatedPlayers) {
        const hands = gameState.hands || {};
        let count = 0;
        for (const idx of Object.keys(hands)) {
            if (!eliminatedPlayers.includes(parseInt(idx))) {
                count++;
            }
        }
        return count;
    }

    /**
     * Get suit counts from hand
     * @param {Array<number>} hand - Player's hand
     * @returns {Object} Map of suit to count
     */
    static getSuitCounts(hand) {
        const counts = { 0: 0, 1: 0, 2: 0, 3: 0 }; // spades, hearts, clubs, diamonds
        for (const card of hand) {
            if (card < 52) { // Not a joker
                const suit = Math.floor(card / 13);
                counts[suit]++;
            }
        }
        return counts;
    }

    /**
     * Calculate longest potential run (sequence) in hand
     * @param {Array<number>} hand - Player's hand
     * @returns {number} Length of longest potential sequence
     */
    static calculateLongestRunPotential(hand) {
        // Group cards by suit
        const suits = { 0: [], 1: [], 2: [], 3: [] };
        let jokerCount = 0;

        for (const card of hand) {
            if (card >= 52) {
                jokerCount++;
            } else {
                const suit = Math.floor(card / 13);
                const rank = card % 13;
                suits[suit].push(rank);
            }
        }

        let longestRun = 0;

        // Check each suit for longest run
        for (const ranks of Object.values(suits)) {
            if (ranks.length === 0) continue;

            ranks.sort((a, b) => a - b);
            const uniqueRanks = [...new Set(ranks)];

            // Find longest consecutive sequence
            let currentRun = 1;
            let maxRun = 1;

            for (let i = 1; i < uniqueRanks.length; i++) {
                if (uniqueRanks[i] === uniqueRanks[i - 1] + 1) {
                    currentRun++;
                } else {
                    maxRun = Math.max(maxRun, currentRun);
                    currentRun = 1;
                }
            }
            maxRun = Math.max(maxRun, currentRun);

            // Add jokers to extend potential run
            longestRun = Math.max(longestRun, maxRun + jokerCount);
        }

        return Math.min(longestRun, 7); // Cap at 7 (max useful sequence)
    }

    /**
     * OPPONENT MODELING: Extract features about opponent behavior
     * Analyzes game state to infer opponent strategies and tendencies
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player making the decision
     * @param {Array<number>} eliminatedPlayers - List of eliminated players
     * @returns {Object} Opponent modeling features
     */
    static extractOpponentModelingFeatures(gameState, playerIndex, eliminatedPlayers) {
        const hands = gameState.hands || {};
        const scores = gameState.scores || {};
        const lastCardsPlayed = gameState.lastCardsPlayed || [];
        const currentTurn = gameState.currentTurn;

        // Calculate hand size changes (who's playing aggressively)
        let totalOpponentCards = 0;
        let opponentCount = 0;
        let minHandSize = Infinity;
        let maxHandSize = 0;

        for (const [idx, hand] of Object.entries(hands)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i) && Array.isArray(hand)) {
                totalOpponentCards += hand.length;
                opponentCount++;
                minHandSize = Math.min(minHandSize, hand.length);
                maxHandSize = Math.max(maxHandSize, hand.length);
            }
        }

        // Hand size variance (are opponents at similar levels or diverging?)
        const handSizeVariance = opponentCount > 0
            ? (maxHandSize - minHandSize) / Math.max(maxHandSize, 1)
            : 0;

        // Threat level: how many opponents could potentially ZapZap soon
        let zapZapThreats = 0;
        for (const [idx, hand] of Object.entries(hands)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i) && Array.isArray(hand)) {
                // Opponent with <= 3 cards is a threat
                if (hand.length <= 3) zapZapThreats++;
            }
        }

        // Score pressure: how many opponents are close to elimination
        let eliminationThreats = 0;
        for (const [idx, score] of Object.entries(scores)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i)) {
                if (score > 85) eliminationThreats++;
            }
        }

        // Discard pile analysis - opponent just played
        const lastPlaySize = lastCardsPlayed.length;
        const lastPlayHadJoker = lastCardsPlayed.some(c => c >= 52) ? 1 : 0;
        const lastPlayWasMulti = lastPlaySize > 1 ? 1 : 0;

        // Calculate last play value (what kind of cards opponents are discarding)
        let lastPlayValue = 0;
        let lastPlayHighCards = 0;
        let lastPlayLowCards = 0;
        for (const card of lastCardsPlayed) {
            if (card < 52) {
                const rank = card % 13;
                lastPlayValue += rank === 0 ? 1 : (rank >= 10 ? rank + 1 : rank + 1);
                if (rank >= 9) lastPlayHighCards++;
                if (rank <= 3) lastPlayLowCards++;
            }
        }

        // Opponent aggression indicator: high cards being discarded = aggressive play
        const opponentDiscardingHighCards = lastPlayHighCards > 0 ? 1 : 0;
        const opponentKeepingLowCards = lastPlayLowCards === 0 && lastPlaySize > 0 ? 1 : 0;

        // Turn position advantage (are we playing before or after dangerous opponents)
        const dangerousOpponentNext = this.isDangerousOpponentNext(gameState, playerIndex, eliminatedPlayers);

        // Score leader analysis
        const myScore = scores[playerIndex] || 0;
        let leadersAhead = 0;
        let trailersBelow = 0;
        for (const [idx, score] of Object.entries(scores)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i)) {
                if (score < myScore) leadersAhead++;
                if (score > myScore) trailersBelow++;
            }
        }

        // Am I the score leader (lowest score)?
        const isScoreLeader = leadersAhead === 0 ? 1 : 0;
        const isScoreTrailer = trailersBelow === 0 ? 1 : 0;

        return {
            // Opponent hand analysis
            handSizeVariance,
            zapZapThreats: Math.min(zapZapThreats, 3),
            eliminationThreats: Math.min(eliminationThreats, 3),

            // Last play analysis (opponent behavior)
            lastPlaySize: Math.min(lastPlaySize, 5),
            lastPlayHadJoker,
            lastPlayWasMulti,
            opponentDiscardingHighCards,
            opponentKeepingLowCards,

            // Position and score dynamics
            dangerousOpponentNext: dangerousOpponentNext ? 1 : 0,
            isScoreLeader,
            isScoreTrailer,

            // Normalized opponent card count
            avgOpponentCards: opponentCount > 0 ? totalOpponentCards / opponentCount : 0
        };
    }

    /**
     * Check if a dangerous opponent (few cards) plays next
     * @param {Object} gameState
     * @param {number} playerIndex
     * @param {Array<number>} eliminatedPlayers
     * @returns {boolean}
     */
    static isDangerousOpponentNext(gameState, playerIndex, eliminatedPlayers) {
        const hands = gameState.hands || {};
        const playerCount = Object.keys(hands).length;

        // Find next active player
        for (let offset = 1; offset < playerCount; offset++) {
            const nextPlayer = (playerIndex + offset) % playerCount;
            if (!eliminatedPlayers.includes(nextPlayer)) {
                const hand = hands[nextPlayer];
                if (Array.isArray(hand) && hand.length <= 3) {
                    return true; // Next player is dangerous
                }
                return false; // Next player is not dangerous
            }
        }
        return false;
    }

    /**
     * POSITION-AWARE: Extract features related to player position
     * Position has huge impact on win rate (~30% for position 0 vs ~6% for position 3)
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player's position (0-3)
     * @param {Array<number>} eliminatedPlayers - List of eliminated players
     * @returns {Object} Position-related features
     */
    static extractPositionFeatures(gameState, playerIndex, eliminatedPlayers) {
        const hands = gameState.hands || {};
        const playerCount = Object.keys(hands).length;
        const activePlayerCount = this.getActivePlayerCount(gameState, eliminatedPlayers);

        // Raw position (0-3)
        const position = playerIndex;

        // Position relative to active players (normalized 0-1)
        // 0 = first to play, 1 = last to play
        const relativePosition = activePlayerCount > 1
            ? playerIndex / (activePlayerCount - 1)
            : 0;

        // Is first position (strong advantage)
        const isFirstPosition = playerIndex === 0 ? 1 : 0;

        // Is last position (disadvantage - must react to all others)
        const isLastPosition = playerIndex === (playerCount - 1) ? 1 : 0;

        // Position bucket (early=0, mid=1, late=2)
        let positionBucket;
        if (playerIndex === 0) {
            positionBucket = 0; // Early (best)
        } else if (playerIndex === playerCount - 1) {
            positionBucket = 2; // Late (worst)
        } else {
            positionBucket = 1; // Mid
        }

        // Number of players who play BEFORE me this turn
        // (more = more info available, but less control)
        const playersBefore = playerIndex;

        // Number of players who play AFTER me this turn
        // (more = less safe to play aggressively)
        const playersAfter = playerCount - playerIndex - 1;

        // Position-based strategy hints
        // First position should be more aggressive (set the pace)
        // Last position should be more defensive (react to threats)
        const shouldBeAggressive = isFirstPosition;
        const shouldBeDefensive = isLastPosition;

        // Calculate "danger window" - how many dangerous opponents play before next turn
        let dangerousBefore = 0;
        let dangerousAfter = 0;
        for (const [idx, hand] of Object.entries(hands)) {
            const i = parseInt(idx);
            if (i !== playerIndex && !eliminatedPlayers.includes(i) && Array.isArray(hand)) {
                if (hand.length <= 3) {
                    if (i < playerIndex) dangerousBefore++;
                    if (i > playerIndex) dangerousAfter++;
                }
            }
        }

        return {
            // Raw position
            position,
            relativePosition,

            // Position flags
            isFirstPosition,
            isLastPosition,
            positionBucket,

            // Turn order context
            playersBefore,
            playersAfter,

            // Strategy hints
            shouldBeAggressive,
            shouldBeDefensive,

            // Danger assessment by position
            dangerousBefore,
            dangerousAfter
        };
    }

    /**
     * Convert features object to a fixed-size array for neural network input
     * @param {Object} features - Features object from extract()
     * @returns {Array<number>} Fixed-size feature array (45 dimensions)
     */
    static toArray(features) {
        // Return 45-dimensional feature vector in consistent order
        // Each feature is normalized to roughly [0, 1] range where possible
        return [
            // Hand features (10)
            Math.min((features.handValue || 0) / 100, 1),        // Normalized hand value
            Math.min((features.handSize || 0) / 10, 1),          // Normalized hand size
            Math.min((features.jokerCount || 0) / 2, 1),         // Normalized joker count
            features.hasPairs ? 1 : 0,
            features.hasSequences ? 1 : 0,
            features.canZapZap ? 1 : 0,
            Math.min((features.multiCardPlayCount || 0) / 10, 1), // Multi-card plays
            Math.min((features.highCardCount || 0) / 5, 1),      // High card count
            Math.min((features.lowCardCount || 0) / 5, 1),       // Low card count
            Math.min((features.bestPlaySize || 1) / 5, 1),       // Best play size

            // Game state (10)
            Math.min((features.roundNumber || 1) / 10, 1),       // Round number
            Math.min((features.deckSize || 0) / 54, 1),          // Deck size ratio
            Math.min((features.discardSize || 0) / 5, 1),        // Discard size
            Math.min((features.activePlayerCount || 4) / 4, 1),  // Active players
            features.isGoldenScore || 0,
            features.earlyGame || 0,
            features.midGame || 0,
            features.lateGame || 0,
            features.discardHasJoker || 0,
            features.discardHasLowCard || 0,

            // Scoring features (8)
            Math.min((features.myScore || 0) / 100, 1),          // My score
            Math.min((features.minOpponentScore || 0) / 100, 1), // Min opponent score
            Math.min((features.maxOpponentScore || 0) / 100, 1), // Max opponent score
            Math.min((features.avgOpponentScore || 0) / 100, 1), // Avg opponent score
            Math.max(-1, Math.min((features.scoreGap || 0) / 50, 1)),  // Score gap
            features.scoreRisk || 0,
            features.eliminationRisk || 0,
            features.eliminationProximity || 0,

            // Opponent features (10)
            Math.min((features.minOpponentHandSize || 0) / 10, 1),
            Math.min((features.avgOpponentHandSize || 0) / 10, 1),
            features.opponentCloseToZapZap || 0,
            features.opponentCloseToWin || 0,
            features.shouldKeepJokers || 0,
            Math.min((features.zapZapThreats || 0) / 3, 1),
            Math.min((features.eliminationThreats || 0) / 3, 1),
            features.dangerousOpponentNext || 0,
            features.isScoreLeader || 0,
            features.isScoreTrailer || 0,

            // Position features (5)
            Math.min((features.position || 0) / 3, 1),
            features.relativePosition || 0,
            features.isFirstPosition || 0,
            features.isLastPosition || 0,
            Math.min((features.positionBucket || 0) / 2, 1),

            // Advanced hand quality (2)
            features.suitConcentration || 0,
            features.rankSpread || 0
        ];
    }

    /**
     * Get the dimension of the feature array
     * @returns {number} Feature dimension (45)
     */
    static getFeatureDimension() {
        return 45;
    }
}

module.exports = FeatureExtractor;
