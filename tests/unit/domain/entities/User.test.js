/**
 * Unit tests for User Entity
 */

const User = require('../../../../src/domain/entities/User');

describe('User Entity', () => {
    describe('Constructor', () => {
        it('should create user with valid properties', () => {
            const user = new User({
                id: 'user-123',
                username: 'testuser',
                passwordHash: 'hashed_password',
                createdAt: 1234567890,
                updatedAt: 1234567890
            });

            expect(user.id).toBe('user-123');
            expect(user.username).toBe('testuser');
            expect(user.passwordHash).toBe('hashed_password');
            expect(user.createdAt).toBe(1234567890);
            expect(user.updatedAt).toBe(1234567890);
        });

        it('should generate ID if not provided', () => {
            const user = new User({
                username: 'testuser',
                passwordHash: 'hashed_password'
            });

            expect(user.id).toBeDefined();
            expect(typeof user.id).toBe('string');
        });

        it('should generate timestamps if not provided', () => {
            const before = Math.floor(Date.now() / 1000);

            const user = new User({
                username: 'testuser',
                passwordHash: 'hashed_password'
            });

            const after = Math.floor(Date.now() / 1000);

            expect(user.createdAt).toBeGreaterThanOrEqual(before);
            expect(user.createdAt).toBeLessThanOrEqual(after);
            expect(user.updatedAt).toBeGreaterThanOrEqual(before);
            expect(user.updatedAt).toBeLessThanOrEqual(after);
        });

        it('should throw error for missing username', () => {
            expect(() => {
                new User({
                    passwordHash: 'hashed_password'
                });
            }).toThrow('Username is required');
        });

        it('should throw error for short username', () => {
            expect(() => {
                new User({
                    username: 'ab',
                    passwordHash: 'hashed_password'
                });
            }).toThrow('Username must be at least 3 characters');
        });

        it('should throw error for long username', () => {
            expect(() => {
                new User({
                    username: 'a'.repeat(51),
                    passwordHash: 'hashed_password'
                });
            }).toThrow('Username must not exceed 50 characters');
        });

        it('should throw error for invalid username characters', () => {
            expect(() => {
                new User({
                    username: 'test@user',
                    passwordHash: 'hashed_password'
                });
            }).toThrow('Username can only contain alphanumeric');
        });

        it('should throw error for missing password hash', () => {
            expect(() => {
                new User({
                    username: 'testuser'
                });
            }).toThrow('Password hash is required');
        });
    });

    describe('create()', () => {
        it('should create user with plain password', async () => {
            const user = await User.create('newuser', 'password123');

            expect(user.username).toBe('newuser');
            expect(user.passwordHash).toBeDefined();
            expect(user.passwordHash).not.toBe('password123');
        });

        it('should hash password with bcrypt', async () => {
            const user = await User.create('hashtest', 'mypassword');

            // Bcrypt hashes start with $2a$, $2b$, or $2y$
            expect(user.passwordHash).toMatch(/^\$2[aby]\$/);
        });

        it('should throw error for short password', async () => {
            await expect(
                User.create('testuser', '12345')
            ).rejects.toThrow('Password must be at least 6 characters');
        });

        it('should throw error for missing password', async () => {
            await expect(
                User.create('testuser', '')
            ).rejects.toThrow('Password is required');
        });

        it('should trim username', async () => {
            const user = await User.create('  spaceuser  ', 'password123');

            expect(user.username).toBe('spaceuser');
        });
    });

    describe('verifyPassword()', () => {
        it('should verify correct password', async () => {
            const user = await User.create('testuser', 'correct_password');

            const isValid = await user.verifyPassword('correct_password');

            expect(isValid).toBe(true);
        });

        it('should reject incorrect password', async () => {
            const user = await User.create('testuser', 'correct_password');

            const isValid = await user.verifyPassword('wrong_password');

            expect(isValid).toBe(false);
        });
    });

    describe('updateUsername()', () => {
        let user;

        beforeEach(async () => {
            user = await User.create('originaluser', 'password123');
        });

        it('should update username', (done) => {
            const oldUpdatedAt = user.updatedAt;

            // Wait a moment to ensure different timestamp
            setTimeout(() => {
                user.updateUsername('newusername');

                expect(user.username).toBe('newusername');
                expect(user.updatedAt).toBeGreaterThanOrEqual(oldUpdatedAt);
                done();
            }, 1100);
        }, 2000);

        it('should trim new username', () => {
            user.updateUsername('  trimmed  ');

            expect(user.username).toBe('trimmed');
        });

        it('should throw error for invalid username', () => {
            expect(() => {
                user.updateUsername('ab');
            }).toThrow('Username must be between 3 and 50 characters');
        });
    });

    describe('updatePassword()', () => {
        let user;

        beforeEach(async () => {
            user = await User.create('testuser', 'old_password');
        });

        it('should update password', async () => {
            const oldHash = user.passwordHash;

            await user.updatePassword('new_password');

            expect(user.passwordHash).not.toBe(oldHash);

            // Verify new password works
            const isValid = await user.verifyPassword('new_password');
            expect(isValid).toBe(true);

            // Verify old password doesn't work
            const isOldValid = await user.verifyPassword('old_password');
            expect(isOldValid).toBe(false);
        });

        it('should throw error for short password', async () => {
            await expect(
                user.updatePassword('12345')
            ).rejects.toThrow('Password must be at least 6 characters');
        });
    });

    describe('toObject()', () => {
        it('should convert to plain object', async () => {
            const user = await User.create('testuser', 'password123');

            const obj = user.toObject();

            expect(obj.id).toBe(user.id);
            expect(obj.username).toBe('testuser');
            expect(obj.passwordHash).toBe(user.passwordHash);
            expect(obj.createdAt).toBe(user.createdAt);
            expect(obj.updatedAt).toBe(user.updatedAt);
        });
    });

    describe('toPublicObject()', () => {
        it('should convert to public object without password', async () => {
            const user = await User.create('testuser', 'password123');

            const obj = user.toPublicObject();

            expect(obj.id).toBe(user.id);
            expect(obj.username).toBe('testuser');
            expect(obj.passwordHash).toBeUndefined();
            expect(obj.createdAt).toBe(user.createdAt);
            expect(obj.updatedAt).toBe(user.updatedAt);
        });
    });

    describe('fromDatabase()', () => {
        it('should reconstruct from database record', () => {
            const record = {
                id: 'user-db-123',
                username: 'dbuser',
                password_hash: 'hashed',
                created_at: 1234567890,
                updated_at: 1234567890
            };

            const user = User.fromDatabase(record);

            expect(user.id).toBe('user-db-123');
            expect(user.username).toBe('dbuser');
            expect(user.passwordHash).toBe('hashed');
            expect(user.createdAt).toBe(1234567890);
            expect(user.updatedAt).toBe(1234567890);
        });
    });
});
