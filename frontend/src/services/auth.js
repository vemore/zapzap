import { apiClient, setAuthToken, clearAuthToken } from './api';

/**
 * Login with username and password
 * @param {string} username - User's username
 * @param {string} password - User's password
 * @returns {Promise<{success: boolean, user: object, token: string}>}
 */
export const login = async (username, password) => {
  // Validation
  if (!username || username.trim() === '') {
    throw new Error('Username is required');
  }
  if (!password || password.trim() === '') {
    throw new Error('Password is required');
  }

  try {
    const response = await apiClient.post('/auth/login', {
      username,
      password,
    });

    const { token, user } = response.data;

    // Store token and user in localStorage
    setAuthToken(token);
    localStorage.setItem('user', JSON.stringify(user));

    return response.data;
  } catch (error) {
    const message = error.response?.data?.message || 'Login failed';
    throw new Error(message);
  }
};

/**
 * Register a new user
 * @param {string} username - Desired username (min 3 characters)
 * @param {string} password - Desired password (min 6 characters)
 * @returns {Promise<{success: boolean, user: object, token: string}>}
 */
export const register = async (username, password) => {
  // Validation
  if (!username || username.trim().length < 3) {
    throw new Error('Username must be at least 3 characters');
  }
  if (!password || password.length < 6) {
    throw new Error('Password must be at least 6 characters');
  }

  try {
    const response = await apiClient.post('/auth/register', {
      username,
      password,
    });

    const { token, user } = response.data;

    // Store token and user in localStorage
    setAuthToken(token);
    localStorage.setItem('user', JSON.stringify(user));

    return response.data;
  } catch (error) {
    const message = error.response?.data?.message || 'Registration failed';
    throw new Error(message);
  }
};

/**
 * Logout the current user
 */
export const logout = () => {
  clearAuthToken();
};

/**
 * Get the currently logged in user
 * @returns {object|null} - User object or null if not logged in
 */
export const getCurrentUser = () => {
  try {
    const userStr = localStorage.getItem('user');
    if (!userStr) return null;
    return JSON.parse(userStr);
  } catch (error) {
    // Handle corrupted JSON
    console.error('Error parsing user data:', error);
    return null;
  }
};

/**
 * Check if user is authenticated
 * @returns {boolean} - True if user has valid token
 */
export const isAuthenticated = () => {
  const token = localStorage.getItem('token');
  return !!token && token.trim() !== '';
};

/**
 * Get the current auth token
 * @returns {string|null} - JWT token or null
 */
export const getToken = () => {
  return localStorage.getItem('token');
};

export default {
  login,
  register,
  logout,
  getCurrentUser,
  isAuthenticated,
  getToken,
};
