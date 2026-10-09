# Concepts and invariants

The living memory of this addon: what each part is meant to be, the decisions
the player (the owner of this repo) made about it, and the **invariants** —
things that must stay true whatever is changed or added later.

**Rule:** before changing a module, read its section here. After changing it,
update the section in the same commit. A decision the player states in a
session goes here, not only into the commit message.

---

## The player's standing design rules

These apply to every visible change, in every module.

- **Professional and uniform.** One look per element type: all icons in a row
  the same size, cut and frame; arrows the same shape in both states (mirrored,
  never two different textures); no mix of round atlases, glows and plus signs.
- **Nothing ever overlaps.** Every window has a fixed grid: one inner margin
  (10 px) on all sides, fixed gaps between columns, a minimum width that fits
  the header (title, money line, search field ≥ 140 px, every tool button).
  Text that does not fit is cut with an ellipsis, never drawn over a neighbour.
- **Changes show at once.** A setting changed in the options updates the open
  window immediately (e.g. the bag view dropdown switches the open window).
- **Calm at rest, colour on intent.** Unselected icons desaturated and dimmed,
  full colour on hover and when selected; the selection marked by a gold edge
  plus a small gold bar.
- **Both looks, always.** A feature with a Standard and a Modern style is done
  only when it works in both.
- **German first.** Every visible string goes through `L[...]` with a deDE
  entry; the other locales (frFR, esES/esMX, ruRU, ptBR) get the same key.

---

## Engine rules that broke things before (never again)

| Rule | Why | Guard |
|---|---|---|
| Never call `Hide()` / `SetParent()` on a client frame from our code — not even an invisible one. Use `SetAlpha(0)` + move it off screen. | Its `OnHide` runs in our taint. Bags: `ContainerFrameSettingsManager.bagsShown` tainted → bank tab purchase forbidden, Edit Mode exit error in party frames (2026-10-04, re-measured 2026-10-07). | `check.js` taint traps; `Bags.CheckTaint` logs a `taint` diag note |
| Never call into `HelpTip` (`Show/Hide/HideAllSystem`). Only read its pool and set alpha. | Its frame pool is shared with tips the action bars show from secure code. | `check.js` taint traps |
| `SetMouseClickEnabled`, `SetMouseMotionEnabled`, `SetPropagateMouse*` are protected even on our own frames. Only out of combat (`ns:RunOutOfCombatOnce`). | `ADDON_ACTION_BLOCKED` when the chat tabs were first built in a fight. | — |
| A blocked protected call raises nothing; `pcall` returns true. | See memory `protected-call-pcall-lies`. | — |
| Template frames carry absolute frame levels (`PortraitFrameFlatTemplate`: `Bg` 10000, `NineSlice` 498; item buttons 10). Set them explicitly after creating. | Grey veil over the whole bag window. | — |
| Re-anchoring a frame under the mouse (even to the same spot) fires OnLeave/OnEnter. Move a slot only when its place changed. | Bag tooltip blinked on every layout. | — |
| Client alpha animations (`ShowAnim`/`HideAnim` from 1 → 0) override `SetAlpha`. To hide a client panel during a run, change its **scale**, not its alpha. | Loot window still flashed during quick loot. | — |
| No font family of our own (`CreateFontFamily`) on an EditBox. For text in any alphabet use the client's own family (`ChatFontNormal`); plain text the house font. | Our family drew nothing in the chat copy box; the house font showed Chinese as boxes. | — |
| Every combat value may be secret: display it, never decide on it. | CLAUDE.md rule 2. | `secretlint` |

---

## Bags (`Modules/Bags/`)

- **One factory, two windows** (bags, bank) in `Window.lua`; the offline bank
  view is `BankView.lua` and must follow every look change too.
- **Two looks** (`db.style`): `modern` = flat window; `standard` = the same
  window inside the client's `PortraitFrameFlatTemplate` (portrait, title bar,
  close button), our own dark ground under it, the template's `Bg` at level 0
  and `NineSlice` at window level + 1. Window level is 3 (below item buttons at
  10, above the template ground).
