#!/usr/bin/env node
// VuloForeverUI pre-release checker. Run from the addon root or tools/:
//   cd tools && npm install && node check.js
//
// Checks, in order:
//   1. Lua 5.1 syntax of every .lua file (luaparse)
//   1c. a local function read above its own definition (compiles as a nil
//      global; hard fail -- shipped twice on 2026-09-12 before this existed)
//   2. top-level locals per chunk (Lua 5.1 hard cap: 200; warn at 175)
//   3. locale coverage: every L["..."] key used in code exists in deDE.lua
//      (missing keys fall back to English — listed so nothing slips through)
//   4. raw/escaped ASCII double quotes inside GERMAN locale values
//      (house rule: use „ " or ' — a stray " breaks or uglifies the string)
//   5. third-party addon names in code/comments/strings (house rule: never
//      name other addons; WeakAuras is the only allowed exception)
//   6. writes to bare global names (house rule: everything lives on ns; a
//      global we define is visible to every other addon and never goes away)
//   7. module default keys that nothing anywhere reads (a setting that is
//      written into every profile and can never have an effect)
//   8. L["..."] evaluated at file scope (resolves before the saved language
//      override is read, so it bakes in the client language)
//   9. format specifiers must survive translation in every locale
//  10. TOC file lists: identical across flavors, nothing missing or orphaned
//  11. CHANGELOG-release.md matches the newest CHANGELOG.md section (the
//      packager falls back to the German git log silently when it is stale)
//
// Exit code 1 only on syntax errors or locals-cap violations; everything
// else is a warning report for human judgment.
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');
const SCAN_DIRS = ['Core', 'Modules', 'UI', 'Locales', 'Trinkets'];
const SYNTAX_ONLY_DIRS = ['Libs', 'Dev'];   // vendor code and the generated dev seed: syntax/locals checks only
const DEDE = path.join(ROOT, 'Locales', 'deDE.lua');
// "doom_?cooldownpulse" joined 2026-08-04: it sat in the Cooldown Pulse module's
// DESCRIPTION -- on screen in the options, and translated into all nine locale
// files, so the name shipped nine times over. Nothing here caught it, which is
// the only reason it survived that long.
const FORBIDDEN = /baganator|ellesmere|chattynator|dragonflight|dfui|elvui|leatrix|masque|sexymap|ndui|bartender|dominos|totemtimers|tacotip|gearscore|doom_?cooldownpulse/i;
// "masque" is also the ordinary French word for "hides", so the French locale
// alone produced 60 false hits — enough noise to hide a real one. That name can
// only appear meaningfully in code (an integration), so it is dropped for
// locale files while every other name is still checked there.
// "retail" is banned from USER-FACING text only (locale keys and values):
// comparisons against the other game version do not belong in the product's
// own voice. Code and comments keep the word — API-availability notes
// legitimately need it, and identifiers like IsRetail would false-positive.
const FORBIDDEN_LOCALE = new RegExp(FORBIDDEN.source.replace('|masque', '') + '|retail', 'i');
const patternFor = (file) => file.includes(path.sep + 'Locales' + path.sep)
    ? FORBIDDEN_LOCALE : FORBIDDEN;
// WeakAuras is the one allowed mention: STRIP it, then test the rest of the
// line — a line-level exemption would mask other names sharing the line
const stripAllowed = (line) => line.replace(/weakauras\w*/gi, '');

let hardFail = false;

function walk(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walk(p, out);
        else if (e.name.endsWith('.lua')) out.push(p);
    }
    return out;
}

const files = [];
for (const d of SCAN_DIRS) {
    const p = path.join(ROOT, d);
    if (fs.existsSync(p)) walk(p, files);
}
// vendor libs are TOC-loaded too — a corrupt file breaks the whole load
// chain in-game, so they get the syntax/locals pass (house rules skipped)
const syntaxOnly = [];
for (const d of SYNTAX_ONLY_DIRS) {
    const p = path.join(ROOT, d);
    if (fs.existsSync(p)) walk(p, syntaxOnly);
}

