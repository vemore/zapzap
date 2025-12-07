/**
 * CreateDefaultAdmin Use Case
 * Creates the default admin user on server startup if it doesn't exist
 */

const User = require('../../domain/entities/User');
const logger = require('../../../logger');

class CreateDefaultAdmin {
    /**
     * @param {UserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} params
     * @param {string} params.password - Admin password
     * @returns {Promise<Object>} Result with created flag
     */
    async execute({ password }) {
        const adminUsername = 'admin';

        try {
            // Check if admin already exists
            const existingAdmin = await this.userRepository.findByUsername(adminUsername);
            if (existingAdmin) {
                logger.debug('Default admin user already exists');
                return { success: true, created: false, message: 'Admin already exists' };
            }

            // Create admin user
            const admin = await User.create(adminUsername, password);
            admin.setAdmin(true);

            await this.userRepository.save(admin);

            logger.info('Default admin user created', { userId: admin.id });

            return {
                success: true,
                created: true,
                user: admin.toPublicObject()
            };
        } catch (error) {
            logger.error('Failed to create default admin', { error: error.message });
            throw new Error(`Failed to create default admin: ${error.message}`);
        }
    }
}

module.exports = CreateDefaultAdmin;
