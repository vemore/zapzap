import { describe, it, expect } from 'vitest';

describe('Phase 0: Infrastructure Tests', () => {
  describe('Test Environment', () => {
    it('should have vitest globals available', () => {
      expect(describe).toBeDefined();
      expect(it).toBeDefined();
      expect(expect).toBeDefined();
    });

    it('should have jest-dom matchers available', () => {
      const element = document.createElement('div');
      expect(element).toBeInTheDocument;
    });
  });

  describe('Browser APIs', () => {
    it('should have localStorage mock', () => {
      expect(localStorage).toBeDefined();
      expect(localStorage.getItem).toBeDefined();
      expect(localStorage.setItem).toBeDefined();
      expect(localStorage.removeItem).toBeDefined();
    });

    it('should have EventSource mock for SSE', () => {
      expect(EventSource).toBeDefined();
      const eventSource = new EventSource('http://test.com');
      expect(eventSource.url).toBe('http://test.com');
      expect(eventSource.close).toBeDefined();
    });
  });

  describe('Environment Configuration', () => {
    it('should run in test environment', () => {
      expect(import.meta.env.MODE).toBe('test');
    });
  });
});
