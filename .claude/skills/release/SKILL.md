---
name: release
description: >
  Cut a VuloForeverUI release: write the CHANGELOG.md block, bump the TOC
  version, regenerate CHANGELOG-release.md, commit, tag, push, and confirm the
  packager run that uploads to CurseForge and GitHub. Use when the user says
  "release", "bring es raus", "neue version", "changelog", "release notes" or
  "Versionshinweise" in this repo.
---

# Release VuloForeverUI

The tag push does the publishing: `.github/workflows/release.yml` runs the
packager on every `v*` tag, which zips the addon (without `tools`, `docs`,
`CLAUDE.md`, dot-folders) and uploads it to CurseForge and a GitHub release
with `CHANGELOG-release.md` as the notes. Everything before the tag is local
and can be redone; the tag push cannot.

## 1. Orient

```bash
cd ~/addons/VuloForeverUI && git status -sb && git describe --tags --abbrev=0
git log --format='%h %s' $(git describe --tags --abbrev=0)..HEAD
```

The tree must be clean apart from release work. Read every commit since the
last tag; the commit messages are German and for developers, the notes are
English and for players.

**Version rule** (0.x until the user says otherwise): a new module, tab, window
or automatic behaviour the player did not have before is **minor** (0.Y+1.0).
Fixes, polish and new options on existing behaviour are **patch** (0.Y.Z+1),
no matter how many. State the pick and proceed; do not ask.

## 2. Write the CHANGELOG.md block

New `## <version>` section at the top of `CHANGELOG.md`, above the previous
one. House format, copied from 0.8.0:

```
## 0.9.0

**New**

- **<Module name as the player sees it>** — what the player can now do, in
  plain English, wrapped at ~78 columns.

**Changed**

- **<Module>** — ...

**Fixed**

- **<Module>** — the symptom the player saw, not the code cause.
```

- Only the sections that have entries. Group by module, the module name as in
  the options sidebar (English).
- One bullet per thing a player notices. Internal work (refactors, the checker,
  tools, diagnostics nobody sees) stays out.
- **Never name another addon**, not even as "like X". `check.js` greps for the
  known names, but describe behaviour, never origin.
- No in-game patch notes and no translation step exist in this addon: the
  block is English only.

## 3. Bump and generate

1. `## Version: <version>` in `VuloForeverUI.toc`.
2. `node tools/gen_changelog.js` — writes `CHANGELOG-release.md` from the top
   section.
3. `cd tools && node check.js` — must print `RESULT: OK`. Pass 11 fails when
   the two changelog files drift; the version check fails when the TOC and the
   top section disagree.

## 4. Commit, tag, push

Subject ≤ 100 characters (the commit-msg hook refuses longer ones), the
version first, then the headline features in German:

```bash
cd ~/addons/VuloForeverUI && git add CHANGELOG.md CHANGELOG-release.md VuloForeverUI.toc
git commit -m "v0.9.0: <zwei bis vier Stichworte>"
git tag -a v0.9.0 -m "v0.9.0: <same text>"
git push origin master && git push origin v0.9.0
```

No `Co-Authored-By` and no tool attribution, in commit and tag alike.

## 5. Confirm

```bash
gh run list --limit 1
```

The `Release` run for the tag must end `success` (it takes ~25 s; check once
after about a minute, do not poll in a loop). On failure: `gh run view <id>
--log-failed`, fix, then delete and re-push the tag only if the user agrees —
a re-pushed tag uploads a second file to CurseForge.

Report: version, the CurseForge/GitHub release done, and that the player gets
it through the CurseForge app.
