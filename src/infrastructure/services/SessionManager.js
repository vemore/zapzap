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
        // Map<userId, number>: open event streams per user. A user is online
        // while at least one is open (two tabs, or a reconnection whose new
        // stream opens before the old one is seen closing).
        this.streams = new Map();
    }

    /**
     * Register one event stream of a user.
     * @param {string} userId
     * @param {string} username
     * @returns {object|null} The new session on the user's first stream,
     *   null when the user was already connected (the session is kept as is).
     */
    connect(userId, username) {
        const open = this.streams.get(userId) || 0;
        this.streams.set(userId, open + 1);
        if (open > 0 && this.sessions.has(userId)) {
            return null;
        }
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
     * Unregister one event stream of a user.
     * @param {string} userId
     * @returns {object|null} The removed session when that was the user's
     *   last stream, null while another one is still open or if not found.
     */
    disconnect(userId) {
        const open = (this.streams.get(userId) || 1) - 1;
        if (open > 0) {
            this.streams.set(userId, open);
            return null;
        }
        this.streams.delete(userId);
        const session = this.sessions.get(userId) || null;
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
