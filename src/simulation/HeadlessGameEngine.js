/**
 * HeadlessGameEngine
 * Synchronous game engine for fast simulation without I/O overhead
 * Replicates the game logic from use-cases but runs entirely in memory
 */

const GameState = require('../domain/value-objects/GameState');
const CardAnalyzer = require('../infrastructure/bot/CardAnalyzer');

class HeadlessGameEngine {
    /**
     * @param {Array<Object>} strategies - Array of bot strategies (one per player)
     * @param {Object} options - Engine options
     * @param {number} options.playerCount - Number of players (default: strategies.length)
     */
    constructor(strategies, options = {}) {
        this.strategies = strategies;
        this.playerCount = options.playerCount || strategies.length;
    }

    /**
     * Run a complete game synchronously
     * @returns {Object} Game result with all round data
     */
    runGame() {
        // Initialize scores
        const scores = {};
        for (let i = 0; i < this.playerCount; i++) {
            scores[i] = 0;
        }

        let gameState = new GameState({
            deck: [],
            hands: {},
            scores,
            currentTurn: 0,
            currentAction: 'selectHandSize',
            roundNumber: 1,
            eliminatedPlayers: [],
            isGoldenScore: false
        });

        const roundHistory = [];
        let roundNumber = 1;

        // Main game loop
        while (!this.isGameFinished(gameState)) {
            const roundResult = this.runRound(gameState, roundNumber);
            roundHistory.push(roundResult);
            gameState = roundResult.finalState;
            roundNumber++;

            // Process round end - check eliminations and golden score
            gameState = this.processRoundEnd(gameState);
        }

        // Determine winner
        const winner = this.determineWinner(gameState);

        return {
            winner,
            rounds: roundHistory,
            totalRounds: roundNumber - 1,
            finalScores: gameState.scores,
            wasGoldenScore: gameState.isGoldenScore,
            eliminatedPlayers: gameState.eliminatedPlayers
        };
    }

    /**
     * Run a single round synchronously
     * @param {GameState} gameState - Current game state
     * @param {number} roundNumber - Round number
     * @returns {Object} Round result
     */
    runRound(gameState, roundNumber) {
        // Get active (non-eliminated) players
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        const activePlayers = [];
        for (let i = 0; i < this.playerCount; i++) {
            if (!eliminatedPlayers.includes(i)) {
                activePlayers.push(i);
            }
        }

        // Use currentTurn from gameState (set by processRoundEnd to rotate starting player)
        let currentPlayer = gameState.currentTurn;
        // Ensure we start with an active player
        while (eliminatedPlayers.includes(currentPlayer)) {
            currentPlayer = (currentPlayer + 1) % this.playerCount;
        }

        // Select hand size
        const strategy = this.strategies[currentPlayer];
        const handSize = strategy.selectHandSize(activePlayers.length, gameState.isGoldenScore);
        const validHandSize = this.validateHandSize(handSize, gameState.isGoldenScore);

        // Deal cards - pass the starting player to maintain turn order
        gameState = this.dealCards(gameState, validHandSize, activePlayers, roundNumber, currentPlayer);

        // Play turns until ZapZap
        let turnCount = 0;
        const maxTurns = 1000; // Safety limit

        while (gameState.currentAction !== 'finished' && turnCount < maxTurns) {
            currentPlayer = gameState.currentTurn;
            const currentStrategy = this.strategies[currentPlayer];
            const hand = gameState.getPlayerHand(currentPlayer);

            // Skip eliminated players
            if (eliminatedPlayers.includes(currentPlayer)) {
                gameState = this.advanceTurn(gameState, eliminatedPlayers);
                turnCount++;
                continue;
            }

            // Check for ZapZap
            if (CardAnalyzer.canCallZapZap(hand) && currentStrategy.shouldZapZap(hand, gameState)) {
                gameState = this.executeZapZap(gameState, currentPlayer, activePlayers);
                break;
            }

            // Play phase
            const cardsToPlay = currentStrategy.selectPlay(hand, gameState);
            if (cardsToPlay && cardsToPlay.length > 0) {
                gameState = this.executePlay(gameState, currentPlayer, cardsToPlay);
            } else {
                // Must play at least one card - play random
                const fallbackPlay = CardAnalyzer.findRandomPlay(hand);
                if (fallbackPlay) {
                    gameState = this.executePlay(gameState, currentPlayer, fallbackPlay);
                }
            }

            // Draw phase
            const drawSource = currentStrategy.selectDrawSource(
                gameState.getPlayerHand(currentPlayer),
                gameState.lastCardsPlayed,
                gameState
            );
            gameState = this.executeDraw(gameState, currentPlayer, drawSource, eliminatedPlayers);

            turnCount++;
        }

        return {
            roundNumber,
            finalState: gameState,
            turnsPlayed: turnCount
        };
    }

