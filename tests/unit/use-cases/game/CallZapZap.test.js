/**
 * Unit tests for CallZapZap use case
 */

const CallZapZap = require('../../../../src/use-cases/game/CallZapZap');
const User = require('../../../../src/domain/entities/User');
const Party = require('../../../../src/domain/entities/Party');
const Round = require('../../../../src/domain/entities/Round');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');
const GameState = require('../../../../src/domain/value-objects/GameState');

describe('CallZapZap Use Case', () => {
    let callZapZap;
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
            playerCount: 3,
            handSize: 7
        });
        mockParty = Party.create('Test Party', 'owner-id', 'public', settings);
        mockParty.start();

        // Create test round
        mockRound = Round.create(mockParty.id, 1, 'player0');
        mockParty.startNewRound(mockRound.id);

        // Create test game state
        // Player 0 has low hand (Ace + 2 = 3 points)
        mockGameState = new GameState({
            deck: [],
            hands: {
                0: [0, 1],      // Ace of spades (1) + 2 of spades (2) = 3 points
                1: [13, 14],    // Ace of hearts (1) + 2 of hearts (2) = 3 points
                2: [26, 27, 28] // Ace, 2, 3 of clubs = 6 points
            },
            lastCardsPlayed: [],
            cardsPlayed: [],
            scores: { 0: 0, 1: 0, 2: 0 },
            currentTurn: 0,
            currentAction: 'zapzap',
            roundNumber: 1
        });

        // Mock repositories
        mockPartyRepository = {
            findById: jest.fn(),
            getRoundById: jest.fn(),
            getGameState: jest.fn(),
            getPartyPlayers: jest.fn(),
            saveGameState: jest.fn(),
            saveRound: jest.fn()
        };

        mockUserRepository = {
            findById: jest.fn()
        };

        callZapZap = new CallZapZap(mockPartyRepository, mockUserRepository);
    });

    describe('Successful zapzap', () => {
        it('should call zapzap successfully when lowest', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 },
                { id: 'p2', userId: 'user2', playerIndex: 2 }
            ];

            const lowHandState = new GameState({
                ...mockGameState.toObject(),
                hands: {
                    0: [0, 1],      // 3 points
                    1: [13, 14, 15], // 6 points
                    2: [26, 27, 28] // 6 points
                }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(lowHandState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);
            mockPartyRepository.saveRound.mockResolvedValue(true);

            const result = await callZapZap.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.zapzapSuccess).toBe(true);
            expect(result.counteracted).toBe(false);
            expect(result.callerPoints).toBe(3);
            expect(result.scores[1]).toBe(6);  // Ace + 2 + 3 = 1+2+3 = 6 points
            expect(result.scores[2]).toBe(6);  // Ace + 2 + 3 = 1+2+3 = 6 points
        });

        it('should be counteracted when another player has equal/lower points', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 },
                { id: 'p2', userId: 'user2', playerIndex: 2 }
            ];

            // Player 0 and 1 both have 3 points
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(mockGameState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);
            mockPartyRepository.saveRound.mockResolvedValue(true);

            const result = await callZapZap.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.success).toBe(true);
            expect(result.zapzapSuccess).toBe(false);
            expect(result.counteracted).toBe(true);
            expect(result.counteractedBy).toBe(1);
        });

        it('should calculate scores correctly when counteracted', async () => {
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
            mockPartyRepository.saveRound.mockResolvedValue(true);

            const result = await callZapZap.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            // Caller gets penalty: callerPoints + ((activePlayerCount - 1) * 5)
            // mockGameState: player 0 = 3pts, player 1 = 3pts, player 2 = 6pts
            // Counteracted by player 1 (equal), so caller gets: 3 + ((3-1) * 5) = 3 + 10 = 13
            expect(result.scores[0]).toBe(13);
        });

        it('should finish the round', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 }
            ];

            const twoPlayerState = new GameState({
                ...mockGameState.toObject(),
                hands: { 0: [0], 1: [13, 14] }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(twoPlayerState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);
            mockPartyRepository.saveRound.mockResolvedValue(true);

            await callZapZap.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(mockPartyRepository.saveRound).toHaveBeenCalled();
        });
    });

    describe('Validation errors', () => {
        it('should reject missing user ID', async () => {
            await expect(
                callZapZap.execute({
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User ID is required');
        });

        it('should reject missing party ID', async () => {
            await expect(
                callZapZap.execute({
                    userId: mockUser.id
                })
            ).rejects.toThrow('Party ID is required');
        });

        it('should reject non-existent user', async () => {
            mockUserRepository.findById.mockResolvedValue(null);

            await expect(
                callZapZap.execute({
                    userId: 'invalid',
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User not found');
        });

        it('should reject non-existent party', async () => {
            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(null);

            await expect(
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: 'invalid'
                })
            ).rejects.toThrow('Party not found');
        });
    });

    describe('Business rule violations', () => {
        it('should reject zapzap when party not playing', async () => {
            const waitingParty = Party.create('Waiting Party', 'owner', 'public', mockParty.settings);

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(waitingParty);

            await expect(
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: waitingParty.id
                })
            ).rejects.toThrow('Party is not in playing state');
        });

        it('should reject zapzap when not player turn', async () => {
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
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Not your turn');
        });

        it('should reject zapzap when hand value too high', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            const highHandState = new GameState({
                ...mockGameState.toObject(),
                hands: {
                    0: [9, 10, 11] // 10 + J(11) + Q(12) = 33 points
                }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(highHandState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Hand value too high (33 points). Must be ≤5 to call zapzap.');
        });

        it('should reject zapzap when current action not allowed', async () => {
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
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Cannot call zapzap at this time');
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
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('User is not in this party');
        });
    });

    describe('Point calculation', () => {
        it('should calculate hand points correctly for face cards', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 }
            ];

            // J, Q, K = 11 + 12 + 13 = 36
            const faceCardState = new GameState({
                ...mockGameState.toObject(),
                hands: { 0: [10, 11, 12] }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(faceCardState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);

            await expect(
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Hand value too high (36 points)');
        });

        it('should count jokers as 0 points', async () => {
            const players = [
                { id: 'p0', userId: mockUser.id, playerIndex: 0 },
                { id: 'p1', userId: 'user1', playerIndex: 1 }
            ];

            // Ace + Joker = 1 + 0 = 1 point
            const jokerHandState = new GameState({
                ...mockGameState.toObject(),
                hands: {
                    0: [0, 52],   // Ace + Joker = 1
                    1: [13, 14]   // 2 Aces = 2
                }
            });

            mockUserRepository.findById.mockResolvedValue(mockUser);
            mockPartyRepository.findById.mockResolvedValue(mockParty);
            mockPartyRepository.getRoundById.mockResolvedValue(mockRound);
            mockPartyRepository.getGameState.mockResolvedValue(jokerHandState);
            mockPartyRepository.getPartyPlayers.mockResolvedValue(players);
            mockPartyRepository.saveGameState.mockResolvedValue(true);
            mockPartyRepository.saveRound.mockResolvedValue(true);

            const result = await callZapZap.execute({
                userId: mockUser.id,
                partyId: mockParty.id
            });

            expect(result.callerPoints).toBe(1);
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockUserRepository.findById.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                callZapZap.execute({
                    userId: mockUser.id,
                    partyId: mockParty.id
                })
            ).rejects.toThrow('Database error');
        });
    });
});
