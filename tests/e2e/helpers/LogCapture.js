/**
 * LogCapture Helper
 * Captures Winston logs during E2E tests for validation
 */

const winston = require('winston');
const Transport = require('winston-transport');

/**
 * Custom Winston transport that captures logs in memory
 */
class MemoryTransport extends Transport {
    constructor(opts) {
        super(opts);
        this.logs = [];
    }

    log(info, callback) {
        setImmediate(() => {
            this.emit('logged', info);
        });

        // Store log entry
        this.logs.push({
            level: info.level,
            message: info.message,
            timestamp: info.timestamp || new Date().toISOString(),
            ...info
        });

        callback();
    }

    clear() {
        this.logs = [];
    }

    getLogs() {
        return this.logs;
    }
}

/**
 * LogCapture - Manages log capture during tests
 */
class LogCapture {
    constructor(logger) {
        this.logger = logger;
        this.transport = null;
        this.isCapturing = false;
    }

    /**
     * Start capturing logs
     */
    start() {
        if (this.isCapturing) {
            return;
        }

        // Create memory transport
        this.transport = new MemoryTransport({
            level: 'debug', // Capture all levels
            format: winston.format.combine(
                winston.format.timestamp(),
                winston.format.json()
            )
        });

        // Add transport to logger
        this.logger.add(this.transport);
        this.isCapturing = true;
    }

    /**
     * Stop capturing logs
     */
    stop() {
        if (!this.isCapturing || !this.transport) {
            return;
        }

        // Remove transport from logger
        this.logger.remove(this.transport);
        this.isCapturing = false;
    }

    /**
     * Clear captured logs
     */
    clear() {
        if (this.transport) {
            this.transport.clear();
        }
    }

    /**
     * Get all captured logs
     * @returns {Array} All log entries
     */
    getLogs() {
        if (!this.transport) {
            return [];
        }
        return this.transport.getLogs();
    }

    /**
     * Get logs by level
     * @param {string} level - Log level (error, warn, info, debug)
     * @returns {Array} Filtered log entries
     */
    getLogsByLevel(level) {
        return this.getLogs().filter(log => log.level === level);
    }

    /**
     * Get error logs
     * @returns {Array} Error log entries
     */
    getErrors() {
        return this.getLogsByLevel('error');
    }

    /**
     * Get warning logs
     * @returns {Array} Warning log entries
     */
    getWarnings() {
        return this.getLogsByLevel('warn');
    }

    /**
     * Get info logs
     * @returns {Array} Info log entries
     */
    getInfo() {
        return this.getLogsByLevel('info');
    }

    /**
     * Get debug logs
     * @returns {Array} Debug log entries
     */
    getDebug() {
        return this.getLogsByLevel('debug');
    }

    /**
     * Filter logs by message pattern
     * @param {string|RegExp} pattern - Pattern to match
     * @returns {Array} Matching log entries
     */
    findByMessage(pattern) {
        const regex = pattern instanceof RegExp ? pattern : new RegExp(pattern, 'i');
        return this.getLogs().filter(log => regex.test(log.message));
    }

    /**
     * Filter logs by metadata field
     * @param {string} field - Metadata field name
     * @param {*} value - Expected value
     * @returns {Array} Matching log entries
     */
    findByMetadata(field, value) {
        return this.getLogs().filter(log => log[field] === value);
    }

    /**
     * Check if specific log message exists
     * @param {string|RegExp} pattern - Pattern to match
     * @returns {boolean} True if log found
     */
    hasLog(pattern) {
        return this.findByMessage(pattern).length > 0;
    }

    /**
     * Check if error log exists
     * @param {string|RegExp} pattern - Pattern to match (optional)
     * @returns {boolean} True if error found
     */
    hasError(pattern = null) {
        const errors = this.getErrors();
        if (!pattern) {
            return errors.length > 0;
        }
        const regex = pattern instanceof RegExp ? pattern : new RegExp(pattern, 'i');
        return errors.some(log => regex.test(log.message));
    }

    /**
     * Get log count
     * @returns {number} Total number of logs
     */
    count() {
        return this.getLogs().length;
    }

    /**
     * Get log count by level
     * @param {string} level - Log level
     * @returns {number} Count of logs at specified level
     */
    countByLevel(level) {
        return this.getLogsByLevel(level).length;
    }

    /**
     * Get formatted logs for display
     * @returns {string} Formatted log output
     */
    format() {
        return this.getLogs()
            .map(log => {
                const level = log.level.toUpperCase().padEnd(5);
                const timestamp = log.timestamp || '';
                const message = log.message || '';
                const meta = Object.keys(log)
                    .filter(k => !['level', 'message', 'timestamp', 'Symbol(level)', 'Symbol(message)'].includes(k))
                    .map(k => `${k}=${JSON.stringify(log[k])}`)
                    .join(' ');

                return `[${timestamp}] ${level} ${message}${meta ? ' ' + meta : ''}`;
            })
            .join('\n');
    }

    /**
     * Print logs to console (useful for debugging)
     */
    print() {
        console.log('\n=== Captured Logs ===');
        console.log(this.format());
        console.log('=====================\n');
    }

    /**
     * Get statistics about captured logs
     * @returns {Object} Log statistics
     */
    getStats() {
        const logs = this.getLogs();
        return {
            total: logs.length,
            error: this.countByLevel('error'),
            warn: this.countByLevel('warn'),
            info: this.countByLevel('info'),
            debug: this.countByLevel('debug'),
            startTime: logs[0]?.timestamp,
            endTime: logs[logs.length - 1]?.timestamp
        };
    }

    /**
     * Assert no errors were logged
     * @throws {Error} If errors were found
     */
    assertNoErrors() {
        const errors = this.getErrors();
        if (errors.length > 0) {
            throw new Error(`Expected no errors, but found ${errors.length}:\n${
                errors.map(e => `  - ${e.message}`).join('\n')
            }`);
        }
    }

    /**
     * Assert specific log exists
     * @param {string|RegExp} pattern - Pattern to match
     * @throws {Error} If log not found
     */
    assertHasLog(pattern) {
        if (!this.hasLog(pattern)) {
            throw new Error(`Expected to find log matching: ${pattern}\nActual logs:\n${this.format()}`);
        }
    }

    /**
     * Assert error log exists
     * @param {string|RegExp} pattern - Pattern to match
     * @throws {Error} If error log not found
     */
    assertHasError(pattern) {
        if (!this.hasError(pattern)) {
            const errors = this.getErrors();
            throw new Error(`Expected to find error log matching: ${pattern}\nActual errors:\n${
                errors.map(e => e.message).join('\n')
            }`);
        }
    }

    /**
     * Get logs in time range
     * @param {Date|string} start - Start time
     * @param {Date|string} end - End time
     * @returns {Array} Logs in time range
     */
    getLogsInTimeRange(start, end) {
        const startTime = new Date(start).getTime();
        const endTime = new Date(end).getTime();

        return this.getLogs().filter(log => {
            const logTime = new Date(log.timestamp).getTime();
            return logTime >= startTime && logTime <= endTime;
        });
    }
}

/**
 * Create LogCapture instance
 * @param {winston.Logger} logger - Winston logger instance
 * @returns {LogCapture} LogCapture instance
 */
function createLogCapture(logger) {
    return new LogCapture(logger);
}

module.exports = {
    LogCapture,
    createLogCapture,
    MemoryTransport
};
