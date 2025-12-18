#!/usr/bin/env node
/**
 * analyze-human-deep.js - Deep analysis of human winning patterns
 *
 * Identifies specific situations where human decisions differ from HardBot
 * and correlate with winning outcomes.
 */

const path = require('path');
const sqlite3 = require('better-sqlite3');

// Card utilities
function getCardValue(cardId) {
    if (cardId >= 52) return 0; // Joker
    const rank = cardId % 13;
    if (rank === 0) return 1; // Ace
    if (rank >= 10) return rank + 1;
    return rank + 1;
}

function calculateHandValue(hand) {
    return hand.reduce((sum, c) => sum + getCardValue(c), 0);
}

function isJoker(cardId) {
    return cardId >= 52;
}

function getCardSuit(cardId) {
    if (cardId >= 52) return 'joker';
    return ['spades', 'hearts', 'clubs', 'diamonds'][Math.floor(cardId / 13)];
}

function getCardRank(cardId) {
    if (cardId >= 52) return 'joker';
    const ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];
    return ranks[cardId % 13];
}

function cardToString(cardId) {
    if (cardId >= 52) return 'Joker';
    const suits = ['♠', '♥', '♣', '♦'];
    return getCardRank(cardId) + suits[Math.floor(cardId / 13)];
}

// Check if cards form a sequence
function isSequence(cards) {
    if (cards.length < 3) return false;
    const nonJokers = cards.filter(c => c < 52);
    if (nonJokers.length < 2) return false;

    const suits = nonJokers.map(c => Math.floor(c / 13));
    const uniqueSuits = [...new Set(suits)];
    if (uniqueSuits.length !== 1) return false;

    const ranks = cards.map(c => c < 52 ? c % 13 : -1).filter(r => r >= 0).sort((a, b) => a - b);
    for (let i = 1; i < ranks.length; i++) {
        if (ranks[i] - ranks[i-1] > 2) return false; // Allow one gap for joker
    }
    return true;
}

// Check if cards are same rank
function isSameRank(cards) {
    if (cards.length < 2) return false;
    const nonJokers = cards.filter(c => c < 52);
    if (nonJokers.length < 2) return false;

    const ranks = nonJokers.map(c => c % 13);
    return ranks.every(r => r === ranks[0]);
}

