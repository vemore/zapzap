/**
 * The HTTP scenarios, run in this order against each backend with the same recorder
 * labels. `ctx` carries what one scenario leaves to the next on the same backend, and
 * `ctx.sql` reaches its scratch database for the one thing the API cannot do.
 * Human-only parties: both backends play bots on their own, with no off switch.
 * Each step leaves both backends in the same state whatever they answered, so that one
 * difference does not cascade into the steps after it.
 */

const { playGame, points, HAND_SIZE, beforeDeal } = require('./lib/game');

const PASSWORD = 'secret123';
const UNKNOWN_ID = '00000000-0000-4000-8000-000000000000';
const SETTINGS = { playerCount: 3 };

async function register(rec, label, username) {
    const r = await rec.call(label, 'POST', '/api/auth/register', {
        body: { username, password: PASSWORD },
        values: ['success', 'user.username'],
    });
    return { token: r.body.token, id: r.body.user && r.body.user.id, username };
}

async function auth(rec, ctx) {
    ctx.users = {};
    for (const name of ['alice', 'bob', 'carol', 'dave', 'erin', 'frank', 'gina', 'hugo']) {
        ctx.users[name] = await register(rec, `auth.register.${name === 'alice' ? 'ok' : 'more'}`, name);
    }
    await rec.call('auth.register.duplicate', 'POST', '/api/auth/register', { body: { username: 'alice', password: PASSWORD } });
    await rec.call('auth.register.missing-password', 'POST', '/api/auth/register', { body: { username: 'zoe' } });
    await rec.call('auth.register.short-username', 'POST', '/api/auth/register', { body: { username: 'zo', password: PASSWORD } });
    await rec.call('auth.register.short-password', 'POST', '/api/auth/register', { body: { username: 'zoey', password: '123' } });
    await rec.call('auth.login.ok', 'POST', '/api/auth/login', {
        body: { username: 'alice', password: PASSWORD },
        values: ['success', 'user.username', 'user.isAdmin'],
    });
    await rec.call('auth.login.wrong-password', 'POST', '/api/auth/login', { body: { username: 'alice', password: 'nope-nope' } });
    await rec.call('auth.login.unknown-user', 'POST', '/api/auth/login', { body: { username: 'nobody', password: PASSWORD } });
    await rec.call('auth.login.missing-fields', 'POST', '/api/auth/login', { body: {} });
    await rec.call('auth.no-token', 'GET', '/api/stats/me');
    await rec.call('auth.bad-token', 'GET', '/api/stats/me', { token: 'not-a-jwt' });
}

