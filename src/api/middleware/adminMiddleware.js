/**
 * Admin Middleware
 * Validates that the authenticated user has admin privileges
 */

const logger = require('../../../logger');

/**
 * Create admin middleware
 * @param {UserRepository} userRepository - User repository instance
 * @returns {Function} Express middleware
 */
function createAdminMiddleware(userRepository) {
    return async (req, res, next) => {
        try {
            // Requires authMiddleware to run first
            if (!req.user) {
                return res.status(401).json({
                    success: false,
                    error: 'Authentication required',
                    code: 'AUTH_REQUIRED'
                });
            }

            // Check if user is admin
            const user = await userRepository.findById(req.user.id);

            if (!user || !user.isAdminUser()) {
                logger.warn('Admin access denied', {
                    userId: req.user.id,
                    path: req.path
                });
                return res.status(403).json({
                    success: false,
                    error: 'Admin access required',
                    code: 'ADMIN_REQUIRED'
                });
            }

            next();
        } catch (error) {
            logger.error('Admin middleware error', { error: error.message });
            return res.status(500).json({
                success: false,
                error: 'Internal server error',
                code: 'INTERNAL_ERROR'
            });
        }
    };
}

module.exports = { createAdminMiddleware };
