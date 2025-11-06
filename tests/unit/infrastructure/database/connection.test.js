/**
 * Unit tests for DatabaseConnection
 * Tests database operations, transactions, and connection management
 */

const fs = require('fs');
const path = require('path');
const { DatabaseConnection } = require('../../../../src/infrastructure/database/sqlite/connection');

describe('DatabaseConnection', () => {
    let dbConnection;
    const testDbPath = './data/test-zapzap.db';

    beforeEach(async () => {
        // Clean up any existing test database
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }

        dbConnection = new DatabaseConnection(testDbPath);
    });

    afterEach(async () => {
        // Close connection and clean up
        if (dbConnection && dbConnection.db) {
            await dbConnection.close();
        }

        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
    });

    describe('Constructor', () => {
        it('should create instance with provided path', () => {
            expect(dbConnection.dbPath).toBe(testDbPath);
            expect(dbConnection.db).toBeNull();
        });

        it('should use default path when not provided', () => {
            const defaultConnection = new DatabaseConnection();
            expect(defaultConnection.dbPath).toBe('./data/zapzap.db');
        });
    });

    describe('initialize()', () => {
        it('should initialize database and run migrations', async () => {
            await dbConnection.initialize();

            expect(dbConnection.db).not.toBeNull();
            expect(fs.existsSync(testDbPath)).toBe(true);

            // Verify schema_version table exists
            const version = await dbConnection.get(
                'SELECT version FROM schema_version ORDER BY version DESC LIMIT 1'
            );

            expect(version).toBeDefined();
            expect(version.version).toBe(1);
        });

        it('should create data directory if not exists', async () => {
            const nestedPath = './data/nested/test/db.db';
            const nestedConnection = new DatabaseConnection(nestedPath);

            await nestedConnection.initialize();

            expect(fs.existsSync(nestedPath)).toBe(true);

            // Cleanup
            await nestedConnection.close();
            fs.unlinkSync(nestedPath);
            fs.rmdirSync('./data/nested/test', { recursive: true });
        });

        it('should enable foreign keys', async () => {
            await dbConnection.initialize();

            const result = await dbConnection.get('PRAGMA foreign_keys');

            expect(result.foreign_keys).toBe(1);
        });
    });

    describe('run()', () => {
        beforeEach(async () => {
            await dbConnection.initialize();
        });

        it('should execute INSERT and return lastID', async () => {
            const result = await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-1', 'testuser', 'hash123']
            );

            expect(result.lastID).toBeDefined();
            expect(result.changes).toBe(1);
        });

        it('should execute UPDATE and return changes', async () => {
            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-2', 'updateuser', 'hash456']
            );

            // Update
            const result = await dbConnection.run(
                'UPDATE users SET username = ? WHERE id = ?',
                ['updateduser', 'user-2']
            );

            expect(result.changes).toBe(1);
        });

        it('should execute DELETE and return changes', async () => {
            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-3', 'deleteuser', 'hash789']
            );

            // Delete
            const result = await dbConnection.run(
                'DELETE FROM users WHERE id = ?',
                ['user-3']
            );

            expect(result.changes).toBe(1);
        });

        it('should reject on SQL error', async () => {
            await expect(
                dbConnection.run('INSERT INTO nonexistent_table (col) VALUES (?)', ['val'])
            ).rejects.toThrow();
        });
    });

    describe('get()', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert test data
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-get-1', 'getuser', 'gethash']
            );
        });

        it('should return single row', async () => {
            const user = await dbConnection.get(
                'SELECT * FROM users WHERE id = ?',
                ['user-get-1']
            );

            expect(user).toBeDefined();
            expect(user.id).toBe('user-get-1');
            expect(user.username).toBe('getuser');
            expect(user.password_hash).toBe('gethash');
        });

        it('should return undefined for no match', async () => {
            const user = await dbConnection.get(
                'SELECT * FROM users WHERE id = ?',
                ['nonexistent']
            );

            expect(user).toBeUndefined();
        });

        it('should reject on SQL error', async () => {
            await expect(
                dbConnection.get('SELECT * FROM nonexistent_table')
            ).rejects.toThrow();
        });
    });

    describe('all()', () => {
        beforeEach(async () => {
            await dbConnection.initialize();

            // Insert multiple test records
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-all-1', 'alice', 'hash1']
            );
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-all-2', 'bob', 'hash2']
            );
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-all-3', 'charlie', 'hash3']
            );
        });

        it('should return all matching rows', async () => {
            const users = await dbConnection.all('SELECT * FROM users ORDER BY username');

            expect(users).toHaveLength(3);
            expect(users[0].username).toBe('alice');
            expect(users[1].username).toBe('bob');
            expect(users[2].username).toBe('charlie');
        });

        it('should return empty array for no matches', async () => {
            const users = await dbConnection.all(
                'SELECT * FROM users WHERE username = ?',
                ['nonexistent']
            );

            expect(users).toEqual([]);
        });

        it('should support parameterized queries', async () => {
            const users = await dbConnection.all(
                'SELECT * FROM users WHERE username IN (?, ?)',
                ['alice', 'charlie']
            );

            expect(users).toHaveLength(2);
            expect(users[0].username).toBe('alice');
            expect(users[1].username).toBe('charlie');
        });

        it('should reject on SQL error', async () => {
            await expect(
                dbConnection.all('SELECT * FROM nonexistent_table')
            ).rejects.toThrow();
        });
    });

    describe('Transaction management', () => {
        beforeEach(async () => {
            await dbConnection.initialize();
        });

        describe('beginTransaction() / commit()', () => {
            it('should commit transaction successfully', async () => {
                await dbConnection.beginTransaction();

                await dbConnection.run(
                    'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                    ['user-tx-1', 'txuser', 'txhash']
                );

                await dbConnection.commit();

                // Verify data persisted
                const user = await dbConnection.get(
                    'SELECT * FROM users WHERE id = ?',
                    ['user-tx-1']
                );

                expect(user).toBeDefined();
                expect(user.username).toBe('txuser');
            });
        });

        describe('beginTransaction() / rollback()', () => {
            it('should rollback transaction on failure', async () => {
                await dbConnection.beginTransaction();

                await dbConnection.run(
                    'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                    ['user-rollback', 'rollbackuser', 'rollbackhash']
                );

                await dbConnection.rollback();

                // Verify data not persisted
                const user = await dbConnection.get(
                    'SELECT * FROM users WHERE id = ?',
                    ['user-rollback']
                );

                expect(user).toBeUndefined();
            });
        });

        describe('transaction()', () => {
            it('should commit successful transaction', async () => {
                const result = await dbConnection.transaction(async () => {
                    await dbConnection.run(
                        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                        ['user-fn-1', 'fnuser1', 'fnhash1']
                    );

                    await dbConnection.run(
                        'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                        ['user-fn-2', 'fnuser2', 'fnhash2']
                    );

                    return 'success';
                });

                expect(result).toBe('success');

                // Verify both records persisted
                const users = await dbConnection.all(
                    'SELECT * FROM users WHERE id IN (?, ?)',
                    ['user-fn-1', 'user-fn-2']
                );

                expect(users).toHaveLength(2);
            });

            it('should rollback failed transaction', async () => {
                await expect(
                    dbConnection.transaction(async () => {
                        await dbConnection.run(
                            'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                            ['user-fail-1', 'failuser1', 'failhash1']
                        );

                        // This will fail (duplicate username)
                        await dbConnection.run(
                            'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                            ['user-fail-2', 'failuser1', 'failhash2']
                        );
                    })
                ).rejects.toThrow();

                // Verify no records persisted
                const users = await dbConnection.all(
                    'SELECT * FROM users WHERE id IN (?, ?)',
                    ['user-fail-1', 'user-fail-2']
                );

                expect(users).toHaveLength(0);
            });

            it('should return function result', async () => {
                const result = await dbConnection.transaction(async () => {
                    return { status: 'completed', count: 42 };
                });

                expect(result).toEqual({ status: 'completed', count: 42 });
            });
        });
    });

    describe('close()', () => {
        it('should close database connection', async () => {
            await dbConnection.initialize();
            await dbConnection.close();

            expect(dbConnection.db).toBeNull();
        });

        it('should resolve if no connection exists', async () => {
            await expect(dbConnection.close()).resolves.toBeUndefined();
        });
    });

    describe('getDb()', () => {
        it('should return database instance when initialized', async () => {
            await dbConnection.initialize();

            const db = dbConnection.getDb();

            expect(db).not.toBeNull();
            expect(db).toBe(dbConnection.db);
        });

        it('should throw error when not initialized', () => {
            expect(() => {
                dbConnection.getDb();
            }).toThrow('Database not initialized');
        });
    });

    describe('Foreign key constraints', () => {
        beforeEach(async () => {
            await dbConnection.initialize();
        });

        it('should enforce foreign key constraints', async () => {
            // Try to insert party with non-existent owner
            await expect(
                dbConnection.run(
                    `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                     VALUES (?, ?, ?, ?, ?, ?, ?)`,
                    ['party-1', 'Test Party', 'nonexistent-user', 'CODE123', 'public', 'waiting', '{}']
                )
            ).rejects.toThrow();
        });

        it('should cascade delete', async () => {
            // Insert user
            await dbConnection.run(
                'INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)',
                ['user-cascade', 'cascadeuser', 'cascadehash']
            );

            // Insert party owned by user
            await dbConnection.run(
                `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json)
                 VALUES (?, ?, ?, ?, ?, ?, ?)`,
                ['party-cascade', 'Cascade Party', 'user-cascade', 'CASC123', 'public', 'waiting', '{}']
            );

            // Delete user
            await dbConnection.run('DELETE FROM users WHERE id = ?', ['user-cascade']);

            // Verify party was cascade deleted
            const party = await dbConnection.get(
                'SELECT * FROM parties WHERE id = ?',
                ['party-cascade']
            );

            expect(party).toBeUndefined();
        });
    });
});
