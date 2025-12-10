/**
 * CardProbabilityTracker
 * Advanced card counting and opponent modeling system
 *
 * Strategy 8: Enhanced Card Counting - Probability calculation for cards in deck
 * Strategy 9: Opponent Hand Modeling - Estimate opponent hands based on their actions
 *
 * Tracks:
 * - All cards that have been seen (played, discarded, in own hand)
 * - Probability of each card being in the deck vs opponent hands
 * - Opponent behavior patterns (what they pick, what they avoid)
 * - Estimated opponent hand compositions
 */

const CardAnalyzer = require('./CardAnalyzer');

class CardProbabilityTracker {
    /**
     * Total cards in a standard deck with jokers
     */
    static TOTAL_CARDS = 54; // 52 + 2 jokers
    static CARDS_PER_RANK = 4; // One per suit
    static JOKER_COUNT = 2;

    constructor() {
        this.reset();
    }

    /**
     * Reset all tracking state (call at start of new round)
     */
    reset() {
        // Cards we know for certain
        this.knownCards = {
            inMyHand: new Set(),           // Cards in bot's hand
            played: new Set(),              // Cards played and gone to discard/reshuffled
            inDiscard: new Set(),           // Cards currently visible in discard pile
        };

        // Opponent modeling
        this.opponents = {}; // playerIndex -> OpponentModel

        // Deck state
        this.deckSize = 0;
        this.lastKnownDeckSize = null;
        this.reshuffleDetected = false;

        // Game context
        this.totalPlayers = 4;
        this.botPlayerIndex = null;
    }

    /**
     * Initialize opponent models
     * @param {number} totalPlayers - Number of players in game
     * @param {number} botIndex - Bot's player index
     */
    initializeOpponents(totalPlayers, botIndex) {
        this.totalPlayers = totalPlayers;
        this.botPlayerIndex = botIndex;

        for (let i = 0; i < totalPlayers; i++) {
            if (i !== botIndex) {
                this.opponents[i] = new OpponentModel(i);
            }
        }
    }

    /**
     * Update tracking based on game state
     * @param {Object} gameState - Current game state
     * @param {Array<number>} myHand - Bot's current hand
     */
    update(gameState, myHand) {
        const botIndex = gameState.currentTurn;

        // Initialize opponents if needed
        if (Object.keys(this.opponents).length === 0) {
            const playerCount = Object.keys(gameState.hands || {}).length;
            this.initializeOpponents(playerCount, botIndex);
        }

        // Detect reshuffle
        const currentDeckSize = gameState.deck ? gameState.deck.length : 0;
        if (this.lastKnownDeckSize !== null && currentDeckSize > this.lastKnownDeckSize + 5) {
            this.onReshuffle();
        }
        this.lastKnownDeckSize = currentDeckSize;
        this.deckSize = currentDeckSize;

        // Update known cards in my hand
        this.knownCards.inMyHand = new Set(myHand);

        // Update discard pile
        if (gameState.lastCardsPlayed) {
            this.knownCards.inDiscard = new Set(gameState.lastCardsPlayed);
            // Also mark them as played
            for (const cardId of gameState.lastCardsPlayed) {
                this.knownCards.played.add(cardId);
            }
        }

        // Track last action for opponent modeling
        const lastAction = gameState.lastAction;
        if (lastAction && lastAction.playerIndex !== botIndex) {
            this.processOpponentAction(lastAction, gameState);
        }

        // Update opponent hand sizes
        const hands = gameState.hands || {};
        for (const [indexStr, hand] of Object.entries(hands)) {
            const playerIndex = parseInt(indexStr, 10);
            if (this.opponents[playerIndex]) {
                this.opponents[playerIndex].updateHandSize(
                    Array.isArray(hand) ? hand.length : 0
                );
            }
        }
    }

    /**
     * Handle deck reshuffle - reset played cards but keep opponent models
     */
    onReshuffle() {
        this.reshuffleDetected = true;
        this.knownCards.played.clear();
        this.knownCards.inDiscard.clear();

        // Opponent models maintain their behavioral patterns
        // but reset certainty about specific cards
        for (const opponent of Object.values(this.opponents)) {
            opponent.onReshuffle();
        }
    }

    /**
     * Process an opponent's action to update their model
     * @param {Object} action - The action taken
     * @param {Object} gameState - Current game state
     */
    processOpponentAction(action, gameState) {
        const opponent = this.opponents[action.playerIndex];
        if (!opponent) return;

        switch (action.type) {
            case 'draw':
                if (action.source === 'played' && action.cardId !== undefined) {
                    // Opponent picked specific card from discard
                    opponent.recordPickup(action.cardId);
                    // Remove from discard
                    this.knownCards.inDiscard.delete(action.cardId);
                } else if (action.source === 'deck') {
                    // Opponent drew from deck - we don't know what they got
                    opponent.recordDeckDraw();
                }
                break;

            case 'play':
                if (action.cards && action.cards.length > 0) {
                    // Opponent played cards - we now know they had these
                    opponent.recordPlay(action.cards);
                    // Add to played cards
                    for (const cardId of action.cards) {
                        this.knownCards.played.add(cardId);
                    }
                }
                break;

            case 'zapzap':
                // Opponent called zapzap - their hand value is <= 5
                opponent.recordZapZap();
                break;
        }
    }