async function parties(rec, ctx) {
    const { alice, bob, carol, dave } = ctx.users;
    const create = (label, token, body) => rec.call(label, 'POST', '/api/party', {
        token, body, values: ['success', 'party.name', 'party.visibility', 'party.status', 'botsJoined'],
    });

    await create('party.create.missing-name', alice.token, { visibility: 'public', settings: SETTINGS });
    await create('party.create.short-name', alice.token, { name: 'P', settings: SETTINGS });
    await create('party.create.no-settings', alice.token, { name: 'No settings' });
    await rec.call('party.create.no-token', 'POST', '/api/party', { body: { name: 'Nope', settings: SETTINGS } });

    const pub = (await create('party.create.public', alice.token, { name: 'Public one', visibility: 'public', settings: SETTINGS })).body.party;

    const list = await rec.call('party.list.anonymous', 'GET', '/api/party', { values: ['success'] });
    rec.value('party.list.anonymous.names', (list.body.parties || []).map((p) => p.name).sort());
    const mine = await rec.call('party.list.member', 'GET', '/api/party', { token: alice.token });
    rec.value('party.list.member.isMember', (mine.body.parties || []).map((p) => `${p.name}:${p.isMember}`).sort());

    await rec.call('party.details.member', 'GET', `/api/party/${pub.id}`, {
        token: alice.token, values: ['isOwner', 'userPlayerIndex', 'party.status'],
    });
    await rec.call('party.details.non-member', 'GET', `/api/party/${pub.id}`, { token: dave.token });
    await rec.call('party.details.unknown', 'GET', `/api/party/${UNKNOWN_ID}`, { token: alice.token });

    await rec.call('party.join.public', 'POST', `/api/party/${pub.id}/join`, { token: bob.token, body: {}, values: ['playerIndex'] });
    await rec.call('party.join.again', 'POST', `/api/party/${pub.id}/join`, { token: bob.token, body: {} });
    await rec.call('party.join.unknown', 'POST', `/api/party/${UNKNOWN_ID}/join`, { token: bob.token, body: {} });
    await rec.call('party.leave.non-member', 'POST', `/api/party/${pub.id}/leave`, { token: dave.token });
    await rec.call('party.join.third', 'POST', `/api/party/${pub.id}/join`, { token: carol.token, body: {} });
    await rec.call('party.join.full', 'POST', `/api/party/${pub.id}/join`, { token: dave.token, body: {} });
    // Whatever the answer, the party is back to its three players.
    await rec.request('POST', `/api/party/${pub.id}/leave`, { token: dave.token });
    await rec.call('party.leave.member', 'POST', `/api/party/${pub.id}/leave`, { token: carol.token, values: ['success', 'newOwner'] });
    await rec.call('party.join.back', 'POST', `/api/party/${pub.id}/join`, { token: carol.token, body: {} });

    await rec.call('party.start.not-owner', 'POST', `/api/party/${pub.id}/start`, { token: bob.token });
    await rec.call('party.start.ok', 'POST', `/api/party/${pub.id}/start`, {
        token: alice.token, values: ['success', 'party.status', 'round.roundNumber', 'round.status'],
    });
    await rec.call('party.start.again', 'POST', `/api/party/${pub.id}/start`, { token: alice.token });
    await rec.call('party.join.started', 'POST', `/api/party/${pub.id}/join`, { token: dave.token, body: {} });
    await rec.call('party.delete.playing', 'DELETE', `/api/party/${pub.id}`, { token: alice.token });

    await rec.call('party.state.after-start', 'GET', `/api/game/${pub.id}/state`, {
        token: alice.token, prepare: beforeDeal,
        values: ['party.status', 'gameState.currentAction', 'gameState.currentTurn', 'gameState.startingPlayer'],
    });
    await rec.call('party.state.non-member', 'GET', `/api/game/${pub.id}/state`, { token: dave.token });
    await rec.call('party.state.unknown', 'GET', `/api/game/${UNKNOWN_ID}/state`, { token: alice.token });

    // A party of two is not started.
    const two = (await rec.request('POST', '/api/party', { token: alice.token, body: { name: 'Too few', settings: SETTINGS } })).body.party;
    await rec.request('POST', `/api/party/${two.id}/join`, { token: bob.token, body: {} });
    await rec.call('party.start.too-few', 'POST', `/api/party/${two.id}/start`, { token: alice.token });

    await privateParty(rec, ctx);

    // A waiting party the owner deletes.
    const temp = (await rec.request('POST', '/api/party', { token: dave.token, body: { name: 'To delete', settings: SETTINGS } })).body.party;
    await rec.call('party.state.waiting', 'GET', `/api/game/${temp.id}/state`, { token: dave.token, values: ['party.status'] });
    await rec.call('party.delete.not-owner', 'DELETE', `/api/party/${temp.id}`, { token: bob.token });
    await rec.call('party.delete.ok', 'DELETE', `/api/party/${temp.id}`, { token: dave.token, values: ['success'] });
    await rec.call('party.delete.unknown', 'DELETE', `/api/party/${UNKNOWN_ID}`, { token: dave.token });
}

/**
 * Invite codes; the owner leaving hands the party over. Node cannot create a private
 * party (its owner is refused by its own invite-code check), so the party these steps
 * use is created public and made private in SQL, on both backends alike.
 */
