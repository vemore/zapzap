/**
 * UserRepository Implementation
 * SQLite implementation of IUserRepository
 */

const IUserRepository = require('../../../../domain/repositories/IUserRepository');
const User = require('../../../../domain/entities/User');
const logger = require('../../../../../logger');

class UserRepository extends IUserRepository {
    /**
     * @param {DatabaseConnection} database - Database connection
     */
    constructor(database) {
        super();
        this.db = database;
    }

    /**
     * Find user by ID
     * @param {string} id - User ID
     * @returns {Promise<User|null>}
     */
    async findById(id) {
        try {
            const record = await this.db.get(
                'SELECT * FROM users WHERE id = ?',
                [id]
            );

            if (!record) {
                return null;
            }

            logger.debug('User found by ID', { userId: id });
            return User.fromDatabase(record);
        } catch (error) {
            logger.error('Error finding user by ID', { userId: id, error: error.message });
            throw new Error(`Failed to find user by ID: ${error.message}`);
        }
    }

    /**
     * Find user by username
     * @param {string} username - Username
     * @returns {Promise<User|null>}
     */
    async findByUsername(username) {
        try {
            const record = await this.db.get(
                'SELECT * FROM users WHERE username = ?',
                [username]
            );

            if (!record) {
                return null;
            }

            logger.debug('User found by username', { username });
            return User.fromDatabase(record);
        } catch (error) {
            logger.error('Error finding user by username', { username, error: error.message });
            throw new Error(`Failed to find user by username: ${error.message}`);
        }
    }

    /**
     * Check if username exists
     * @param {string} username - Username to check
     * @returns {Promise<boolean>}
     */
    async existsByUsername(username) {
        try {
            const record = await this.db.get(
                'SELECT 1 FROM users WHERE username = ?',
                [username]
            );

            return !!record;
        } catch (error) {
            logger.error('Error checking username existence', { username, error: error.message });
            throw new Error(`Failed to check username existence: ${error.message}`);
        }
    }

