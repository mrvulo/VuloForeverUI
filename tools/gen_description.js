// VuloForeverUI / tools / gen_description
//
// One description, three markups. docs/curseforge-description.md is the source
// and the only file anyone edits; this writes the BBCode and HTML versions of
// the same text beside it.
//
// WHY THREE
//
// The description editor on the project page has a markup type, and what it
// accepts depends on which one is set. Markdown mode escapes raw HTML and
// prints BBCode literally -- it renders headings and bold, but there is no way
// to colour anything. BBCode and HTML mode both carry colour. Keeping three
// hand-written copies in step is how two of them quietly go stale, so the other
// two are generated.
//
// The purple is the addon's own: themeColor in Modules/GlobalSettings.lua is
// 0.608 / 0.424 / 1.000, which is #9B6CFF. The lighter tone is for slash
// commands, so they read as something you type without competing with a
// heading.
const fs   = require('fs');
const path = require('path');

const ROOT    = path.join(__dirname, '..');
const SRC     = path.join(ROOT, 'docs', 'curseforge-description.md');
const ACCENT  = '#9B6CFF';
const LIGHT   = '#C9A9FF';

const md = fs.readFileSync(SRC, 'utf8').replace(/\r\n/g, '\n');
if (/[<>]/.test(md)) {
    // The Markdown copy is pasted into an editor that escapes HTML, so a stray
    // tag would show up as text on the page. Better to fail here.
    console.error('docs/curseforge-description.md contains < or > -- Markdown mode shows those literally');
    process.exit(1);
}

const lines = md.split('\n');

// ---- inline: bold and `code`, shared by both writers ------------------------
function inline(text, bold, code) {
    return text
        .replace(/\*\*(.+?)\*\*/g, (_, s) => bold(s))
        .replace(/`([^`]+)`/g, (_, s) => code(s));
}

// ---- BBCode -----------------------------------------------------------------
function toBBCode() {
    const out = [];
    let inList = false;
    const ln = (s) => inline(s, (x) => '[b]' + x + '[/b]',
                                (x) => '[color=' + LIGHT + ']' + x + '[/color]');

    for (const raw of lines) {
        const l = raw.trimEnd();
        const item = /^-\s+(.*)$/.exec(l);
        if (!item && inList) { out.push('[/list]'); inList = false; }

        if (/^#\s+/.test(l)) {
            out.push('[size=6][color=' + ACCENT + '][b]' + l.replace(/^#\s+/, '') + '[/b][/color][/size]');
        } else if (/^##\s+/.test(l)) {
            out.push('[size=5][color=' + ACCENT + '][b]' + l.replace(/^##\s+/, '') + '[/b][/color][/size]');
        } else if (/^---+$/.test(l)) {
            out.push('[hr]');
        } else if (item) {
            if (!inList) { out.push('[list]'); inList = true; }
            out.push('[*]' + ln(item[1]));
        } else if (l === '') {
            out.push('');
        } else {
            out.push(ln(l).replace(/(https?:\/\/\S+)/g,
                (u) => '[url=' + u + ']' + u.replace(/^https?:\/\//, '') + '[/url]'));
        }
    }
    if (inList) out.push('[/list]');
    // A blank line after a heading is a paragraph break in Markdown and dead
    // space in BBCode; collapsing runs keeps the page tight.
    return out.join('\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
}

// ---- HTML -------------------------------------------------------------------
function toHTML() {
    const out = [];
    let inList = false;
    const ln = (s) => inline(s, (x) => '<strong>' + x + '</strong>',
                                (x) => '<code style="color:' + LIGHT + '">' + x + '</code>');

    for (const raw of lines) {
        const l = raw.trimEnd();
        const item = /^-\s+(.*)$/.exec(l);
        if (!item && inList) { out.push('</ul>'); inList = false; }

        if (/^#\s+/.test(l)) {
            out.push('<h1 style="color:' + ACCENT + '">' + l.replace(/^#\s+/, '') + '</h1>');
        } else if (/^##\s+/.test(l)) {
            out.push('<h2 style="color:' + ACCENT + '">' + l.replace(/^##\s+/, '') + '</h2>');
        } else if (/^---+$/.test(l)) {
            out.push('<hr>');
        } else if (item) {
            if (!inList) { out.push('<ul>'); inList = true; }
            out.push('  <li>' + ln(item[1]) + '</li>');
        } else if (l === '') {
            // paragraphs are closed as they are written, so a blank line is nothing
        } else {
            out.push('<p>' + ln(l).replace(/(https?:\/\/\S+)/g,
                (u) => '<a href="' + u + '">' + u.replace(/^https?:\/\//, '') + '</a>') + '</p>');
        }
    }
    if (inList) out.push('</ul>');
    return out.join('\n').trim() + '\n';
}

const targets = [
    ['curseforge-description.bbcode.txt', toBBCode()],
    ['curseforge-description.html',       toHTML()],
];
for (const [name, body] of targets) {
    fs.writeFileSync(path.join(ROOT, 'docs', name), body, 'utf8');
    console.log(name + ': ' + body.length + ' characters');
}
