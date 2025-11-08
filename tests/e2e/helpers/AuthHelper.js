/**
 * AuthHelper
 * Handles authentication operations for E2E tests
 */

class AuthHelper {
    constructor(baseURL) {
        this.baseURL = baseURL;
        this.users = new Map(); // username -> { user, token }
    }

    /**
     * Register a new user
     * @param {string} username - Username
     * @param {string} password - Password (default: test123)
     * @returns {Promise<{user: Object, token: string}>}
     */
    async register(username, password = 'test123') {
        const response = await fetch(`${this.baseURL}/api/auth/register`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Registration failed: ${error.error || error.message}`);
        }

        const data = await response.json();

        // Store user data
        this.users.set(username, {
            user: data.user,
            token: data.token,
            password
        });

        return data;
    }

    /**
     * Login user
     * @param {string} username - Username
     * @param {string} password - Password (default: test123)
     * @returns {Promise<{user: Object, token: string}>}
     */
    async login(username, password = 'test123') {
        const response = await fetch(`${this.baseURL}/api/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ username, password })
        });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`Login failed: ${error.error || error.message}`);
        }

        const data = await response.json();

        // Store user data
        this.users.set(username, {
            user: data.user,
            token: data.token,
            password
        });

        return data;
    }

    /**
     * Register or login user (convenience method)
     * @param {string} username - Username
     * @param {string} password - Password
     * @returns {Promise<{user: Object, token: string}>}
     */
    async getOrCreateUser(username, password = 'test123') {
        try {
            return await this.register(username, password);
        } catch (error) {
            // If registration fails (user exists), try login
            if (error.message.includes('already exists')) {
                return await this.login(username, password);
            }
            throw error;
        }
    }

    /**
     * Get stored user data
     * @param {string} username - Username
     * @returns {Object|null} User data or null
     */
    getUser(username) {
        return this.users.get(username);
    }

    /**
     * Get user token
     * @param {string} username - Username
     * @returns {string|null} JWT token or null
     */
    getToken(username) {
        const userData = this.users.get(username);
        return userData?.token || null;
    }

    /**
     * Get authorization header for user
     * @param {string} username - Username
     * @returns {Object} Authorization header object
     */
    getAuthHeader(username) {
        const token = this.getToken(username);
        if (!token) {
            throw new Error(`No token found for user: ${username}`);
        }
        return { 'Authorization': `Bearer ${token}` };
    }

    /**
     * Get headers with auth and content-type
     * @param {string} username - Username
     * @returns {Object} Headers object
     */
    getHeaders(username) {
        return {
            'Content-Type': 'application/json',
            ...this.getAuthHeader(username)
        };
    }

    /**
     * Make authenticated API request
     * @param {string} username - Username
     * @param {string} path - API path (e.g., /api/party)
     * @param {Object} options - Fetch options
     * @returns {Promise<Response>} Fetch response
     */
    async request(username, path, options = {}) {
        const url = path.startsWith('http') ? path : `${this.baseURL}${path}`;

        const response = await fetch(url, {
            ...options,
            headers: {
                ...this.getHeaders(username),
                ...(options.headers || {})
            }
        });

        return response;
    }

    /**
     * Make authenticated GET request
     * @param {string} username - Username
     * @param {string} path - API path
     * @returns {Promise<Object>} Response data
     */
    async get(username, path) {
        const response = await this.request(username, path, { method: 'GET' });

        if (!response.ok) {
            const error = await response.json();
            throw new Error(`GET ${path} failed: ${error.error || error.message}`);
        }

        return await response.json();
    }

    /**
     * Make authenticated POST request
     * @param {string} username - Username
     * @param {string} path - API path
     * @param {Object} data - Request body
     * @returns {Promise<Object>} Response data
     */
    async post(username, path, data) {
        const response = await this.request(username, path, {
            method: 'POST',
            body: JSON.stringify(data)
        });

        if (!response.ok) {
            const error = await response.json();
            const errorMsg = error.details || error.error || error.message || 'Unknown error';
            throw new Error(`POST ${path} failed: ${errorMsg}`);
        }

        return await response.json();
    }

    /**
     * Authenticate Playwright page/context with user token
     * @param {Page|BrowserContext} pageOrContext - Playwright page or context
     * @param {string} username - Username
     * @returns {Promise<void>}
     */
    async authenticatePage(pageOrContext, username) {
        const userData = this.users.get(username);
        if (!userData) {
            throw new Error(`User not found: ${username}. Call register/login first.`);
        }

        // Set localStorage with auth token
        await pageOrContext.addInitScript((token) => {
            localStorage.setItem('token', token);
        }, userData.token);

        // Also set user data if needed
        await pageOrContext.addInitScript((user) => {
            localStorage.setItem('user', JSON.stringify(user));
        }, userData.user);
    }

    /**
     * Create authenticated Playwright context
     * @param {Browser} browser - Playwright browser
     * @param {string} username - Username
     * @returns {Promise<BrowserContext>} Authenticated browser context
     */
    async createAuthContext(browser, username) {
        const userData = this.users.get(username);
        if (!userData) {
            throw new Error(`User not found: ${username}. Call register/login first.`);
        }

        // Create new context with storage state
        const context = await browser.newContext({
            storageState: {
                cookies: [],
                origins: [
                    {
                        origin: this.baseURL.replace(':9999', ':5173'), // Frontend URL
                        localStorage: [
                            {
                                name: 'token',
                                value: userData.token
                            },
                            {
                                name: 'user',
                                value: JSON.stringify(userData.user)
                            }
                        ]
                    }
                ]
            }
        });

        return context;
    }

    /**
     * Setup multiple authenticated users for multi-player tests
     * @param {Array<string>} usernames - Array of usernames
     * @param {string} password - Common password (default: test123)
     * @returns {Promise<Array<{user: Object, token: string}>>}
     */
    async setupMultipleUsers(usernames, password = 'test123') {
        const results = [];

        for (const username of usernames) {
            const data = await this.getOrCreateUser(username, password);
            results.push(data);
        }

        return results;
    }

    /**
     * Create multiple authenticated Playwright contexts
     * @param {Browser} browser - Playwright browser
     * @param {Array<string>} usernames - Array of usernames
     * @returns {Promise<Array<BrowserContext>>} Array of authenticated contexts
     */
    async createMultipleContexts(browser, usernames) {
        const contexts = [];

        for (const username of usernames) {
            const context = await this.createAuthContext(browser, username);
            contexts.push(context);
        }

        return contexts;
    }

    /**
     * Clear stored user data
     */
    clear() {
        this.users.clear();
    }

    /**
     * Get all registered usernames
     * @returns {Array<string>} Array of usernames
     */
    getUsernames() {
        return Array.from(this.users.keys());
    }

    /**
     * Get count of registered users
     * @returns {number} User count
     */
    getUserCount() {
        return this.users.size;
    }

    /**
     * Check if user is registered
     * @param {string} username - Username
     * @returns {boolean} True if user is registered
     */
    hasUser(username) {
        return this.users.has(username);
    }
}

/**
 * Create AuthHelper instance
 * @param {string} baseURL - Base URL for API requests
 * @returns {AuthHelper} AuthHelper instance
 */
function createAuthHelper(baseURL) {
    return new AuthHelper(baseURL);
}

module.exports = {
    AuthHelper,
    createAuthHelper
};
