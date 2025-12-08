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
 */

const BotStrategy = require('./BotStrategy');
const CardAnalyzer = require('../CardAnalyzer');

class HardVinceBotStrategy extends BotStrategy {
    constructor() {
        super('hard_vince');
        // Memory state (persists during bot's lifetime in a game)
        this.playedCardsHistory = [];      // All cards played this round
        this.opponentPickedCards = {};     // { playerIndex: [cardIds picked from discard] }
        this.lastDeckSize = null;          // To detect deck reshuffle
        this.lastRoundNumber = null;       // To detect new round
        this.botPlayerIndex = null;        // Bot's own player index
    }

    /**
     * Update memory based on game state
     * @param {Object} gameState - Current game state
     */
    updateMemory(gameState) {
        // Detect new round - reset all memory
        if (this.lastRoundNumber !== null && gameState.roundNumber !== this.lastRoundNumber) {
            this.playedCardsHistory = [];
            this.opponentPickedCards = {};
            this.lastDeckSize = null;
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
     * Select optimal play with Vince strategies
     * @param {Array<number>} hand - Bot's current hand
     * @param {Object} gameState - Current game state
     * @returns {Array<number>|null} Cards to play
     */
    selectPlay(hand, gameState) {
        if (!Array.isArray(hand) || hand.length === 0) {
            return null;
        }

        // Update memory before making decision
        this.updateMemory(gameState);

        // Determine bot's player index from gameState
        const botPlayerIndex = gameState.currentTurn;
        this.botPlayerIndex = botPlayerIndex;

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
                score -= 1000; // Extreme penalty - effectively blocks any play containing Jokers
            }
            // VINCE STRATEGY 1 & 2: Joker management (only applies outside Golden Score)
            else if (hasJokersInPlay) {
                if (opponentsHaveMoreThan3) {
                    // Opponents have > 3 cards: keep jokers, penalize playing them in pairs/sets
                    if (isPairOrSet) {
                        score -= 50; // Heavy penalty for playing jokers in pairs/sets
                    } else if (isSequence) {
                        score -= 10; // Small penalty even for sequences when opponents have many cards
                    }
                } else {
                    // Opponent has <= 3 cards: encourage playing jokers in pairs/sets
                    if (isPairOrSet) {
                        score += 30; // Bonus for getting rid of jokers in pairs/sets
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
                score
            };
        });

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
                bonus += combiningCards * 2;
            }
        }

        return bonus;
    }

    /**
     * Strategic zapzap decision based on hand value and game context
     * (Inherited from HardBotStrategy with same logic)
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

        // Always zapzap if hand value is 0
        if (handValue === 0) {
            return true;
        }

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
        // Update memory before making decision
        this.updateMemory(gameState);

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
        // VINCE STRATEGY 5: Priority Joker pickup when opponents have > 3 cards (outside Golden Score)
        if (jokersInDiscard.length > 0 && opponentsHaveMoreThan3) {
            // Strongly prefer picking up the Joker
            return 'played';
        }

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

        // If any discard card provides significant improvement, take it
        if (bestImprovement > 5) {
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

        let combinationBonus = (newMultiCardPlays - originalMultiCardPlays) * 10;

        // Prefer low-value cards (helps with zapzap)
        const cardPoints = CardAnalyzer.getCardPoints(cardId);
        const lowValueBonus = (10 - cardPoints);

        // Prefer cards that complete sequences or sets
        const rank = CardAnalyzer.getRank(cardId);
        const sameRankCount = hand.filter(id =>
            !CardAnalyzer.isJoker(id) && CardAnalyzer.getRank(id) === rank
        ).length;

        let setBonus = sameRankCount >= 1 ? sameRankCount * 5 : 0;

        // VINCE STRATEGY 4: Probability adjustment based on played cards memory
        if (!CardAnalyzer.isJoker(cardId)) {
            const sameRankPlayedCount = this.playedCardsHistory.filter(playedId =>
                !CardAnalyzer.isJoker(playedId) && CardAnalyzer.getRank(playedId) === rank
            ).length;

            // If many cards of this rank have been played, it's harder to find more
            // Total of 4 cards per rank (one per suit)
            // If 2+ already played, probability of drawing another is low
            if (sameRankPlayedCount >= 2) {
                setBonus = Math.max(0, setBonus - 5); // Reduce bonus
            }
            if (sameRankPlayedCount >= 3) {
                setBonus = 0; // No bonus, very unlikely to find another
                combinationBonus = Math.max(0, combinationBonus - 5);
            }
        }

        // VINCE STRATEGY 6: During Golden Score, Jokers are EXTREMELY valuable to hoard
        // Pick them up to deny them to opponent and keep them forever (never play them)
        const isGoldenScore = gameState.isGoldenScore || false;
        if (CardAnalyzer.isJoker(cardId)) {
            if (isGoldenScore) {
                // Extreme bonus during Golden Score - ALWAYS pick up Jokers to hoard them
                return 100;
            } else if (opponentsHaveMoreThan3) {
                combinationBonus += 20; // Jokers valuable for sequences/combos
            } else {
                // Heavy penalty - Jokers are 25 point liability when opponent is close to zapzap
                // Override all other bonuses to strongly discourage pickup
                return -50;
            }
        }

        return combinationBonus + lowValueBonus + setBonus;
    }

    /**
     * Select strategic hand size (fewer cards = easier to zapzap quickly)
     * (Same as HardBotStrategy)
     * @param {number} activePlayerCount - Number of active players
     * @param {boolean} isGoldenScore - Whether in Golden Score mode
     * @returns {number} Hand size
     */
    selectHandSize(activePlayerCount, isGoldenScore) {
        // Hard bot prefers fewer cards for faster zapzap potential
        // But not always minimum to add some unpredictability
        if (isGoldenScore) {
            // Golden Score: prefer 4-6 cards (lower end)
            return 4 + Math.floor(Math.random() * 3); // 4, 5, or 6
        }
        // Normal game: prefer 4-5 cards (minimum or near minimum)
        return 4 + Math.floor(Math.random() * 2); // 4 or 5
    }
}

module.exports = HardVinceBotStrategy;
