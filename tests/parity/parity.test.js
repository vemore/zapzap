/**
 * Backend parity: the same HTTP scenarios against the legacy Node backend (the
 * reference, what production runs) and the Rust backend (the target), compared.
 *
 *   cd zapzap-rust && cargo build --release && cd .. && npm run test:parity
 *
 * Every difference must be listed in divergences.json, as a Node bug Rust rightly does
 * not copy ("node-bug") or as something Rust must still change ("pending"), with its
 * wip entry. The suite fails on a difference that is not listed, and on a listed one
 * that no longer occurs. PARITY_RUST_BIN overrides the Rust binary's path.
 */

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const sqlite3 = require('sqlite3');

const { startBackends, ADMIN_PASSWORD } = require('./lib/servers');
const { Recorder } = require('./lib/recorder');
const { compareRecorders, checkDivergences, report } = require('./lib/compare');
const scenarios = require('./scenarios');

const DIVERGENCES = path.join(__dirname, 'divergences.json');

/**
 * Node creates `admin` on startup (src/api/bootstrap.js, ADMIN_PASSWORD); Rust has no
 * such step. The same account is made on the Rust database: registered through the
 * API, then flagged admin in SQL.
 */
function sql(dbPath) {
    return (query, params = []) => new Promise((resolve, reject) => {
        const db = new sqlite3.Database(dbPath);
        db.run(query, params, (err) => {
            db.close();
            if (err) reject(err);
            else resolve();
        });
    });
}

async function seedRustAdmin(backend) {
    const res = await fetch(`${backend.base}/api/auth/register`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ username: 'admin', password: ADMIN_PASSWORD }),
    });
    assert.strictEqual(res.status, 201, `registering admin on Rust answered ${res.status}`);
    await sql(backend.dbPath)("UPDATE users SET is_admin = 1 WHERE username = 'admin'");
}

function loadDivergences() {
    const list = JSON.parse(fs.readFileSync(DIVERGENCES, 'utf8'));
    const ids = new Set();
    for (const d of list) {
        assert.ok(d.id && typeof d.id === 'string', `divergence without id: ${JSON.stringify(d)}`);
        assert.ok(!ids.has(d.id), `divergence listed twice: ${d.id}`);
        ids.add(d.id);
        assert.ok(['node-bug', 'pending'].includes(d.class), `${d.id}: class must be node-bug or pending`);
        assert.ok(d.wip && /\.md$/.test(d.wip), `${d.id}: wip must name the entry file`);
        if (d.class === 'node-bug') assert.ok(d.why, `${d.id}: a node-bug needs a one-line why`);
    }
    return list;
}

test('Node and Rust backends answer the same, but for the listed divergences', { timeout: 10 * 60 * 1000 }, async (t) => {
    const divergences = loadDivergences();
    const backends = await startBackends();
    t.after(() => backends.stop());
    await seedRustAdmin(backends.rust);

    const node = new Recorder('node', backends.node.base);
    const rust = new Recorder('rust', backends.rust.base);
    // What a scenario may use besides HTTP: the admin password, and SQL on the scratch
    // database for what the API cannot do (see scenarios.js).
    const ctx = {
        node: { adminPassword: ADMIN_PASSWORD, sql: sql(backends.node.dbPath) },
        rust: { adminPassword: ADMIN_PASSWORD, sql: sql(backends.rust.dbPath) },
    };

    for (const [name, run] of scenarios) {
        await Promise.all([node, rust].map(async (rec) => {
            const t0 = Date.now();
            try {
                await run(rec, ctx[rec.name]);
                if (process.env.PARITY_TIMING) t.diagnostic(`${name} on ${rec.name}: ${rec.requests} requests so far, ${Date.now() - t0} ms`);
            } catch (err) {
                // A scenario one backend cannot finish is a difference, not a crash of the suite.
                rec.value(`crash.${name}`, `${err.message}`);
            }
        }));
    }
    t.diagnostic(`game: ${ctx.node.gameRounds} round(s) on Node, ${ctx.rust.gameRounds} on Rust`);

    for (const b of [backends.node, backends.rust]) {
        const why = b.death();
        assert.ok(!why, `the ${b.name} backend ${why}`);
    }

    const differences = compareRecorders(node, rust);
    const result = checkDivergences(differences, divergences);
    t.diagnostic(`${differences.length} difference(s), ${result.matched.length} listed`);
    if (process.env.PARITY_DUMP) {
        fs.writeFileSync(process.env.PARITY_DUMP, JSON.stringify(differences, null, 2));
    }
    assert.ok(result.unexpected.length === 0 && result.stale.length === 0, `\n${report(node, rust, result)}`);
});
