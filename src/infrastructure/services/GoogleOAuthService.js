/**
 * Google OAuth Service
 * Verifies Google ID tokens and extracts user information
 */

const { OAuth2Client } = require('google-auth-library');
const logger = require('../../../logger');

class GoogleOAuthService {
    /**
     * @param {string} clientId - Google OAuth Client ID
     */
    constructor(clientId) {
        this.clientId = clientId;
        this.client = new OAuth2Client(clientId);
    }

    /**
     * Verify Google ID token and extract user profile
     * @param {string} idToken - Google ID token (credential from frontend)
     * @returns {Promise<{googleId: string, email: string, name: string, picture: string}>}
     */
    async verifyIdToken(idToken) {
        try {
            const ticket = await this.client.verifyIdToken({
                idToken,
                audience: this.clientId
            });

            const payload = ticket.getPayload();

            if (!payload) {
                throw new Error('Invalid token payload');
            }

            // Verify email is verified
            if (!payload.email_verified) {
                throw new Error('Email not verified by Google');
            }

            const profile = {
                googleId: payload.sub,
                email: payload.email,
                name: payload.name || payload.email.split('@')[0],
                picture: payload.picture || null
            };

            logger.debug('Google token verified', {
                googleId: profile.googleId,
                email: profile.email
            });

            return profile;
        } catch (error) {
            logger.error('Google token verification failed', {
                error: error.message
            });

            if (error.message.includes('Token used too late') ||
                error.message.includes('Token used too early')) {
                throw new Error('Token expiré. Veuillez réessayer.');
            }

            if (error.message.includes('Invalid token')) {
                throw new Error('Token Google invalide');
            }

            throw new Error('Échec de la vérification Google: ' + error.message);
        }
    }

    /**
     * Generate a username from Google profile
     * @param {string} email - User email
     * @param {string} name - User name
     * @returns {string} - Generated username (alphanumeric with _ and -)
     */
    generateUsername(email, name) {
        // Try to use name first, fallback to email prefix
        let base = name || email.split('@')[0];

        // Replace special characters with underscore, keep only alphanumeric, _, -
        let username = base
            .toLowerCase()
            .replace(/[^a-z0-9_-]/g, '_')
            .replace(/_+/g, '_')
            .replace(/^_|_$/g, '');

        // Ensure minimum length
        if (username.length < 3) {
            username = username + '_user';
        }

        // Truncate if too long
        if (username.length > 30) {
            username = username.substring(0, 30);
        }

        return username;
    }

    /**
     * Generate a unique username by appending a number if needed
     * @param {string} baseUsername - Base username
     * @param {Function} existsCheck - Async function to check if username exists
     * @returns {Promise<string>} - Unique username
     */
    async generateUniqueUsername(baseUsername, existsCheck) {
        let username = baseUsername;
        let counter = 1;

        while (await existsCheck(username)) {
            // Truncate base to make room for number
            const maxBaseLength = 30 - String(counter).length - 1;
            const truncatedBase = baseUsername.substring(0, maxBaseLength);
            username = `${truncatedBase}_${counter}`;
            counter++;

            // Safety limit
            if (counter > 1000) {
                throw new Error('Unable to generate unique username');
            }
        }

        return username;
    }
}

module.exports = GoogleOAuthService;
