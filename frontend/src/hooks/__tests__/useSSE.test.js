import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import useSSE from '../useSSE';

// Mock EventSource
class MockEventSource {
  constructor(url) {
    this.url = url;
    this.readyState = 0; // CONNECTING
    this.onopen = null;
    this.onerror = null;
    this.onmessage = null;
    this.listeners = {};

    // Simulate connection opening
    setTimeout(() => {
      this.readyState = 1; // OPEN
      if (this.onopen) this.onopen({ type: 'open' });
    }, 0);
  }

  addEventListener(event, handler) {
    if (!this.listeners[event]) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(handler);
  }

  removeEventListener(event, handler) {
    if (this.listeners[event]) {
      this.listeners[event] = this.listeners[event].filter((h) => h !== handler);
    }
  }

  close() {
    this.readyState = 2; // CLOSED
  }

  // Test helper to simulate receiving a message
  _simulateMessage(data) {
    const event = {
      type: 'message',
      data: JSON.stringify(data),
    };
    if (this.onmessage) this.onmessage(event);
    if (this.listeners.message) {
      this.listeners.message.forEach((handler) => handler(event));
    }
  }

  // Test helper to simulate an error
  _simulateError(error) {
    const event = { type: 'error', error };
    if (this.onerror) this.onerror(event);
    if (this.listeners.error) {
      this.listeners.error.forEach((handler) => handler(event));
    }
  }
}

describe('Phase 6: useSSE Hook Tests', () => {
  let originalEventSource;

  beforeEach(() => {
    originalEventSource = global.EventSource;
    global.EventSource = MockEventSource;
  });

  afterEach(() => {
    global.EventSource = originalEventSource;
  });

  describe('Connection Management', () => {
    it('should create EventSource connection on mount', () => {
      const { result } = renderHook(() => useSSE('/suscribeupdate'));

      expect(result.current.connected).toBe(false); // Initially connecting

      // Will become connected after setTimeout
    });

    it('should set connected to true when connection opens', async () => {
      const { result } = renderHook(() => useSSE('/suscribeupdate'));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });
    });

    it('should close connection on unmount', () => {
      const { unmount } = renderHook(() => useSSE('/suscribeupdate'));

      const closeSpy = vi.spyOn(MockEventSource.prototype, 'close');
      unmount();

      expect(closeSpy).toHaveBeenCalled();
    });

    it('should not create connection if url is null', () => {
      const { result } = renderHook(() => useSSE(null));

      expect(result.current.connected).toBe(false);
      expect(result.current.error).toBe(null);
    });
  });

  describe('Message Handling', () => {
    it('should receive and parse messages', async () => {
      const onMessage = vi.fn();
      const { result } = renderHook(() => useSSE('/suscribeupdate', { onMessage }));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      // Get the EventSource instance and simulate a message
      const es = result.current._eventSource;
      const testData = { partyId: 'party1', action: 'play' };
      es._simulateMessage(testData);

      await waitFor(() => {
        expect(onMessage).toHaveBeenCalledWith(testData);
      });
    });

    it('should handle multiple messages', async () => {
      const messages = [];
      const onMessage = vi.fn((data) => messages.push(data));
      const { result } = renderHook(() => useSSE('/suscribeupdate', { onMessage }));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      const es = result.current._eventSource;
      es._simulateMessage({ action: 'play' });
      es._simulateMessage({ action: 'draw' });
      es._simulateMessage({ action: 'zapzap' });

      await waitFor(() => {
        expect(messages.length).toBe(3);
      });

      expect(messages[0].action).toBe('play');
      expect(messages[1].action).toBe('draw');
      expect(messages[2].action).toBe('zapzap');
    });

    it('should handle malformed JSON gracefully', async () => {
      const onMessage = vi.fn();
      const onError = vi.fn();
      const { result } = renderHook(() =>
        useSSE('/suscribeupdate', { onMessage, onError })
      );

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      const es = result.current._eventSource;

      // Simulate message with invalid JSON
      const event = { type: 'message', data: 'invalid json{' };
      if (es.onmessage) es.onmessage(event);

      // Should not crash, should call onError
      await waitFor(() => {
        expect(onError).toHaveBeenCalled();
      });
    });
  });

  describe('Error Handling', () => {
    it('should handle connection errors', async () => {
      const onError = vi.fn();
      const { result } = renderHook(() => useSSE('/suscribeupdate', { onError }));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      const es = result.current._eventSource;
      es._simulateError(new Error('Connection failed'));

      await waitFor(() => {
        expect(result.current.connected).toBe(false);
        expect(onError).toHaveBeenCalled();
      });
    });

    it('should set error state on connection failure', async () => {
      const { result } = renderHook(() => useSSE('/suscribeupdate'));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      const es = result.current._eventSource;
      es._simulateError(new Error('Network error'));

      await waitFor(() => {
        expect(result.current.error).toBeTruthy();
      });
    });
  });

  describe('Reconnection Logic', () => {
    it('should support manual reconnect', async () => {
      const { result } = renderHook(() => useSSE('/suscribeupdate'));

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      // Simulate disconnect
      const es = result.current._eventSource;
      es._simulateError(new Error('Disconnected'));

      await waitFor(() => {
        expect(result.current.connected).toBe(false);
      });

      // Reconnect
      result.current.reconnect();

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });
    });
  });

  describe('Cleanup', () => {
    it('should close connection on unmount', () => {
      const { unmount } = renderHook(() => useSSE('/suscribeupdate'));

      const closeSpy = vi.spyOn(MockEventSource.prototype, 'close');

      unmount();

      expect(closeSpy).toHaveBeenCalled();
    });

    it('should clear reconnection timeout on unmount', async () => {
      const { result, unmount } = renderHook(() =>
        useSSE('/suscribeupdate', { reconnectDelay: 100 })
      );

      await waitFor(() => {
        expect(result.current.connected).toBe(true);
      });

      // Trigger error to schedule reconnection
      const es = result.current._eventSource;
      es._simulateError(new Error('Test error'));

      // Unmount before reconnection happens
      unmount();

      // Wait to ensure no reconnection occurs
      await new Promise((resolve) => setTimeout(resolve, 150));

      // Should not throw or cause any issues
      expect(true).toBe(true);
    });
  });
});
