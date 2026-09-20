# VuloForeverUI

**VuloForeverUI** is a fully modular UI suite built from scratch for **World of Warcraft: Forever**. Dark, minimal, one purple accent throughout — the same look as its Classic sibling, but none of the same code underneath. Forever needed its own addon, and this is it.

## Built for a client that hides its numbers

Forever looks like Classic and behaves like retail. Under the hood it runs the modern restrictions: in combat the game stops telling addons what a health bar, a cast bar or an aura actually contains. Most addons written for Classic simply go blank or throw errors when the fight starts.

Every module here is built the other way round. The addon never reads those numbers — it hands them straight to the game and lets the game draw them. Health bars fill, cast bars run, aura timers tick down, and none of it stops when you enter combat.

## Edit Mode

One editor for everything the suite owns. Drag frames, nudge them with the arrow keys, snap to a grid and align against live guides. Save complete named layouts and switch between them. Everything is scale-aware and pixel-accurate. Open it with `/vedit`.

## Nameplates

Custom enemy nameplates that keep working mid-fight: health with absorb shields, a full cast bar with an interrupt shield, spell name, target and timer, plus a tick that marks the exact moment your own interrupt comes off cooldown. Threat colours by role, class colours for enemy players, separate rows for debuffs, buffs and crowd control, quest markers, raid target icons, elite and rare indicators, and an execute glow. Six freely assignable slots decide what sits where. Friendly plates come as name-only or as a full bar.

## Unit Frames

Three looks for player and target, switchable at any time: Blizzard's own frames with extras added, the original Classic frame art, or a flat modern frame of our own. Class colours, threat display, class icons on the portrait and status text on the bars.

## Damage Meter

Damage, healing, interrupts, dispels and deaths, in up to five windows with a breakdown per player. Forever gives addons no combat log at all, so this reads the game's own combat data instead — which means it keeps counting where a traditional meter cannot.

## Cooldown Manager

Icon bars for your own spell cooldowns. The swipe and the countdown are drawn by the client, so they keep running in combat instead of freezing.

## Resource Bars

Free-standing bars for your power, your casting and your swing timer, each placed wherever you want it. The swing timer uses the client's own swing events.

## Bags, Minimap and the small stuff

A minimap button that opens the suite, and a collector that gathers every other addon's minimap buttons into one tidy box. Buff and debuff timers shortened to one letter: 58m, 2h, 4s. Saved action bar setups that restore your buttons, macros and keybindings in one click.

## Modular by Design

Every feature is a standalone module you can switch off individually. Run the whole suite or just the one piece you came for — nothing loads that you did not ask for.

## Profiles

Named profiles with completely separate settings, exportable as a string. A default profile can be assigned per class and loads itself when you log in.

## Localization

Fully localized in English and German.

---

## Included Modules

- **Edit Mode** *(movers, grid, snapping, named layouts)*
- **Nameplates** *(enemy and friendly plates, auras, cast bar, interrupt tick)*
- **Unit Frames** *(Blizzard, Classic or Modern look)*
- **Damage Meter** *(five windows, per-player breakdown, no combat log needed)*
- **Cooldown Manager** *(cooldown bars drawn by the client)*
- **Resource Bars** *(power, cast bar, swing timer)*
- **Minimap Button** *(quick access, Shift+drag to move)*
- **Minimap Button Collector** *(one box for every other addon's button)*
- **Short Buff Durations** *(58m instead of 58 min)*
- **Bar Setups** *(save and restore bars, macros, keybindings)*
- **Profiles** *(per-class defaults, import and export)*
- **Global Settings** *(fonts, colours, scale, per-module font overrides)*

## Getting started

`/vfui` opens the suite. `/vedit` opens Edit Mode.

## A note on the state of things

Forever is in beta, and so is this. Version 0.1.0 runs, the nameplates are tested in the live beta client, and the rest is in active development. Bug reports are genuinely useful right now — the client changes from build to build, and so does what an addon is allowed to do.

Source, issues and releases: https://github.com/mrvulo/VuloForeverUI
