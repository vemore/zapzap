/**
 * Presence: a user is online while at least one of their event streams is
 * open, and the stream that brings a user online hears its own userConnected.
 */

const events = require('events');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

const SessionManager = require('../../../src/infrastructure/services/SessionManager');

describe('SessionManager stream count', () => {
    it('keeps a user online until their last stream closes', () => {
        const sessions = new SessionManager();

        expect(sessions.connect('u1', 'alice')).not.toBeNull();
        expect(sessions.connect('u1', 'alice')).toBeNull();

        expect(sessions.disconnect('u1')).toBeNull();
        expect(sessions.isConnected('u1')).toBe(true);

        expect(sessions.disconnect('u1')).toMatchObject({ userId: 'u1' });
        expect(sessions.isConnected('u1')).toBe(false);
        expect(sessions.disconnect('u1')).toBeNull();
    });

    it('keeps the status of a user who opens a second stream', () => {
        const sessions = new SessionManager();
        sessions.connect('u1', 'alice');
        sessions.updateStatus('u1', 'game', 'p1');

        sessions.connect('u1', 'alice');

        expect(sessions.getSession('u1')).toMatchObject({ status: 'game', partyId: 'p1' });
    });
});

describe('GET /suscribeupdate presence', () => {
    const saved = process.env.DB_PATH;
    let tmp;
    let container;
    let server;
    let base;
    let jwtService;
    let shutdown;
    const streams = [];

    beforeAll(async () => {
        tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'zapzap-presence-'));
        process.env.DB_PATH = path.join(tmp, 'scratch.db');
        const bootstrapModule = require('../../../src/api/bootstrap');
        shutdown = bootstrapModule.shutdown;
        const { createApp } = require('../../../src/api/server');
        container = await bootstrapModule.bootstrap();
        jwtService = container.resolve('jwtService');
        const app = createApp(container, new events.EventEmitter());
        server = await new Promise((resolve) => {
            const listening = app.listen(0, '127.0.0.1', () => resolve(listening));
        });
        base = `http://127.0.0.1:${server.address().port}`;
    });

    afterEach(() => {
        while (streams.length) streams.pop().close();
    });

    afterAll(async () => {
        await new Promise((resolve) => server.close(resolve));
        await shutdown(container);
        if (saved === undefined) delete process.env.DB_PATH;
        else process.env.DB_PATH = saved;
        fs.rmSync(tmp, { recursive: true, force: true });
    });

    // Opens a stream with the user's token; resolves once the greeting is in.
    // `received` collects the JSON of every `event: event` it gets.
    function openStream(userId, username) {
        const token = jwtService.sign({ userId, username });
        return new Promise((resolve, reject) => {
            const request = http.get(`${base}/suscribeupdate?token=${token}`, (res) => {
                const stream = {
                    received: [],
                    close: () => request.destroy(),
                };
                let buffer = '';
                res.setEncoding('utf8');
                res.on('data', (chunk) => {
                    buffer += chunk;
                    let end;
                    while ((end = buffer.indexOf('\n\n')) >= 0) {
                        const block = buffer.slice(0, end);
                        buffer = buffer.slice(end + 2);
                        const data = block.split('\n').find((line) => line.startsWith('data: '));
                        if (block.includes('event: event') && data) {
                            stream.received.push(JSON.parse(data.slice(6)));
                        }
                        if (block.includes('event: connected')) resolve(stream);
                    }
                });
                streams.push(stream);
            });
            request.on('error', (error) => {
                if (error.code !== 'ECONNRESET') reject(error);
            });
        });
    }

    async function connectedIds() {
        const response = await fetch(`${base}/api/players/connected`);
        const { players } = await response.json();
        return players.map((player) => player.userId);
    }

    const settle = () => new Promise((resolve) => setTimeout(resolve, 100));

    it('sends a stream its own userConnected', async () => {
        const stream = await openStream('alice-id', 'alice');
        await settle();

        expect(stream.received).toEqual([
            expect.objectContaining({ type: 'userConnected', userId: 'alice-id', username: 'alice' }),
        ]);
        expect(await connectedIds()).toEqual(['alice-id']);
    });

    it('keeps a user connected when one of two streams closes', async () => {
        const first = await openStream('bob-id', 'bobby');
        const second = await openStream('bob-id', 'bobby');
        await settle();

        second.close();
        await settle();

        expect(await connectedIds()).toContain('bob-id');
        expect(first.received.map((event) => event.type)).toEqual(['userConnected']);

        first.close();
        await settle();
        expect(await connectedIds()).not.toContain('bob-id');
    });
});