// ---- 1 + 2: syntax + locals -------------------------------------------------
console.log('== syntax + top-level locals ==');
for (const f of [...files, ...syntaxOnly]) {
    const src = fs.readFileSync(f, 'utf8');
    let ast;
    try {
        ast = luaparse.parse(src, { luaVersion: '5.1' });
    } catch (e) {
        console.log('SYNTAX FAIL ' + path.relative(ROOT, f) + ' -> ' + e.message);
        hardFail = true;
        continue;
    }
    let locals = 0;
    for (const s of ast.body) {
        if (s.type === 'LocalStatement') locals += s.variables.length;
        if (s.type === 'FunctionDeclaration' && s.isLocal) locals += 1;
    }
    // At 200 the chunk does not COMPILE -- the whole file is gone, not one
    // feature. 185 left almost no room to react calmly, so warn at 175: still
    // 25 slots, which is a normal amount of work rather than an emergency.
    // The fix is a do-block around a group of narrowly-used locals (their slots
    // are freed at the `end`, the closures keep them as upvalues), or splitting
    // the file. See the CLASS_* block in Modules/Bags.lua for the pattern.
    if (locals >= 200) {
        console.log('LOCALS FAIL ' + path.relative(ROOT, f) + ' -> ' + locals + '/200 (this file no longer compiles)');
        hardFail = true;
    } else if (locals > 175) {
        console.log('LOCALS WARN ' + path.relative(ROOT, f) + ' -> ' + locals + '/200');
    }
}
console.log('checked ' + (files.length + syntaxOnly.length) + ' files ('
    + syntaxOnly.length + ' vendor, syntax-only)');

// ---- 1c: local functions read before their definition ------------------------
// `local function f()` is only a local FROM THAT LINE ON. A call to f written
// above it -- in an earlier function, say -- compiles as a read of the GLOBAL
// f, which is nil, and the file parses, the checker was green, and the crash
// waited for the one code path that runs the line. It shipped twice in one
// day (pageChanged in the meter window, justDragged an hour later), each time
// found by the IDE's linter and by nobody else. The fix is always the same:
// put the name in the forward-declaration list at the top of the file and
// assign `f = function` where the body lives.
//
// A local declaration of the same name at an EARLIER line -- the forward
// declaration, a parameter, an inner local -- makes the read legitimate; the
// scoping is approximated by line order, which is exact for the pattern that
// matters and only ever too lenient otherwise.
console.log('\n== local functions read before their definition ==');
{
    const walkP = (node, fn, parent, key) => {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { node.forEach(n => walkP(n, fn, parent, key)); return; }
        fn(node, parent, key);
        for (const k of Object.keys(node)) if (k !== 'loc' && k !== 'range') walkP(node[k], fn, node, k);
    };
    let hits = 0;
    for (const f of files) {
        let ast;
        try { ast = luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1', locations: true }); }
        catch (e) { continue; }
        // late-defined locals: local function NAME / local NAME = function
        const defs = {};
        for (const s of ast.body) {
            if (s.type === 'FunctionDeclaration' && s.isLocal && s.identifier && s.identifier.type === 'Identifier') {
                defs[s.identifier.name] = s.loc.start.line;
            } else if (s.type === 'LocalStatement' && s.init && s.init.length === 1 && s.init[0].type === 'FunctionExpression') {
                defs[s.variables[0].name] = s.loc.start.line;
            }
        }
        if (!Object.keys(defs).length) continue;
        // every local declaration of those names, any scope, by line
        const declared = {};
        const note = (name, line) => { if (defs[name] !== undefined && (declared[name] === undefined || line < declared[name])) declared[name] = line; };
        walkP(ast, (n) => {
            if (n.type === 'LocalStatement') for (const v of n.variables) note(v.name, n.loc.start.line);
            if (n.type === 'FunctionDeclaration' || n.type === 'FunctionExpression') {
                for (const p of n.parameters || []) if (p.type === 'Identifier') note(p.name, n.loc.start.line);
                if (n.isLocal && n.identifier && n.identifier.type === 'Identifier') note(n.identifier.name, n.loc.start.line);
            }
            if (n.type === 'ForNumericStatement') note(n.variable.name, n.loc.start.line);
            if (n.type === 'ForGenericStatement') for (const v of n.variables) note(v.name, n.loc.start.line);
        });
        const seen = new Set();
        walkP(ast, (n, parent, key) => {
            if (n.type !== 'Identifier') return;
            const name = n.name;
            const defLine = defs[name];
            if (defLine === undefined) return;
            const line = n.loc.start.line;
            if (line >= defLine) return;
            if (declared[name] !== undefined && declared[name] <= line) return;
            // not a read: member names, table keys, declarations, parameters
            if (parent && (parent.type === 'MemberExpression' && key === 'identifier')) return;
            if (parent && parent.type === 'TableKeyString') return;
            if (parent && (parent.type === 'LocalStatement' || parent.type === 'FunctionDeclaration')) return;
            if (parent && parent.type === 'FunctionExpression') return;
            const tag = path.relative(ROOT, f) + ':' + line;
            if (seen.has(tag + name)) return;
            seen.add(tag + name);
            hits++;
            console.log('  NIL-GLOBAL ' + tag + '  ' + name + '() is a local defined at line ' + defLine + ' -- forward-declare it');
            hardFail = true;
        });
    }
    if (hits === 0) console.log('clean');
}

// ---- 3: locale coverage -----------------------------------------------------
console.log('\n== locale coverage (deDE) ==');
const KEY_RE = /L\[\s*"((?:[^"\\]|\\.)*)"\s*\]/g;
const DEF_RE = /\["((?:[^"\\]|\\.)*)"\]\s*=/g;   // global: lines can hold SEVERAL defs
const deSrc = fs.existsSync(DEDE) ? fs.readFileSync(DEDE, 'utf8') : '';
const defined = new Set();
for (const line of deSrc.split('\n')) {
    if (/^\s*--/.test(line)) continue;   // commented-out entries don't count
    let m;
    while ((m = DEF_RE.exec(line)) !== null) defined.add(m[1]);
}
const missing = new Map();
for (const f of files) {
    // skip the locale files themselves (segment match, not substring —
    // a parent folder containing "Locales" in its name must not skip all)
    if (path.relative(ROOT, f).split(path.sep)[0] === 'Locales') continue;
    const src = fs.readFileSync(f, 'utf8');
    for (const line of src.split('\n')) {
        if (/^\s*--/.test(line)) continue;   // doc comments aren't real usages
        let m;
        while ((m = KEY_RE.exec(line)) !== null) {
            if (!defined.has(m[1]) && !missing.has(m[1])) {
                missing.set(m[1], path.relative(ROOT, f));
            }
        }
    }
}
if (missing.size === 0) {
    console.log('all used L[...] keys have deDE entries');
} else {
    console.log(missing.size + ' key(s) missing a deDE entry (English fallback):');
    for (const [k, f] of missing) {
        console.log('  MISSING [' + f + '] ' + (k.length > 90 ? k.slice(0, 90) + '…' : k));
    }
}

