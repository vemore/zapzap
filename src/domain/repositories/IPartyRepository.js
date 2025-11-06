/**
 * IPartyRepository Interface
 * Defines the contract for Party data access
 */

class IPartyRepository {
    /**
     * Find party by ID
     * @param {string} id - Party ID
     * @returns {Promise<Party|null>} Party or null if not found
     */
    async findById(id) {
        throw new Error('Method not implemented');
    }

    /**
     * Find party by invite code
     * @param {string} inviteCode - Invite code
     * @returns {Promise<Party|null>} Party or null if not found
     */
    async findByInviteCode(inviteCode) {
        throw new Error('Method not implemented');
    }

    /**
     * Find all public parties
     * @param {string} status - Optional status filter ('waiting', 'playing', 'finished')
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Party>>} Array of parties
     */
    async findPublicParties(status = null, limit = 50, offset = 0) {
        throw new Error('Method not implemented');
    }

    /**
     * Find parties owned by user
     * @param {string} userId - Owner user ID
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Party>>} Array of parties
     */
    async findByOwner(userId, limit = 50, offset = 0) {
        throw new Error('Method not implemented');
    }

    /**
     * Save party (create or update)
     * @param {Party} party - Party entity
     * @returns {Promise<Party>} Saved party
     */
    async save(party) {
        throw new Error('Method not implemented');
    }

    /**
     * Delete party by ID
     * @param {string} id - Party ID
     * @returns {Promise<boolean>} True if deleted
     */
    async delete(id) {
        throw new Error('Method not implemented');
    }

    /**
     * Add player to party
     * @param {PartyPlayer} partyPlayer - PartyPlayer entity
     * @returns {Promise<PartyPlayer>} Saved party player
     */
    async addPlayer(partyPlayer) {
        throw new Error('Method not implemented');
    }

    /**
     * Remove player from party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<boolean>} True if removed
     */
    async removePlayer(partyId, userId) {
        throw new Error('Method not implemented');
    }

    /**
     * Get players in party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<PartyPlayer>>} Array of party players
     */
    async getPlayers(partyId) {
        throw new Error('Method not implemented');
    }

    /**
     * Get player count in party
     * @param {string} partyId - Party ID
     * @returns {Promise<number>} Number of players
     */
    async getPlayerCount(partyId) {
        throw new Error('Method not implemented');
    }

    /**
     * Check if user is in party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<boolean>} True if user is in party
     */
    async isUserInParty(partyId, userId) {
        throw new Error('Method not implemented');
    }

    /**
     * Get user's player index in party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<number|null>} Player index or null if not in party
     */
    async getUserPlayerIndex(partyId, userId) {
        throw new Error('Method not implemented');
    }

    /**
     * Save round
     * @param {Round} round - Round entity
     * @returns {Promise<Round>} Saved round
     */
    async saveRound(round) {
        throw new Error('Method not implemented');
    }

    /**
     * Get round by ID
     * @param {string} roundId - Round ID
     * @returns {Promise<Round|null>} Round or null
     */
    async getRoundById(roundId) {
        throw new Error('Method not implemented');
    }

    /**
     * Get active round for party
     * @param {string} partyId - Party ID
     * @returns {Promise<Round|null>} Active round or null
     */
    async getActiveRound(partyId) {
        throw new Error('Method not implemented');
    }

    /**
     * Get all rounds for party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<Round>>} Array of rounds
     */
    async getRounds(partyId) {
        throw new Error('Method not implemented');
    }

    /**
     * Alias for getPlayers()
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<PartyPlayer>>} Array of party players
     */
    async getPartyPlayers(partyId) {
        return this.getPlayers(partyId);
    }

    /**
     * Save game state
     * @param {string} partyId - Party ID
     * @param {GameState} gameState - Game state
     * @returns {Promise<GameState>} Saved game state
     */
    async saveGameState(partyId, gameState) {
        throw new Error('Method not implemented');
    }

    /**
     * Get game state for party
     * @param {string} partyId - Party ID
     * @returns {Promise<GameState|null>} Game state or null
     */
    async getGameState(partyId) {
        throw new Error('Method not implemented');
    }

    /**
     * Count public parties by status
     * @param {string} status - Status filter
     * @returns {Promise<number>} Count
     */
    async countPublicParties(status = null) {
        throw new Error('Method not implemented');
    }
}

module.exports = IPartyRepository;