    /**
     * Deal cards to all active players
     * @param {GameState} gameState - Current game state
     * @param {number} handSize - Number of cards per player
     * @param {Array<number>} activePlayers - List of active player indices
     * @param {number} roundNumber - Current round number
     * @param {number} startingPlayer - Player who starts this round
     */
    dealCards(gameState, handSize, activePlayers, roundNumber, startingPlayer) {
        // Create and shuffle deck (54 cards: 0-51 standard, 52-53 jokers)
        const deck = [];
        for (let i = 0; i < 54; i++) {
            deck.push(i);
        }
        this.shuffleArray(deck);

        // Deal hands
        const hands = {};
        for (let i = 0; i < this.playerCount; i++) {
            if (activePlayers.includes(i)) {
                hands[i] = deck.splice(0, handSize);
            } else {
                hands[i] = []; // Eliminated players get no cards
            }
        }

        // Flip one card to start discard pile
        const flippedCard = deck.pop();

        return gameState.with({
            deck,
            hands,
            lastCardsPlayed: [flippedCard],
            cardsPlayed: [],
            discardPile: [],
            currentTurn: startingPlayer,  // Use the starting player, not always first
            currentAction: 'play',
            roundNumber
        });
    }

    /**
     * Execute a play action
     */
    executePlay(gameState, playerIndex, cardIds) {
        const hand = gameState.getPlayerHand(playerIndex);
        const newHand = hand.filter(id => !cardIds.includes(id));

        const newHands = gameState.hands;
        newHands[playerIndex] = newHand;

        // Determine new lastCardsPlayed
        const isFirstPlayOfRound = !gameState.cardsPlayed || gameState.cardsPlayed.length === 0;
        const newLastCardsPlayed = isFirstPlayOfRound
            ? gameState.lastCardsPlayed
            : gameState.cardsPlayed;

        const newDiscardPile = isFirstPlayOfRound
            ? [...gameState.discardPile]
            : [...gameState.discardPile, ...gameState.lastCardsPlayed];

        return gameState.with({
            hands: newHands,
            cardsPlayed: cardIds,
            lastCardsPlayed: newLastCardsPlayed,
            discardPile: newDiscardPile,
            currentAction: 'draw'
        });
    }

    /**
     * Execute a draw action
     */
    executeDraw(gameState, playerIndex, source, eliminatedPlayers) {
        let drawnCard;
        let newDeck = [...gameState.deck];
        let newLastCardsPlayed = [...gameState.lastCardsPlayed];
        let newDiscardPile = [...gameState.discardPile];

        if (source === 'deck' || newLastCardsPlayed.length === 0) {
            // Draw from deck
            if (newDeck.length === 0) {
                // Reshuffle discard pile
                if (newDiscardPile.length === 0) {
                    // No cards to draw - should not happen normally
                    return this.advanceTurn(gameState, eliminatedPlayers);
                }
                newDeck = [...newDiscardPile];
                this.shuffleArray(newDeck);
                newDiscardPile = [];
            }
            drawnCard = newDeck.pop();
        } else {
            // Draw from last played cards (take the last one)
            drawnCard = newLastCardsPlayed.pop();
        }

        // Add card to player's hand
        const newHands = gameState.hands;
        newHands[playerIndex] = [...gameState.getPlayerHand(playerIndex), drawnCard];

        // Move to next active player
        let nextTurn = (gameState.currentTurn + 1) % this.playerCount;
        while (eliminatedPlayers.includes(nextTurn)) {
            nextTurn = (nextTurn + 1) % this.playerCount;
        }

        return gameState.with({
            hands: newHands,
            deck: newDeck,
            lastCardsPlayed: newLastCardsPlayed,
            discardPile: newDiscardPile,
            currentTurn: nextTurn,
            currentAction: 'play',
            cardsPlayed: [] // Reset for next turn
        });
    }

    /**
     * Execute ZapZap and calculate scores
     */
    executeZapZap(gameState, callerIndex, activePlayers) {
        const callerHand = gameState.getPlayerHand(callerIndex);
        const callerBasePoints = CardAnalyzer.calculateHandValue(callerHand);

        // Calculate base hand points for all active players
        const baseHandPoints = {};
        for (const playerIndex of activePlayers) {
            const hand = gameState.getPlayerHand(playerIndex);
            baseHandPoints[playerIndex] = CardAnalyzer.calculateHandValue(hand);
        }

        // Check for counteract
        let counteracted = false;
        for (const playerIndex of activePlayers) {
            if (playerIndex !== callerIndex && baseHandPoints[playerIndex] <= callerBasePoints) {
                counteracted = true;
                break;
            }
        }

        // Find lowest base value
        const lowestBaseValue = Math.min(...Object.values(baseHandPoints));

        // Calculate actual hand scores (Joker = 25)
        const handScores = {};
        for (const playerIndex of activePlayers) {
            const hand = gameState.getPlayerHand(playerIndex);
            handScores[playerIndex] = CardAnalyzer.calculateHandScore(hand, false);
        }

        // Calculate new scores
        const newScores = { ...gameState.scores };

        if (counteracted) {
            // Caller gets penalty
            const callerPenalty = handScores[callerIndex] + ((activePlayers.length - 1) * 5);
            newScores[callerIndex] += callerPenalty;

            // Other players
            for (const playerIndex of activePlayers) {
                if (playerIndex === callerIndex) continue;

                const isLowest = baseHandPoints[playerIndex] === lowestBaseValue;
                if (!isLowest) {
                    newScores[playerIndex] += handScores[playerIndex];
                }
                // Lowest gets 0
            }
        } else {
            // Caller (lowest) gets 0
            // Others get their hand scores
            for (const playerIndex of activePlayers) {
                if (playerIndex !== callerIndex) {
                    newScores[playerIndex] += handScores[playerIndex];
                }
            }
        }

        return gameState.with({
            scores: newScores,
            currentAction: 'finished',
            lastAction: {
                type: 'zapzap',
                playerIndex: callerIndex,
                wasCounterActed: counteracted,
                callerHandPoints: callerBasePoints
            }
        });
    }

