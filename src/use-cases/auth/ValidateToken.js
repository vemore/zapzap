/**
 * ValidateToken Use Case
 * Validates JWT tokens and returns associated user information
 */

const logger = require('../../../logger');

class ValidateToken {
    /**
     * @param {IUserRepository} userRepository - User repository
     * @param {JwtService} jwtService - JWT service
     */
    constructor(userRepository, jwtService) {
        this.userRepository = userRepository;
        this.jwtService = jwtService;
    }

    /**
     * Execute the use case
     * @param {Object} request - Validation request
     * @param {string} request.token - JWT token to validate
     * @returns {Promise<Object>} Validation result with user
     */
    async execute({ token }) {
        try {
            // Validate input
            if (!token || typeof token !== 'string') {
                throw new Error('Token is required');
            }

            // Verify and decode token
            let decoded;
            try {
                decoded = this.jwtService.verify(token);
            } catch (error) {
                logger.warn('Token validation failed', { error: error.message });
                throw new Error('Invalid or expired token');
            }

            // Find user by ID from token
            const user = await this.userRepository.findById(decoded.userId);

            if (!user) {
                logger.warn('Token validation failed: user not found', {
                    userId: decoded.userId
                });
                throw new Error('User not found');
            }

            logger.debug('Token validated successfully', {
                userId: user.id,
                username: user.username
            });

            return {
                success: true,
                user: user.toPublicObject(),
                tokenData: {
                    userId: decoded.userId,
                    username: decoded.username,
                    issuedAt: decoded.iat,
                    expiresAt: decoded.exp
                }
            };
        } catch (error) {
            logger.error('Token validation error', {
                error: error.message
            });

            throw error;
        }
    }

    /**
     * Validate token from Authorization header
     * @param {string} authHeader - Authorization header value
     * @returns {Promise<Object>} Validation result with user
     */
    async executeFromHeader({ authHeader }) {
        const token = this.jwtService.extractTokenFromHeader(authHeader);

        if (!token) {
            throw new Error('Invalid Authorization header format');
        }

        return this.execute({ token });
    }
}

module.exports = ValidateToken;
