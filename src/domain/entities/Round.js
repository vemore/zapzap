/**
 * Round Entity
 * Represents a single round of play in a party
 */

const crypto = require('crypto');

/**
 * Round status enum
 */
const RoundStatus = {
    ACTIVE: 'active',
    FINISHED: 'finished'
};

/**
 * Round action enum
 */
const RoundAction = {
    DRAW: 'draw',
    PLAY: 'play',
    ZAPZAP: 'zapzap'
};

class Round {
    /**
     * Create a new Round
     * @param {Object} props - Round properties
     * @param {string} props.id - Round ID (UUID)
     * @param {string} props.partyId - Party ID
     * @param {number} props.roundNumber - Round number (1-based)
     * @param {string} props.status - 'active' or 'finished'
     * @param {number} props.currentTurn - Current turn number (0-based)
     * @param {string} props.currentAction - 'draw', 'play', or 'zapzap'
     * @param {number} props.createdAt - Creation timestamp
     * @param {number} props.finishedAt - Finish timestamp (null if active)
     */
    constructor({
        id,
        partyId,
        roundNumber = 1,
        status = RoundStatus.ACTIVE,
        currentTurn = 0,
        currentAction = RoundAction.DRAW,
        createdAt,
        finishedAt = null
    }) {
        this.validate(partyId, roundNumber, status, currentAction);

        this._id = id || crypto.randomUUID();
        this._partyId = partyId;
        this._roundNumber = roundNumber;
        this._status = status;
        this._currentTurn = currentTurn;
        this._currentAction = currentAction;
        this._createdAt = createdAt || Math.floor(Date.now() / 1000);
        this._finishedAt = finishedAt;
    }

    /**
     * Validate round properties
     * @private
     */
    validate(partyId, roundNumber, status, currentAction) {
        if (!partyId || typeof partyId !== 'string') {
            throw new Error('Party ID is required');
        }

        if (typeof roundNumber !== 'number' || roundNumber < 1) {
            throw new Error('Round number must be a positive integer');
        }

        if (status && !Object.values(RoundStatus).includes(status)) {
            throw new Error(`Status must be one of: ${Object.values(RoundStatus).join(', ')}`);
        }

        if (currentAction && !Object.values(RoundAction).includes(currentAction)) {
            throw new Error(`Action must be one of: ${Object.values(RoundAction).join(', ')}`);
        }
    }

    // Getters
    get id() {
        return this._id;
    }

    get partyId() {
        return this._partyId;
    }

    get roundNumber() {
        return this._roundNumber;
    }

    get status() {
        return this._status;
    }

    get currentTurn() {
        return this._currentTurn;
    }

    get currentAction() {
        return this._currentAction;
    }

    get createdAt() {
        return this._createdAt;
    }

    get finishedAt() {
        return this._finishedAt;
    }

    /**
     * Check if round is active
     * @returns {boolean}
     */
    isActive() {
        return this._status === RoundStatus.ACTIVE;
    }

    /**
     * Check if round is finished
     * @returns {boolean}
     */
    isFinished() {
        return this._status === RoundStatus.FINISHED;
    }

    /**
     * Check if current action is draw
     * @returns {boolean}
     */
    isDrawPhase() {
        return this._currentAction === RoundAction.DRAW;
    }

    /**
     * Check if current action is play
     * @returns {boolean}
     */
    isPlayPhase() {
        return this._currentAction === RoundAction.PLAY;
    }

    /**
     * Check if current action is zapzap
     * @returns {boolean}
     */
    isZapZapPhase() {
        return this._currentAction === RoundAction.ZAPZAP;
    }

    /**
     * Get current player index
     * @param {number} playerCount - Total number of players
     * @returns {number} Current player index
     */
    getCurrentPlayerIndex(playerCount) {
        return this._currentTurn % playerCount;
    }

    /**
     * Advance to next turn
     */
    nextTurn() {
        if (!this.isActive()) {
            throw new Error('Cannot advance turn on finished round');
        }

        this._currentTurn++;
        this._currentAction = RoundAction.DRAW;
    }

    /**
     * Set action to play
     */
    setPlayPhase() {
        if (!this.isActive()) {
            throw new Error('Cannot change action on finished round');
        }

        this._currentAction = RoundAction.PLAY;
    }

    /**
     * Set action to draw
     */
    setDrawPhase() {
        if (!this.isActive()) {
            throw new Error('Cannot change action on finished round');
        }

        this._currentAction = RoundAction.DRAW;
    }

    /**
     * Trigger zapzap and finish round
     */
    triggerZapZap() {
        if (!this.isActive()) {
            throw new Error('Cannot trigger zapzap on finished round');
        }

        this._currentAction = RoundAction.ZAPZAP;
        this.finish();
    }

    /**
     * Finish the round
     */
    finish() {
        if (!this.isActive()) {
            throw new Error('Round is already finished');
        }

        this._status = RoundStatus.FINISHED;
        this._finishedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Convert to plain object
     * @returns {Object}
     */
    toObject() {
        return {
            id: this._id,
            partyId: this._partyId,
            roundNumber: this._roundNumber,
            status: this._status,
            currentTurn: this._currentTurn,
            currentAction: this._currentAction,
            createdAt: this._createdAt,
            finishedAt: this._finishedAt
        };
    }

    /**
     * Convert to database format
     * @returns {Object}
     */
    toDatabase() {
        return {
            id: this._id,
            party_id: this._partyId,
            round_number: this._roundNumber,
            status: this._status,
            current_turn: this._currentTurn,
            current_action: this._currentAction,
            created_at: this._createdAt,
            finished_at: this._finishedAt
        };
    }

    /**
     * Reconstruct from database record
     * @param {Object} record - Database record
     * @returns {Round}
     */
    static fromDatabase(record) {
        return new Round({
            id: record.id,
            partyId: record.party_id,
            roundNumber: record.round_number,
            status: record.status,
            currentTurn: record.current_turn,
            currentAction: record.current_action,
            createdAt: record.created_at,
            finishedAt: record.finished_at
        });
    }

    /**
     * Create a new round
     * @param {string} partyId - Party ID
     * @param {number} roundNumber - Round number
     * @returns {Round}
     */
    static create(partyId, roundNumber = 1) {
        return new Round({
            partyId,
            roundNumber,
            status: RoundStatus.ACTIVE,
            currentTurn: 0,
            currentAction: RoundAction.DRAW
        });
    }
}

module.exports = Round;
module.exports.RoundStatus = RoundStatus;
module.exports.RoundAction = RoundAction;
