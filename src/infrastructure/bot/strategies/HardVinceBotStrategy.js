/**
 * HardVinceBotStrategy
 * Advanced bot that builds on HardBotStrategy with additional "Vince" strategies:
 * 1. Keep Jokers for sequences while opponents have > 3 cards
 * 2. Play Jokers in pairs/sets when any opponent has <= 3 cards
 * 3. Track when opponents pick cards from discard - they'll likely play it soon
 * 4. Track all played cards for probability calculation (reset on reshuffle)
 * 5. Priority Joker pickup when opponents have > 3 cards
 * 6. Golden Score Joker Strategy:
 *    - ALWAYS pick up Jokers from discard (hoard them)
 *    - NEVER play Jokers (keep them until the end)
 *    - This denies Jokers to opponent and forces them to play theirs first
 * 7. Early Game High Card Accumulation Strategy:
 *    - When all players have >= 5 cards (early game), ZapZap probability is low
 *    - Players often discard high cards early → opportunity to pick them up for pairs
 *    - If no triple or sequence available, favor keeping high card pairs
 *    - Play intermediate value cards (5-9) instead to preserve high card pairs
 * 8. Enhanced Card Counting - Probability calculation for cards in deck
 *    - Calculate exact probability of cards being in deck vs opponent hands
 *    - Use probability to make better draw decisions
 * 9. Opponent Hand Modeling - Estimate opponent hands based on their actions
 *    - Track what opponents pick from discard
 *    - Estimate opponent hand compositions and zapzap risk
 *    - Adjust strategy based on opponent threat levels
 * 10. Strategic ZapZap Timing
 *    - Aggressive ZapZap: Call immediately at <=5 when opponents have many cards (maximize their penalty)
 *    - Defensive ZapZap: Avoid calling when opponents are close to ZapZap (high risk of being countered)
 *    - Counter-ZapZap Joker pickup: Pick Joker when at 1-2 points to counter opponent's ZapZap
 * 11. Bad Hand Fallback Strategy
 *    - Detect poor starting hand "zoupzoup" (no pairs, no sequences, no jokers, high total value)
 *    - Switch to defensive mode: prioritize discarding highest point cards
 *    - Goal: minimize points when opponent likely calls ZapZap first
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');
const CardProbabilityTracker = require('../CardProbabilityTracker');

class HardVinceBotStrategy extends BotStrategy {
    /**
     * Default parameters for scoring decisions
     * Optimized via genetic algorithm (74,000 games, 8 generations)
     * Win rate: 18.65% vs 15.80% baseline (+2.85% improvement)
     * Includes Strategy 8-11 (card counting, opponent modeling, strategic ZapZap, bad hand fallback)
     */
    static DEFAULT_PARAMS = {
        // Strategy 6: Golden Score Joker management
        goldenScoreJokerPenalty: -393.86,    // Penalty for playing Jokers in Golden Score
        goldenScoreJokerPickupBonus: 23.89,  // Bonus for picking up Jokers in Golden Score

        // Strategy 1 & 2: Joker management based on opponent hand size
        jokerPairSetPenalty: -46.24,         // Penalty for playing Joker in pair/set when opponents > 3 cards
        jokerSequencePenalty: -15.43,        // Penalty for playing Joker in sequence when opponents > 3 cards
        jokerPairSetBonusLateGame: 93.69,    // Bonus for playing Joker when opponents <= 3 cards
        jokerSequenceBonusEarly: 11.47,      // Bonus for Joker in combos when opponents > 3 cards
        jokerPenaltyNearZapZap: -71.26,      // Penalty for picking up Joker when opponent near zapzap

        // Strategy 3: Opponent tracking
        opponentWantsBonusMultiplier: 5.63,  // Multiplier for cards that combine with opponent picks

        // Strategy 7: Early game high card accumulation
        intermediateCardBonusMultiplier: 19.83, // Bonus per intermediate card (5-9) played in early game
        highCardPairBreakingPenalty: -168.99, // Penalty for breaking up a high card pair
        singleHighCardRetentionPenalty: -6.10, // Penalty for playing single high card
        highCardPairPreservationBonusMultiplier: 44.28, // Bonus per high card pair preserved

        // Card evaluation for draw decisions
        combinationBonusMultiplier: 11.77,   // Bonus per new multi-card combo created
        setBonusMultiplier: 50.99,           // Bonus per card of same rank in hand
        setBonusReduction: -6.41,            // Reduction when 2+ cards of rank already played
        combinationBonusReduction: -21.53,   // Reduction when 3+ cards of rank already played

        // Draw decision threshold
        discardPickupThreshold: 15.45,       // Min improvement to pick from discard

        // Strategy 8: Enhanced card counting (probability-based)
        deckProbabilityWeight: 6.87,         // Weight for deck probability in draw decisions
        lowProbabilityPenalty: -25.65,       // Penalty when probability of completing combo is low

        // Strategy 9: Opponent modeling
        highThreatZapZapPenalty: -40.79,     // Penalty for risky plays when opponent zapzap risk is high
        opponentThreatMultiplier: 2.40,      // Multiplier for opponent threat assessment
        blockOpponentBonus: 17.59,           // Bonus for plays that block opponent combos

        // Strategy 10: Strategic ZapZap timing
        aggressiveZapZapMinOpponentCards: 5.38, // Min avg opponent cards for aggressive ZapZap
        defensiveZapZapRiskThreshold: 0.13,  // ZapZap risk threshold to become defensive
        defensiveZapZapMaxHandValue: 6.66,   // Only ZapZap at this value when opponents are risky
        counterZapZapMaxHandValue: 4.73,     // Max hand value for counter-ZapZap Joker pickup
        counterZapZapJokerBonus: 233.13,     // Bonus for picking Joker when counter-ZapZap possible

        // Strategy 11: Bad Hand Fallback
        badHandMinValue: 67.18,              // Min hand value to consider "bad" (with no combos)
        badHandHighCardBonusMultiplier: 3.92, // Bonus for playing high cards in bad hand mode
        badHandMaxPairs: 0,                  // Max pairs to still be considered bad hand
        badHandMaxSequenceCards: 3.83        // Max cards that could form sequence to be bad hand
    };

    constructor(params = {}) {
        super('hard_vince');

        // Merge provided params with defaults
        this.params = { ...HardVinceBotStrategy.DEFAULT_PARAMS, ...params };

        // Memory state (persists during bot's lifetime in a game)
        this.playedCardsHistory = [];      // All cards played this round
        this.opponentPickedCards = {};     // { playerIndex: [cardIds picked from discard] }
        this.lastDeckSize = null;          // To detect deck reshuffle
        this.lastRoundNumber = null;       // To detect new round
        this.botPlayerIndex = null;        // Bot's own player index

        // Strategy 8 & 9: Advanced probability tracker
        this.probabilityTracker = new CardProbabilityTracker();

        // Strategy 11: Bad hand detection
        this.isBadHandMode = false;        // Whether we're in bad hand fallback mode
        this.initialHandAnalyzed = false;  // Whether initial hand has been analyzed this round
    }

    /**
     * Get current parameters (useful for debugging/optimization)
     * @returns {Object} Current parameters
     */
    getParams() {
        return { ...this.params };
    }

    /**
     * Update memory based on game state
     * @param {Object} gameState - Current game state
     * @param {Array<number>} myHand - Bot's current hand (optional)
     */
    updateMemory(gameState, myHand = null) {
        // Detect new round - reset all memory
        if (this.lastRoundNumber !== null && gameState.roundNumber !== this.lastRoundNumber) {
            this.playedCardsHistory = [];
            this.opponentPickedCards = {};
            this.lastDeckSize = null;
            // Reset probability tracker for new round
            this.probabilityTracker.reset();
            // Reset bad hand detection for new round
            this.isBadHandMode = false;
            this.initialHandAnalyzed = false;
        }
        this.lastRoundNumber = gameState.roundNumber;

        // Detect deck reshuffle (deck size suddenly increases)
        const currentDeckSize = gameState.deck ? gameState.deck.length : 0;
        if (this.lastDeckSize !== null && currentDeckSize > this.lastDeckSize + 5) {
            // Deck was reshuffled - reset played cards history
            this.playedCardsHistory = [];
        }
        this.lastDeckSize = currentDeckSize;

        // Track opponent draws from discard pile
        const lastAction = gameState.lastAction;
        if (lastAction && lastAction.type === 'draw' && lastAction.source === 'played') {
            const playerIndex = lastAction.playerIndex;
            if (!this.opponentPickedCards[playerIndex]) {
                this.opponentPickedCards[playerIndex] = [];
            }
            if (lastAction.cardId !== undefined) {
                this.opponentPickedCards[playerIndex].push(lastAction.cardId);
            }
        }

        // Track played cards (from lastCardsPlayed which are the previously played cards)
        if (gameState.lastCardsPlayed && gameState.lastCardsPlayed.length > 0) {
            for (const cardId of gameState.lastCardsPlayed) {
                if (!this.playedCardsHistory.includes(cardId)) {
                    this.playedCardsHistory.push(cardId);
                }
            }
        }

        // Strategy 8 & 9: Update probability tracker with full game state
        if (myHand) {
            this.probabilityTracker.update(gameState, myHand);
        }
    }

    /**
     * Get minimum hand size among opponents
     * @param {Object} gameState - Current game state
     * @param {number} botPlayerIndex - Bot's player index
     * @returns {number} Minimum opponent hand size
     */
    getMinOpponentHandSize(gameState, botPlayerIndex) {
        const hands = gameState.hands || {};
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        let minSize = Infinity;

        for (const [indexStr, hand] of Object.entries(hands)) {
            const playerIndex = parseInt(indexStr, 10);
            if (playerIndex !== botPlayerIndex && !eliminatedPlayers.includes(playerIndex)) {
                if (Array.isArray(hand)) {
                    minSize = Math.min(minSize, hand.length);
                }
            }
        }

        return minSize === Infinity ? 0 : minSize;
    }

    /**
     * Check if all opponents have more than a threshold number of cards
     * @param {Object} gameState - Current game state
     * @param {number} botPlayerIndex - Bot's player index
     * @param {number} threshold - Card threshold
     * @returns {boolean}
     */
    allOpponentsHaveMoreThan(gameState, botPlayerIndex, threshold) {
        return this.getMinOpponentHandSize(gameState, botPlayerIndex) > threshold;
    }

    /**
     * VINCE STRATEGY 7: Check if we're in early game phase
     * Early game = all players have >= 5 cards (low ZapZap probability)
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    isEarlyGamePhase(gameState) {
        const hands = gameState.hands || {};
        const eliminatedPlayers = gameState.eliminatedPlayers || [];

        for (const [indexStr, hand] of Object.entries(hands)) {
            const playerIndex = parseInt(indexStr, 10);
            if (!eliminatedPlayers.includes(playerIndex)) {
                if (Array.isArray(hand) && hand.length < 5) {
                    return false; // Someone has few cards, not early game
                }
            }
        }
        return true;
    }

    /**
     * VINCE STRATEGY 7: Check if hand has triples or sequences available
     * @param {Array<Object>} evaluatedPlays - All evaluated plays
     * @returns {boolean}
     */
    hasTripleOrSequence(evaluatedPlays) {
        for (const play of evaluatedPlays) {
            const cards = play.cards;
            if (cards.length >= 3) {
                // Check if it's a triple (same rank) or sequence
                if (CardAnalyzer.isValidSameRank(cards) || CardAnalyzer.isValidSequence(cards)) {
                    return true;
                }
            }
        }
        return false;
    }

    /**
     * VINCE STRATEGY 7: Get card rank value (for determining intermediate vs high cards)
     * Intermediate cards: 5-9 (rank index 4-8)
     * High cards: 10-K (rank index 9-12)
     * Low cards: A-4 (rank index 0-3)
     * @param {number} cardId - Card ID
     * @returns {string} 'low', 'intermediate', or 'high'
     */
    getCardCategory(cardId) {
        if (CardAnalyzer.isJoker(cardId)) {
            return 'joker';
        }
        const rank = CardAnalyzer.getRank(cardId); // 0-12 (A=0, K=12)
        if (rank <= 3) return 'low';        // A, 2, 3, 4
        if (rank <= 8) return 'intermediate'; // 5, 6, 7, 8, 9
        return 'high';                       // 10, J, Q, K
    }

    /**
     * VINCE STRATEGY 7: Count high card pairs in remaining hand
     * @param {Array<number>} hand - Hand to analyze
     * @returns {number} Number of high card pairs
     */
    countHighCardPairs(hand) {
        const nonJokers = hand.filter(cardId => !CardAnalyzer.isJoker(cardId));
        const rankCounts = {};

        for (const cardId of nonJokers) {
            const rank = CardAnalyzer.getRank(cardId);
            if (rank >= 9) { // High cards: 10, J, Q, K (rank index 9-12)
                rankCounts[rank] = (rankCounts[rank] || 0) + 1;
            }
        }

        let pairCount = 0;
        for (const count of Object.values(rankCounts)) {
            if (count >= 2) pairCount++;
        }
        return pairCount;
    }

    /**
     * STRATEGY 11: Analyze if hand is "bad" (poor starting position)
     * A bad hand has:
     * - No jokers
     * - No pairs (or very few)
     * - No sequence potential (cards too scattered)
     * - High total value
     * @param {Array<number>} hand - Hand to analyze
     * @returns {boolean} True if hand is considered bad
     */
    analyzeBadHand(hand) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return false;
        }

        // Check for jokers - having a joker is always good
        const jokers = CardAnalyzer.findJokers(hand);
        if (jokers.length > 0) {
            return false; // Jokers make any hand decent
        }

        // Calculate hand value
        const handValue = CardAnalyzer.calculateHandValue(hand);
        if (handValue < this.params.badHandMinValue) {
            return false; // Low value hands are fine
        }

        // Count pairs
        const nonJokers = hand.filter(cardId => !CardAnalyzer.isJoker(cardId));
        const rankCounts = {};
        for (const cardId of nonJokers) {
            const rank = CardAnalyzer.getRank(cardId);
            rankCounts[rank] = (rankCounts[rank] || 0) + 1;
        }

        let pairCount = 0;
        for (const count of Object.values(rankCounts)) {
            if (count >= 2) pairCount++;
        }

        if (pairCount > this.params.badHandMaxPairs) {
            return false; // Has pairs, not a bad hand
        }

        // Check for sequence potential (consecutive cards in same suit)
        const bySuit = {};
        for (const cardId of nonJokers) {
            const suit = CardAnalyzer.getSuit(cardId);
            if (!bySuit[suit]) bySuit[suit] = [];
            bySuit[suit].push(CardAnalyzer.getRank(cardId));
        }

        let maxSequencePotential = 0;
        for (const ranks of Object.values(bySuit)) {
            if (ranks.length < 2) continue;
            ranks.sort((a, b) => a - b);

            // Count cards that could form a sequence (within 2 ranks of each other)
            let sequenceCards = 1;
            for (let i = 1; i < ranks.length; i++) {
                if (ranks[i] - ranks[i - 1] <= 2) {
                    sequenceCards++;
                } else {
                    maxSequencePotential = Math.max(maxSequencePotential, sequenceCards);
                    sequenceCards = 1;
                }
            }
            maxSequencePotential = Math.max(maxSequencePotential, sequenceCards);
        }

        if (maxSequencePotential > this.params.badHandMaxSequenceCards) {
            return false; // Has sequence potential
        }

        // Hand is bad: high value, no jokers, no pairs, no sequence potential
        return true;
    }

    /**
     * Select optimal play with Vince strategies
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // Update memory before making decision (pass hand for probability tracker)
        this.updateMemory(gameState, hand);

        // Determine bot's player index from gameState
        const botPlayerIndex = gameState.currentTurn;
        this.botPlayerIndex = botPlayerIndex;

        // STRATEGY 9: Get opponent threat assessment
        const opponentThreats = this.probabilityTracker.getOpponentThreats();
        const highestThreat = opponentThreats.length > 0 ? opponentThreats[0] : null;
        const maxZapZapRisk = highestThreat ? highestThreat.zapZapRisk : 0;

        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        const jokers = CardAnalyzer.findJokers(hand);
        const hasJokers = jokers.length > 0;
        const minOpponentCards = this.getMinOpponentHandSize(gameState, botPlayerIndex);
        const opponentsHaveMoreThan3 = minOpponentCards > 3;

        // VINCE STRATEGY 6: Detect Golden Score mode
        const isGoldenScore = gameState.isGoldenScore || false;

        // VINCE STRATEGY 7: Detect early game phase
        const isEarlyGame = this.isEarlyGamePhase(gameState);

        // STRATEGY 11: Bad Hand Detection - analyze initial hand once per round
        if (!this.initialHandAnalyzed && isEarlyGame) {
            this.isBadHandMode = this.analyzeBadHand(hand);
            this.initialHandAnalyzed = true;
        }

        // STRATEGY 11: Bad Hand Fallback - if in bad hand mode, use defensive strategy
        // Prioritize getting rid of highest point cards as quickly as possible
        if (this.isBadHandMode && !isGoldenScore) {
            // In bad hand mode: play the highest value cards first
            // This minimizes our score when opponent calls ZapZap
            const maxPointPlay = CardAnalyzer.findMaxPointPlay(hand);
            if (maxPointPlay) {
                return maxPointPlay;
            }
        }

        // Evaluate each play by resulting hand value
        const evaluatedPlays = validPlays.map(play => {
            const remainingHand = hand.filter(cardId => !play.includes(cardId));
            const remainingValue = CardAnalyzer.calculateHandValue(remainingHand);
            const playValue = CardAnalyzer.calculateHandValue(play);
            const playSize = play.length;

            // Check if this play contains jokers
            const jokersInPlay = play.filter(cardId => CardAnalyzer.isJoker(cardId));
            const hasJokersInPlay = jokersInPlay.length > 0;

            // Check if this is a sequence (jokers are valuable in sequences)
            const isSequence = play.length >= 3 && CardAnalyzer.isValidSequence(play);
            // Check if this is a pair/set
            const isPairOrSet = play.length >= 2 && CardAnalyzer.isValidSameRank(play) && !isSequence;

            let score = -remainingValue + (playSize * 0.5);

            // VINCE STRATEGY 6: NEVER play Jokers during Golden Score
            // In Golden Score, playing a Joker gives a massive advantage to the opponent
            // Keep Jokers until the very end - opponent will get stuck with their Jokers too
            if (hasJokersInPlay && isGoldenScore) {
                score += this.params.goldenScoreJokerPenalty; // Extreme penalty - effectively blocks any play containing Jokers
            }
            // VINCE STRATEGY 1 & 2: Joker management (only applies outside Golden Score)
            else if (hasJokersInPlay) {
                if (opponentsHaveMoreThan3) {
                    // Opponents have > 2 cards: keep jokers, penalize playing them in pairs/sets
                    if (isPairOrSet) {
                        score += this.params.jokerPairSetPenalty; // Heavy penalty for playing jokers in pairs/sets
                    } else if (isSequence) {
                        score += this.params.jokerSequencePenalty; // Small penalty even for sequences when opponents have many cards
                    }
                } else {
                    // Opponent has <= 3 cards: encourage playing jokers in pairs/sets
                    if (isPairOrSet) {
                        score += this.params.jokerPairSetBonusLateGame; // Bonus for getting rid of jokers in pairs/sets
                    }
                }
            }

            // VINCE STRATEGY 3: Prioritize cards that combine with opponent's picked cards
            const opponentWantsBonus = this.calculateOpponentWantsBonus(play, hand);
            score += opponentWantsBonus;

            return {
                cards: play,
                remainingValue,
                playValue,
                playSize,
                score,
                isSequence,
                isPairOrSet
            };
        });

        // VINCE STRATEGY 7: Early game high card accumulation
        // When all players have >= 5 cards, ZapZap probability is low
        // Players discard high cards early → opportunity to collect them for pairs later
        // If no triple or sequence available, favor keeping high card pairs
        // Play intermediate value cards (5-9) instead of high cards (10-K)
        if (isEarlyGame && !isGoldenScore) {
            const hasTripleOrSeq = this.hasTripleOrSequence(evaluatedPlays);

            if (!hasTripleOrSeq) {
                // No triple or sequence available - apply early game strategy
                for (const evalPlay of evaluatedPlays) {
                    const play = evalPlay.cards;

                    // Only apply to single cards or pairs (not triples+)
                    if (play.length <= 2) {
                        // Categorize cards in this play
                        let intermediateCount = 0;
                        let highCount = 0;

                        for (const cardId of play) {
                            const category = this.getCardCategory(cardId);
                            if (category === 'intermediate') intermediateCount++;
                            if (category === 'high') highCount++;
                        }

                        // Check if remaining hand preserves high card pairs
                        const remainingHand = hand.filter(cardId => !play.includes(cardId));
                        const highPairsRemaining = this.countHighCardPairs(remainingHand);

                        // Favor playing intermediate cards (bonus)
                        if (intermediateCount > 0) {
                            evalPlay.score += intermediateCount * this.params.intermediateCardBonusMultiplier; // Bonus for playing intermediate cards
                        }

                        // Penalize playing high cards that could form pairs
                        if (highCount > 0 && play.length === 1) {
                            // Check if this high card has a pair potential
                            const cardRank = CardAnalyzer.getRank(play[0]);
                            const sameRankInHand = hand.filter(id =>
                                !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === cardRank
                            ).length;

                            if (sameRankInHand >= 2) {
                                // Don't break up a pair of high cards
                                evalPlay.score += this.params.highCardPairBreakingPenalty;
                            } else if (cardRank >= 9) {
                                // Single high card with no pair - slight penalty to keep for potential future pair
                                evalPlay.score += this.params.singleHighCardRetentionPenalty;
                            }
                        }

                        // Bonus for preserving high card pairs in remaining hand
                        if (highPairsRemaining > 0) {
                            evalPlay.score += highPairsRemaining * this.params.highCardPairPreservationBonusMultiplier;
                        }
                    }
                }
            }
        }

        // STRATEGY 9: Adjust scores based on opponent threat level
        if (maxZapZapRisk > 0.5) {
            // High risk of opponent calling zapzap - prioritize reducing hand value
            for (const evalPlay of evaluatedPlays) {
                // Penalize plays that leave high remaining value when opponent might zapzap
                if (evalPlay.remainingValue > 10) {
                    evalPlay.score += this.params.highThreatZapZapPenalty * maxZapZapRisk;
                }

                // Bonus for plays that significantly reduce our hand value
                if (evalPlay.playValue >= 15) {
                    evalPlay.score += evalPlay.playValue * 0.5 * maxZapZapRisk;
                }
            }
        }

        // STRATEGY 9: Block opponent combos
        if (highestThreat && highestThreat.likelyRanks.length > 0) {
            for (const evalPlay of evaluatedPlays) {
                // Check if this play blocks cards opponent likely wants
                let blockBonus = 0;
                for (const cardId of evalPlay.cards) {
                    if (CardAnalyzer.isJoker(cardId)) continue;
                    const rank = CardAnalyzer.getRank(cardId);
                    if (highestThreat.likelyRanks.includes(rank)) {
                        blockBonus += this.params.blockOpponentBonus;
                    }
                }
                evalPlay.score += blockBonus;
            }
        }

        // Sort by score descending (best plays first)
        evaluatedPlays.sort((a, b) => b.score - a.score);

        // Return best play
        return evaluatedPlays[0].cards;
    }

    /**
     * Calculate bonus for playing cards that could combine with opponent's picked cards
     * @param {Array<number>} play - Cards to play
     * @param {Array<number>} hand - Full hand
     * @returns {number} Bonus score
     */
    calculateOpponentWantsBonus(play, hand) {
        let bonus = 0;

        // Check if we're keeping cards that could combine with opponent's picked cards
        const remainingHand = hand.filter(cardId => !play.includes(cardId));

        for (const [playerIndexStr, pickedCards] of Object.entries(this.opponentPickedCards)) {
            for (const pickedCard of pickedCards) {
                if (CardAnalyzer.isJoker(pickedCard)) continue;

                const pickedRank = CardAnalyzer.getRank(pickedCard);
                const pickedSuit = CardAnalyzer.getSuit(pickedCard);

                // Count how many cards we keep that could combine with their picked card
                let combiningCards = 0;
                for (const remainingCard of remainingHand) {
                    if (CardAnalyzer.isJoker(remainingCard)) continue;

                    const rank = CardAnalyzer.getRank(remainingCard);
                    const suit = CardAnalyzer.getSuit(remainingCard);

                    // Same rank (for pairs/sets)
                    if (rank === pickedRank) {
                        combiningCards++;
                    }
                    // Adjacent rank and same suit (for sequences)
                    if (suit === pickedSuit && Math.abs(rank - pickedRank) <= 2) {
                        combiningCards++;
                    }
                }

                // Bonus for keeping cards that could block/combine
                bonus += combiningCards * this.params.opponentWantsBonusMultiplier;
            }
        }

        return bonus;
    }

    /**
     * Get average opponent hand size (excluding eliminated players)
     * @param {Object} gameState - Current game state
     * @param {number} botPlayerIndex - Bot's player index
     * @returns {number} Average opponent hand size
     */
    getAverageOpponentHandSize(gameState, botPlayerIndex) {
        const hands = gameState.hands || {};
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        let totalCards = 0;
        let playerCount = 0;

        for (const [indexStr, hand] of Object.entries(hands)) {
            const playerIndex = parseInt(indexStr, 10);
            if (playerIndex !== botPlayerIndex && !eliminatedPlayers.includes(playerIndex)) {
                if (Array.isArray(hand)) {
                    totalCards += hand.length;
                    playerCount++;
                }
            }
        }

        return playerCount > 0 ? totalCards / playerCount : 0;
    }

    /**
     * Get max opponent zapzap risk from probability tracker
     * @returns {number} Maximum zapzap risk (0-1)
     */
    getMaxOpponentZapZapRisk() {
        const opponentThreats = this.probabilityTracker.getOpponentThreats();
        if (opponentThreats.length === 0) return 0;
        return Math.max(...opponentThreats.map(t => t.zapZapRisk));
    }

    /**
     * STRATEGY 10: Strategic zapzap decision with aggressive and defensive modes
     * - Aggressive: Call ZapZap immediately when at <=5 and opponents have many cards
     *   (maximizes their penalty score since they have many cards to count)
     * - Defensive: Avoid ZapZap when opponents are close to calling (high counter risk)
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Can't zapzap if hand value > 5
        if (handValue > 5) {
            return false;
        }

        // Always zapzap if hand value is 0 - guaranteed win
        if (handValue === 0) {
            return true;
        }

        const botPlayerIndex = gameState.currentTurn;
        this.botPlayerIndex = botPlayerIndex;

        // Update probability tracker if not already updated this turn
        this.updateMemory(gameState, hand);

        const avgOpponentCards = this.getAverageOpponentHandSize(gameState, botPlayerIndex);
        const maxZapZapRisk = this.getMaxOpponentZapZapRisk();

        // STRATEGY 10 - DEFENSIVE MODE:
        // If an opponent is close to ZapZap (high risk), be very conservative
        // Only call ZapZap if we have very low hand value (1-2 points)
        if (maxZapZapRisk >= this.params.defensiveZapZapRiskThreshold) {
            // High risk of being countered - opponent might have lower hand
            // Only ZapZap if we have extremely low value (likely to win anyway)
            if (handValue <= this.params.defensiveZapZapMaxHandValue) {
                return true; // Still safe to call with 1-2 points
            }
            // Otherwise, too risky - don't call ZapZap
            return false;
        }

        // STRATEGY 10 - AGGRESSIVE MODE:
        // If opponents have many cards, call ZapZap immediately to maximize their penalty
        // When opponents have 3+ cards each, their hand values are likely high
        // Calling ZapZap forces them to count all their cards as penalty
        if (avgOpponentCards >= this.params.aggressiveZapZapMinOpponentCards) {
            // Great opportunity - opponents have many cards, maximize their penalty!
            // ZapZap eligibility already checked above (handValue <= 5)
            return true;
        }

        // Standard zapzap logic for other cases
        // Very confident zapzap at value <= 2
        if (handValue <= 2) {
            return true;
        }

        // Strategic zapzap at value 3-5 based on game state
        // Consider round number: earlier rounds = more conservative
        const roundNumber = gameState.roundNumber || 1;

        if (roundNumber <= 2) {
            // Early game: only zapzap with very low values
            return handValue <= 2;
        } else if (roundNumber <= 4) {
            // Mid game: moderate risk
            return handValue <= 3;
        } else {
            // Late game: more aggressive
            return handValue <= 4;
        }
    }

    /**
     * Intelligent draw decision with Joker priority and probability awareness
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string}
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        // Update memory before making decision (pass hand for probability tracker)
        this.updateMemory(gameState, hand);

        if (!Array.isArray(lastCardsPlayed) || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        const botPlayerIndex = gameState.currentTurn;
        const opponentsHaveMoreThan3 = this.allOpponentsHaveMoreThan(gameState, botPlayerIndex, 3);
        const isGoldenScore = gameState.isGoldenScore || false;

        // VINCE STRATEGY 6: During Golden Score, ALWAYS pick up Jokers from discard
        // Accumulate Jokers to deny them to opponent - you'll keep them and never play them
        // This forces opponent to either play their Jokers (giving you advantage) or keep them
        const jokersInDiscard = lastCardsPlayed.filter(cardId => CardAnalyzer.isJoker(cardId));
        if (jokersInDiscard.length > 0 && isGoldenScore) {
            // ALWAYS pick up Jokers during Golden Score - hoard them!
            return 'played';
        }

        // STRATEGY 10 - COUNTER-ZAPZAP JOKER PICKUP:
        // If our hand value is very low (1-2 points) and opponents are close to ZapZap,
        // picking up a Joker is excellent because:
        // 1. If opponent calls ZapZap, we likely have lower hand and they get countered (+20 penalty)
        // 2. The Joker becomes worth 0 points for us (we have lowest hand)
        // 3. If we call ZapZap, opponent gets the 25-point Joker penalty
        const handValue = CardAnalyzer.calculateHandValue(hand);
        const maxZapZapRisk = this.getMaxOpponentZapZapRisk();

        if (jokersInDiscard.length > 0 &&
            handValue <= this.params.counterZapZapMaxHandValue &&
            maxZapZapRisk > 0.3) {
            // Great opportunity for counter-ZapZap!
            // With 1-2 points in hand, we're likely to win even if opponent calls ZapZap
            // And the Joker will hurt them, not us
            return 'played';
        }

        // VINCE STRATEGY 5: Priority Joker pickup when opponents have > 2 cards (outside Golden Score)
        if (jokersInDiscard.length > 0 && opponentsHaveMoreThan3) {
            // Strongly prefer picking up the Joker
            return 'played';
        }

        // STRATEGY 8: Calculate expected value of drawing from deck
        const deckExpectedValue = this.probabilityTracker.calculateDeckDrawExpectedValue(hand);

        // Evaluate each discard card's value with probability awareness
        let bestDiscardCard = null;
        let bestImprovement = 0;

        for (const discardCard of lastCardsPlayed) {
            const improvement = this.evaluateCardValueWithProbability(discardCard, hand, gameState);

            if (improvement > bestImprovement) {
                bestImprovement = improvement;
                bestDiscardCard = discardCard;
            }
        }

        // STRATEGY 8: Compare discard value with expected deck value
        // If deck has higher expected value, prefer deck
        const deckBonus = deckExpectedValue.totalExpectedValue * this.params.deckProbabilityWeight / 100;

        // If any discard card provides significant improvement over deck expected value
        if (bestImprovement > this.params.discardPickupThreshold + deckBonus) {
            return 'played';
        }

        // Default to deck
        return 'deck';
    }

    /**
     * Evaluate how valuable a card would be with probability awareness
     * @param {number} cardId - Card to evaluate
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @returns {number} Value score (higher = better)
     */
    evaluateCardValueWithProbability(cardId, hand, gameState) {
        const botPlayerIndex = gameState.currentTurn;
        const opponentsHaveMoreThan3 = this.allOpponentsHaveMoreThan(gameState, botPlayerIndex, 3);

        const testHand = [...hand, cardId];

        // Count how many new multi-card combinations this creates
        const originalPlays = CardAnalyzer.findAllValidPlays(hand);
        const newPlays = CardAnalyzer.findAllValidPlays(testHand);

        const originalMultiCardPlays = originalPlays.filter(p => p.length > 1).length;
        const newMultiCardPlays = newPlays.filter(p => p.length > 1 && p.includes(cardId)).length;

        let combinationBonus = (newMultiCardPlays - originalMultiCardPlays) * this.params.combinationBonusMultiplier;

        // Prefer low-value cards (helps with zapzap)
        const cardPoints = CardAnalyzer.getCardPoints(cardId);
        const lowValueBonus = (10 - cardPoints);

        // Prefer cards that complete sequences or sets
        const rank = CardAnalyzer.getRank(cardId);
        const sameRankCount = hand.filter(id =>
            !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === rank
        ).length;

        let setBonus = sameRankCount >= 1 ? sameRankCount * this.params.setBonusMultiplier : 0;

        // VINCE STRATEGY 4: Probability adjustment based on played cards memory
        if (!CardAnalyzer.isJoker(cardId)) {
            const sameRankPlayedCount = this.playedCardsHistory.filter(playedId =>
                !CardAnalyzer.isJoker(playedId) && CardAnalyzer.getRank(playedId) === rank
            ).length;

            // If many cards of this rank have been played, it's harder to find more
            // Total of 4 cards per rank (one per suit)
            // If 2+ already played, probability of drawing another is low
            if (sameRankPlayedCount >= 2) {
                setBonus = Math.max(0, setBonus + this.params.setBonusReduction); // Reduce bonus
            }
            if (sameRankPlayedCount >= 3) {
                setBonus = 0; // No bonus, very unlikely to find another
                combinationBonus = Math.max(0, combinationBonus + this.params.combinationBonusReduction);
            }

            // STRATEGY 8: Use probability tracker for more accurate assessment
            const probInDeck = this.probabilityTracker.getProbabilityOfRankInDeck(rank);
            if (probInDeck < 0.25 && sameRankCount === 1) {
                // Low probability of finding another card of this rank
                // Penalize picking up a card that won't complete a set
                combinationBonus += this.params.lowProbabilityPenalty;
            }
        }

        // VINCE STRATEGY 6: During Golden Score, Jokers are EXTREMELY valuable to hoard
        // Pick them up to deny them to opponent and keep them forever (never play them)
        const isGoldenScore = gameState.isGoldenScore || false;
        if (CardAnalyzer.isJoker(cardId)) {
            if (isGoldenScore) {
                // Extreme bonus during Golden Score - ALWAYS pick up Jokers to hoard them
                return this.params.goldenScoreJokerPickupBonus;
            }

            // STRATEGY 10 - COUNTER-ZAPZAP JOKER EVALUATION:
            // If our hand value is very low (1-2 points), picking Joker is great for counter
            const currentHandValue = CardAnalyzer.calculateHandValue(hand);
            const opponentThreats = this.probabilityTracker.getOpponentThreats();
            const maxZapZapRisk = opponentThreats.length > 0
                ? Math.max(...opponentThreats.map(t => t.zapZapRisk))
                : 0;

            if (currentHandValue <= this.params.counterZapZapMaxHandValue && maxZapZapRisk > 0.3) {
                // Excellent for counter-ZapZap - high bonus
                return this.params.counterZapZapJokerBonus;
            }

            if (opponentsHaveMoreThan3) {
                combinationBonus += this.params.jokerSequenceBonusEarly; // Jokers valuable for sequences/combos
            } else {
                // Heavy penalty - Jokers are 25 point liability when opponent is close to zapzap
                // Override all other bonuses to strongly discourage pickup
                return this.params.jokerPenaltyNearZapZap;
            }
        }

        // STRATEGY 9: Consider if opponent likely wants this card
        const threatsForBlock = this.probabilityTracker.getOpponentThreats();
        for (const threat of threatsForBlock) {
            if (threat.likelyRanks.includes(rank)) {
                // Picking up this card denies it to opponent
                combinationBonus += this.params.blockOpponentBonus * threat.zapZapRisk;
            }
        }

        return combinationBonus + lowValueBonus + setBonus;
    }

    /**
     * Select strategic hand size (max cards = easier to deploy strategies)
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        // Hard bot prefers fewer cards for faster zapzap potential
        // But not always minimum to add some unpredictability
        if (isGoldenScore) {
            // Golden Score: prefer 8-10 cards
            return 8 + Math.floor(Math.random() * 3); // 8, 9, or 10
        }
        // Normal game: prefer 6-7 cards (maximum or near maximum)
        return 6 + Math.floor(Math.random() * 2); // 6 or 7
    }
}

module.exports = HardVinceBotStrategy;
