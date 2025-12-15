/**
 * Test comparison: JavaScript vs Rust implementation
 * Verifies that both implementations produce identical results
 */

const native = require('./index.js');
const path = require('path');

// Import JS CardAnalyzer from main project
const CardAnalyzer = require('../src/infrastructure/bot/CardAnalyzer');

// Helper to sort plays for comparison
const sortPlays = (plays) =>
  plays.map(p => [...p].sort((a, b) => a - b))
       .sort((a, b) => a.length - b.length || a[0] - b[0]);

// Test cases
const testHands = [
  { name: 'Simple hand', cards: [0, 1, 2, 13] },  // A♠, 2♠, 3♠, A♥
  { name: 'With jokers', cards: [0, 1, 52, 53] }, // A♠, 2♠, 2 Jokers
  { name: 'All same rank', cards: [0, 13, 26, 39] }, // 4 Aces
  { name: 'Long sequence', cards: [0, 1, 2, 3, 4, 5, 6] }, // A-7 of spades
  { name: 'Mixed suits', cards: [0, 14, 28, 42, 5, 18] }, // A♠, 2♥, 3♣, 4♦, 6♠, 6♥
  { name: 'Empty hand', cards: [] },
  { name: 'Single card', cards: [25] },
  { name: 'Pair only', cards: [12, 25] }, // K♠, K♥
  { name: 'Full house-like', cards: [0, 13, 26, 1, 14] }, // AAA + 22
];

console.log('=== Comparison Tests: JavaScript vs Rust ===\n');

let passed = 0;
let failed = 0;

// Test 1: getCardPoints
console.log('--- Test: getCardPoints ---');
for (let cardId = 0; cardId <= 53; cardId++) {
  const jsResult = CardAnalyzer.getCardPoints(cardId);
  const rustResult = native.getCardPoints(cardId);
  if (jsResult !== rustResult) {
    console.log(`  FAIL: cardId=${cardId}, JS=${jsResult}, Rust=${rustResult}`);
    failed++;
  } else {
    passed++;
  }
}
console.log(`  ${passed} tests passed\n`);

// Test 2: calculateHandValue
console.log('--- Test: calculateHandValue ---');
for (const { name, cards } of testHands) {
  const jsResult = CardAnalyzer.calculateHandValue(cards);
  const rustResult = native.calculateHandValue(cards);
  if (jsResult !== rustResult) {
    console.log(`  FAIL ${name}: JS=${jsResult}, Rust=${rustResult}`);
    failed++;
  } else {
    console.log(`  OK ${name}: ${jsResult}`);
    passed++;
  }
}
console.log();

// Test 3: canCallZapZap
// Per game rules: hand must be <= 5 points (Jokers = 0 for eligibility)
console.log('--- Test: canCallZapZap ---');
const zapzapTestCases = [
  // From game rules documentation:
  { cards: [0, 14, 14], expected: true, desc: 'A♠, 2♥, 2♣ = 1+2+2 = 5' },        // A + 2 + 2 = 5 ✅
  { cards: [52, 28, 14], expected: true, desc: 'Joker, 3♦, 2♠ = 0+3+2 = 5' },    // Joker + 3 + 2 = 5 ✅
  { cards: [0, 13, 26, 39, 52], expected: true, desc: 'A♠,A♥,A♣,A♦,Joker = 4' }, // 1+1+1+1+0 = 4 ✅
  { cards: [2, 15], expected: false, desc: '3♠, 3♥ = 3+3 = 6' },                 // 3 + 3 = 6 ❌

  // Additional tests:
  { cards: [0, 1], expected: true, desc: 'A+2 = 3' },           // 1+2 = 3 <= 5
  { cards: [0, 1, 2], expected: false, desc: 'A+2+3 = 6' },     // 1+2+3 = 6 > 5
  { cards: [52, 53], expected: true, desc: '2 Jokers = 0' },    // 0+0 = 0 <= 5
  { cards: [52, 0, 1], expected: true, desc: 'Joker+A+2 = 3' }, // 0+1+2 = 3 <= 5
  { cards: [9, 10], expected: false, desc: '10+J = 21' },       // 10+11 = 21 > 5
];

for (const { cards, expected, desc } of zapzapTestCases) {
  const jsResult = CardAnalyzer.canCallZapZap(cards);
  const rustResult = native.canCallZapzap(cards);
  if (jsResult !== rustResult || jsResult !== expected) {
    console.log(`  FAIL ${desc}: JS=${jsResult}, Rust=${rustResult}, expected=${expected}`);
    failed++;
  } else {
    console.log(`  OK ${desc}: ${jsResult}`);
    passed++;
  }
}
console.log();