async function privateParty(rec, ctx) {
    const { erin, frank, gina, hugo } = ctx.users;
    await rec.call('party.create.private', 'POST', '/api/party', {
        token: erin.token, body: { name: 'Private try', visibility: 'private', settings: SETTINGS },
        values: ['success', 'party.visibility'],
    });
    const priv = (await rec.request('POST', '/api/party', {
        token: erin.token, body: { name: 'Private one', visibility: 'public', settings: SETTINGS },
    })).body.party;
    await ctx.sql("UPDATE parties SET visibility = 'private' WHERE id = ?", [priv.id]);

    const list = await rec.call('party.private.list', 'GET', '/api/party');
    rec.value('party.private.listed', (list.body.parties || []).some((p) => p.id === priv.id));
    const seen = await rec.call('party.private.details.non-member', 'GET', `/api/party/${priv.id}`, { token: frank.token });
    rec.value('party.private.details.non-member.sees-invite-code', Boolean(seen.body.party && seen.body.party.inviteCode));
    await rec.call('party.private.join.no-code', 'POST', `/api/party/${priv.id}/join`, { token: frank.token, body: {} });
    await rec.call('party.private.join.wrong-code', 'POST', `/api/party/${priv.id}/join`, { token: gina.token, body: { inviteCode: 'WRONG123' } });
    await rec.call('party.private.join.code', 'POST', `/api/party/${priv.id}/join`, { token: hugo.token, body: { inviteCode: priv.inviteCode } });
    rec.value('party.private.players', ((await rec.request('GET', `/api/party/${priv.id}`, { token: erin.token })).body.players || [])
        .map((p) => p.username).sort());
    await rec.call('party.private.leave.owner', 'POST', `/api/party/${priv.id}/leave`, { token: erin.token, values: ['success'] });
    rec.value('party.private.new-owner-is-hugo',
        (await rec.request('GET', `/api/party/${priv.id}`, { token: hugo.token })).body.party?.ownerId === hugo.id);
}

