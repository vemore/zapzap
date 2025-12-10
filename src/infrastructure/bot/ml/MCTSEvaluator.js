/**
 * MCTSEvaluator
 * Lightweight Monte Carlo Tree Search for card play evaluation
 * Simulates future game states to evaluate move quality
 */

const CardAnalyzer = require('../CardAnalyzer');

class MCTSEvaluator {
    /**
     * @param {Object} options - MCTS options
     * @param {number} options.simulations - Number of simulations per evaluation (default: 50)
     * @param {number} options.maxDepth - Maximum simulation depth (default: 10)
     */
    constructor(options = {}) {
        this.simulations = options.simulations || 50;
        this.maxDepth = options.maxDepth || 10;
    }

    /**
     * Evaluate a play by simulating future outcomes
     * @param {Array<number>} play - Cards to play
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player making the move
     * @returns {number} Score estimate (higher is better)
     */
    evaluatePlay(play, hand, gameState, playerIndex) {
        let totalScore = 0;

        for (let i = 0; i < this.simulations; i++) {
            const score = this.simulateGame(play, hand, gameState, playerIndex);
            totalScore += score;
        }

        return totalScore / this.simulations;
    }

    /**
     * Evaluate multiple plays and rank them
     * @param {Array<Array<number>>} plays - List of possible plays
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player making the move
     * @returns {Array<Object>} Plays ranked by MCTS score
     */
    rankPlays(plays, hand, gameState, playerIndex) {
        const evaluatedPlays = plays.map(play => ({
            cards: play,
            mctsScore: this.evaluatePlay(play, hand, gameState, playerIndex),
            handValueAfter: CardAnalyzer.calculateHandValue(
                hand.filter(c => !play.includes(c))
            )
        }));

        // Sort by MCTS score (higher is better)
        evaluatedPlays.sort((a, b) => b.mctsScore - a.mctsScore);

        return evaluatedPlays;
    }

    /**
     * Simulate a game from the current state
     * @param {Array<number>} initialPlay - The play to evaluate
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player making the move
     * @returns {number} Simulation result score
     */
    simulateGame(initialPlay, hand, gameState, playerIndex) {
        // Create simulation state
        const simState = this.createSimulationState(gameState, playerIndex);

        // Apply initial play
        let myHand = hand.filter(c => !initialPlay.includes(c));
        simState.discard = [...initialPlay];

        // Simulate turns
        let depth = 0;
        let currentPlayer = (playerIndex + 1) % simState.playerCount;

        while (depth < this.maxDepth && !this.isGameOver(simState, myHand, playerIndex)) {
            if (currentPlayer === playerIndex) {
                // My turn - simulate draw and play
                myHand = this.simulateMyTurn(myHand, simState);
            } else {
                // Opponent turn - simulate their play
                this.simulateOpponentTurn(currentPlayer, simState);
            }

            currentPlayer = (currentPlayer + 1) % simState.playerCount;
            depth++;
        }

        // Calculate score based on final state
        return this.calculateSimulationScore(myHand, simState, playerIndex);
    }

    /**
     * Create a lightweight simulation state
     */
    createSimulationState(gameState, playerIndex) {
        const hands = gameState.hands || {};
        const opponentHands = {};

        for (const [idx, hand] of Object.entries(hands)) {
            const i = parseInt(idx);
            if (i !== playerIndex && Array.isArray(hand)) {
                // Store hand size only (we don't know exact cards)
                opponentHands[i] = hand.length;
            }
        }

        return {
            playerCount: Object.keys(hands).length,
            opponentHandSizes: opponentHands,
            deckSize: gameState.deck?.length || 30,
            discard: [...(gameState.lastCardsPlayed || [])],
            isGoldenScore: gameState.isGoldenScore || false,
            eliminatedPlayers: [...(gameState.eliminatedPlayers || [])]
        };
    }

    /**
     * Simulate my turn (draw + play)
     */
    simulateMyTurn(hand, simState) {
        // Simulate draw
        if (simState.deckSize > 0) {
            // Random card (simplified - just reduce deck)
            simState.deckSize--;
            // Add a random card value (simplified)
            const randomCard = Math.floor(Math.random() * 52);
            hand = [...hand, randomCard];
        }

        // Simulate play - remove highest value card
        if (hand.length > 0) {
            const sortedByValue = [...hand].sort((a, b) => {
                const aVal = a >= 52 ? 0 : (a % 13) + 1;
                const bVal = b >= 52 ? 0 : (b % 13) + 1;
                return bVal - aVal;
            });
            const playCard = sortedByValue[0];
            hand = hand.filter(c => c !== playCard);
            simState.discard = [playCard];
        }

        return hand;
    }

