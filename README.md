# VuloForeverUI

A complete, modular UI suite for **World of Warcraft: Forever** (client 1.60.1, interface `16001`).

Unit frames, action bars, nameplates, bags, chat, minimap, damage meter, cooldowns and a long
list of small conveniences — one settings window, one look, live previews for everything.
Every module can be switched off, and off means it registers no events at all.

Fully in **English and German**.

## Install

- **CurseForge:** [VuloForeverUI](https://www.curseforge.com/projects/1704138), or through the CurseForge app
- **GitHub:** the zip from [Releases](https://github.com/mrvulo/VuloForeverUI/releases),
  unpacked into the Forever client's `Interface/AddOns/` folder

In game, `/vfui` opens the settings. On first start a short setup asks for the basics.

The client is still young and moves with every build; so does this addon. Bug reports are
welcome as [issues](https://github.com/mrvulo/VuloForeverUI/issues) — `/vfdiag` collects
errors and blocked actions into a log you can paste along.

## What is in it

### Unit frames and HUD

- **Unit Frames** — player, target, focus and target of target in three looks: Blizzard's
  own with extras, the Classic art, or a flat Modern frame. Class colours, aggro, class icon.
- **Action Bars** — dresses the client's own bars: the look they came with, the old 1.x
  stone band, or flat square icons. Per-bar settings, out-of-range tint, free bag slots on
  the backpack, totem bar for Shamans.
- **Nameplates** — enemy plates with health, cast bar, spell target, threat colours, target
  and hover effects, execute glow, quest progress (3/8, 40%), aura groups for buffs,
  debuffs and crowd control.
- **Resource Bars** — free-standing power, cast and swing timer bars, each placed on its own.
  Shows a spell's cost while you cast it.
- **Cooldown Manager** — icon bars for your own cooldowns; the swipe and countdown are drawn
  by the client, so they keep running in combat. Optional ready sound.
- **Auras** — your buffs and debuffs in rows of your own, dispel-type borders, right-click
  to cancel a buff.
- **Damage Meter** — damage, healing, interrupts, dispels and deaths in up to five windows,
  breakdown per player, a threat tab, and a Classic window style.
- **Minimap** — three looks (Standard, classic ring, flat Modern), movable readouts, quest
  markers for your open objectives with distance and waypoint on click.
- **Minimap Button Collector** — every other addon's minimap button in one box.

### General

- **Bags** — one window for all bags and the bank, sorted into categories, with your own
  categories on top. A search that understands `#epic`, `#boe`, `#upgrade`, `#potion`,
  item level ranges (`20-40`), and / or / not. Upgrade arrows, new-item glow, items you
  cannot use where you stand faded out, bank viewable from anywhere, own sort order.
- **Chat** — the chat in the suite's style: own tabs with unread glow, side buttons, a
  movable frame, and a scrollback that survives a reload.
- **Quality of Life** — sell junk and repair at the merchant, mark junk yourself, faster
  looting, Train all, mail recipients one click away, flight time bar, zone levels on the
  world map, quest colours and quest-line steps, a quest journal per character, a gold
  tracker, trinket slots, auto-answers to the prompts you always click the same way.
- **Reminders** — an icon when one of your own buffs or a weapon enchant is missing; click
  it to cast. Hidden in combat.
- **Tooltip IDs** — spell, item, NPC, quest and many other IDs in tooltips.

### Global

- **Global Settings** — theme, five window styles, fonts, colours, class colours, UI scale,
  graphics preset.
- **Edit Mode** (`/vedit`) — unlock every window of the suite and place it: grid, snapping,
  opacity in and out of combat per window.
- **Profiles** — per character or per class, assigned automatically on login, with
  import/export strings.
- **Bar Setups** — named snapshots of your action bars, macros and keybindings, restored with
  one click.
- **Locales** — English or German, or follow the game client.

## Commands

| Command | Does |
|---|---|
| `/vfui`, `/vulo` | open the settings; add `help`, `modules`, `client`, `setup`, `debug` or `reset` |
| `/vedit` | Edit Mode: unlock the windows and place them |
| `/vfbags`, `/vfchat`, `/vfbars`, `/vfbars2`, `/vfcd`, `/vfmeter` | jump to that module's page (`/vfmeter reset` clears the data) |
| `/vfjournal` | the quest journal |
| `/vfdiag` | diagnostics log for bug reports |
| `/vfsecrets` | which combat values the client lets addons read right now |
| `/vfuiprof` | which modules cost the most time |
| `/rl`, `/reloadui` | reload, refused in combat |

## Built for Forever, not ported

Forever looks like Classic but runs Blizzard's **Mainline** code (internal game type
`camelot`): retail FrameXML, retail Edit Mode and the full retail in-combat addon
restrictions. Classic addons do not run on it, and this one is not a Classic addon with a
patch — it is written against the retail API from the ground up. The research behind that
is in [docs/forever-client-research.md](docs/forever-client-research.md).

What that means in practice:

- **Combat data arrives as secret values.** A secret can be shown, but not compared,
  calculated with or even tested for truth. Every module here passes such values straight
  into the client's own widgets and never decides on them — that is why the frames keep
  working in combat. `Core/Secret.lua` holds the helpers.
- **There is no combat log.** Swing timer, damage meter and threat use the client's own
  sources (`C_SwingTimer`, `C_DamageMeter`) instead.
- **Auras are stricter still** — in restricted content reading them throws, so aura code
  asks first.

## Development

```bash
cd tools && npm install && node check.js
```

`check.js` must print `RESULT: OK` before anything ships. It checks Lua 5.1 syntax and the
200-local cap, locals read before their definition, locale coverage and dead locale keys,
writes to bare globals, unused module defaults, locale lookups at file load, format
specifiers across locales, the TOC file list against disk, the release notes, and last a
secret-value lint that follows a value across a whole file and fails on anything new since
`tools/secret-lint-baseline.json`.

Adding a module is one `ns:RegisterModule` call, an `OnEnable`/`OnDisable` pair and a
`GetOptions`; the file then goes into `VuloForeverUI.toc`. Locale keys are English text, so
a missing translation shows the original instead of a blank; a new language needs only its
own file in `Locales/`.

Releases are built by the packager from a tag and go to CurseForge and GitHub at the same
time; the player-facing notes are in [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
