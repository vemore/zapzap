/**
 * PartyRepository Implementation
 * SQLite implementation of IPartyRepository
 */

const IPartyRepository = require('../../../../domain/repositories/IPartyRepository');
const Party = require('../../../../domain/entities/Party');
const PartyPlayer = require('../../../../domain/entities/PartyPlayer');
const Round = require('../../../../domain/entities/Round');
const GameState = require('../../../../domain/value-objects/GameState');
const logger = require('../../../../../logger');

class PartyRepository extends IPartyRepository {
    /**
     * @param {DatabaseConnection} database - Database connection
     */
    constructor(database) {
        super();
        this.db = database;
    }

    /**
     * Find party by ID
     * @param {string} id - Party ID
     * @returns {Promise<Party|null>}
     */
    async findById(id) {
        try {
            const record = await this.db.get(
                'SELECT * FROM parties WHERE id = ?',
                [id]
            );

            if (!record) {
                return null;
            }

            logger.debug('Party found by ID', { partyId: id });
            return Party.fromDatabase(record);
        } catch (error) {
            logger.error('Error finding party by ID', { partyId: id, error: error.message });
            throw new Error(`Failed to find party by ID: ${error.message}`);
        }
    }

    /**
     * Find party by invite code
     * @param {string} inviteCode - Invite code
     * @returns {Promise<Party|null>}
     */
    async findByInviteCode(inviteCode) {
        try {
            const record = await this.db.get(
                'SELECT * FROM parties WHERE invite_code = ?',
                [inviteCode]
            );

            if (!record) {
                return null;
            }

            logger.debug('Party found by invite code', { inviteCode });
            return Party.fromDatabase(record);
        } catch (error) {
            logger.error('Error finding party by invite code', { inviteCode, error: error.message });
            throw new Error(`Failed to find party by invite code: ${error.message}`);
        }
    }

    /**
     * Find all public parties
     * @param {string} status - Optional status filter
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Party>>}
     */
    async findPublicParties(status = null, limit = 50, offset = 0) {
        try {
            let query = `SELECT * FROM parties WHERE visibility = 'public'`;
            const params = [];

            if (status) {
                query += ` AND status = ?`;
                params.push(status);
            }

            query += ` ORDER BY created_at DESC LIMIT ? OFFSET ?`;
            params.push(limit, offset);

            const records = await this.db.all(query, params);

            logger.debug('Public parties retrieved', { count: records.length, status, limit, offset });

            return records.map(record => Party.fromDatabase(record));
        } catch (error) {
            logger.error('Error finding public parties', { error: error.message });
            throw new Error(`Failed to find public parties: ${error.message}`);
        }
    }

