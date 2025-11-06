/**
 * Unit tests for JwtService
 * Tests token generation, verification, and utility methods
 */

const JwtService = require('../../../../src/infrastructure/auth/JwtService');

describe('JwtService', () => {
    let jwtService;

    beforeEach(() => {
        jwtService = new JwtService({
            secret: 'test-secret-key',
            expiresIn: '1h'
        });
    });

    describe('Constructor', () => {
        it('should use provided configuration', () => {
            expect(jwtService.secret).toBe('test-secret-key');
            expect(jwtService.expiresIn).toBe('1h');
            expect(jwtService.algorithm).toBe('HS256');
        });

        it('should use default values when config not provided', () => {
            const defaultService = new JwtService();
            expect(defaultService.expiresIn).toBe('7d');
            expect(defaultService.algorithm).toBe('HS256');
        });

        it('should use environment variable JWT_SECRET if available', () => {
            const originalSecret = process.env.JWT_SECRET;
            process.env.JWT_SECRET = 'env-secret';

            const envService = new JwtService();
            expect(envService.secret).toBe('env-secret');

            // Cleanup
            if (originalSecret) {
                process.env.JWT_SECRET = originalSecret;
            } else {
                delete process.env.JWT_SECRET;
            }
        });
    });

    describe('sign()', () => {
        it('should generate valid JWT token', () => {
            const payload = {
                userId: 'user-123',
                username: 'testuser'
            };

            const token = jwtService.sign(payload);

            expect(token).toBeDefined();
            expect(typeof token).toBe('string');
            expect(token.split('.')).toHaveLength(3); // JWT has 3 parts
        });

        it('should include userId and username in token', () => {
            const payload = {
                userId: 'user-456',
                username: 'alice'
            };

            const token = jwtService.sign(payload);
            const decoded = jwtService.decode(token);

            expect(decoded.userId).toBe('user-456');
            expect(decoded.username).toBe('alice');
        });

        it('should throw error on sign failure with invalid payload', () => {
            // jwt.sign will throw with undefined payload
            expect(() => {
                jwtService.sign(undefined);
            }).toThrow();
        });
    });

    describe('verify()', () => {
        it('should verify valid token', () => {
            const payload = {
                userId: 'user-789',
                username: 'bob'
            };

            const token = jwtService.sign(payload);
            const decoded = jwtService.verify(token);

            expect(decoded.userId).toBe('user-789');
            expect(decoded.username).toBe('bob');
            expect(decoded.iat).toBeDefined();
            expect(decoded.exp).toBeDefined();
        });

        it('should reject token with wrong secret', () => {
            const payload = {
                userId: 'user-999',
                username: 'charlie'
            };

            const token = jwtService.sign(payload);

            // Create new service with different secret
            const differentService = new JwtService({ secret: 'different-secret' });

            expect(() => {
                differentService.verify(token);
            }).toThrow('Invalid token');
        });

        it('should reject expired token', () => {
            const shortLivedService = new JwtService({
                secret: 'test-secret',
                expiresIn: '1s' // 1 second expiration
            });

            const payload = {
                userId: 'user-expired',
                username: 'expired'
            };

            const token = shortLivedService.sign(payload);

            // Wait for token to expire (2 seconds to be safe)
            return new Promise(resolve => setTimeout(resolve, 2100))
                .then(() => {
                    expect(() => {
                        shortLivedService.verify(token);
                    }).toThrow('Token expired');
                });
        }, 3000); // Increase test timeout to 3 seconds

        it('should reject malformed token', () => {
            expect(() => {
                jwtService.verify('not.a.token');
            }).toThrow('Invalid token');
        });

        it('should reject empty token', () => {
            expect(() => {
                jwtService.verify('');
            }).toThrow();
        });
    });

    describe('decode()', () => {
        it('should decode token without verification', () => {
            const payload = {
                userId: 'user-decode',
                username: 'decoder'
            };

            const token = jwtService.sign(payload);
            const decoded = jwtService.decode(token);

            expect(decoded.userId).toBe('user-decode');
            expect(decoded.username).toBe('decoder');
        });

        it('should decode expired token', () => {
            const shortLivedService = new JwtService({
                secret: 'test-secret',
                expiresIn: '1s' // 1 second expiration
            });

            const payload = {
                userId: 'user-expired-decode',
                username: 'expired-decoder'
            };

            const token = shortLivedService.sign(payload);

            // Wait for expiration (2 seconds to be safe)
            return new Promise(resolve => setTimeout(resolve, 2100))
                .then(() => {
                    const decoded = jwtService.decode(token);
                    expect(decoded.userId).toBe('user-expired-decode');
                });
        }, 3000); // Increase test timeout to 3 seconds

        it('should return null for invalid token', () => {
            const decoded = jwtService.decode('invalid.token.here');
            expect(decoded).toBeNull();
        });
    });

    describe('extractTokenFromHeader()', () => {
        it('should extract token from Bearer header', () => {
            const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.token';
            const authHeader = `Bearer ${token}`;

            const extracted = jwtService.extractTokenFromHeader(authHeader);

            expect(extracted).toBe(token);
        });

        it('should return null for missing header', () => {
            const extracted = jwtService.extractTokenFromHeader(null);
            expect(extracted).toBeNull();
        });

        it('should return null for undefined header', () => {
            const extracted = jwtService.extractTokenFromHeader(undefined);
            expect(extracted).toBeNull();
        });

        it('should return null for malformed header (no Bearer)', () => {
            const extracted = jwtService.extractTokenFromHeader('token-without-bearer');
            expect(extracted).toBeNull();
        });

        it('should return null for malformed header (wrong prefix)', () => {
            const extracted = jwtService.extractTokenFromHeader('Basic token123');
            expect(extracted).toBeNull();
        });

        it('should return null for empty string', () => {
            const extracted = jwtService.extractTokenFromHeader('');
            expect(extracted).toBeNull();
        });
    });

    describe('isExpired()', () => {
        it('should return false for valid token', () => {
            const payload = {
                userId: 'user-valid',
                username: 'valid'
            };

            const token = jwtService.sign(payload);
            const expired = jwtService.isExpired(token);

            expect(expired).toBe(false);
        });

        it('should return true for expired token', () => {
            const shortLivedService = new JwtService({
                secret: 'test-secret',
                expiresIn: '1s' // 1 second expiration
            });

            const payload = {
                userId: 'user-check-expired',
                username: 'check-expired'
            };

            const token = shortLivedService.sign(payload);

            // Wait for expiration (2 seconds to be safe)
            return new Promise(resolve => setTimeout(resolve, 2100))
                .then(() => {
                    const expired = shortLivedService.isExpired(token);
                    expect(expired).toBe(true);
                });
        }, 3000); // Increase test timeout to 3 seconds

        it('should return true for invalid token', () => {
            const expired = jwtService.isExpired('invalid.token');
            expect(expired).toBe(true);
        });

        it('should return true for token without exp field', () => {
            // This shouldn't normally happen with our sign method,
            // but test the defensive check
            const expired = jwtService.isExpired('');
            expect(expired).toBe(true);
        });
    });

    describe('getTimeToExpiry()', () => {
        it('should return positive number for valid token', () => {
            const payload = {
                userId: 'user-time',
                username: 'timer'
            };

            const token = jwtService.sign(payload);
            const timeToExpiry = jwtService.getTimeToExpiry(token);

            expect(timeToExpiry).toBeGreaterThan(0);
            expect(timeToExpiry).toBeLessThanOrEqual(3600); // 1 hour in seconds
        });

        it('should return 0 for expired token', () => {
            const shortLivedService = new JwtService({
                secret: 'test-secret',
                expiresIn: '1s' // 1 second expiration
            });

            const payload = {
                userId: 'user-expired-time',
                username: 'expired-timer'
            };

            const token = shortLivedService.sign(payload);

            // Wait for expiration (2 seconds to be safe)
            return new Promise(resolve => setTimeout(resolve, 2100))
                .then(() => {
                    const timeToExpiry = shortLivedService.getTimeToExpiry(token);
                    expect(timeToExpiry).toBe(0);
                });
        }, 3000); // Increase test timeout to 3 seconds

        it('should return -1 for invalid token', () => {
            const timeToExpiry = jwtService.getTimeToExpiry('invalid.token');
            expect(timeToExpiry).toBe(-1);
        });
    });

    describe('Integration scenarios', () => {
        it('should handle complete auth flow', () => {
            // 1. Sign token
            const payload = {
                userId: 'user-flow',
                username: 'flowuser'
            };

            const token = jwtService.sign(payload);

            // 2. Extract from header
            const authHeader = `Bearer ${token}`;
            const extracted = jwtService.extractTokenFromHeader(authHeader);

            expect(extracted).toBe(token);

            // 3. Verify token
            const decoded = jwtService.verify(extracted);

            expect(decoded.userId).toBe('user-flow');
            expect(decoded.username).toBe('flowuser');

            // 4. Check not expired
            expect(jwtService.isExpired(token)).toBe(false);
            expect(jwtService.getTimeToExpiry(token)).toBeGreaterThan(0);
        });
    });
});
