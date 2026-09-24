/**
 * Integration tests for GetGameHistory: GET /history and GET /history/public over the
 * real SQLite repositories, so the join on player_game_results is exercised.
 */

const fs = require('fs');
const DatabaseConnection = require('../../../src/infrastructure/database/sqlite/DatabaseConnection');
const UserRepository = require('../../../src/infrastructure/database/sqlite/repositories/UserRepository');
const PartyRepository = require('../../../src/infrastructure/database/sqlite/repositories/PartyRepository');
const GetGameHistory = require('../../../src/use-cases/history/GetGameHistory');
const User = require('../../../src/domain/entities/User');
const Party = require('../../../src/domain/entities/Party');
const { PartyVisibility } = require('../../../src/domain/entities/Party');

describe('GetGameHistory Integration', () => {
    const testDbPath = './data/test-get-game-history.db';
    let dbConnection;
    let partyRepository;
    let getGameHistory;
    let winner;
    let second;
    let third;

    beforeAll(async () => {
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
        dbConnection = new DatabaseConnection(testDbPath);
        await dbConnection.initialize();
        const userRepository = new UserRepository(dbConnection);
        partyRepository = new PartyRepository(dbConnection);
        getGameHistory = new GetGameHistory(partyRepository, userRepository);

        winner = await User.create('historywinner', 'password123');
        second = await User.create('historysecond', 'password123');
        third = await User.create('historythird', 'password123');
        for (const user of [winner, second, third]) {
            await userRepository.save(user);
        }

        const party = Party.create('History party', winner.id, PartyVisibility.PUBLIC);
        await partyRepository.save(party);
        await partyRepository.saveGameResult({
            partyId: party.id,
            winnerUserId: winner.id,
            winnerFinalScore: 42,
            totalRounds: 6,
            wasGoldenScore: false,
            playerCount: 3
        });
        await partyRepository.savePlayerGameResults(party.id, [
            { userId: winner.id, finalScore: 42, finishPosition: 1, roundsPlayed: 6, isWinner: true },
            { userId: second.id, finalScore: 88, finishPosition: 2, roundsPlayed: 6, isWinner: false },
            { userId: third.id, finalScore: 105, finishPosition: 3, roundsPlayed: 6, isWinner: false }
        ]);
    });

    afterAll(async () => {
        if (dbConnection) {
            await dbConnection.close();
        }
        if (fs.existsSync(testDbPath)) {
            fs.unlinkSync(testDbPath);
        }
    });

    it('gives the caller who finished 3rd their place and score', async () => {
        const result = await getGameHistory.execute({ userId: third.id });

        expect(result.games).toHaveLength(1);
        const game = result.games[0];
        expect(game.winnerUserId).toBe(winner.id);
        expect(game.winnerUsername).toBe('historywinner');
        expect(game.winnerFinalScore).toBe(42);
        expect(game.userPlacement).toBe(3);
        expect(game.userScore).toBe(105);
    });

    it('gives the winner first place', async () => {
        const result = await getGameHistory.execute({ userId: winner.id });

        expect(result.games[0].userPlacement).toBe(1);
        expect(result.games[0].userScore).toBe(42);
    });

    it('leaves both fields out of the public history', async () => {
        const result = await getGameHistory.execute({ publicOnly: true });

        expect(result.games).toHaveLength(1);
        expect(result.games[0]).not.toHaveProperty('userPlacement');
        expect(result.games[0]).not.toHaveProperty('userScore');
    });
});
