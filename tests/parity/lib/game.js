/**
 * GAME_RULES.md as code, and the deterministic player both backends are driven with.
 *
 * The player reads its hand from GET /api/game/:id/state and, on its turn:
 *   - picks hand size HAND_SIZE when it starts a round;
 *   - calls ZapZap as soon as its hand is worth 5 points or less (Joker = 0);
 *   - otherwise plays what sheds the most points: all its cards of one rank (a pair or
 *     more, Jokers kept) or its single highest card — a single card is always legal, and
 *     shedding the high cards is what brings a hand down to 5;
 *   - draws from the deck, except the first draw of a round, which takes the first
 *     card of the last played pile (so both draw sources are exercised).
 * Dealt cards differ between the backends (no shared seed), so the two games differ
 * in length and detail: what is compared is the shape of every kind of response, and
 * each backend is checked against GAME_RULES.md on its own game.
 */

const HAND_SIZE = 4;
const MAX_SCORE = 100;
const MAX_REQUESTS = 20000;

const points = (id) => (id >= 52 ? 0 : (id % 13) + 1);
const penalty = (id) => (id >= 52 ? 25 : points(id));
const handValue = (hand) => hand.reduce((s, c) => s + points(c), 0);
const handPenalty = (hand) => hand.reduce((s, c) => s + penalty(c), 0);

/** The next active player after `from`, clockwise by player index. */
function nextActive(from, active, n) {
    for (let i = 1; i <= n; i++) {
        const p = (from + i) % n;
        if (active.includes(p)) return p;
    }
    return from;
}

/** GAME_RULES.md "Final Scoring": the points each active player takes this round. */
function expectedRoundScores(hands, caller, active) {
    const base = Object.fromEntries(active.map((p) => [p, handValue(hands[p] || [])]));
    const lowest = Math.min(...Object.values(base));
    const counteracted = active.some((p) => p !== caller && base[p] <= base[caller]);
    const out = {};
    for (const p of active) {
        if (p === caller && counteracted) out[p] = handPenalty(hands[p]) + (active.length - 1) * 5;
        else if (base[p] === lowest) out[p] = 0;
        else out[p] = handPenalty(hands[p]);
    }
    return out;
}

/** The legal play that sheds the most points: a same-rank group or one card. */
function choosePlay(hand) {
    const byRank = new Map();
    for (const c of hand.filter((id) => id < 52)) {
        const r = c % 13;
        byRank.set(r, [...(byRank.get(r) || []), c]);
    }
    let best = [[...hand].sort((a, b) => points(b) - points(a) || a - b)[0]];
    for (const group of byRank.values()) {
        if (group.length >= 2 && handValue(group) > handValue(best)) best = [...group].sort((a, b) => a - b);
    }
    return best;
}

/** Card ids a state shows, which must all be distinct and within 0..53. */
function visibleCards(gs) {
    const ids = [...(gs.lastCardsPlayed || []), ...(gs.cardsPlayed || [])];
    if (gs.allHands) for (const h of Object.values(gs.allHands)) ids.push(...h);
    else ids.push(...(gs.playerHand || []));
    return ids;
}

function countOnTable(gs) {
    const others = Object.values(gs.otherPlayersHandSizes || {}).reduce((s, n) => s + n, 0);
    return (gs.deckSize || 0) + (gs.playerHand || []).length + others
        + (gs.lastCardsPlayed || []).length + (gs.cardsPlayed || []).length;
}

/**
 * Rust deals when the party starts, Node when the hand size is chosen: in the hand-size
 * phase the dealt cards are dropped before the shape is taken.
 */
function beforeDeal(body) {
    const gs = body && body.gameState;
    if (gs && gs.currentAction === 'selectHandSize') {
        gs.playerHand = [];
        gs.otherPlayersHandSizes = Object.fromEntries(Object.keys(gs.otherPlayersHandSizes || {}).map((k) => [k, 0]));
    }
    return body;
}

/**
 * Plays a started party to its end.
 * @param {Recorder} rec
 * @param {string} label  prefix of the recorded labels
 * @param {string} partyId
 * @param {Object<number, string>} tokens player index -> token
 */
