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
     * Validate username format
     * @param {string} username - Username to validate
     * @returns {{valid: boolean, message: string|null}}
     */
    validateUsername(username) {
        if (!username || typeof username !== 'string') {
            return { valid: false, message: 'Le pseudo est requis' };
        }

        const trimmed = username.trim();

        if (trimmed.length < 3) {
            return { valid: false, message: 'Le pseudo doit contenir au moins 3 caractères' };
        }

        if (trimmed.length > 30) {
            return { valid: false, message: 'Le pseudo ne peut pas dépasser 30 caractères' };
        }

        // Only allow letters, numbers, hyphens and underscores
        const validUsernameRegex = /^[a-zA-Z0-9_-]+$/;
        if (!validUsernameRegex.test(trimmed)) {
            return {
                valid: false,
                message: 'Le pseudo ne peut contenir que des lettres, chiffres, tirets (-) et underscores (_)'
            };
        }

        return { valid: true, message: null };
    }

    /**
     * Validate password format
     * @param {string} password - Password to validate
     * @returns {{valid: boolean, message: string|null}}
     */
    validatePassword(password) {
        if (!password || typeof password !== 'string') {
            return { valid: false, message: 'Le mot de passe est requis' };
        }

        if (password.length < 6) {
            return { valid: false, message: 'Le mot de passe doit contenir au moins 6 caractères' };
        }

        if (password.length > 100) {
            return { valid: false, message: 'Le mot de passe ne peut pas dépasser 100 caractères' };
        }

        return { valid: true, message: null };
    }

    /**
     * Execute the use case
     * @param {Object} request - Registration request
     * @param {string} request.username - Username (3-30 chars, alphanumeric with - and _)
     * @param {string} request.password - Password (6-100 chars)
     * @returns {Promise<Object>} Registration result with user and token
     */
    async execute({ username, password }) {
        try {
            // Validate username
            const usernameValidation = this.validateUsername(username);
            if (!usernameValidation.valid) {
                throw new Error(usernameValidation.message);
            }

            // Validate password
            const passwordValidation = this.validatePassword(password);
            if (!passwordValidation.valid) {
                throw new Error(passwordValidation.message);
            }

            const trimmedUsername = username.trim();

            // Check if username already exists
            const existingUser = await this.userRepository.existsByUsername(trimmedUsername);

            if (existingUser) {
                logger.warn('Registration failed: username already exists', { username: trimmedUsername });
                throw new Error('Ce pseudo est déjà pris');
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