    /**
     * Find parties owned by user
     * @param {string} userId - Owner user ID
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Party>>}
     */
    async findByOwner(userId, limit = 50, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT * FROM parties
                 WHERE owner_id = ?
                 ORDER BY created_at DESC
                 LIMIT ? OFFSET ?`,
                [userId, limit, offset]
            );

            logger.debug('Parties by owner retrieved', { userId, count: records.length });

            return records.map(record => Party.fromDatabase(record));
        } catch (error) {
            logger.error('Error finding parties by owner', { userId, error: error.message });
            throw new Error(`Failed to find parties by owner: ${error.message}`);
        }
    }

    /**
     * Save party (create or update)
     * @param {Party} party - Party entity
     * @returns {Promise<Party>}
     */
    async save(party) {
        try {
            const existing = await this.findById(party.id);
            const dbParty = party.toDatabase();

            if (existing) {
                // Update existing party
                await this.db.run(
                    `UPDATE parties
                     SET name = ?, owner_id = ?, invite_code = ?, visibility = ?,
                         status = ?, settings_json = ?, updated_at = ?
                     WHERE id = ?`,
                    [
                        dbParty.name,
                        dbParty.owner_id,
                        dbParty.invite_code,
                        dbParty.visibility,
                        dbParty.status,
                        dbParty.settings_json,
                        dbParty.updated_at,
                        dbParty.id
                    ]
                );

                logger.info('Party updated', { partyId: party.id, name: party.name });
            } else {
                // Insert new party
                await this.db.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        dbParty.id,
                        dbParty.name,
                        dbParty.owner_id,
                        dbParty.invite_code,
                        dbParty.visibility,
                        dbParty.status,
                        dbParty.settings_json,
                        dbParty.created_at,
                        dbParty.updated_at
                    ]
                );

                logger.info('Party created', { partyId: party.id, name: party.name });
            }

            return party;
        } catch (error) {
            logger.error('Error saving party', { partyId: party.id, error: error.message });
            throw new Error(`Failed to save party: ${error.message}`);
        }
    }

    /**
     * Delete party by ID
     * @param {string} id - Party ID
     * @returns {Promise<boolean>}
     */
    async delete(id) {
        try {
            const result = await this.db.run(
                'DELETE FROM parties WHERE id = ?',
                [id]
            );

            const deleted = result.changes > 0;

            if (deleted) {
                logger.info('Party deleted', { partyId: id });
            } else {
                logger.warn('Party not found for deletion', { partyId: id });
            }

            return deleted;
        } catch (error) {
            logger.error('Error deleting party', { partyId: id, error: error.message });
            throw new Error(`Failed to delete party: ${error.message}`);
        }
    }

    /**
     * Add player to party
     * @param {PartyPlayer} partyPlayer - PartyPlayer entity
     * @returns {Promise<PartyPlayer>}
     */
    async addPlayer(partyPlayer) {
        try {
            const dbPlayer = partyPlayer.toDatabase();

            const result = await this.db.run(
                `INSERT INTO party_players (party_id, user_id, player_index, joined_at)
                 VALUES (?, ?, ?, ?)`,
                [dbPlayer.party_id, dbPlayer.user_id, dbPlayer.player_index, dbPlayer.joined_at]
            );

            // Retrieve the newly created player with generated ID
            const record = await this.db.get(
                'SELECT * FROM party_players WHERE id = ?',
                [result.lastID]
            );

            logger.info('Player added to party', {
                partyId: partyPlayer.partyId,
                userId: partyPlayer.userId,
                playerIndex: partyPlayer.playerIndex,
                id: result.lastID
            });

            return PartyPlayer.fromDatabase(record);
        } catch (error) {
            logger.error('Error adding player to party', {
                partyId: partyPlayer.partyId,
                userId: partyPlayer.userId,
                error: error.message
            });
            throw new Error(`Failed to add player to party: ${error.message}`);
        }
    }

    /**
     * Remove player from party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<boolean>}
     */
    async removePlayer(partyId, userId) {
        try {
            const result = await this.db.run(
                'DELETE FROM party_players WHERE party_id = ? AND user_id = ?',
                [partyId, userId]
            );

            const removed = result.changes > 0;

            if (removed) {
                logger.info('Player removed from party', { partyId, userId });
            } else {
                logger.warn('Player not found in party', { partyId, userId });
            }

            return removed;
        } catch (error) {
            logger.error('Error removing player from party', { partyId, userId, error: error.message });
            throw new Error(`Failed to remove player from party: ${error.message}`);
        }
    }

    /**
     * Get players in party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<PartyPlayer>>}
     */
    async getPlayers(partyId) {
        try {
            const records = await this.db.all(
                `SELECT * FROM party_players
                 WHERE party_id = ?
                 ORDER BY player_index ASC`,
                [partyId]
            );

            logger.debug('Party players retrieved', { partyId, count: records.length });

            return records.map(record => PartyPlayer.fromDatabase(record));
        } catch (error) {
            logger.error('Error getting party players', { partyId, error: error.message });
            throw new Error(`Failed to get party players: ${error.message}`);
        }
    }

    /**
     * Get player count in party
     * @param {string} partyId - Party ID
     * @returns {Promise<number>}
     */
    async getPlayerCount(partyId) {
        try {
            const result = await this.db.get(
                'SELECT COUNT(*) as count FROM party_players WHERE party_id = ?',
                [partyId]
            );

            return result.count;
        } catch (error) {
            logger.error('Error getting player count', { partyId, error: error.message });
            throw new Error(`Failed to get player count: ${error.message}`);
        }
    }

    /**
     * Check if user is in party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<boolean>}
     */
    async isUserInParty(partyId, userId) {
        try {
            const record = await this.db.get(
                'SELECT 1 FROM party_players WHERE party_id = ? AND user_id = ?',
                [partyId, userId]
            );

            return !!record;
        } catch (error) {
            logger.error('Error checking if user in party', { partyId, userId, error: error.message });
            throw new Error(`Failed to check if user in party: ${error.message}`);
        }
    }

    /**
     * Get user's player index in party
     * @param {string} partyId - Party ID
     * @param {string} userId - User ID
     * @returns {Promise<number|null>}
     */
    async getUserPlayerIndex(partyId, userId) {
        try {
            const record = await this.db.get(
                'SELECT player_index FROM party_players WHERE party_id = ? AND user_id = ?',
                [partyId, userId]
            );

            return record ? record.player_index : null;
        } catch (error) {
            logger.error('Error getting user player index', { partyId, userId, error: error.message });
            throw new Error(`Failed to get user player index: ${error.message}`);
        }
    }

    /**
     * Save round
     * @param {Round} round - Round entity
     * @returns {Promise<Round>}
     */
    async saveRound(round) {
        try {
            const existing = await this.db.get(
                'SELECT 1 FROM rounds WHERE id = ?',
                [round.id]
            );

            const dbRound = round.toDatabase();

            if (existing) {
                // Update existing round
                await this.db.run(
                    `UPDATE rounds
                     SET status = ?, current_turn = ?, current_action = ?, finished_at = ?
                     WHERE id = ?`,
                    [
                        dbRound.status,
                        dbRound.current_turn,
                        dbRound.current_action,
                        dbRound.finished_at,
                        dbRound.id
                    ]
                );

                logger.info('Round updated', { roundId: round.id, partyId: round.partyId });
            } else {
                // Insert new round
                await this.db.run(
                    `INSERT INTO rounds (id, party_id, round_number, status, current_turn, current_action, created_at, finished_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        dbRound.id,
                        dbRound.party_id,
                        dbRound.round_number,
                        dbRound.status,
                        dbRound.current_turn,
                        dbRound.current_action,
                        dbRound.created_at,
                        dbRound.finished_at
                    ]
                );

