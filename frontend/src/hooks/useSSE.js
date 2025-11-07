import { useState, useEffect, useRef, useCallback } from 'react';

/**
 * useSSE hook - manages Server-Sent Events connection
 * @param {string} url - SSE endpoint URL
 * @param {Object} options - Configuration options
 * @param {Function} options.onMessage - Message handler
 * @param {Function} options.onError - Error handler
 * @param {Function} options.onOpen - Connection open handler
 * @param {number} options.reconnectDelay - Delay before reconnection (ms)
 * @returns {Object} - { connected, error, reconnect, _eventSource }
 */
function useSSE(url, options = {}) {
  const {
    onMessage,
    onError,
    onOpen,
    reconnectDelay = 3000,
  } = options;

  const [connected, setConnected] = useState(false);
  const [error, setError] = useState(null);
  const eventSourceRef = useRef(null);
  const reconnectTimeoutRef = useRef(null);
  const mountedRef = useRef(true);

  // Create connection
  const connect = useCallback(() => {
    if (!url || !mountedRef.current) return;

    // Close existing connection
    if (eventSourceRef.current) {
      eventSourceRef.current.close();
    }

    try {
      const eventSource = new EventSource(url);
      eventSourceRef.current = eventSource;

      // Connection opened
      eventSource.onopen = (event) => {
        if (!mountedRef.current) return;
        setConnected(true);
        setError(null);
        if (onOpen) onOpen(event);
      };

      // Message received
      eventSource.onmessage = (event) => {
        if (!mountedRef.current) return;

        try {
          const data = JSON.parse(event.data);
          if (onMessage) onMessage(data);
        } catch (err) {
          console.error('Failed to parse SSE message:', err);
          setError(err);
          if (onError) onError(err);
        }
      };

      // Error occurred
      eventSource.onerror = (event) => {
        if (!mountedRef.current) return;

        setConnected(false);
        const errorObj = new Error('SSE connection error');
        setError(errorObj);
        if (onError) onError(errorObj);

        // Close connection
        eventSource.close();

        // Schedule reconnection
        if (mountedRef.current) {
          reconnectTimeoutRef.current = setTimeout(() => {
            if (mountedRef.current) {
              connect();
            }
          }, reconnectDelay);
        }
      };

      // Custom event listener for 'event' type
      eventSource.addEventListener('event', (event) => {
        if (!mountedRef.current) return;

        try {
          const data = JSON.parse(event.data);
          if (onMessage) onMessage(data);
        } catch (err) {
          console.error('Failed to parse event:', err);
          setError(err);
          if (onError) onError(err);
        }
      });
    } catch (err) {
      console.error('Failed to create EventSource:', err);
      setError(err);
      if (onError) onError(err);
    }
  }, [url, onMessage, onError, onOpen, reconnectDelay]);

  // Manual reconnect
  const reconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    connect();
  }, [connect]);

  // Connect on mount or URL change
  useEffect(() => {
    mountedRef.current = true;
    connect();

    return () => {
      mountedRef.current = false;

      // Clear reconnection timeout
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current);
      }

      // Close EventSource
      if (eventSourceRef.current) {
        eventSourceRef.current.close();
        eventSourceRef.current = null;
      }
    };
  }, [connect]);

  return {
    connected,
    error,
    reconnect,
    _eventSource: eventSourceRef.current, // For testing
  };
}

export default useSSE;
