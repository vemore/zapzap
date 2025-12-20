/**
 * SessionManager - Tracks connected users and their status
 *
 * Status values:
 * - "lobby" - User is browsing the parties list
 * - "party" - User is in a party lobby (waiting to start)
 * - "game" - User is actively playing in a game
 */

const logger = require('../../../logger');

class SessionManager {
    constructor() {
        // Map<userId, {userId, username, status, partyId, connectedAt}>
        this.sessions = new Map();
    }

    /**
     * Register a user connection
     * @param {string} userId
     * @param {string} username
     * @returns {object} Session info
     */
    connect(userId, username) {
        const session = {
            userId,
            username,
            status: 'lobby',
            partyId: null,
            connectedAt: Date.now()
        };
        this.sessions.set(userId, session);
        logger.info('User connected', { userId, username });
        return session;
    }

    /**
     * Remove a user connection
     * @param {string} userId
     * @returns {object|null} Removed session info or null if not found
     */
    disconnect(userId) {
        const session = this.sessions.get(userId);
        if (session) {
            this.sessions.delete(userId);
            logger.info('User disconnected', { userId, username: session.username });
        }
        return session;
    }

    /**
     * Update user status
     * @param {string} userId
     * @param {'lobby'|'party'|'game'} status
     * @param {string|null} partyId
     * @returns {object|null} Updated session or null if not found
     */
    updateStatus(userId, status, partyId = null) {
        const session = this.sessions.get(userId);
        if (session) {
            session.status = status;
            session.partyId = partyId;
            logger.debug('User status updated', { userId, status, partyId });
        }
        return session;
    }

    /**
     * Get a user's current session
     * @param {string} userId
     * @returns {object|null}
     */
    getSession(userId) {
        return this.sessions.get(userId) || null;
    }

    /**
     * Check if user is connected
     * @param {string} userId
     * @returns {boolean}
     */
    isConnected(userId) {
        return this.sessions.has(userId);
    }

    /**
     * Get last N connected users, sorted by most recently connected
     * @param {number} limit
     * @returns {Array<object>}
     */
    getConnectedUsers(limit = 5) {
        const users = Array.from(this.sessions.values());
        // Sort by connectedAt descending (most recent first)
        users.sort((a, b) => b.connectedAt - a.connectedAt);
        return users.slice(0, limit);
    }

    /**
     * Get all connected users count
     * @returns {number}
     */
    getConnectedCount() {
        return this.sessions.size;
    }

    /**
     * Update status for multiple users at once (e.g., when game starts)
     * @param {Array<string>} userIds
     * @param {'lobby'|'party'|'game'} status
     * @param {string|null} partyId
     */
    updateStatusBulk(userIds, status, partyId = null) {
        for (const userId of userIds) {
            this.updateStatus(userId, status, partyId);
        }
    }
}

module.exports = SessionManager;
