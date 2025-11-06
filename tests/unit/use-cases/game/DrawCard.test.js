/**
 * Unit tests for DrawCard use case
 */

const DrawCard = require('../../../../src/use-cases/game/DrawCard');
const User = require('../../../../src/domain/entities/User');
const Party = require('../../../../src/domain/entities/Party');
const Round = require('../../../../src/domain/entities/Round');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');
const GameState = require('../../../../src/domain/value-objects/GameState');

describe('DrawCard Use Case', () => {
    let drawCard;
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
                0: [10, 11, 12],
                1: [20, 21, 22]
            },
            lastCardsPlayed: [5, 6, 7],
            cardsPlayed: [8, 9],
            scores: { 0: 0, 1: 0 },
            currentTurn: 0,
            currentAction: 'draw',
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

        drawCard = new DrawCard(mockPartyRepository, mockUserRepository);
    });

    describe('Successful draws', () => {
        it('should draw from deck successfully', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await drawCard.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                source: 'deck'
            });

            expect(result.success).toBe(true);
            expect(result.cardDrawn).toBe(4); // Top card from deck
            expect(result.source).toBe('deck');
            expect(result.handSize).toBe(4);
            expect(result.gameState.currentAction).toBe('play');
            expect(result.gameState.currentTurn).toBe(1); // Next turn
        });

        it('should draw from played cards successfully', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await drawCard.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                source: 'played'
            });

            expect(result.success).toBe(true);
            expect(result.cardDrawn).toBe(7); // Top card from lastCardsPlayed
            expect(result.source).toBe('played');
            expect(result.handSize).toBe(4);
        });

        it('should draw specific card from played cards', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await drawCard.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                source: 'played',
                cardId: 5
            });

            expect(result.success).toBe(true);
            expect(result.cardDrawn).toBe(5);
        });

        it('should advance to next turn', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 },
                { id: 'p2', userId: 'user2', playerIndex: 2 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await drawCard.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                source: 'deck'
            });

            expect(result.gameState.currentTurn).toBe(1);
        });

        it('should wrap turn to first player', async () => {
            const players = [
                { id: 'p0', userId: 'user0', playerIndex: 0 },
                { id: 'p1', userId: mockUser.id, playerIndex: 1 }
            ];

            const lastPlayerState = new GameState({
                ...mockGameState.toObject(),
                currentTurn: 1,
                hands: { 0: [1, 2], 1: [3, 4] }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(lastPlayerState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);

            const result = await drawCard.execute({
                userId: mockUser.id,
                partyId: mockParty.id,
                source: 'deck'
            });

            expect(result.gameState.currentTurn).toBe(0);
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                drawCard.execute({
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID', async () => {
            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject invalid source', async () => {
            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'invalid'
                })
            ).rejects.toThrow('Source must be "deck" or "played"');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                drawCard.execute({
                    userId: 'invalid',
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject non-existent party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: 'invalid',
                    source: 'deck'
                })
            ).rejects.toThrow('Party not found');
        });
    });

    describe('Business rule violations', () => {
        it('should reject draw when party not playing', async () => {
            const waitingParty = Party.create('Waiting Party', 'owner', 'public', mockParty.settings);

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(waitingParty);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: waitingParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Party is not in playing state');
        });

        it('should reject draw when not player turn', async () => {
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
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Not your turn');
        });

        it('should reject draw when current action is not DRAW', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const playState = new GameState({
                ...mockGameState.toObject(),
                currentAction: 'play'
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(playState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Current action is not DRAW');
        });

        it('should reject draw from empty deck', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const emptyDeckState = new GameState({
                ...mockGameState.toObject(),
                deck: []
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(emptyDeckState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Deck is empty');
        });

        it('should reject draw from empty played cards', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const noPlayedState = new GameState({
                ...mockGameState.toObject(),
                lastCardsPlayed: []
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(noPlayedState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'played'
                })
            ).rejects.toThrow('No cards available to draw from played cards');
        });

        it('should reject draw of unavailable card from played', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'played',
                    cardId: 99
                })
            ).rejects.toThrow('Card not available in played cards');
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
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'deck'
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
                drawCard.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id,
                    source: 'deck'
                })
            ).rejects.toThrow('Database error');
        });
    });
});