    /**
     * STRATEGY 8: Calculate probability of a card being in the deck
     * @param {number} cardId - Card to check
     * @returns {number} Probability 0-1
     */
    getProbabilityInDeck(cardId) {
        // If we can see the card, probability is 0
        if (this.knownCards.inMyHand.has(cardId)) return 0;
        if (this.knownCards.inDiscard.has(cardId)) return 0;
        if (this.knownCards.played.has(cardId) && !this.reshuffleDetected) return 0;

        // Calculate unknown cards
        const totalKnown = this.knownCards.inMyHand.size +
            this.knownCards.inDiscard.size +
            (this.reshuffleDetected ? 0 : this.knownCards.played.size);

        const unknownCards = CardProbabilityTracker.TOTAL_CARDS - totalKnown;

        if (unknownCards <= 0) return 0;

        // Cards are distributed between deck and opponent hands
        // Deck has deckSize cards, opponents have the rest of unknown cards
        const cardsInOpponentHands = unknownCards - this.deckSize;

        // Simple probability: deck cards / unknown cards
        // This assumes uniform distribution
        return Math.max(0, Math.min(1, this.deckSize / unknownCards));
    }

    /**
     * STRATEGY 8: Get probability of drawing a card of specific rank from deck
     * @param {number} rank - Rank (0-12)
     * @returns {number} Probability 0-1
     */
    getProbabilityOfRankInDeck(rank) {
        let availableCount = 0;
        let totalAvailable = 0;

        // Check all 4 cards of this rank (one per suit)
        for (let suit = 0; suit < 4; suit++) {
            const cardId = suit * 13 + rank;
            const prob = this.getProbabilityInDeck(cardId);
            if (prob > 0) {
                availableCount += prob;
            }
        }

        return availableCount / 4; // Average probability
    }

    /**
     * STRATEGY 8: Calculate expected value of drawing from deck
     * @param {Array<number>} myHand - Current hand
     * @returns {Object} Expected outcomes
     */
    calculateDeckDrawExpectedValue(myHand) {
        let expectedCombos = 0;
        let expectedSetImprovement = 0;
        let expectedSequenceImprovement = 0;

        // For each unknown card that might be in deck
        for (let cardId = 0; cardId < 54; cardId++) {
            const probInDeck = this.getProbabilityInDeck(cardId);
            if (probInDeck <= 0) continue;

            // Check how this card would improve our hand
            const rank = CardAnalyzer.getRank(cardId);
            const suit = CardAnalyzer.getSuit(cardId);

            // Set improvement: same rank cards
            const sameRankCount = myHand.filter(id =>
                !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === rank
            ).length;

            if (sameRankCount >= 1) {
                expectedSetImprovement += probInDeck * sameRankCount;
            }

            // Sequence improvement: adjacent cards in same suit
            const adjacentCount = myHand.filter(id => {
                if (CardAnalyzer.isJoker(id)) return false;
                if (CardAnalyzer.getSuit(id) !== suit) return false;
                const r = CardAnalyzer.getRank(id);
                return Math.abs(r - rank) <= 2;
            }).length;

            if (adjacentCount >= 1) {
                expectedSequenceImprovement += probInDeck * adjacentCount;
            }

            // General combo potential
            if (sameRankCount >= 1 || adjacentCount >= 2) {
                expectedCombos += probInDeck;
            }
        }

        return {
            expectedCombos,
            expectedSetImprovement,
            expectedSequenceImprovement,
            totalExpectedValue: expectedCombos * 10 + expectedSetImprovement * 5 + expectedSequenceImprovement * 3
        };
    }

    /**
     * STRATEGY 9: Get estimated hand composition for opponent
     * @param {number} playerIndex - Opponent player index
     * @returns {Object} Estimated hand information
     */
    getOpponentEstimate(playerIndex) {
        const opponent = this.opponents[playerIndex];
        if (!opponent) {
            return {
                handSize: 0,
                likelyHasJoker: false,
                estimatedValue: 50,
                likelyRanks: [],
                threatLevel: 'unknown'
            };
        }

        return opponent.getEstimate();
    }

