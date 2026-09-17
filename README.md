# VuloForeverUI

Modular UI suite for **World of Warcraft: Forever** (client 1.60.1, interface `16001`).

Successor to VuloClassicUI, which targets Classic Era / Anniversary / Wrath. This is a
separate product, not a port: Forever belongs to Blizzard's **Mainline family** (internal
game type `camelot`), so this addon is written against the retail API, Edit Mode and the
retail in-combat restrictions. See [docs/forever-client-research.md](docs/forever-client-research.md)
for how that was established and what it costs.

## State

Framework only. No feature modules yet.

| Layer | Files | Status |
|---|---|---|
| Core | Namespace, Locale, Utils, Slash, **Secret**, Database, Modules, Container, Events, Schedule, Profiler, MediaRegistry, Mover, PopupMenu, ColorPicker, Init | carried over from VuloClassicUI, adapted |
| UI | Tooltip, Widgets, StringDialog, Setup, MainFrame, Sidebar, Dashboard, OptionsBuilder, EditMode | carried over unchanged |
| Modules | GlobalSettings, Profiles, Minimap | carried over, flavour gates removed |

What that already gives you: the settings window with sidebar and search, the options
builder, profiles with per-class assignment and keybinds, import/export strings, the
first-time setup, the addon's own Edit Mode HUD for its own frames, the minimap button,
the module registry with per-character enable state, and the slash registry.

## Commands

| Command | Does |
|---|---|
| `/vfui` | open the settings window |
| `/vfui help` | list every command |
| `/vfui client` | what client this is, and what the addon detected |
| `/vfui modules` | registered modules with on/off state |
| `/vfsecrets` | which combat values this client lets the addon read **right now** |
| `/rl` | reload, refused in combat |

`/vfsecrets` is the one to run first in the beta, in three places: standing in a city,
mid-fight solo, and in a raid. The restriction state differs, and what it prints decides
which modules are even buildable.

## The one rule

Forever hands addons **secret values** for combat data. A secret can be displayed but not
reasoned about: no arithmetic, no comparison, no concatenation, no use as a table key.

> **Display a secret, never decide on one.**

`Core/Secret.lua` holds the helpers (`ns.IsSecret`, `ns.CanRead`, `ns.Num`,
`ns:SetHealthFill`, `ns:SetPowerFill`, `ns:SetSpellCooldown`, and the `SecretUtil`
wrappers). Blizzard's own unit frames pass `UnitHealth()` straight into
`StatusBar:SetValue()`; every module here does the same.

**The combat log is not readable at all.** There is no addon-side event info, so anything
that used to count damage, track other players' casts, watch diminishing returns or drive
a swing timer from it has to find another source or not exist. `PLAYER_SWING` +
`C_SwingTimer` replace the swing timer; `C_DamageMeter` replaces the meter.

## Development

```bash
cd tools && npm install && node check.js
```

Checks Lua 5.1 syntax, the 200-local cap per chunk, locale coverage, house rules
(no bare globals, no third-party addon names) and that the TOC file list matches what is
on disk. Exit code 1 only on syntax errors and the locals cap.

Locale files are deliberately absent for now: every `L["..."]` key is its own English
text, so the addon is fully usable untranslated, and the nine languages get generated
once the module set is settled.

## Not yet verified in the client

1. `WOW_PROJECT_ID`, `GetBuildInfo()` and `C_GameRules.GetActiveGameMode()` — `/vfui client`
2. whether LibEditModeOverride works against camelot's Edit Mode
3. which power types stay readable — `/vfsecrets`
4. whether a plain `.toc` with `## Interface: 16001` loads, or a `_Mainline.toc` suffix is needed
