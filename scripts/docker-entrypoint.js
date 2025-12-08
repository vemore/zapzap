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

/**
 * Run database migrations
 */
async function runMigrations() {
    // Check if database exists
    if (!fs.existsSync(dbPath)) {
        console.log('Database does not exist yet. It will be created on first run.');
        return;
    }

    console.log('Running database migrations...');

    try {
        const sqlite3 = require('better-sqlite3');
        const db = sqlite3(dbPath);

        // Check current schema for bot_difficulty constraint
        const tableInfo = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'").get();

        if (!tableInfo) {
            console.log('Users table does not exist yet. Skipping migration.');
            db.close();
            return;
        }

        const currentSchema = tableInfo.sql;
        console.log('Current users table schema found.');

        // Check if hard_vince is already in the constraint
        if (currentSchema.includes('hard_vince')) {
            console.log('Migration not needed: hard_vince already in schema.');
            db.close();
            return;
        }

        console.log('Migration needed: Adding hard_vince to bot_difficulty constraint...');

        // Start transaction
        db.exec('BEGIN TRANSACTION');

        try {
            // Create new table with updated constraint
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

            // Copy data
            db.exec(`
                INSERT INTO users_new
                SELECT id, username, password_hash, user_type, bot_difficulty, is_admin,
                       last_login_at, total_play_time_seconds, created_at, updated_at
                FROM users
            `);

            // Drop old table and rename new one
            db.exec('DROP TABLE users');
            db.exec('ALTER TABLE users_new RENAME TO users');

            // Recreate indexes
            db.exec('CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
            db.exec('CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type)');

            db.exec('COMMIT');
            console.log('Migration completed successfully!');

        } catch (migrationError) {
            db.exec('ROLLBACK');
            throw migrationError;
        }

        db.close();

    } catch (error) {
        console.error('Migration error:', error.message);
        // Don't fail startup on migration errors - let the app handle it
        console.log('Continuing with startup...');
    }
}

/**
 * Create default bots if they don't exist
 */
async function ensureDefaultBots() {
    if (!fs.existsSync(dbPath)) {
        return;
    }

    try {
        const sqlite3 = require('better-sqlite3');
        const bcrypt = require('bcryptjs');
        const crypto = require('crypto');
        const db = sqlite3(dbPath);

        // Check if VinceBot exists
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
                if (!err.message.includes('UNIQUE constraint')) {
                    console.error('Failed to create VinceBot:', err.message);
                }
            }
        } else {
            console.log('VinceBot already exists.');
        }

        db.close();
    } catch (error) {
        console.error('Error ensuring default bots:', error.message);
    }
}

/**
 * Start the main application
 */
function startApp() {
    console.log('Starting ZapZap application...');

    const app = spawn('node', ['app.js'], {
        stdio: 'inherit',
        env: process.env
    });

    app.on('error', (err) => {
        console.error('Failed to start application:', err);
        process.exit(1);
    });

    app.on('exit', (code) => {
        process.exit(code || 0);
    });

    // Forward signals to child process
    process.on('SIGTERM', () => app.kill('SIGTERM'));
    process.on('SIGINT', () => app.kill('SIGINT'));
}

/**
 * Main entrypoint
 */
async function main() {
    try {
        await runMigrations();
        await ensureDefaultBots();
        startApp();
    } catch (error) {
        console.error('Entrypoint error:', error);
        process.exit(1);
    }
}

main();
