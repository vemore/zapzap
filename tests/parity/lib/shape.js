/**
 * What of a response is compared, and how a response is printed.
 *
 * A body is reduced to its shape: the set of `path:type` it holds. Map keys that are
 * player indexes or ids become `#` / `<id>`, array elements share the path `a[]`, and a
 * null value counts as an absent key (a JS or Dart client reads both as null).
 */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const JWT = /^eyJ[\w-]+\.[\w-]+\.[\w-]+$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$/;

function typeOf(v) {
    if (Array.isArray(v)) return 'array';
    return typeof v;
}

function keyName(k) {
    if (/^\d+$/.test(k)) return '#';
    if (UUID.test(k)) return '<id>';
    return k;
}

/** @returns {Map<string, Set<string>>} path -> types */
function shapeOf(value, prefix = '', out = new Map()) {
    const add = (p, t) => {
        if (!out.has(p)) out.set(p, new Set());
        out.get(p).add(t);
    };
    if (value === null || value === undefined) return out;
    const t = typeOf(value);
    if (prefix) add(prefix, t);
    if (t === 'array') {
        for (const el of value) shapeOf(el, `${prefix}[]`, out);
    } else if (t === 'object') {
        for (const [k, v] of Object.entries(value)) {
            shapeOf(v, prefix ? `${prefix}.${keyName(k)}` : keyName(k), out);
        }
    }
    return out;
}

function mergeShapes(target, src) {
    for (const [p, types] of src) {
        if (!target.has(p)) target.set(p, new Set());
        for (const t of types) target.get(p).add(t);
    }
    return target;
}

/** Placeholders for what differs by construction between two runs, keys sorted. */
function normalize(value, key = '') {
    if (value === null || value === undefined) return value;
    if (Array.isArray(value)) return value.map((v) => normalize(v));
    if (typeof value === 'object') {
        const out = {};
        for (const k of Object.keys(value).sort()) out[keyName(k)] = normalize(value[k], k);
        return out;
    }
    if (typeof value === 'string') {
        if (UUID.test(value)) return '<uuid>';
        if (JWT.test(value)) return '<jwt>';
        if (ISO_DATE.test(value)) return '<date>';
        if (key === 'inviteCode') return '<invite>';
    }
    return value;
}

/** A value at a dotted path (`a.b.0.c`), undefined when absent. */
function at(value, path) {
    return path.split('.').reduce((v, k) => (v === null || v === undefined ? undefined : v[k]), value);
}

function brief(value, max = 600) {
    const s = JSON.stringify(normalize(value));
    return s === undefined ? 'undefined' : s.length > max ? `${s.slice(0, max)}…` : s;
}

module.exports = { shapeOf, mergeShapes, normalize, at, brief };
