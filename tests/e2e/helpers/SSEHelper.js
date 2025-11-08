/**
 * SSEHelper
 * Handles Server-Sent Events (SSE) for E2E tests
 */

const { EventSource } = require('eventsource');

class SSEHelper {
    constructor(baseURL) {
        this.baseURL = baseURL;
        this.connections = new Map(); // connectionId -> EventSource
        this.events = new Map(); // connectionId -> Array of events
        this.listeners = new Map(); // connectionId -> Array of listener functions
    }

    /**
     * Connect to SSE endpoint
     * @param {string} connectionId - Unique ID for this connection
     * @returns {Promise<EventSource>} EventSource instance when connected
     */
    async connect(connectionId = 'default') {
        if (this.connections.has(connectionId)) {
            throw new Error(`Connection '${connectionId}' already exists`);
        }

        const url = `${this.baseURL}/suscribeupdate`;

        return new Promise((resolve, reject) => {
            const eventSource = new EventSource(url);

            // Initialize event storage
            this.events.set(connectionId, []);
            this.listeners.set(connectionId, []);

            // Connection opened
            eventSource.onopen = () => {
                this.connections.set(connectionId, eventSource);
                resolve(eventSource);
            };

            // Handle events
            eventSource.addEventListener('event', (e) => {
                try {
                    const data = JSON.parse(e.data);

                    // Store event
                    this.events.get(connectionId).push({
                        type: 'event',
                        data,
                        timestamp: new Date()
                    });

                    // Call registered listeners
                    const listeners = this.listeners.get(connectionId) || [];
                    listeners.forEach(listener => {
                        try {
                            listener(data);
                        } catch (error) {
                            console.error('SSE listener error:', error);
                        }
                    });
                } catch (error) {
                    console.error('Failed to parse SSE data:', error, e.data);
                }
            });

            // Error handling
            eventSource.onerror = (error) => {
                // Don't reject on errors, they're common with SSE
                console.error('SSE error:', error);
            };

            // Timeout if not connected in 5 seconds
            setTimeout(() => {
                if (!this.connections.has(connectionId)) {
                    eventSource.close();
                    reject(new Error('SSE connection timeout'));
                }
            }, 5000);
        });
    }

    /**
     * Disconnect from SSE
     * @param {string} connectionId - Connection ID
     */
    disconnect(connectionId = 'default') {
        const eventSource = this.connections.get(connectionId);

        if (eventSource) {
            eventSource.close();
            this.connections.delete(connectionId);
        }

        // Keep events and listeners for post-disconnect inspection
    }

    /**
     * Disconnect all connections
     */
    disconnectAll() {
        for (const connectionId of this.connections.keys()) {
            this.disconnect(connectionId);
        }
    }

    /**
     * Register event listener
     * @param {string} connectionId - Connection ID
     * @param {Function} callback - Callback function (data) => void
     */
    onEvent(connectionId, callback) {
        const listeners = this.listeners.get(connectionId) || [];
        listeners.push(callback);
        this.listeners.set(connectionId, listeners);
    }

    /**
     * Get all captured events
     * @param {string} connectionId - Connection ID
     * @returns {Array} Array of events
     */
    getEvents(connectionId = 'default') {
        return this.events.get(connectionId) || [];
    }

    /**
     * Get events count
     * @param {string} connectionId - Connection ID
     * @returns {number} Number of events
     */
    getEventCount(connectionId = 'default') {
        return this.getEvents(connectionId).length;
    }

    /**
     * Clear captured events
     * @param {string} connectionId - Connection ID
     */
    clearEvents(connectionId = 'default') {
        this.events.set(connectionId, []);
    }

    /**
     * Clear all events for all connections
     */
    clearAllEvents() {
        for (const connectionId of this.events.keys()) {
            this.events.set(connectionId, []);
        }
    }

    /**
     * Filter events by party ID
     * @param {string} connectionId - Connection ID
     * @param {string} partyId - Party ID
     * @returns {Array} Filtered events
     */
    getEventsByParty(connectionId, partyId) {
        return this.getEvents(connectionId).filter(event => event.data.partyId === partyId);
    }

    /**
     * Filter events by action
     * @param {string} connectionId - Connection ID
     * @param {string} action - Action name (e.g., 'play', 'draw', 'zapzap')
     * @returns {Array} Filtered events
     */
    getEventsByAction(connectionId, action) {
        return this.getEvents(connectionId).filter(event => event.data.action === action);
    }

    /**
     * Filter events by user ID
     * @param {string} connectionId - Connection ID
     * @param {string} userId - User ID
     * @returns {Array} Filtered events
     */
    getEventsByUser(connectionId, userId) {
        return this.getEvents(connectionId).filter(event => event.data.userId === userId);
    }

    /**
     * Wait for specific event
     * @param {string} connectionId - Connection ID
     * @param {Function} predicate - Function to test event (event) => boolean
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Object>} Event data when found
     */
    async waitForEvent(connectionId, predicate, timeout = 5000) {
        const startTime = Date.now();

        // Check existing events first
        const existingEvents = this.getEvents(connectionId);
        const existing = existingEvents.find(event => predicate(event.data));
        if (existing) {
            return existing.data;
        }

        // Wait for new events
        return new Promise((resolve, reject) => {
            const listener = (data) => {
                if (predicate(data)) {
                    cleanup();
                    resolve(data);
                }
            };

            const timeoutId = setTimeout(() => {
                cleanup();
                reject(new Error(`Timeout waiting for SSE event after ${timeout}ms`));
            }, timeout);

            const cleanup = () => {
                clearTimeout(timeoutId);
                const listeners = this.listeners.get(connectionId) || [];
                const index = listeners.indexOf(listener);
                if (index > -1) {
                    listeners.splice(index, 1);
                }
            };

            this.onEvent(connectionId, listener);
        });
    }

