/**
 * LoginUser Use Case
 * Handles user authentication and JWT token generation
 */

const logger = require('../../../logger');

class LoginUser {
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
     * @param {Object} request - Login request
     * @param {string} request.username - Username
     * @param {string} request.password - Password
     * @returns {Promise<Object>} Login result with user and token
     */
    async execute({ username, password }) {
        try {
            // Validate input
            if (!username || typeof username !== 'string') {
                throw new Error('Username is required');
            }

            if (!password || typeof password !== 'string') {
                throw new Error('Password is required');
            }

            const trimmedUsername = username.trim();

            // Find user by username
            const user = await this.userRepository.findByUsername(trimmedUsername);

            if (!user) {
                logger.warn('Login failed: user not found', { username: trimmedUsername });
                throw new Error('Invalid username or password');
            }

            // Verify password
            const isPasswordValid = await user.verifyPassword(password);

            if (!isPasswordValid) {
                logger.warn('Login failed: invalid password', {
                    userId: user.id,
                    username: user.username
                });
                throw new Error('Invalid username or password');
            }

            // Update last login timestamp
            await this.userRepository.updateLastLogin(user.id);

            // Generate JWT token (include isAdmin for frontend)
            const token = this.jwtService.sign({
                userId: user.id,
                username: user.username,
                isAdmin: user.isAdminUser()
            });

            logger.info('User logged in successfully', {
                userId: user.id,
                username: user.username,
                isAdmin: user.isAdminUser()
            });

            return {
                success: true,
                user: user.toPublicObject(),
                token
            };
        } catch (error) {
            logger.error('Login error', {
                username,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = LoginUser;
