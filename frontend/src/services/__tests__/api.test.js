import { describe, it, expect, beforeEach } from 'vitest';
import { setAuthToken, clearAuthToken } from '../api';

describe('Phase 1: API Client Tests', () => {
  beforeEach(() => {
    localStorage.clear();
  });

  describe('JWT Token Management', () => {
    it('should store JWT token in localStorage when set', () => {
      const token = 'test-jwt-token-12345';

      setAuthToken(token);

      expect(localStorage.getItem('token')).toBe(token);
    });

    it('should remove token from localStorage when cleared', () => {
      localStorage.setItem('token', 'test-token');
      localStorage.setItem('user', 'test-user');

      clearAuthToken();

      expect(localStorage.getItem('token')).toBeNull();
      expect(localStorage.getItem('user')).toBeNull();
    });

    it('should handle null token gracefully', () => {
      setAuthToken(null);

      expect(localStorage.getItem('token')).toBeNull();
    });

    it('should handle undefined token gracefully', () => {
      setAuthToken(undefined);

      expect(localStorage.getItem('token')).toBeNull();
    });
  });

  describe('Token Storage', () => {
    it('should store token with correct key', () => {
      const token = 'Bearer jwt-123';
      setAuthToken(token);

      expect(localStorage.getItem('token')).toBe(token);
    });

    it('should replace existing token', () => {
      setAuthToken('old-token');
      setAuthToken('new-token');

      expect(localStorage.getItem('token')).toBe('new-token');
    });
  });

  describe('Token Clearing', () => {
    it('should remove both token and user data', () => {
      localStorage.setItem('token', 'test-token');
      localStorage.setItem('user', JSON.stringify({ id: 1 }));

      clearAuthToken();

      expect(localStorage.getItem('token')).toBeNull();
      expect(localStorage.getItem('user')).toBeNull();
    });

    it('should not throw if nothing to clear', () => {
      expect(() => clearAuthToken()).not.toThrow();
    });
  });
});
