/**
 * DeleteUser Use Case
 * Deletes a user and their in-progress parties (preserves statistics)
 */

const logger = require('../../../logger');

class DeleteUser {
    /**
     * @param {UserRepository} userRepository - User repository
     * @param {PartyRepository} partyRepository - Party repository
     */
    constructor(userRepository, partyRepository) {
        this.userRepository = userRepository;
        this.partyRepository = partyRepository;
    }

    /**
     * Execute the use case
     * @param {Object} params
     * @param {string} params.adminUserId - Admin performing the action
     * @param {string} params.targetUserId - User to delete
     * @returns {Promise<Object>} Result
     */
    async execute({ adminUserId, targetUserId }) {
        try {
            // Validate admin
            const admin = await this.userRepository.findById(adminUserId);
            if (!admin || !admin.isAdminUser()) {
                throw new Error('Admin access required');
            }

            // Cannot delete self
            if (adminUserId === targetUserId) {
                throw new Error('Cannot delete your own account');
            }

            // Get target user
            const targetUser = await this.userRepository.findById(targetUserId);
            if (!targetUser) {
                throw new Error('User not found');
            }

            // Cannot delete the default admin
            if (targetUser.username === 'admin') {
                throw new Error('Cannot delete the default admin account');
            }

            // Delete the user (CASCADE will handle related records)
            // Note: player_game_results and round_scores have ON DELETE CASCADE,
            // so stats are preserved in those tables even after user deletion
            await this.userRepository.delete(targetUserId);

            logger.info('User deleted by admin', {
                adminId: adminUserId,
                deletedUserId: targetUserId,
                deletedUsername: targetUser.username
            });

            return {
                success: true,
                deletedUserId: targetUserId,
                deletedUsername: targetUser.username
            };
        } catch (error) {
            logger.error('Failed to delete user', {
                adminUserId,
                targetUserId,
                error: error.message
            });
            throw error;
        }
    }
}

module.exports = DeleteUser;
