#!/usr/bin/env node
/**
 * Migration script to add 'hard_vince' to bot_difficulty CHECK constraint
 * Run this script inside the Docker container to update the database schema
 *
 * Usage: node scripts/migrate-hard-vince.js
 */

const sqlite3 = require('better-sqlite3');
const path = require('path');

const dbPath = process.env.DB_PATH || path.join(__dirname, '..', 'data', 'zapzap.db');

console.log('Migrating database at:', dbPath);

try {
    const db = sqlite3(dbPath);

    // Start transaction
    db.exec('BEGIN TRANSACTION');

    console.log('1. Creating temporary users table with new constraint...');
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

    console.log('2. Copying data from old table to new table...');
    db.exec(`
        INSERT INTO users_new
        SELECT id, username, password_hash, user_type, bot_difficulty, is_admin,
               last_login_at, total_play_time_seconds, created_at, updated_at
        FROM users
    `);

    console.log('3. Dropping old table...');
    db.exec('DROP TABLE users');

    console.log('4. Renaming new table to users...');
    db.exec('ALTER TABLE users_new RENAME TO users');

    console.log('5. Recreating indexes...');
    db.exec('CREATE INDEX IF NOT EXISTS idx_users_username ON users(username)');
    db.exec('CREATE INDEX IF NOT EXISTS idx_users_user_type ON users(user_type)');

    // Commit transaction
    db.exec('COMMIT');

    console.log('Migration completed successfully!');

    // Verify the change
    const tableInfo = db.prepare("SELECT sql FROM sqlite_master WHERE type='table' AND name='users'").get();
    console.log('\nNew table schema:');
    console.log(tableInfo.sql);

    // Now create the VinceBot
    console.log('\n6. Creating VinceBot with hard_vince difficulty...');

    const bcrypt = require('bcryptjs');
    const crypto = require('crypto');

    const botId = crypto.randomUUID();
    const passwordHash = bcrypt.hashSync('bot-no-password-' + crypto.randomUUID(), 10);
    const now = Math.floor(Date.now() / 1000);

    const insertBot = db.prepare(`
        INSERT INTO users (id, username, password_hash, user_type, bot_difficulty, is_admin, created_at, updated_at)
        VALUES (?, ?, ?, 'bot', 'hard_vince', 0, ?, ?)
    `);

    try {
        insertBot.run(botId, 'VinceBot', passwordHash, now, now);
        console.log('VinceBot created successfully!');
    } catch (err) {
        if (err.message.includes('UNIQUE constraint')) {
            console.log('VinceBot already exists, skipping creation.');
        } else {
            throw err;
        }
    }

    db.close();
    console.log('\nDone! You can now use hard_vince bots.');

} catch (error) {
    console.error('Migration failed:', error.message);
    process.exit(1);
}