    /**
     * STRATEGY 9: Estimate probability opponent has specific card
     * @param {number} playerIndex - Opponent index
     * @param {number} cardId - Card ID
     * @returns {number} Probability 0-1
     */
    getProbabilityOpponentHas(playerIndex, cardId) {
        const opponent = this.opponents[playerIndex];
        if (!opponent) return 0;

        // If card is visible/known elsewhere, probability is 0
        if (this.knownCards.inMyHand.has(cardId)) return 0;
        if (this.knownCards.inDiscard.has(cardId)) return 0;
        if (this.knownCards.played.has(cardId) && !this.reshuffleDetected) return 0;

        // Check if opponent picked this card from discard
        if (opponent.pickedCards.has(cardId)) {
            // High probability they still have it (unless they played something)
            return 0.8;
        }

        // Base probability: their hand size / unknown cards
        const unknownCards = CardProbabilityTracker.TOTAL_CARDS -
            this.knownCards.inMyHand.size -
            this.knownCards.inDiscard.size -
            (this.reshuffleDetected ? 0 : this.knownCards.played.size);

        if (unknownCards <= 0) return 0;

        return Math.min(1, opponent.handSize / unknownCards);
    }

    /**
     * STRATEGY 9: Get threat assessment for all opponents
     * @returns {Array<Object>} Sorted list of opponents by threat level
     */
    getOpponentThreats() {
        const threats = [];

        for (const [indexStr, opponent] of Object.entries(this.opponents)) {
            const estimate = opponent.getEstimate();
            threats.push({
                playerIndex: parseInt(indexStr, 10),
                ...estimate
            });
        }

        // Sort by threat level (lower estimated value = higher threat)
        threats.sort((a, b) => a.estimatedValue - b.estimatedValue);

        return threats;
    }

    /**
     * Get summary statistics for debugging/logging
     * @returns {Object} Summary
     */
    getSummary() {
        return {
            knownCardsCount: this.knownCards.inMyHand.size +
                this.knownCards.inDiscard.size +
                this.knownCards.played.size,
            deckSize: this.deckSize,
            reshuffleDetected: this.reshuffleDetected,
            opponentCount: Object.keys(this.opponents).length,
            opponents: Object.fromEntries(
                Object.entries(this.opponents).map(([idx, opp]) => [
                    idx, opp.getEstimate()
                ])
            )
        };
    }
}

/**
 * OpponentModel
 * Tracks a single opponent's behavior and estimates their hand
 */
class OpponentModel {
    constructor(playerIndex) {
        this.playerIndex = playerIndex;
        this.handSize = 0;

        // Cards we know they picked from discard
        this.pickedCards = new Set();

        // Cards they've played
        this.playedCards = [];

        // Behavior patterns
        this.drawFromDiscardCount = 0;
        this.drawFromDeckCount = 0;
        this.totalPlaysCount = 0;
        this.multiCardPlayCount = 0;
        this.zapZapCalled = false;

        // Rank preferences (which ranks they tend to pick/keep)
        this.preferredRanks = {}; // rank -> count of picks

        // Estimated hand value range
        this.estimatedMinValue = 0;
        this.estimatedMaxValue = 100;
    }

    /**
     * Reset certainties on reshuffle (keep behavioral patterns)
     */
    onReshuffle() {
        this.pickedCards.clear();
        // Keep behavioral patterns
    }

    /**
     * Update hand size
     * @param {number} size - Current hand size
     */
    updateHandSize(size) {
        const previousSize = this.handSize;
        this.handSize = size;

        // If hand size decreased significantly, they played cards
        if (previousSize - size >= 2) {
            this.multiCardPlayCount++;
        }
    }

    /**
     * Record when opponent picks card from discard
     * @param {number} cardId - Card they picked
     */
    recordPickup(cardId) {
        this.pickedCards.add(cardId);
        this.drawFromDiscardCount++;

        // Track rank preference
        if (!CardAnalyzer.isJoker(cardId)) {
            const rank = CardAnalyzer.getRank(cardId);
            this.preferredRanks[rank] = (this.preferredRanks[rank] || 0) + 1;
        }

        // They picked this card for a reason - they likely have related cards
        this.updateEstimateFromPickup(cardId);
    }

    /**
     * Record when opponent draws from deck
     */
    recordDeckDraw() {
        this.drawFromDeckCount++;
    }

    /**
     * Record when opponent plays cards
     * @param {Array<number>} cards - Cards played
     */
    recordPlay(cards) {
        this.playedCards.push(...cards);
        this.totalPlaysCount++;

        if (cards.length >= 2) {
            this.multiCardPlayCount++;
        }

        // Remove from picked cards if present
        for (const cardId of cards) {
            this.pickedCards.delete(cardId);
        }

        // Update estimate based on what they played
        this.updateEstimateFromPlay(cards);
    }

    /**
     * Record zapzap call
     */
    recordZapZap() {
        this.zapZapCalled = true;
        this.estimatedMaxValue = 5;
    }

