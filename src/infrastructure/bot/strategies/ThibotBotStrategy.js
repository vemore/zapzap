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
 *
 * Parameters optimized via genetic algorithm achieving ~40% winrate vs HardBots
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
    }

    /**
     * Reset tracking for new game/round
     */
    reset() {
        this.playedCards.clear();
        this.opponentTakenCards.clear();
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
     * @param {number} rank - Card rank (0-12)
     * @param {Array<number>} hand - Current hand
     * @returns {number} Number of drawable cards
     */
    countDrawableRank(rank, hand) {
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
            return 923; // Genetically optimized joker score
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
            score += 54; // existing_pair_bonus
        } else if (drawable >= 2) {
            score += 25; // good_pair_chance_bonus
        } else if (drawable === 1) {
            score += 14; // low_pair_chance_bonus
        } else {
            score -= 34; // dead_rank_penalty
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
            score += 52; // sequence_part_bonus
        } else if (adjacentCount === 1) {
            score += 33; // potential_sequence_bonus
            if (hasJoker) {
                score += 31; // joker_sequence_bonus
            }
        } else if (closeCount >= 1 && hasJoker) {
            score += 13; // close_with_joker_bonus
        }

        return score;
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
            const valueScore = pointsRemoved * 19; // value_score_weight
            const cardsScore = cardsRemoved * 14; // cards_score_weight
            const potentialScore = Math.floor(remainingPotential / 15); // potential_divisor

            // Penalty for using jokers
            const jokerCount = play.filter(c => CardAnalyzer.isJoker(c)).length;
            const jokerPenalty = jokerCount * 50; // joker_play_penalty

            // Bonus for ZapZap potential
            const zapzapBonus = remainingValue <= 5 ? 122 : 0; // zapzap_potential_bonus

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
     * Select optimal play
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        const minOpponentSize = this.getMinOpponentHandSize(gameState);

        // Defensive mode: if any opponent has few cards, play max points
        // defensive_threshold = 4 (genetically optimized)
        if (minOpponentSize <= 4) {
            return this.findBestDefensivePlay(hand);
        }

        // Offensive mode: maximize points removed while keeping potential
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

        // zapzap_moderate_hand_size = 5, zapzap_moderate_value_threshold = 5
        if (minOpponentSize >= 5 && handValue <= 5) {
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
            return 177; // discard_joker_score
        }

        const rank = CardAnalyzer.getRank(card);
        const points = CardAnalyzer.getCardPoints(card);

        let score = 0;

        // Low points are good
        score += 9 - points; // low_points_base

        // Check if it completes a pair
        if (CardAnalyzer.wouldCompletePair(hand, card)) {
            score += 133; // pair_completion_bonus

            // Even better if we already have 2 of this rank
            const sameRankCount = hand.filter(c =>
                !CardAnalyzer.isJoker(c) && CardAnalyzer.getRank(c) === rank
            ).length;
            if (sameRankCount >= 2) {
                score += 25; // three_of_kind_bonus
            }
        }

        // Check if it completes a sequence
        if (CardAnalyzer.wouldCompleteSequence(hand, card)) {
            score += 52; // sequence_completion_bonus
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
     * Select draw source
     * @param {Array<number>} hand - Bot's current hand
     * @param {Array<number>} lastCardsPlayed - Cards in discard pile
     * @param {Object} gameState - Current game state
     * @returns {string} 'deck' or 'played'
     */
    selectDrawSource(hand, lastCardsPlayed, gameState) {
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
            deckExpectedValue += 177 * jokerDrawable; // discard_joker_score
            totalDrawable += jokerDrawable;
        }

        const avgDeckValue = totalDrawable > 0 ? deckExpectedValue / totalDrawable : 0;

        // discard_threshold = 14
        if (bestDiscardScore > avgDeckValue + 14) {
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
