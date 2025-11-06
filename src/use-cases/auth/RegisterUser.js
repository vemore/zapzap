/**
 * RegisterUser Use Case
 * Handles user registration with validation and JWT token generation
 */

const User = require('../../domain/entities/User');
const logger = require('../../../logger');

class RegisterUser {
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
     * @param {Object} request - Registration request
     * @param {string} request.username - Username (3-50 chars, alphanumeric)
     * @param {string} request.password - Password (min 6 chars)
     * @returns {Promise<Object>} Registration result with user and token
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

            // Check if username already exists
            const existingUser = await this.userRepository.existsByUsername(trimmedUsername);

            if (existingUser) {
                logger.warn('Registration failed: username already exists', { username: trimmedUsername });
                throw new Error('Username already exists');
            }

            // Create new user (will hash password)
            const user = await User.create(trimmedUsername, password);

            // Save to repository
            await this.userRepository.save(user);

            // Generate JWT token
            const token = this.jwtService.sign({
                userId: user.id,
                username: user.username
            });

            logger.info('User registered successfully', {
                userId: user.id,
                username: user.username
            });

            return {
                success: true,
                user: user.toPublicObject(),
                token
            };
        } catch (error) {
            logger.error('Registration error', {
                username,
                error: error.message
            });

            throw error;
        }
    }
}

module.exports = RegisterUser;