    /**
     * Save user (create or update)
     * @param {User} user - User entity
     * @returns {Promise<User>}
     */
    async save(user) {
        try {
            // Check if user exists
            const existing = await this.findById(user.id);

            if (existing) {
                // Update existing user
                await this.db.run(
                    `UPDATE users
                     SET username = ?, password_hash = ?, user_type = ?, bot_difficulty = ?,
                         is_admin = ?, last_login_at = ?, total_play_time_seconds = ?, updated_at = ?
                     WHERE id = ?`,
                    [user.username, user.passwordHash, user.userType, user.botDifficulty,
                     user.isAdmin ? 1 : 0, user.lastLoginAt, user.totalPlayTimeSeconds, user.updatedAt, user.id]
                );

                logger.info('User updated', { userId: user.id, username: user.username, userType: user.userType });
            } else {
                // Insert new user
                await this.db.run(
                    `INSERT INTO users (id, username, password_hash, user_type, bot_difficulty,
                                        is_admin, last_login_at, total_play_time_seconds, created_at, updated_at)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
                    [user.id, user.username, user.passwordHash, user.userType, user.botDifficulty,
                     user.isAdmin ? 1 : 0, user.lastLoginAt, user.totalPlayTimeSeconds, user.createdAt, user.updatedAt]
                );

                logger.info('User created', { userId: user.id, username: user.username, userType: user.userType });
            }

            return user;
        } catch (error) {
            logger.error('Error saving user', { userId: user.id, error: error.message });
            throw new Error(`Failed to save user: ${error.message}`);
        }
    }

    /**
     * Delete user by ID
     * @param {string} id - User ID
     * @returns {Promise<boolean>}
     */
    async delete(id) {
        try {
            const result = await this.db.run(
                'DELETE FROM users WHERE id = ?',
                [id]
            );

            const deleted = result.changes > 0;

            if (deleted) {
                logger.info('User deleted', { userId: id });
            } else {
                logger.warn('User not found for deletion', { userId: id });
            }

            return deleted;
        } catch (error) {
            logger.error('Error deleting user', { userId: id, error: error.message });
            throw new Error(`Failed to delete user: ${error.message}`);
        }
    }

    /**
     * Get all users (for admin purposes)
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<User>>}
     */
    async findAll(limit = 100, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT * FROM users
                 ORDER BY created_at DESC
                 LIMIT ? OFFSET ?`,
                [limit, offset]
            );

            logger.debug('Users retrieved', { count: records.length, limit, offset });

            return records.map(record => User.fromDatabase(record));
        } catch (error) {
            logger.error('Error finding all users', { error: error.message });
            throw new Error(`Failed to find all users: ${error.message}`);
        }
    }

    /**
     * Count total users
     * @returns {Promise<number>}
     */
    async count() {
        try {
            const result = await this.db.get('SELECT COUNT(*) as count FROM users');
            return result.count;
        } catch (error) {
            logger.error('Error counting users', { error: error.message });
            throw new Error(`Failed to count users: ${error.message}`);
        }
    }

    /**
     * Find all bots
     * @param {string|null} difficulty - Filter by difficulty (optional)
     * @returns {Promise<Array<User>>}
     */
    async findBots(difficulty = null) {
        try {
            let query = 'SELECT * FROM users WHERE user_type = ?';
            let params = ['bot'];

            if (difficulty) {
                query += ' AND bot_difficulty = ?';
                params.push(difficulty);
            }

            query += ' ORDER BY username';

            const records = await this.db.all(query, params);

            logger.debug('Bots retrieved', { count: records.length, difficulty });

            return records.map(record => User.fromDatabase(record));
        } catch (error) {
            logger.error('Error finding bots', { difficulty, error: error.message });
            throw new Error(`Failed to find bots: ${error.message}`);
        }
    }

    /**
     * Update user's last login timestamp
     * @param {string} userId - User ID
     * @returns {Promise<void>}
     */
    async updateLastLogin(userId) {
        try {
            const now = Math.floor(Date.now() / 1000);
            await this.db.run(
                'UPDATE users SET last_login_at = ?, updated_at = ? WHERE id = ?',
                [now, now, userId]
            );
            logger.debug('Last login updated', { userId });
        } catch (error) {
            logger.error('Error updating last login', { userId, error: error.message });
            throw new Error(`Failed to update last login: ${error.message}`);
        }
    }

    /**
     * Set user admin status
     * @param {string} userId - User ID
     * @param {boolean} isAdmin - Admin status
     * @returns {Promise<void>}
     */
    async setAdminStatus(userId, isAdmin) {
        try {
            const now = Math.floor(Date.now() / 1000);
            await this.db.run(
                'UPDATE users SET is_admin = ?, updated_at = ? WHERE id = ?',
                [isAdmin ? 1 : 0, now, userId]
            );
            logger.info('Admin status updated', { userId, isAdmin });
        } catch (error) {
            logger.error('Error setting admin status', { userId, error: error.message });
            throw new Error(`Failed to set admin status: ${error.message}`);
        }
    }

    /**
     * Find all human users with game statistics
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<Object>>}
     */
    async findAllHumansWithStats(limit = 50, offset = 0) {
        try {
            const records = await this.db.all(
                `SELECT u.*,
                        COALESCE((SELECT COUNT(*) FROM player_game_results pgr WHERE pgr.user_id = u.id), 0) as games_played
                 FROM users u
                 WHERE u.user_type = 'human'
                 ORDER BY u.created_at DESC
                 LIMIT ? OFFSET ?`,
                [limit, offset]
            );

            logger.debug('Human users with stats retrieved', { count: records.length, limit, offset });

            return records;
        } catch (error) {
            logger.error('Error finding human users with stats', { error: error.message });
            throw new Error(`Failed to find human users with stats: ${error.message}`);
        }
    }

    /**
     * Count total human users
     * @returns {Promise<number>}
     */
    async countHumans() {
        try {
            const result = await this.db.get(
                "SELECT COUNT(*) as count FROM users WHERE user_type = 'human'"
            );
            return result.count;
        } catch (error) {
            logger.error('Error counting human users', { error: error.message });
            throw new Error(`Failed to count human users: ${error.message}`);
        }
    }
}

module.exports = UserRepository;
