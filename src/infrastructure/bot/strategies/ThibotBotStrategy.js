/**
 * ThibotBotStrategy
 * Probability-based bot strategy using the native Rust implementation
 *
 * Key features:
 * - Tracks all played cards (full discard pile knowledge)
 * - Tracks cards taken by other players from the discard
 * - Uses probabilities to maximize points removed per turn
 * - Goal: reach low hand value quickly for ZapZap
 * - Safeguard: discard max points if opponent is close to ZapZap
 * - Coordinated play/draw decisions for better combos
 *
 * Parameters optimized via genetic algorithm achieving 44.25% winrate vs HardBots
 * Optimization: 30 generations, 2000 games/eval, 872k total games
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');

// Try to load native module, fallback to JS implementation if not available
let native = null;
try {
    native = require('../../../../native');
} catch (e) {
    console.warn('Native module not available for Thibot, using JS fallback');
}

class ThibotBotStrategy extends BotStrategy {
    constructor() {
        super('thibot');

        // Track game state for probability calculations
        this.playedCards = new Set();
        this.opponentTakenCards = new Map(); // Map<playerIndex, Set<cardId>>
        this.currentRound = 0;

        // CardTracker: Track all visible cards (like Rust implementation)
        // Cards in discard pile, last_cards_played, and cards_played are all visible
        this.discardPile = [];          // Full discard pile (all cards played to discard)
        this.lastCardsPlayed = [];      // Last play visible (top of discard)
        this.cardsPlayed = [];          // Current turn's played cards
        this.playerTakenCards = [];     // Bitmask-like tracking: Array of Sets per player

        // Coordinated decision between selectPlay and selectDrawSource
        // Stores: { play, drawSource, targetCard, reason }
        this.coordinatedDecision = null;

        // Coordination parameters (genetically optimized - 44.25% winrate)
        this.coordParams = {
            futureValueDiscount: 91,           // % (91 = 0.91) - high value for future plays
            riskPenaltyMultiplier: 17,         // % multiplier for risk (low = more coordination)
            coordinationThreshold: 6,           // Min score improvement to prefer coordination
            holdPairForThreeBonus: 226,         // Bonus for holding pair for 3-of-a-kind
            holdSequenceForExtendBonus: 114,    // Bonus for extending sequence
        };
    }

    /**
     * Reset tracking for new game/round
     */
    reset() {
        this.playedCards.clear();
        this.opponentTakenCards.clear();
        this.discardPile = [];
        this.lastCardsPlayed = [];
        this.cardsPlayed = [];
        this.playerTakenCards = [];
    }

    /**
     * Update card tracker from game state
     * Should be called at the start of selectPlay to sync with current game state
     * Uses the full discardPile from gameState (all cards played this round)
     * @param {Object} gameState - Current game state
     */
    updateCardTracker(gameState) {
        // Track round changes to reset on new round
        const roundNumber = gameState.roundNumber || 0;
        if (roundNumber !== this.currentRound) {
            // New round - reset all tracking
            this.reset();
            this.currentRound = roundNumber;
        }

        // Sync directly from gameState - use ALL visible cards
        // discardPile contains all cards played this round (except lastCardsPlayed)
        if (gameState.discardPile) {
            this.discardPile = [...gameState.discardPile];
        }
        if (gameState.lastCardsPlayed) {
            this.lastCardsPlayed = [...gameState.lastCardsPlayed];
        }
        if (gameState.cardsPlayed) {
            this.cardsPlayed = [...gameState.cardsPlayed];
        }

        // Update playedCards set for compatibility with old countDrawableRank fallback
        this.playedCards.clear();
        for (const cardId of this.discardPile) {
            this.playedCards.add(cardId);
        }
        for (const cardId of this.lastCardsPlayed) {
            this.playedCards.add(cardId);
        }
        for (const cardId of this.cardsPlayed) {
            this.playedCards.add(cardId);
        }
    }

    /**
     * Track a card taken from played pile by a player
     * @param {number} playerIndex - Player who took the card
     * @param {number} cardId - Card that was taken
     */
    trackCardTaken(playerIndex, cardId) {
        while (this.playerTakenCards.length <= playerIndex) {
            this.playerTakenCards.push(new Set());
        }
        this.playerTakenCards[playerIndex].add(cardId);
    }

    /**
     * Track cards played by a player (remove from taken tracking)
     * @param {number} playerIndex - Player who played the cards
     * @param {Array<number>} cards - Cards that were played
     */
    trackCardsPlayed(playerIndex, cards) {
        if (playerIndex < this.playerTakenCards.length) {
            for (const cardId of cards) {
                this.playerTakenCards[playerIndex].delete(cardId);
            }
        }
    }

    /**
     * Count how many cards of a specific rank are visible
     * (in discard pile + last_cards_played + cards_played)
     * Rank: 0-12 (A=0, 2=1, ..., K=12), 13 = Joker
     * @param {number} rank - Card rank (0-12, or 13 for jokers)
     * @returns {number} Count of visible cards (0-4 for normal, 0-2 for jokers)
     */
    countVisibleRank(rank) {
        let count = 0;

        // Count in discard pile
        for (const card of this.discardPile) {
            if (CardAnalyzer.isJoker(card)) {
                if (rank === 13) count++;
            } else if (CardAnalyzer.getRank(card) === rank) {
                count++;
            }
        }

        // Count in last_cards_played (visible)
        for (const card of this.lastCardsPlayed) {
            if (CardAnalyzer.isJoker(card)) {
                if (rank === 13) count++;
            } else if (CardAnalyzer.getRank(card) === rank) {
                count++;
            }
        }

        // Count in cards_played (current turn, also visible)
        for (const card of this.cardsPlayed) {
            if (CardAnalyzer.isJoker(card)) {
                if (rank === 13) count++;
            } else if (CardAnalyzer.getRank(card) === rank) {
                count++;
            }
        }

        return count;
    }

    /**
     * Count remaining cards of a rank that could be drawn
     * If 3 jacks are in discard, only 1 jack can be drawn
     * @param {number} rank - Card rank (0-12, or 13 for jokers)
     * @param {Array<number>} hand - Current hand (to exclude)
     * @returns {number} Number of drawable cards
     */
    countDrawableRankWithTracker(rank, hand) {
        const maxCards = (rank === 13) ? 2 : 4;  // 2 jokers, 4 of each rank
        const visible = this.countVisibleRank(rank);

        // Also subtract cards in hand
        let inHand = 0;
        for (const cardId of hand) {
            if (CardAnalyzer.isJoker(cardId)) {
                if (rank === 13) inHand++;
            } else if (CardAnalyzer.getRank(cardId) === rank) {
                inHand++;
            }
        }

        return Math.max(0, maxCards - visible - inHand);
    }

    /**
     * Get probability of drawing a specific rank from deck
     * @param {number} rank - Card rank (0-12, or 13 for jokers)
     * @param {Array<number>} hand - Current hand
     * @param {number} deckSize - Size of the deck
     * @returns {number} Probability (0.0 to 1.0)
     */
    drawProbability(rank, hand, deckSize) {
        const drawable = this.countDrawableRankWithTracker(rank, hand);
        if (deckSize === 0) return 0;
        return drawable / deckSize;
    }

    /**
     * Check if a rank is "dead" (all cards visible or in hand, no pair possible)
     * @param {number} rank - Card rank
     * @param {Array<number>} hand - Current hand
     * @returns {boolean}
     */
    isRankDead(rank, hand) {
        return this.countDrawableRankWithTracker(rank, hand) === 0;
    }

    /**
     * Get all cards a player has taken but not played (known to be in their hand)
     * @param {number} playerIndex - Player index
     * @returns {Array<number>} Known cards
     */
    getPlayerKnownCards(playerIndex) {
        if (playerIndex < this.playerTakenCards.length) {
            return Array.from(this.playerTakenCards[playerIndex]);
        }
        return [];
    }

    /**
     * Estimate minimum possible hand value for a player based on tracked cards
     * @param {number} playerIndex - Player index
     * @param {number} handSize - Player's hand size
     * @returns {number} Minimum possible hand value
     */
    estimateMinHandValue(playerIndex, handSize) {
        const knownCards = this.getPlayerKnownCards(playerIndex);
        const trackedCount = knownCards.length;

        // If we know ALL cards in their hand, calculate exact value
        if (trackedCount >= handSize && knownCards.length > 0) {
            // Get values and sort to take lowest N
            const values = knownCards.map(c => {
                if (CardAnalyzer.isJoker(c)) return 0;
                return CardAnalyzer.getCardPoints(c);
            });
            values.sort((a, b) => a - b);

            return values.slice(0, handSize).reduce((sum, v) => sum + v, 0);
        }

        // Minimum possible if we only know some cards
        // They could have drawn jokers from deck, so min is 0
        return 0;
    }

    /**
     * Track a card that was played to the discard
     * @param {number} cardId - Card that was played
     */
    trackPlayedCard(cardId) {
        this.playedCards.add(cardId);
    }

    /**
     * Track a card taken by an opponent from the discard
     * @param {number} playerIndex - Player who took the card
     * @param {number} cardId - Card that was taken
     */
    trackOpponentTake(playerIndex, cardId) {
        if (!this.opponentTakenCards.has(playerIndex)) {
            this.opponentTakenCards.set(playerIndex, new Set());
        }
        this.opponentTakenCards.get(playerIndex).add(cardId);
    }

    /**
     * Count how many cards of a rank are still drawable (not played/tracked)
     * Uses the new CardTracker for accurate counting from discard pile
     * @param {number} rank - Card rank (0-12)
     * @param {Array<number>} hand - Current hand
     * @returns {number} Number of drawable cards
     */
    countDrawableRank(rank, hand) {
        // Use the new tracker-based method if we have tracker data
        if (this.discardPile.length > 0 || this.lastCardsPlayed.length > 0) {
            return this.countDrawableRankWithTracker(rank, hand);
        }

        // Fallback to old method for backward compatibility
        let count = 4; // 4 suits per rank

        // Subtract cards in hand
        for (const cardId of hand) {
            if (!CardAnalyzer.isJoker(cardId) && CardAnalyzer.getRank(cardId) === rank) {
                count--;
            }
        }

        // Subtract played cards
        for (const cardId of this.playedCards) {
            if (!CardAnalyzer.isJoker(cardId) && CardAnalyzer.getRank(cardId) === rank) {
                count--;
            }
        }

        // Subtract cards taken by opponents (we know these are in play)
        for (const takenSet of this.opponentTakenCards.values()) {
            for (const cardId of takenSet) {
                if (!CardAnalyzer.isJoker(cardId) && CardAnalyzer.getRank(cardId) === rank) {
                    count--;
                }
            }
        }

        return Math.max(0, count);
    }

    /**
     * Get minimum opponent hand size
     * @param {Object} gameState - Current game state
     * @returns {number} Minimum hand size among opponents
     */
    getMinOpponentHandSize(gameState) {
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

        return minSize === Infinity ? 10 : minSize;
    }

    /**
     * Evaluate a card's potential for future combos
     * Higher score = more valuable to keep
     * @param {number} card - Card to evaluate
     * @param {Array<number>} hand - Current hand
     * @returns {number} Potential score
     */
    evaluateCardPotential(card, hand) {
        if (CardAnalyzer.isJoker(card)) {
            return 705; // joker_keep_score (genetically optimized)
        }

        const rank = CardAnalyzer.getRank(card);
        const suit = CardAnalyzer.getSuit(card);
        const points = CardAnalyzer.getCardPoints(card);

        let score = -points; // Prefer keeping low cards

        // Check pair potential
        const drawable = this.countDrawableRank(rank, hand);
        const sameRankInHand = hand.filter(c =>
            !CardAnalyzer.isJoker(c) && CardAnalyzer.getRank(c) === rank && c !== card
        ).length;

        if (sameRankInHand >= 1) {
            score += 68; // existing_pair_bonus
        } else if (drawable >= 2) {
            score += 30; // good_pair_chance_bonus
        } else if (drawable === 1) {
            score += 12; // low_pair_chance_bonus
        } else {
            score -= 26; // dead_rank_penalty
        }

        // Check sequence potential
        const sameSuit = hand.filter(c =>
            c !== card && !CardAnalyzer.isJoker(c) && CardAnalyzer.getSuit(c) === suit
        ).map(c => CardAnalyzer.getRank(c));

        let adjacentCount = 0;
        let closeCount = 0;

        for (const otherRank of sameSuit) {
            const diff = Math.abs(rank - otherRank);
            if (diff === 1) adjacentCount++;
            else if (diff === 2) closeCount++;
        }

        const hasJoker = hand.some(c => CardAnalyzer.isJoker(c));

        if (adjacentCount >= 2) {
            score += 33; // sequence_part_bonus
        } else if (adjacentCount === 1) {
            score += 27; // potential_sequence_bonus
            if (hasJoker) {
                score += 31; // joker_sequence_bonus
            }
        } else if (closeCount >= 1 && hasJoker) {
            score += 17; // close_with_joker_bonus
        }

        return score;
    }

    // ========================================
    // COORDINATED PLAY/DRAW DECISION METHODS
    // ========================================

    /**
     * Find all valid plays that include a specific card
     * Used to evaluate what combos become possible by taking a discard card
     * @param {Array<number>} hand - Current hand
     * @param {number} cardId - Card to include in plays
     * @returns {Array<Array<number>>} Valid plays including the card
     */
    findPlaysWithCard(hand, cardId) {
        const hypotheticalHand = [...hand, cardId];
        const allPlays = CardAnalyzer.findAllValidPlays(hypotheticalHand);
        return allPlays.filter(play => play.includes(cardId));
    }

    /**
     * Score a coordinated scenario (play now + take discard + play future combo)
     * This scoring should be comparable to the normal play scoring.
     *
     * Normal play score = playValue*19 + cardCount*14 + potential/15 - jokerPenalty + zapzapBonus
     * Coordinated score = (playNow score) + (futurePlay score * discount) + coordination bonus
     *
     * @param {Array<number>} playNow - Cards to play this turn
     * @param {Array<number>} futurePlay - Cards to play next turn (including discard card)
     * @param {Array<number>} hand - Current hand
     * @param {number} discardCard - Card from discard pile
     * @param {Object} gameState - Current game state
     * @returns {number} Score for this scenario
     */
    scoreCoordinatedScenario(playNow, futurePlay, hand, discardCard, gameState) {
        // Discount factor for future value (uncertainty of getting the card, surviving until next turn)
        const discountFactor = this.coordParams.futureValueDiscount / 100;

        // === Score for playing NOW ===
        const playNowValue = CardAnalyzer.calculateHandValue(playNow);
        const jokerCountNow = playNow.filter(c => CardAnalyzer.isJoker(c)).length;
        const immediateScore = playNowValue * 15 + playNow.length * 7 - jokerCountNow * 36;

        // === Score for future play (discounted) ===
        const futurePlayValue = CardAnalyzer.calculateHandValue(futurePlay);
        const jokerCountFuture = futurePlay.filter(c => CardAnalyzer.isJoker(c)).length;
        const futureScore = (futurePlayValue * 15 + futurePlay.length * 7 - jokerCountFuture * 36) * discountFactor;

        // === Bonus for coordination patterns (making bigger combos) ===
        let coordinationBonus = 0;

        // Bonus for making a 3-of-a-kind or 4-of-a-kind
        const futurePlayRanks = futurePlay.filter(c => !CardAnalyzer.isJoker(c)).map(c => CardAnalyzer.getRank(c));
        if (futurePlay.length >= 3 && CardAnalyzer.isValidSameRank(futurePlay)) {
            coordinationBonus += this.coordParams.holdPairForThreeBonus;
            if (futurePlay.length >= 4) {
                coordinationBonus += this.coordParams.holdPairForThreeBonus / 2; // Extra for 4-of-a-kind
            }
        }

        // Bonus for extending a sequence to 4+ cards
        if (futurePlay.length >= 4 && CardAnalyzer.isValidSequence(futurePlay)) {
            coordinationBonus += this.coordParams.holdSequenceForExtendBonus;
        }

        // === Risk penalty: holding high value cards when opponent might ZapZap ===
        const minOpponentSize = this.getMinOpponentHandSize(gameState);
        const remainingAfterPlay = hand.filter(c => !playNow.includes(c));
        const remainingValue = CardAnalyzer.calculateHandValue(remainingAfterPlay);
        let riskPenalty = 0;
        if (minOpponentSize <= 3) { // defensive_threshold = 3
            riskPenalty = remainingValue * (this.coordParams.riskPenaltyMultiplier / 100);
        }

        // === Potential ZapZap bonus (if remaining hand after future play would allow ZapZap) ===
        // After playing now, we draw the discard card, then next turn we play futurePlay
        const afterNowAndDraw = [...remainingAfterPlay, discardCard];
        const afterFuturePlay = afterNowAndDraw.filter(c => !futurePlay.includes(c));
        const afterFutureValue = CardAnalyzer.calculateHandValue(afterFuturePlay);
        const zapzapBonus = afterFutureValue <= 5 ? 79 * discountFactor : 0; // zapzap_potential_bonus

        return immediateScore + futureScore + coordinationBonus + zapzapBonus - riskPenalty;
    }

    /**
     * Evaluate the "hold and take" scenario for a specific discard card
     * @param {Array<number>} hand - Current hand
     * @param {number} discardCard - Card from discard pile to evaluate
     * @param {Object} gameState - Current game state
     * @returns {Object|null} Best scenario or null if not beneficial
     */
    evaluateHoldAndTakeScenario(hand, discardCard, gameState) {
        // Find all plays that become possible with this discard card
        const playsWithDiscard = this.findPlaysWithCard(hand, discardCard);

        // Filter to only plays that are better than what we can do without the card
        // (plays with 3+ cards, or pairs that become sets)
        const valuablePlays = playsWithDiscard.filter(play => {
            // Must include cards from our hand (not just the discard card alone)
            const handCardsInPlay = play.filter(c => c !== discardCard && hand.includes(c));
            return handCardsInPlay.length >= 1 && play.length >= 2;
        });

        if (valuablePlays.length === 0) {
            return null;
        }

        let bestScenario = null;
        let bestScore = -Infinity;

        for (const futurePlay of valuablePlays) {
            // Cards from hand needed for this future play
            const cardsNeededFromHand = futurePlay.filter(c => c !== discardCard);

            // What can we play NOW while keeping cardsNeededFromHand?
            const cardsToKeep = new Set(cardsNeededFromHand);
            const playableNow = hand.filter(c => !cardsToKeep.has(c));

            // Skip if we can't play anything (need to keep all cards)
            if (playableNow.length === 0) {
                continue;
            }

            // Find valid plays from the playable cards
            let playsNow = CardAnalyzer.findAllValidPlays(playableNow);

            // If no valid combo, just play the lowest single card
            if (playsNow.length === 0) {
                const lowestCard = playableNow.reduce((lowest, c) => {
                    return CardAnalyzer.getCardPoints(c) < CardAnalyzer.getCardPoints(lowest) ? c : lowest;
                });
                playsNow = [[lowestCard]];
            }

            for (const playNow of playsNow) {
                const score = this.scoreCoordinatedScenario(playNow, futurePlay, hand, discardCard, gameState);

                if (score > bestScore) {
                    bestScore = score;
                    bestScenario = {
                        playNow,
                        futurePlay,
                        discardCard,
                        score,
                        isCoordinated: true,
                        reason: `Hold for ${futurePlay.length}-card combo`
                    };
                }
            }
        }

        return bestScenario;
    }

    /**
     * Evaluate all coordination scenarios and compare with normal play
     * @param {Array<number>} hand - Current hand
     * @param {Array<number>} lastCardsPlayed - Available discard cards
     * @param {Object} gameState - Current game state
     * @returns {Object} Best scenario (coordinated or normal)
     */
    evaluateCoordinatedScenarios(hand, lastCardsPlayed, gameState) {
        // First, calculate the "normal" play scenario score
        const normalPlay = this.findBestOffensivePlay(hand);
        let normalScore = -Infinity;

        if (normalPlay) {
            const playValue = CardAnalyzer.calculateHandValue(normalPlay);
            const remaining = hand.filter(c => !normalPlay.includes(c));
            let remainingPotential = 0;
            for (const c of remaining) {
                remainingPotential += this.evaluateCardPotential(c, remaining);
            }

            const jokerCount = normalPlay.filter(c => CardAnalyzer.isJoker(c)).length;
            const remainingValue = CardAnalyzer.calculateHandValue(remaining);
            const zapzapBonus = remainingValue <= 5 ? 79 : 0; // zapzap_potential_bonus

            normalScore = playValue * 15 + normalPlay.length * 7 +
                         Math.floor(remainingPotential / 20) - jokerCount * 36 + zapzapBonus;
        }

        const normalScenario = {
            playNow: normalPlay,
            score: normalScore,
            isCoordinated: false,
            drawSource: 'deck',
            reason: 'Normal play'
        };

        // Evaluate coordination scenarios for each discard card
        let bestCoordinated = null;

        for (const discardCard of lastCardsPlayed) {
            const scenario = this.evaluateHoldAndTakeScenario(hand, discardCard, gameState);

            if (scenario && (!bestCoordinated || scenario.score > bestCoordinated.score)) {
                bestCoordinated = scenario;
            }
        }

        // Compare and decide
        if (bestCoordinated && bestCoordinated.score > normalScore + this.coordParams.coordinationThreshold) {
            return bestCoordinated;
        }

        return normalScenario;
    }

    /**
     * Find the best offensive play
     * @param {Array<number>} hand - Current hand
     * @returns {Array<number>|null} Best play
     */
    findBestOffensivePlay(hand) {
        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Score each play
        let bestPlay = null;
        let bestScore = -Infinity;

        for (const play of validPlays) {
            const remaining = hand.filter(c => !play.includes(c));
            const remainingValue = CardAnalyzer.calculateHandValue(remaining);
            const pointsRemoved = handValue - remainingValue;
            const cardsRemoved = play.length;

            // Evaluate remaining hand's combo potential
            let remainingPotential = 0;
            for (const c of remaining) {
                remainingPotential += this.evaluateCardPotential(c, remaining);
            }

            // Genetically optimized scoring
            const valueScore = pointsRemoved * 15; // value_score_weight
            const cardsScore = cardsRemoved * 7; // cards_score_weight
            const potentialScore = Math.floor(remainingPotential / 20); // potential_divisor

            // Penalty for using jokers
            const jokerCount = play.filter(c => CardAnalyzer.isJoker(c)).length;
            const jokerPenalty = jokerCount * 36; // joker_play_penalty

            // Bonus for ZapZap potential
            const zapzapBonus = remainingValue <= 5 ? 79 : 0; // zapzap_potential_bonus

            const score = valueScore + cardsScore + potentialScore - jokerPenalty + zapzapBonus;

            if (score > bestScore) {
                bestScore = score;
                bestPlay = play;
            }
        }

        return bestPlay;
    }

    /**
     * Find the play that maximizes points removed (defensive mode)
     * @param {Array<number>} hand - Current hand
     * @returns {Array<number>|null} Best defensive play
     */
    findBestDefensivePlay(hand) {
        return CardAnalyzer.findMaxPointPlay(hand);
    }

    /**
     * Select optimal play with coordinated play/draw decision
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        // Reset coordinated decision at start of each play
        this.coordinatedDecision = null;

        // Update card tracker from game state for accurate probability calculations
        this.updateCardTracker(gameState);

        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        const minOpponentSize = this.getMinOpponentHandSize(gameState);

        // Defensive mode: if any opponent has few cards, play max points
        // defensive_threshold = 3 (genetically optimized)
        // In defensive mode, don't use coordination - just dump points
        if (minOpponentSize <= 3) {
            return this.findBestDefensivePlay(hand);
        }

        // Offensive mode with coordinated play/draw evaluation
        const lastCardsPlayed = gameState.lastCardsPlayed || [];

        // Try coordinated evaluation if there are cards in the discard
        if (lastCardsPlayed.length > 0) {
            const bestScenario = this.evaluateCoordinatedScenarios(hand, lastCardsPlayed, gameState);

            if (bestScenario.isCoordinated) {
                // Store the coordinated decision for selectDrawSource
                this.coordinatedDecision = {
                    play: bestScenario.playNow,
                    drawSource: 'played',
                    targetCard: bestScenario.discardCard,
                    reason: bestScenario.reason
                };
                return bestScenario.playNow;
            }
        }

        // Default: maximize points removed while keeping potential
        return this.findBestOffensivePlay(hand);
    }

    /**
     * Decide whether to call ZapZap
     * Uses genetically optimized thresholds
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {boolean}
     */
    shouldZapZap(hand, gameState) {
        const handValue = CardAnalyzer.calculateHandValue(hand);

        // Can't ZapZap if hand value > 5
        if (handValue > 5) {
            return false;
        }

        // Always ZapZap with 0 points
        if (handValue === 0) {
            return true;
        }

        // Always ZapZap with 1 point (very safe)
        // zapzap_safe_value_threshold = 1
        if (handValue <= 1) {
            return true;
        }

        // Check opponent risk
        const minOpponentSize = this.getMinOpponentHandSize(gameState);

        // Genetically optimized thresholds
        // zapzap_safe_hand_size = 2 (if opponents have many cards, safe)
        if (minOpponentSize >= 2 && handValue <= 2) {
            return true;
        }

        // zapzap_moderate_hand_size = 4, zapzap_moderate_value_threshold = 5
        if (minOpponentSize >= 4 && handValue <= 5) {
            return true;
        }

        // zapzap_risky_hand_size = 2, zapzap_risky_value_threshold = 2
        if (minOpponentSize <= 2 && handValue <= 2) {
            return true;
        }

        // Conservative default
        return handValue <= 2;
    }

    /**
     * Evaluate how good a card from discard would be
     * @param {number} card - Card to evaluate
     * @param {Array<number>} hand - Current hand
     * @returns {number} Score (higher = better)
     */
    evaluateDiscardCard(card, hand) {
        if (CardAnalyzer.isJoker(card)) {
            return 116; // discard_joker_score
        }

        const rank = CardAnalyzer.getRank(card);
        const points = CardAnalyzer.getCardPoints(card);

        let score = 0;

        // Low points are good
        score += 10 - points; // low_points_base

        // Check if it completes a pair
        if (CardAnalyzer.wouldCompletePair(hand, card)) {
            score += 56; // pair_completion_bonus

            // Even better if we already have 2 of this rank
            const sameRankCount = hand.filter(c =>
                !CardAnalyzer.isJoker(c) && CardAnalyzer.getRank(c) === rank
            ).length;
            if (sameRankCount >= 2) {
                score += 24; // three_of_kind_bonus
            }
        }

        // Check if it completes a sequence
        if (CardAnalyzer.wouldCompleteSequence(hand, card)) {
            score += 73; // sequence_completion_bonus
        }

        // Penalty if the rank is mostly dead
        const drawable = this.countDrawableRank(rank, hand);
        if (drawable === 0) {
            if (!CardAnalyzer.wouldCompletePair(hand, card) &&
                !CardAnalyzer.wouldCompleteSequence(hand, card)) {
                score -= 46; // dead_rank_discard_penalty
            }
        }

        return score;
    }

    /**
     * Select draw source with coordinated decision support
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string} 'deck' or 'played'
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
        // Ensure card tracker is updated (in case selectDrawSource is called without selectPlay)
        this.updateCardTracker(gameState);

        // Check if we have a coordinated decision from selectPlay
        if (this.coordinatedDecision && this.coordinatedDecision.drawSource === 'played') {
            // Verify the target card is still available
            if (lastCardsPlayed.includes(this.coordinatedDecision.targetCard)) {
                return 'played';
            }
            // Target card not available, fall through to normal logic
        }

        if (!Array.isArray(lastCardsPlayed) || lastCardsPlayed.length === 0) {
            return 'deck';
        }

        // Evaluate each available discard card
        let bestDiscardScore = -Infinity;
        for (const card of lastCardsPlayed) {
            const score = this.evaluateDiscardCard(card, hand);
            if (score > bestDiscardScore) {
                bestDiscardScore = score;
            }
        }

        // Calculate expected value of drawing from deck
        let deckExpectedValue = 0;
        let totalDrawable = 0;

        for (let rank = 0; rank < 13; rank++) {
            const drawable = this.countDrawableRank(rank, hand);
            if (drawable > 0) {
                // Create a representative card of this rank
                const sampleCard = rank; // Spades
                const cardValue = this.evaluateDiscardCard(sampleCard, hand);
                deckExpectedValue += cardValue * drawable;
                totalDrawable += drawable;
            }
        }

        // Add joker contribution
        const jokerDrawable = Math.max(0, 2 -
            hand.filter(c => CardAnalyzer.isJoker(c)).length -
            [...this.playedCards].filter(c => CardAnalyzer.isJoker(c)).length
        );
        if (jokerDrawable > 0) {
            deckExpectedValue += 116 * jokerDrawable; // discard_joker_score
            totalDrawable += jokerDrawable;
        }

        const avgDeckValue = totalDrawable > 0 ? deckExpectedValue / totalDrawable : 0;

        // discard_threshold = 8
        if (bestDiscardScore > avgDeckValue + 8) {
            return 'played';
        }

        return 'deck';
    }

    /**
     * Select strategic hand size
     * Thibot prefers smaller hands to reach 1 card faster
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        if (isGoldenScore) {
            return 4; // Minimum in golden score
        }
        // Slight randomization between 4-5
        return 4 + Math.floor(Math.random() * 2);
    }

    /**
     * Get strategy name
     */
    getName() {
        return 'Thibot (Probability)';
    }
}

module.exports = ThibotBotStrategy;
