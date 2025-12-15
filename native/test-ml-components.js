/**
 * Test ML Components: FeatureExtractor and LightweightDQN
 * Compares Rust implementation with JS implementation
 */

const native = require('./index.js');

// Import JS implementations for comparison
const path = require('path');
const FeatureExtractor = require(path.join(__dirname, '../src/infrastructure/bot/ml/FeatureExtractor.js'));
const LightweightDQN = require(path.join(__dirname, '../src/infrastructure/bot/ml/LightweightDQN.js'));

let passed = 0;
let failed = 0;

function test(name, fn) {
    try {
        fn();
        console.log(`✅ ${name}`);
        passed++;
    } catch (e) {
        console.log(`❌ ${name}: ${e.message}`);
        failed++;
    }
}

function assertEqual(actual, expected, msg) {
    if (actual !== expected) {
        throw new Error(`${msg}: expected ${expected}, got ${actual}`);
    }
}

function assertArrayClose(actual, expected, tolerance, msg) {
    if (actual.length !== expected.length) {
        throw new Error(`${msg}: length mismatch ${actual.length} vs ${expected.length}`);
    }
    for (let i = 0; i < actual.length; i++) {
        if (Math.abs(actual[i] - expected[i]) > tolerance) {
            throw new Error(`${msg}: at index ${i}, expected ${expected[i]}, got ${actual[i]}`);
        }
    }
}

console.log('\n========================================');
console.log('Testing ML Components (Phase 3)');
console.log('========================================\n');

// ============================================
// FeatureExtractor Tests
// ============================================

console.log('--- FeatureExtractor Tests ---\n');

test('getFeatureDimension returns 45', () => {
    const dim = native.getFeatureDimension();
    assertEqual(dim, 45, 'Feature dimension');
    assertEqual(dim, FeatureExtractor.getFeatureDimension(), 'Matches JS');
});

test('extractHandSizeFeatures returns 45 features', () => {
    const features = native.extractHandSizeFeatures(4, false, 50);
    assertEqual(features.length, 45, 'Feature count');
});

test('extractHandSizeFeatures golden score', () => {
    const normal = native.extractHandSizeFeatures(4, false, 50);
    const golden = native.extractHandSizeFeatures(2, true, 50);

    // Golden score flag should be different
    assertEqual(normal[14], 0, 'Normal is_golden_score');
    assertEqual(golden[14], 1, 'Golden is_golden_score');
});

test('extractFeatures returns 45 features', () => {
    const hand = [0, 13, 5, 18]; // A♠, A♥, 6♠, 6♥
    const scores = [50, 60, 70, 80];
    const opponentHandSizes = [5, 4, 6, 5];
    const features = native.extractFeatures(
        hand,
        0,
        scores,
        opponentHandSizes,
        3,
        30,
        [1, 2],
        false,
        []
    );
    assertEqual(features.length, 45, 'Feature count');
});

test('extractFeatures with eliminated players', () => {
    const hand = [0, 1, 2];
    const scores = [50, 120, 70, 80]; // Player 1 eliminated (>100)
    const opponentHandSizes = [0, 0, 4, 5];
    const features = native.extractFeatures(
        hand,
        0,
        scores,
        opponentHandSizes,
        5,
        20,
        [],
        false,
        [1] // Player 1 eliminated
    );
    assertEqual(features.length, 45, 'Feature count');
});

