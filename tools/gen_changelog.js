// VuloForeverUI / tools / gen_changelog
//
// Cuts the newest section out of CHANGELOG.md and writes it to
// CHANGELOG-release.md, which is the file .pkgmeta hands to the packager.
//
// WHY THE TWO FILES ARE NOT ONE
//
// CHANGELOG.md is the history, and it grows. What CurseForge, Wago and the
// GitHub release show is ONE version's notes -- handing them the whole file
// would put every past release into the announcement of the current one.
//
// And why either file exists rather than letting the packager do it: without a
// manual changelog the packager builds the notes FROM THE COMMIT MESSAGES since
// the last tag, silently. Commits are written for whoever works on the addon;
// release notes are for whoever plays with it. They are not the same text, and
// the commit messages here are German while the addon ships English.
//
// check.js pass 11 compares the two files and fails when they drift, so this
// runs before every release.
const fs   = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const src  = path.join(ROOT, 'CHANGELOG.md');
const out  = path.join(ROOT, 'CHANGELOG-release.md');

if (!fs.existsSync(src)) {
    console.error('no CHANGELOG.md');
    process.exit(1);
}

// Comments are stripped the same way check.js strips them, or the comparison
// between the two files would never agree.
const body  = fs.readFileSync(src, 'utf8').replace(/<!--[\s\S]*?-->/g, '');
const lines = body.split(/\r?\n/);

const start = lines.findIndex((l) => /^##\s+/.test(l));
if (start < 0) {
    console.error('CHANGELOG.md has no "## <version>" section');
    process.exit(1);
}

let end = lines.length;
for (let i = start + 1; i < lines.length; i++) {
    if (/^##\s+/.test(lines[i])) { end = i; break; }
}

const section = lines.slice(start, end).join('\n').replace(/\s+$/, '');
fs.writeFileSync(out, section + '\n', 'utf8');

const version = lines[start].replace(/^##\s+/, '');
const words   = section.split(/\s+/).length;
console.log('CHANGELOG-release.md written: ' + version
    + ' (' + section.length + ' characters, ' + words + ' words)');
