/**
 * One recorder per backend: the HTTP client the scenarios use, and what it observed.
 *
 * Observations are keyed by a label (`<scenario>.<step>`), the same on both backends:
 *   - call(label, ...)      status, error code and shape of the response (merged when a
 *                           label is called several times, e.g. every play of a game)
 *   - value(label, v)       a normalized value both backends must agree on
 *   - check(name, ok, why)  an invariant this backend must hold (GAME_RULES.md); the
 *                           first violation is kept
 */

const { shapeOf, mergeShapes, normalize, at } = require('./shape');

class Recorder {
    constructor(name, base) {
        this.name = name;
        this.base = base;
        this.calls = new Map();
        this.values = new Map();
        this.checks = new Map();
        this.callValues = new Set();
    }

    /**
     * @param {string} label
     * @param {string} method
     * @param {string} path
     * @param {{token?: string, body?: any, values?: string[], prepare?: Function}} [opts]
     *   values: dotted paths of the body whose normalized value is compared too;
     *   prepare: body -> body before the shape is taken (a documented normalization)
     * @returns {Promise<{status: number, body: any}>} the raw response
     */
    async call(label, method, path, opts = {}) {
        const res = await this.request(method, path, opts);
        this.record(label, res, opts);
        return res;
    }

    /** The request alone, nothing recorded. */
    async request(method, path, opts = {}) {
        this.requests = (this.requests || 0) + 1;
        const headers = {};
        if (opts.token) headers.authorization = `Bearer ${opts.token}`;
        if (opts.body !== undefined) headers['content-type'] = 'application/json';
        const res = await fetch(this.base + path, {
            method,
            headers,
            body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
        });
        const text = await res.text();
        let body;
        try {
            body = text === '' ? null : JSON.parse(text);
        } catch {
            body = { '<non-json>': text.slice(0, 200) };
        }
        return { status: res.status, body };
    }

    /** Records a response obtained with request(), under a label chosen after the fact. */
    record(label, { status, body }, opts = {}) {
        const shaped = opts.prepare ? opts.prepare(structuredClone(body)) : body;
        let rec = this.calls.get(label);
        if (!rec) {
            rec = { statuses: new Set(), codes: new Set(), shape: new Map(), sample: null, n: 0 };
            this.calls.set(label, rec);
        }
        rec.n += 1;
        rec.statuses.add(status);
        rec.codes.add(body && typeof body === 'object' && body.code !== undefined ? String(body.code) : '-');
        mergeShapes(rec.shape, shapeOf(shaped));
        if (!rec.sample) rec.sample = { status, body };
        for (const p of opts.values || []) {
            const v = at(body, p);
            // An absent key is already a shape difference of the call.
            if (v === undefined) continue;
            this.value(`${label}.${p}`, v);
            this.callValues.add(`${label}.${p}`);
        }
    }

    value(label, v) {
        if (!this.values.has(label)) this.values.set(label, []);
        this.values.get(label).push(JSON.stringify(normalize(v)));
    }

    check(name, ok, why) {
        if (!this.checks.has(name)) this.checks.set(name, { ok: true, why: null, n: 0 });
        const c = this.checks.get(name);
        c.n += 1;
        if (!ok && c.ok) {
            c.ok = false;
            c.why = typeof why === 'function' ? why() : why;
        }
    }
}

module.exports = { Recorder };