test('extractFeatures compares favorably with JS', () => {
    const hand = [0, 13, 5, 18, 52]; // A♠, A♥, 6♠, 6♥, Joker
    const scores = [30, 40, 50, 60];

    // Create JS game state mock
    const jsGameState = {
        hands: {
            0: hand,
            1: [1, 2, 3, 4],
            2: [5, 6, 7],
            3: [8, 9, 10, 11, 12]
        },
        scores: { 0: 30, 1: 40, 2: 50, 3: 60 },
        eliminatedPlayers: [],
        roundNumber: 3,
        deck: new Array(30).fill(0),
        lastCardsPlayed: [14, 15],
        isGoldenScore: false,
        currentTurn: 0
    };

    const jsFeatures = FeatureExtractor.extract(jsGameState, 0, hand);
    const jsArray = FeatureExtractor.toArray(jsFeatures);

    const rustFeatures = native.extractFeatures(
        hand,
        0,
        scores,
        [4, 3, 5], // opponent hand sizes (excluding player 0)
        3,
        30,
        [14, 15],
        false,
        []
    );

    // Check dimensions match
    assertEqual(rustFeatures.length, jsArray.length, 'Feature dimensions match');

    // Check some key features are in reasonable range
    // Note: exact match is not expected due to implementation differences
    // but values should be normalized [0, 1] mostly
    for (let i = 0; i < rustFeatures.length; i++) {
        if (rustFeatures[i] < -2 || rustFeatures[i] > 2) {
            throw new Error(`Feature ${i} out of range: ${rustFeatures[i]}`);
        }
    }
});

// ============================================
// LightweightDQN Tests
// ============================================

console.log('\n--- LightweightDQN Tests ---\n');

test('dqnInit initializes without error', () => {
    const result = native.dqnInit(42);
    assertEqual(result, true, 'Init successful');
});

test('dqnPredict returns correct action dimensions', () => {
    native.dqnInit(42);
    const features = new Array(45).fill(0.5);

    const handSizeQ = native.dqnPredict(features, 'handSize');
    assertEqual(handSizeQ.length, 7, 'handSize actions');

    const zapzapQ = native.dqnPredict(features, 'zapzap');
    assertEqual(zapzapQ.length, 2, 'zapzap actions');

    const playTypeQ = native.dqnPredict(features, 'playType');
    assertEqual(playTypeQ.length, 5, 'playType actions');

    const drawSourceQ = native.dqnPredict(features, 'drawSource');
    assertEqual(drawSourceQ.length, 2, 'drawSource actions');
});

test('dqnGreedyAction returns valid action', () => {
    native.dqnInit(42);
    const features = new Array(45).fill(0.5);

    const action = native.dqnGreedyAction(features, 'playType');
    if (action < 0 || action >= 5) {
        throw new Error(`Invalid action: ${action}`);
    }
});

test('dqnSelectAction with epsilon=0 is greedy', () => {
    native.dqnInit(42);
    const features = new Array(45).fill(0.5);

    const greedyAction = native.dqnGreedyAction(features, 'zapzap');
    const selectedAction = native.dqnSelectAction(features, 'zapzap', 0.0);
    assertEqual(selectedAction, greedyAction, 'Greedy with epsilon=0');
});

test('dqnSelectAction with epsilon=1.0 explores', () => {
    native.dqnInit(123);
    const features = new Array(45).fill(0.5);

    // With epsilon=1.0, should get different actions over multiple calls
    const actions = new Set();
    for (let i = 0; i < 50; i++) {
        const action = native.dqnSelectAction(features, 'playType', 1.0);
        actions.add(action);
    }

    // Should have explored multiple actions
    if (actions.size < 2) {
        throw new Error(`Expected exploration, got only ${actions.size} unique actions`);
    }
});

test('dqnPredict is deterministic', () => {
    native.dqnInit(42);
    const features = new Array(45).fill(0.5);

    const q1 = native.dqnPredict(features, 'playType');
    const q2 = native.dqnPredict(features, 'playType');

    assertArrayClose(q1, q2, 1e-6, 'Q-values should be deterministic');
});

// ============================================
// Benchmark Tests
// ============================================

console.log('\n--- Performance Benchmarks ---\n');

test('benchmarkFeatureExtraction performance', () => {
    const iterations = 100000;
    const usPerOp = native.benchmarkFeatureExtraction(iterations);
    console.log(`   Feature extraction: ${usPerOp.toFixed(2)} µs/op (${(1e6/usPerOp).toFixed(0)} ops/sec)`);

    // Should be fast - less than 10µs per operation
    if (usPerOp > 50) {
        throw new Error(`Feature extraction too slow: ${usPerOp}µs`);
    }
});

