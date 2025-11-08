/**
 * PartyHelper
 * Handles party operations for E2E tests
 */

class PartyHelper {
    constructor(baseURL, authHelper) {
        this.baseURL = baseURL;
        this.authHelper = authHelper;
        this.parties = new Map(); // partyId -> party data
    }

    /**
     * Create a new party
     * @param {string} ownerUsername - Username of party owner
     * @param {Object} options - Party options
     * @param {string} options.name - Party name
     * @param {string} options.visibility - public or private (default: public)
     * @param {number} options.playerCount - Number of players 3-8 (default: 5)
     * @param {number} options.handSize - Hand size 5-7 (default: 7)
     * @param {Array<string>} options.botIds - Bot user IDs to auto-join
     * @returns {Promise<Object>} Created party data
     */
    async createParty(ownerUsername, options = {}) {
        const {
            name = `Test Party ${Date.now()}`,
            visibility = 'public',
            playerCount = 5,
            handSize = 7,
            botIds = []
        } = options;

        const response = await this.authHelper.post(ownerUsername, '/api/party', {
            name,
            visibility,
            settings: {
                playerCount,
                handSize
            },
            botIds
        });

        if (!response.success) {
            const errorMsg = response.details || response.error || response.message || JSON.stringify(response);
            throw new Error(`Failed to create party: ${errorMsg}`);
        }

        // Store party data
        this.parties.set(response.party.id, {
            ...response.party,
            ownerUsername,
            botsJoined: response.botsJoined || 0
        });

        return response.party;
    }

    /**
     * Get party details
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @returns {Promise<Object>} Party details
     */
    async getParty(username, partyId) {
        const response = await this.authHelper.get(username, `/api/party/${partyId}`);

        if (!response.success) {
            throw new Error(`Failed to get party: ${response.error}`);
        }

        // Update stored party data
        this.parties.set(partyId, {
            ...this.parties.get(partyId),
            ...response.party,
            players: response.players
        });

        return response;
    }