- **Header grid:** Modern header starts at `PAD`; Standard at y 30 and x 62
  (right of the portrait). `Window.ContentTop()` is where the first slot row
  starts; the side bar starts there too.
- **Search field:** magnifier, grey placeholder `L["Search"]`, visible edge
  (gold while typing), Enter ends input, Escape clears. Same in both looks.
- **Side bar (`Sidebar.lua`):** the arrow is always there and IS the switch
  (`bagSidebar` / `bankSidebar`). Open → arrow points right, folded → left;
  one texture, mirrored. Icons 22 px, square item icons from the `ICON` table;
  a player-made category or set shows its first item, an empty one a bag.
  Hairline between column and slots.
- **Slot colours:** quality ring for uncommon and better; profession bags
  tinted by bag family (`FAMILY_COLORS` in `Slots.lua`): first the family the
  container reports, then the family of the bag item itself, then — reagent
  bag only — what lies in it (trade goods subclass: leather → leatherworking
  brown, herb → green, …; measured: Forever reports no family for a leather
  reagent bag). A leather reagent bag is brown — the player's call,
  2026-10-08. Only an empty reagent bag gets the general green-teal. In Standard
  the family colour is an edge on full and empty slots; round slots (setting
  "Rounded slots", honoured in both looks) use our round ring — quality first,
  else family. Recently looted items: light blue (`recentColor`).
- **Free-slot count** in the header: ordinary bags, then the special bags
  (any reported family, and the reagent bag slot always) as a second number
  in the special bag's colour. Never fold a reagent bag into the ordinary
  count.
- **Quest starters** carry the client's own yellow "!" (`IconQuestTexture`,
  `TEXTURE_ITEM_QUEST_BANG`), sized to the slot; gone once the quest is taken
  (`QUEST_ACCEPTED` repaints). Setting `markQuestStarter`.
- **Client bag frames** are parked under a hidden frame of ours and never
  hidden by us (see engine rules). A visible one is stashed (alpha 0, off
  screen). On takeover off, a still-open one stays parked until the client
  closes it (`FinishUnpark`).
- **Client tutorials** that wait for the client's bag frame (reagent bag step
  1 and 2) are faded out while the takeover is on (`Tutorials.lua`).

## Resource Bars (`Modules/ResourceBars/`)

- Tabs: Resources, Cast bar, Swing timer, XP bar.
- **XP bar** (`Experience.lua`): default style `client` = overlays and texts on
  the client's own experience bar (it keeps its place, look, blue-while-rested
  colour); style `own` = free-standing bar. Quest XP (orange) and rested
  (blue) after the fill; info line inside the bar by default (left: level and
  pace, right: quests/rested/time and percent), each text shiftable sideways.
  XP/h and time-to-level over the last 15 minutes, session average as fallback.

## Action Bars (`Modules/ActionBars/`)

- Skin only — the client's bars keep their secure clicks.
- Classic band: rows above it lifted by `upperLift` (default 6) so the XP
  strip's texts stay readable. Free bag slots on the backpack count only
  ordinary bags (family 0).
- **Uprank** (`Uprank.lua`): a newly learned rank replaces only the rank that
  was the highest before; lower ranks placed on purpose stay.

## Cooldown Manager (`Modules/CooldownManager/`)

- Own icon bars, driven by duration objects, never by reading numbers.
- Queued next-swing abilities light up like the action bar button
  (`C_Spell.IsCurrentSpell`, alpha folded from the boolean).

## Quality of Life (`Modules/QoL/`)

- Quick loot hides the client loot window by **scale** during the run and
  restores it when something is left (full bags, roll, confirmation).

## Locales

- Keys are English text. deDE is the reference; check.js covers literal
  `L["..."]`, declarative option fields, `RegisterModule` name/group/
  description, tab labels and slash `desc`. Other locales must get every new
  key in the same commit.