/** A second party of three, where every illegal move is tried once. */
async function illegal(rec, ctx) {
    const { alice, bob, carol, dave } = ctx.users;
    const party = (await rec.request('POST', '/api/party', {
        token: alice.token, body: { name: 'Illegal moves', settings: SETTINGS },
    })).body.party;
    for (const u of [bob, carol]) await rec.request('POST', `/api/party/${party.id}/join`, { token: u.token, body: {} });
    await rec.request('POST', `/api/party/${party.id}/start`, { token: alice.token });
    const url = (a) => `/api/game/${party.id}/${a}`;
    const hand = async (u) => (await rec.request('GET', url('state'), { token: u.token })).body.gameState.playerHand;

    await rec.call('illegal.hand-size.missing', 'POST', url('selectHandSize'), { token: alice.token, body: {} });
    await rec.call('illegal.hand-size.out-of-range', 'POST', url('selectHandSize'), { token: alice.token, body: { handSize: 3 } });
    await rec.call('illegal.hand-size.not-your-turn', 'POST', url('selectHandSize'), { token: bob.token, body: { handSize: 7 } });
    await rec.call('illegal.hand-size.non-member', 'POST', url('selectHandSize'), { token: dave.token, body: { handSize: 7 } });
    await rec.call('illegal.play.before-hand-size', 'POST', url('play'), { token: alice.token, body: { cardIds: [0] } });
    // Seven cards are worth at least 6 (two Jokers, four aces and a two): never a ZapZap.
    await rec.call('illegal.hand-size.ok', 'POST', url('selectHandSize'), { token: alice.token, body: { handSize: 7 }, values: ['handSize'] });

    const mine = await hand(alice);
    const notMine = [...Array(54).keys()].find((c) => !mine.includes(c));
    const plain = mine.filter((c) => c < 52);
    const pairless = plain.find((c) => plain.some((d) => d % 13 !== c % 13));
    const other = plain.find((d) => d % 13 !== pairless % 13);

    await rec.call('illegal.play.missing-cards', 'POST', url('play'), { token: alice.token, body: {} });
    await rec.call('illegal.play.empty', 'POST', url('play'), { token: alice.token, body: { cardIds: [] } });
    await rec.call('illegal.play.not-in-hand', 'POST', url('play'), { token: alice.token, body: { cardIds: [notMine] } });
    await rec.call('illegal.play.invalid-combination', 'POST', url('play'), { token: alice.token, body: { cardIds: [pairless, other] } });
    await rec.call('illegal.play.not-your-turn', 'POST', url('play'), { token: bob.token, body: { cardIds: [(await hand(bob))[0]] } });
    await rec.call('illegal.play.non-member', 'POST', url('play'), { token: dave.token, body: { cardIds: [0] } });
    await rec.call('illegal.draw.before-play', 'POST', url('draw'), { token: alice.token, body: { source: 'deck' } });
    await rec.call('illegal.zapzap.hand-too-high', 'POST', url('zapzap'), { token: alice.token });
    await rec.call('illegal.zapzap.not-your-turn', 'POST', url('zapzap'), { token: bob.token });
    await rec.call('illegal.next-round.round-not-finished', 'POST', url('nextRound'), { token: alice.token });
    await rec.call('illegal.next-round.non-member', 'POST', url('nextRound'), { token: dave.token });
    await rec.call('illegal.play.unknown-party', 'POST', `/api/game/${UNKNOWN_ID}/play`, { token: alice.token, body: { cardIds: [0] } });

    const now = await hand(alice);
    const top = [...now].sort((a, b) => points(b) - points(a) || a - b)[0];
    await rec.call('illegal.play.ok', 'POST', url('play'), { token: alice.token, body: { cardIds: [top] }, values: ['remainingCards'] });
    await rec.call('illegal.play.twice', 'POST', url('play'), { token: alice.token, body: { cardIds: [now.find((c) => c !== top)] } });
    await rec.call('illegal.draw.missing-source', 'POST', url('draw'), { token: alice.token, body: {} });
    await rec.call('illegal.draw.bad-source', 'POST', url('draw'), { token: alice.token, body: { source: 'hand' } });
    await rec.call('illegal.draw.card-not-in-pile', 'POST', url('draw'), { token: alice.token, body: { source: 'played', cardId: top } });
    await rec.call('illegal.zapzap.in-draw-phase', 'POST', url('zapzap'), { token: alice.token });
    rec.value('illegal.state.after-draw-attempts', (await rec.request('GET', url('state'), { token: alice.token })).body.gameState?.currentAction);
    // Node takes a card for this one, which ends Alice's turn: last of the draw attempts.
    await rec.call('illegal.draw.played-without-card', 'POST', url('draw'), { token: alice.token, body: { source: 'played' } });

    // Bob's turn: the same card twice. A 200 moves the round on, so this comes last.
    await rec.request('POST', url('draw'), { token: alice.token, body: { source: 'deck' } });
    const bobs = await hand(bob);
    const twice = await rec.call('illegal.play.repeated-card', 'POST', url('play'), { token: bob.token, body: { cardIds: [bobs[0], bobs[0]] } });
    rec.check('illegal.repeated-card-refused', twice.status >= 400 && twice.status < 500,
        () => `a play of [${bobs[0]}, ${bobs[0]}] answered ${twice.status}`);
    ctx.illegalParty = party.id;
}

/**
 * GAMES games to their end, side by side, under the same labels: which keys a response
 * holds depends on what happened (a counteract, an elimination, a golden score), and a
 * few games make each of those all but certain on both backends.
 */
const GAMES = 16;

