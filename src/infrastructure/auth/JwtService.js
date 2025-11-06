/**
 * JWT Service
 * Handles token generation, validation, and decoding for authentication
 */

const jwt = require('jsonwebtoken');
const logger = require('../../../logger');

class JwtService {
    constructor(config = {}) {
        this.secret = config.secret || process.env.JWT_SECRET || 'zapzap-secret-key-change-in-production';
        this.expiresIn = config.expiresIn || '7d'; // 7 days default
        this.algorithm = config.algorithm || 'HS256';

        if (this.secret === 'zapzap-secret-key-change-in-production' && process.env.NODE_ENV === 'production') {
            logger.warn('Using default JWT secret in production! Set JWT_SECRET environment variable.');
        }
    }

    /**
     * Generate JWT token for user
     * @param {Object} payload - Token payload
     * @param {string} payload.userId - User ID
     * @param {string} payload.username - Username
     * @returns {string} JWT token
     */
    sign(payload) {
        try {
            const token = jwt.sign(
                {
                    userId: payload.userId,
                    username: payload.username
                },
                this.secret,
                {
                    expiresIn: this.expiresIn,
                    algorithm: this.algorithm
                }
            );

            logger.info('JWT token generated', {
                userId: payload.userId,
                username: payload.username
            });

            return token;
        } catch (error) {
            logger.error('JWT token generation failed', {
                error: error.message,
                userId: payload.userId
            });
            throw new Error('Failed to generate authentication token');
        }
    }

    /**
     * Verify and decode JWT token
     * @param {string} token - JWT token
     * @returns {Object} Decoded token payload
     * @throws {Error} If token is invalid or expired
     */
    verify(token) {
        try {
            const decoded = jwt.verify(token, this.secret, {
                algorithms: [this.algorithm]
            });

            return {
                userId: decoded.userId,
                username: decoded.username,
                iat: decoded.iat,
                exp: decoded.exp
            };
        } catch (error) {
            if (error.name === 'TokenExpiredError') {
                logger.warn('JWT token expired', { expiredAt: error.expiredAt });
                throw new Error('Token expired');
            } else if (error.name === 'JsonWebTokenError') {
                logger.warn('Invalid JWT token', { error: error.message });
                throw new Error('Invalid token');
            } else {
                logger.error('JWT verification failed', { error: error.message });
                throw new Error('Token verification failed');
            }
        }
    }

    /**
     * Decode JWT token without verification (for debugging)
     * @param {string} token - JWT token
     * @returns {Object|null} Decoded token payload or null if invalid
     */
    decode(token) {
        try {
            return jwt.decode(token);
        } catch (error) {
            logger.warn('JWT token decode failed', { error: error.message });
            return null;
        }
    }

    /**
     * Extract token from Authorization header
     * @param {string} authHeader - Authorization header value
     * @returns {string|null} Token or null if not found
     */
    extractTokenFromHeader(authHeader) {
        if (!authHeader) {
            return null;
        }

        // Expected format: "Bearer <token>"
        const parts = authHeader.split(' ');
        if (parts.length !== 2 || parts[0] !== 'Bearer') {
            logger.warn('Invalid Authorization header format', { header: authHeader });
            return null;
        }

        return parts[1];
    }

    /**
     * Check if token is expired (without verification)
     * @param {string} token - JWT token
     * @returns {boolean} True if expired
     */
    isExpired(token) {
        const decoded = this.decode(token);
        if (!decoded || !decoded.exp) {
            return true;
        }

        const now = Math.floor(Date.now() / 1000);
        return decoded.exp < now;
    }

    /**
     * Get remaining time until token expiration
     * @param {string} token - JWT token
     * @returns {number} Seconds until expiration, -1 if expired or invalid
     */
    getTimeToExpiry(token) {
        const decoded = this.decode(token);
        if (!decoded || !decoded.exp) {
            return -1;
        }

        const now = Math.floor(Date.now() / 1000);
        return Math.max(0, decoded.exp - now);
    }
}

module.exports = JwtService;
