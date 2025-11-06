/**
 * SQLite Database Connection Module
 * Handles database initialization, migrations, and connection management
 */

const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');
const path = require('path');
const logger = require('../../../../logger');

class DatabaseConnection {
    constructor(dbPath = './data/zapzap.db') {
        this.dbPath = dbPath;
        this.db = null;
    }

    /**
     * Initialize database connection and run migrations
     * @returns {Promise<void>}
     */
    async initialize() {
        try {
            // Ensure data directory exists
            const dataDir = path.dirname(this.dbPath);
            if (!fs.existsSync(dataDir)) {
                fs.mkdirSync(dataDir, { recursive: true });
                logger.info('Created data directory', { path: dataDir });
            }

            // Connect to database
            await this.connect();

            // Run migrations
            await this.runMigrations();

            logger.info('Database initialized successfully', {
                path: this.dbPath
            });
        } catch (error) {
            logger.error('Database initialization failed', { error: error.message });
            throw error;
        }
    }

    /**
     * Connect to SQLite database
     * @returns {Promise<sqlite3.Database>}
     */
    connect() {
        return new Promise((resolve, reject) => {
            this.db = new sqlite3.Database(this.dbPath, (err) => {
                if (err) {
                    logger.error('Database connection failed', { error: err.message });
                    reject(err);
                } else {
                    // Enable foreign keys
                    this.db.run('PRAGMA foreign_keys = ON', (err) => {
                        if (err) {
                            logger.error('Failed to enable foreign keys', { error: err.message });
                            reject(err);
                        } else {
                            logger.info('Database connected', { path: this.dbPath });
                            resolve(this.db);
                        }
                    });
                }
            });
        });
    }

    /**
     * Run database migrations
     * @returns {Promise<void>}
     */
    async runMigrations() {
        try {
            // Read schema file
            const schemaPath = path.join(__dirname, '../schemas/schema.sql');
            const schema = fs.readFileSync(schemaPath, 'utf8');

            // Execute schema
            await this.exec(schema);

            logger.info('Migrations completed successfully');
        } catch (error) {
            logger.error('Migration failed', { error: error.message });
            throw error;
        }
    }

    /**
     * Execute SQL statement
     * @param {string} sql - SQL statement
     * @param {Array} params - Parameters for prepared statement
     * @returns {Promise<void>}
     */
    exec(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.exec(sql, (err) => {
                if (err) {
                    reject(err);
                } else {
                    resolve();
                }
            });
        });
    }

    /**
     * Run SQL query (INSERT, UPDATE, DELETE)
     * @param {string} sql - SQL statement
     * @param {Array} params - Parameters for prepared statement
     * @returns {Promise<{lastID: number, changes: number}>}
     */
    run(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.run(sql, params, function(err) {
                if (err) {
                    reject(err);
                } else {
                    resolve({
                        lastID: this.lastID,
                        changes: this.changes
                    });
                }
            });
        });
    }

    /**
     * Get single row from query
     * @param {string} sql - SQL statement
     * @param {Array} params - Parameters for prepared statement
     * @returns {Promise<Object|undefined>}
     */
    get(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.get(sql, params, (err, row) => {
                if (err) {
                    reject(err);
                } else {
                    resolve(row);
                }
            });
        });
    }

    /**
     * Get all rows from query
     * @param {string} sql - SQL statement
     * @param {Array} params - Parameters for prepared statement
     * @returns {Promise<Array<Object>>}
     */
    all(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.all(sql, params, (err, rows) => {
                if (err) {
                    reject(err);
                } else {
                    resolve(rows || []);
                }
            });
        });
    }

    /**
     * Begin transaction
     * @returns {Promise<void>}
     */
    beginTransaction() {
        return this.run('BEGIN TRANSACTION');
    }

    /**
     * Commit transaction
     * @returns {Promise<void>}
     */
    commit() {
        return this.run('COMMIT');
    }

    /**
     * Rollback transaction
     * @returns {Promise<void>}
     */
    rollback() {
        return this.run('ROLLBACK');
    }

    /**
     * Execute function within transaction
     * @param {Function} fn - Async function to execute in transaction
     * @returns {Promise<*>} Result of function
     */
    async transaction(fn) {
        try {
            await this.beginTransaction();
            const result = await fn();
            await this.commit();
            return result;
        } catch (error) {
            await this.rollback();
            throw error;
        }
    }

    /**
     * Close database connection
     * @returns {Promise<void>}
     */
    close() {
        return new Promise((resolve, reject) => {
            if (!this.db) {
                resolve();
                return;
            }

            this.db.close((err) => {
                if (err) {
                    logger.error('Error closing database', { error: err.message });
                    reject(err);
                } else {
                    logger.info('Database connection closed');
                    this.db = null;
                    resolve();
                }
            });
        });
    }

    /**
     * Get database instance
     * @returns {sqlite3.Database}
     */
    getDb() {
        if (!this.db) {
            throw new Error('Database not initialized. Call initialize() first.');
        }
        return this.db;
    }
}

// Singleton instance
let instance = null;

/**
 * Get database connection instance
 * @param {string} dbPath - Optional database path (for testing)
 * @returns {DatabaseConnection}
 */
function getConnection(dbPath) {
    if (!instance || dbPath) {
        instance = new DatabaseConnection(dbPath);
    }
    return instance;
}

module.exports = {
    DatabaseConnection,
    getConnection
};
