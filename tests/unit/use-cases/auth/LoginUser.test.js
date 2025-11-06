/**
 * Unit tests for LoginUser use case
 */

const LoginUser = require('../../../../src/use-cases/auth/LoginUser');
const User = require('../../../../src/domain/entities/User');

describe('LoginUser Use Case', () => {
    let loginUser;
    let mockUserRepository;
    let mockJwtService;
    let mockUser;

    beforeEach(async () => {
        // Create a real user for testing
        mockUser = await User.create('testuser', 'password123');

        // Mock repository
        mockUserRepository = {
            findByUsername: jest.fn()
        };

        // Mock JWT service
        mockJwtService = {
            sign: jest.fn()
        };

        loginUser = new LoginUser(mockUserRepository, mockJwtService);
    });

    describe('Successful login', () => {
        it('should authenticate user and return token', async () => {
            mockUserRepository.findByUsername.mockResolvedValue(mockUser);
            mockJwtService.sign.mockReturnValue('mock-jwt-token');

            const result = await loginUser.execute({
                username: 'testuser',
                password: 'password123'
            });

            expect(result.success).toBe(true);
            expect(result.user).toBeDefined();
            expect(result.user.username).toBe('testuser');
            expect(result.user.passwordHash).toBeUndefined();
            expect(result.token).toBe('mock-jwt-token');

            expect(mockUserRepository.findByUsername).toHaveBeenCalledWith('testuser');
            expect(mockJwtService.sign).toHaveBeenCalledWith({
                userId: mockUser.id,
                username: 'testuser'
            });
        });

        it('should trim username before processing', async () => {
            mockUserRepository.findByUsername.mockResolvedValue(mockUser);
            mockJwtService.sign.mockReturnValue('token');

            await loginUser.execute({
                username: '  testuser  ',
                password: 'password123'
            });

            expect(mockUserRepository.findByUsername).toHaveBeenCalledWith('testuser');
        });
    });

    describe('Validation errors', () => {
        it('should reject missing username', async () => {
            await expect(
                loginUser.execute({
                    password: 'password123'
                })
            ).rejects.toThrow('Username is required');
        });

        it('should reject empty username', async () => {
            await expect(
                loginUser.execute({
                    username: '',
                    password: 'password123'
                })
            ).rejects.toThrow();
        });

        it('should reject missing password', async () => {
            await expect(
                loginUser.execute({
                    username: 'testuser'
                })
            ).rejects.toThrow('Password is required');
        });

        it('should reject empty password', async () => {
            await expect(
                loginUser.execute({
                    username: 'testuser',
                    password: ''
                })
            ).rejects.toThrow();
        });
    });

    describe('Authentication failures', () => {
        it('should reject non-existent user', async () => {
            mockUserRepository.findByUsername.mockResolvedValue(null);

            await expect(
                loginUser.execute({
                    username: 'nonexistent',
                    password: 'password123'
                })
            ).rejects.toThrow('Invalid username or password');

            expect(mockJwtService.sign).not.toHaveBeenCalled();
        });

        it('should reject incorrect password', async () => {
            mockUserRepository.findByUsername.mockResolvedValue(mockUser);

            await expect(
                loginUser.execute({
                    username: 'testuser',
                    password: 'wrongpassword'
                })
            ).rejects.toThrow('Invalid username or password');

            expect(mockJwtService.sign).not.toHaveBeenCalled();
        });

        it('should not reveal whether username or password is wrong', async () => {
            mockUserRepository.findByUsername.mockResolvedValue(null);

            const promise1 = loginUser.execute({
                username: 'nonexistent',
                password: 'password123'
            });

            mockUserRepository.findByUsername.mockResolvedValue(mockUser);

            const promise2 = loginUser.execute({
                username: 'testuser',
                password: 'wrongpassword'
            });

            await expect(promise1).rejects.toThrow('Invalid username or password');
            await expect(promise2).rejects.toThrow('Invalid username or password');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors gracefully', async () => {
            mockUserRepository.findByUsername.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                loginUser.execute({
                    username: 'testuser',
                    password: 'password123'
                })
            ).rejects.toThrow('Database error');
        });
    });
});
