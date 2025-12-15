/**
 * Benchmark: JavaScript vs Rust CardAnalyzer
 * Measures performance difference between implementations
 */

const native = require('./index.js');
const CardAnalyzer = require('../src/infrastructure/bot/CardAnalyzer');

// Generate random hand
function randomHand(size = 7) {
  const cards = [];
  const available = Array.from({ length: 54 }, (_, i) => i);
  for (let i = 0; i < size; i++) {
    const idx = Math.floor(Math.random() * available.length);
    cards.push(available.splice(idx, 1)[0]);
  }
  return cards;
}

// Benchmark function
function benchmark(name, fn, iterations) {
  // Warmup
  for (let i = 0; i < Math.min(1000, iterations / 10); i++) {
    fn();
  }

  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) {
    fn();
  }
  const end = process.hrtime.bigint();

  const totalMs = Number(end - start) / 1_000_000;
  const avgUs = (totalMs * 1000) / iterations;

  return { name, iterations, totalMs, avgUs };
}

console.log('=== CardAnalyzer Performance Benchmark ===\n');
console.log('Generating test data...');

// Generate test hands
const hands = Array.from({ length: 1000 }, () => randomHand(7));
const singleHand = hands[0];

console.log(`Test data: ${hands.length} random 7-card hands\n`);

// ---- findAllValidPlays Benchmark ----
console.log('--- findAllValidPlays (critical path) ---');
const iterations1 = 10000;

const jsResult1 = benchmark(
  'JavaScript',
  () => CardAnalyzer.findAllValidPlays(singleHand),
  iterations1
);

const rustResult1 = benchmark(
  'Rust',
  () => native.findAllValidPlays(singleHand),
  iterations1
);

console.log(`  JavaScript: ${jsResult1.avgUs.toFixed(2)} µs/call (${jsResult1.totalMs.toFixed(1)} ms total)`);
console.log(`  Rust:       ${rustResult1.avgUs.toFixed(2)} µs/call (${rustResult1.totalMs.toFixed(1)} ms total)`);
console.log(`  Speedup:    ${(jsResult1.avgUs / rustResult1.avgUs).toFixed(1)}x faster\n`);

// ---- calculateHandValue Benchmark (hot path) ----
console.log('--- calculateHandValue (very hot path) ---');
const iterations2 = 100000;

const jsResult2 = benchmark(
  'JavaScript',
  () => CardAnalyzer.calculateHandValue(singleHand),
  iterations2
);

const rustResult2 = benchmark(
  'Rust',
  () => native.calculateHandValue(singleHand),
  iterations2
);

console.log(`  JavaScript: ${jsResult2.avgUs.toFixed(3)} µs/call (${jsResult2.totalMs.toFixed(1)} ms total)`);
console.log(`  Rust:       ${rustResult2.avgUs.toFixed(3)} µs/call (${rustResult2.totalMs.toFixed(1)} ms total)`);
console.log(`  Speedup:    ${(jsResult2.avgUs / rustResult2.avgUs).toFixed(1)}x faster\n`);

// ---- Batch processing ----
console.log('--- Batch processing (1000 different hands) ---');

const jsResult3 = benchmark(
  'JavaScript',
  () => hands.forEach(h => CardAnalyzer.findAllValidPlays(h)),
  100
);

const rustResult3 = benchmark(
  'Rust',
  () => hands.forEach(h => native.findAllValidPlays(h)),
  100
);

console.log(`  JavaScript: ${jsResult3.totalMs.toFixed(1)} ms for 100 batches`);
console.log(`  Rust:       ${rustResult3.totalMs.toFixed(1)} ms for 100 batches`);
console.log(`  Speedup:    ${(jsResult3.totalMs / rustResult3.totalMs).toFixed(1)}x faster\n`);

// ---- Native benchmark function ----
console.log('--- Rust internal benchmark (100K iterations) ---');
const rustBenchResult = native.benchmarkFindAllValidPlays(singleHand, 100000);
console.log(`  Total plays found: ${rustBenchResult}`);
console.log(`  (This bypasses N-API overhead)\n`);

// ---- Summary ----
console.log('=== Summary ===');
console.log(`findAllValidPlays: ${(jsResult1.avgUs / rustResult1.avgUs).toFixed(1)}x faster`);
console.log(`calculateHandValue: ${(jsResult2.avgUs / rustResult2.avgUs).toFixed(1)}x faster`);
console.log(`Batch (1000 hands): ${(jsResult3.totalMs / rustResult3.totalMs).toFixed(1)}x faster`);

const avgSpeedup = (
  (jsResult1.avgUs / rustResult1.avgUs) +
  (jsResult2.avgUs / rustResult2.avgUs) +
  (jsResult3.totalMs / rustResult3.totalMs)
) / 3;

console.log(`\nAverage speedup: ${avgSpeedup.toFixed(1)}x`);
console.log('\nNote: Real-world speedup depends on N-API call frequency.');
console.log('For simulation with batched operations, expect 10-50x improvement.');
