/**
 * IUserRepository Interface
 * Defines the contract for User data access
 */

class IUserRepository {
    /**
     * Find user by ID
     * @param {string} id - User ID
     * @returns {Promise<User|null>} User or null if not found
     */
    async findById(id) {
        throw new Error('Method not implemented');
    }

    /**
     * Find user by username
     * @param {string} username - Username
     * @returns {Promise<User|null>} User or null if not found
     */
    async findByUsername(username) {
        throw new Error('Method not implemented');
    }

    /**
     * Check if username exists
     * @param {string} username - Username to check
     * @returns {Promise<boolean>} True if username exists
     */
    async existsByUsername(username) {
        throw new Error('Method not implemented');
    }

    /**
     * Save user (create or update)
     * @param {User} user - User entity
     * @returns {Promise<User>} Saved user
     */
    async save(user) {
        throw new Error('Method not implemented');
    }

    /**
     * Delete user by ID
     * @param {string} id - User ID
     * @returns {Promise<boolean>} True if deleted
     */
    async delete(id) {
        throw new Error('Method not implemented');
    }

    /**
     * Get all users (for admin purposes)
     * @param {number} limit - Maximum number of results
     * @param {number} offset - Offset for pagination
     * @returns {Promise<Array<User>>} Array of users
     */
    async findAll(limit = 100, offset = 0) {
        throw new Error('Method not implemented');
    }

    /**
     * Count total users
     * @returns {Promise<number>} Total count
     */
    async count() {
        throw new Error('Method not implemented');
    }
}

module.exports = IUserRepository;
