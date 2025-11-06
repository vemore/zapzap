/**
 * Unit tests for PlayCards use case
 */

const PlayCards = require('../../../../src/use-cases/game/PlayCards');
const User = require('../../../../src/domain/entities/User');
const Party = require('../../../../src/domain/entities/Party');
const Round = require('../../../../src/domain/entities/Round');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');
const GameState = require('../../../../src/domain/value-objects/GameState');

describe('PlayCards Use Case', () => {
    let playCards;
    let mockPartyRepository;
    let mockUserRepository;
    let mockUser;
    let mockParty;
    let mockRound;
    let mockGameState;

    beforeEach(async () => {
        // Create test user
        mockUser = await User.create('testuser', 'password123');

        // Create test party
        const settings = new PartySettings({
            playerCount: 4,
            handSize: 7
        });
        mockParty = Party.create('Test Party', 'owner-id', 'public', settings);
        mockParty.start();

        // Create test round
        mockRound = Round.create(mockParty.id, 1, 'player0');
        mockParty.startNewRound(mockRound.id);

        // Create test game state
        mockGameState = new GameState({
            deck: [0, 1, 2, 3, 4],
            hands: {
                0: [10, 11, 12, 13, 14],
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
            getPartyPlayers: jest.fn(),
            saveGameState: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        playCards = new PlayCards(mockPartyRepository, mockUserRepository);
    });

    describe('Successful plays', () => {
        it('should play cards successfully', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await playCards.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                cardIds: [10, 11]
            });

            expect(result.success).toBe(true);
            expect(result.cardsPlayed).toEqual([10, 11]);
            expect(result.remainingCards).toBe(3);
            expect(result.gameState.currentAction).toBe('draw');

            expect(mockPartyRepository.saveGameState).toHaveBeenCalled();
        });

        it('should update game state correctly', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await playCards.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                cardIds: [10, 11, 12]
            });

            expect(result.gameState.cardsPlayed).toEqual([10, 11, 12]);
            expect(result.gameState.lastCardsPlayed).toEqual([7, 8]);
            expect(result.gameState.hands[0]).toEqual([13, 14]);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                playCards.execute({
                    partyId: mockParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID', async () => {
            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject missing card IDs', async () => {
            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Card IDs are required');
        });

        it('should reject empty card array', async () => {
            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: []
                })
            ).rejects.toThrow('Card IDs are required');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                playCards.execute({
                    userId: 'invalid',
                    partyId: mockParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject non-existent party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: 'invalid',
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Party not found');
        });
    });

    describe('Business rule violations', () => {
        it('should reject play when party not playing', async () => {
            const waitingParty = Party.create('Waiting Party', 'owner', 'public', mockParty.settings);

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(waitingParty);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: waitingParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Party is not in playing state');
        });

        it('should reject play when no active round', async () => {
            const partyNoRound = Party.create('No Round', 'owner', 'public', mockParty.settings);
            partyNoRound.start();

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(partyNoRound);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: partyNoRound.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('No active round');
        });

        it('should reject play when not player turn', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const wrongTurnState = new GameState({
                ...mockGameState.toObject(),
                currentTurn: 1
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(wrongTurnState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Not your turn');
        });

        it('should reject play when current action is not PLAY', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const drawState = new GameState({
                ...mockGameState.toObject(),
                currentAction: 'draw'
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(drawState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Current action is not PLAY');
        });

        it('should reject playing cards not in hand', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [99, 100]
                })
            ).rejects.toThrow('Card 99 not in hand');
        });

        it('should reject playing single card', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [10]
                })
            ).rejects.toThrow('Must play at least 2 cards');
        });

        it('should reject user not in party', async () => {
            const players = [
                { id: 'p1', userId: 'other-user', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [10, 11]
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
                playCards.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    cardIds: [10, 11]
                })
            ).rejects.toThrow('Database error');
        });
    });
});