// Test 4: isValidSameRank
// Per game rules: Valid pairs/sets are same rank cards (Jokers act as wildcards)
console.log('--- Test: isValidSameRank ---');
const sameRankTests = [
  // From game rules documentation:
  { cards: [12, 25], expected: true, desc: 'K♠ K♥ (pair)' },           // K + K
  { cards: [0, 13, 26, 39], expected: true, desc: 'A♠ A♥ A♣ A♦ (quad)' }, // 4 Aces
  { cards: [5, 18, 52], expected: true, desc: '6♠ 6♥ Joker (set)' },   // 6 + 6 + Joker

  // Additional tests:
  { cards: [0, 13], expected: true, desc: 'Pair of Aces' },
  { cards: [0, 13, 26], expected: true, desc: '3 Aces' },
  { cards: [0, 1], expected: false, desc: 'A♠ 2♠ (different ranks)' },
  { cards: [0, 52], expected: true, desc: 'Ace + Joker' },
  { cards: [52, 53], expected: true, desc: 'Two Jokers' },
  { cards: [5], expected: false, desc: 'Single card (invalid)' },
];

for (const { cards, expected, desc } of sameRankTests) {
  const jsResult = CardAnalyzer.isValidSameRank(cards);
  const rustResult = native.isValidSameRank(cards);
  if (jsResult !== rustResult || jsResult !== expected) {
    console.log(`  FAIL ${desc}: JS=${jsResult}, Rust=${rustResult}, expected=${expected}`);
    failed++;
  } else {
    console.log(`  OK ${desc}: ${jsResult}`);
    passed++;
  }
}
console.log();

// Test 5: isValidSequence
// Per game rules: 3+ consecutive cards of SAME SUIT. Jokers fill gaps.
console.log('--- Test: isValidSequence ---');
const sequenceTests = [
  // From game rules documentation - VALID sequences:
  { cards: [4, 5, 6], expected: true, desc: '5♠ 6♠ 7♠ (same suit)' },
  { cards: [22, 23, 24, 25], expected: true, desc: '10♣ J♣ Q♣ K♣' },   // 10-K of clubs
  { cards: [14, 15, 16, 17, 18], expected: true, desc: '2♥ 3♥ 4♥ 5♥ 6♥' },

  // With Jokers filling gaps:
  { cards: [4, 52, 6], expected: true, desc: '5♠ Joker 7♠ (Joker=6♠)' },
  { cards: [22, 23, 52, 25], expected: true, desc: '10♣ J♣ Joker K♣ (Joker=Q♣)' },

  // From game rules documentation - INVALID sequences:
  { cards: [4, 18, 32], expected: false, desc: '5♠ 6♥ 7♣ (mixed suits)' },
  { cards: [4, 6, 8], expected: false, desc: '5♠ 7♠ 9♠ (not consecutive)' },
  { cards: [4, 5], expected: false, desc: '5♠ 6♠ (only 2 cards)' },

  // Additional tests:
  { cards: [0, 1, 2], expected: true, desc: 'A♠ 2♠ 3♠ (same suit)' },
  { cards: [0, 2, 52], expected: true, desc: 'A♠ 3♠ Joker (fills 2)' },
  { cards: [52, 53, 0], expected: true, desc: '2 Jokers + Ace' },
  { cards: [10, 11, 12], expected: true, desc: 'J♠ Q♠ K♠' },
];

for (const { cards, expected, desc } of sequenceTests) {
  const jsResult = CardAnalyzer.isValidSequence(cards);
  const rustResult = native.isValidSequence(cards);
  if (jsResult !== rustResult || jsResult !== expected) {
    console.log(`  FAIL ${desc}: JS=${jsResult}, Rust=${rustResult}, expected=${expected}`);
    failed++;
  } else {
    console.log(`  OK ${desc}: ${jsResult}`);
    passed++;
  }
}
console.log();

// Test 6: findAllValidPlays (most important)
console.log('--- Test: findAllValidPlays ---');
for (const { name, cards } of testHands) {
  const jsPlays = sortPlays(CardAnalyzer.findAllValidPlays(cards));
  const rustPlays = sortPlays(native.findAllValidPlays(cards));

  const jsStr = JSON.stringify(jsPlays);
  const rustStr = JSON.stringify(rustPlays);

  if (jsStr !== rustStr) {
    console.log(`  FAIL ${name}:`);
    console.log(`    JS   (${jsPlays.length}): ${jsStr.slice(0, 100)}...`);
    console.log(`    Rust (${rustPlays.length}): ${rustStr.slice(0, 100)}...`);
    failed++;
  } else {
    console.log(`  OK ${name}: ${jsPlays.length} plays`);
    passed++;
  }
}
console.log();

// Summary
console.log('=== Summary ===');
console.log(`Passed: ${passed}`);
console.log(`Failed: ${failed}`);
console.log(failed === 0 ? '\n✅ All tests passed!' : '\n❌ Some tests failed!');

process.exit(failed > 0 ? 1 : 0);
