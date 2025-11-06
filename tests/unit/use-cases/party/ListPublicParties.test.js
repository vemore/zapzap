/**
 * Unit tests for ListPublicParties use case
 */

const ListPublicParties = require('../../../../src/use-cases/party/ListPublicParties');
const Party = require('../../../../src/domain/entities/Party');
const PartySettings = require('../../../../src/domain/value-objects/PartySettings');

describe('ListPublicParties Use Case', () => {
    let listPublicParties;
    let mockPartyRepository;

    beforeEach(() => {
        // Mock repository
        mockPartyRepository = {
            findPublicParties: jest.fn(),
            getPartyPlayers: jest.fn()
        };

        listPublicParties = new ListPublicParties(mockPartyRepository);
    });

    describe('Successful listing', () => {
        it('should list all public parties with player counts', async () => {
            const settings = new PartySettings({
                playerCount: 4,
                handSize: 7
            });

            const party1 = Party.create('Party 1', 'owner1', 'public', settings);

            const party2 = Party.create('Party 2', 'owner2', 'public', settings);

            mockPartyRepository.findPublicParties.mockResolvedValue([party1, party2]);
            mockPartyRepository.getPartyPlayers
                .mockResolvedValueOnce([
                    { id: '1', userId: 'user1', playerIndex: 0 },
                    { id: '2', userId: 'user2', playerIndex: 1 }
                ])
                .mockResolvedValueOnce([
                    { id: '3', userId: 'user3', playerIndex: 0 }
                ]);

            const result = await listPublicParties.execute();

            expect(result.success).toBe(true);
            expect(result.parties).toHaveLength(2);
            expect(result.parties[0].currentPlayers).toBe(2);
            expect(result.parties[0].maxPlayers).toBe(4);
            expect(result.parties[0].isFull).toBe(false);
            expect(result.parties[1].currentPlayers).toBe(1);
            expect(result.parties[1].isFull).toBe(false);

            expect(mockPartyRepository.findPublicParties).toHaveBeenCalledWith({
                status: undefined,
                limit: 50,
                offset: 0
            });
        });

        it('should filter by status', async () => {
            mockPartyRepository.findPublicParties.mockResolvedValue([]);

            await listPublicParties.execute({ status: 'waiting' });

            expect(mockPartyRepository.findPublicParties).toHaveBeenCalledWith({
                status: 'waiting',
                limit: 50,
                offset: 0
            });
        });

        it('should apply pagination', async () => {
            mockPartyRepository.findPublicParties.mockResolvedValue([]);

            const result = await listPublicParties.execute({
                limit: 10,
                offset: 20
            });

            expect(result.pagination.limit).toBe(10);
            expect(result.pagination.offset).toBe(20);
            expect(mockPartyRepository.findPublicParties).toHaveBeenCalledWith({
                status: undefined,
                limit: 10,
                offset: 20
            });
        });

        it('should mark full parties correctly', async () => {
            const settings = new PartySettings({
                playerCount: 3,
                handSize: 7
            });

            const fullParty = Party.create('Full Party', 'owner', 'public', settings);

            mockPartyRepository.findPublicParties.mockResolvedValue([fullParty]);
            mockPartyRepository.getPartyPlayers.mockResolvedValue([
                { id: '1', userId: 'user1', playerIndex: 0 },
                { id: '2', userId: 'user2', playerIndex: 1 },
                { id: '3', userId: 'user3', playerIndex: 2 }
            ]);

            const result = await listPublicParties.execute();

            expect(result.parties[0].currentPlayers).toBe(3);
            expect(result.parties[0].maxPlayers).toBe(3);
            expect(result.parties[0].isFull).toBe(true);
        });

        it('should use default pagination values', async () => {
            mockPartyRepository.findPublicParties.mockResolvedValue([]);

            await listPublicParties.execute({});

            expect(mockPartyRepository.findPublicParties).toHaveBeenCalledWith({
                status: undefined,
                limit: 50,
                offset: 0
            });
        });
    });

    describe('Validation errors', () => {
        it('should reject invalid status filter', async () => {
            await expect(
                listPublicParties.execute({ status: 'invalid' })
            ).rejects.toThrow('Invalid status filter');
        });

        it('should reject invalid limit (too low)', async () => {
            await expect(
                listPublicParties.execute({ limit: 0 })
            ).rejects.toThrow('Limit must be between 1 and 100');
        });

        it('should reject invalid limit (too high)', async () => {
            await expect(
                listPublicParties.execute({ limit: 101 })
            ).rejects.toThrow('Limit must be between 1 and 100');
        });

        it('should reject negative offset', async () => {
            await expect(
                listPublicParties.execute({ offset: -1 })
            ).rejects.toThrow('Offset must be non-negative');
        });
    });

    describe('Repository errors', () => {
        it('should handle repository errors', async () => {
            mockPartyRepository.findPublicParties.mockRejectedValue(
                new Error('Database error')
            );

            await expect(
                listPublicParties.execute()
            ).rejects.toThrow('Database error');
        });
    });
});
