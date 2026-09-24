/**
 * Starts the legacy Node backend and the Rust backend side by side, each on a free
 * port with its own scratch SQLite file, and stops them.
 *
 * Both run with their working directory in the temp dir: neither reads the checkout's
 * .env (dotenv / dotenvy load it from the cwd) and Node's winston logs land there too.
 */

const { spawn } = require('node:child_process');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../../..');
const JWT_SECRET = 'parity-secret';
const ADMIN_PASSWORD = 'parity-admin-pw';
const RUST_BIN = process.env.PARITY_RUST_BIN
    || path.join(ROOT, 'zapzap-rust/target/release/zapzap-backend');

function freePort() {
    return new Promise((resolve, reject) => {
        const srv = net.createServer();
        srv.unref();
        srv.on('error', reject);
        srv.listen(0, '127.0.0.1', () => {
            const { port } = srv.address();
            srv.close(() => resolve(port));
        });
    });
}

/**
 * Waits for /api/health, and for `bound` in the backend's output when given: a health
 * answer alone may come from another process on that port.
 */
async function waitHealthy(name, base, child, logs, bound, timeoutMs = 30000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        if (child.exitCode !== null) {
            throw new Error(`${name} exited with ${child.exitCode} before /api/health answered:\n${logs.join('')}`);
        }
        try {
            const res = await fetch(`${base}/api/health`);
            if (res.ok && (!bound || logs.join('').includes(bound))) return;
        } catch {
            // not listening yet
        }
        await new Promise((r) => setTimeout(r, 200));
    }
    throw new Error(`${name} did not answer /api/health within ${timeoutMs} ms:\n${logs.join('')}`);
}

function launch(name, cmd, args, env, cwd) {
    const logs = [];
    const child = spawn(cmd, args, {
        cwd,
        env: { PATH: process.env.PATH, HOME: process.env.HOME, ...env },
        stdio: ['ignore', 'pipe', 'pipe'],
    });
    const keep = (chunk) => {
        logs.push(chunk.toString());
        if (logs.length > 400) logs.shift();
    };
    child.stdout.on('data', keep);
    child.stderr.on('data', keep);
    return { child, logs };
}

/**
 * @returns {Promise<{node: {base, dbPath, death}, rust: {base, dbPath, death}, tmp, stop: Function}>}
 */
async function startBackends() {
    // A port found free can be taken by another process before the backend binds it; the
    // backend then exits, while /api/health may have been answered by the other process.
    for (let attempt = 1; ; attempt++) {
        const started = await startOnce();
        await new Promise((r) => setTimeout(r, 500));
        const dead = [started.node, started.rust].find((b) => b.death());
        if (!dead) return started;
        await started.stop();
        if (attempt === 3) throw new Error(`the ${dead.name} backend ${dead.death()}`);
    }
}

async function startOnce() {
    if (!fs.existsSync(RUST_BIN)) {
        throw new Error(`Rust binary not found: ${RUST_BIN}\n`
            + 'Build it with `cd zapzap-rust && cargo build --release`, or set PARITY_RUST_BIN.');
    }
    // tmpfs when there is one: every game action is a SQLite write, and fsync on a disk
    // triples the suite's time.
    const scratch = fs.existsSync('/dev/shm') ? '/dev/shm' : os.tmpdir();
    const tmp = fs.mkdtempSync(path.join(scratch, 'zapzap-parity-'));
    const nodeDb = path.join(tmp, 'node.db');
    const rustDb = path.join(tmp, 'rust.db');
    const nodePort = await freePort();
    let rustPort = await freePort();
    while (rustPort === nodePort) rustPort = await freePort();

    const common = { JWT_SECRET, ADMIN_PASSWORD, NODE_ENV: 'test', BOT_ACTION_DELAY_MS: '0' };
    const node = launch('node', process.execPath, [path.join(ROOT, 'app.js')],
        { ...common, PORT: String(nodePort), DB_PATH: nodeDb }, tmp);
    // mode=rwc: sqlx creates the file (the default mode refuses a missing database).
    const rust = launch('rust', RUST_BIN, [],
        { ...common, PORT: String(rustPort), DATABASE_URL: `sqlite:${rustDb}?mode=rwc`, RUST_LOG: 'warn' }, tmp);

    const stop = async () => {
        for (const { child } of [node, rust]) {
            if (child.exitCode === null) child.kill('SIGKILL');
        }
        await new Promise((r) => setTimeout(r, 100));
        fs.rmSync(tmp, { recursive: true, force: true });
    };

    try {
        const nodeBase = `http://127.0.0.1:${nodePort}`;
        const rustBase = `http://127.0.0.1:${rustPort}`;
        await Promise.all([
            // src/api/server.js prints the port once it listens.
            waitHealthy('node', nodeBase, node.child, node.logs, `Port: ${nodePort}`),
            waitHealthy('rust', rustBase, rust.child, rust.logs),
        ]);
        // Why a backend is gone, if it died during the run: its exit code and last output.
        const death = ({ child, logs }) => () => (child.exitCode === null && child.signalCode === null ? null
            : `exited (${child.exitCode ?? child.signalCode}); last output:\n${logs.slice(-40).join('')}`);
        return {
            node: { name: 'node', base: nodeBase, dbPath: nodeDb, death: death(node) },
            rust: { name: 'rust', base: rustBase, dbPath: rustDb, death: death(rust) },
            tmp,
            stop,
        };
    } catch (err) {
        await stop();
        throw err;
    }
}

module.exports = { startBackends, ADMIN_PASSWORD, ROOT };