async function oneGame(rec, ctx, n) {
    const { alice, bob, carol } = ctx.users;
    const party = (await rec.request('POST', '/api/party', {
        token: alice.token, body: { name: `Full game ${n}`, settings: SETTINGS },
    })).body.party;
    for (const u of [bob, carol]) await rec.request('POST', `/api/party/${party.id}/join`, { token: u.token, body: {} });
    await rec.request('POST', `/api/party/${party.id}/start`, { token: alice.token });
    const players = (await rec.request('GET', `/api/game/${party.id}/state`, { token: alice.token })).body.players;
    const byId = { [alice.id]: alice.token, [bob.id]: bob.token, [carol.id]: carol.token };
    const tokens = Object.fromEntries(players.map((p) => [p.playerIndex, byId[p.userId]]));
    const result = await playGame(rec, 'game', party.id, tokens);

    const url = (a) => `/api/game/${party.id}/${a}`;
    // The state of a finished game is the state of its last finished round.
    const end = await rec.request('GET', url('state'), { token: alice.token });
    rec.record(`game.state.${end.body.gameState?.currentAction}`, end);
    rec.value('game.over.party.status', end.body.party?.status);
    rec.value('game.over.gameFinished', end.body.gameState?.gameFinished);
    await rec.call('game.next-round.game-over', 'POST', url('nextRound'), { token: alice.token });
    await rec.call('game.play.game-over', 'POST', url('play'), { token: alice.token, body: { cardIds: [0] } });
    await rec.call('game.party.details.finished', 'GET', `/api/party/${party.id}`, { token: alice.token, values: ['party.status'] });
    return { partyId: party.id, ...result };
}

async function game(rec, ctx) {
    const results = await Promise.all([...Array(GAMES).keys()].map((n) => oneGame(rec, ctx, n + 1)));
    for (const r of results) {
        rec.value('game.finished', r.finished ? 'finished' : `not finished: ${r.why}`);
        // Both backends agreeing is not enough: every game must reach its end.
        rec.check('game.reached-end', r.finished, () => `game in party ${r.partyId}: ${r.why}`);
    }
    ctx.gameParty = results[0].partyId;
    ctx.gameRounds = results.map((r) => r.rounds).join('+');
    // How many times each game checked its winner: parity.test.js wants at least one each.
    ctx.games = GAMES;
    ctx.winnerChecks = results.map((r) => r.winnerChecks || 0);
    rec.value('game.hand-size', HAND_SIZE);
}

async function readOnly(rec, ctx) {
    const { alice, dave } = ctx.users;
    await rec.call('history.mine', 'GET', '/api/history', { token: alice.token });
    await rec.call('history.public', 'GET', '/api/history/public');
    await rec.call('history.no-token', 'GET', '/api/history');
    await rec.call('history.game', 'GET', `/api/history/${ctx.gameParty}`, { token: alice.token });
    await rec.call('history.game.non-member', 'GET', `/api/history/${ctx.gameParty}`, { token: dave.token });
    await rec.call('history.game.unfinished', 'GET', `/api/history/${ctx.illegalParty}`, { token: alice.token });
    await rec.call('history.game.unknown', 'GET', `/api/history/${UNKNOWN_ID}`, { token: alice.token });

    await rec.call('stats.me', 'GET', '/api/stats/me', { token: alice.token });
    await rec.call('stats.user', 'GET', `/api/stats/user/${alice.id}`);
    await rec.call('stats.user.unknown', 'GET', `/api/stats/user/${UNKNOWN_ID}`);
    const board = await rec.call('stats.leaderboard', 'GET', '/api/stats/leaderboard?minGames=0');
    rec.value('stats.leaderboard.usernames', JSON.stringify(board.body).match(/"username":"[a-z]+"/g)?.sort() || []);
    await rec.call('stats.leaderboard.default', 'GET', '/api/stats/leaderboard');
    await rec.call('stats.bots', 'GET', '/api/stats/bots');

    await rec.call('bots.list', 'GET', '/api/bots');
    await rec.call('bots.list.easy', 'GET', '/api/bots?difficulty=easy');
    await rec.call('bots.list.bad-difficulty', 'GET', '/api/bots?difficulty=nope');
    await rec.call('bots.create.anonymous', 'POST', '/api/bots', { body: { username: 'SneakyBot', difficulty: 'easy' } });
    await rec.call('bots.delete.anonymous', 'DELETE', `/api/bots/${UNKNOWN_ID}`);

    await rec.call('health.root', 'GET', '/health');
    await rec.call('health.api', 'GET', '/api/health', { values: ['status'] });
    await rec.call('players.connected', 'GET', '/api/players/connected');
    await rec.call('route.unknown', 'GET', '/api/nope');
    await rec.call('route.unknown.root', 'GET', '/nope', { values: ['path'] });
    // A served path with a method it does not serve: Node falls through to its 404
    await rec.call('route.wrong-method', 'PUT', '/api/party', { values: ['path'] });
    // Only POST is behind the auth middleware there: a GET without a token is a 404
    await rec.call('route.wrong-method.auth-route', 'GET', `/api/party/${UNKNOWN_ID}/join`, { values: ['path'] });
}

