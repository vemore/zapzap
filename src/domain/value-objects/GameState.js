/**
 * GameState Value Object
 * Represents immutable snapshot of game state
 */

class GameState {
    /**
     * Create GameState
     * @param {Object} props - State properties
     * @param {Array<number>} props.deck - Array of card IDs in deck
     * @param {Object<string, Array<number>>} props.hands - Map of player index to card IDs
     * @param {Array<number>} props.lastCardsPlayed - Card IDs from previous turn
     * @param {Array<number>} props.cardsPlayed - Card IDs from current turn
     * @param {Object<string, number>} props.scores - Map of player index to scores
     * @param {number} props.currentTurn - Current turn number
     * @param {string} props.currentAction - Current action ('draw', 'play', 'zapzap')
     * @param {number} props.roundNumber - Current round number
     * @param {Object} props.lastAction - Last action performed { type, playerIndex, source?, cardId? }
     * @param {boolean} props.isGoldenScore - Whether the game is in Golden Score mode (final 2 players)
     * @param {Array<number>} props.eliminatedPlayers - Player indices who are eliminated (score > 100)
     */
    constructor({
        deck = [],
        hands = {},
        lastCardsPlayed = [],
        cardsPlayed = [],
        scores = {},
        currentTurn = 0,
        currentAction = 'draw',
        roundNumber = 1,
        lastAction = null,
        isGoldenScore = false,
        eliminatedPlayers = []
    }) {
        this._deck = [...deck];
        this._hands = JSON.parse(JSON.stringify(hands));
        this._lastCardsPlayed = [...lastCardsPlayed];
        this._cardsPlayed = [...cardsPlayed];
        this._scores = JSON.parse(JSON.stringify(scores));
        this._currentTurn = currentTurn;
        this._currentAction = currentAction;
        this._roundNumber = roundNumber;
        this._lastAction = lastAction ? { ...lastAction } : null;
        this._isGoldenScore = isGoldenScore;
        this._eliminatedPlayers = [...eliminatedPlayers];

        // Make immutable
        Object.freeze(this);
    }

    // Getters
    get deck() {
        return [...this._deck];
    }

    get hands() {
        return JSON.parse(JSON.stringify(this._hands));
    }

    get lastCardsPlayed() {
        return [...this._lastCardsPlayed];
    }

    get cardsPlayed() {
        return [...this._cardsPlayed];
    }

    get scores() {
        return JSON.parse(JSON.stringify(this._scores));
    }

    get currentTurn() {
        return this._currentTurn;
    }

    get currentAction() {
        return this._currentAction;
    }

    get roundNumber() {
        return this._roundNumber;
    }

    get lastAction() {
        return this._lastAction ? { ...this._lastAction } : null;
    }

    get isGoldenScore() {
        return this._isGoldenScore;
    }

    get eliminatedPlayers() {
        return [...this._eliminatedPlayers];
    }

    /**
     * Get hand for specific player
     * @param {number} playerIndex - Player index
     * @returns {Array<number>} Card IDs
     */
    getPlayerHand(playerIndex) {
        return this._hands[playerIndex] ? [...this._hands[playerIndex]] : [];
    }

    /**
     * Get score for specific player
     * @param {number} playerIndex - Player index
     * @returns {number} Score
     */
    getPlayerScore(playerIndex) {
        return this._scores[playerIndex] || 0;
    }

    /**
     * Get number of cards in deck
     * @returns {number}
     */
    getDeckSize() {
        return this._deck.length;
    }

    /**
     * Create initial game state
     * @param {number} playerCount - Number of players
     * @returns {GameState}
     */
    static createInitial(playerCount) {
        const hands = {};
        const scores = {};

        for (let i = 0; i < playerCount; i++) {
            hands[i] = [];
            scores[i] = 0;
        }

        return new GameState({
            deck: [],
            hands,
            lastCardsPlayed: [],
            cardsPlayed: [],
            scores,
            currentTurn: 0,
            currentAction: 'draw',
            roundNumber: 1
        });
    }

