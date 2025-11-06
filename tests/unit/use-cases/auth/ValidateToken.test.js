/**
 * Unit tests for ValidateToken use case
 */

const ValidateToken = require('../../../../src/use-cases/auth/ValidateToken');
const User = require('../../../../src/domain/entities/User');

describe('ValidateToken Use Case', () => {
    let validateToken;
    let mockUserRepository;
    let mockJwtService;
    let mockUser;

    beforeEach(async () => {
        // Create a real user for testing
        mockUser = await User.create('testuser', 'password123');

        // Mock repository
        mockUserRepository = {
            findById: jest.fn()
        };

        // Mock JWT service
        mockJwtService = {
            verify: jest.fn(),
            extractTokenFromHeader: jest.fn()
        };

        validateToken = new ValidateToken(mockUserRepository, mockJwtService);
    });

    describe('Successful validation', () => {
        it('should validate token and return user', async () => {
            const mockDecoded = {
                userId: mockUser.id,
                username: 'testuser',
                iat: 1234567890,
                exp: 1234567890 + 3600
            };

            mockJwtService.verify.mockReturnValue(mockDecoded);
            mockUserRepository.findById.mockResolvedValue(mockUser);

            const result = await validateToken.execute({
                token: 'valid-jwt-token'
            });

            expect(result.success).toBe(true);
            expect(result.user).toBeDefined();
            expect(result.user.username).toBe('testuser');
            expect(result.user.passwordHash).toBeUndefined();
            expect(result.tokenData).toEqual({
                userId: mockUser.id,
                username: 'testuser',
                issuedAt: mockDecoded.iat,
                expiresAt: mockDecoded.exp
            });

            expect(mockJwtService.verify).toHaveBeenCalledWith('valid-jwt-token');
            expect(mockUserRepository.findById).toHaveBeenCalledWith(mockUser.id);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing token', async () => {
            await expect(
                validateToken.execute({})
            ).rejects.toThrow('Token is required');
        });

        it('should reject empty token', async () => {
            await expect(
                validateToken.execute({
                    token: ''
                })
            ).rejects.toThrow('Token is required');
        });

        it('should reject invalid token', async () => {
            mockJwtService.verify.mockImplementation(() => {
                throw new Error('Invalid token');
            });

            await expect(
                validateToken.execute({
                    token: 'invalid-token'
                })
            ).rejects.toThrow('Invalid or expired token');

            expect(mockUserRepository.findById).not.toHaveBeenCalled();
        });

        it('should reject expired token', async () => {
            mockJwtService.verify.mockImplementation(() => {
                throw new Error('Token expired');
            });

            await expect(
                validateToken.execute({
                    token: 'expired-token'
                })
            ).rejects.toThrow('Invalid or expired token');
        });
    });

    describe('User not found', () => {
        it('should reject token for deleted user', async () => {
            const mockDecoded = {
                userId: 'deleted-user-id',
                username: 'deleteduser',
                iat: 1234567890,
                exp: 1234567890 + 3600
            };

            mockJwtService.verify.mockReturnValue(mockDecoded);
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                validateToken.execute({
                    token: 'valid-token-deleted-user'
                })
            ).rejects.toThrow('User not found');
        });
    });

    describe('executeFromHeader()', () => {
        it('should validate token from Authorization header', async () => {
            const mockDecoded = {
                userId: mockUser.id,
                username: 'testuser',
                iat: 1234567890,
                exp: 1234567890 + 3600
            };

            mockJwtService.extractTokenFromHeader.mockReturnValue('extracted-token');
            mockJwtService.verify.mockReturnValue(mockDecoded);
            mockUserRepository.findById.mockResolvedValue(mockUser);

            const result = await validateToken.executeFromHeader({
                authHeader: 'Bearer extracted-token'
            });

            expect(result.success).toBe(true);
            expect(result.user.username).toBe('testuser');

            expect(mockJwtService.extractTokenFromHeader).toHaveBeenCalledWith('Bearer extracted-token');
            expect(mockJwtService.verify).toHaveBeenCalledWith('extracted-token');
        });

        it('should reject invalid Authorization header format', async () => {
            mockJwtService.extractTokenFromHeader.mockReturnValue(null);

            await expect(
                validateToken.executeFromHeader({
                    authHeader: 'Invalid header'
                })
            ).rejects.toThrow('Invalid Authorization header format');
        });

        it('should reject missing Authorization header', async () => {
            mockJwtService.extractTokenFromHeader.mockReturnValue(null);

            await expect(
                validateToken.executeFromHeader({
                    authHeader: null
                })
            ).rejects.toThrow('Invalid Authorization header format');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors gracefully', async () => {
            const mockDecoded = {
                userId: mockUser.id,
                username: 'testuser',
                iat: 1234567890,
                exp: 1234567890 + 3600
            };

            mockJwtService.verify.mockReturnValue(mockDecoded);
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                validateToken.execute({
                    token: 'valid-token'
                })
            ).rejects.toThrow('Database error');
        });
    });
});
