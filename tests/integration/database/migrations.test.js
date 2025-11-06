/**
 * Integration tests for database migrations
 * Tests complete schema creation and table structure
 */

const fs = require('fs');
const path = require('path');
const { DatabaseConnection } = require('../../../src/infrastructure/database/sqlite/connection');

describe('Database Migrations Integration', () => {
    let dbConnection;
    const testDbPath = './data/test-migrations.db';

    beforeEach(async () => {
        // Clean up any existing test database
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }

        dbConnection = new DatabaseConnection(testDbPath);
    });

    afterEach(async () => {
        if (dbConnection && dbConnection.db) {
            await dbConnection.close();
        }

        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
    });

    describe('Schema creation', () => {
        it('should create all required tables', async () => {
            await dbConnection.initialize();

            // Get list of tables
            const tables = await dbConnection.all(
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            );

            const tableNames = tables.map(t => t.name);

            expect(tableNames).toContain('users');
            expect(tableNames).toContain('parties');
            expect(tableNames).toContain('party_players');
            expect(tableNames).toContain('rounds');
            expect(tableNames).toContain('game_state');
            expect(tableNames).toContain('schema_version');
        });

        it('should create all indexes', async () => {
            await dbConnection.initialize();

            // Get list of indexes
            const indexes = await dbConnection.all(
                "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            );

            const indexNames = indexes.map(i => i.name);

            // User indexes
            expect(indexNames).toContain('idx_users_username');
            expect(indexNames).toContain('idx_users_created_at');

            // Party indexes
            expect(indexNames).toContain('idx_parties_owner');
            expect(indexNames).toContain('idx_parties_invite_code');
            expect(indexNames).toContain('idx_parties_visibility_status');
            expect(indexNames).toContain('idx_parties_created_at');

            // Party players indexes
            expect(indexNames).toContain('idx_party_players_party');
            expect(indexNames).toContain('idx_party_players_user');
            expect(indexNames).toContain('idx_party_players_joined');

            // Round indexes
            expect(indexNames).toContain('idx_rounds_party');
            expect(indexNames).toContain('idx_rounds_status');
            expect(indexNames).toContain('idx_rounds_created');

            // Game state indexes
            expect(indexNames).toContain('idx_game_state_updated');
        });

        it('should create all triggers', async () => {
            await dbConnection.initialize();

            // Get list of triggers
            const triggers = await dbConnection.all(
                "SELECT name FROM sqlite_master WHERE type='trigger' ORDER BY name"
            );

            const triggerNames = triggers.map(t => t.name);

            expect(triggerNames).toContain('update_users_timestamp');
            expect(triggerNames).toContain('update_parties_timestamp');
            expect(triggerNames).toContain('update_game_state_timestamp');
        });
    });

    describe('Users table', () => {
        beforeEach(async () => {
            await dbConnection.initialize();
        });

        it('should have correct structure', async () => {
            const columns = await dbConnection.all('PRAGMA table_info(users)');

            const columnNames = columns.map(c => c.name);
            expect(columnNames).toContain('id');
            expect(columnNames).toContain('username');
            expect(columnNames).toContain('password_hash');
            expect(columnNames).toContain('created_at');
            expect(columnNames).toContain('updated_at');

            // Check primary key
            const pkColumn = columns.find(c => c.pk === 1);
            expect(pkColumn.name).toBe('id');
        });

        it('should enforce unique username', async () => {
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-1', 'duplicateuser', 'hash1']
            );

            await expect(
                dbConnection.run(
                    'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                    ['user-2', 'duplicateuser', 'hash2']
                )
            ).rejects.toThrow();
        });

        it('should auto-populate timestamps', async () => {
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-timestamp', 'timestampuser', 'hash']
            );

            const user = await dbConnection.get(
                'SELECT * FROM users WHERE id = ?',
                ['user-timestamp']
            );

            expect(user.created_at).toBeDefined();
            expect(user.updated_at).toBeDefined();
            expect(typeof user.created_at).toBe('number');
            expect(typeof user.updated_at).toBe('number');
        });

        it('should trigger updated_at on update', async () => {
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-update', 'updateuser', 'hash']
            );

            const userBefore = await dbConnection.get(
                'SELECT * FROM users WHERE id = ?',
                ['user-update']
            );

            // Wait a bit to ensure different timestamp
            await new Promise(resolve => setTimeout(resolve, 1000));

            await dbConnection.run(
                'UPDATE users SET username = ? WHERE id = ?',
                ['updateduser', 'user-update']
            );

            const userAfter = await dbConnection.get(
                'SELECT * FROM users WHERE id = ?',
                ['user-update']
            );

            expect(userAfter.updated_at).toBeGreaterThan(userBefore.updated_at);
        });
    });

    describe('Parties table', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert test user for foreign key
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['owner-1', 'owner', 'hash']
            );
        });

        it('should have correct structure', async () => {
            const columns = await dbConnection.all('PRAGMA table_info(parties)');

            const columnNames = columns.map(c => c.name);
            expect(columnNames).toContain('id');
            expect(columnNames).toContain('name');
            expect(columnNames).toContain('owner_id');
            expect(columnNames).toContain('invite_code');
            expect(columnNames).toContain('visibility');
            expect(columnNames).toContain('status');
            expect(columnNames).toContain('settings_json');
            expect(columnNames).toContain('created_at');
            expect(columnNames).toContain('updated_at');
        });

        it('should enforce unique invite_code', async () => {
            await dbConnection.run(
                `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                ['party-1', 'Party 1', 'owner-1', 'CODE123', 'public', 'waiting', '{}']
            );

            await expect(
                dbConnection.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    ['party-2', 'Party 2', 'owner-1', 'CODE123', 'public', 'waiting', '{}']
                )
            ).rejects.toThrow();
        });

        it('should enforce visibility check constraint', async () => {
            await expect(
                dbConnection.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    ['party-bad', 'Bad Party', 'owner-1', 'BADC123', 'invalid', 'waiting', '{}']
                )
            ).rejects.toThrow();
        });

        it('should enforce status check constraint', async () => {
            await expect(
                dbConnection.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    ['party-bad', 'Bad Party', 'owner-1', 'BADC123', 'public', 'invalid', '{}']
                )
            ).rejects.toThrow();
        });

        it('should enforce foreign key to users', async () => {
            await expect(
                dbConnection.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    ['party-orphan', 'Orphan Party', 'nonexistent', 'ORPH123', 'public', 'waiting', '{}']
                )
            ).rejects.toThrow();
        });
    });

    describe('Party_players table', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-pp-1', 'user1', 'hash1']
            );
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-pp-2', 'user2', 'hash2']
            );
            await dbConnection.run(
                `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                ['party-pp', 'Test Party', 'user-pp-1', 'PPCODE', 'public', 'waiting', '{}']
            );
        });

        it('should have correct structure', async () => {
            const columns = await dbConnection.all('PRAGMA table_info(party_players)');

            const columnNames = columns.map(c => c.name);
            expect(columnNames).toContain('id');
            expect(columnNames).toContain('party_id');
            expect(columnNames).toContain('user_id');
            expect(columnNames).toContain('player_index');
            expect(columnNames).toContain('joined_at');
        });

        it('should enforce unique (party_id, user_id)', async () => {
            await dbConnection.run(
                'INSERT INTO party_players (party_id, user_id, player_index) VALUES (?, ?, ?)',
                ['party-pp', 'user-pp-1', 0]
            );

            await expect(
                dbConnection.run(
                    'INSERT INTO party_players (party_id, user_id, player_index) VALUES (?, ?, ?)',
                    ['party-pp', 'user-pp-1', 1]
                )
            ).rejects.toThrow();
        });

        it('should enforce unique (party_id, player_index)', async () => {
            await dbConnection.run(
                'INSERT INTO party_players (party_id, user_id, player_index) VALUES (?, ?, ?)',
                ['party-pp', 'user-pp-1', 0]
            );

            await expect(
                dbConnection.run(
                    'INSERT INTO party_players (party_id, user_id, player_index) VALUES (?, ?, ?)',
                    ['party-pp', 'user-pp-2', 0]
                )
            ).rejects.toThrow();
        });

        it('should cascade delete when party deleted', async () => {
            await dbConnection.run(
                'INSERT INTO party_players (party_id, user_id, player_index) VALUES (?, ?, ?)',
                ['party-pp', 'user-pp-1', 0]
            );

            await dbConnection.run('DELETE FROM parties WHERE id = ?', ['party-pp']);

            const players = await dbConnection.all(
                'SELECT * FROM party_players WHERE party_id = ?',
                ['party-pp']
            );

            expect(players).toHaveLength(0);
        });
    });

    describe('Rounds table', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-round', 'rounduser', 'hash']
            );
            await dbConnection.run(
                `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                ['party-round', 'Round Party', 'user-round', 'RNDCODE', 'public', 'playing', '{}']
            );
        });

        it('should have correct structure', async () => {
            const columns = await dbConnection.all('PRAGMA table_info(rounds)');

            const columnNames = columns.map(c => c.name);
            expect(columnNames).toContain('id');
            expect(columnNames).toContain('party_id');
            expect(columnNames).toContain('round_number');
            expect(columnNames).toContain('status');
            expect(columnNames).toContain('current_turn');
            expect(columnNames).toContain('current_action');
            expect(columnNames).toContain('created_at');
            expect(columnNames).toContain('finished_at');
        });

        it('should enforce unique (party_id, round_number)', async () => {
            await dbConnection.run(
                `INSERT INTO rounds (id, party_id, round_number, status, current_action)
                 VALUES (?, ?, ?, ?, ?)`,
                ['round-1', 'party-round', 1, 'active', 'draw']
            );

            await expect(
                dbConnection.run(
                    `INSERT INTO rounds (id, party_id, round_number, status, current_action)
                     VALUES (?, ?, ?, ?, ?)`,
                    ['round-2', 'party-round', 1, 'active', 'draw']
                )
            ).rejects.toThrow();
        });

        it('should enforce status check constraint', async () => {
            await expect(
                dbConnection.run(
                    `INSERT INTO rounds (id, party_id, round_number, status, current_action)
                     VALUES (?, ?, ?, ?, ?)`,
                    ['round-bad', 'party-round', 2, 'invalid', 'draw']
                )
            ).rejects.toThrow();
        });

        it('should enforce current_action check constraint', async () => {
            await expect(
                dbConnection.run(
                    `INSERT INTO rounds (id, party_id, round_number, status, current_action)
                     VALUES (?, ?, ?, ?, ?)`,
                    ['round-bad', 'party-round', 2, 'active', 'invalid']
                )
            ).rejects.toThrow();
        });
    });

    describe('Game_state table', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-gs', 'gsuser', 'hash']
            );
            await dbConnection.run(
                `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                ['party-gs', 'GS Party', 'user-gs', 'GSCODE', 'public', 'playing', '{}']
            );
        });

        it('should have correct structure', async () => {
            const columns = await dbConnection.all('PRAGMA table_info(game_state)');

            const columnNames = columns.map(c => c.name);
            expect(columnNames).toContain('party_id');
            expect(columnNames).toContain('state_json');
            expect(columnNames).toContain('updated_at');

            // Check primary key
            const pkColumn = columns.find(c => c.pk === 1);
            expect(pkColumn.name).toBe('party_id');
        });

        it('should store JSON state', async () => {
            const gameState = {
                deck: [1, 2, 3, 4, 5],
                hands: { '0': [10, 11], '1': [12, 13] },
                scores: { '0': 5, '1': 8 }
            };

            await dbConnection.run(
                'INSERT INTO game_state (party_id, state_json) VALUES (?, ?)',
                ['party-gs', JSON.stringify(gameState)]
            );

            const row = await dbConnection.get(
                'SELECT * FROM game_state WHERE party_id = ?',
                ['party-gs']
            );

            const retrieved = JSON.parse(row.state_json);
            expect(retrieved).toEqual(gameState);
        });

        it('should trigger updated_at on update', async () => {
            await dbConnection.run(
                'INSERT INTO game_state (party_id, state_json) VALUES (?, ?)',
                ['party-gs', '{"initial": true}']
            );

            const stateBefore = await dbConnection.get(
                'SELECT * FROM game_state WHERE party_id = ?',
                ['party-gs']
            );

            // Wait to ensure different timestamp
            await new Promise(resolve => setTimeout(resolve, 1000));

            await dbConnection.run(
                'UPDATE game_state SET state_json = ? WHERE party_id = ?',
                ['{"updated": true}', 'party-gs']
            );

            const stateAfter = await dbConnection.get(
                'SELECT * FROM game_state WHERE party_id = ?',
                ['party-gs']
            );

            expect(stateAfter.updated_at).toBeGreaterThan(stateBefore.updated_at);
        });
    });

    describe('Schema version tracking', () => {
        it('should track schema version', async () => {
            await dbConnection.initialize();

            const version = await dbConnection.get(
                'SELECT version FROM schema_version ORDER BY version DESC LIMIT 1'
            );

            expect(version.version).toBe(1);
        });
    });
});