                logger.info('Round created', { roundId: round.id, partyId: round.partyId, roundNumber: round.roundNumber });
            }

            return round;
        } catch (error) {
            logger.error('Error saving round', { roundId: round.id, error: error.message });
            throw new Error(`Failed to save round: ${error.message}`);
        }
    }

    /**
     * Get round by ID
     * @param {string} roundId - Round ID
     * @returns {Promise<Round|null>}
     */
    async getRoundById(roundId) {
        try {
            const record = await this.db.get(
                'SELECT * FROM rounds WHERE id = ?',
                [roundId]
            );

            if (!record) {
                return null;
            }

            logger.debug('Round found by ID', { roundId });
            return Round.fromDatabase(record);
        } catch (error) {
            logger.error('Error finding round by ID', { roundId, error: error.message });
            throw new Error(`Failed to find round by ID: ${error.message}`);
        }
    }

    /**
     * Get active round for party
     * @param {string} partyId - Party ID
     * @returns {Promise<Round|null>}
     */
    async getActiveRound(partyId) {
        try {
            const record = await this.db.get(
                `SELECT * FROM rounds
                 WHERE party_id = ? AND status = 'active'
                 ORDER BY round_number DESC
                 LIMIT 1`,
                [partyId]
            );

            if (!record) {
                return null;
            }

            logger.debug('Active round retrieved', { partyId, roundNumber: record.round_number });
            return Round.fromDatabase(record);
        } catch (error) {
            logger.error('Error getting active round', { partyId, error: error.message });
            throw new Error(`Failed to get active round: ${error.message}`);
        }
    }

    /**
     * Alias for getPlayers()
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<PartyPlayer>>}
     */
    async getPartyPlayers(partyId) {
        return this.getPlayers(partyId);
    }

    /**
     * Get all rounds for party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array<Round>>}
     */
    async getRounds(partyId) {
        try {
            const records = await this.db.all(
                `SELECT * FROM rounds
                 WHERE party_id = ?
                 ORDER BY round_number ASC`,
                [partyId]
            );

            logger.debug('Rounds retrieved', { partyId, count: records.length });

            return records.map(record => Round.fromDatabase(record));
        } catch (error) {
            logger.error('Error getting rounds', { partyId, error: error.message });
            throw new Error(`Failed to get rounds: ${error.message}`);
        }
    }

    /**
     * Save game state
     * @param {string} partyId - Party ID
     * @param {GameState} gameState - Game state
     * @returns {Promise<GameState>}
     */
    async saveGameState(partyId, gameState) {
        try {
            const existing = await this.db.get(
                'SELECT 1 FROM game_state WHERE party_id = ?',
                [partyId]
            );

            const stateJson = gameState.toJSON();
            const now = Math.floor(Date.now() / 1000);

            if (existing) {
                // Update existing game state
                await this.db.run(
                    'UPDATE game_state SET state_json = ?, updated_at = ? WHERE party_id = ?',
                    [stateJson, now, partyId]
                );

                logger.debug('Game state updated', { partyId });
            } else {
                // Insert new game state
                await this.db.run(
                    'INSERT INTO game_state (party_id, state_json, updated_at) VALUES (?, ?, ?)',
                    [partyId, stateJson, now]
                );

                logger.debug('Game state created', { partyId });
            }

            return gameState;
        } catch (error) {
            logger.error('Error saving game state', { partyId, error: error.message });
            throw new Error(`Failed to save game state: ${error.message}`);
        }
    }

    /**
     * Get game state for party
     * @param {string} partyId - Party ID
     * @returns {Promise<GameState|null>}
     */
    async getGameState(partyId) {
        try {
            const record = await this.db.get(
                'SELECT state_json FROM game_state WHERE party_id = ?',
                [partyId]
            );

            if (!record) {
                return null;
            }

            logger.debug('Game state retrieved', { partyId });
            return GameState.fromJSON(record.state_json);
        } catch (error) {
            logger.error('Error getting game state', { partyId, error: error.message });
            throw new Error(`Failed to get game state: ${error.message}`);
        }
    }

    /**
     * Count public parties by status
     * @param {string} status - Status filter
     * @returns {Promise<number>}
     */
    async countPublicParties(status = null) {
        try {
            let query = `SELECT COUNT(*) as count FROM parties WHERE visibility = 'public'`;
            const params = [];

            if (status) {
                query += ` AND status = ?`;
                params.push(status);
            }

            const result = await this.db.get(query, params);
            return result.count;
        } catch (error) {
            logger.error('Error counting public parties', { error: error.message });
            throw new Error(`Failed to count public parties: ${error.message}`);
        }
    }
}

module.exports = PartyRepository;
