// Structural check of the declarative options pages.
//
//   node tools/optcheck.cjs             -- check Modules/ and UI/
//   node tools/optcheck.cjs --selftest  -- prove the checks still fire
//   node tools/optcheck.cjs <file.lua>  -- check one file
//
// WHY THIS IS PARSED AND NOT GREPPED
// All four findings below are about WHERE a table sits, not what a line says.
// A text search cannot see nesting, and the first three of these shipped as
// real bugs before this file existed.
//
// WHAT IT LOOKS FOR
//   1. subOptions on an item inside a group. UI:PlaceGroup calls createWidget
//      directly -- both its row and its columns branch -- and never draws a
//      gear. The setting is then on no page and behind no gear: gone, silently.
//   2. subOptions on a type that gets no card (button, desc, custom, ...).
//      Same silent loss, different cause.
//   3. two gears on one page sharing an expansion key. The key is item.subKey,
//      or the label when there is none, so two rows with the same label open
//      together. This is what item.subKey exists for.
//   4. a segmented row whose values are not a literal list of 2 to 4 entries.
//      Values from a function (VisibilityValues()) would draw a dozen buttons
//      three pixels wide.
//
// RUN THE SELF-TEST WHEN YOU TOUCH THIS FILE. Check 1 was silently dead on the
// first write -- the flag was handed to the items TABLE instead of to each item
// -- and a check that cannot fail is worse than no check, because it is trusted.
'use strict';
const fs = require('fs');
const path = require('path');
const luaparse = require(path.join(__dirname, 'node_modules', 'luaparse'));

const ROOT = path.resolve(__dirname, '..');
const CARD_TYPES = new Set(['toggle', 'checkbox', 'dropdown', 'editbox', 'slider', 'color', 'segmented']);

const SELFTEST = `
return {
    { type = "group", layout = "row", items = {
        { type = "checkbox", label = L["Trap one"],
          subOptions = { { type = "slider", label = L["Hidden for ever"] } } },
    } },
    { type = "checkbox", label = L["Same label"],
      subOptions = { { type = "slider", label = L["A"] } } },
    { type = "checkbox", label = L["Same label"],
      subOptions = { { type = "slider", label = L["B"] } } },
    { type = "segmented", label = L["Too many"], values = {
        { value = "a", text = L["A"] }, { value = "b", text = L["B"] },
        { value = "c", text = L["C"] }, { value = "d", text = L["D"] },
        { value = "e", text = L["E"] },
    } },
    { type = "segmented", label = L["From a function"], values = SomeValues() },
    { type = "button", label = L["Press me"],
      subOptions = { { type = "slider", label = L["Also lost"] } } },
    { type = "checkbox", label = L["Perfectly fine"], subKey = "ok/1",
      subOptions = { { type = "slider", label = L["Visible"] } } },
}
`;

function walkFiles(dir, out) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walkFiles(p, out);
        else if (e.name.endsWith('.lua')) out.push(p);
    }
    return out;
}

const str = n => {
    if (!n) return null;
    if (n.type === 'StringLiteral') {
        return (n.value !== undefined && n.value !== null) ? n.value : String(n.raw).slice(1, -1);
    }
    if (n.type === 'IndexExpression') return str(n.index);   // L["Label"]
    return null;
};

function fields(node) {
    const out = {};
    if (!node || node.type !== 'TableConstructorExpression') return out;
    for (const f of node.fields) {
        if (f.type === 'TableKeyString') out[f.key.name] = f.value;
        else if (f.type === 'TableKey' && f.key.type === 'StringLiteral') out[str(f.key)] = f.value;
    }
    return out;
}
const arrayParts = node =>
    (node && node.type === 'TableConstructorExpression')
        ? node.fields.filter(f => f.type === 'TableValue').map(f => f.value) : [];

const problems = [];
const gearKeys = {};
let gearCount = 0;

