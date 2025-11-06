import { describe, it, expect, beforeEach, vi } from 'vitest';
import { login, logout, register, getCurrentUser, isAuthenticated } from '../auth';
import * as api from '../api';

// Mock the API module
vi.mock('../api', () => ({
  apiClient: {
    post: vi.fn(),
  },
  setAuthToken: vi.fn((token) => {
    if (token) {
      localStorage.setItem('token', token);
    }
  }),
  clearAuthToken: vi.fn(() => {
    localStorage.removeItem('token');
    localStorage.removeItem('user');
  }),
}));

describe('Phase 1: Authentication Service Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  describe('Login Functionality', () => {
    it('should login with username and password', async () => {
      const mockResponse = {
        data: {
          success: true,
          token: 'jwt-token-12345',
          user: { id: '1', username: 'testuser' }
        }
      };

      api.apiClient.post = vi.fn().mockResolvedValue(mockResponse);

      const result = await login('testuser', 'password123');

      expect(api.apiClient.post).toHaveBeenCalledWith('/auth/login', {
        username: 'testuser',
        password: 'password123'
      });
      expect(result.success).toBe(true);
      expect(result.user).toBeDefined();
    });

    it('should store token in localStorage on successful login', async () => {
      const token = 'jwt-token-12345';
      const mockResponse = {
        data: {
          success: true,
          token,
          user: { id: '1', username: 'testuser' }
        }
      };

      api.apiClient.post = vi.fn().mockResolvedValue(mockResponse);

      await login('testuser', 'password123');

      expect(localStorage.getItem('token')).toBe(token);
    });

    it('should store user data in localStorage on successful login', async () => {
      const user = { id: '1', username: 'testuser' };
      const mockResponse = {
        data: {
          success: true,
          token: 'token',
          user
        }
      };

      api.apiClient.post = vi.fn().mockResolvedValue(mockResponse);

      await login('testuser', 'password123');

      const storedUser = JSON.parse(localStorage.getItem('user'));
      expect(storedUser).toEqual(user);
    });

    it('should throw error on failed login', async () => {
      const mockError = {
        response: {
          data: { message: 'Invalid credentials' }
        }
      };

      api.apiClient.post = vi.fn().mockRejectedValue(mockError);

      await expect(login('testuser', 'wrongpassword')).rejects.toThrow();
    });

    it('should validate username is provided', async () => {
      await expect(login('', 'password')).rejects.toThrow();
    });

    it('should validate password is provided', async () => {
      await expect(login('username', '')).rejects.toThrow();
    });
  });

  describe('Logout Functionality', () => {
    it('should clear token from localStorage', () => {
      localStorage.setItem('token', 'test-token');
      localStorage.setItem('user', JSON.stringify({ id: '1' }));

      logout();

      expect(localStorage.getItem('token')).toBeNull();
    });

    it('should clear user data from localStorage', () => {
      localStorage.setItem('token', 'test-token');
      localStorage.setItem('user', JSON.stringify({ id: '1' }));

      logout();

      expect(localStorage.getItem('user')).toBeNull();
    });

    it('should not throw error if already logged out', () => {
      expect(() => logout()).not.toThrow();
    });
  });

  describe('Registration Functionality', () => {
    it('should register new user with username and password', async () => {
      const mockResponse = {
        data: {
          success: true,
          token: 'jwt-token-12345',
          user: { id: '1', username: 'newuser' }
        }
      };

      api.apiClient.post = vi.fn().mockResolvedValue(mockResponse);

      const result = await register('newuser', 'password123');

      expect(api.apiClient.post).toHaveBeenCalledWith('/auth/register', {
        username: 'newuser',
        password: 'password123'
      });
      expect(result.success).toBe(true);
    });

    it('should store token and user after successful registration', async () => {
      const token = 'jwt-token-12345';
      const user = { id: '1', username: 'newuser' };
      const mockResponse = {
        data: {
          success: true,
          token,
          user
        }
      };

      api.apiClient.post = vi.fn().mockResolvedValue(mockResponse);

      await register('newuser', 'password123');

      expect(localStorage.getItem('token')).toBe(token);
      expect(JSON.parse(localStorage.getItem('user'))).toEqual(user);
    });

    it('should validate username length (min 3 characters)', async () => {
      await expect(register('ab', 'password123')).rejects.toThrow();
    });

    it('should validate password length (min 6 characters)', async () => {
      await expect(register('username', '12345')).rejects.toThrow();
    });
  });

  describe('Current User', () => {
    it('should return current user from localStorage', () => {
      const user = { id: '1', username: 'testuser' };
      localStorage.setItem('user', JSON.stringify(user));

      const currentUser = getCurrentUser();

      expect(currentUser).toEqual(user);
    });

    it('should return null if no user is logged in', () => {
      const currentUser = getCurrentUser();

      expect(currentUser).toBeNull();
    });

    it('should handle corrupted user data gracefully', () => {
      localStorage.setItem('user', 'invalid-json{');

      const currentUser = getCurrentUser();

      expect(currentUser).toBeNull();
    });
  });

  describe('Authentication State', () => {
    it('should return true if token exists', () => {
      localStorage.setItem('token', 'test-token');

      expect(isAuthenticated()).toBe(true);
    });

    it('should return false if no token exists', () => {
      expect(isAuthenticated()).toBe(false);
    });

    it('should return false if token is empty string', () => {
      localStorage.setItem('token', '');

      expect(isAuthenticated()).toBe(false);
    });
  });
});
