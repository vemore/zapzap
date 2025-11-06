/**
 * JWT Service
 * Handles JSON Web Token signing and verification
 */

const jwt = require('jsonwebtoken');

class JwtService {
    constructor(secret = null, expiresIn = '24h') {
        this.secret = secret || process.env.JWT_SECRET || 'zapzap-secret-key-change-in-production';
        this.expiresIn = expiresIn;
    }

    /**
     * Sign a payload and return JWT token
     * @param {Object} payload - Payload to sign
     * @param {string} expiresIn - Optional expiration time
     * @returns {string} JWT token
     */
    sign(payload, expiresIn = null) {
        return jwt.sign(payload, this.secret, {
            expiresIn: expiresIn || this.expiresIn
        });
    }

    /**
     * Verify and decode a JWT token
     * @param {string} token - JWT token to verify
     * @returns {Object} Decoded payload
     * @throws {Error} If token is invalid or expired
     */
    verify(token) {
        return jwt.verify(token, this.secret);
    }

    /**
     * Decode a JWT token without verification (for inspection)
     * @param {string} token - JWT token to decode
     * @returns {Object|null} Decoded payload or null if invalid
     */
    decode(token) {
        return jwt.decode(token);
    }
}

module.exports = JwtService;
