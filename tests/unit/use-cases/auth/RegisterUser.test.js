/**
 * Unit tests for RegisterUser use case
 */

const RegisterUser = require('../../../../src/use-cases/auth/RegisterUser');
const User = require('../../../../src/domain/entities/User');

describe('RegisterUser Use Case', () => {
    let registerUser;
    let mockUserRepository;
    let mockJwtService;

    beforeEach(() => {
        // Mock repository
        mockUserRepository = {
            existsByUsername: jest.fn(),
            save: jest.fn(),
            findByUsername: jest.fn()
        };

        // Mock JWT service
        mockJwtService = {
            sign: jest.fn()
        };

        registerUser = new RegisterUser(mockUserRepository, mockJwtService);
    });

    describe('Successful registration', () => {
        it('should register a new user and return token', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);
            mockUserRepository.save.mockResolvedValue(true);
            mockJwtService.sign.mockReturnValue('mock-jwt-token');

            const result = await registerUser.execute({
                username: 'newuser',
                password: 'password123'
            });

            expect(result.success).toBe(true);
            expect(result.user).toBeDefined();
            expect(result.user.username).toBe('newuser');
            expect(result.user.passwordHash).toBeUndefined(); // Public object shouldn't have hash
            expect(result.token).toBe('mock-jwt-token');

            expect(mockUserRepository.existsByUsername).toHaveBeenCalledWith('newuser');
            expect(mockUserRepository.save).toHaveBeenCalled();
            expect(mockJwtService.sign).toHaveBeenCalledWith({
                userId: expect.any(String),
                username: 'newuser'
            });
        });

        it('should trim username before processing', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);
            mockUserRepository.save.mockResolvedValue(true);
            mockJwtService.sign.mockReturnValue('token');

            await registerUser.execute({
                username: '  spaceuser  ',
                password: 'password123'
            });

            expect(mockUserRepository.existsByUsername).toHaveBeenCalledWith('spaceuser');
        });
    });

    describe('Validation errors', () => {
        it('should reject missing username', async () => {
            await expect(
                registerUser.execute({
                    password: 'password123'
                })
            ).rejects.toThrow('Username is required');
        });

        it('should reject empty username', async () => {
            await expect(
                registerUser.execute({
                    username: '',
                    password: 'password123'
                })
            ).rejects.toThrow();
        });

        it('should reject missing password', async () => {
            await expect(
                registerUser.execute({
                    username: 'testuser'
                })
            ).rejects.toThrow('Password is required');
        });

        it('should reject empty password', async () => {
            await expect(
                registerUser.execute({
                    username: 'testuser',
                    password: ''
                })
            ).rejects.toThrow();
        });
    });

    describe('Business rule violations', () => {
        it('should reject duplicate username', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(true);

            await expect(
                registerUser.execute({
                    username: 'existinguser',
                    password: 'password123'
                })
            ).rejects.toThrow('Username already exists');

            expect(mockUserRepository.save).not.toHaveBeenCalled();
            expect(mockJwtService.sign).not.toHaveBeenCalled();
        });

        it('should reject short username', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);

            await expect(
                registerUser.execute({
                    username: 'ab',
                    password: 'password123'
                })
            ).rejects.toThrow();
        });

        it('should reject short password', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);

            await expect(
                registerUser.execute({
                    username: 'testuser',
                    password: '12345'
                })
            ).rejects.toThrow('Password must be at least 6 characters');
        });

        it('should reject invalid username characters', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);

            await expect(
                registerUser.execute({
                    username: 'test@user',
                    password: 'password123'
                })
            ).rejects.toThrow();
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors gracefully', async () => {
            mockUserRepository.existsByUsername.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                registerUser.execute({
                    username: 'testuser',
                    password: 'password123'
                })
            ).rejects.toThrow('Database error');
        });

        it('should handle save errors', async () => {
            mockUserRepository.existsByUsername.mockResolvedValue(false);
            mockUserRepository.save.mockRejectedValue(
                new Error('Save failed')
            );

            await expect(
                registerUser.execute({
                    username: 'testuser',
                    password: 'password123'
                })
            ).rejects.toThrow('Save failed');
        });
    });
});