    /**
     * Simulate opponent turn
     */
    simulateOpponentTurn(opponentIndex, simState) {
        const handSize = simState.opponentHandSizes[opponentIndex];
        if (!handSize || handSize <= 0) return;

        // Draw (simplified)
        if (simState.deckSize > 0) {
            simState.deckSize--;
            simState.opponentHandSizes[opponentIndex]++;
        }

        // Play (simplified - reduce hand by 1-2 cards randomly)
        const playSize = Math.random() < 0.7 ? 1 : 2;
        simState.opponentHandSizes[opponentIndex] = Math.max(
            0,
            simState.opponentHandSizes[opponentIndex] - playSize
        );
    }

    /**
     * Check if game is over
     */
    isGameOver(simState, myHand, playerIndex) {
        // Game over if I have very few cards and low value
        if (myHand.length <= 2) {
            const handValue = CardAnalyzer.calculateHandValue(myHand);
            if (handValue <= 5) return true;
        }

        // Game over if any opponent has 0 cards
        for (const [idx, size] of Object.entries(simState.opponentHandSizes)) {
            if (size <= 0) return true;
        }

        return false;
    }

    /**
     * Calculate simulation score
     * Higher score = better outcome for player
     */
    calculateSimulationScore(myHand, simState, playerIndex) {
        const myHandValue = CardAnalyzer.calculateHandValue(myHand);
        const myHandSize = myHand.length;

        // Base score: lower hand value is better
        let score = 100 - myHandValue;

        // Bonus for fewer cards
        score += (10 - myHandSize) * 5;

        // Bonus if we can ZapZap
        if (myHandValue <= 5) {
            score += 50;
        }

        // Penalty if opponents have fewer cards
        let minOpponentCards = Infinity;
        for (const size of Object.values(simState.opponentHandSizes)) {
            minOpponentCards = Math.min(minOpponentCards, size);
        }

        if (minOpponentCards < myHandSize) {
            score -= (myHandSize - minOpponentCards) * 10;
        }

        // Joker handling
        const jokerCount = myHand.filter(c => c >= 52).length;
        if (simState.isGoldenScore) {
            // In Golden Score, jokers are valuable
            score += jokerCount * 15;
        } else if (minOpponentCards <= 2) {
            // Opponents close to winning - jokers should be played
            score -= jokerCount * 10;
        }

        return score;
    }

    /**
     * Get best play using MCTS evaluation
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player index
     * @returns {Array<number>|null} Best play
     */
    getBestPlay(hand, gameState, playerIndex) {
        const validPlays = CardAnalyzer.findAllValidPlays(hand);

        if (validPlays.length === 0) {
            // No valid plays - play highest single card
            let highest = hand[0];
            let highestValue = CardAnalyzer.getCardPoints(hand[0]);
            for (const card of hand) {
                const value = CardAnalyzer.getCardPoints(card);
                if (value > highestValue) {
                    highestValue = value;
                    highest = card;
                }
            }
            return [highest];
        }

        if (validPlays.length === 1) {
            return validPlays[0];
        }

        // Rank plays using MCTS
        const ranked = this.rankPlays(validPlays, hand, gameState, playerIndex);
        return ranked[0].cards;
    }

    /**
     * Evaluate if ZapZap should be called using simulations
     * @param {Array<number>} hand - Current hand
     * @param {Object} gameState - Current game state
     * @param {number} playerIndex - Player index
     * @returns {boolean} Whether to call ZapZap
     */
    shouldZapZap(hand, gameState, playerIndex) {
        const handValue = CardAnalyzer.calculateHandValue(hand);
        if (handValue > 5) return false;

        // Simulate outcomes with and without ZapZap
        const zapZapScore = this.simulateZapZap(hand, gameState, playerIndex, true);
        const noZapZapScore = this.simulateZapZap(hand, gameState, playerIndex, false);

        return zapZapScore > noZapZapScore;
    }

    /**
     * Simulate ZapZap decision
     */
    simulateZapZap(hand, gameState, playerIndex, callZapZap) {
        if (callZapZap) {
            // Estimate probability of winning ZapZap
            const myHandValue = CardAnalyzer.calculateHandValue(hand);
            const hands = gameState.hands || {};

            let betterOrEqualCount = 0;
            let opponentCount = 0;

            for (const [idx, oppHand] of Object.entries(hands)) {
                const i = parseInt(idx);
                if (i !== playerIndex && Array.isArray(oppHand)) {
                    opponentCount++;
                    // Estimate opponent hand value (average)
                    const estimatedValue = oppHand.length * 5; // Rough estimate
                    if (estimatedValue <= myHandValue) {
                        betterOrEqualCount++;
                    }
                }
            }

            // If likely to win ZapZap
            if (betterOrEqualCount === 0 || myHandValue === 0) {
                return 100; // High score for winning
            } else {
                // Risk of counteract
                return 20 - (betterOrEqualCount * 30);
            }
        } else {
            // Don't call ZapZap - continue playing
            return 30 + (5 - CardAnalyzer.calculateHandValue(hand)) * 5;
        }
    }
}

module.exports = MCTSEvaluator;
