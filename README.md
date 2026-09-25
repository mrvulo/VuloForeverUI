# VuloForeverUI

Modular UI suite for **World of Warcraft: Forever** (client 1.60.1, interface `16001`).

Successor to VuloClassicUI, which targets Classic Era / Anniversary / Wrath. This is a
separate product, not a port: Forever belongs to Blizzard's **Mainline family** (internal
game type `camelot`), so this addon is written against the retail API, retail Edit Mode
and the retail in-combat restrictions. See
[docs/forever-client-research.md](docs/forever-client-research.md) for how that was
established and what it costs.

Version 0.1.0, and the client it targets is a beta — expect both to move.

## What is in it

Eighteen modules on top of the framework. Every module can be switched off per character,
and off means it registers no events at all.

| Sidebar group | Modules |
|---|---|
| Global | Global Settings (theme, fonts, colours, UI scale, graphics preset), Edit Mode, Locales |
| Unit Frames | Unit Frames — Blizzard's own with extras, a Classic reskin, or our flat Modern frame |
| General | Chat, Bags, Quality of Life (vendor, looting, readouts) |
| HUD | Action Bars, Auras, Cooldown Manager, Damage Meter, Minimap, Minimap Button Collector, Nameplates, Resource Bars |
| Tabs of Global Settings | Profiles (per class, per character, import/export), Bar Setups |
| No row of its own | Minimap Button — switched from Global Settings |

The framework underneath: the settings window with sidebar, search and live previews;
the options builder; profiles with per-class assignment and keybinds; import/export
strings; the first-time setup; the addon's own Edit Mode HUD for its own frames; the
module and slash registries; and `Core/Secret.lua`, which is the reason the rest works at
all — see below.

## Commands

| Command | Does |
|---|---|
| `/vfui`, `/vulo` | open the settings window; add `help`, `modules`, `client`, `setup`, `debug` or `reset` |
| `/vedit` | Edit Mode: unlock the windows and place them |
| `/vfsecrets` | which combat values this client lets the addon read **right now** |
| `/vfuiprof` | which of our modules cost the most time in handlers and tickers |
| `/vfcd`, `/vfbars`, `/vfbars2`, `/vfchat`, `/vfbags`, `/vfmeter` | jump to that module's page (`/vfmeter reset` clears the data) |
| `/vfmmtex` | which classic minimap textures this client ships |
| `/rl`, `/reloadui` | reload, refused in combat |

`/vfsecrets` is the one to run first in the beta, in three places: standing in a city,
mid-fight solo, and in a raid. The restriction state differs, and what it prints decides
which modules are even buildable.

## The one rule

Forever hands addons **secret values** for combat data. A secret can be displayed but not
reasoned about: no arithmetic, no comparison, no concatenation, no use as a table key.
Even a truth test throws — `value or fallback` is a crash, not a fallback.

> **Display a secret, never decide on one.**

`Core/Secret.lua` holds the helpers (`ns.IsSecret`, `ns.CanRead`, `ns.Num`,
`ns:SetHealthFill`, `ns:SetPowerFill`, `ns:SetSpellCooldown`, `ns.AurasRestricted`, and
the `SecretUtil` wrappers). Blizzard's own unit frames pass `UnitHealth()` straight into
`StatusBar:SetValue()`; every module here does the same.

**The combat log is not readable at all.** `CombatLogGetCurrentEventInfo` is nil and
`COMBAT_LOG_EVENT_UNFILTERED` is restricted, so anything that used to count damage, track
other players' casts, watch diminishing returns or drive a swing timer from it needs a
different source or cannot exist. `PLAYER_SWING` + `C_SwingTimer` replace the swing timer;
`C_DamageMeter` replaces the meter.

**Auras are stricter than the rest.** `C_UnitAuras.GetAuraDataByIndex` does not return a
secret in restricted content, it *throws* — aura code has to ask
`ns.AurasRestricted()` first. Cooldowns come back secret; threat stays readable.

## Languages

Keys are English text, so a missing translation shows the original rather than a blank.
English and German both ship complete: every `L[...]` key and every declarative label has
a German entry, and `tools/check.js` fails the build if that stops being true. The
language is picked under **Global → Locales** (Auto follows the game client) and takes
full effect after a `/reload`. More languages need only their own file in `Locales/`.

## Development

```bash
cd tools && npm install && node check.js
```

`check.js` must print `RESULT: OK` before anything ships. It runs, in order: Lua 5.1
syntax and the 200-local cap per chunk, local functions read before their definition,
locale coverage for both `L[...]` keys and declarative fields, locale keys nothing
reaches, ASCII quotes inside German values, third-party addon names, writes to bare
globals, module defaults nothing reads, `L[...]` resolved at file load, format specifiers
across locales, the TOC file list against what is on disk, release notes, and last the
secret-value lint (`tools/secretlint.js`, baseline in `tools/secret-lint-baseline.json`),
which follows a value across a whole file and fails on anything new.

Adding a module: one call to `ns:RegisterModule`, an `OnEnable`/`OnDisable` pair and a
`GetOptions`; a module of several files gets its own folder under `Modules/`. The file
then goes into `VuloForeverUI.toc` — the checker verifies that list against disk.

## Still open in the client

1. Whether LibEditModeOverride works against camelot's Edit Mode. Our own Edit Mode HUD
   (`/vedit`) is what the suite uses; the library is loaded but no module calls it yet.
2. Which power types stay readable, per class and per situation — `/vfsecrets` answers it
   for the character you are on, and the answers differ.
3. How much of the restriction behaviour is intended. Blizzard has already called some of
   it unintentional, so what `/vfsecrets` prints today may not be what it prints next build.

Confirmed in the client and no longer in question: client detection via
`GetBuildInfo()` + `C_SwingTimer`, a plain `.toc` with `## Interface: 16001` loading,
`ReloadUI()` from our own button, and the classic unit-frame art being present.
