/**
 * Party Entity
 * Represents a game party/room where players can join and play
 */

const crypto = require('crypto');
const PartySettings = require('../value-objects/PartySettings');

/**
 * Party status enum
 */
const PartyStatus = {
    WAITING: 'waiting',
    PLAYING: 'playing',
    FINISHED: 'finished'
};

/**
 * Party visibility enum
 */
const PartyVisibility = {
    PUBLIC: 'public',
    PRIVATE: 'private'
};

class Party {
    /**
     * Create a new Party
     * @param {Object} props - Party properties
     * @param {string} props.id - Party ID (UUID)
     * @param {string} props.name - Party name
     * @param {string} props.ownerId - Owner user ID
     * @param {string} props.inviteCode - Unique invite code
     * @param {string} props.visibility - 'public' or 'private'
     * @param {string} props.status - 'waiting', 'playing', or 'finished'
     * @param {PartySettings} props.settings - Party settings
     * @param {number} props.createdAt - Creation timestamp
     * @param {number} props.updatedAt - Last update timestamp
     */
    constructor({ id, name, ownerId, inviteCode, visibility, status, settings, createdAt, updatedAt }) {
        this.validate(name, ownerId, inviteCode, visibility, status);

        this._id = id || crypto.randomUUID();
        this._name = name;
        this._ownerId = ownerId;
        this._inviteCode = inviteCode || this.generateInviteCode();
        this._visibility = visibility || PartyVisibility.PUBLIC;
        this._status = status || PartyStatus.WAITING;
        this._settings = settings || PartySettings.createDefault();
        this._createdAt = createdAt || Math.floor(Date.now() / 1000);
        this._updatedAt = updatedAt || Math.floor(Date.now() / 1000);
    }

    /**
     * Validate party properties
     * @private
     */
    validate(name, ownerId, inviteCode, visibility, status) {
        if (!name || typeof name !== 'string') {
            throw new Error('Party name is required');
        }

        if (name.trim().length < 3 || name.trim().length > 100) {
            throw new Error('Party name must be between 3 and 100 characters');
        }

        if (!ownerId || typeof ownerId !== 'string') {
            throw new Error('Owner ID is required');
        }

        if (inviteCode && (typeof inviteCode !== 'string' || inviteCode.length !== 8)) {
            throw new Error('Invite code must be 8 characters');
        }

        if (visibility && !Object.values(PartyVisibility).includes(visibility)) {
            throw new Error(`Visibility must be one of: ${Object.values(PartyVisibility).join(', ')}`);
        }

        if (status && !Object.values(PartyStatus).includes(status)) {
            throw new Error(`Status must be one of: ${Object.values(PartyStatus).join(', ')}`);
        }
    }

    /**
     * Generate random invite code
     * @private
     * @returns {string} 8-character invite code
     */
    generateInviteCode() {
        const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excludes confusing characters
        let code = '';
        for (let i = 0; i < 8; i++) {
            code += characters.charAt(Math.floor(Math.random() * characters.length));
        }
        return code;
    }

    // Getters
    get id() {
        return this._id;
    }

    get name() {
        return this._name;
    }

    get ownerId() {
        return this._ownerId;
    }

    get inviteCode() {
        return this._inviteCode;
    }

    get visibility() {
        return this._visibility;
    }

    get status() {
        return this._status;
    }

    get settings() {
        return this._settings;
    }

    get createdAt() {
        return this._createdAt;
    }

    get updatedAt() {
        return this._updatedAt;
    }

    get currentRoundId() {
        return this._currentRoundId;
    }

    /**
     * Check if party is public
     * @returns {boolean}
     */
    isPublic() {
        return this._visibility === PartyVisibility.PUBLIC;
    }

    /**
     * Check if party is waiting for players
     * @returns {boolean}
     */
    isWaiting() {
        return this._status === PartyStatus.WAITING;
    }

    /**
     * Check if party is currently playing
     * @returns {boolean}
     */
    isPlaying() {
        return this._status === PartyStatus.PLAYING;
    }

    /**
     * Check if party is finished
     * @returns {boolean}
     */
    isFinished() {
        return this._status === PartyStatus.FINISHED;
    }

    /**
     * Check if user is the owner
     * @param {string} userId - User ID to check
     * @returns {boolean}
     */
    isOwner(userId) {
        return this._ownerId === userId;
    }

