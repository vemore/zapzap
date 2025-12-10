/**
 * Database Connection
 * SQLite database connection wrapper
 */

const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const logger = require('../../../../logger');

class DatabaseConnection {
    constructor(dbPath = null) {
        this.dbPath = dbPath || path.join(__dirname, '../../../../data/zapzap.db');
        this.db = null;
    }

    /**
     * Initialize database connection and schema
     * @returns {Promise<void>}
     */
    async initialize() {
        try {
            // Ensure data directory exists
            const dataDir = path.dirname(this.dbPath);
            if (!fs.existsSync(dataDir)) {
                fs.mkdirSync(dataDir, { recursive: true });
            }

            // Create database connection
            this.db = await this.connect();

            // Enable foreign keys
            await this.run('PRAGMA foreign_keys = ON');

            // Create schema
            await this.createSchema();

            logger.info('Database initialized', { dbPath: this.dbPath });
        } catch (error) {
            logger.error('Database initialization failed', {
                error: error.message,
                stack: error.stack
            });
            throw error;
        }
    }

    /**
     * Connect to database
     * @returns {Promise<sqlite3.Database>}
     */
    connect() {
        return new Promise((resolve, reject) => {
            const db = new sqlite3.Database(this.dbPath, (err) => {
                if (err) {
                    reject(err);
                } else {
                    resolve(db);
                }
            });
        });
    }

    /**
     * Create database schema
     * @returns {Promise<void>}
     */
    async createSchema() {
        const schema = `
            -- Users table
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                user_type TEXT NOT NULL DEFAULT 'human' CHECK(user_type IN ('human', 'bot')),
                bot_difficulty TEXT CHECK(bot_difficulty IN ('easy', 'medium', 'hard', 'hard_vince', 'ml', 'drl', 'llm')),
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );

            -- Parties table
            CREATE TABLE IF NOT EXISTS parties (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                owner_id TEXT NOT NULL,
                invite_code TEXT UNIQUE NOT NULL,
                visibility TEXT NOT NULL CHECK(visibility IN ('public', 'private')),
                status TEXT NOT NULL CHECK(status IN ('waiting', 'playing', 'finished')),
                settings_json TEXT NOT NULL,
                current_round_id TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
            );

            -- Party players table
            CREATE TABLE IF NOT EXISTS party_players (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                party_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                player_index INTEGER NOT NULL,
                joined_at INTEGER NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                UNIQUE(party_id, user_id),
                UNIQUE(party_id, player_index)
            );

            -- Rounds table
            CREATE TABLE IF NOT EXISTS rounds (
                id TEXT PRIMARY KEY,
                party_id TEXT NOT NULL,
                round_number INTEGER NOT NULL,
                status TEXT NOT NULL CHECK(status IN ('active', 'finished')),
                current_turn INTEGER NOT NULL,
                current_action TEXT NOT NULL CHECK(current_action IN ('draw', 'play', 'zapzap')),
                created_at INTEGER NOT NULL,
                finished_at INTEGER,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                UNIQUE(party_id, round_number)
            );

            -- Game state table
            CREATE TABLE IF NOT EXISTS game_state (
                party_id TEXT PRIMARY KEY,
                state_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE
            );

            -- Indexes for common queries
            CREATE INDEX IF NOT EXISTS idx_parties_owner ON parties(owner_id);
            CREATE INDEX IF NOT EXISTS idx_parties_status ON parties(status);
            CREATE INDEX IF NOT EXISTS idx_parties_visibility ON parties(visibility, status);
            CREATE INDEX IF NOT EXISTS idx_party_players_user ON party_players(user_id);
            CREATE INDEX IF NOT EXISTS idx_party_players_party ON party_players(party_id);
            CREATE INDEX IF NOT EXISTS idx_rounds_party ON rounds(party_id);
            CREATE INDEX IF NOT EXISTS idx_rounds_status ON rounds(party_id, status);

            -- Round scores table (archives scores at end of each round)
            CREATE TABLE IF NOT EXISTS round_scores (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                party_id TEXT NOT NULL,
                round_number INTEGER NOT NULL,
                user_id TEXT NOT NULL,
                player_index INTEGER NOT NULL,
                score_this_round INTEGER NOT NULL,
                total_score_after INTEGER NOT NULL,
                hand_points INTEGER NOT NULL,
                is_zapzap_caller INTEGER NOT NULL DEFAULT 0,
                zapzap_success INTEGER NOT NULL DEFAULT 0,
                was_counteracted INTEGER NOT NULL DEFAULT 0,
                hand_cards TEXT,
                is_lowest_hand INTEGER NOT NULL DEFAULT 0,
                is_eliminated INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                UNIQUE(party_id, round_number, user_id)
            );

            CREATE INDEX IF NOT EXISTS idx_round_scores_party ON round_scores(party_id);
            CREATE INDEX IF NOT EXISTS idx_round_scores_user ON round_scores(user_id);
            CREATE INDEX IF NOT EXISTS idx_round_scores_party_round ON round_scores(party_id, round_number);

            -- Game results table (stores final game results)
            CREATE TABLE IF NOT EXISTS game_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                party_id TEXT UNIQUE NOT NULL,
                winner_user_id TEXT NOT NULL,
                winner_final_score INTEGER NOT NULL,
                total_rounds INTEGER NOT NULL,
                was_golden_score INTEGER NOT NULL DEFAULT 0,
                player_count INTEGER NOT NULL,
                finished_at INTEGER NOT NULL,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                FOREIGN KEY (winner_user_id) REFERENCES users(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_game_results_winner ON game_results(winner_user_id);
            CREATE INDEX IF NOT EXISTS idx_game_results_finished ON game_results(finished_at);

            -- Player game results table (per-player results for each finished game)
            CREATE TABLE IF NOT EXISTS player_game_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                party_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                final_score INTEGER NOT NULL,
                finish_position INTEGER NOT NULL,
                rounds_played INTEGER NOT NULL,
                total_zapzap_calls INTEGER NOT NULL DEFAULT 0,
                successful_zapzaps INTEGER NOT NULL DEFAULT 0,
                failed_zapzaps INTEGER NOT NULL DEFAULT 0,
                lowest_hand_count INTEGER NOT NULL DEFAULT 0,
                is_winner INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL,
                FOREIGN KEY (party_id) REFERENCES parties(id) ON DELETE CASCADE,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
                UNIQUE(party_id, user_id)
            );

            CREATE INDEX IF NOT EXISTS idx_player_results_user ON player_game_results(user_id);
            CREATE INDEX IF NOT EXISTS idx_player_results_party ON player_game_results(party_id);
        `;

        await this.exec(schema);

        // Run migrations for admin features
        await this.runMigrations();
    }

