/**
 * Unit tests for LeaveParty use case
 */

const LeaveParty = require('../../../../src/use-cases/party/LeaveParty');
const Party = require('../../../../src/domain/entities/Party');
const User = require('../../../../src/domain/entities/User');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');

describe('LeaveParty Use Case', () => {
    let leaveParty;
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
            getPartyPlayers: jest.fn(),
            removePlayer: jest.fn(),
            save: jest.fn(),
            delete: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        leaveParty = new LeaveParty(mockPartyRepository, mockUserRepository);
    });

    describe('Successful leaves', () => {
        it('should leave party as regular player', async () => {
            const players = [
                { id: 'player-1', userId: 'owner-id', playerIndex: 0 },
                { id: 'player-2', userId: mockUser.id, playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.removePlayer.mockResolvedValue(true);

            const result = await leaveParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.partyDeleted).toBe(false);
            expect(mockPartyRepository.removePlayer).toHaveBeenCalledWith('player-2');
        });

        it('should transfer ownership when owner leaves', async () => {
            mockParty.updateOwner(mockUser.id);
            const secondUser = await User.create('seconduser', 'password123');

            const players = [
                { id: 'player-1', userId: mockUser.id, playerIndex: 0 },
                { id: 'player-2', userId: secondUser.id, playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.removePlayer.mockResolvedValue(true);
            mockPartyRepository.save.mockResolvedValue(mockParty);

            const result = await leaveParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(mockParty.ownerId).toBe(secondUser.id);
            expect(mockPartyRepository.save).toHaveBeenCalledWith(mockParty);
        });

        it('should delete party when last player leaves', async () => {
            mockParty.updateOwner(mockUser.id);

            const players = [
                { id: 'player-1', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.delete.mockResolvedValue(true);

            const result = await leaveParty.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.partyDeleted).toBe(true);
            expect(mockPartyRepository.delete).toHaveBeenCalledWith(mockParty.id);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                leaveParty.execute({
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID', async () => {
            await expect(
                leaveParty.execute({
                    userId: mockUser.id
                })
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                leaveParty.execute({
                    userId: 'non-existent',
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject non-existent party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                leaveParty.execute({
                    userId: mockUser.id,
                    partyId: 'invalid-party'
                })
            ).rejects.toThrow('Party not found');
        });

        it('should reject user not in party', async () => {
            const players = [
                { id: 'player-1', userId: 'other-user', playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                leaveParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User is not in this party');
        });
    });

    describe('Business rule violations', () => {
        it('should reject leaving during active game', async () => {
            mockParty.start();

            const players = [
                { id: 'player-1', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                leaveParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Cannot leave party during active game');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                leaveParty.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Database error');
        });
    });
});