function visit(node, file, insideGroup) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) visit(n, file, insideGroup); return; }

    if (node.type === 'TableConstructorExpression') {
        const f = fields(node);
        const t = str(f.type);
        const line = node.loc ? node.loc.start.line : 0;

        if (f.subOptions) {
            gearCount++;
            if (insideGroup) {
                problems.push(`${file}:${line}  subOptions in einer Gruppe -- PlaceGroup zeichnet nie ein Zahnrad`);
            }
            if (t && !CARD_TYPES.has(t)) {
                problems.push(`${file}:${line}  subOptions auf type="${t}" -- kein Kartentyp, also kein Zahnrad`);
            }
            const key = str(f.subKey) || str(f.label) || ('?' + line);
            gearKeys[file] = gearKeys[file] || {};
            (gearKeys[file][key] = gearKeys[file][key] || []).push(line);
        }

        if (t === 'segmented') {
            const vals = f.values;
            if (!vals || vals.type !== 'TableConstructorExpression') {
                problems.push(`${file}:${line}  segmented ohne woertliche Werteliste`);
            } else {
                const n = arrayParts(vals).length;
                if (n < 2 || n > 4) {
                    problems.push(`${file}:${line}  segmented mit ${n} Werten (erlaubt 2-4)`);
                }
            }
        }

        // The flag has to reach each ITEM table, so a group's items are visited
        // one by one. Handing it to the items TABLE loses it one level early.
        const isGroup = (t === 'group');
        for (const f2 of node.fields) {
            const isItems = f2.type === 'TableKeyString' && f2.key.name === 'items';
            const child = f2.value !== undefined ? f2.value : f2;
            if (isGroup && isItems) {
                for (const el of arrayParts(child)) visit(el, file, true);
            } else {
                visit(child, file, false);
            }
        }
        return;
    }

    for (const k of Object.keys(node)) {
        if (k === 'loc' || k === 'range') continue;
        visit(node[k], file, insideGroup);
    }
}

function scan(label, src) {
    let ast;
    try {
        ast = luaparse.parse(src, { luaVersion: '5.1', locations: true });
    } catch (e) {
        problems.push(`${label}  NICHT PARSEBAR: ${e.message}`);
        return;
    }
    visit(ast.body, label, false);
}

// Runs after everything is scanned, in BOTH modes. It lived only in the file
// path at first, so the self-test reported four of five and blamed a check that
// was fine.
function reportDuplicateGears() {
    for (const file of Object.keys(gearKeys)) {
        for (const key of Object.keys(gearKeys[file])) {
            const lines = gearKeys[file][key];
            if (lines.length > 1) {
                problems.push(`${file}  Zahnrad-Schluessel "${key}" ${lines.length}x (Zeilen ${lines.join(', ')}) -- ein Klick oeffnet alle`);
            }
        }
    }
}

const arg = process.argv[2];
let scanned = 0;

if (arg === '--selftest') {
    scan('selftest', SELFTEST);
    reportDuplicateGears();
    const want = 5;
    console.log(`selftest: ${problems.length} von ${want} erwarteten Befunden`);
    problems.forEach(p => console.log('  ' + p));
    if (problems.length !== want) {
        console.log('\nRESULT: SELBSTTEST FEHLGESCHLAGEN -- eine Pruefung feuert nicht mehr');
        process.exit(1);
    }
    console.log('\nRESULT: OK (alle Pruefungen feuern)');
    process.exit(0);
}

const files = arg ? [path.resolve(arg)]
                  : walkFiles(path.join(ROOT, 'Modules'), []).concat(walkFiles(path.join(ROOT, 'UI'), []));
for (const file of files) {
    scanned++;
    scan(path.relative(ROOT, file).replace(/\\/g, '/'), fs.readFileSync(file, 'utf8'));
}

reportDuplicateGears();

console.log(`${scanned} Datei(en), ${gearCount} Zahnraeder`);
if (!problems.length) {
    console.log('RESULT: OK');
} else {
    console.log(`\n${problems.length} BEFUND(E):`);
    problems.forEach(p => console.log('  ' + p));
    console.log('\nRESULT: FEHLER');
    process.exit(1);
}