    /**
     * Run database migrations for new features
     * @returns {Promise<void>}
     */
    async runMigrations() {
        // Migration: Add admin-related columns to users table
        const adminMigrations = [
            {
                name: 'add_is_admin_column',
                sql: 'ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0'
            },
            {
                name: 'add_last_login_at_column',
                sql: 'ALTER TABLE users ADD COLUMN last_login_at INTEGER'
            },
            {
                name: 'add_total_play_time_seconds_column',
                sql: 'ALTER TABLE users ADD COLUMN total_play_time_seconds INTEGER NOT NULL DEFAULT 0'
            }
        ];

        for (const migration of adminMigrations) {
            try {
                await this.run(migration.sql);
                logger.debug(`Migration applied: ${migration.name}`);
            } catch (error) {
                // Ignore "duplicate column name" errors (column already exists)
                if (!error.message.includes('duplicate column name')) {
                    throw error;
                }
            }
        }
    }

    /**
     * Execute SQL statement
     * @param {string} sql - SQL statement
     * @returns {Promise<void>}
     */
    exec(sql) {
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
     * Run SQL statement with parameters
     * @param {string} sql - SQL statement
     * @param {Array} params - Parameters
     * @returns {Promise<{lastID: number, changes: number}>}
     */
    run(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.run(sql, params, function(err) {
                if (err) {
                    reject(err);
                } else {
                    resolve({ lastID: this.lastID, changes: this.changes });
                }
            });
        });
    }

    /**
     * Get single row from query
     * @param {string} sql - SQL query
     * @param {Array} params - Parameters
     * @returns {Promise<Object|null>}
     */
    get(sql, params = []) {
        return new Promise((resolve, reject) => {
            this.db.get(sql, params, (err, row) => {
                if (err) {
                    reject(err);
                } else {
                    resolve(row || null);
                }
            });
        });
    }

    /**
     * Get all rows from query
     * @param {string} sql - SQL query
     * @param {Array} params - Parameters
     * @returns {Promise<Array>}
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
    async beginTransaction() {
        await this.run('BEGIN TRANSACTION');
    }

    /**
     * Commit transaction
     * @returns {Promise<void>}
     */
    async commit() {
        await this.run('COMMIT');
    }

    /**
     * Rollback transaction
     * @returns {Promise<void>}
     */
    async rollback() {
        await this.run('ROLLBACK');
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
                    reject(err);
                } else {
                    this.db = null;
                    logger.info('Database connection closed');
                    resolve();
                }
            });
        });
    }
}

module.exports = DatabaseConnection;
