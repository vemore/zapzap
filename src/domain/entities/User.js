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
     * @param {string} props.passwordHash - Hashed password (optional for OAuth users)
     * @param {string} props.userType - User type ('human' or 'bot')
     * @param {string} props.botDifficulty - Bot difficulty ('easy', 'medium', 'hard') - only for bots
     * @param {boolean} props.isAdmin - Whether user has admin privileges
     * @param {number} props.lastLoginAt - Last login timestamp
     * @param {number} props.totalPlayTimeSeconds - Total play time in seconds
     * @param {string} props.googleId - Google OAuth user ID (optional)
     * @param {string} props.email - User email (optional, from OAuth)
     * @param {number} props.createdAt - Creation timestamp
     * @param {number} props.updatedAt - Last update timestamp
     */
    constructor({ id, username, passwordHash = null, userType = 'human', botDifficulty = null, isAdmin = false, lastLoginAt = null, totalPlayTimeSeconds = 0, googleId = null, email = null, createdAt, updatedAt }) {
        this.validate(username, passwordHash, userType, botDifficulty, googleId);

        this._id = id || crypto.randomUUID();
        this._username = username;
        this._passwordHash = passwordHash;
        this._userType = userType;
        this._botDifficulty = botDifficulty;
        this._isAdmin = isAdmin;
        this._lastLoginAt = lastLoginAt;
        this._totalPlayTimeSeconds = totalPlayTimeSeconds;
        this._googleId = googleId;
        this._email = email;
        this._createdAt = createdAt || Math.floor(Date.now() / 1000);
        this._updatedAt = updatedAt || Math.floor(Date.now() / 1000);
    }

    /**
     * Validate user properties
     * @private
     */
    validate(username, passwordHash, userType, botDifficulty, googleId = null) {
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

        // Password is required for human users without Google OAuth (bots don't need passwords)
        if (userType === 'human' && !googleId && (!passwordHash || typeof passwordHash !== 'string')) {
            throw new Error('Password hash is required for non-OAuth users');
        }

        // Validate user type
        if (!['human', 'bot'].includes(userType)) {
            throw new Error('User type must be either "human" or "bot"');
        }

        // Validate bot difficulty
        const validDifficulties = ['easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm', 'thibot'];
        if (userType === 'bot') {
            if (!botDifficulty || !validDifficulties.includes(botDifficulty)) {
                throw new Error(`Bot difficulty must be one of: ${validDifficulties.join(', ')}`);
            }
        }

        if (userType === 'human' && botDifficulty) {
            throw new Error('Bot difficulty should not be set for human users');
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

    get userType() {
        return this._userType;
    }

    get botDifficulty() {
        return this._botDifficulty;
    }

    get createdAt() {
        return this._createdAt;
    }

    get updatedAt() {
        return this._updatedAt;
    }

    get isAdmin() {
        return this._isAdmin;
    }

    get lastLoginAt() {
        return this._lastLoginAt;
    }

    get totalPlayTimeSeconds() {
        return this._totalPlayTimeSeconds;
    }

    get googleId() {
        return this._googleId;
    }

    get email() {
        return this._email;
    }

    /**
     * Check if user is a bot
     * @returns {boolean}
     */
    isBot() {
        return this._userType === 'bot';
    }

    /**
     * Check if user is human
     * @returns {boolean}
     */
    isHuman() {
        return this._userType === 'human';
    }

    /**
     * Check if user has admin privileges
     * @returns {boolean}
     */
    isAdminUser() {
        return this._isAdmin === true || this._isAdmin === 1;
    }

    /**
     * Check if user is authenticated via Google OAuth
     * @returns {boolean}
     */
    isGoogleUser() {
        return !!this._googleId;
    }

    /**
     * Set admin status
     * @param {boolean} value - Admin status
     */
    setAdmin(value) {
        this._isAdmin = value;
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Update last login timestamp to now
     */
    updateLastLogin() {
        this._lastLoginAt = Math.floor(Date.now() / 1000);
        this._updatedAt = Math.floor(Date.now() / 1000);
    }

    /**
     * Add play time
     * @param {number} seconds - Seconds to add
     */
    addPlayTime(seconds) {
        this._totalPlayTimeSeconds += seconds;
        this._updatedAt = Math.floor(Date.now() / 1000);
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
            passwordHash,
            userType: 'human'
        });
    }

    /**
     * Create a new User from Google OAuth profile
     * @param {Object} googleProfile - Google profile data
     * @param {string} googleProfile.googleId - Google user ID
     * @param {string} googleProfile.email - User email
     * @param {string} googleProfile.name - User display name
     * @param {string} username - Generated username
     * @returns {User} New User instance
     */
    static createFromGoogle({ googleId, email, name }, username) {
        return new User({
            username: username.trim(),
            passwordHash: null,
            userType: 'human',
            googleId,
            email
        });
    }

    /**
     * Create a new Bot user
     * @param {string} username - Bot username
     * @param {string} difficulty - Bot difficulty ('easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm', 'thibot')
     * @returns {Promise<User>} New Bot user instance
     */
    static async createBot(username, difficulty) {
        const validDifficulties = ['easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm', 'thibot'];
        if (!difficulty || !validDifficulties.includes(difficulty)) {
            throw new Error(`Bot difficulty must be one of: ${validDifficulties.join(', ')}`);
        }

        // Bots don't need real passwords, use a placeholder hash
        const passwordHash = await bcrypt.hash('bot-no-password-' + crypto.randomUUID(), 10);

        return new User({
            username: username.trim(),
            passwordHash,
            userType: 'bot',
            botDifficulty: difficulty
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
            userType: this._userType,
            botDifficulty: this._botDifficulty,
            isAdmin: this._isAdmin,
            lastLoginAt: this._lastLoginAt,
            totalPlayTimeSeconds: this._totalPlayTimeSeconds,
            googleId: this._googleId,
            email: this._email,
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
            userType: this._userType,
            botDifficulty: this._botDifficulty,
            isAdmin: this._isAdmin,
            lastLoginAt: this._lastLoginAt,
            totalPlayTimeSeconds: this._totalPlayTimeSeconds,
            email: this._email,
            isGoogleUser: !!this._googleId,
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
            passwordHash: record.password_hash || null,
            userType: record.user_type || 'human',
            botDifficulty: record.bot_difficulty || null,
            isAdmin: record.is_admin === 1,
            lastLoginAt: record.last_login_at || null,
            totalPlayTimeSeconds: record.total_play_time_seconds || 0,
            googleId: record.google_id || null,
            email: record.email || null,
            createdAt: record.created_at,
            updatedAt: record.updated_at
        });
    }
}

module.exports = User;