async function playGame(rec, label, partyId, tokens) {
    const n = Object.keys(tokens).length;
    const url = (a) => `/api/game/${partyId}/${a}`;
    let active = Object.keys(tokens).map(Number);
    let viewer = 0;
    let prev = { action: 'start' };
    let round = { starter: null, scoresBefore: null, firstDraw: true, golden: false };
    let expectedStarter = 0;
    let requests = 0;
    let rounds = 0;

    const check = (name, ok, why) => rec.check(`${label}.${name}`, ok, why);

    while (requests < MAX_REQUESTS) {
        requests += 1;
        const s = await rec.request('GET', url('state'), { token: tokens[viewer] });
        const gs = s.body && s.body.gameState;
        if (s.status !== 200 || !gs) {
            rec.record(`${label}.state.unexpected`, s);
            return { finished: false, rounds, why: `state answered ${s.status}` };
        }
        const action = gs.currentAction;

        // What the previous action must have led to.
        if (prev.action === 'select') {
            check('turn.after-hand-size', action === 'play' && gs.currentTurn === prev.player,
                () => `after player ${prev.player} chose the hand size: ${action}, turn ${gs.currentTurn}`);
            check('cards.dealt', countOnTable(gs) === 54,
                () => `after the deal ${countOnTable(gs)} cards are accounted for, not 54`);
            check('cards.hand-size', (gs.playerHand || []).length === HAND_SIZE
                && Object.entries(gs.otherPlayersHandSizes || {})
                    .every(([p, k]) => k === (active.includes(Number(p)) ? HAND_SIZE : 0)),
                () => `hand size ${HAND_SIZE} chosen, active ${active}: hands ${JSON.stringify(gs.otherPlayersHandSizes)} + ${(gs.playerHand || []).length}`);
        } else if (prev.action === 'play') {
            check('turn.after-play', action === 'draw' && gs.currentTurn === prev.player
                && (gs.playerHand || []).length === prev.handLen - prev.played,
                () => `after player ${prev.player} played: ${action}, turn ${gs.currentTurn}, hand ${(gs.playerHand || []).length}`);
        } else if (prev.action === 'draw') {
            const want = nextActive(prev.player, active, n);
            check('turn.after-draw', action === 'play' && gs.currentTurn === want,
                () => `after player ${prev.player} drew: ${action}, turn ${gs.currentTurn}, expected ${want}`);
            const held = viewer === prev.player ? (gs.playerHand || []).length : (gs.otherPlayersHandSizes || {})[prev.player];
            check('cards.after-draw', held === prev.handLen,
                () => `player ${prev.player} holds ${held} cards after drawing, not ${prev.handLen}`);
        } else if (prev.action === 'zapzap') {
            check('turn.after-zapzap', action === 'finished', () => `after ZapZap: ${action}`);
        }
        prev = { action: 'seen' };

        if (action !== 'finished' && gs.currentTurn !== viewer) {
            viewer = gs.currentTurn;
            continue;
        }
        rec.record(`${label}.state.${action}`, s, { prepare: beforeDeal });
        const ids = visibleCards(gs);
        check('cards.distinct', new Set(ids).size === ids.length && ids.every((c) => c >= 0 && c <= 53),
            () => `visible cards repeat or fall outside 0..53: ${JSON.stringify(ids)}`);
        if (action !== 'finished') {
            check('cards.at-most-54', countOnTable(gs) <= 54, () => `${countOnTable(gs)} cards on the table`);
        }

        const me = gs.currentTurn;
        requests += 1;
        if (action === 'selectHandSize') {
            rounds += 1;
            check('rules.round-starter', me === expectedStarter,
                () => `round ${rounds} starts with player ${me}, expected ${expectedStarter} (active ${active})`);
            check('rules.eliminated-list', JSON.stringify([...(gs.eliminatedPlayers || [])].sort())
                === JSON.stringify(Object.keys(tokens).map(Number).filter((p) => !active.includes(p))),
                () => `eliminatedPlayers ${JSON.stringify(gs.eliminatedPlayers)}, scores ${JSON.stringify(gs.scores)}`);
            check('rules.golden-score-flag', Boolean(gs.isGoldenScore) === (active.length === 2),
                () => `isGoldenScore ${gs.isGoldenScore} with ${active.length} active players`);
            round = { starter: me, scoresBefore: { ...gs.scores }, firstDraw: true, golden: active.length === 2 };
            const r = await rec.call(`${label}.selectHandSize`, 'POST', url('selectHandSize'),
                { token: tokens[me], body: { handSize: HAND_SIZE } });
            if (r.status !== 200) return { finished: false, rounds, why: `selectHandSize answered ${r.status}` };
            prev = { action: 'select', player: me };
        } else if (action === 'play') {
            const hand = gs.playerHand;
            if (handValue(hand) <= 5) {
                round.caller = me;
                round.callerHand = [...hand];
                const r = await rec.call(`${label}.zapzap`, 'POST', url('zapzap'), { token: tokens[me] });
                if (r.status !== 200) return { finished: false, rounds, why: `zapzap answered ${r.status}` };
                prev = { action: 'zapzap', player: me };
            } else {
                const cards = choosePlay(hand);
                const r = await rec.call(`${label}.play.${cards.length > 1 ? 'group' : 'single'}`, 'POST', url('play'),
                    { token: tokens[me], body: { cardIds: cards } });
                if (r.status !== 200) return { finished: false, rounds, why: `play answered ${r.status}` };
                prev = { action: 'play', player: me, handLen: hand.length, played: cards.length };
            }
        } else if (action === 'draw') {
            const handLen = gs.playerHand.length + 1; // after the draw
            let r;
            if (round.firstDraw && (gs.lastCardsPlayed || []).length) {
                r = await rec.call(`${label}.draw.played`, 'POST', url('draw'),
                    { token: tokens[me], body: { source: 'played', cardId: gs.lastCardsPlayed[0] } });
            } else {
                r = await rec.call(`${label}.draw.deck`, 'POST', url('draw'), { token: tokens[me], body: { source: 'deck' } });
            }
            round.firstDraw = false;
            if (r.status !== 200) return { finished: false, rounds, why: `draw answered ${r.status}` };
            prev = { action: 'draw', player: me, handLen };
            viewer = nextActive(me, active, n);
        } else if (action === 'finished') {
            const hands = gs.allHands || {};
            if (!round.golden) {
                const want = expectedRoundScores(hands, round.caller, active);
                const got = Object.fromEntries(active.map((p) => [p, (gs.scores[p] || 0) - (round.scoresBefore[p] || 0)]));
                check('rules.round-scores', JSON.stringify(want) === JSON.stringify(got),
                    () => `caller ${round.caller}, hands ${JSON.stringify(hands)}: took ${JSON.stringify(got)}, GAME_RULES.md gives ${JSON.stringify(want)}`);
            }
            const before = active;
            active = before.filter((p) => (gs.scores[p] || 0) <= MAX_SCORE);
            const r = await rec.call(`${label}.nextRound`, 'POST', url('nextRound'), { token: tokens[0] });
            if (r.status !== 200) return { finished: false, rounds, why: `nextRound answered ${r.status}` };
            if (round.golden || active.length <= 1) {
                let winner = active.length === 1 ? active[0] : null;
                if (round.golden) {
                    const [a, b] = before;
                    const va = handValue(hands[a] || []);
                    const vb = handValue(hands[b] || []);
                    winner = va !== vb ? (va < vb ? a : b) : before.find((p) => p !== round.caller);
                }
                check('rules.game-over', r.body.gameFinished === true,
                    () => `the game should be over (active ${JSON.stringify(active)}, golden ${round.golden}), nextRound says ${JSON.stringify(r.body.gameFinished)}`);
                const got = r.body.winner && r.body.winner.playerIndex;
                check('rules.winner', winner === null || got === winner,
                    () => `winner ${got}, GAME_RULES.md gives ${winner} (hands ${JSON.stringify(hands)}, caller ${round.caller}, scores ${JSON.stringify(gs.scores)})`);
                return { finished: r.body.gameFinished === true, rounds };
            }
            check('rules.game-over', r.body.gameFinished !== true,
                () => `nextRound ended the game with ${active.length} active players`);
            if (r.body.gameFinished === true) return { finished: true, rounds };
            expectedStarter = nextActive(round.starter, active, n);
            prev = { action: 'next' };
        } else {
            return { finished: false, rounds, why: `unknown action ${action}` };
        }
    }
    return { finished: false, rounds, why: `no end after ${MAX_REQUESTS} requests` };
}

module.exports = { playGame, points, handValue, HAND_SIZE, beforeDeal };
