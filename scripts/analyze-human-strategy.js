#!/usr/bin/env node
/**
 * analyze-human-strategy.js - Analyze human player actions to identify winning strategies
 *
 * This script analyzes game actions recorded in the database to understand:
 * 1. Play patterns (when singles vs combos are played)
 * 2. Draw source preferences (deck vs played cards)
 * 3. ZapZap timing (when to call, when to hold)
 * 4. Opponent awareness (how hand sizes affect decisions)
 *
 * Usage:
 *   node scripts/analyze-human-strategy.js [--user <username>] [--limit <n>]
 */

const path = require('path');
const sqlite3 = require('better-sqlite3');

// Parse arguments
const args = process.argv.slice(2);
let username = null;
let limit = 1000;

for (let i = 0; i < args.length; i++) {
    if (args[i] === '--user' && args[i + 1]) {
        username = args[++i];
    } else if (args[i] === '--limit' && args[i + 1]) {
        limit = parseInt(args[++i], 10);
    }
}

// Card utilities
function getCardValue(cardId) {
    if (cardId >= 52) return 0; // Joker
    const rank = cardId % 13;
    if (rank === 0) return 1; // Ace
    if (rank >= 10) return rank + 1; // J=11, Q=12, K=13
    return rank + 1;
}

function calculateHandValue(hand) {
    return hand.reduce((sum, c) => sum + getCardValue(c), 0);
}

function isJoker(cardId) {
    return cardId >= 52;
}