    /**
     * Process round end - check for eliminations and golden score
     * Rotates starting player for next round
     */
    processRoundEnd(gameState) {
        const scores = gameState.scores;
        const eliminatedPlayers = [...gameState.eliminatedPlayers];

        // Check for new eliminations
        for (let i = 0; i < this.playerCount; i++) {
            if (scores[i] > 100 && !eliminatedPlayers.includes(i)) {
                eliminatedPlayers.push(i);
            }
        }

        // Count active players
        const activePlayers = [];
        for (let i = 0; i < this.playerCount; i++) {
            if (!eliminatedPlayers.includes(i)) {
                activePlayers.push(i);
            }
        }

        // Check for golden score
        let isGoldenScore = gameState.isGoldenScore;
        if (!isGoldenScore && activePlayers.length === 2) {
            isGoldenScore = true;
        }

        // Rotate starting player for next round
        // The starting player advances by 1 each round (wrapping around)
        // This ensures fairness - each position gets to start equally often
        let nextTurn = (gameState.currentTurn + 1) % this.playerCount;

        // Find next active player from that position
        let attempts = 0;
        while (eliminatedPlayers.includes(nextTurn) && attempts < this.playerCount) {
            nextTurn = (nextTurn + 1) % this.playerCount;
            attempts++;
        }

        return gameState.with({
            eliminatedPlayers,
            isGoldenScore,
            currentTurn: nextTurn,
            currentAction: 'selectHandSize',
            roundNumber: gameState.roundNumber + 1
        });
    }

    /**
     * Check if game is finished
     */
    isGameFinished(gameState) {
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        const activePlayers = [];

        for (let i = 0; i < this.playerCount; i++) {
            if (!eliminatedPlayers.includes(i)) {
                activePlayers.push(i);
            }
        }

        // Game ends if 1 or fewer players remain
        if (activePlayers.length <= 1) {
            return true;
        }

        // Golden Score: game ends when scores differ
        if (gameState.isGoldenScore && activePlayers.length === 2) {
            const score1 = gameState.scores[activePlayers[0]] || 0;
            const score2 = gameState.scores[activePlayers[1]] || 0;
            if (score1 !== score2 && gameState.currentAction === 'finished') {
                return true;
            }
        }

        return false;
    }

    /**
     * Determine the winner
     */
    determineWinner(gameState) {
        const eliminatedPlayers = gameState.eliminatedPlayers || [];
        const scores = gameState.scores;

        // Find active players
        const activePlayers = [];
        for (let i = 0; i < this.playerCount; i++) {
            if (!eliminatedPlayers.includes(i)) {
                activePlayers.push(i);
            }
        }

        if (activePlayers.length === 1) {
            return activePlayers[0];
        }

        if (activePlayers.length === 0) {
            // All eliminated - lowest score wins
            let winner = 0;
            let lowestScore = scores[0] || Infinity;
            for (let i = 1; i < this.playerCount; i++) {
                if ((scores[i] || 0) < lowestScore) {
                    lowestScore = scores[i];
                    winner = i;
                }
            }
            return winner;
        }

        // Multiple active - lowest score wins
        let winner = activePlayers[0];
        let lowestScore = scores[winner] || Infinity;
        for (const playerIndex of activePlayers) {
            if ((scores[playerIndex] || 0) < lowestScore) {
                lowestScore = scores[playerIndex];
                winner = playerIndex;
            }
        }
        return winner;
    }

    /**
     * Advance to next active player's turn
     */
    advanceTurn(gameState, eliminatedPlayers) {
        let nextTurn = (gameState.currentTurn + 1) % this.playerCount;
        while (eliminatedPlayers.includes(nextTurn)) {
            nextTurn = (nextTurn + 1) % this.playerCount;
        }

        return gameState.with({
            currentTurn: nextTurn,
            currentAction: 'play'
        });
    }

    /**
     * Validate and clamp hand size
     */
    validateHandSize(handSize, isGoldenScore) {
        const minHandSize = 4;
        const maxHandSize = isGoldenScore ? 10 : 7;
        return Math.max(minHandSize, Math.min(maxHandSize, handSize));
    }

    /**
     * Fisher-Yates shuffle
     */
    shuffleArray(array) {
        for (let i = array.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [array[i], array[j]] = [array[j], array[i]];
        }
        return array;
    }
}

module.exports = HeadlessGameEngine;
