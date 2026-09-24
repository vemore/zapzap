/**
 * bootstrap opens the database DB_PATH names, and data/zapzap.db without it.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

describe('bootstrap database path', () => {
    const saved = process.env.DB_PATH;
    let tmp;

    beforeEach(() => {
        tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'zapzap-bootstrap-'));
    });

    afterEach(() => {
        if (saved === undefined) delete process.env.DB_PATH;
        else process.env.DB_PATH = saved;
        fs.rmSync(tmp, { recursive: true, force: true });
        jest.resetModules();
    });

    it('opens the file DB_PATH names', async () => {
        const dbPath = path.join(tmp, 'scratch.db');
        process.env.DB_PATH = dbPath;
        const { bootstrap, shutdown } = require('../../../src/api/bootstrap');

        const container = await bootstrap();
        try {
            expect(container.resolve('database').dbPath).toBe(dbPath);
            expect(fs.existsSync(dbPath)).toBe(true);
        } finally {
            await shutdown(container);
        }
    });

    it('opens data/zapzap.db without DB_PATH', async () => {
        delete process.env.DB_PATH;
        // A connection that records its path and stops the bootstrap there, so that the
        // checkout's database is never opened by a test.
        const opened = [];
        jest.doMock('../../../src/infrastructure/database/sqlite/DatabaseConnection', () => {
            const Real = jest.requireActual('../../../src/infrastructure/database/sqlite/DatabaseConnection');
            return class extends Real {
                async initialize() {
                    opened.push(this.dbPath);
                    throw new Error('stop');
                }
            };
        });
        const { bootstrap } = require('../../../src/api/bootstrap');

        await expect(bootstrap()).rejects.toThrow('stop');
        expect(opened).toEqual([path.resolve(__dirname, '../../../data/zapzap.db')]);
    });
});
