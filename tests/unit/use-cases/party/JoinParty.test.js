/**
 * Unit tests for JoinParty use case
 */

const JoinParty = require('../../../../src/use-cases/party/JoinParty');
const Party = require('../../../../src/domain/entities/Party');
const User = require('../../../../src/domain/entities/User');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');

describe('JoinParty Use Case', () => {
    let joinParty;
    let mockPartyRepository;
    let mockUserRepository;
    let mockUser;
    let mockParty;

    beforeEach(async () => {
        // Create test user
        mockUser = await User.create('testuser', 'password123');

        // Create test party
        const settings = new PartySettings({
            playerCount: 4,
            handSize: 7
        });
        mockParty = Party.create('Test Party', 'owner-id', 'public', settings);

        // Mock repositories
        mockPartyRepository = {
            findById: jest.fn(),
            findByInviteCode: jest.fn(),
            getPartyPlayers: jest.fn(),
            addPlayer: jest.fn(),
            save: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        joinParty = new JoinParty(mockPartyRepository, mockUserRepository);
    });

    describe('Successful joins', () => {
        it('should join public party with party ID', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue([]);
            mockPartyRepository.addPlayer.mockImplementation(async (player) => ({
                id: 'player-id',
                partyId: player.partyId,
                userId: player.userId,
                playerIndex: player.playerIndex,
                joinedAt: player.joinedAt
            }));

            const result = await joinParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.party).toBeDefined();
            expect(result.player).toBeDefined();
            expect(result.player.userId).toBe(mockUser.id);
            expect(result.player.playerIndex).toBe(0);

            expect(mockPartyRepository.findById).toHaveBeenCalledWith(mockParty.id);
            expect(mockPartyRepository.addPlayer).toHaveBeenCalled();
        });

        it('should join party with invite code', async () => {
            const privateParty = Party.create('Private Party', 'owner-id', 'private', mockParty.settings);

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findByInviteCode.mockResolvedValue(privateParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue([]);
            mockPartyRepository.addPlayer.mockImplementation(async (player) => ({
                id: 'player-id',
                partyId: player.partyId,
                userId: player.userId,
                playerIndex: player.playerIndex,
                joinedAt: player.joinedAt
            }));

            const result = await joinParty.execute({
                userId: mockUser.id,
                inviteCode: privateParty.inviteCode
            });

            expect(result.success).toBe(true);
            expect(mockPartyRepository.findByInviteCode).toHaveBeenCalledWith(privateParty.inviteCode);
        });

        it('should assign correct player index', async () => {
            const existingPlayers = [
                { id: '1', userId: 'user1', playerIndex: 0 },
                { id: '2', userId: 'user2', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(existingPlayers);
            mockPartyRepository.addPlayer.mockImplementation(async (player) => ({
                id: 'player-id',
                partyId: player.partyId,
                userId: player.userId,
                playerIndex: player.playerIndex,
                joinedAt: player.joinedAt
            }));

            const result = await joinParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.player.playerIndex).toBe(2);
        });

        it('should start party when full', async () => {
            const existingPlayers = [
                { id: '1', userId: 'user1', playerIndex: 0 },
                { id: '2', userId: 'user2', playerIndex: 1 },
                { id: '3', userId: 'user3', playerIndex: 2 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(existingPlayers);
            mockPartyRepository.addPlayer.mockImplementation(async (player) => ({
                id: 'player-id',
                partyId: player.partyId,
                userId: player.userId,
                playerIndex: player.playerIndex,
                joinedAt: player.joinedAt
            }));
            mockPartyRepository.save.mockResolvedValue(mockParty);

            await joinParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(mockParty.status).toBe('playing');
            expect(mockPartyRepository.save).toHaveBeenCalledWith(mockParty);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                joinParty.execute({
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID and invite code', async () => {
            await expect(
                joinParty.execute({
                    userId: mockUser.id
                })
            ).rejects.toThrow('Either party ID or invite code is required');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                joinParty.execute({
                    userId: 'non-existent',
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject invalid party ID', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: 'invalid-party'
                })
            ).rejects.toThrow('Party not found');
        });

        it('should reject invalid invite code', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findByInviteCode.mockResolvedValue(null);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    inviteCode: 'INVALID'
                })
            ).rejects.toThrow('Invalid invite code');
        });

        it('should reject joining private party without invite code', async () => {
            const privateParty = Party.create('Private Party', 'owner-id', 'private', mockParty.settings);

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(privateParty);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: privateParty.id
                })
            ).rejects.toThrow('Party is private. Use invite code to join.');
        });
    });

    describe('Business rule violations', () => {
        it('should reject joining finished party', async () => {
            mockParty.start();
            mockParty.finish();

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Cannot join finished party');
        });

        it('should reject joining full party', async () => {
            const fullPlayers = [
                { id: '1', userId: 'user1', playerIndex: 0 },
                { id: '2', userId: 'user2', playerIndex: 1 },
                { id: '3', userId: 'user3', playerIndex: 2 },
                { id: '4', userId: 'user4', playerIndex: 3 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(fullPlayers);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Party is full');
        });

        it('should reject joining party already in', async () => {
            const existingPlayers = [
                { id: '1', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(existingPlayers);

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User is already in this party');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                joinParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Database error');
        });
    });
});
