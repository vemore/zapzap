/**
 * PartySettings Value Object
 * Represents immutable party configuration
 */

class PartySettings {
    /**
     * Create PartySettings
     * @param {Object} props - Settings properties
     * @param {number} props.playerCount - Number of players (3-8)
     * @param {number} props.handSize - Starting hand size (5-7)
     * @param {boolean} props.allowSpectators - Allow spectators
     * @param {number} props.roundTimeLimit - Time limit per round in seconds (0 = unlimited)
     */
    constructor({ playerCount, handSize, allowSpectators = false, roundTimeLimit = 0 }) {
        this.validate(playerCount, handSize, roundTimeLimit);

        this._playerCount = playerCount;
        this._handSize = handSize;
        this._allowSpectators = allowSpectators;
        this._roundTimeLimit = roundTimeLimit;

        // Make immutable
        Object.freeze(this);
    }

    /**
     * Validate settings
     * @private
     */
    validate(playerCount, handSize, roundTimeLimit) {
        if (typeof playerCount !== 'number' || playerCount < 3 || playerCount > 8) {
            throw new Error('Player count must be between 3 and 8');
        }

        if (typeof handSize !== 'number' || handSize < 5 || handSize > 7) {
            throw new Error('Hand size must be between 5 and 7');
        }

        if (typeof roundTimeLimit !== 'number' || roundTimeLimit < 0) {
            throw new Error('Round time limit must be a non-negative number');
        }
    }

    // Getters
    get playerCount() {
        return this._playerCount;
    }

    get handSize() {
        return this._handSize;
    }

    get allowSpectators() {
        return this._allowSpectators;
    }

    get roundTimeLimit() {
        return this._roundTimeLimit;
    }

    /**
     * Create default settings
     * @returns {PartySettings}
     */
    static createDefault() {
        return new PartySettings({
            playerCount: 5,
            handSize: 7,
            allowSpectators: false,
            roundTimeLimit: 0
        });
    }

    /**
     * Convert to JSON string
     * @returns {string}
     */
    toJSON() {
        return JSON.stringify({
            playerCount: this._playerCount,
            handSize: this._handSize,
            allowSpectators: this._allowSpectators,
            roundTimeLimit: this._roundTimeLimit
        });
    }

    /**
     * Convert to plain object
     * @returns {Object}
     */
    toObject() {
        return {
            playerCount: this._playerCount,
            handSize: this._handSize,
            allowSpectators: this._allowSpectators,
            roundTimeLimit: this._roundTimeLimit
        };
    }

    /**
     * Create from JSON string
     * @param {string} jsonString - JSON string
     * @returns {PartySettings}
     */
    static fromJSON(jsonString) {
        const obj = JSON.parse(jsonString);
        return new PartySettings(obj);
    }

    /**
     * Check equality with another PartySettings
     * @param {PartySettings} other - Other settings
     * @returns {boolean}
     */
    equals(other) {
        if (!(other instanceof PartySettings)) {
            return false;
        }

        return (
            this._playerCount === other._playerCount &&
            this._handSize === other._handSize &&
            this._allowSpectators === other._allowSpectators &&
            this._roundTimeLimit === other._roundTimeLimit
        );
    }

    /**
     * Create new settings with modified properties
     * @param {Object} changes - Properties to change
     * @returns {PartySettings} New PartySettings instance
     */
    with(changes) {
        return new PartySettings({
            playerCount: changes.playerCount ?? this._playerCount,
            handSize: changes.handSize ?? this._handSize,
            allowSpectators: changes.allowSpectators ?? this._allowSpectators,
            roundTimeLimit: changes.roundTimeLimit ?? this._roundTimeLimit
        });
    }
}

module.exports = PartySettings;