async function admin(rec, ctx) {
    const { alice, erin, gina } = ctx.users;
    const login = await rec.call('admin.login', 'POST', '/api/auth/login', {
        body: { username: 'admin', password: ctx.adminPassword }, values: ['user.isAdmin'],
    });
    const token = login.body.token;
    await rec.call('admin.users.non-admin', 'GET', '/api/admin/users', { token: alice.token });
    await rec.call('admin.users.no-token', 'GET', '/api/admin/users');
    const users = await rec.call('admin.users', 'GET', '/api/admin/users', { token });
    rec.value('admin.users.usernames', JSON.stringify(users.body).match(/"username":"[a-z]+"/g)?.sort() || []);
    await rec.call('admin.parties', 'GET', '/api/admin/parties', { token });
    await rec.call('admin.parties.playing', 'GET', '/api/admin/parties?status=playing', { token });
    await rec.call('admin.statistics', 'GET', '/api/admin/statistics', { token });
    await rec.call('admin.set-admin.bad-body', 'POST', `/api/admin/users/${erin.id}/admin`, { token, body: { isAdmin: 'yes' } });
    await rec.call('admin.set-admin.ok', 'POST', `/api/admin/users/${erin.id}/admin`, { token, body: { isAdmin: true } });
    await rec.call('admin.set-admin.unknown', 'POST', `/api/admin/users/${UNKNOWN_ID}/admin`, { token, body: { isAdmin: true } });
    await rec.call('admin.set-admin.revoke', 'POST', `/api/admin/users/${erin.id}/admin`, { token, body: { isAdmin: false } });
    await rec.call('admin.delete-user.ok', 'DELETE', `/api/admin/users/${erin.id}`, { token });
    await rec.request('POST', `/api/admin/users/${gina.id}/admin`, { token, body: { isAdmin: true } });
    await rec.call('admin.delete-user.admin', 'DELETE', `/api/admin/users/${gina.id}`, { token });
    await rec.call('admin.delete-user.self', 'DELETE', `/api/admin/users/${login.body.user.id}`, { token });
    await rec.call('admin.delete-user.unknown', 'DELETE', `/api/admin/users/${UNKNOWN_ID}`, { token });
    await rec.call('admin.stop-party.ok', 'POST', `/api/admin/parties/${ctx.illegalParty}/stop`, { token });
    await rec.call('admin.stop-party.finished', 'POST', `/api/admin/parties/${ctx.illegalParty}/stop`, { token });
    await rec.call('admin.stop-party.unknown', 'POST', `/api/admin/parties/${UNKNOWN_ID}/stop`, { token });
    await rec.call('admin.delete-party.ok', 'DELETE', `/api/admin/parties/${ctx.illegalParty}`, { token });
    await rec.call('admin.delete-party.unknown', 'DELETE', `/api/admin/parties/${UNKNOWN_ID}`, { token });
    // Every /api/admin path, served or not, is behind the token and admin checks
    await rec.call('admin.unknown.no-token', 'GET', '/api/admin/nope');
    await rec.call('admin.unknown.non-admin', 'GET', '/api/admin/nope', { token: alice.token });
    await rec.call('admin.unknown', 'GET', '/api/admin/nope', { token, values: ['path'] });
    await rec.call('admin.root.no-token', 'GET', '/api/admin');
    await rec.call('admin.wrong-method.no-token', 'PUT', '/api/admin/users');
    await rec.call('admin.wrong-method', 'PUT', '/api/admin/users', { token, values: ['path'] });
}

module.exports = [
    ['auth', auth],
    ['parties', parties],
    ['illegal moves', illegal],
    ['games to their end', game],
    ['history, stats, bots, health', readOnly],
    ['admin', admin],
];
