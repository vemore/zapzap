/**
 * Turns two recorders into a list of differences, each with a stable id:
 *   <label>:status | <label>:code
 *   <label>:keys:<path>       a key only one backend returns (the deepest common
 *                             ancestor only, not every key under it)
 *   <label>:type:<path>       the same key with another JSON type
 *   <label>:value             a compared value
 *   invariant:<name>@<backend> a rule of GAME_RULES.md one backend broke
 *   missing:<label>@<backend> a step one backend never reached
 * and checks it against divergences.json.
 */

const { brief } = require('./shape');

function sortedList(set) {
    return [...set].sort().join(',');
}

function parentPath(p) {
    if (p.endsWith('[]')) return p.slice(0, -2);
    const i = p.lastIndexOf('.');
    return i < 0 ? null : p.slice(0, i);
}

/** `a.b[].c` -> [`a.b`]: the arrays a path goes through. */
function arraysOf(p) {
    const out = [];
    let i = p.indexOf('[]');
    while (i >= 0) {
        out.push(p.slice(0, i));
        i = p.indexOf('[]', i + 2);
    }
    return out;
}

function diffShapes(label, nodeShape, rustShape, out) {
    // An array one backend only ever returned empty says nothing about its elements.
    const comparable = (p) => arraysOf(p).every((arr) => nodeShape.has(`${arr}[]`) && rustShape.has(`${arr}[]`)
        || !(nodeShape.has(arr) && rustShape.has(arr)));
    const only = (a, b, side) => {
        for (const p of a.keys()) {
            if (b.has(p) || !comparable(p)) continue;
            const parent = parentPath(p);
            if (parent !== null && a.has(parent) && !b.has(parent)) continue;
            out.push({ id: `${label}:keys:${p}`, node: side === 'node' ? 'present' : 'absent', rust: side === 'rust' ? 'present' : 'absent' });
        }
    };
    only(nodeShape, rustShape, 'node');
    only(rustShape, nodeShape, 'rust');
    for (const [p, types] of nodeShape) {
        const r = rustShape.get(p);
        if (!r || !comparable(p)) continue;
        const n = sortedList(types);
        const rs = sortedList(r);
        if (n !== rs) out.push({ id: `${label}:type:${p}`, node: n, rust: rs });
    }
}

function compareRecorders(node, rust) {
    const out = [];
    const labels = new Set([...node.calls.keys(), ...rust.calls.keys()]);
    for (const label of labels) {
        const n = node.calls.get(label);
        const r = rust.calls.get(label);
        if (!n || !r) {
            const missing = n ? 'rust' : 'node';
            out.push({ id: `missing:${label}@${missing}`, node: n ? 'called' : 'never', rust: r ? 'called' : 'never', label });
            continue;
        }
        const fields = [];
        if (sortedList(n.statuses) !== sortedList(r.statuses)) {
            fields.push({ id: `${label}:status`, node: sortedList(n.statuses), rust: sortedList(r.statuses) });
        }
        if (sortedList(n.codes) !== sortedList(r.codes)) {
            fields.push({ id: `${label}:code`, node: sortedList(n.codes), rust: sortedList(r.codes) });
        }
        diffShapes(label, n.shape, r.shape, fields);
        for (const f of fields) out.push({ ...f, label });
    }
    const vlabels = new Set([...node.values.keys(), ...rust.values.keys()]);
    for (const label of vlabels) {
        // A value read from a response one backend refused: the call's own difference says it.
        const partial = !(node.values.has(label) && rust.values.has(label))
            && (node.callValues.has(label) || rust.callValues.has(label));
        if (partial) continue;
        const n = [...(node.values.get(label) || [])].sort().join(' | ');
        const r = [...(rust.values.get(label) || [])].sort().join(' | ');
        if (n !== r) out.push({ id: `${label}:value`, node: n || '(none)', rust: r || '(none)' });
    }
    for (const rec of [node, rust]) {
        for (const [name, c] of rec.checks) {
            if (!c.ok) out.push({ id: `invariant:${name}@${rec.name}`, [rec.name]: c.why, [rec.name === 'node' ? 'rust' : 'node']: '-' });
        }
    }
    return out;
}

/**
 * @returns {{unexpected: object[], stale: object[], matched: object[]}}
 */
function checkDivergences(differences, divergences) {
    const listed = new Map(divergences.map((d) => [d.id, d]));
    const found = new Set(differences.map((d) => d.id));
    return {
        unexpected: differences.filter((d) => !listed.has(d.id)),
        // A "sometimes" difference hangs on a random deal (a tie, say): it may not occur.
        stale: divergences.filter((d) => !found.has(d.id) && !d.sometimes),
        matched: differences.filter((d) => listed.has(d.id)),
    };
}

function sampleOf(rec, label) {
    const c = label && rec.calls.get(label);
    return c ? `${c.sample.status} ${brief(c.sample.body)}` : '(no call)';
}

function report(node, rust, { unexpected, stale }) {
    const lines = [];
    if (unexpected.length) {
        lines.push(`${unexpected.length} difference(s) not listed in tests/parity/divergences.json:`);
        for (const d of unexpected) {
            lines.push('', `  ✗ ${d.id}`, `      node: ${d.node}`, `      rust: ${d.rust}`);
            if (d.label) {
                lines.push(`      node sample: ${sampleOf(node, d.label)}`, `      rust sample: ${sampleOf(rust, d.label)}`);
            }
        }
        lines.push('', 'Fix the backend, or list the difference with its class (node-bug | pending) and wip entry.');
    }
    if (stale.length) {
        lines.push('', `${stale.length} listed difference(s) that no longer occur — remove them from divergences.json:`);
        for (const d of stale) lines.push(`  ✓ ${d.id}  (${d.class}, ${d.wip})`);
    }
    return lines.join('\n');
}

module.exports = { compareRecorders, checkDivergences, report };
