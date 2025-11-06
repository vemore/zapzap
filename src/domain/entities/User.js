/**
 * User Entity
 * Represents a registered user in the system
 */

const bcrypt = require('bcryptjs');
const crypto = require('crypto');

class User {
    /**
     * Create a new User
     * @param {Object} props - User properties
     * @param {string} props.id - User ID (UUID)
     * @param {string} props.username - Username (unique)
     * @param {string} props.passwordHash - Hashed password
     * @param {number} props.createdAt - Creation timestamp
     * @param {number} props.updatedAt - Last update timestamp
     */
    constructor({ id, username, passwordHash, createdAt, updatedAt }) {
        this.validate(username, passwordHash);

        this._id = id || crypto.randomUUID();
        this._username = username;
        this._passwordHash = passwordHash;
        this._createdAt = createdAt || Math.floor(Date.now() / 1000);
        this._updatedAt = updatedAt || Math.floor(Date.now() / 1000);
    }

    /**
     * Validate user properties
     * @private
     */
    validate(username, passwordHash) {
        if (!username || typeof username !== 'string') {
            throw new Error('Username is required and must be a string');
        }

        if (username.trim().length < 3) {
            throw new Error('Username must be at least 3 characters long');
        }

        if (username.trim().length > 50) {
            throw new Error('Username must not exceed 50 characters');
        }

        if (!/^[a-zA-Z0-9_-]+$/.test(username)) {
            throw new Error('Username can only contain alphanumeric characters, hyphens, and underscores');
        }

        if (!passwordHash || typeof passwordHash !== 'string') {
            throw new Error('Password hash is required');
        }
    }

    // Getters
    get id() {
        return this._id;
    }

    get username() {
        return this._username;
    }

    get passwordHash() {
        return this._passwordHash;
    }

    get createdAt() {
        return this._createdAt;
    }

    get updatedAt() {
        return this._updatedAt;
    }

    /**
     * Create a new User with plain password
     * @param {string} username - Username
     * @param {string} plainPassword - Plain text password
     * @returns {Promise<User>} New User instance
     */
    static async create(username, plainPassword) {
        if (!plainPassword || typeof plainPassword !== 'string') {
            throw new Error('Password is required');
        }

        if (plainPassword.length < 6) {
            throw new Error('Password must be at least 6 characters long');
        }

        const passwordHash = await bcrypt.hash(plainPassword, 10);

        return new User({
            username: username.trim(),
            passwordHash
        });
    }

    /**
     * Verify password against stored hash
     * @param {string} plainPassword - Plain text password to verify
     * @returns {Promise<boolean>} True if password matches
     */
    async verifyPassword(plainPassword) {
        return bcrypt.compare(plainPassword, this._passwordHash);
    }

    /**
     * Update username
     * @param {string} newUsername - New username
     */
    updateUsername(newUsername) {
        if (!newUsername || typeof newUsername !== 'string') {
            throw new Error('Username is required and must be a string');
        }

        const trimmed = newUsername.trim();

        if (trimmed.length < 3 || trimmed.length > 50) {
            throw new Error('Username must be between 3 and 50 characters');
        }

        if (!/^[a-zA-Z0-9_-]+$/.test(trimmed)) {
            throw new Error('Username can only contain alphanumeric characters, hyphens, and underscores');
        }

        this._username = trimmed;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update password
     * @param {string} plainPassword - New plain text password
     * @returns {Promise<void>}
     */
    async updatePassword(plainPassword) {
        if (!plainPassword || typeof plainPassword !== 'string') {
            throw new Error('Password is required');
        }

        if (plainPassword.length < 6) {
            throw new Error('Password must be at least 6 characters long');
        }

        this._passwordHash = await bcrypt.hash(plainPassword, 10);
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Convert to plain object for persistence
     * @returns {Object}
     */
    toObject() {
        return {
            id: this._id,
            username: this._username,
            passwordHash: this._passwordHash,
            createdAt: this._createdAt,
            updatedAt: this._updatedAt
        };
    }

    /**
     * Convert to safe object for API responses (no password hash)
     * @returns {Object}
     */
    toPublicObject() {
        return {
            id: this._id,
            username: this._username,
            createdAt: this._createdAt,
            updatedAt: this._updatedAt
        };
    }

    /**
     * Reconstruct User from database record
     * @param {Object} record - Database record
     * @returns {User}
     */
    static fromDatabase(record) {
        return new User({
            id: record.id,
            username: record.username,
            passwordHash: record.password_hash,
            createdAt: record.created_at,
            updatedAt: record.updated_at
        });
    }
}

module.exports = User;
