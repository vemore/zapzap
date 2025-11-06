/**
 * Unit tests for GetPartyDetails use case
 */

const GetPartyDetails = require('../../../../src/use-cases/party/GetPartyDetails');
const Party = require('../../../../src/domain/entities/Party');
const User = require('../../../../src/domain/entities/User');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');
const Round = require('../../../../src/domain/entities/Round');
const GameState = require('../../../../src/domain/value-objects/GameState');

describe('GetPartyDetails Use Case', () => {
    let getPartyDetails;
    let mockPartyRepository;
    let mockUserRepository;
    let mockParty;
    let mockUser;

    beforeEach(async () => {
        // Create test user and party
        mockUser = await User.create('testuser', 'password123');

        const settings = new PartySettings({
            playerCount: 4,
            handSize: 7
        });

        mockParty = Party.create('Test Party', 'owner-id', 'public', settings);

        // Mock repositories
        mockPartyRepository = {
            findById: jest.fn(),
            getPartyPlayers: jest.fn(),
            getRoundById: jest.fn(),
            getGameState: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        getPartyDetails = new GetPartyDetails(mockPartyRepository, mockUserRepository);
    });

    describe('Successful retrieval', () => {
        it('should get public party details without user ID', async () => {
            const players = [
                { id: 'player-1', userId: 'user1', playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(mockUser);

            const result = await getPartyDetails.execute({
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.party).toBeDefined();
            expect(result.party.name).toBe('Test Party');
            expect(result.party.currentPlayers).toBe(1);
            expect(result.party.maxPlayers).toBe(4);
            expect(result.party.isFull).toBe(false);
            expect(result.players).toHaveLength(1);
            expect(result.players[0].username).toBe('testuser');
            expect(result.currentRound).toBeNull();
            expect(result.gameState).toBeNull();
        });

        it('should get party details with current round', async () => {
            const round = Round.create(mockParty.id, 1, 'user1');

            mockParty.startNewRound(round.id);

            const players = [
                { id: 'player-1', userId: 'user1', playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.getRoundById.mockResolvedValue(round);
            mockPartyRepository.getGameState.mockResolvedValue(null);

            const result = await getPartyDetails.execute({
                partyId: mockParty.id
            });

            expect(result.currentRound).toBeDefined();
            expect(result.currentRound.id).toBe(round.id);
            expect(result.currentRound.roundNumber).toBe(1);
        });

        it('should get party details with game state', async () => {
            const round = Round.create(mockParty.id, 1, 'user1');

            const gameState = new GameState({
                deck: [],
                hands: { user1: [] },
                scores: { user1: 0 },
                currentTurn: 0,
                lastAction: 'deal'
            });

            mockParty.startNewRound(round.id);

            const players = [
                { id: 'player-1', userId: 'user1', playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.getRoundById.mockResolvedValue(round);
            mockPartyRepository.getGameState.mockResolvedValue(gameState);

            const result = await getPartyDetails.execute({
                partyId: mockParty.id
            });

            expect(result.gameState).toBeDefined();
            expect(result.gameState.currentTurn).toBe(0);
        });

        it('should handle unknown users gracefully', async () => {
            const players = [
                { id: 'player-1', userId: 'unknown-user', playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(null);

            const result = await getPartyDetails.execute({
                partyId: mockParty.id
            });

            expect(result.players[0].username).toBe('Unknown');
        });

        it('should show party is full when at capacity', async () => {
            const players = [
                { id: '1', userId: 'user1', playerIndex: 0, joinedAt: Date.now() },
                { id: '2', userId: 'user2', playerIndex: 1, joinedAt: Date.now() },
                { id: '3', userId: 'user3', playerIndex: 2, joinedAt: Date.now() },
                { id: '4', userId: 'user4', playerIndex: 3, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(mockUser);

            const result = await getPartyDetails.execute({
                partyId: mockParty.id
            });

            expect(result.party.currentPlayers).toBe(4);
            expect(result.party.isFull).toBe(true);
        });
    });

    describe('Private party access control', () => {
        it('should allow member to view private party', async () => {
            const privateParty = Party.create('Private Party', 'owner-id', 'private', mockParty.settings);

            const players = [
                { id: 'player-1', userId: mockUser.id, playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(privateParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockUserRepository.findById.mockResolvedValue(mockUser);

            const result = await getPartyDetails.execute({
                partyId: privateParty.id,
                userId: mockUser.id
            });

            expect(result.success).toBe(true);
        });

        it('should deny non-member access to private party', async () => {
            const privateParty = Party.create('Private Party', 'owner-id', 'private', mockParty.settings);

            const players = [
                { id: 'player-1', userId: 'other-user', playerIndex: 0, joinedAt: Date.now() }
            ];

            mockPartyRepository.findById.mockResolvedValue(privateParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                getPartyDetails.execute({
                    partyId: privateParty.id,
                    userId: mockUser.id
                })
            ).rejects.toThrow('Access denied. Party is private.');
        });
    });

    describe('Validation errors', () => {
        it('should reject missing party ID', async () => {
            await expect(
                getPartyDetails.execute({})
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject non-existent party', async () => {
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                getPartyDetails.execute({
                    partyId: 'invalid-party'
                })
            ).rejects.toThrow('Party not found');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockPartyRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                getPartyDetails.execute({
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Database error');
        });
    });
});