async function analyze() {
    console.log('\n' + '='.repeat(60));
    console.log('DEEP HUMAN STRATEGY ANALYSIS');
    console.log('='.repeat(60) + '\n');

    const dbPath = path.join(__dirname, '..', 'data', 'zapzap.db');
    let db;

    try {
        db = sqlite3(dbPath);
    } catch (err) {
        console.error('Could not open database:', err.message);
        process.exit(1);
    }

    const tableCheck = db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='game_actions'").get();
    if (!tableCheck) {
        console.log('No game_actions table found. Play some games first!');
        process.exit(0);
    }

    // Get all human actions
    const allActions = db.prepare(`
        SELECT * FROM game_actions
        WHERE is_human = 1
        ORDER BY party_id, round_number, turn_number
    `).all();

    console.log(`Total human actions: ${allActions.length}\n`);

    if (allActions.length === 0) {
        console.log('No actions recorded. Play some games first!');
        process.exit(0);
    }

    // ========================================
    // 1. PLAY DECISION ANALYSIS BY CONTEXT
    // ========================================
    console.log('-'.repeat(60));
    console.log('1. PLAY DECISIONS BY GAME CONTEXT');
    console.log('-'.repeat(60) + '\n');

    const playActions = allActions.filter(a => a.action_type === 'play');

    // Analyze by hand value ranges
    const playByHandValue = {
        'very_low': { range: '0-5', singles: 0, combos: 0 },
        'low': { range: '6-10', singles: 0, combos: 0 },
        'medium': { range: '11-20', singles: 0, combos: 0 },
        'high': { range: '21-30', singles: 0, combos: 0 },
        'very_high': { range: '31+', singles: 0, combos: 0 }
    };

    // Analyze by opponent proximity to ZapZap
    const playByOpponentState = {
        'opponent_1card': { singles: 0, combos: 0 },
        'opponent_2cards': { singles: 0, combos: 0 },
        'opponent_3cards': { singles: 0, combos: 0 },
        'opponent_4plus': { singles: 0, combos: 0 }
    };

    // Analyze specific play patterns
    const playPatterns = {
        keepJokerWhenClose: 0,      // Kept joker when could have played it, and close to ZapZap
        burnHighCard: 0,            // Played high card (J,Q,K) as single
        holdPair: 0,                // Had pair but played single instead
        playSequence: 0,            // Played 3+ card sequence
        playPair: 0,                // Played pair
        playSingleLow: 0,           // Played single low card (A-5)
        playSingleHigh: 0,          // Played single high card (10-K)
    };

    for (const action of playActions) {
        const data = JSON.parse(action.action_data);
        const handBefore = JSON.parse(action.hand_before);
        const opponentSizes = JSON.parse(action.opponent_hand_sizes);
        const minOpponentSize = Math.min(...opponentSizes);
        const handValue = action.hand_value_before;
        const playedCards = data.cardIds || [];

        // Categorize by hand value
        let valueCategory;
        if (handValue <= 5) valueCategory = 'very_low';
        else if (handValue <= 10) valueCategory = 'low';
        else if (handValue <= 20) valueCategory = 'medium';
        else if (handValue <= 30) valueCategory = 'high';
        else valueCategory = 'very_high';

        if (data.isSingle) {
            playByHandValue[valueCategory].singles++;
        } else {
            playByHandValue[valueCategory].combos++;
        }

        // Categorize by opponent state
        let opponentCategory;
        if (minOpponentSize <= 1) opponentCategory = 'opponent_1card';
        else if (minOpponentSize <= 2) opponentCategory = 'opponent_2cards';
        else if (minOpponentSize <= 3) opponentCategory = 'opponent_3cards';
        else opponentCategory = 'opponent_4plus';

        if (data.isSingle) {
            playByOpponentState[opponentCategory].singles++;
        } else {
            playByOpponentState[opponentCategory].combos++;
        }

        // Analyze specific patterns
        if (playedCards.length === 1) {
            const cardValue = getCardValue(playedCards[0]);
            if (cardValue <= 5) playPatterns.playSingleLow++;
            else if (cardValue >= 10) playPatterns.playSingleHigh++;

            // Check if burning high card
            if (cardValue >= 11) playPatterns.burnHighCard++;

            // Check if had pair but played single
            const ranks = handBefore.filter(c => c < 52).map(c => c % 13);
            const rankCounts = {};
            ranks.forEach(r => rankCounts[r] = (rankCounts[r] || 0) + 1);
            const hasPair = Object.values(rankCounts).some(c => c >= 2);
            if (hasPair) playPatterns.holdPair++;
        } else if (playedCards.length >= 2) {
            if (isSameRank(playedCards)) {
                playPatterns.playPair++;
            } else if (isSequence(playedCards)) {
                playPatterns.playSequence++;
            }
        }

        // Check joker handling
        const hasJoker = handBefore.some(c => c >= 52);
        const playedJoker = playedCards.some(c => c >= 52);
        if (hasJoker && !playedJoker && handValue <= 10) {
            playPatterns.keepJokerWhenClose++;
        }
    }

    console.log('Play type by hand value:');
    for (const [key, stats] of Object.entries(playByHandValue)) {
        const total = stats.singles + stats.combos;
        if (total > 0) {
            const singlePct = (stats.singles / total * 100).toFixed(0);
            console.log(`  ${stats.range} points: ${singlePct}% singles, ${100 - singlePct}% combos (n=${total})`);
        }
    }

    console.log('\nPlay type by opponent hand size:');
    for (const [key, stats] of Object.entries(playByOpponentState)) {
        const total = stats.singles + stats.combos;
        if (total > 0) {
            const singlePct = (stats.singles / total * 100).toFixed(0);
            console.log(`  ${key}: ${singlePct}% singles, ${100 - singlePct}% combos (n=${total})`);
        }
    }

    console.log('\nSpecific play patterns:');
    console.log(`  Kept joker when close to ZapZap: ${playPatterns.keepJokerWhenClose}`);
    console.log(`  Burned high card (J/Q/K) as single: ${playPatterns.burnHighCard}`);
    console.log(`  Had pair but played single instead: ${playPatterns.holdPair}`);
    console.log(`  Played sequence (3+ cards): ${playPatterns.playSequence}`);
    console.log(`  Played pair: ${playPatterns.playPair}`);
    console.log(`  Single low card (A-5): ${playPatterns.playSingleLow}`);
    console.log(`  Single high card (10-K): ${playPatterns.playSingleHigh}`);

    // ========================================
    // 2. DRAW DECISION ANALYSIS
    // ========================================
    console.log('\n' + '-'.repeat(60));
    console.log('2. DRAW DECISIONS BY CONTEXT');
    console.log('-'.repeat(60) + '\n');

    const drawActions = allActions.filter(a => a.action_type === 'draw');

    const drawByContext = {
        'joker_available': { deck: 0, played: 0 },
        'low_card_available': { deck: 0, played: 0 },
        'high_card_only': { deck: 0, played: 0 },
        'no_choice': { deck: 0, played: 0 }
    };

    const drawByHandValue = {
        'close_to_zapzap': { deck: 0, played: 0 }, // hand <= 10
        'medium': { deck: 0, played: 0 },          // 11-20
        'high': { deck: 0, played: 0 }              // 21+
    };

    for (const action of drawActions) {
        const data = JSON.parse(action.action_data);
        const lastPlayed = JSON.parse(action.last_cards_played);
        const handValue = action.hand_value_before;

        // Categorize available cards
        let context;
        if (lastPlayed.length === 0) {
            context = 'no_choice';
        } else {
            const hasJoker = lastPlayed.some(c => c >= 52);
            const hasLowCard = lastPlayed.some(c => c < 52 && getCardValue(c) <= 3);
            if (hasJoker) context = 'joker_available';
            else if (hasLowCard) context = 'low_card_available';
            else context = 'high_card_only';
        }

        if (data.fromDeck) {
            drawByContext[context].deck++;
        } else {
            drawByContext[context].played++;
        }

        // Categorize by hand value
        let handCategory;
        if (handValue <= 10) handCategory = 'close_to_zapzap';
        else if (handValue <= 20) handCategory = 'medium';
        else handCategory = 'high';

        if (data.fromDeck) {
            drawByHandValue[handCategory].deck++;
        } else {
            drawByHandValue[handCategory].played++;
        }
    }

    console.log('Draw source by available cards:');
    for (const [key, stats] of Object.entries(drawByContext)) {
        const total = stats.deck + stats.played;
        if (total > 0) {
            const deckPct = (stats.deck / total * 100).toFixed(0);
            console.log(`  ${key}: ${deckPct}% deck, ${100 - deckPct}% played (n=${total})`);
        }
    }

    console.log('\nDraw source by hand value:');
    for (const [key, stats] of Object.entries(drawByHandValue)) {
        const total = stats.deck + stats.played;
        if (total > 0) {
            const deckPct = (stats.deck / total * 100).toFixed(0);
            console.log(`  ${key}: ${deckPct}% deck, ${100 - deckPct}% played (n=${total})`);
        }
    }

    // ========================================
    // 3. ZAPZAP TIMING ANALYSIS
    // ========================================
    console.log('\n' + '-'.repeat(60));
    console.log('3. ZAPZAP TIMING ANALYSIS');
    console.log('-'.repeat(60) + '\n');

    const zapActions = allActions.filter(a => a.action_type === 'zapzap');

    const zapByOpponentState = {};
    const zapByTurnNumber = {};
    const zapSuccess = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };
    const zapFail = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0 };

    for (const action of zapActions) {
        const data = JSON.parse(action.action_data);
        const opponentSizes = JSON.parse(action.opponent_hand_sizes);
        const minOpponentSize = Math.min(...opponentSizes);
        const handValue = data.handPoints || action.hand_value_before;
        const turnNumber = action.turn_number;

        // Track by opponent state
        const opponentKey = `opp_${minOpponentSize}cards`;
        if (!zapByOpponentState[opponentKey]) {
            zapByOpponentState[opponentKey] = { success: 0, fail: 0 };
        }
        if (data.success) {
            zapByOpponentState[opponentKey].success++;
        } else {
            zapByOpponentState[opponentKey].fail++;
        }

        // Track by turn number
        const turnBucket = Math.floor(turnNumber / 5) * 5;
        const turnKey = `turn_${turnBucket}-${turnBucket + 4}`;
        if (!zapByTurnNumber[turnKey]) {
            zapByTurnNumber[turnKey] = { success: 0, fail: 0 };
        }
        if (data.success) {
            zapByTurnNumber[turnKey].success++;
        } else {
            zapByTurnNumber[turnKey].fail++;
        }

        // Track success/fail by hand value
        if (handValue >= 0 && handValue <= 5) {
            if (data.success) {
                zapSuccess[handValue]++;
            } else {
                zapFail[handValue]++;
            }
        }
    }

    console.log('ZapZap success rate by hand value:');
    for (let v = 0; v <= 5; v++) {
        const total = zapSuccess[v] + zapFail[v];
        if (total > 0) {
            const successPct = (zapSuccess[v] / total * 100).toFixed(0);
            console.log(`  ${v} points: ${successPct}% success (${zapSuccess[v]}/${total})`);
        }
    }

    console.log('\nZapZap success rate by opponent hand size:');
    for (const [key, stats] of Object.entries(zapByOpponentState)) {
        const total = stats.success + stats.fail;
        if (total > 0) {
            const successPct = (stats.success / total * 100).toFixed(0);
            console.log(`  ${key}: ${successPct}% success (${stats.success}/${total})`);
        }
    }

    console.log('\nZapZap success rate by turn number:');
    const sortedTurns = Object.entries(zapByTurnNumber).sort((a, b) => {
        const numA = parseInt(a[0].split('_')[1].split('-')[0]);
        const numB = parseInt(b[0].split('_')[1].split('-')[0]);
        return numA - numB;
    });
    for (const [key, stats] of sortedTurns) {
        const total = stats.success + stats.fail;
        if (total > 0) {
            const successPct = (stats.success / total * 100).toFixed(0);
            console.log(`  ${key}: ${successPct}% success (${stats.success}/${total})`);
        }
    }

    // ========================================
    // 4. KEY DIFFERENCES FROM HARDBOT
    // ========================================
    console.log('\n' + '-'.repeat(60));
    console.log('4. KEY STRATEGIC DIFFERENCES (vs HardBot)');
    console.log('-'.repeat(60) + '\n');

    // HardBot always plays optimal (minimizes remaining hand value)
    // HardBot ZapZaps whenever hand <= 5
    // HardBot draws from played if any card is available

    console.log('Your unique strategies that differ from HardBot:\n');

    // 1. Play strategy differences
    const totalPlays = playActions.length;
    const singlePlays = playActions.filter(a => JSON.parse(a.action_data).isSingle).length;
    const singlePct = (singlePlays / totalPlays * 100).toFixed(0);

    if (singlePct > 60) {
        console.log(`[PLAY] PRESERVE COMBOS: You play singles ${singlePct}% of the time`);
        console.log('       HardBot: Always plays to minimize remaining hand value');
        console.log('       ADVANTAGE: Keeps pairs/sequences for big plays later\n');
    }

    // 2. Hold pair pattern
    if (playPatterns.holdPair > 10) {
        const holdPairPct = (playPatterns.holdPair / singlePlays * 100).toFixed(0);
        console.log(`[PLAY] HOLD PAIRS: ${holdPairPct}% of your singles were when you had a pair`);
        console.log('       HardBot: Would play the pair to reduce hand value faster');
        console.log('       ADVANTAGE: Save pairs for opponent ZapZap situations\n');
    }

    // 3. Draw strategy
    if (drawByContext['joker_available']) {
        const jokerStats = drawByContext['joker_available'];
        const total = jokerStats.deck + jokerStats.played;
        if (total > 0 && jokerStats.played > jokerStats.deck) {
            console.log(`[DRAW] GRAB JOKERS: You take jokers ${((jokerStats.played/total)*100).toFixed(0)}% when available`);
            console.log('       HardBot: Would take any available card');
            console.log('       ADVANTAGE: Jokers = 0 points for ZapZap eligibility\n');
        }
    }

    // 4. ZapZap timing
    let conservativeZap = 0;
    let aggressiveZap = 0;
    for (let v = 0; v <= 2; v++) conservativeZap += zapSuccess[v] + zapFail[v];
    for (let v = 4; v <= 5; v++) aggressiveZap += zapSuccess[v] + zapFail[v];

    if (conservativeZap > aggressiveZap * 2) {
        console.log('[ZAPZAP] CONSERVATIVE TIMING: You prefer ZapZap at 0-2 points');
        console.log('         HardBot: ZapZaps at any value <= 5');
        console.log('         ADVANTAGE: Higher success rate, fewer counteractions\n');
    }

    // 5. Opponent awareness
    if (playByOpponentState['opponent_1card'].combos > playByOpponentState['opponent_4plus'].combos) {
        console.log('[PRESSURE] OPPONENT AWARENESS: You use more combos when opponent has 1 card');
        console.log('           HardBot: Same play style regardless of opponent state');
        console.log('           ADVANTAGE: Race to ZapZap before opponent\n');
    }

    // ========================================
    // 5. RECOMMENDED IMPROVEMENTS TO DRL
    // ========================================
    console.log('\n' + '='.repeat(60));
    console.log('RECOMMENDED DRL IMPROVEMENTS');
    console.log('='.repeat(60) + '\n');

    // Calculate actual thresholds from data
    const handValueThreshold = Object.entries(playByHandValue)
        .filter(([k, v]) => v.combos > v.singles)
        .map(([k]) => k)[0] || 'high';

    console.log('Based on your data, suggested DRL parameters:\n');
    console.log(`1. BURN_HIGH_THRESHOLD: ${handValueThreshold === 'very_high' ? 31 : handValueThreshold === 'high' ? 21 : 11}`);
    console.log(`   (Currently: 20, your data suggests: ${handValueThreshold})\n`);

    // ZapZap threshold
    const bestZapValue = Object.entries(zapSuccess)
        .filter(([v, count]) => count > 0)
        .sort((a, b) => {
            const rateA = zapSuccess[a[0]] / (zapSuccess[a[0]] + zapFail[a[0]]);
            const rateB = zapSuccess[b[0]] / (zapSuccess[b[0]] + zapFail[b[0]]);
            return rateB - rateA;
        })[0];

    if (bestZapValue) {
        console.log(`2. ZAPZAP_THRESHOLD: ${bestZapValue[0]} points`);
        console.log(`   (Best success rate at this value)\n`);
    }

    // Draw preference
    const lowCardDraw = drawByContext['low_card_available'];
    if (lowCardDraw) {
        const takeLowPct = lowCardDraw.played / (lowCardDraw.deck + lowCardDraw.played) * 100;
        console.log(`3. TAKE_LOW_CARDS: ${takeLowPct.toFixed(0)}% when available`);
        console.log(`   (Deck otherwise)\n`);
    }

    console.log('='.repeat(60) + '\n');
    db.close();
}

analyze().catch(console.error);