    /**
     * Wait for party event
     * @param {string} connectionId - Connection ID
     * @param {string} partyId - Party ID
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Object>} Event data
     */
    async waitForPartyEvent(connectionId, partyId, timeout = 5000) {
        return await this.waitForEvent(
            connectionId,
            (data) => data.partyId === partyId,
            timeout
        );
    }

    /**
     * Wait for action event
     * @param {string} connectionId - Connection ID
     * @param {string} action - Action name
     * @param {number} timeout - Timeout in ms (default: 5000)
     * @returns {Promise<Object>} Event data
     */
    async waitForActionEvent(connectionId, action, timeout = 5000) {
        return await this.waitForEvent(
            connectionId,
            (data) => data.action === action,
            timeout
        );
    }

    /**
     * Wait for bot action event
     * @param {string} connectionId - Connection ID
     * @param {number} timeout - Timeout in ms (default: 10000)
     * @returns {Promise<Object>} Event data
     */
    async waitForBotAction(connectionId, timeout = 10000) {
        return await this.waitForEvent(
            connectionId,
            (data) => data.userId && data.userId.includes('Bot'),
            timeout
        );
    }

    /**
     * Wait for multiple events
     * @param {string} connectionId - Connection ID
     * @param {number} count - Number of events to wait for
     * @param {Function} predicate - Filter function (optional)
     * @param {number} timeout - Timeout in ms (default: 10000)
     * @returns {Promise<Array>} Array of event data
     */
    async waitForEvents(connectionId, count, predicate = null, timeout = 10000) {
        const startTime = Date.now();
        const matchedEvents = [];

        while (Date.now() - startTime < timeout) {
            const events = this.getEvents(connectionId);
            const filtered = predicate
                ? events.filter(event => predicate(event.data))
                : events;

            if (filtered.length >= count) {
                return filtered.slice(0, count).map(e => e.data);
            }

            // Wait 100ms before checking again
            await new Promise(resolve => setTimeout(resolve, 100));
        }

        throw new Error(`Timeout waiting for ${count} events after ${timeout}ms. Got ${matchedEvents.length}.`);
    }

    /**
     * Get last event
     * @param {string} connectionId - Connection ID
     * @returns {Object|null} Last event or null
     */
    getLastEvent(connectionId = 'default') {
        const events = this.getEvents(connectionId);
        return events.length > 0 ? events[events.length - 1].data : null;
    }

    /**
     * Check if event exists
     * @param {string} connectionId - Connection ID
     * @param {Function} predicate - Test function
     * @returns {boolean} True if event found
     */
    hasEvent(connectionId, predicate) {
        return this.getEvents(connectionId).some(event => predicate(event.data));
    }

    /**
     * Get events in time range
     * @param {string} connectionId - Connection ID
     * @param {Date} start - Start time
     * @param {Date} end - End time
     * @returns {Array} Events in time range
     */
    getEventsInTimeRange(connectionId, start, end) {
        return this.getEvents(connectionId).filter(event => {
            return event.timestamp >= start && event.timestamp <= end;
        });
    }

    /**
     * Get event statistics
     * @param {string} connectionId - Connection ID
     * @returns {Object} Event statistics
     */
    getStats(connectionId = 'default') {
        const events = this.getEvents(connectionId);

        const actions = {};
        const parties = {};

        events.forEach(event => {
            const action = event.data.action;
            const partyId = event.data.partyId;

            if (action) {
                actions[action] = (actions[action] || 0) + 1;
            }

            if (partyId) {
                parties[partyId] = (parties[partyId] || 0) + 1;
            }
        });

        return {
            total: events.length,
            actions,
            parties,
            firstEvent: events[0]?.timestamp,
            lastEvent: events[events.length - 1]?.timestamp
        };
    }

    /**
     * Format events for display
     * @param {string} connectionId - Connection ID
     * @returns {string} Formatted event list
     */
    format(connectionId = 'default') {
        return this.getEvents(connectionId)
            .map((event, index) => {
                const timestamp = event.timestamp.toISOString();
                const data = JSON.stringify(event.data);
                return `[${index}] ${timestamp} - ${data}`;
            })
            .join('\n');
    }

    /**
     * Print events to console (debugging)
     * @param {string} connectionId - Connection ID
     */
    print(connectionId = 'default') {
        console.log(`\n=== SSE Events (${connectionId}) ===`);
        console.log(this.format(connectionId));
        console.log('==========================\n');
    }

    /**
     * Cleanup all resources
     */
    cleanup() {
        this.disconnectAll();
        this.events.clear();
        this.listeners.clear();
    }

    /**
     * Check if connected
     * @param {string} connectionId - Connection ID
     * @returns {boolean} True if connected
     */
    isConnected(connectionId = 'default') {
        const eventSource = this.connections.get(connectionId);
        return eventSource && eventSource.readyState === EventSource.OPEN;
    }

    /**
     * Get active connection count
     * @returns {number} Number of active connections
     */
    getConnectionCount() {
        return this.connections.size;
    }
}

/**
 * Create SSEHelper instance
 * @param {string} baseURL - Base URL for SSE endpoint
 * @returns {SSEHelper} SSEHelper instance
 */
function createSSEHelper(baseURL) {
    return new SSEHelper(baseURL);
}

module.exports = {
    SSEHelper,
    createSSEHelper
};