    /**
     * List public parties
     * @param {Object} options - Query options
     * @param {string} options.status - Filter by status (waiting, playing, finished)
     * @param {number} options.limit - Limit results (default: 50)
     * @param {number} options.offset - Offset for pagination (default: 0)
     * @returns {Promise<Array>} List of parties
     */
    async listParties(options = {}) {
        const { status, limit = 50, offset = 0 } = options;

        const queryParams = new URLSearchParams();
        if (status) queryParams.append('status', status);
        queryParams.append('limit', limit.toString());
        queryParams.append('offset', offset.toString());

        const response = await fetch(`${this.baseURL}/api/party?${queryParams}`);

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Failed to list parties: ${error.error}`);
        }

        const data = await response.json();
        return data.parties;
    }

    /**
     * Join a party
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @param {string} inviteCode - Invite code (optional, for private parties)
     * @returns {Promise<Object>} Join result
     */
    async joinParty(username, partyId, inviteCode = null) {
        const body = inviteCode ? { inviteCode } : {};

        const response = await this.authHelper.post(
            username,
            `/api/party/${partyId}/join`,
            body
        );

        if (!response.success) {
            throw new Error(`Failed to join party: ${response.error}`);
        }

        return response;
    }

    /**
     * Leave a party
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @returns {Promise<Object>} Leave result
     */
    async leaveParty(username, partyId) {
        const response = await this.authHelper.post(
            username,
            `/api/party/${partyId}/leave`,
            {}
        );

        if (!response.success) {
            throw new Error(`Failed to leave party: ${response.error}`);
        }

        return response;
    }

    /**
     * Start a party (owner only)
     * @param {string} ownerUsername - Party owner username
     * @param {string} partyId - Party ID
     * @returns {Promise<Object>} Start result
     */
    async startParty(ownerUsername, partyId) {
        const response = await this.authHelper.post(
            ownerUsername,
            `/api/party/${partyId}/start`,
            {}
        );

        if (!response.success) {
            throw new Error(`Failed to start party: ${response.error}`);
        }

        return response;
    }

    /**
     * Get game state for party
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @returns {Promise<Object>} Game state
     */
    async getGameState(username, partyId) {
        const response = await this.authHelper.get(
            username,
            `/api/game/${partyId}/state`
        );

        if (!response.success) {
            throw new Error(`Failed to get game state: ${response.error}`);
        }

        return response;
    }

    /**
     * Play cards in a game
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @param {Array<number>} cards - Card IDs to play
     * @returns {Promise<Object>} Play result
     */
    async playCards(username, partyId, cards) {
        const response = await this.authHelper.post(
            username,
            `/api/game/${partyId}/play`,
            { cards }
        );

        if (!response.success) {
            throw new Error(`Failed to play cards: ${response.error}`);
        }

        return response;
    }

    /**
     * Draw a card from deck or discard pile
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @param {string} source - 'deck' or 'discard'
     * @returns {Promise<Object>} Draw result
     */
    async drawCard(username, partyId, source = 'deck') {
        const response = await this.authHelper.post(
            username,
            `/api/game/${partyId}/draw`,
            { source }
        );

        if (!response.success) {
            throw new Error(`Failed to draw card: ${response.error}`);
        }

        return response;
    }

    /**
     * Call ZapZap to end the round
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @returns {Promise<Object>} ZapZap result
     */
    async callZapZap(username, partyId) {
        const response = await this.authHelper.post(
            username,
            `/api/game/${partyId}/zapzap`,
            {}
        );

        if (!response.success) {
            throw new Error(`Failed to call ZapZap: ${response.error}`);
        }

        return response;
    }

    /**
     * Wait for party to have specific player count
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @param {number} expectedCount - Expected player count
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Object>} Party details when condition met
     */
    async waitForPlayerCount(username, partyId, expectedCount, timeout = 5000) {
        const startTime = Date.now();

        while (Date.now() - startTime < timeout) {
            const partyData = await this.getParty(username, partyId);

            if (partyData.players.length === expectedCount) {
                return partyData;
            }

            // Wait 100ms before checking again
            await new Promise(resolve => setTimeout(resolve, 100));
        }

        throw new Error(`Timeout waiting for ${expectedCount} players in party ${partyId}`);
    }

    /**
     * Wait for party status
     * @param {string} username - Username
     * @param {string} partyId - Party ID
     * @param {string} expectedStatus - Expected status (waiting, playing, finished)
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Object>} Party details when condition met
     */
    async waitForStatus(username, partyId, expectedStatus, timeout = 5000) {
        const startTime = Date.now();

        while (Date.now() - startTime < timeout) {
            const partyData = await this.getParty(username, partyId);

            if (partyData.party.status === expectedStatus) {
                return partyData;
            }

            // Wait 100ms before checking again
            await new Promise(resolve => setTimeout(resolve, 100));
        }

        throw new Error(`Timeout waiting for status '${expectedStatus}' in party ${partyId}`);
    }

    /**
     * Create party with multiple human players
     * @param {string} ownerUsername - Owner username
     * @param {Array<string>} joinUsernames - Usernames to join
     * @param {Object} options - Party options
     * @returns {Promise<{party: Object, players: Array}>}
     */
    async createMultiPlayerParty(ownerUsername, joinUsernames, options = {}) {
        // Create party
        const party = await this.createParty(ownerUsername, {
            ...options,
            playerCount: Math.max(options.playerCount || 5, joinUsernames.length + 1)
        });

        // Join other players
        const joinResults = [];
        for (const username of joinUsernames) {
            const result = await this.joinParty(username, party.id);
            joinResults.push(result);
        }

        // Get updated party state
        const partyData = await this.getParty(ownerUsername, party.id);

        return {
            party: partyData.party,
            players: partyData.players,
            joinResults
        };
    }

    /**
     * Create party with bots
     * @param {string} ownerUsername - Owner username
     * @param {Array<string>} botIds - Bot user IDs
     * @param {Object} options - Party options
     * @returns {Promise<Object>} Created party with bots
     */
    async createPartyWithBots(ownerUsername, botIds, options = {}) {
        const party = await this.createParty(ownerUsername, {
            ...options,
            botIds,
            playerCount: Math.max(options.playerCount || 5, botIds.length + 1)
        });

        // Wait for all bots to join
        await this.waitForPlayerCount(ownerUsername, party.id, botIds.length + 1, 3000);

        return party;
    }

    /**
     * Get stored party data
     * @param {string} partyId - Party ID
     * @returns {Object|null} Stored party data
     */
    getStoredParty(partyId) {
        return this.parties.get(partyId);
    }

    /**
     * Clear stored party data
     */
    clear() {
        this.parties.clear();
    }

    /**
     * Get all stored party IDs
     * @returns {Array<string>} Array of party IDs
     */
    getPartyIds() {
        return Array.from(this.parties.keys());
    }
}

/**
 * Create PartyHelper instance
 * @param {string} baseURL - Base URL for API
 * @param {AuthHelper} authHelper - AuthHelper instance
 * @returns {PartyHelper} PartyHelper instance
 */
function createPartyHelper(baseURL, authHelper) {
    return new PartyHelper(baseURL, authHelper);
}

module.exports = {
    PartyHelper,
    createPartyHelper
};
