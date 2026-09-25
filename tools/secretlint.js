#!/usr/bin/env node
// Secret-value lint for VuloForeverUI.
//
// wow-secret-lint refuses an addon folder whose .toc says `## Interface: 16001`
// -- it reads five digits starting with 1 as Classic, and Classic has no secret
// values. Forever is Mainline with secrets, so we hand the linter the file list
// ourselves, force the retail surface, and tell it about our own guards from
// Core/Secret.lua.
//
// The rule table is generated from retail 12.1.5, not from 1.60.1. Where the two
// disagree, docs/forever-client-research.md and /vfsecrets in the client win.
// Treat this as a second opinion: it reads flow across a file, which check.js
// does not.
//
//   node secretlint.js                     report what is new since the baseline
//   node secretlint.js --all               report everything, baseline ignored
//   node secretlint.js --write-baseline    accept the current findings

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const TOC = path.join(ROOT, "VuloForeverUI.toc");
const BASELINE = path.join(__dirname, "secret-lint-baseline.json");

// Our wrappers in Core/Secret.lua. ns.IsSecret answers "is this secret",
// ns.CanRead answers "may I look at it" -- the linter's two guard kinds.
const SECRET_GUARDS = "IsSecret,ns.IsSecret";
const ACCESS_GUARDS = "CanRead,ns.CanRead,Num,ns.Num";

// Libs are third-party.
const SKIP = [/^Libs[\/]/i];

function tocFiles() {
    return fs.readFileSync(TOC, "utf8")
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => line && !line.startsWith("#") && line.toLowerCase().endsWith(".lua"))
        .filter((line) => !SKIP.some((re) => re.test(line)))
        // Kept relative to the addon root, and the linter is run from there:
        // the baseline records findings BY PATH, so a run from tools/ and a run
        // from the repo root must not spell the same file two different ways.
        .map((line) => line.split("\\").join("/"))
        .filter((file) => fs.existsSync(path.join(ROOT, file)));
}

const argv = process.argv.slice(2);
const files = tocFiles();
if (files.length === 0) {
    console.error("secretlint: no addon Lua files listed in VuloForeverUI.toc");
    process.exit(1);
}

const args = [
    "--game=retail",
    "--patch=12.1.5",
    // Warnings do not change the exit code on their own, and most of what we
    // care about -- a boolean test or a comparison on a value that MIGHT be
    // secret -- is filed as a warning. The baseline carries the ones we have
    // already judged, so anything left over is new and should stop a release.
    "--max-warnings=0",
    `--secret-guard=${SECRET_GUARDS}`,
    `--access-guard=${ACCESS_GUARDS}`,
];

if (argv.includes("--write-baseline")) {
    args.push(`--write-baseline=${BASELINE}`);
} else if (!argv.includes("--all") && fs.existsSync(BASELINE)) {
    args.push(`--baseline=${BASELINE}`);
}
args.push(...argv.filter((a) => a !== "--all" && a !== "--write-baseline"));

const bin = path.join(__dirname, "node_modules", ".bin",
    process.platform === "win32" ? "wow-secret-lint.cmd" : "wow-secret-lint");
const run = spawnSync(bin, args.concat(files), {
    cwd: ROOT,
    stdio: "inherit",
    shell: process.platform === "win32",
});
process.exit(run.status === null ? 1 : run.status);
