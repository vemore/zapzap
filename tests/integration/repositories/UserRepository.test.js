/**
 * Integration tests for UserRepository
 */

const fs = require('fs');
const { DatabaseConnection } = require('../../../src/infrastructure/database/sqlite/connection');
const UserRepository = require('../../../src/infrastructure/database/sqlite/repositories/UserRepository');
const User = require('../../../src/domain/entities/User');

describe('UserRepository Integration', () => {
    let dbConnection;
    let userRepository;
    const testDbPath = './data/test-user-repo.db';

    beforeAll(async () => {
        // Clean up any existing test database
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }

        dbConnection = new DatabaseConnection(testDbPath);
        await dbConnection.initialize();
        userRepository = new UserRepository(dbConnection);
    });

    afterAll(async () => {
        if (dbConnection) {
            await dbConnection.close();
        }

        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
    });

    afterEach(async () => {
        // Clean up test data after each test
        await dbConnection.run('DELETE FROM users');
    });

    describe('save() and findById()', () => {
        it('should save and retrieve user', async () => {
            const user = await User.create('testuser', 'password123');

            await userRepository.save(user);

            const retrieved = await userRepository.findById(user.id);

            expect(retrieved).not.toBeNull();
            expect(retrieved.id).toBe(user.id);
            expect(retrieved.username).toBe('testuser');
            expect(retrieved.passwordHash).toBe(user.passwordHash);
        });

        it('should update existing user', async () => {
            const user = await User.create('originaluser', 'password123');
            await userRepository.save(user);

            user.updateUsername('updateduser');
            await userRepository.save(user);

            const retrieved = await userRepository.findById(user.id);

            expect(retrieved.username).toBe('updateduser');
        });

        it('should return null for non-existent user', async () => {
            const retrieved = await userRepository.findById('nonexistent-id');

            expect(retrieved).toBeNull();
        });
    });

    describe('findByUsername()', () => {
        it('should find user by username', async () => {
            const user = await User.create('findme', 'password123');
            await userRepository.save(user);

            const retrieved = await userRepository.findByUsername('findme');

            expect(retrieved).not.toBeNull();
            expect(retrieved.id).toBe(user.id);
            expect(retrieved.username).toBe('findme');
        });

        it('should return null for non-existent username', async () => {
            const retrieved = await userRepository.findByUsername('nonexistent');

            expect(retrieved).toBeNull();
        });
    });

    describe('existsByUsername()', () => {
        it('should return true for existing username', async () => {
            const user = await User.create('existinguser', 'password123');
            await userRepository.save(user);

            const exists = await userRepository.existsByUsername('existinguser');

            expect(exists).toBe(true);
        });

        it('should return false for non-existent username', async () => {
            const exists = await userRepository.existsByUsername('nonexistent');

            expect(exists).toBe(false);
        });
    });

    describe('delete()', () => {
        it('should delete user', async () => {
            const user = await User.create('deleteuser', 'password123');
            await userRepository.save(user);

            const deleted = await userRepository.delete(user.id);

            expect(deleted).toBe(true);

            const retrieved = await userRepository.findById(user.id);
            expect(retrieved).toBeNull();
        });

        it('should return false when deleting non-existent user', async () => {
            const deleted = await userRepository.delete('nonexistent-id');

            expect(deleted).toBe(false);
        });
    });

    describe('findAll()', () => {
        it('should retrieve all users', async () => {
            const user1 = await User.create('user1', 'password123');
            const user2 = await User.create('user2', 'password123');
            const user3 = await User.create('user3', 'password123');

            await userRepository.save(user1);
            await userRepository.save(user2);
            await userRepository.save(user3);

            const users = await userRepository.findAll();

            expect(users).toHaveLength(3);
            expect(users.map(u => u.username)).toContain('user1');
            expect(users.map(u => u.username)).toContain('user2');
            expect(users.map(u => u.username)).toContain('user3');
        });

        it('should respect limit and offset', async () => {
            for (let i = 0; i < 10; i++) {
                const user = await User.create(`user${i}`, 'password123');
                await userRepository.save(user);
            }

            const users = await userRepository.findAll(5, 0);
            expect(users).toHaveLength(5);

            const nextUsers = await userRepository.findAll(5, 5);
            expect(nextUsers).toHaveLength(5);

            // Ensure no overlap
            const userIds = users.map(u => u.id);
            const nextUserIds = nextUsers.map(u => u.id);
            expect(userIds.some(id => nextUserIds.includes(id))).toBe(false);
        });

        it('should return empty array when no users', async () => {
            const users = await userRepository.findAll();

            expect(users).toEqual([]);
        });
    });

    describe('count()', () => {
        it('should count users', async () => {
            expect(await userRepository.count()).toBe(0);

            const user1 = await User.create('user1', 'password123');
            await userRepository.save(user1);
            expect(await userRepository.count()).toBe(1);

            const user2 = await User.create('user2', 'password123');
            await userRepository.save(user2);
            expect(await userRepository.count()).toBe(2);
        });
    });

    describe('Error handling', () => {
        it('should handle unique constraint violations', async () => {
            const user1 = await User.create('duplicateuser', 'password123');
            await userRepository.save(user1);

            // Try to create another user with same username
            const user2 = await User.create('duplicateuser', 'password456');
            user2._id = user2.id + '-different'; // Different ID

            await expect(userRepository.save(user2)).rejects.toThrow();
        });
    });
});
