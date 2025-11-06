/**
 * Unit tests for GetGameState use case
 */

const GetGameState = require('../../../../src/use-cases/game/GetGameState');
const User = require('../../../../src/domain/entities/User');
const Party = require('../../../../src/domain/entities/Party');
const Round = require('../../../../src/domain/entities/Round');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');
const GameState = require('../../../../src/domain/value-objects/GameState');

describe('GetGameState Use Case', () => {
    let getGameState;
    let mockPartyRepository;
    let mockUserRepository;
    let mockUser;
    let mockParty;
    let mockRound;
    let mockGameStateData;

    beforeEach(async () => {
        // Create test user
        mockUser = await User.create('testuser', 'password123');

        // Create test party
        const settings = new PartySettings({
            playerCount: 3,
            handSize: 7
        });
        mockParty = Party.create('Test Party', 'owner-id', 'public', settings);
        mockParty.start();

        // Create test round
        mockRound = Round.create(mockParty.id, 1, 'player0');
        mockParty.startNewRound(mockRound.id);

        // Create test game state
        mockGameStateData = new GameState({
            deck: [0, 1, 2, 3, 4],
            hands: {
                0: [10, 11, 12],
                1: [20, 21, 22],
                2: [30, 31, 32]
            },
            lastCardsPlayed: [5, 6],
            cardsPlayed: [7, 8],
            scores: { 0: 0, 1: 0, 2: 0 },
            currentTurn: 0,
            currentAction: 'play',
            roundNumber: 1
        });

        // Mock repositories
        mockPartyRepository = {
            findById: jest.fn(),
            getRoundById: jest.fn(),
            getGameState: jest.fn(),
            getPartyPlayers: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        getGameState = new GetGameState(mockPartyRepository, mockUserRepository);
    });

    describe('Successful retrieval', () => {
        it('should get game state for active game', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 },
                { id: 'p2', userId: 'user2', playerIndex: 2 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameStateData);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.party.id).toBe(mockParty.id);
            expect(result.party.status).toBe('playing');
            expect(result.round.id).toBe(mockRound.id);
            expect(result.gameState).toBeDefined();
            expect(result.gameState.currentTurn).toBe(0);
            expect(result.gameState.currentAction).toBe('play');
        });

        it('should return player-specific view', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 },
                { id: 'p2', userId: 'user2', playerIndex: 2 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameStateData);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            // Player should see their own hand
            expect(result.gameState.playerHand).toEqual([10, 11, 12]);

            // Player should only see hand sizes for others
            expect(result.gameState.otherPlayersHandSizes[1]).toBe(3);
            expect(result.gameState.otherPlayersHandSizes[2]).toBe(3);
            expect(result.gameState.otherPlayersHandSizes[0]).toBeUndefined();
        });

        it('should return deck size instead of actual deck', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameStateData);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.gameState.deckSize).toBe(5);
            expect(result.gameState.deck).toBeUndefined();
        });

        it('should include visible played cards', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameStateData);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.gameState.lastCardsPlayed).toEqual([5, 6]);
            expect(result.gameState.cardsPlayed).toEqual([7, 8]);
        });

        it('should include scores', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameStateData);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.gameState.scores).toEqual({ 0: 0, 1: 0, 2: 0 });
        });
    });

    describe('Party not playing', () => {
        it('should return basic info when party waiting', async () => {
            const waitingParty = Party.create('Waiting Party', 'owner', 'public', mockParty.settings);
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(waitingParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: waitingParty.id
            });

            expect(result.success).toBe(true);
            expect(result.party.status).toBe('waiting');
            expect(result.round).toBeNull();
            expect(result.gameState).toBeNull();
        });

        it('should return basic info when party finished', async () => {
            const finishedParty = Party.create('Finished Party', 'owner', 'public', mockParty.settings);
            finishedParty.start();
            finishedParty.finish();

            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(finishedParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: finishedParty.id
            });

            expect(result.success).toBe(true);
            expect(result.party.status).toBe('finished');
            expect(result.round).toBeNull();
            expect(result.gameState).toBeNull();
        });

        it('should return null for round when no active round', async () => {
            const playingPartyNoRound = Party.create('No Round', 'owner', 'public', mockParty.settings);
            playingPartyNoRound.start();

            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(playingPartyNoRound);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            const result = await getGameState.execute({
                userId: mockUser.id,
                partyId: playingPartyNoRound.id
            });

            expect(result.success).toBe(true);
            expect(result.round).toBeNull();
            expect(result.gameState).toBeNull();
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                getGameState.execute({
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID', async () => {
            await expect(
                getGameState.execute({
                    userId: mockUser.id
                })
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                getGameState.execute({
                    userId: 'invalid',
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject non-existent party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                getGameState.execute({
                    userId: mockUser.id,
                    partyId: 'invalid'
                })
            ).rejects.toThrow('Party not found');
        });

        it('should reject user not in party', async () => {
            const players = [
                { id: 'p1', userId: 'other-user', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                getGameState.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User is not in this party');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                getGameState.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Database error');
        });
    });
});
