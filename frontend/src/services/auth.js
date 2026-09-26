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
 * Validate username format
 * @param {string} username - Username to validate
 * @returns {{valid: boolean, message: string|null}}
 */
export const validateUsername = (username) => {
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
      message: 'Le pseudo ne peut contenir que des lettres, chiffres, tirets (-) et underscores (_)',
    };
  }

  return { valid: true, message: null };
};

/**
 * Validate password format
 * @param {string} password - Password to validate
 * @returns {{valid: boolean, message: string|null}}
 */
export const validatePassword = (password) => {
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
};

/**
 * Register a new user
 * @param {string} username - Desired username (3-30 chars, alphanumeric with - and _)
 * @param {string} password - Desired password (6-100 chars)
 * @returns {Promise<{success: boolean, user: object, token: string}>}
 */
export const register = async (username, password) => {
  // Validate username
  const usernameValidation = validateUsername(username);
  if (!usernameValidation.valid) {
    throw new Error(usernameValidation.message);
  }

  // Validate password
  const passwordValidation = validatePassword(password);
  if (!passwordValidation.valid) {
    throw new Error(passwordValidation.message);
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
  localStorage.removeItem('user');
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

/**
 * Login or register with Google OAuth
 * @param {string} credential - Google ID token
 * @returns {Promise<{success: boolean, user: object, token: string, isNewUser: boolean}>}
 */
export const loginWithGoogle = async (credential) => {
  if (!credential) {
    throw new Error('Token Google requis');
  }

  try {
    const response = await apiClient.post('/auth/google', {
      credential,
    });

    const { token, user } = response.data;

    // Store token and user in localStorage
    setAuthToken(token);
    localStorage.setItem('user', JSON.stringify(user));

    return response.data;
  } catch (error) {
    const message = error.response?.data?.error || error.response?.data?.details || 'Connexion Google échouée';
    throw new Error(message);
  }
};

/**
 * Delete the signed-in user's account, confirmed by their password or, for an account
 * created with Google, by a fresh Google ID token. On success the stored session is
 * cleared. A refusal throws an Error whose `code` is the backend's (INVALID_PASSWORD,
 * MISSING_CONFIRMATION, GOOGLE_AUTH_FAILED, ACTIVE_PARTY, LAST_ADMIN).
 * @param {{password?: string, credential?: string}} confirmation
 * @returns {Promise<{success: boolean, deletedUserId: string}>}
 */
export const deleteAccount = async ({ password, credential } = {}) => {
  try {
    const response = await apiClient.delete('/auth/me', {
      data: credential ? { credential } : { password },
    });
    logout();
    return response.data;
  } catch (error) {
    const err = new Error(error.response?.data?.error || 'Suppression du compte échouée');
    err.code = error.response?.data?.code;
    throw err;
  }
};

export default {
  deleteAccount,
  login,
  register,
  logout,
  getCurrentUser,
  isAuthenticated,
  getToken,
  validateUsername,
  validatePassword,
  loginWithGoogle,
};