    /**
     * Start the game
     */
    start() {
        if (this._status !== PartyStatus.WAITING) {
            throw new Error(`Cannot start party with status: ${this._status}`);
        }

        this._status = PartyStatus.PLAYING;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Finish the game
     */
    finish() {
        if (this._status !== PartyStatus.PLAYING) {
            throw new Error(`Cannot finish party with status: ${this._status}`);
        }

        this._status = PartyStatus.FINISHED;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update party name
     * @param {string} newName - New party name
     */
    updateName(newName) {
        if (!newName || typeof newName !== 'string') {
            throw new Error('Party name is required');
        }

        const trimmed = newName.trim();
        if (trimmed.length < 3 || trimmed.length > 100) {
            throw new Error('Party name must be between 3 and 100 characters');
        }

        this._name = trimmed;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update visibility
     * @param {string} newVisibility - 'public' or 'private'
     */
    updateVisibility(newVisibility) {
        if (!Object.values(PartyVisibility).includes(newVisibility)) {
            throw new Error(`Visibility must be one of: ${Object.values(PartyVisibility).join(', ')}`);
        }

        this._visibility = newVisibility;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update settings
     * @param {PartySettings} newSettings - New settings
     */
    updateSettings(newSettings) {
        if (!(newSettings instanceof PartySettings)) {
            throw new Error('Settings must be a PartySettings instance');
        }

        if (this._status !== PartyStatus.WAITING) {
            throw new Error('Cannot update settings after party has started');
        }

        this._settings = newSettings;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update owner
     * @param {string} newOwnerId - New owner user ID
     */
    updateOwner(newOwnerId) {
        if (!newOwnerId || typeof newOwnerId !== 'string') {
            throw new Error('New owner ID is required');
        }

        this._ownerId = newOwnerId;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Start a new round
     * @param {string} roundId - Round ID
     */
    startNewRound(roundId) {
        if (!roundId || typeof roundId !== 'string') {
            throw new Error('Round ID is required');
        }

        this._currentRoundId = roundId;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Convert to plain object for persistence
     * @returns {Object}
     */
    toObject() {
        return {
            id: this._id,
            name: this._name,
            ownerId: this._ownerId,
            inviteCode: this._inviteCode,
            visibility: this._visibility,
            status: this._status,
            settings: this._settings.toObject(),
            currentRoundId: this._currentRoundId,
            createdAt: this._createdAt,
            updatedAt: this._updatedAt
        };
    }

    /**
     * Convert to public object for API responses
     * @returns {Object}
     */
    toPublicObject() {
        return {
            id: this._id,
            name: this._name,
            ownerId: this._ownerId,
            inviteCode: this._inviteCode,
            visibility: this._visibility,
            status: this._status,
            settings: this._settings.toObject(),
            currentRoundId: this._currentRoundId,
            createdAt: this._createdAt,
            updatedAt: this._updatedAt
        };
    }

    /**
     * Convert to database format
     * @returns {Object}
     */
    toDatabase() {
        return {
            id: this._id,
            name: this._name,
            owner_id: this._ownerId,
            invite_code: this._inviteCode,
            visibility: this._visibility,
            status: this._status,
            settings_json: this._settings.toJSON(),
            created_at: this._createdAt,
            updated_at: this._updatedAt
        };
    }

    /**
     * Reconstruct Party from database record
     * @param {Object} record - Database record
     * @returns {Party}
     */
    static fromDatabase(record) {
        return new Party({
            id: record.id,
            name: record.name,
            ownerId: record.owner_id,
            inviteCode: record.invite_code,
            visibility: record.visibility,
            status: record.status,
            settings: PartySettings.fromJSON(record.settings_json),
            createdAt: record.created_at,
            updatedAt: record.updated_at
        });
    }

    /**
     * Create a new party
     * @param {string} name - Party name
     * @param {string} ownerId - Owner user ID
     * @param {string} visibility - 'public' or 'private'
     * @param {PartySettings} settings - Party settings
     * @returns {Party}
     */
    static create(name, ownerId, visibility = PartyVisibility.PUBLIC, settings = null) {
        return new Party({
            name: name.trim(),
            ownerId,
            visibility,
            settings: settings || PartySettings.createDefault(),
            status: PartyStatus.WAITING
        });
    }
}

module.exports = Party;
module.exports.PartyStatus = PartyStatus;
module.exports.PartyVisibility = PartyVisibility;