// ---- 3b: locale coverage of declarative fields --------------------------------
// Options items, dropdown values and module descriptions are rendered through
// L[<literal>] at draw time, so the bare literal IS the locale key — check 3
// only sees explicit L["..."] and misses all of these. This is how a module
// description shipped untranslated even in German.
console.log('\n== locale coverage (declarative fields, deDE) ==');
const ITEM_TYPES = new Set(['header', 'desc', 'checkbox', 'toggle', 'slider',
    'dropdown', 'button', 'editbox', 'section', 'color', 'keybind', 'custom']);
const FIELD_KEYS = ['label', 'text', 'tooltip', 'title'];
const litVal = (n) => (n && n.type === 'StringLiteral')
    ? ((n.value !== undefined && n.value !== null)
        ? n.value : (n.raw || '').replace(/^["']|["']$/g, ''))
    : null;
// worth translating = contains a real word; anchors, format-only strings,
// colour codes and paths are not locale keys
const wordy = (s) => typeof s === 'string' && /[A-Za-z]{2}/.test(s)
    && !/^[A-Z]+$/.test(s) && !s.includes('\\\\') && !s.includes('Interface\\');

const dynMissing = new Map();
function noteMissing(s, rel, line) {
    if (!wordy(s) || defined.has(s)) return;
    if (!dynMissing.has(s)) dynMissing.set(s, rel + ':' + line);
}
// The language switcher lists every language in ITSELF (someone who needs it
// cannot read the current language) — those endonyms must stay untranslated.
const DYN_EXEMPT_FILES = new Set([path.join('Core', 'Locale.lua')]);
for (const f of files) {
    const rel = path.relative(ROOT, f);
    if (rel.split(path.sep)[0] === 'Locales') continue;
    if (DYN_EXEMPT_FILES.has(rel)) continue;
    let ast;
    try {
        ast = luaparse.parse(fs.readFileSync(f, 'utf8'),
            { luaVersion: '5.1', locations: true });
    } catch (e) { continue; }
    eachNode(ast, (n) => {
        if (n.type !== 'TableConstructorExpression') return;
        const kv = {};
        for (const fl of n.fields || []) {
            if (fl.type === 'TableKeyString' && fl.key) kv[fl.key.name] = fl.value;
        }
        const line = n.loc ? n.loc.start.line : 0;
        const typeVal = litVal(kv.type);
        if (typeVal && ITEM_TYPES.has(typeVal)) {
            for (const k of FIELD_KEYS) {
                const s = litVal(kv[k]);
                if (s !== null) noteMissing(s, rel, line);
            }
        }
        // dropdown entry: { value = ..., text = "..." } — but value == text is a
        // media/identifier list (LSM names etc.), shown raw on purpose
        if (kv.value !== undefined && kv.text !== undefined && !typeVal) {
            const s = litVal(kv.text);
            if (s !== null && s !== litVal(kv.value)) noteMissing(s, rel, line);
        }
        // RegisterModule config: description renders as L[mod.description]
        if (kv.defaults !== undefined && kv.description !== undefined) {
            const s = litVal(kv.description);
            if (s !== null && s !== '') noteMissing(s, rel, line);
        }
    });
}
if (dynMissing.size === 0) {
    console.log('all declarative labels/texts have deDE entries');
} else {
    console.log(dynMissing.size + ' literal(s) missing a deDE entry (English fallback):');
    for (const [k, at] of dynMissing) {
        console.log('  MISSING [' + at + '] ' + (k.length > 90 ? k.slice(0, 90) + '…' : k));
    }
}

// ---- 3c: locale keys nothing reaches -----------------------------------------
// Checks 3 and 3b ask "is every used key translated". This asks the reverse:
// is every translated key still used. Nothing asked that before, so renamed
// labels left their old key behind in all nine files -- 241 of them had piled
// up by 1.42.0, about 8% of every locale file.
//
// Reading string literals from the SYNTAX TREE, not a line regex: a key holding
// \n (the mover captions) is escaped in the source and would never match its
// own definition textually. Both sides go through the same unescaper.
//
// Two whitelists, because a computed L[...] can reach a key no literal spells:
//   1. the patch-notes page strips "NEW: " and looks the remainder up
//      (Modules/Changelog.lua) -- 63 keys that no literal contains
//   2. Modules/ProfessionWindow.lua looks up the difficulty word the client
//      hands back, which exists here only as a table field name
// A WARNING, never a failure: a key can be legitimately parked ahead of the
// feature that will use it, and a stale translation breaks nothing at runtime.
console.log('\n== locale keys nothing reaches ==');
{
    const unesc = (s) => {
        let r = '', i = 0;
        const simple = { n: '\n', t: '\t', r: '\r', a: '\x07', b: '\b', f: '\f', v: '\v', '\\': '\\', '"': '"', "'": "'", '\n': '\n' };
        while (i < s.length) {
            if (s[i] !== '\\') { r += s[i]; i++; continue; }
            const n = s[i + 1];
            if (n === undefined) { r += s[i]; break; }
            if (simple[n] !== undefined) { r += simple[n]; i += 2; }
            else if (/[0-9]/.test(n)) {
                let d = '', j = i + 1;
                while (j < s.length && /[0-9]/.test(s[j]) && d.length < 3) { d += s[j]; j++; }
                r += String.fromCharCode(parseInt(d, 10)); i = j;
            } else { r += n; i += 2; }
        }
        return r;
    };
    const litVal = (node) => {
        const raw = node.raw;
        if (raw.startsWith('[')) {
            const m = /^\[(=*)\[([\s\S]*)\]\1\]$/.exec(raw);
            return m ? m[2].replace(/^\n/, '') : raw;
        }
        return unesc(raw.slice(1, -1));
    };
    const walkAst = (node, fn) => {
        if (!node || typeof node !== 'object') return;
        if (Array.isArray(node)) { node.forEach(n => walkAst(n, fn)); return; }
        fn(node);
        for (const k of Object.keys(node)) if (k !== 'loc') walkAst(node[k], fn);
    };

    const literals = new Set();
    for (const f of files) {
        if (path.relative(ROOT, f).split(path.sep)[0] === 'Locales') continue;
        let ast;
        try { ast = luaparse.parse(fs.readFileSync(f, 'utf8'), { luaVersion: '5.1' }); } catch (e) { continue; }
        walkAst(ast, n => { if (n.type === 'StringLiteral') literals.add(litVal(n)); });
    }
    const reachable = new Set(['orange', 'yellow', 'green', 'gray', 'grey',
        'trivial', 'easy', 'medium', 'optimal', 'difficult']);
    for (const s of literals) {
        const m = /^NEW:\s*(.+)$/.exec(s);
        if (m) reachable.add(m[1]);
    }

    let deAst = null;
    try { deAst = luaparse.parse(deSrc, { luaVersion: '5.1' }); } catch (e) { /* section 1 already reported it */ }
    const unreached = [];
    if (deAst) {
        walkAst(deAst, n => {
            if (n.type !== 'TableKey' || !n.key || n.key.type !== 'StringLiteral') return;
            const k = litVal(n.key);
            if (!literals.has(k) && !reachable.has(k)) unreached.push(k);
        });
    }
    if (unreached.length === 0) {
        console.log('every deDE key is reachable from code');
    } else {
        console.log('  ' + unreached.length + ' key(s) no code literal reaches — dead weight in all nine files:');
        for (const k of unreached.slice(0, 15)) {
            console.log('    UNUSED ' + (k.length > 90 ? k.slice(0, 90) + '…' : k));
        }
        if (unreached.length > 15) console.log('    ... and ' + (unreached.length - 15) + ' more');
    }
}

// ---- 4: quotes in German values ----------------------------------------------
console.log('\n== ASCII quotes inside German values ==');
let qhits = 0;
deSrc.split('\n').forEach((line, i) => {
    if (/^\s*--/.test(line)) return;
    // global + unanchored: lines can hold SEVERAL ["k"] = "v" pairs
    const VAL_RE = /\["(?:[^"\\]|\\.)*"\]\s*=\s*"((?:[^"\\]|\\.)*)"/g;
    let m;
    while ((m = VAL_RE.exec(line)) !== null) {
        if (m[1].includes('\\"')) {
            qhits++;
            console.log('  QUOTE deDE.lua:' + (i + 1));
            break;   // one report per line is enough
        }
    }
});
if (qhits === 0) console.log('clean');

// ---- 5: forbidden names -------------------------------------------------------
console.log('\n== third-party addon names ==');
let nhits = 0;
const tocs = fs.readdirSync(ROOT).filter(n => n.endsWith('.toc')).map(n => path.join(ROOT, n));
for (const f of [...files, ...tocs]) {
    const src = fs.readFileSync(f, 'utf8');
    src.split('\n').forEach((line, i) => {
        if (patternFor(f).test(stripAllowed(line))) {
            nhits++;
            console.log('  NAME ' + path.relative(ROOT, f) + ':' + (i + 1) + '  ' + line.trim().slice(0, 100));
        }
    });
}
if (nhits === 0) console.log('clean');
else console.log('(known pre-existing functional references may be acceptable — judge each hit)');

// ---- 6: writes to bare globals ----------------------------------------------
// The read side of this question is not worth asking: 264 names over 1190 sites,
// almost all of it legitimate game API, unusable without a huge allowlist. The
// WRITE side is exact and tiny - under eighty sites across the whole addon - so
// it needs no guesswork. It is also where the damage is: a global we define is
// visible to every other addon and outlives our own module being switched off.
console.log('\n== writes to bare globals ==');
const GLOBAL_OK = [
    /^SLASH_/,                    // slash commands have to be global by design
    /^BINDING_/,                  // keybinding headers, likewise
    /^Trinkets/,                  // the embedded engine's own namespace
    /^VuloForeverUI(Char)?DB$/,   // our saved variables, declared in the TOC
    // Button libraries read this one by name, so it has to be global. It is
    // allowed here only because it captures the previous definition and hands
    // back to it when our module is off - see Modules/Minimap/Style.lua.
    /^GetMinimapShape$/,
];
// Core/Compat.lua IS the shim layer: its whole job is to fill in absent game
// APIs, and every line there is guarded with "X = X or ...". Anywhere else that
// pattern would be a module quietly redefining something for the whole client.
const GLOBAL_OK_FILES = new Set([path.join('Core', 'Compat.lua')]);

function eachNode(node, cb) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) eachNode(n, cb); return; }
    if (node.type) cb(node);
    for (const k of Object.keys(node)) {
        if (k === 'type' || k === 'loc' || k === 'range') continue;
        eachNode(node[k], cb);
    }
}

let ghits = 0;
for (const f of files) {
    const rel = path.relative(ROOT, f);
    if (rel.split(path.sep)[0] === 'Locales') continue;
    if (GLOBAL_OK_FILES.has(rel)) continue;
    let ast;
    try {
        ast = luaparse.parse(fs.readFileSync(f, 'utf8'),
            { luaVersion: '5.1', scope: true, locations: true });
    } catch (e) { continue; }   // already reported by check 1

    const report = (name, line, how) => {
        if (GLOBAL_OK.some(re => re.test(name))) return;
        ghits++;
        console.log('  GLOBAL ' + rel + ':' + line + '  ' + name + ' (' + how + ')');
    };

    eachNode(ast, (n) => {
        if (n.type === 'AssignmentStatement') {
            for (const t of n.variables || []) {
                if (t.type === 'Identifier' && t.isLocal === false) {
                    report(t.name, t.loc.start.line, 'assignment');
                }
            }
        } else if (n.type === 'FunctionDeclaration' && !n.isLocal && n.identifier
                   && n.identifier.type === 'Identifier' && n.identifier.isLocal === false) {
            report(n.identifier.name, n.identifier.loc.start.line, 'function');
        }
    });
}
if (ghits === 0) console.log('clean');
else console.log('(put it on ns, or guard it with "X = X or ..." if it must be global)');

// ---- 7: module defaults nothing reads ---------------------------------------
// Nothing in the code connects an option to the database key behind it, so a
// default and its reader can drift apart silently - that is how settings end up
// written into every profile with no way to ever take effect. Mentions are
// collected repo-wide (one module can span several files) and STRING LITERALS
// count, so keys reached through a table of names are not falsely reported.
// Limitation: top-level keys of a RegisterModule defaults table only, not
// nested sub-tables.
console.log('\n== module defaults nothing reads ==');
const FRAMEWORK_KEYS = new Set(['enabled']);   // read by Core/Modules.lua itself

function defaultsTable(ast) {
    let found = null;
    eachNode(ast, (n) => {
        if (found || n.type !== 'TableConstructorExpression') return;
        for (const fl of n.fields || []) {
            if (fl.type === 'TableKeyString' && fl.key && fl.key.name === 'defaults'
                && fl.value && fl.value.type === 'TableConstructorExpression') {
                found = fl.value;
            }
        }
    });
    return found;
}

const asts = new Map();
for (const f of files) {
    if (path.relative(ROOT, f).split(path.sep)[0] === 'Locales') continue;
    try {
        asts.set(f, luaparse.parse(fs.readFileSync(f, 'utf8'),
            { luaVersion: '5.1', locations: true }));
    } catch (e) { /* reported by check 1 */ }
}

let ohits = 0;
for (const [f, ast] of asts) {
    const dt = defaultsTable(ast);
    if (!dt) continue;
    const declared = new Map();
    for (const fl of dt.fields || []) {
        if (fl.type === 'TableKeyString' && fl.key && fl.key.name) {
            declared.set(fl.key.name, fl.key.loc.start.line);
        }
    }
    if (!declared.size) continue;

    const dtStart = dt.loc.start.line, dtEnd = dt.loc.end.line;
    const mentioned = new Set();
    for (const [g, gast] of asts) {
        const sameFile = (g === f);
        eachNode(gast, (n) => {
            const line = n.loc && n.loc.start.line;
            if (n.type === 'Identifier' && n.name) {
                if (!(sameFile && line >= dtStart && line <= dtEnd)) mentioned.add(n.name);
            } else if (n.type === 'StringLiteral') {
                const v = (n.value !== undefined && n.value !== null)
                    ? n.value : (n.raw || '').replace(/^["']|["']$/g, '');
                if (typeof v === 'string') mentioned.add(v);
            }
        });
    }

    for (const [name, line] of declared) {
        if (mentioned.has(name) || FRAMEWORK_KEYS.has(name)) continue;
        ohits++;
        console.log('  ORPHAN ' + path.relative(ROOT, f) + ':' + line + '  ' + name);
    }
}
if (ohits === 0) console.log('clean');
else console.log('(delete the default, or wire up the reader it was meant to have)');

// ---- 8: L[...] evaluated at file scope ---------------------------------------
// The saved language choice only exists from ADDON_LOADED. Anything that looks a
// key up while the file is still loading bakes in the CLIENT language and, worse,
// fills the locale cache before the override is known - which is exactly how the
// language option silently did nothing for several releases. Lookups inside any
// function body are fine (they run later), so this walker refuses to descend into
// them: OnEnable, GetOptions and ns.OnLocaleReady(function() ... end) are exempt
// automatically, by construction rather than by a list.
console.log('\n== L[...] resolved at file load ==');
const FILESCOPE_EXEMPT = new Set([path.join('Core', 'Locale.lua')]);
const LOCALE_TABLES = new Set(['L', 'VL']);

function eachTopLevelNode(node, cb) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) eachTopLevelNode(n, cb); return; }
    if (node.type === 'FunctionDeclaration') return;   // runs later, by definition
    if (node.type) cb(node);
    for (const k of Object.keys(node)) {
        if (k === 'type' || k === 'loc' || k === 'range') continue;
        eachTopLevelNode(node[k], cb);
    }
}

let lhits = 0;
for (const [f, ast] of asts) {
    const rel = path.relative(ROOT, f);
    if (FILESCOPE_EXEMPT.has(rel)) continue;
    eachTopLevelNode(ast, (n) => {
        if (n.type !== 'IndexExpression' || !n.base) return;
        const b = n.base;
        const isLocaleTable =
            (b.type === 'Identifier' && LOCALE_TABLES.has(b.name)) ||
            (b.type === 'MemberExpression' && b.identifier
             && LOCALE_TABLES.has(b.identifier.name));
        if (!isLocaleTable) return;
        const key = n.index && (n.index.value !== undefined && n.index.value !== null
            ? n.index.value : (n.index.raw || '').replace(/^["']|["']$/g, ''));
        if (typeof key !== 'string') return;   // L[variable] cannot be judged here
        lhits++;
        console.log('  FILESCOPE-L ' + rel + ':' + n.loc.start.line + '  ' + key.slice(0, 60));
    });
}
if (lhits === 0) console.log('clean');
else {
    hardFail = true;
    console.log('(build it lazily in OnEnable/GetOptions, or wrap the block in ns.OnLocaleReady(function() ... end))');
}

// ---- 9: format specifiers must survive translation ---------------------------
// ns:Print formats its message, so a translation that drops or reorders a %s is
// a hard Lua error at the call site, not a cosmetic bug - and the release process
// now ships fresh translations every version. Only keys actually USED as a format
// string are compared: checking every value would drown in false positives from
// prose like "5% of shadow damage", which parses as a specifier.
console.log('\n== format specifiers across locales ==');
const FORMAT_CALLERS = new Set(['Print', 'Debug', 'format']);
const specs = (s) => (String(s).replace(/%%/g, '').match(/%[-0-9.]*[a-zA-Z]/g) || []).join(',');

const formatKeys = new Set();
for (const [f, ast] of asts) {
    eachNode(ast, (n) => {
        if (n.type !== 'CallExpression' || !(n.arguments || []).length) return;
        const c = n.base;
        const name = c && (c.type === 'MemberExpression' ? c.identifier && c.identifier.name
                                                         : c.type === 'Identifier' ? c.name : null);
        if (!FORMAT_CALLERS.has(name)) return;
        if (n.arguments.length < 2) return;          // nothing substituted: cannot break
        const a = n.arguments[0];
        if (!a || a.type !== 'IndexExpression' || !a.base) return;
        const b = a.base;
        const isLocaleTable =
            (b.type === 'Identifier' && LOCALE_TABLES.has(b.name)) ||
            (b.type === 'MemberExpression' && b.identifier && LOCALE_TABLES.has(b.identifier.name));
        if (!isLocaleTable) return;
        const key = a.index && (a.index.value !== undefined && a.index.value !== null
            ? a.index.value : (a.index.raw || '').replace(/^["']|["']$/g, ''));
        if (typeof key === 'string' && specs(key)) formatKeys.add(key);
    });
}

const PAIR_RE = /\["((?:[^"\\]|\\.)*)"\]\s*=\s*"((?:[^"\\]|\\.)*)"/g;
const unesc = (s) => s.replace(/\\(["\\])/g, '$1');
let fhits = 0;
// No Locales/ at all is a valid state here: keys ARE the English text, so the
// addon runs untranslated and the nine languages get generated once the module
// set is settled.
const LOCALE_DIR = path.join(ROOT, 'Locales');
const localeFiles = fs.existsSync(LOCALE_DIR) ? fs.readdirSync(LOCALE_DIR) : [];
for (const name of localeFiles) {
    if (!name.endsWith('.lua')) continue;
    const src = fs.readFileSync(path.join(ROOT, 'Locales', name), 'utf8');
    const lines = src.split(/\r?\n/);
    lines.forEach((line, i) => {
        if (/^\s*--/.test(line)) return;
        let m; PAIR_RE.lastIndex = 0;
        while ((m = PAIR_RE.exec(line)) !== null) {
            const key = unesc(m[1]);
            if (!formatKeys.has(key)) continue;
            const want = specs(key), got = specs(unesc(m[2]));
            if (want !== got) {
                fhits++;
                console.log('  FORMAT Locales' + path.sep + name + ':' + (i + 1)
                    + '  expected [' + want + '] got [' + got + ']  ' + key.slice(0, 50));
            }
        }
    });
}
console.log('format-string keys checked: ' + formatKeys.size);
if (fhits === 0) console.log('clean');
else {
    hardFail = true;
    console.log('(the translation must keep the same specifiers in the same order as the English key)');
}

// ---- 10: TOC file lists ------------------------------------------------------
// We ship one TOC per flavor and their file lists have to be identical -- a file
// added to one and forgotten in the other simply does not load on that client,
// with no error anywhere. That rule used to be a comment asking a human to
// remember it. Also catches a listed file that does not exist (the addon stops
// loading at that line) and a source file nobody listed (dead weight, or a
// module that silently never runs).
console.log('\n== TOC file lists ==');
const tocNames = fs.readdirSync(ROOT).filter(n => n.endsWith('.toc')).sort();
const tocFiles = new Map();
for (const name of tocNames) {
    const listed = [];
    for (const raw of fs.readFileSync(path.join(ROOT, name), 'utf8').split(/\r?\n/)) {
        // A file entry may carry a load condition or a trailing comment:
        //   Vanilla\Foo.lua [AllowLoadGameType vanilla, tbc]
        // Strip both before testing the path, or the whole thing reads as one
        // long filename that cannot exist and the checker fails on valid TOCs.
        const line = raw.replace(/\[.*$/, '').replace(/#.*$/, '').trim();
        if (!line) continue;
        listed.push(line.replace(/\\/g, path.sep).replace(/\//g, path.sep));
    }
    tocFiles.set(name, listed);
}

let thits = 0;
// (a) every flavor lists exactly the same files, in the same order
const [firstName, ...restNames] = tocNames;
for (const other of restNames) {
    const a = tocFiles.get(firstName), b = tocFiles.get(other);
    const onlyA = a.filter(f => !b.includes(f));
    const onlyB = b.filter(f => !a.includes(f));
    for (const f of onlyA) { thits++; console.log('  TOC-ONLY ' + firstName + ': ' + f); }
    for (const f of onlyB) { thits++; console.log('  TOC-ONLY ' + other + ': ' + f); }
    if (!onlyA.length && !onlyB.length && a.join('|') !== b.join('|')) {
        thits++;
        console.log('  TOC-ORDER ' + firstName + ' and ' + other + ' list the same files in a DIFFERENT order');
    }
}

// (b) every listed file exists, and (c) every source file is listed
const listedAll = new Set();
for (const list of tocFiles.values()) for (const f of list) listedAll.add(f);
for (const [name, list] of tocFiles) {
    for (const f of list) {
        if (!fs.existsSync(path.join(ROOT, f))) {
            thits++;
            console.log('  TOC-MISSING ' + name + ': ' + f + ' (loading stops here)');
        }
    }
}
for (const f of files) {
    const rel = path.relative(ROOT, f);
    if (rel.split(path.sep)[0] === 'Libs') continue;   // vendor, listed via .xml
    if (!listedAll.has(rel)) {
        thits++;
        console.log('  TOC-ORPHAN ' + rel + ' (never loaded)');
    }
}

if (thits === 0) console.log('clean (' + tocNames.length + ' TOCs, '
    + tocFiles.get(firstName).length + ' entries each)');
else hardFail = true;

// ---- 11: release notes match the changelog -----------------------------------
// The packager uploads CHANGELOG-release.md to CurseForge, Wago and the GitHub
// release (see .pkgmeta). When that file is missing or stale it falls back to
// the git log WITHOUT SAYING SO -- and our commit messages are German. That is
// a failure nobody notices until a player reads the release notes, so it is a
// hard fail here rather than a warning.
console.log('\n== release notes ==');
{
    const relPath = path.join(ROOT, 'CHANGELOG-release.md');
    const mdPath  = path.join(ROOT, 'CHANGELOG.md');
    if (!fs.existsSync(mdPath)) {
        console.log('  no CHANGELOG.md - skipped');
    } else if (!fs.existsSync(relPath)) {
        console.log('  MISSING CHANGELOG-release.md (run: node tools/gen_changelog.js)');
        hardFail = true;
    } else {
        const body = fs.readFileSync(mdPath, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
        const lines = body.split(/\r?\n/);
        const start = lines.findIndex((l) => /^##\s+/.test(l));
        let end = lines.length;
        for (let i = start + 1; i < lines.length; i++) {
            if (/^##\s+/.test(lines[i])) { end = i; break; }
        }
        const want = lines.slice(start, end).join('\n').replace(/\s+$/, '');
        const have = fs.readFileSync(relPath, 'utf8').replace(/\r\n/g, '\n').replace(/\s+$/, '');
        if (want !== have) {
            const wv = (lines[start] || '').replace(/^##\s+/, '');
            const hv = (have.split('\n')[0] || '').replace(/^##\s+/, '');
            console.log('  STALE CHANGELOG-release.md: holds ' + (hv || '?')
                + ', changelog is at ' + (wv || '?') + ' (run: node tools/gen_changelog.js)');
            hardFail = true;
        } else {
            console.log('clean (' + (lines[start] || '').replace(/^##\s+/, '') + ')');
        }
    }
}

// ---- 12: secret-value lint ---------------------------------------------------
// A second opinion on rule 2. secretlint.js drives wow-secret-lint, which
// follows a value across a whole file -- through assignments, table fields and
// returns -- which the passes above do not. Its rule table is generated from
// retail 12.1.5, so where it disagrees with the client,
// docs/forever-client-research.md and /vfsecrets win; the baseline in
// secret-lint-baseline.json holds what we have already looked at and accepted.
//
// Only NEW findings fail. A missing devDependency is a note, not a failure:
// check.js has to keep working on a clean clone without npm install.
console.log('\n== secret values ==');
{
    const binName = process.platform === 'win32' ? 'wow-secret-lint.cmd' : 'wow-secret-lint';
    const bin = path.join(__dirname, 'node_modules', '.bin', binName);
    if (!fs.existsSync(bin)) {
        console.log('  wow-secret-lint not installed - skipped (run: npm install in tools/)');
    } else {
        const run = require('child_process').spawnSync(
            process.execPath, [path.join(__dirname, 'secretlint.js')], { encoding: 'utf8' });
        const out = ((run.stdout || '') + (run.stderr || '')).replace(/\s+$/, '');
        if (run.status === 0) {
            console.log('clean (nothing new since the baseline)');
        } else {
            if (out) console.log(out.split('\n').map((l) => '  ' + l).join('\n'));
            console.log('  new secret-value findings'
                + ' (accept with: node tools/secretlint.js --write-baseline)');
            hardFail = true;
        }
    }
}

console.log('\n' + (hardFail ? 'RESULT: FAIL' : 'RESULT: OK (warnings above, if any)'));
process.exit(hardFail ? 1 : 0);
