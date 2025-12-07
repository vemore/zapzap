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
            } else {
                // By default, exclude finished parties from the list
                query += ` AND status != 'finished'`;
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
                         status = ?, settings_json = ?, current_round_id = ?, updated_at = ?
                     WHERE id = ?`,
                    [
                        dbParty.name,
                        dbParty.owner_id,
                        dbParty.invite_code,
                        dbParty.visibility,
                        dbParty.status,
                        dbParty.settings_json,
                        dbParty.current_round_id,
                        dbParty.updated_at,
                        dbParty.id
                    ]
                );

                logger.info('Party updated', { partyId: party.id, name: party.name });
            } else {
                // Insert new party
                await this.db.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json, current_round_id, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        dbParty.id,
                        dbParty.name,
                        dbParty.owner_id,
                        dbParty.invite_code,
                        dbParty.visibility,
                        dbParty.status,
                        dbParty.settings_json,
                        dbParty.current_round_id,
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

    // ============================================
    // HISTORY & STATS METHODS
    // ============================================

    /**
     * Save round scores for all players at end of round
     * @param {string} partyId - Party ID
     * @param {number} roundNumber - Round number
     * @param {Array} playerScores - Array of player score data
     * @returns {Promise<void>}
     */
    async saveRoundScores(partyId, roundNumber, playerScores) {
        try {
            const now = Math.floor(Date.now() / 1000);

            for (const ps of playerScores) {
                await this.db.run(
                    `INSERT OR REPLACE INTO round_scores
                     (party_id, round_number, user_id, player_index, score_this_round, total_score_after,
                      hand_points, is_zapzap_caller, zapzap_success, was_counteracted, hand_cards,
                      is_lowest_hand, is_eliminated, created_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        partyId,
                        roundNumber,
                        ps.userId,
                        ps.playerIndex,
                        ps.scoreThisRound,
                        ps.totalScoreAfter,
                        ps.handPoints,
                        ps.isZapZapCaller ? 1 : 0,
                        ps.zapZapSuccess ? 1 : 0,
                        ps.wasCounterActed ? 1 : 0,
                        ps.handCards ? JSON.stringify(ps.handCards) : null,
                        ps.isLowestHand ? 1 : 0,
                        ps.isEliminated ? 1 : 0,
                        now
                    ]
                );
            }

            logger.info('Round scores saved', { partyId, roundNumber, playerCount: playerScores.length });
        } catch (error) {
            logger.error('Error saving round scores', { partyId, roundNumber, error: error.message });
            throw new Error(`Failed to save round scores: ${error.message}`);
        }
    }

    /**
     * Save game result when game finishes
     * @param {Object} gameResult - Game result data
     * @returns {Promise<void>}
     */
    async saveGameResult(gameResult) {
        try {
            const now = Math.floor(Date.now() / 1000);

            await this.db.run(
                `INSERT OR REPLACE INTO game_results
                 (party_id, winner_user_id, winner_final_score, total_rounds, was_golden_score,
                  player_count, finished_at, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [
                    gameResult.partyId,
                    gameResult.winnerUserId,
                    gameResult.winnerFinalScore,
                    gameResult.totalRounds,
                    gameResult.wasGoldenScore ? 1 : 0,
                    gameResult.playerCount,
                    now,
                    now
                ]
            );

            logger.info('Game result saved', { partyId: gameResult.partyId, winnerId: gameResult.winnerUserId });
        } catch (error) {
            logger.error('Error saving game result', { partyId: gameResult.partyId, error: error.message });
            throw new Error(`Failed to save game result: ${error.message}`);
        }
    }

    /**
     * Save player game results for all players
     * @param {string} partyId - Party ID
     * @param {Array} playerResults - Array of player result data
     * @returns {Promise<void>}
     */
    async savePlayerGameResults(partyId, playerResults) {
        try {
            const now = Math.floor(Date.now() / 1000);

            for (const pr of playerResults) {
                await this.db.run(
                    `INSERT OR REPLACE INTO player_game_results
                     (party_id, user_id, final_score, finish_position, rounds_played,
                      total_zapzap_calls, successful_zapzaps, failed_zapzaps, lowest_hand_count,
                      is_winner, created_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [
                        partyId,
                        pr.userId,
                        pr.finalScore,
                        pr.finishPosition,
                        pr.roundsPlayed,
                        pr.totalZapZapCalls || 0,
                        pr.successfulZapZaps || 0,
                        pr.failedZapZaps || 0,
                        pr.lowestHandCount || 0,
                        pr.isWinner ? 1 : 0,
                        now
                    ]
                );
            }

            logger.info('Player game results saved', { partyId, playerCount: playerResults.length });
        } catch (error) {
            logger.error('Error saving player game results', { partyId, error: error.message });
            throw new Error(`Failed to save player game results: ${error.message}`);
        }
    }

    /**
     * Get finished games for a user
     * @param {string} userId - User ID
     * @param {number} limit - Limit
     * @param {number} offset - Offset
     * @returns {Promise<Array>}
     */
    async getFinishedGamesForUser(userId, limit = 20, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT gr.*, p.name as party_name, p.visibility,
                        u.username as winner_username,
                        pgr.final_score as user_final_score,
                        pgr.finish_position as user_position,
                        pgr.is_winner as user_is_winner
                 FROM game_results gr
                 JOIN parties p ON gr.party_id = p.id
                 JOIN users u ON gr.winner_user_id = u.id
                 JOIN player_game_results pgr ON gr.party_id = pgr.party_id AND pgr.user_id = ?
                 ORDER BY gr.finished_at DESC
                 LIMIT ? OFFSET ?`,
                [userId, limit, offset]
            );

            return records;
        } catch (error) {
            logger.error('Error getting finished games for user', { userId, error: error.message });
            throw new Error(`Failed to get finished games: ${error.message}`);
        }
    }

    /**
     * Get public finished games
     * @param {number} limit - Limit
     * @param {number} offset - Offset
     * @returns {Promise<Array>}
     */
    async getPublicFinishedGames(limit = 20, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT gr.*, p.name as party_name,
                        u.username as winner_username
                 FROM game_results gr
                 JOIN parties p ON gr.party_id = p.id
                 JOIN users u ON gr.winner_user_id = u.id
                 WHERE p.visibility = 'public'
                 ORDER BY gr.finished_at DESC
                 LIMIT ? OFFSET ?`,
                [limit, offset]
            );

            return records;
        } catch (error) {
            logger.error('Error getting public finished games', { error: error.message });
            throw new Error(`Failed to get public finished games: ${error.message}`);
        }
    }

    /**
     * Get game result by party ID
     * @param {string} partyId - Party ID
     * @returns {Promise<Object|null>}
     */
    async getGameResultByPartyId(partyId) {
        try {
            const record = await this.db.get(
                `SELECT gr.*, p.name as party_name, p.visibility,
                        u.username as winner_username
                 FROM game_results gr
                 JOIN parties p ON gr.party_id = p.id
                 JOIN users u ON gr.winner_user_id = u.id
                 WHERE gr.party_id = ?`,
                [partyId]
            );

            return record || null;
        } catch (error) {
            logger.error('Error getting game result', { partyId, error: error.message });
            throw new Error(`Failed to get game result: ${error.message}`);
        }
    }

    /**
     * Get round scores for a party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array>}
     */
    async getRoundScoresForParty(partyId) {
        try {
            const records = await this.db.all(
                `SELECT rs.*, u.username
                 FROM round_scores rs
                 JOIN users u ON rs.user_id = u.id
                 WHERE rs.party_id = ?
                 ORDER BY rs.round_number ASC, rs.player_index ASC`,
                [partyId]
            );

            return records;
        } catch (error) {
            logger.error('Error getting round scores', { partyId, error: error.message });
            throw new Error(`Failed to get round scores: ${error.message}`);
        }
    }

    /**
     * Get player results for a party
     * @param {string} partyId - Party ID
     * @returns {Promise<Array>}
     */
    async getPlayerResultsForParty(partyId) {
        try {
            const records = await this.db.all(
                `SELECT pgr.*, u.username
                 FROM player_game_results pgr
                 JOIN users u ON pgr.user_id = u.id
                 WHERE pgr.party_id = ?
                 ORDER BY pgr.finish_position ASC`,
                [partyId]
            );

            return records;
        } catch (error) {
            logger.error('Error getting player results', { partyId, error: error.message });
            throw new Error(`Failed to get player results: ${error.message}`);
        }
    }

    /**
     * Get user statistics
     * @param {string} userId - User ID
     * @returns {Promise<Object>}
     */
    async getUserStats(userId) {
        try {
            // Get basic game stats
            const gameStats = await this.db.get(
                `SELECT
                    COUNT(*) as games_played,
                    SUM(CASE WHEN is_winner = 1 THEN 1 ELSE 0 END) as wins,
                    AVG(final_score) as avg_score,
                    MIN(final_score) as best_score,
                    SUM(rounds_played) as total_rounds,
                    SUM(total_zapzap_calls) as total_zapzaps,
                    SUM(successful_zapzaps) as successful_zapzaps,
                    SUM(failed_zapzaps) as failed_zapzaps,
                    SUM(lowest_hand_count) as lowest_hand_count
                 FROM player_game_results
                 WHERE user_id = ?`,
                [userId]
            );

            const gamesPlayed = gameStats.games_played || 0;
            const wins = gameStats.wins || 0;

            return {
                gamesPlayed,
                wins,
                losses: gamesPlayed - wins,
                winRate: gamesPlayed > 0 ? wins / gamesPlayed : 0,
                averageScore: gameStats.avg_score || 0,
                bestScore: gameStats.best_score || 0,
                totalRoundsPlayed: gameStats.total_rounds || 0,
                zapzaps: {
                    total: gameStats.total_zapzaps || 0,
                    successful: gameStats.successful_zapzaps || 0,
                    failed: gameStats.failed_zapzaps || 0,
                    successRate: (gameStats.total_zapzaps || 0) > 0
                        ? (gameStats.successful_zapzaps || 0) / (gameStats.total_zapzaps || 0)
                        : 0
                },
                lowestHandCount: gameStats.lowest_hand_count || 0
            };
        } catch (error) {
            logger.error('Error getting user stats', { userId, error: error.message });
            throw new Error(`Failed to get user stats: ${error.message}`);
        }
    }

    /**
     * Get global leaderboard
     * @param {number} minGames - Minimum games to qualify
     * @param {number} limit - Limit
     * @param {number} offset - Offset
     * @returns {Promise<Array>}
     */
    async getLeaderboard(minGames = 5, limit = 50, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT
                    u.id as user_id,
                    u.username,
                    COUNT(*) as games_played,
                    SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins,
                    CAST(SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) AS REAL) / COUNT(*) as win_rate,
                    AVG(pgr.final_score) as avg_score
                 FROM player_game_results pgr
                 JOIN users u ON pgr.user_id = u.id
                 WHERE u.user_type = 'human'
                 GROUP BY pgr.user_id
                 HAVING COUNT(*) >= ?
                 ORDER BY win_rate DESC, wins DESC
                 LIMIT ? OFFSET ?`,
                [minGames, limit, offset]
            );

            return records.map((r, index) => ({
                rank: offset + index + 1,
                userId: r.user_id,
                username: r.username,
                gamesPlayed: r.games_played,
                wins: r.wins,
                winRate: r.win_rate,
                avgScore: r.avg_score
            }));
        } catch (error) {
            logger.error('Error getting leaderboard', { error: error.message });
            throw new Error(`Failed to get leaderboard: ${error.message}`);
        }
    }

    /**
     * Get bot statistics aggregated by difficulty
     * @returns {Promise<Object>} Bot statistics per difficulty level and individual bots
     */
    async getBotStats() {
        try {
            // Aggregated stats by difficulty
            const byDifficulty = await this.db.all(
                `SELECT
                    u.bot_difficulty as difficulty,
                    COUNT(DISTINCT pgr.user_id) as bot_count,
                    COUNT(pgr.id) as games_played,
                    SUM(pgr.rounds_played) as total_rounds,
                    SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins,
                    SUM(pgr.total_zapzap_calls) as zapzap_total,
                    SUM(pgr.successful_zapzaps) as zapzap_success,
                    SUM(pgr.failed_zapzaps) as zapzap_failed,
                    SUM(pgr.lowest_hand_count) as lowest_hand_count
                 FROM player_game_results pgr
                 JOIN users u ON pgr.user_id = u.id
                 WHERE u.user_type = 'bot'
                 GROUP BY u.bot_difficulty
                 ORDER BY CASE u.bot_difficulty
                    WHEN 'easy' THEN 1
                    WHEN 'medium' THEN 2
                    WHEN 'hard' THEN 3
                 END`
            );

            // Individual bot stats
            const byBot = await this.db.all(
                `SELECT
                    u.id as bot_id,
                    u.username,
                    u.bot_difficulty as difficulty,
                    COUNT(pgr.id) as games_played,
                    SUM(pgr.rounds_played) as total_rounds,
                    SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins,
                    SUM(pgr.total_zapzap_calls) as zapzap_total,
                    SUM(pgr.successful_zapzaps) as zapzap_success,
                    SUM(pgr.failed_zapzaps) as zapzap_failed,
                    SUM(pgr.lowest_hand_count) as lowest_hand_count
                 FROM player_game_results pgr
                 JOIN users u ON pgr.user_id = u.id
                 WHERE u.user_type = 'bot'
                 GROUP BY pgr.user_id
                 ORDER BY u.bot_difficulty, wins DESC`
            );

            logger.debug('Bot stats retrieved', {
                difficultyCount: byDifficulty.length,
                botCount: byBot.length
            });

            return { byDifficulty, byBot };
        } catch (error) {
            logger.error('Error getting bot stats', { error: error.message });
            throw new Error(`Failed to get bot stats: ${error.message}`);
        }
    }

    /**
     * Count finished games for user
     * @param {string} userId - User ID
     * @returns {Promise<number>}
     */
    async countFinishedGamesForUser(userId) {
        try {
            const result = await this.db.get(
                `SELECT COUNT(*) as count
                 FROM player_game_results
                 WHERE user_id = ?`,
                [userId]
            );

            return result.count;
        } catch (error) {
            logger.error('Error counting finished games', { userId, error: error.message });
            throw new Error(`Failed to count finished games: ${error.message}`);
        }
    }

    /**
     * Count public finished games
     * @returns {Promise<number>}
     */
    async countPublicFinishedGames() {
        try {
            const result = await this.db.get(
                `SELECT COUNT(*) as count
                 FROM game_results gr
                 JOIN parties p ON gr.party_id = p.id
                 WHERE p.visibility = 'public'`
            );

            return result.count;
        } catch (error) {
            logger.error('Error counting public finished games', { error: error.message });
            throw new Error(`Failed to count public finished games: ${error.message}`);
        }
    }

    /**
     * Count leaderboard entries
     * @param {number} minGames - Minimum games to qualify
     * @returns {Promise<number>}
     */
    async countLeaderboardEntries(minGames = 5) {
        try {
            const result = await this.db.get(
                `SELECT COUNT(*) as count FROM (
                    SELECT pgr.user_id
                    FROM player_game_results pgr
                    JOIN users u ON pgr.user_id = u.id
                    WHERE u.user_type = 'human'
                    GROUP BY pgr.user_id
                    HAVING COUNT(*) >= ?
                 )`,
                [minGames]
            );

            return result.count;
        } catch (error) {
            logger.error('Error counting leaderboard entries', { error: error.message });
            throw new Error(`Failed to count leaderboard entries: ${error.message}`);
        }
    }

    // ============================================
    // ADMIN METHODS
    // ============================================

    /**
     * Find all parties (for admin - includes private parties)
     * @param {string} status - Optional status filter
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Party>>}
     */
    async findAllParties(status = null, limit = 50, offset = 0) {
        try {
            let query = `SELECT * FROM parties`;
            const params = [];

            if (status) {
                query += ` WHERE status = ?`;
                params.push(status);
            }

            query += ` ORDER BY created_at DESC LIMIT ? OFFSET ?`;
            params.push(limit, offset);

            const records = await this.db.all(query, params);

            logger.debug('All parties retrieved (admin)', { count: records.length, status, limit, offset });

            return records.map(record => Party.fromDatabase(record));
        } catch (error) {
            logger.error('Error finding all parties', { error: error.message });
            throw new Error(`Failed to find all parties: ${error.message}`);
        }
    }

    /**
     * Count all parties (for admin)
     * @param {string} status - Optional status filter
     * @returns {Promise<number>}
     */
    async countAllParties(status = null) {
        try {
            let query = `SELECT COUNT(*) as count FROM parties`;
            const params = [];

            if (status) {
                query += ` WHERE status = ?`;
                params.push(status);
            }

            const result = await this.db.get(query, params);
            return result.count;
        } catch (error) {
            logger.error('Error counting all parties', { error: error.message });
            throw new Error(`Failed to count all parties: ${error.message}`);
        }
    }

    /**
     * Count total rounds played
     * @returns {Promise<number>}
     */
    async countTotalRounds() {
        try {
            const result = await this.db.get(
                `SELECT COUNT(*) as count FROM rounds`
            );
            return result.count;
        } catch (error) {
            logger.error('Error counting total rounds', { error: error.message });
            throw new Error(`Failed to count total rounds: ${error.message}`);
        }
    }

    /**
     * Get games finished per time period
     * @param {string} period - 'day', 'week', or 'month'
     * @returns {Promise<Array>}
     */
    async getGamesPerPeriod(period = 'day') {
        try {
            let dateFormat;
            let limit;

            switch (period) {
                case 'week':
                    dateFormat = '%Y-%W';
                    limit = 12;
                    break;
                case 'month':
                    dateFormat = '%Y-%m';
                    limit = 12;
                    break;
                case 'day':
                default:
                    dateFormat = '%Y-%m-%d';
                    limit = 30;
                    break;
            }

            const records = await this.db.all(
                `SELECT
                    strftime('${dateFormat}', datetime(finished_at, 'unixepoch')) as period,
                    COUNT(*) as count
                 FROM game_results
                 GROUP BY period
                 ORDER BY period DESC
                 LIMIT ?`,
                [limit]
            );

            return records.reverse();
        } catch (error) {
            logger.error('Error getting games per period', { period, error: error.message });
            throw new Error(`Failed to get games per period: ${error.message}`);
        }
    }

    /**
     * Get most active users by games played
     * @param {number} limit - Number of users to return
     * @returns {Promise<Array>}
     */
    async getMostActiveUsers(limit = 10) {
        try {
            const records = await this.db.all(
                `SELECT
                    u.id as user_id,
                    u.username,
                    COUNT(pgr.id) as games_played,
                    SUM(CASE WHEN pgr.is_winner = 1 THEN 1 ELSE 0 END) as wins
                 FROM users u
                 JOIN player_game_results pgr ON u.id = pgr.user_id
                 WHERE u.user_type = 'human'
                 GROUP BY u.id
                 ORDER BY games_played DESC
                 LIMIT ?`,
                [limit]
            );

            return records.map(r => ({
                userId: r.user_id,
                username: r.username,
                gamesPlayed: r.games_played,
                wins: r.wins
            }));
        } catch (error) {
            logger.error('Error getting most active users', { error: error.message });
            throw new Error(`Failed to get most active users: ${error.message}`);
        }
    }
}

module.exports = PartyRepository;
