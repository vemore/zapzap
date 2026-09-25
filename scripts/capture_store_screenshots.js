#!/usr/bin/env node
// ZapZap - the raw Play Store captures of one locale, driven by
// scripts/capture_store_screenshots.sh (which starts the backend on a seeded throwaway
// database and passes the arguments below; run it, not this file).
//
// 1. Through the API, as the demo users (demo123) and the seeded bots: two finished games
//    (for the history and the statistics), three open parties (the list), a lobby, and a
//    game in progress, played to the start of a turn of Vincent's in round 2.
// 2. In headless Chromium, in a 390x844 phone viewport at 3 device pixels (1170x2532),
//    with the browser's language set to the locale: the login screen, then — with the
//    session stored as the app stores it — the parties, the lobby, the board, the same
//    board once the round ends, the history and the statistics.
//
// The game is random (the backend shuffles), so each run shows other cards and scores.
// Usage: node scripts/capture_store_screenshots.js --locale fr-FR --api http://localhost:9971
//          --web-port 8871 --web-dir <flutter build web output> --out <raw dir>

'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const { chromium } = require('playwright');

const args = {};
for (let i = 2; i < process.argv.length; i += 2) {
  args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
}
for (const key of ['locale', 'api', 'web-port', 'web-dir', 'out']) {
  if (!args[key]) {
    console.error(`missing --${key}`);
    process.exit(2);
  }
}
const LOCALE = args.locale;
const LANG = LOCALE.split('-')[0];
const API = args.api.replace(/\/+$/, '');
const WEB_PORT = Number(args['web-port']);
const WEB_DIR = path.resolve(args['web-dir']);
const OUT = path.resolve(args.out);
const APP = `http://localhost:${WEB_PORT}/app`;
const PASSWORD = 'demo123'; // DEMO_USERS, zapzap-rust/src/infrastructure/database/seed.rs

// The fictional names shown on screen, per language: parties are data, not UI strings.
const NAMES = {
  fr: {
    finished: ['Tournoi du dimanche', 'Revanche'],
    open: ['Apéro cartes', 'Pause déjeuner'],
    lobby: 'Soirée du vendredi',
    game: 'Partie de famille',
  },
  en: {
    finished: ['Sunday tournament', 'Rematch'],
    open: ['Card night', 'Lunch break'],
    lobby: 'Friday night game',
    game: 'Family game',
  },
}[LANG];
if (!NAMES) {
  console.error(`no party names for the language ${LANG}`);
  process.exit(2);
}

// ------------------------------------------------------------------ the API

