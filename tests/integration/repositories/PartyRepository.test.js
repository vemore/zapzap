/**
 * Integration tests for PartyRepository
 */

const fs = require('fs');
const { DatabaseConnection } = require('../../../src/infrastructure/database/sqlite/connection');
const UserRepository = require('../../../src/infrastructure/database/sqlite/repositories/UserRepository');
const PartyRepository = require('../../../src/infrastructure/database/sqlite/repositories/PartyRepository');
const User = require('../../../src/domain/entities/User');
const Party = require('../../../src/domain/entities/Party');
const { PartyVisibility, PartyStatus } = require('../../../src/domain/entities/Party');
const PartyPlayer = require('../../../src/domain/entities/PartyPlayer');
const Round = require('../../../src/domain/entities/Round');
const { RoundAction } = require('../../../src/domain/entities/Round');
const GameState = require('../../../src/domain/value-objects/GameState');
const PartySettings = require('../../../src/domain/value-objects/PartySettings');

describe('PartyRepository Integration', () => {
    let dbConnection;
    let userRepository;
    let partyRepository;
    let testUser;
    const testDbPath = './data/test-party-repo.db';

    beforeAll(async () => {
        // Clean up any existing test database
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }

        dbConnection = new DatabaseConnection(testDbPath);
        await dbConnection.initialize();
        userRepository = new UserRepository(dbConnection);
        partyRepository = new PartyRepository(dbConnection);

        // Create a test user
        testUser = await User.create('testowner', 'password123');
        await userRepository.save(testUser);
    });

    afterAll(async () => {
        if (dbConnection) {
            await dbConnection.close();
        }

        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
    });

    afterEach(async () => {
        // Clean up test data (cascade will handle related records)
        await dbConnection.run('DELETE FROM parties');
    });

    describe('save() and findById()', () => {
        it('should save and retrieve party', async () => {
            const party = Party.create('Test Party', testUser.id, PartyVisibility.PUBLIC);

            await partyRepository.save(party);

            const retrieved = await partyRepository.findById(party.id);

            expect(retrieved).not.toBeNull();
            expect(retrieved.id).toBe(party.id);
            expect(retrieved.name).toBe('Test Party');
            expect(retrieved.ownerId).toBe(testUser.id);
            expect(retrieved.visibility).toBe(PartyVisibility.PUBLIC);
            expect(retrieved.status).toBe(PartyStatus.WAITING);
        });

        it('should update existing party', async () => {
            const party = Party.create('Original Name', testUser.id);
            await partyRepository.save(party);

            party.updateName('Updated Name');
            party.start();
            await partyRepository.save(party);

            const retrieved = await partyRepository.findById(party.id);

            expect(retrieved.name).toBe('Updated Name');
            expect(retrieved.status).toBe(PartyStatus.PLAYING);
        });
    });

    describe('findByInviteCode()', () => {
        it('should find party by invite code', async () => {
            const party = Party.create('Invite Party', testUser.id);
            await partyRepository.save(party);

            const retrieved = await partyRepository.findByInviteCode(party.inviteCode);

            expect(retrieved).not.toBeNull();
            expect(retrieved.id).toBe(party.id);
        });

        it('should return null for non-existent invite code', async () => {
            const retrieved = await partyRepository.findByInviteCode('INVALID1');

            expect(retrieved).toBeNull();
        });
    });

    describe('findPublicParties()', () => {
        it('should find all public parties', async () => {
            const party1 = Party.create('Public 1', testUser.id, PartyVisibility.PUBLIC);
            const party2 = Party.create('Public 2', testUser.id, PartyVisibility.PUBLIC);
            const party3 = Party.create('Private', testUser.id, PartyVisibility.PRIVATE);

            await partyRepository.save(party1);
            await partyRepository.save(party2);
            await partyRepository.save(party3);

            const publicParties = await partyRepository.findPublicParties();

            expect(publicParties).toHaveLength(2);
            expect(publicParties.map(p => p.name)).toContain('Public 1');
            expect(publicParties.map(p => p.name)).toContain('Public 2');
            expect(publicParties.map(p => p.name)).not.toContain('Private');
        });

        it('should filter by status', async () => {
            const waiting = Party.create('Waiting Party', testUser.id, PartyVisibility.PUBLIC);
            const playing = Party.create('Playing Party', testUser.id, PartyVisibility.PUBLIC);
            playing.start();

            await partyRepository.save(waiting);
            await partyRepository.save(playing);

            const waitingParties = await partyRepository.findPublicParties(PartyStatus.WAITING);
            const playingParties = await partyRepository.findPublicParties(PartyStatus.PLAYING);

            expect(waitingParties).toHaveLength(1);
            expect(waitingParties[0].status).toBe(PartyStatus.WAITING);

            expect(playingParties).toHaveLength(1);
            expect(playingParties[0].status).toBe(PartyStatus.PLAYING);
        });
    });

    describe('findByOwner()', () => {
        it('should find parties by owner', async () => {
            const otherUser = await User.create('otheruser', 'password123');
            await userRepository.save(otherUser);

            const party1 = Party.create('Owner Party 1', testUser.id);
            const party2 = Party.create('Owner Party 2', testUser.id);
            const party3 = Party.create('Other Party', otherUser.id);

            await partyRepository.save(party1);
            await partyRepository.save(party2);
            await partyRepository.save(party3);

            const ownerParties = await partyRepository.findByOwner(testUser.id);

            expect(ownerParties).toHaveLength(2);
            expect(ownerParties.every(p => p.ownerId === testUser.id)).toBe(true);
        });
    });

    describe('delete()', () => {
        it('should delete party and cascade to related records', async () => {
            const party = Party.create('Delete Party', testUser.id);
            await partyRepository.save(party);

            // Add a player
            const player = PartyPlayer.create(party.id, testUser.id, 0);
            await partyRepository.addPlayer(player);

            const deleted = await partyRepository.delete(party.id);

            expect(deleted).toBe(true);

            const retrieved = await partyRepository.findById(party.id);
            expect(retrieved).toBeNull();

            // Verify player was cascade deleted
            const players = await partyRepository.getPlayers(party.id);
            expect(players).toHaveLength(0);
        });
    });

    describe('Player management', () => {
        let party;

        beforeEach(async () => {
            party = Party.create('Player Party', testUser.id);
            await partyRepository.save(party);
        });

        it('should add player to party', async () => {
            const partyPlayer = PartyPlayer.create(party.id, testUser.id, 0);

            const added = await partyRepository.addPlayer(partyPlayer);

            expect(added.id).toBeDefined();
            expect(added.partyId).toBe(party.id);
            expect(added.userId).toBe(testUser.id);
            expect(added.playerIndex).toBe(0);
        });

        it('should get players in party', async () => {
            const user2 = await User.create('player2', 'password123');
            await userRepository.save(user2);

            const player1 = PartyPlayer.create(party.id, testUser.id, 0);
            const player2 = PartyPlayer.create(party.id, user2.id, 1);

            await partyRepository.addPlayer(player1);
            await partyRepository.addPlayer(player2);

            const players = await partyRepository.getPlayers(party.id);

            expect(players).toHaveLength(2);
            expect(players[0].playerIndex).toBe(0);
            expect(players[1].playerIndex).toBe(1);
        });

        it('should remove player from party', async () => {
            const player = PartyPlayer.create(party.id, testUser.id, 0);
            await partyRepository.addPlayer(player);

            const removed = await partyRepository.removePlayer(party.id, testUser.id);

            expect(removed).toBe(true);

            const players = await partyRepository.getPlayers(party.id);
            expect(players).toHaveLength(0);
        });

        it('should get player count', async () => {
            expect(await partyRepository.getPlayerCount(party.id)).toBe(0);

            const player = PartyPlayer.create(party.id, testUser.id, 0);
            await partyRepository.addPlayer(player);

            expect(await partyRepository.getPlayerCount(party.id)).toBe(1);
        });

        it('should check if user is in party', async () => {
            expect(await partyRepository.isUserInParty(party.id, testUser.id)).toBe(false);

            const player = PartyPlayer.create(party.id, testUser.id, 0);
            await partyRepository.addPlayer(player);

            expect(await partyRepository.isUserInParty(party.id, testUser.id)).toBe(true);
        });

        it('should get user player index', async () => {
            const player = PartyPlayer.create(party.id, testUser.id, 2);
            await partyRepository.addPlayer(player);

            const index = await partyRepository.getUserPlayerIndex(party.id, testUser.id);

            expect(index).toBe(2);
        });
    });

    describe('Round management', () => {
        let party;

        beforeEach(async () => {
            party = Party.create('Round Party', testUser.id);
            party.start();
            await partyRepository.save(party);
        });

        it('should save and retrieve round', async () => {
            const round = Round.create(party.id, 1);

            await partyRepository.saveRound(round);

            const retrieved = await partyRepository.getActiveRound(party.id);

            expect(retrieved).not.toBeNull();
            expect(retrieved.id).toBe(round.id);
            expect(retrieved.partyId).toBe(party.id);
            expect(retrieved.roundNumber).toBe(1);
            expect(retrieved.isActive()).toBe(true);
        });

        it('should update existing round', async () => {
            const round = Round.create(party.id, 1);
            await partyRepository.saveRound(round);

            round.setPlayPhase();
            round.nextTurn();
            await partyRepository.saveRound(round);

            const retrieved = await partyRepository.getActiveRound(party.id);

            expect(retrieved.currentAction).toBe(RoundAction.DRAW);
            expect(retrieved.currentTurn).toBe(1);
        });

        it('should get all rounds for party', async () => {
            const round1 = Round.create(party.id, 1);
            const round2 = Round.create(party.id, 2);

            await partyRepository.saveRound(round1);
            await partyRepository.saveRound(round2);

            const rounds = await partyRepository.getRounds(party.id);

            expect(rounds).toHaveLength(2);
            expect(rounds[0].roundNumber).toBe(1);
            expect(rounds[1].roundNumber).toBe(2);
        });
    });

    describe('GameState management', () => {
        let party;

        beforeEach(async () => {
            party = Party.create('GameState Party', testUser.id);
            party.start();
            await partyRepository.save(party);
        });

        it('should save and retrieve game state', async () => {
            const gameState = GameState.createInitial(5);

            await partyRepository.saveGameState(party.id, gameState);

            const retrieved = await partyRepository.getGameState(party.id);

            expect(retrieved).not.toBeNull();
            expect(retrieved.roundNumber).toBe(1);
            expect(retrieved.currentAction).toBe('draw');
        });

        it('should update existing game state', async () => {
            const gameState = GameState.createInitial(5);
            await partyRepository.saveGameState(party.id, gameState);

            const updated = gameState.with({
                currentTurn: 5,
                currentAction: 'play'
            });

            await partyRepository.saveGameState(party.id, updated);

            const retrieved = await partyRepository.getGameState(party.id);

            expect(retrieved.currentTurn).toBe(5);
            expect(retrieved.currentAction).toBe('play');
        });
    });

    describe('countPublicParties()', () => {
        it('should count public parties', async () => {
            const party1 = Party.create('Public 1', testUser.id, PartyVisibility.PUBLIC);
            const party2 = Party.create('Public 2', testUser.id, PartyVisibility.PUBLIC);
            const party3 = Party.create('Private', testUser.id, PartyVisibility.PRIVATE);

            await partyRepository.save(party1);
            await partyRepository.save(party2);
            await partyRepository.save(party3);

            const count = await partyRepository.countPublicParties();

            expect(count).toBe(2);
        });

        it('should count by status', async () => {
            const waiting = Party.create('Waiting', testUser.id, PartyVisibility.PUBLIC);
            const playing = Party.create('Playing', testUser.id, PartyVisibility.PUBLIC);
            playing.start();

            await partyRepository.save(waiting);
            await partyRepository.save(playing);

            const waitingCount = await partyRepository.countPublicParties(PartyStatus.WAITING);
            const playingCount = await partyRepository.countPublicParties(PartyStatus.PLAYING);

            expect(waitingCount).toBe(1);
            expect(playingCount).toBe(1);
        });
    });
});