// Main analysis
async function analyze() {
    console.log('\n========================================');
    console.log('Human Strategy Analysis');
    console.log('========================================\n');

    const dbPath = path.join(__dirname, '..', 'data', 'zapzap.db');
    let db;

    try {
        db = sqlite3(dbPath);
    } catch (err) {
        console.error('Could not open database:', err.message);
        process.exit(1);
    }

    // Check if table exists
    const tableCheck = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='game_actions'").get();
    if (!tableCheck) {
        console.log('No game_actions table found. Play some games first!');
        console.log('\nThe action recording system has been set up. Now:');
        console.log('1. Start the server: npm start');
        console.log('2. Play some games against bots');
        console.log('3. Run this script again to analyze your strategies');
        process.exit(0);
    }

    // Get user ID if username provided
    let userId = null;
    if (username) {
        const userRow = db.prepare('SELECT id FROM users WHERE username = ?').get(username);
        if (!userRow) {
            console.error(`User "${username}" not found`);
            process.exit(1);
        }
        userId = userRow.id;
        console.log(`Analyzing actions for user: ${username}\n`);
    } else {
        console.log(`Analyzing all human actions (limit: ${limit})\n`);
    }

    // Get total action counts
    let whereClause = 'WHERE is_human = 1';
    const params = [];
    if (userId) {
        whereClause += ' AND user_id = ?';
        params.push(userId);
    }

    const totalActions = db.prepare(`SELECT COUNT(*) as count FROM game_actions ${whereClause}`).get(...params);
    console.log(`Total human actions recorded: ${totalActions.count}\n`);

    if (totalActions.count === 0) {
        console.log('No human actions recorded yet. Play some games first!');
        process.exit(0);
    }

    // ========================================
    // 1. PLAY ANALYSIS
    // ========================================
    console.log('--- PLAY STRATEGY ---\n');

    const playActions = db.prepare(`
        SELECT action_data, hand_before, hand_value_before, hand_value_after, opponent_hand_sizes
        FROM game_actions ${whereClause} AND action_type = 'play'
        ORDER BY created_at DESC LIMIT ?
    `).all(...params, limit);

    if (playActions.length > 0) {
        let singlePlays = 0;
        let multiPlays = 0;
        let handValueReductions = [];
        let singleWhenLowHand = 0; // Singles when hand value < 10
        let multiWhenHighHand = 0; // Combos when hand value > 20
        let playsWhenOpponentLow = 0; // Actions when opponent has small hand

        for (const action of playActions) {
            const data = JSON.parse(action.action_data);
            const handBefore = JSON.parse(action.hand_before);
            const opponentSizes = JSON.parse(action.opponent_hand_sizes);
            const minOpponentHandSize = Math.min(...opponentSizes);

            if (data.isSingle) {
                singlePlays++;
                if (action.hand_value_before < 10) singleWhenLowHand++;
            } else {
                multiPlays++;
                if (action.hand_value_before > 20) multiWhenHighHand++;
            }

            if (action.hand_value_after !== null) {
                const reduction = action.hand_value_before - action.hand_value_after;
                handValueReductions.push(reduction);
            }

            if (minOpponentHandSize <= 3) {
                playsWhenOpponentLow++;
            }
        }

        const avgReduction = handValueReductions.length > 0
            ? (handValueReductions.reduce((a, b) => a + b, 0) / handValueReductions.length).toFixed(1)
            : 'N/A';

        console.log(`Total plays: ${playActions.length}`);
        console.log(`  Singles: ${singlePlays} (${(singlePlays / playActions.length * 100).toFixed(1)}%)`);
        console.log(`  Multi-card: ${multiPlays} (${(multiPlays / playActions.length * 100).toFixed(1)}%)`);
        console.log(`  Average hand value reduction: ${avgReduction} points`);
        console.log(`  Singles when hand < 10: ${singleWhenLowHand} (preserving combos?)`);
        console.log(`  Combos when hand > 20: ${multiWhenHighHand} (burning high cards?)`);
        console.log(`  Plays when opponent hand size <= 3: ${playsWhenOpponentLow}`);
    }

    // ========================================
    // 2. DRAW ANALYSIS
    // ========================================
    console.log('\n--- DRAW STRATEGY ---\n');

    const drawActions = db.prepare(`
        SELECT action_data, hand_before, hand_value_before, last_cards_played, opponent_hand_sizes
        FROM game_actions ${whereClause} AND action_type = 'draw'
        ORDER BY created_at DESC LIMIT ?
    `).all(...params, limit);

    if (drawActions.length > 0) {
        let deckDraws = 0;
        let playedDraws = 0;
        let tookLowCards = 0; // Took card with value <= 3 from played
        let tookWhenOpponentLow = 0; // Drew from deck when opponent close to zapzap
        let couldChooseButTookDeck = 0;

        for (const action of drawActions) {
            const data = JSON.parse(action.action_data);
            const lastPlayed = JSON.parse(action.last_cards_played);
            const opponentSizes = JSON.parse(action.opponent_hand_sizes);
            const minOpponentHandSize = Math.min(...opponentSizes);

            if (data.fromDeck) {
                deckDraws++;
                if (lastPlayed.length > 0) {
                    couldChooseButTookDeck++;
                }
                if (minOpponentHandSize <= 3) {
                    tookWhenOpponentLow++;
                }
            } else {
                playedDraws++;
                const drawnCard = data.cardDrawn;
                if (getCardValue(drawnCard) <= 3 || isJoker(drawnCard)) {
                    tookLowCards++;
                }
            }
        }

        console.log(`Total draws: ${drawActions.length}`);
        console.log(`  From deck: ${deckDraws} (${(deckDraws / drawActions.length * 100).toFixed(1)}%)`);
        console.log(`  From played: ${playedDraws} (${(playedDraws / drawActions.length * 100).toFixed(1)}%)`);
        console.log(`  Took low cards (≤3) or jokers from played: ${tookLowCards}`);
        console.log(`  Could choose but took deck: ${couldChooseButTookDeck}`);
        console.log(`  Took from deck when opponent hand ≤ 3: ${tookWhenOpponentLow}`);
    }

    // ========================================
    // 3. ZAPZAP ANALYSIS
    // ========================================
    console.log('\n--- ZAPZAP STRATEGY ---\n');

    const zapzapActions = db.prepare(`
        SELECT action_data, hand_before, hand_value_before, opponent_hand_sizes, scores_before
        FROM game_actions ${whereClause} AND action_type = 'zapzap'
        ORDER BY created_at DESC LIMIT ?
    `).all(...params, limit);

    if (zapzapActions.length > 0) {
        let successful = 0;
        let counteracted = 0;
        let zapAtValue = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
        let zapWhenLeading = 0;
        let zapWhenBehind = 0;

        for (const action of zapzapActions) {
            const data = JSON.parse(action.action_data);
            const scores = JSON.parse(action.scores_before);
            const myScore = Object.values(scores)[0]; // Assuming player 0
            const otherScores = Object.values(scores).slice(1);
            const minOtherScore = Math.min(...otherScores);

            if (data.success) {
                successful++;
            } else {
                counteracted++;
            }

            const handValue = data.handPoints || action.hand_value_before;
            if (handValue >= 0 && handValue <= 5) {
                zapAtValue[handValue]++;
            }

            if (myScore < minOtherScore) {
                zapWhenLeading++;
            } else {
                zapWhenBehind++;
            }
        }

        console.log(`Total ZapZap calls: ${zapzapActions.length}`);
        console.log(`  Successful: ${successful} (${(successful / zapzapActions.length * 100).toFixed(1)}%)`);
        console.log(`  Counteracted: ${counteracted} (${(counteracted / zapzapActions.length * 100).toFixed(1)}%)`);
        console.log(`  ZapZap by hand value:`);
        for (let v = 0; v <= 5; v++) {
            if (zapAtValue[v] > 0) {
                console.log(`    ${v} points: ${zapAtValue[v]} times`);
            }
        }
        console.log(`  When leading in score: ${zapWhenLeading}`);
        console.log(`  When behind in score: ${zapWhenBehind}`);
    } else {
        console.log('No ZapZap actions recorded yet.');
    }

    // ========================================
    // 4. SUMMARY & RECOMMENDATIONS
    // ========================================
    console.log('\n========================================');
    console.log('STRATEGIC INSIGHTS');
    console.log('========================================\n');

    if (playActions.length > 0 || drawActions.length > 0 || zapzapActions.length > 0) {
        console.log('Based on your play patterns, key strategies identified:\n');

        // Play strategy insights
        if (playActions.length > 0) {
            const singleRatio = playActions.filter(a => JSON.parse(a.action_data).isSingle).length / playActions.length;
            if (singleRatio > 0.6) {
                console.log('* PRESERVE_COMBOS: You prefer single card plays (', (singleRatio * 100).toFixed(0), '%)');
                console.log('  This keeps pairs/sequences available for big plays later');
            } else if (singleRatio < 0.4) {
                console.log('* BURN_COMBOS: You prefer multi-card plays (', ((1 - singleRatio) * 100).toFixed(0), '%)');
                console.log('  This reduces hand value quickly');
            }
        }

        // Draw strategy insights
        if (drawActions.length > 0) {
            const deckRatio = drawActions.filter(a => JSON.parse(a.action_data).fromDeck).length / drawActions.length;
            if (deckRatio > 0.7) {
                console.log('* PREFER_DECK: You mostly draw from deck (', (deckRatio * 100).toFixed(0), '%)');
                console.log('  Unknown card reduces predictability');
            } else if (deckRatio < 0.5) {
                console.log('* PREFER_PLAYED: You often take from played cards (', ((1 - deckRatio) * 100).toFixed(0), '%)');
                console.log('  Picking known low cards when available');
            }
        }

        // ZapZap strategy insights
        if (zapzapActions.length > 0) {
            const successRate = zapzapActions.filter(a => JSON.parse(a.action_data).success).length / zapzapActions.length;
            if (successRate > 0.7) {
                console.log('* CONSERVATIVE_ZAPZAP: High success rate (', (successRate * 100).toFixed(0), '%)');
                console.log('  You wait for safe opportunities');
            } else if (successRate < 0.5) {
                console.log('* AGGRESSIVE_ZAPZAP: Lower success rate (', (successRate * 100).toFixed(0), '%)');
                console.log('  You take risks to end rounds quickly');
            }
        }
    }

    console.log('\n--- Analysis Complete ---\n');
    db.close();
}

analyze().catch(console.error);
