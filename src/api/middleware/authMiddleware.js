/**
 * Authentication Middleware
 * Validates JWT tokens and attaches user to request
 */

const logger = require('../../../logger');

/**
 * Create authentication middleware
 * @param {ValidateToken} validateTokenUseCase - ValidateToken use case
 * @returns {Function} Express middleware
 */
function createAuthMiddleware(validateTokenUseCase) {
    return async (req, res, next) => {
        try {
            // Extract token from Authorization header
            const authHeader = req.headers.authorization;

            if (!authHeader) {
                return res.status(401).json({
                    error: 'Missing authorization header',
                    code: 'MISSING_AUTH_HEADER'
                });
            }

            // Expect format: "Bearer <token>"
            const parts = authHeader.split(' ');
            if (parts.length !== 2 || parts[0] !== 'Bearer') {
                return res.status(401).json({
                    error: 'Invalid authorization header format',
                    code: 'INVALID_AUTH_FORMAT',
                    details: {
                        expected: 'Bearer <token>'
                    }
                });
            }

            const token = parts[1];

            // Validate token
            const result = await validateTokenUseCase.execute({ token });

            // Attach user to request
            req.user = result.user;

            next();
        } catch (error) {
            logger.warn('Authentication failed', {
                error: error.message,
                path: req.path,
                ip: req.ip
            });

            return res.status(401).json({
                error: 'Invalid or expired token',
                code: 'INVALID_TOKEN'
            });
        }
    };
}

/**
 * Create optional authentication middleware
 * Attaches user if token is valid, but doesn't require it
 * @param {ValidateToken} validateTokenUseCase - ValidateToken use case
 * @returns {Function} Express middleware
 */
function createOptionalAuthMiddleware(validateTokenUseCase) {
    return async (req, res, next) => {
        try {
            const authHeader = req.headers.authorization;

            if (!authHeader) {
                // No token provided, continue without user
                return next();
            }

            const parts = authHeader.split(' ');
            if (parts.length === 2 && parts[0] === 'Bearer') {
                const token = parts[1];

                try {
                    const result = await validateTokenUseCase.execute({ token });
                    req.user = result.user;
                } catch (error) {
                    // Token validation failed, but that's okay for optional auth
                    logger.debug('Optional auth failed', { error: error.message });
                }
            }

            next();
        } catch (error) {
            // Don't fail the request, just continue without user
            logger.error('Optional auth middleware error', {
                error: error.message,
                path: req.path
            });
            next();
        }
    };
}

module.exports = {
    createAuthMiddleware,
    createOptionalAuthMiddleware
};
