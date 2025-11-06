/**
 * Unit tests for CreateParty use case
 */

const CreateParty = require('../../../../src/use-cases/party/CreateParty');
const Party = require('../../../../src/domain/entities/Party');
const User = require('../../../../src/domain/entities/User');

describe('CreateParty Use Case', () => {
    let createParty;
    let mockPartyRepository;
    let mockUserRepository;
    let mockUser;

    beforeEach(async () => {
        // Create a real user for testing
        mockUser = await User.create('testowner', 'password123');

        // Mock repositories
        mockPartyRepository = {
            save: jest.fn(),
            findById: jest.fn(),
            findByInviteCode: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        createParty = new CreateParty(mockPartyRepository, mockUserRepository);
    });

    describe('Successful party creation', () => {
        it('should create public party with valid settings', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.save.mockImplementation(async (party) => party);

            const result = await createParty.execute({
                ownerId: mockUser.id,
                name: 'Test Party',
                visibility: 'public',
                settings: {
                    playerCount: 4,
                    handSize: 7,
                    allowSpectators: false,
                    roundTimeLimit: 0
                }
            });

            expect(result.success).toBe(true);
            expect(result.party).toBeDefined();
            expect(result.party.name).toBe('Test Party');
            expect(result.party.visibility).toBe('public');
            expect(result.party.status).toBe('waiting');
            expect(result.party.inviteCode).toBeDefined();
            expect(result.party.inviteCode).toHaveLength(8);

            expect(mockUserRepository.findById).toHaveBeenCalledWith(mockUser.id);
            expect(mockPartyRepository.save).toHaveBeenCalled();
        });

        it('should create private party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.save.mockImplementation(async (party) => party);

            const result = await createParty.execute({
                ownerId: mockUser.id,
                name: 'Private Party',
                visibility: 'private',
                settings: {
                    playerCount: 5,
                    handSize: 6
                }
            });

            expect(result.success).toBe(true);
            expect(result.party.visibility).toBe('private');
        });

        it('should trim party name', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.save.mockImplementation(async (party) => party);

            const result = await createParty.execute({
                ownerId: mockUser.id,
                name: '  Spaced Name  ',
                visibility: 'public',
                settings: {
                    playerCount: 4,
                    handSize: 7
                }
            });

            expect(result.party.name).toBe('Spaced Name');
        });

        it('should create party with optional spectator settings', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.save.mockImplementation(async (party) => party);

            const result = await createParty.execute({
                ownerId: mockUser.id,
                name: 'Spectator Party',
                visibility: 'public',
                settings: {
                    playerCount: 4,
                    handSize: 7,
                    allowSpectators: true,
                    roundTimeLimit: 300
                }
            });

            expect(result.success).toBe(true);
            expect(result.party.settings.allowSpectators).toBe(true);
            expect(result.party.settings.roundTimeLimit).toBe(300);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing owner ID', async () => {
            await expect(
                createParty.execute({
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Owner ID is required');
        });

        it('should reject missing party name', async () => {
            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Party name is required');
        });

        it('should reject empty party name', async () => {
            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: '',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow();
        });

        it('should reject short party name', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'ab',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Party name must be at least 3 characters long');
        });

        it('should reject long party name', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'a'.repeat(51),
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Party name must not exceed 50 characters');
        });

        it('should reject invalid visibility', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'invalid',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Visibility must be either "public" or "private"');
        });

        it('should reject missing settings', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'public'
                })
            ).rejects.toThrow('Settings are required');
        });

        it('should reject invalid player count', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 2, handSize: 7 }
                })
            ).rejects.toThrow();
        });

        it('should reject invalid hand size', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 3 }
                })
            ).rejects.toThrow();
        });
    });

    describe('Owner validation', () => {
        it('should reject non-existent owner', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                createParty.execute({
                    ownerId: 'non-existent-id',
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Owner not found');
        });
    });

    describe('Repository errors', () => {
        it('should handle user repository errors', async () => {
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Database error');
        });

        it('should handle party repository errors', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.save.mockRejectedValue(
                new Error('Save failed')
            );

            await expect(
                createParty.execute({
                    ownerId: mockUser.id,
                    name: 'Test Party',
                    visibility: 'public',
                    settings: { playerCount: 4, handSize: 7 }
                })
            ).rejects.toThrow('Save failed');
        });
    });
});