    /**
     * Create new state with updated properties
     * @param {Object} updates - Properties to update
     * @returns {GameState} New GameState instance
     */
    with(updates) {
        return new GameState({
            deck: updates.deck !== undefined ? updates.deck : this._deck,
            hands: updates.hands !== undefined ? updates.hands : this._hands,
            lastCardsPlayed: updates.lastCardsPlayed !== undefined ? updates.lastCardsPlayed : this._lastCardsPlayed,
            cardsPlayed: updates.cardsPlayed !== undefined ? updates.cardsPlayed : this._cardsPlayed,
            scores: updates.scores !== undefined ? updates.scores : this._scores,
            currentTurn: updates.currentTurn !== undefined ? updates.currentTurn : this._currentTurn,
            currentAction: updates.currentAction !== undefined ? updates.currentAction : this._currentAction,
            roundNumber: updates.roundNumber !== undefined ? updates.roundNumber : this._roundNumber,
            lastAction: updates.lastAction !== undefined ? updates.lastAction : this._lastAction,
            isGoldenScore: updates.isGoldenScore !== undefined ? updates.isGoldenScore : this._isGoldenScore,
            eliminatedPlayers: updates.eliminatedPlayers !== undefined ? updates.eliminatedPlayers : this._eliminatedPlayers
        });
    }

    /**
     * Alias for with() method
     * @param {Object} updates - Properties to update
     * @returns {GameState} New GameState instance
     */
    withUpdates(updates) {
        return this.with(updates);
    }

    /**
     * Convert to JSON string
     * @returns {string}
     */
    toJSON() {
        return JSON.stringify({
            deck: this._deck,
            hands: this._hands,
            lastCardsPlayed: this._lastCardsPlayed,
            cardsPlayed: this._cardsPlayed,
            scores: this._scores,
            currentTurn: this._currentTurn,
            currentAction: this._currentAction,
            roundNumber: this._roundNumber,
            lastAction: this._lastAction,
            isGoldenScore: this._isGoldenScore,
            eliminatedPlayers: this._eliminatedPlayers
        });
    }

    /**
     * Convert to plain object
     * @returns {Object}
     */
    toObject() {
        return {
            deck: [...this._deck],
            hands: JSON.parse(JSON.stringify(this._hands)),
            lastCardsPlayed: [...this._lastCardsPlayed],
            cardsPlayed: [...this._cardsPlayed],
            scores: JSON.parse(JSON.stringify(this._scores)),
            currentTurn: this._currentTurn,
            currentAction: this._currentAction,
            roundNumber: this._roundNumber,
            lastAction: this._lastAction ? { ...this._lastAction } : null,
            isGoldenScore: this._isGoldenScore,
            eliminatedPlayers: [...this._eliminatedPlayers]
        };
    }

    /**
     * Convert to public object for API responses
     * @returns {Object}
     */
    toPublicObject() {
        return {
            deck: [...this._deck],
            hands: JSON.parse(JSON.stringify(this._hands)),
            lastCardsPlayed: [...this._lastCardsPlayed],
            cardsPlayed: [...this._cardsPlayed],
            scores: JSON.parse(JSON.stringify(this._scores)),
            currentTurn: this._currentTurn,
            currentAction: this._currentAction,
            roundNumber: this._roundNumber,
            lastAction: this._lastAction ? { ...this._lastAction } : null,
            isGoldenScore: this._isGoldenScore,
            eliminatedPlayers: [...this._eliminatedPlayers]
        };
    }

    /**
     * Create from JSON string
     * @param {string} jsonString - JSON string
     * @returns {GameState}
     */
    static fromJSON(jsonString) {
        const obj = JSON.parse(jsonString);
        return new GameState(obj);
    }

    /**
     * Check equality with another GameState
     * @param {GameState} other - Other state
     * @returns {boolean}
     */
    equals(other) {
        if (!(other instanceof GameState)) {
            return false;
        }

        return this.toJSON() === other.toJSON();
    }
}

module.exports = GameState;