async function api(method, route, token, body) {
  const res = await fetch(`${API}/api${route}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    const err = new Error(`${method} ${route}: ${res.status} ${text.slice(0, 200)}`);
    err.status = res.status;
    err.body = json;
    throw err;
  }
  return json;
}

async function login(username) {
  const r = await api('POST', '/auth/login', null, { username, password: PASSWORD });
  return { token: r.token, user: r.user };
}

// Card ids as the backend's: 0-51 = suit id / 13, rank id % 13 + 1; 52, 53 jokers.
const isJoker = (id) => id >= 52;
const rank = (id) => (id % 13) + 1;
const suit = (id) => Math.floor(id / 13);
const points = (id) => (isJoker(id) ? 0 : rank(id));
const handValue = (hand) => hand.reduce((sum, id) => sum + points(id), 0);

// The human seats' strategy: the legal play (single, same-rank group, one-suit run)
// that sheds the most points, jokers kept; draw from the deck; ZapZap at 5 or less.
function bestPlay(hand) {
  const plain = hand.filter((id) => !isJoker(id));
  if (plain.length === 0) return [hand[0]];
  const candidates = plain.map((id) => [id]);
  const byRank = new Map();
  for (const id of plain) byRank.set(rank(id), [...(byRank.get(rank(id)) || []), id]);
  for (const group of byRank.values()) if (group.length >= 2) candidates.push(group);
  for (let s = 0; s < 4; s++) {
    const ranks = new Map(plain.filter((id) => suit(id) === s).map((id) => [rank(id), id]));
    for (let start = 1; start <= 11; start++) {
      const run = [];
      for (let r = start; ranks.has(r); r++) run.push(ranks.get(r));
      if (run.length >= 3) candidates.push(run);
    }
  }
  candidates.sort((a, b) => handValue(b) - handValue(a) || b.length - a.length);
  return candidates[0];
}

// Plays the party until `stop(state)` holds, each human seat by its own token and the
// bots through trigger-bot. `humans` maps a user id to a token; `zapzapBy`, when given,
// is the only user id that calls ZapZap; the `weak` user ids shed their lowest card.
async function playUntil(partyId, humans, stop, { zapzapBy = null, weak = [] } = {}) {
  const anyToken = Object.values(humans)[0];
  let refused = 0;
  for (let step = 0; step < 5000; step++) {
    try {
      const done = await playOneStep();
      if (done !== undefined) return done;
      refused = 0;
    } catch (e) {
      // GET state starts the bots in the background, so a move can race one of theirs
      // (NOT_YOUR_TURN, INVALID_ACTION_STATE, a party finished meanwhile): read again.
      if (!(e.status >= 400 && e.status < 500) || ++refused > 50) throw e;
      await new Promise((r) => setTimeout(r, 50));
    }
  }
  throw new Error(`party ${partyId}: no end after 5000 steps`);

  // One move; `undefined` to go on, else the value playUntil returns.
  async function playOneStep() {
    const party = await api('GET', `/party/${partyId}`, anyToken);
    const status = party.party ? party.party.status : party.status;
    if (status === 'finished') return null;
    const state = await api('GET', `/game/${partyId}/state`, anyToken);
    const gs = state.gameState;
    if (stop(state)) return state;
    if (gs.currentAction === 'finished') {
      await api('POST', `/game/${partyId}/nextRound`, anyToken);
      return undefined;
    }
    const seat = state.players.find((p) => p.playerIndex === gs.currentTurn);
    const token = seat && humans[seat.userId];
    if (!token) {
      await api('POST', `/game/${partyId}/trigger-bot`, anyToken);
      return undefined;
    }
    const mine = (await api('GET', `/game/${partyId}/state`, token)).gameState;
    const hand = mine.playerHand || [];
    const route = (r) => `/game/${partyId}/${r}`;
    if (mine.currentAction === 'selectHandSize') {
      await api('POST', route('selectHandSize'), token, { handSize: mine.isGoldenScore ? 6 : 5 });
    } else if (mine.currentAction === 'play') {
      const mayCall = zapzapBy === null || zapzapBy === seat.userId;
      if (mayCall && handValue(hand) <= 5) {
        await api('POST', route('zapzap'), token);
      } else {
        const lowest = [...hand].sort((a, b) => points(a) - points(b) || a - b)[0];
        const cardIds = weak.includes(seat.userId) ? [lowest] : bestPlay(hand);
        await api('POST', route('play'), token, { cardIds });
      }
    } else if (mine.currentAction === 'draw') {
      await api('POST', route('draw'), token, { source: 'deck' });
    }
    return undefined;
  }
}

async function createParty(owner, name, playerCount, botIds) {
  const r = await api('POST', '/party', owner.token, {
    name,
    visibility: 'public',
    settings: { playerCount },
    botIds,
  });
  return r.party.id;
}

async function setUp() {
  const [vincent, thibaut, simon, lyo] = await Promise.all(
    ['Vincent', 'Thibaut', 'Simon', 'Lyo'].map(login),
  );
  const bots = (await api('GET', '/bots')).bots;
  const bot = (name) => {
    const b = bots.find((x) => x.username === name);
    if (!b) throw new Error(`no bot ${name}`);
    return b.id;
  };

  // Two finished games for the history and the statistics: one Vincent wins against his
  // friends (only he calls ZapZap, they shed their lowest card), one against two bots.
  const friendly = await createParty(vincent, NAMES.finished[0], 3, []);
  await api('POST', `/party/${friendly}/join`, thibaut.token);
  await api('POST', `/party/${friendly}/join`, simon.token);
  await api('POST', `/party/${friendly}/start`, vincent.token);
  const trio = {
    [vincent.user.id]: vincent.token,
    [thibaut.user.id]: thibaut.token,
    [simon.user.id]: simon.token,
  };
  await playUntil(friendly, trio, () => false, {
    zapzapBy: vincent.user.id,
    weak: [thibaut.user.id, simon.user.id],
  });
  const rematch = await createParty(vincent, NAMES.finished[1], 4, [bot('MediumBot1'), bot('HardBot1')]);
  await api('POST', `/party/${rematch}/join`, thibaut.token);
  await api('POST', `/party/${rematch}/start`, vincent.token);
  await playUntil(rematch, { [vincent.user.id]: vincent.token, [thibaut.user.id]: thibaut.token }, () => false);
  console.log(`${LOCALE}: finished "${NAMES.finished[0]}" and "${NAMES.finished[1]}"`);

  // Open parties of other players, one of them with Vincent's friend waiting.
  await createParty(thibaut, NAMES.open[0], 5, [bot('EasyBot1')]);
  const lunch = await createParty(simon, NAMES.open[1], 4, []);
  await api('POST', `/party/${lunch}/join`, lyo.token);

  // Vincent's lobby: a friend, a bot, one seat free.
  const lobby = await createParty(vincent, NAMES.lobby, 4, [bot('HardBot2')]);
  await api('POST', `/party/${lobby}/join`, lyo.token);

  // The game in progress: Vincent, two friends and a bot, into round 2, Vincent to play
  // with at least one card on the table from the player before him.
  const game = await createParty(vincent, NAMES.game, 4, [bot('Thibot1')]);
  await api('POST', `/party/${game}/join`, thibaut.token);
  await api('POST', `/party/${game}/join`, simon.token);
  await api('POST', `/party/${game}/start`, vincent.token);
  const humans = {
    [vincent.user.id]: vincent.token,
    [thibaut.user.id]: thibaut.token,
    [simon.user.id]: simon.token,
  };
  const vincentSeat = (state) => state.players.find((p) => p.userId === vincent.user.id).playerIndex;
  const atPlay = await playUntil(game, humans, (state) => {
    const gs = state.gameState;
    return (
      state.round.roundNumber >= 2 &&
      gs.currentAction === 'play' &&
      gs.currentTurn === vincentSeat(state) &&
      (gs.lastCardsPlayed || []).length > 0 &&
      gs.lastAction && gs.lastAction.type === 'draw'
    );
  }, { zapzapBy: 'nobody' });
  if (!atPlay) throw new Error('the game in progress finished before round 2');
  return { vincent, humans, lobby, game };
}

// ------------------------------------------------------------------ the web build

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.css': 'text/css',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.frag': 'application/octet-stream',
  '.bin': 'application/octet-stream',
};

// The build under /app/, with the SPA fallback of frontend-flutter/nginx.conf: a path
// with no file extension is the app's index.html.
function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    if (!url.startsWith('/app/')) {
      res.writeHead(url === '/app' ? 301 : 404, url === '/app' ? { Location: '/app/' } : {});
      return res.end();
    }
    let file = path.join(WEB_DIR, url.slice('/app/'.length));
    if (!file.startsWith(WEB_DIR)) {
      res.writeHead(403);
      return res.end();
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      if (path.extname(url)) {
        res.writeHead(404);
        return res.end();
      }
      file = path.join(WEB_DIR, 'index.html');
    }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
      'Cache-Control': 'no-store',
    });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(WEB_PORT, '127.0.0.1', () => resolve(server)));
}

// ------------------------------------------------------------------ the captures

const SETTLE_MS = 3500; // after the load: the engine, fonts, the first frames, the SSE state

async function shot(page, name) {
  await page.waitForTimeout(SETTLE_MS);
  const file = path.join(OUT, `${name}.png`);
  await page.screenshot({ path: file });
  console.log(`${LOCALE}: ${name}.png`);
}

async function open(page, route) {
  await page.goto(`${APP}${route}`, { waitUntil: 'load' });
  await page.waitForSelector('flutter-view, flt-glass-pane', { timeout: 30000 });
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const { vincent, humans, lobby, game } = await setUp();
  const server = await serve();
  const browser = await chromium.launch();
  try {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 3,
      isMobile: true,
      hasTouch: true,
      locale: LOCALE,
      reducedMotion: 'reduce',
      colorScheme: 'dark',
    });
    const page = await context.newPage();
    page.on('pageerror', (e) => console.error(`${LOCALE}: page error: ${e.message}`));

    // Signed out: the login screen, the username typed in.
    await open(page, '/login');
    await page.waitForTimeout(SETTLE_MS);
    await page.keyboard.press('Tab');
    await page.keyboard.type('Vincent');
    await shot(page, '01_login');

    // Signed in as the app stores a session (shared_preferences: `flutter.` keys, JSON).
    await page.evaluate(
      ({ token, user }) => {
        localStorage.setItem('flutter.token', JSON.stringify(token));
        localStorage.setItem('flutter.user', JSON.stringify(JSON.stringify(user)));
      },
      { token: vincent.token, user: { ...vincent.user, isGoogleUser: false } },
    );

    await open(page, '/parties');
    await shot(page, '02_parties');

    await open(page, `/parties/${lobby}`);
    await shot(page, '03_lobby');

    await open(page, `/game/${game}`);
    await shot(page, '04_game');

    // The round played to its end, Vincent calling ZapZap when he can.
    await playUntil(game, humans, (state) => state.gameState.currentAction === 'finished', {
      zapzapBy: vincent.user.id,
    });
    await open(page, `/game/${game}`);
    await shot(page, '05_round_end');

    await open(page, '/history');
    await shot(page, '06_history');

    await open(page, '/stats');
    await shot(page, '07_stats');
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((e) => {
  console.error(e.stack || String(e));
  process.exit(1);
});
