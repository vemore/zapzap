/**
 * Script to create a test party near the end of game
 * This allows testing the game end screen functionality
 */

const path = require('path');
const { v4: uuidv4 } = require('uuid');

// Setup database path
const dbPath = path.join(__dirname, '..', 'data', 'zapzap.db');
const DatabaseConnection = require('../src/infrastructure/database/sqlite/DatabaseConnection');

async function createTestEndgameParty() {
    const db = new DatabaseConnection(dbPath);
    await db.initialize();

    try {
        // Get existing users - prioritize human users first, then bots
        const humanUsers = await db.all('SELECT id, username, user_type FROM users WHERE user_type = "human" LIMIT 1');
        const botUsers = await db.all('SELECT id, username, user_type FROM users WHERE user_type = "bot" LIMIT 2');

        if (humanUsers.length < 1 || botUsers.length < 2) {
            console.error('Need at least 1 human user and 2 bots in database. Run npm run init-demo first.');
            process.exit(1);
        }

        const users = [...humanUsers, ...botUsers];
        console.log('Found users:', users.map(u => `${u.username} (${u.user_type})`).join(', '));

        // Create party
        const partyId = uuidv4();
        const inviteCode = Math.random().toString(36).substring(2, 10).toUpperCase().padEnd(8, '0');
        const now = Math.floor(Date.now() / 1000);

        await db.run(
            `INSERT INTO parties (id, name, owner_id, invite_code, visibility, status, settings_json, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                partyId,
                'Test Endgame Party',
                users[0].id,
                inviteCode,
                'public',
                'playing',
                JSON.stringify({ playerCount: 3, handSize: 5, allowSpectators: false, roundTimeLimit: 0 }),
                now,
                now
            ]
        );

        console.log(`Created party: ${partyId}`);

        // Add players to party
        for (let i = 0; i < users.length; i++) {
            await db.run(
                `INSERT INTO party_players (party_id, user_id, player_index, joined_at)
                 VALUES (?, ?, ?, ?)`,
                [partyId, users[i].id, i, new Date().toISOString()]
            );
        }

        console.log('Added players to party');

        // Create round
        const roundId = uuidv4();
        await db.run(
            `INSERT INTO rounds (id, party_id, round_number, status, current_turn, current_action, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?)`,
            [roundId, partyId, 5, 'active', 0, 'play', now]
        );

        // Update party with current round
        await db.run(
            `UPDATE parties SET current_round_id = ? WHERE id = ?`,
            [roundId, partyId]
        );

        console.log(`Created round: ${roundId}`);

        // Create game state with scores near 100 (elimination threshold)
        // Player 0: 95 points (human - can win by calling ZapZap with low hand)
        // Player 1: 102 points (eliminated)
        // Player 2: 98 points (about to be eliminated)

        // Create hands that allow Player 0 to call ZapZap (hand value <= 5)
        // Card IDs: 0-12 = Spades (A=0, 2=1, ..., K=12)
        // 13-25 = Hearts, 26-38 = Clubs, 39-51 = Diamonds
        // 52-53 = Jokers (0 points for ZapZap eligibility)

        const gameState = {
            deck: [20, 21, 22, 23, 24, 25, 33, 34, 35, 36], // Remaining cards
            hands: {
                0: [0, 1, 52],      // Player 0: Ace(1) + 2(2) + Joker(0) = 3 points - CAN CALL ZAPZAP!
                1: [10, 11, 12, 23, 24], // Player 1: J(11) + Q(12) + K(13) + Q(12) + K(13) = 61 points
                2: [5, 6, 7, 8]     // Player 2: 6(6) + 7(7) + 8(8) + 9(9) = 30 points
            },
            lastCardsPlayed: [45, 46], // Last cards played
            cardsPlayed: [3, 4, 15, 16, 28, 29], // All cards played this round
            scores: {
                0: 95,   // Human player - close to elimination
                1: 102,  // Bot - already eliminated (>100)
                2: 98    // Bot - close to elimination
            },
            currentTurn: 0, // Player 0's turn (human)
            currentAction: 'play', // Can play cards or call ZapZap
            roundNumber: 5,
            lastAction: {
                type: 'draw',
                playerIndex: 2,
                source: 'deck',
                cardId: 8,
                timestamp: Date.now() - 5000
            },
            isGoldenScore: false,
            eliminatedPlayers: [1] // Player 1 is eliminated
        };

        await db.run(
            `INSERT INTO game_state (party_id, state_json, updated_at)
             VALUES (?, ?, ?)`,
            [partyId, JSON.stringify(gameState), Math.floor(Date.now() / 1000)]
        );

        console.log('Created game state');

        // Output results
        console.log('\n========================================');
        console.log('TEST ENDGAME PARTY CREATED SUCCESSFULLY');
        console.log('========================================\n');
        console.log(`Party ID: ${partyId}`);
        console.log(`Party Name: Test Endgame Party`);
        console.log(`Invite Code: ${inviteCode}`);
        console.log('\nPlayers:');
        users.forEach((u, i) => {
            const score = gameState.scores[i];
            const eliminated = gameState.eliminatedPlayers.includes(i);
            const hand = gameState.hands[i];
            console.log(`  ${i}: ${u.username} - Score: ${score}${eliminated ? ' (ELIMINATED)' : ''}`);
            console.log(`      Hand: [${hand.join(', ')}]`);
        });
        console.log('\nGame State:');
        console.log(`  Current Turn: Player ${gameState.currentTurn} (${users[gameState.currentTurn].username})`);
        console.log(`  Current Action: ${gameState.currentAction}`);
        console.log(`  Round: ${gameState.roundNumber}`);
        console.log('\nTO TEST:');
        console.log(`  1. Login as ${users[0].username}`);
        console.log(`  2. Go to the party "${partyId}"`);
        console.log(`  3. Player 0 has hand value of 3 points (can call ZapZap!)`);
        console.log(`  4. Click ZapZap button to end the game`);
        console.log(`  5. Verify the end game screen appears with winner announcement`);
        console.log('\nDirect URL:');
        console.log(`  http://localhost:5173/game/${partyId}`);

    } catch (error) {
        console.error('Error creating test party:', error);
        throw error;
    } finally {
        await db.close();
    }
}

createTestEndgameParty().catch(console.error);
