/**
 * PartyPlayer Entity
 * Represents a user's membership in a party
 */

class PartyPlayer {
    /**
     * Create a new PartyPlayer
     * @param {Object} props - PartyPlayer properties
     * @param {number} props.id - Auto-increment ID
     * @param {string} props.partyId - Party ID
     * @param {string} props.userId - User ID
     * @param {number} props.playerIndex - Player index/position (0-based)
     * @param {number} props.joinedAt - Timestamp when joined
     */
    constructor({ id, partyId, userId, playerIndex, joinedAt }) {
        this.validate(partyId, userId, playerIndex);

        this._id = id;
        this._partyId = partyId;
        this._userId = userId;
        this._playerIndex = playerIndex;
        this._joinedAt = joinedAt || Math.floor(Date.now() / 1000);
    }

    /**
     * Validate properties
     * @private
     */
    validate(partyId, userId, playerIndex) {
        if (!partyId || typeof partyId !== 'string') {
            throw new Error('Party ID is required');
        }

        if (!userId || typeof userId !== 'string') {
            throw new Error('User ID is required');
        }

        if (typeof playerIndex !== 'number' || playerIndex < 0 || playerIndex > 7) {
            throw new Error('Player index must be between 0 and 7');
        }
    }

    // Getters
    get id() {
        return this._id;
    }

    get partyId() {
        return this._partyId;
    }

    get userId() {
        return this._userId;
    }

    get playerIndex() {
        return this._playerIndex;
    }

    get joinedAt() {
        return this._joinedAt;
    }

    /**
     * Convert to plain object
     * @returns {Object}
     */
    toObject() {
        return {
            id: this._id,
            partyId: this._partyId,
            userId: this._userId,
            playerIndex: this._playerIndex,
            joinedAt: this._joinedAt
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
            user_id: this._userId,
            player_index: this._playerIndex,
            joined_at: this._joinedAt
        };
    }

    /**
     * Reconstruct from database record
     * @param {Object} record - Database record
     * @returns {PartyPlayer}
     */
    static fromDatabase(record) {
        return new PartyPlayer({
            id: record.id,
            partyId: record.party_id,
            userId: record.user_id,
            playerIndex: record.player_index,
            joinedAt: record.joined_at
        });
    }

    /**
     * Create a new party player
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @param {number} playerIndex - Player position
     * @returns {PartyPlayer}
     */
    static create(partyId, userId, playerIndex) {
        return new PartyPlayer({
            partyId,
            userId,
            playerIndex
        });
    }
}

module.exports = PartyPlayer;
