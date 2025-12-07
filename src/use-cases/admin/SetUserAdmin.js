/**
 * SetUserAdmin Use Case
 * Grants or revokes admin rights for a user
 */

const logger = require('../../../logger');

class SetUserAdmin {
    /**
     * @param {UserRepository} userRepository - User repository
     */
    constructor(userRepository) {
        this.userRepository = userRepository;
    }

    /**
     * Execute the use case
     * @param {Object} params
     * @param {string} params.adminUserId - Admin performing the action
     * @param {string} params.targetUserId - User to modify
     * @param {boolean} params.isAdmin - New admin status
     * @returns {Promise<Object>} Result
     */
    async execute({ adminUserId, targetUserId, isAdmin }) {
        try {
            // Validate requesting user is admin
            const admin = await this.userRepository.findById(adminUserId);
            if (!admin || !admin.isAdminUser()) {
                throw new Error('Admin access required');
            }

            // Cannot modify own admin status
            if (adminUserId === targetUserId) {
                throw new Error('Cannot modify your own admin status');
            }

            const targetUser = await this.userRepository.findById(targetUserId);
            if (!targetUser) {
                throw new Error('User not found');
            }

            // Don't allow revoking admin from default 'admin' user
            if (targetUser.username === 'admin' && !isAdmin) {
                throw new Error('Cannot revoke admin rights from default admin');
            }

            await this.userRepository.setAdminStatus(targetUserId, isAdmin);

            logger.info('Admin status changed', {
                adminId: adminUserId,
                targetUserId,
                targetUsername: targetUser.username,
                newStatus: isAdmin
            });

            return {
                success: true,
                userId: targetUserId,
                username: targetUser.username,
                isAdmin
            };
        } catch (error) {
            logger.error('Failed to set admin status', {
                adminUserId,
                targetUserId,
                isAdmin,
                error: error.message
            });
            throw error;
        }
    }
}

module.exports = SetUserAdmin;
