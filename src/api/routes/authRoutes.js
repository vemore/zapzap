/**
 * Authentication Routes
 * Handles user registration and login
 */

const express = require('express');
const logger = require('../../../logger');

/**
 * Create authentication router
 * @param {DIContainer} container - DI container
 * @returns {express.Router}
 */
function createAuthRouter(container) {
    const router = express.Router();

    const registerUser = container.resolve('registerUser');
    const loginUser = container.resolve('loginUser');

    /**
     * POST /api/auth/register
     * Register a new user
     */
    router.post('/register', async (req, res) => {
        try {
            const { username, password } = req.body;

            if (!username || !password) {
                return res.status(400).json({
                    error: 'Username and password are required',
                    code: 'MISSING_CREDENTIALS'
                });
            }

            const result = await registerUser.execute({ username, password });

            logger.info('User registered', { userId: result.user.id, username: result.user.username });

            res.status(201).json({
                success: true,
                user: {
                    id: result.user.id,
                    username: result.user.username,
                    createdAt: result.user.createdAt
                },
                token: result.token
            });
        } catch (error) {
            logger.error('Registration error', {
                error: error.message,
                username: req.body.username
            });

            if (error.message === 'Username already exists') {
                return res.status(409).json({
                    error: error.message,
                    code: 'USERNAME_EXISTS'
                });
            }

            res.status(500).json({
                error: 'Registration failed',
                code: 'REGISTRATION_ERROR',
                details: error.message
            });
        }
    });

    /**
     * POST /api/auth/login
     * Login with username and password
     */
    router.post('/login', async (req, res) => {
        try {
            const { username, password } = req.body;

            if (!username || !password) {
                return res.status(400).json({
                    error: 'Username and password are required',
                    code: 'MISSING_CREDENTIALS'
                });
            }

            const result = await loginUser.execute({ username, password });

            logger.info('User logged in', { userId: result.user.id, username: result.user.username });

            res.json({
                success: true,
                user: {
                    id: result.user.id,
                    username: result.user.username
                },
                token: result.token
            });
        } catch (error) {
            logger.warn('Login failed', {
                error: error.message,
                username: req.body.username
            });

            if (error.message === 'Invalid username or password') {
                return res.status(401).json({
                    error: error.message,
                    code: 'INVALID_CREDENTIALS'
                });
            }

            res.status(500).json({
                error: 'Login failed',
                code: 'LOGIN_ERROR',
                details: error.message
            });
        }
    });

    return router;
}

module.exports = createAuthRouter;
