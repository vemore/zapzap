/**
 * LoginWithGoogle Use Case
 * Handles user authentication via Google OAuth
 * Creates new user if first login, otherwise logs in existing user
 */

const User = require('../../domain/entities/User');
const logger = require('../../../logger');

class LoginWithGoogle {
    /**
     * @param {IUserRepository} userRepository - User repository
     * @param {JwtService} jwtService - JWT service
     * @param {GoogleOAuthService} googleOAuthService - Google OAuth service
     */
    constructor(userRepository, jwtService, googleOAuthService) {
        this.userRepository = userRepository;
        this.jwtService = jwtService;
        this.googleOAuthService = googleOAuthService;
    }

    /**
     * Execute the use case
     * @param {Object} request - Login request
     * @param {string} request.credential - Google ID token
     * @returns {Promise<Object>} Login result with user and token
     */
    async execute({ credential }) {
        try {
            // Validate input
            if (!credential || typeof credential !== 'string') {
                throw new Error('Token Google requis');
            }

            // Verify Google token and get profile
            const googleProfile = await this.googleOAuthService.verifyIdToken(credential);

            // Try to find existing user by Google ID
            let user = await this.userRepository.findByGoogleId(googleProfile.googleId);

            if (user) {
                // Existing user - update last login
                user.updateLastLogin();
                await this.userRepository.save(user);

                logger.info('Google user logged in', {
                    userId: user.id,
                    username: user.username,
                    googleId: googleProfile.googleId
                });
            } else {
                // New user - create account
                // Generate unique username from Google profile
                const baseUsername = this.googleOAuthService.generateUsername(
                    googleProfile.email,
                    googleProfile.name
                );

                const username = await this.googleOAuthService.generateUniqueUsername(
                    baseUsername,
                    (name) => this.userRepository.existsByUsername(name)
                );

                // Create user from Google profile
                user = User.createFromGoogle(googleProfile, username);
                await this.userRepository.save(user);

                logger.info('New Google user registered', {
                    userId: user.id,
                    username: user.username,
                    googleId: googleProfile.googleId,
                    email: googleProfile.email
                });
            }

            // Generate JWT token
            const token = this.jwtService.sign({
                userId: user.id,
                username: user.username,
                isAdmin: user.isAdmin
            });

            return {
                success: true,
                user: user.toPublicObject(),
                token,
                isNewUser: !user.lastLoginAt || user.createdAt === user.updatedAt
            };
        } catch (error) {
            logger.error('Google login error', {
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = LoginWithGoogle;
