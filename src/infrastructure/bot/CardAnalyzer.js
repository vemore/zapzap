/**
 * CardAnalyzer
 * Analyzes card hands and finds valid plays for bot decision-making
 * Works with card IDs (0-53) instead of Card objects
 */

class CardAnalyzer {
    /**
     * Get card points for zapzap calculation
     * @param {number} cardId - Card ID (0-53)
     * @returns {number} Points value
     */
    static getCardPoints(cardId) {
        // Jokers (52-53) = 0 points
        if (cardId >= 52) {
            return 0;
        }

        const rank = cardId % 13;

        // Ace = 1
        if (rank === 0) {
            return 1;
        }

        // 2-9 = face value (rank 1-8 → points 2-9)
        if (rank <= 8) {
            return rank + 1;
        }

        // 10, J, Q, K = 10 points
        return 10;
    }

    /**
     * Calculate total hand value (for zapzap)
     * @param {Array<number>} hand - Array of card IDs
     * @returns {number} Total hand value
     */
    static calculateHandValue(hand) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return 0;
        }

        return hand.reduce((total, cardId) => {
            return total + this.getCardPoints(cardId);
        }, 0);
    }

    /**
     * Get card rank (0-12)
     * @param {number} cardId - Card ID (0-53)
     * @returns {number} Rank (0=Ace, 1=2, ..., 12=King) or -1 for jokers
     */
    static getRank(cardId) {
        if (cardId >= 52) {
            return -1; // Joker
        }
        return cardId % 13;
    }

    /**
     * Get card suit (0-3)
     * @param {number} cardId - Card ID (0-53)
     * @returns {number} Suit (0=Spades, 1=Hearts, 2=Clubs, 3=Diamonds) or -1 for jokers
     */
    static getSuit(cardId) {
        if (cardId >= 52) {
            return -1; // Joker
        }
        return Math.floor(cardId / 13);
    }

    /**
     * Check if card is joker
     * @param {number} cardId - Card ID (0-53)
     * @returns {boolean}
     */
    static isJoker(cardId) {
        return cardId >= 52;
    }

    /**
     * Check if cards form a valid same-rank combination (pairs/sets)
     * @param {Array<number>} cardIds - Array of card IDs
     * @returns {boolean}
     */
    static isValidSameRank(cardIds) {
        if (!Array.isArray(cardIds) || cardIds.length < 2) {
            return false;
        }

        const normalCards = cardIds.filter(id => !this.isJoker(id));

        // All jokers is valid
        if (normalCards.length === 0) {
            return true;
        }

        // All non-joker cards must have same rank
        const targetRank = this.getRank(normalCards[0]);
        return normalCards.every(id => this.getRank(id) === targetRank);
    }

    /**
     * Check if cards form a valid sequence (run in same suit)
     * @param {Array<number>} cardIds - Array of card IDs
     * @returns {boolean}
     */
    static isValidSequence(cardIds) {
        if (!Array.isArray(cardIds) || cardIds.length < 3) {
            return false;
        }

        const normalCards = cardIds.filter(id => !this.isJoker(id));
        const jokerCount = cardIds.length - normalCards.length;

        // Need at least one normal card to determine suit
        if (normalCards.length === 0) {
            return true; // All jokers
        }

        // Check all same suit
        const targetSuit = this.getSuit(normalCards[0]);
        const sameSuit = normalCards.every(id => this.getSuit(id) === targetSuit);

        if (!sameSuit) {
            return false;
        }

        // Check sequence with joker gaps
        const ranks = normalCards.map(id => this.getRank(id)).sort((a, b) => a - b);

        let expectedRank = ranks[0];
        let gapsToFill = 0;

        for (let i = 1; i < ranks.length; i++) {
            const diff = ranks[i] - expectedRank - 1;
            if (diff > 0) {
                gapsToFill += diff;
            }
            expectedRank = ranks[i];
        }

        // Check if we have enough jokers to fill gaps
        return gapsToFill <= jokerCount;
    }

    /**
     * Check if a play is valid
     * @param {Array<number>} cardIds - Array of card IDs
     * @returns {boolean}
     */
    static isValidPlay(cardIds) {
        if (!Array.isArray(cardIds) || cardIds.length === 0) {
            return false;
        }

        // Single card is always valid
        if (cardIds.length === 1) {
            return true;
        }

        // Multiple cards: must be same rank OR sequence
        return this.isValidSameRank(cardIds) || this.isValidSequence(cardIds);
    }

    /**
     * Find all cards with a specific rank in hand
     * @param {Array<number>} hand - Array of card IDs
     * @param {number} rank - Target rank (0-12)
     * @returns {Array<number>} Card IDs with that rank
     */
    static findCardsByRank(hand, rank) {
        if (!Array.isArray(hand)) {
            return [];
        }

        return hand.filter(id => !this.isJoker(id) && this.getRank(id) === rank);
    }

    /**
     * Find all jokers in hand
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<number>} Joker card IDs
     */
    static findJokers(hand) {
        if (!Array.isArray(hand)) {
            return [];
        }

        return hand.filter(id => this.isJoker(id));
    }

    /**
     * Find all valid same-rank plays (pairs, sets) in hand
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<Array<number>>} Array of valid same-rank combinations
     */
    static findSameRankPlays(hand) {
        if (!Array.isArray(hand) || hand.length < 2) {
            return [];
        }

        const plays = [];
        const jokers = this.findJokers(hand);
        const ranks = {};

        // Group cards by rank
        hand.forEach(cardId => {
            if (!this.isJoker(cardId)) {
                const rank = this.getRank(cardId);
                if (!ranks[rank]) {
                    ranks[rank] = [];
                }
                ranks[rank].push(cardId);
            }
        });

        // Find all combinations for each rank
        Object.values(ranks).forEach(cards => {
            if (cards.length >= 2) {
                // Pure pairs/sets (no jokers)
                plays.push([...cards]);

                // With jokers
                for (let j = 1; j <= jokers.length && j <= (4 - cards.length); j++) {
                    plays.push([...cards, ...jokers.slice(0, j)]);
                }
            } else if (cards.length === 1 && jokers.length > 0) {
                // Single card + jokers
                for (let j = 1; j <= jokers.length; j++) {
                    plays.push([...cards, ...jokers.slice(0, j)]);
                }
            }
        });

        return plays;
    }

    /**
     * Find all valid sequence plays in hand
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<Array<number>>} Array of valid sequences
     */
    static findSequencePlays(hand) {
        if (!Array.isArray(hand) || hand.length < 3) {
            return [];
        }

        const plays = [];
        const jokers = this.findJokers(hand);
        const bySuit = {};

        // Group cards by suit
        hand.forEach(cardId => {
            if (!this.isJoker(cardId)) {
                const suit = this.getSuit(cardId);
                if (!bySuit[suit]) {
                    bySuit[suit] = [];
                }
                bySuit[suit].push(cardId);
            }
        });

        // For each suit, find sequences
        Object.values(bySuit).forEach(cards => {
            if (cards.length < 3 && jokers.length + cards.length < 3) {
                return; // Not enough cards
            }

            // Sort by rank
            cards.sort((a, b) => this.getRank(a) - this.getRank(b));

            // Try all possible sequence starting positions and lengths
            // Sequences require 3+ cards
            for (let start = 0; start < cards.length; start++) {
                for (let end = start + 3; end <= cards.length; end++) {
                    const subset = cards.slice(start, end);

                    // Check if this subset can form a sequence with jokers
                    const ranks = subset.map(id => this.getRank(id));
                    let gapsNeeded = 0;

                    for (let i = 1; i < ranks.length; i++) {
                        const diff = ranks[i] - ranks[i - 1] - 1;
                        if (diff > 0) {
                            gapsNeeded += diff;
                        }
                    }

                    // Valid sequence if we have enough jokers
                    if (gapsNeeded <= jokers.length) {
                        // Add without jokers if no gaps
                        if (gapsNeeded === 0) {
                            plays.push([...subset]);
                        }
                        // Add with exact jokers needed
                        if (gapsNeeded > 0) {
                            plays.push([...subset, ...jokers.slice(0, gapsNeeded)]);
                        }
                    }
                }
            }
        });

        return plays;
    }

    /**
     * Find all valid plays in hand
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<Array<number>>} Array of all valid plays
     */
    static findAllValidPlays(hand) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return [];
        }

        const plays = [];

        // Single cards
        hand.forEach(cardId => {
            plays.push([cardId]);
        });

        // Same rank plays
        const sameRankPlays = this.findSameRankPlays(hand);
        plays.push(...sameRankPlays);

        // Sequence plays
        const sequencePlays = this.findSequencePlays(hand);
        plays.push(...sequencePlays);

        return plays;
    }

    /**
     * Find the play that removes the most points from hand
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<number>|null} Best play to maximize point reduction
     */
    static findMaxPointPlay(hand) {
        const validPlays = this.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        // Calculate points for each play
        const playsWithPoints = validPlays.map(play => ({
            cards: play,
            points: this.calculateHandValue(play),
            count: play.length
        }));

        // Sort by points descending, then by card count descending
        playsWithPoints.sort((a, b) => {
            if (a.points !== b.points) {
                return b.points - a.points; // Higher points first
            }
            return b.count - a.count; // More cards first
        });

        return playsWithPoints[0].cards;
    }

    /**
     * Find the play that removes the most high-value cards (10-point cards)
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<number>|null} Best play to remove high-value cards
     */
    static findHighValuePlay(hand) {
        const validPlays = this.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        // Calculate high-value cards (10-point cards: 10, J, Q, K)
        const playsWithHighCards = validPlays.map(play => ({
            cards: play,
            highValueCount: play.filter(id => {
                if (this.isJoker(id)) return false;
                const rank = this.getRank(id);
                return rank >= 9; // 10, J, Q, K
            }).length,
            points: this.calculateHandValue(play)
        }));

        // Sort by high-value count descending, then by points
        playsWithHighCards.sort((a, b) => {
            if (a.highValueCount !== b.highValueCount) {
                return b.highValueCount - a.highValueCount;
            }
            return b.points - a.points;
        });

        return playsWithHighCards[0].cards;
    }

    /**
     * Find a random valid play
     * @param {Array<number>} hand - Array of card IDs
     * @returns {Array<number>|null} Random valid play
     */
    static findRandomPlay(hand) {
        const validPlays = this.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            return null;
        }

        const randomIndex = Math.floor(Math.random() * validPlays.length);
        return validPlays[randomIndex];
    }

    /**
     * Check if hand value is low enough to call zapzap
     * @param {Array<number>} hand - Array of card IDs
     * @returns {boolean}
     */
    static canCallZapZap(hand) {
        return this.calculateHandValue(hand) <= 5;
    }
}

module.exports = CardAnalyzer;
