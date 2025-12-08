#!/usr/bin/env node
/**
 * Docker Entrypoint Script
 * Runs database migrations before starting the application
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const dbPath = process.env.DB_PATH || '/app/data/zapzap.db';

console.log('=== ZapZap Docker Entrypoint ===');
console.log('Database path:', dbPath);
console.log('Node version:', process.version);
console.log('Current directory:', process.cwd());
console.log('Script location:', __dirname);

/**
 * Run database migrations
 */
async function runMigrations() {
    console.log('\n--- Running Database Migrations ---');

    // Check if database exists
    const dbExists = fs.existsSync(dbPath);
    console.log('Database exists:', dbExists);

    if (!dbExists) {
        console.log('Database does not exist yet. It will be created on first run.');
        return { migrationRan: false, reason: 'no_database' };
    }

    console.log('Loading better-sqlite3...');
    let sqlite3;
    try {
        sqlite3 = require('better-sqlite3');
        console.log('better-sqlite3 loaded successfully');
    } catch (err) {
        console.error('Failed to load better-sqlite3:', err.message);
        return { migrationRan: false, reason: 'sqlite_load_error', error: err.message };
    }

    let db;
    try {
        console.log('Opening database...');
        db = sqlite3(dbPath);
        console.log('Database opened successfully');

        // Check current schema for bot_difficulty constraint
        console.log('Checking users table schema...');
        const tableInfo = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'").get();

        if (!tableInfo) {
            console.log('Users table does not exist yet. Skipping migration.');
            db.close();
            return { migrationRan: false, reason: 'no_users_table' };
        }

        const currentSchema = tableInfo.sql;
        console.log('Current schema:', currentSchema.substring(0, 200) + '...');

        // Check if hard_vince is already in the constraint
        if (currentSchema.includes('hard_vince')) {
            console.log('Migration not needed: hard_vince already in schema.');
            db.close();
            return { migrationRan: false, reason: 'already_migrated' };
        }

        console.log('Migration needed: Adding hard_vince to bot_difficulty constraint...');

        // Start transaction
        console.log('Starting transaction...');
        db.exec('BEGIN TRANSACTION');

        try {
            // Create new table with updated constraint
            console.log('Creating new users table with updated constraint...');
            db.exec(`
                CREATE TABLE users_new (
                    id TEXT PRIMARY KEY,
                    username TEXT UNIQUE NOT NULL,
                    password_hash TEXT NOT NULL,
                    user_type TEXT DEFAULT 'human' CHECK(user_type IN ('human', 'bot')),
                    bot_difficulty TEXT CHECK(bot_difficulty IN ('easy', 'medium', 'hard', 'hard_vince')),
                    is_admin INTEGER DEFAULT 0,
                    last_login_at INTEGER,
                    total_play_time_seconds INTEGER DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                )
            `);
            console.log('New table created');

            // Copy data
            console.log('Copying data to new table...');
            db.exec(`
                INSERT INTO users_new
                SELECT id, username, password_hash, user_type, bot_difficulty, is_admin,
                       last_login_at, total_play_time_seconds, created_at, updated_at
                FROM users
            `);
            console.log('Data copied');

            // Drop old table and rename new one
            console.log('Dropping old table and renaming...');
            db.exec('DROP TABLE users');
            db.exec('ALTER TABLE users_new RENAME TO users');
            console.log('Table renamed');

            // Recreate indexes
            console.log('Recreating indexes...');
            db.exec('CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
            db.exec('CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type)');
            console.log('Indexes recreated');

            db.exec('COMMIT');
            console.log('Migration completed successfully!');

            db.close();
            return { migrationRan: true, reason: 'success' };

        } catch (migrationError) {
            console.error('Migration error during transaction:', migrationError.message);
            db.exec('ROLLBACK');
            db.close();
            throw migrationError;
        }

    } catch (error) {
        console.error('Migration error:', error.message);
        console.error('Stack:', error.stack);
        if (db) {
            try { db.close(); } catch (e) { /* ignore */ }
        }
        // Don't fail startup on migration errors - let the app handle it
        console.log('Continuing with startup despite migration error...');
        return { migrationRan: false, reason: 'error', error: error.message };
    }
}

/**
 * Create default bots if they don't exist
 */
async function ensureDefaultBots(migrationResult) {
    console.log('\n--- Ensuring Default Bots ---');
    console.log('Migration result:', JSON.stringify(migrationResult));

    if (!fs.existsSync(dbPath)) {
        console.log('Database does not exist. Skipping bot creation.');
        return;
    }

    let sqlite3, bcrypt, crypto;
    try {
        sqlite3 = require('better-sqlite3');
        bcrypt = require('bcryptjs');
        crypto = require('crypto');
    } catch (err) {
        console.error('Failed to load dependencies for bot creation:', err.message);
        return;
    }

    let db;
    try {
        db = sqlite3(dbPath);

        // First check if schema supports hard_vince
        const tableInfo = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'").get();
        if (!tableInfo || !tableInfo.sql.includes('hard_vince')) {
            console.log('Schema does not support hard_vince yet. Skipping VinceBot creation.');
            db.close();
            return;
        }

        // Check if VinceBot exists
        console.log('Checking if VinceBot exists...');
        const vinceBot = db.prepare("SELECT id FROM users WHERE username = 'VinceBot'").get();

        if (!vinceBot) {
            console.log('Creating VinceBot (hard_vince difficulty)...');

            const botId = crypto.randomUUID();
            const passwordHash = bcrypt.hashSync('bot-no-password-' + crypto.randomUUID(), 10);
            const now = Math.floor(Date.now() / 1000);

            try {
                db.prepare(`
                    INSERT INTO users (id, username, password_hash, user_type, bot_difficulty, is_admin, created_at, updated_at)
                    VALUES (?, ?, ?, 'bot', 'hard_vince', 0, ?, ?)
                `).run(botId, 'VinceBot', passwordHash, now, now);

                console.log('VinceBot created successfully!');
            } catch (err) {
                if (err.message.includes('UNIQUE constraint')) {
                    console.log('VinceBot already exists (race condition).');
                } else {
                    console.error('Failed to create VinceBot:', err.message);
                }
            }
        } else {
            console.log('VinceBot already exists.');
        }

        db.close();
    } catch (error) {
        console.error('Error ensuring default bots:', error.message);
        if (db) {
            try { db.close(); } catch (e) { /* ignore */ }
        }
    }
}

/**
 * Start the main application
 */
function startApp() {
    console.log('\n--- Starting ZapZap Application ---');

    const app = spawn('node', ['app.js'], {
        stdio: 'inherit',
        env: process.env
    });

    app.on('error', (err) => {
        console.error('Failed to start application:', err);
        process.exit(1);
    });

    app.on('exit', (code) => {
        console.log('Application exited with code:', code);
        process.exit(code || 0);
    });

    // Forward signals to child process
    process.on('SIGTERM', () => {
        console.log('Received SIGTERM, forwarding to app...');
        app.kill('SIGTERM');
    });
    process.on('SIGINT', () => {
        console.log('Received SIGINT, forwarding to app...');
        app.kill('SIGINT');
    });
}

/**
 * Main entrypoint
 */
async function main() {
    console.log('\n========================================');
    console.log('ZapZap Docker Entrypoint Starting...');
    console.log('Time:', new Date().toISOString());
    console.log('========================================\n');

    try {
        const migrationResult = await runMigrations();
        await ensureDefaultBots(migrationResult);
        startApp();
    } catch (error) {
        console.error('Entrypoint error:', error);
        console.error('Stack:', error.stack);
        process.exit(1);
    }
}

main();