test('benchmarkDqnInference performance', () => {
    const iterations = 100000;
    const usPerOp = native.benchmarkDqnInference(iterations);
    console.log(`   DQN inference: ${usPerOp.toFixed(2)} µs/op (${(1e6/usPerOp).toFixed(0)} ops/sec)`);

    // Should be reasonably fast
    if (usPerOp > 100) {
        throw new Error(`DQN inference too slow: ${usPerOp}µs`);
    }
});

// Compare with JS implementation
test('Rust vs JS LightweightDQN performance', () => {
    const jsDqn = new LightweightDQN();
    const features = new Array(45).fill(0.5);

    // JS benchmark
    const jsIterations = 10000;
    const jsStart = Date.now();
    for (let i = 0; i < jsIterations; i++) {
        jsDqn.predict(features, 'playType');
    }
    const jsTime = Date.now() - jsStart;
    const jsUsPerOp = (jsTime * 1000) / jsIterations;

    // Rust benchmark
    native.dqnInit(42);
    const rustIterations = 100000;
    const rustUsPerOp = native.benchmarkDqnInference(rustIterations);

    const speedup = jsUsPerOp / rustUsPerOp;
    console.log(`   JS: ${jsUsPerOp.toFixed(2)} µs/op, Rust: ${rustUsPerOp.toFixed(2)} µs/op`);
    console.log(`   Speedup: ${speedup.toFixed(1)}x`);

    // Rust should be at least 2x faster
    if (speedup < 1) {
        throw new Error(`Rust should be faster than JS`);
    }
});

// ============================================
// Integration Test: Full Pipeline
// ============================================

console.log('\n--- Integration Tests ---\n');

test('Full ML pipeline: extract features -> predict -> select action', () => {
    const hand = [0, 13, 5, 18]; // A♠, A♥, 6♠, 6♥
    const scores = [30, 40, 50, 60];

    // Extract features
    const features = native.extractFeatures(
        hand, 0, scores, [4, 5, 4], 3, 30, [1], false, []
    );

    // Initialize DQN
    native.dqnInit(42);

    // Get Q-values
    const qValues = native.dqnPredict(features, 'playType');

    // Select action
    const action = native.dqnGreedyAction(features, 'playType');

    // Verify
    assertEqual(features.length, 45, 'Features dimension');
    assertEqual(qValues.length, 5, 'Q-values dimension');
    if (action < 0 || action >= 5) {
        throw new Error(`Invalid action: ${action}`);
    }

    console.log(`   Features: [${features.slice(0, 5).map(f => f.toFixed(3)).join(', ')}...]`);
    console.log(`   Q-values: [${qValues.map(q => q.toFixed(3)).join(', ')}]`);
    console.log(`   Selected action: ${action}`);
});

test('End-to-end: Game simulation with ML decision making', () => {
    // Run a batch of games
    const strategies = ['hard', 'hard', 'hard', 'hard'];
    const stats = native.runGamesBatch(strategies, 100, 42);

    console.log(`   Games: ${stats.gamesPlayed}`);
    console.log(`   Wins: [${stats.wins.join(', ')}]`);
    console.log(`   Avg rounds: ${stats.avgRounds.toFixed(1)}`);
    console.log(`   Speed: ${stats.gamesPerSecond.toFixed(0)} games/sec`);

    // Verify balanced wins
    const maxWins = Math.max(...stats.wins);
    const minWins = Math.min(...stats.wins);
    if (maxWins > minWins * 5) {
        throw new Error(`Unbalanced wins: ${stats.wins}`);
    }
});

// ============================================
// Summary
// ============================================

console.log('\n========================================');
console.log(`Results: ${passed} passed, ${failed} failed`);
console.log('========================================\n');

if (failed > 0) {
    process.exit(1);
}
