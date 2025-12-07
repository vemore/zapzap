/**
 * ListUsers Use Case
 * Lists all human users with their statistics for admin management
 */

const logger = require('../../../logger');

class ListUsers {
    /**
     * @param {UserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} params
     * @param {number} [params.limit=50] - Maximum number of results
     * @param {number} [params.offset=0] - Offset for pagination
     * @returns {Promise<Object>} Users list with pagination info
     */
    async execute({ limit = 50, offset = 0 }) {
        try {
            const users = await this.userRepository.findAllHumansWithStats(limit, offset);
            const total = await this.userRepository.countHumans();

            logger.debug('Admin listed users', { count: users.length, total });

            // Remove sensitive data (password_hash)
            const safeUsers = users.map(u => ({
                id: u.id,
                username: u.username,
                userType: u.user_type,
                isAdmin: u.is_admin === 1,
                lastLoginAt: u.last_login_at,
                totalPlayTimeSeconds: u.total_play_time_seconds,
                gamesPlayed: u.games_played,
                createdAt: u.created_at,
                updatedAt: u.updated_at
            }));

            return {
                success: true,
                users: safeUsers,
                pagination: { total, limit, offset }
            };
        } catch (error) {
            logger.error('Failed to list users', { error: error.message });
            throw new Error(`Failed to list users: ${error.message}`);
        }
    }
}

module.exports = ListUsers;