    /**
     * Update estimate when opponent picks a card
     * @param {number} cardId - Card picked
     */
    updateEstimateFromPickup(cardId) {
        // If they picked a card, they likely have related cards (same rank or sequence)
        // This increases likelihood they're building combos
        if (CardAnalyzer.isJoker(cardId)) {
            // Joker pickup - they either have few cards or are building combos
            // Slightly lower their estimated value (jokers help)
            this.estimatedMaxValue = Math.max(this.estimatedMinValue,
                this.estimatedMaxValue - 5);
        }
    }

    /**
     * Update estimate based on cards played
     * @param {Array<number>} cards - Cards played
     */
    updateEstimateFromPlay(cards) {
        // Playing high value cards suggests they have lower value cards left
        const playValue = CardAnalyzer.calculateHandValue(cards);

        if (playValue >= 20) {
            // Playing lots of high cards - their hand is getting lighter
            this.estimatedMaxValue = Math.max(this.estimatedMinValue,
                this.estimatedMaxValue - playValue / 2);
        }

        // Playing combos (2+ cards) suggests organized hand
        if (cards.length >= 2) {
            this.estimatedMaxValue = Math.max(this.estimatedMinValue,
                this.estimatedMaxValue - 10);
        }
    }

    /**
     * Get estimated hand information
     * @returns {Object} Estimate
     */
    getEstimate() {
        // Calculate threat level
        let threatLevel = 'low';
        if (this.handSize <= 3) {
            threatLevel = 'high';
        } else if (this.handSize <= 5) {
            threatLevel = 'medium';
        }

        // Estimate value based on hand size and behavior
        const baseEstimate = this.handSize * 7; // Average ~7 points per card
        const adjustedEstimate = Math.max(
            this.estimatedMinValue,
            Math.min(this.estimatedMaxValue, baseEstimate)
        );

        // Likely has joker if they picked one or if hand is small with low estimate
        const likelyHasJoker = Array.from(this.pickedCards).some(id =>
            CardAnalyzer.isJoker(id)
        ) || (this.handSize <= 3 && adjustedEstimate <= 5);

        // Most likely ranks in their hand
        const likelyRanks = Object.entries(this.preferredRanks)
            .sort((a, b) => b[1] - a[1])
            .slice(0, 3)
            .map(([rank]) => parseInt(rank, 10));

        return {
            handSize: this.handSize,
            likelyHasJoker,
            estimatedValue: adjustedEstimate,
            likelyRanks,
            threatLevel,
            pickedCardsCount: this.pickedCards.size,
            playStyle: this.getPlayStyle(),
            zapZapRisk: this.calculateZapZapRisk()
        };
    }

    /**
     * Determine opponent's play style
     * @returns {string} Play style description
     */
    getPlayStyle() {
        if (this.totalPlaysCount === 0) return 'unknown';

        const multiCardRatio = this.multiCardPlayCount / this.totalPlaysCount;
        const discardPickRatio = this.drawFromDiscardCount /
            (this.drawFromDiscardCount + this.drawFromDeckCount || 1);

        if (multiCardRatio > 0.5 && discardPickRatio > 0.5) {
            return 'combo_builder'; // Builds combos, picks strategically
        } else if (multiCardRatio > 0.5) {
            return 'aggressive'; // Plays combos frequently
        } else if (discardPickRatio > 0.7) {
            return 'opportunistic'; // Takes advantage of discards
        } else if (this.drawFromDeckCount > 10) {
            return 'conservative'; // Prefers deck draws
        }

        return 'balanced';
    }

    /**
     * Calculate risk of opponent calling zapzap soon
     * @returns {number} Risk score 0-1
     */
    calculateZapZapRisk() {
        if (this.zapZapCalled) return 1;

        // Base risk on hand size
        let risk = 0;
        if (this.handSize <= 2) risk = 0.8;
        else if (this.handSize <= 3) risk = 0.5;
        else if (this.handSize <= 4) risk = 0.3;
        else if (this.handSize <= 5) risk = 0.1;

        // Estimate value directly without calling getEstimate() to avoid recursion
        const baseEstimate = this.handSize * 7;
        const adjustedEstimate = Math.max(
            this.estimatedMinValue,
            Math.min(this.estimatedMaxValue, baseEstimate)
        );

        // Adjust based on estimated value
        if (adjustedEstimate <= 5) risk = Math.max(risk, 0.7);
        else if (adjustedEstimate <= 10) risk = Math.max(risk, 0.4);

        // Check if they likely have joker
        const likelyHasJoker = Array.from(this.pickedCards).some(id =>
            CardAnalyzer.isJoker(id)
        ) || (this.handSize <= 3 && adjustedEstimate <= 5);

        // If they have joker(s), risk is higher
        if (likelyHasJoker) {
            risk = Math.min(1, risk + 0.2);
        }

        return risk;
    }
}

module.exports = CardProbabilityTracker;
