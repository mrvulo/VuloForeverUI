# Nameplates — design (2026-09-20)

Module key `nameplates`, sidebar group HUD. Behaviour, option set, ranges and default values
follow a retail 12.x nameplate addon the user picked as the reference. That addon is all
rights reserved: **no code, texture or font of it is copied.** Everything here is written
fresh from API-level facts, in the house style, with our own media. The reference is never
named — not in code, comments, strings, commits, docs or notes.

## Why this shape

Forever runs the retail 12.x restrictions. For a nameplate unit (checked against the
`forever` UI source, build 69913, `Blizzard_APIDocumentationGenerated`):

| Value | State for addon code |
|---|---|
| `UnitHealth`, `UnitHealthPercent`, `UnitGetTotalAbsorbs`, `GetRaidTargetIndex` | always secret |
| `UnitHealthMax` | secret unless player-controlled |
| `UnitCastingInfo` / `UnitChannelInfo`: name, text, texture, times, `notInterruptible`, `spellID` | secret (`SecretWhenUnitSpellCastRestricted`). `castBarID`, `isTradeskill` never secret |
| `UnitName` | secret for units outside the group — pass to `SetText` |
| `UnitClass`, `UnitGUID`, `UnitCreatureType` | identity-restricted: secret for enemies |
| aura reads | throw in combat (stage 2 uses the `AuraContainer` widget, no Lua reads) |
| `UnitThreatSituation("player", unit)`, `UnitDetailedThreatSituation` vs. non-boss | documented readable |
| `UnitReaction`, `UnitSelectionColor`, `UnitIsTapDenied`, `UnitClassification`, `UnitEffectiveLevel`, `UnitCanAttack`, `UnitIsPlayer`, `UnitAffectingCombat`, `UnitIsUnit(plate, "target"/"focus")` | no secret flag |

This corrects `docs/forever-client-research.md`, which says cast bars of other units "work":
they work only through the display path below. The research doc gets that correction as
part of stage 1.

The rules every file in this module follows:

1. Secrets travel only into widget setters: `SetValue`, `SetMinMaxValues`,
   `SetStatusBarColor`, `SetVertexColor`, `SetTexture`, `SetText`,
   `SetFormattedText` (as a format argument), `SetTimerDuration`.
2. Two-way decisions on a secret boolean are made in C:
   `C_CurveUtil.EvaluateColorValueFromBoolean(bool, a, b)` per colour channel,
   `Region:SetAlphaFromBoolean(bool)`. Threshold decisions on health go through a colour
   curve handed to `UnitHealthPercent`.
3. The only existence test on a possibly secret value is `type(x) == "nil"`.
4. Branches are gated on our own plain state (`plate.isCasting`, `plate.isTarget`, …),
   never on a unit read that can turn secret.
5. Geometry instead of logic where a number is needed: stacked StatusBars position the
   kick tick; nothing is computed in Lua.
6. Nothing is ever written onto a Blizzard frame. Per-frame state lives in weak-keyed
   tables.

All APIs above were confirmed present in the 1.60.1 documentation: both boolean folds,
`CreateUnitHealPredictionCalculator`, `UnitGetDetailedHealPrediction`,
`UnitCastingDuration`/`UnitChannelDuration`, `StatusBar:SetTimerDuration`, duration object
`GetRemainingDuration`/`GetElapsedDuration`/`GetTotalDuration`/`IsZero`,
`C_Spell.GetSpellCooldownDuration`, `SetStackingBoundsFrame`,
`C_NamePlateManager.SetNamePlateHitTestInsets`, `UnitSpellTargetName`,
`UnitShouldDisplaySpellTargetName`, `C_Spell.IsSpellImportant`, `SetFlattensRenderLayers`.
`Blizzard_NamePlates` is not loaded into the secure environment; `NamePlateDriverFrame` and
its mixins are reachable.

## Approach

Own pooled frames on the base plate; Blizzard's unit frame stays alive but invisible.
Rejected: reskinning Blizzard's `UnitFrame` (CompactUnitFrame re-lays it out on every
update, getters return secrets, taint risk) and `NamePlateScriptBaseTemplate`
(undocumented, unproven).

## Stages

Each stage is built, checked with `node check.js`, and tested in the client — out of
combat, with `/vfsecrets force`, and in a real fight — before the next begins.

1. **Enemy plates (core)** — this spec.
2. **Auras** — `AuraContainer` widget, three containers per plate (debuffs, buffs, CC),
   C-evaluated filter strings, duration/stack text through the widget's formatter,
   include/exclude spell lists, dispel glow per group. Own spec.
3. **Friendly plates** — name-only mode through Blizzard's font objects and CVars,
   health-bar mode with own frames, NPC titles, guild line, click-through; nothing inside
   instances where plates are forbidden. Own spec.
4. **Extras** — quest-mob indicator and colour, execute pulse glow, combo points on the
   target plate, range alpha and range text, cast bars in front of all plates, extra glow
   styles, a Blizzard-art style. Own spec.

Dropped for Forever because the client has no such thing: M+/delve logic, follower
dungeons, empowered casts, class resources other than combo points, per-spec presets.

## Stage 1

### Files — `Modules/Nameplates/`

| File | One job | Depends on |
|---|---|---|
| `Nameplates.lua` | `ns:RegisterModule`, defaults, manager events, pool, `ns.plates[unit]`, CVars, hitbox and stacking setup, settings-changed fan-out | everything below |
| `Suppress.lua` | make Blizzard's plate invisible and give it back | — |
| `Plate.lua` | build one plate frame; `SetUnit`/`Clear`; layout; text and icon slots; stacking bounds; raid marker; classification | Health, Colors, CastBar, Target |
| `Health.lua` | fill, absorb, health text, the health coalescer | Core/Secret |
| `Colors.lua` | the bar colour chain, name colour, context caches (group, role, instance) | Core/Secret |
| `CastBar.lua` | one cast-event dispatcher, timer fill, shield, kick-ready colour, kick tick, important cast, cast target, timer text, interrupted flash | Kick, Core/Secret |
| `Kick.lua` | the player's interrupt spell and its cooldown duration object | — |
| `Target.lua` | target, focus, hover: glow, border, highlight, overlay, arrows, scale easing, non-target alpha | — |
| `Options.lua` | `GetOptions` for the three pages | OptionsBuilder |

Outside the folder:

- `Core/Secret.lua` gains `ns.FoldColor(bool, r1,g1,b1, r2,g2,b2)` (three
  `EvaluateColorValueFromBoolean` calls), `ns.AlphaFromBool(region, bool)` and
  `ns.Exists(v)` (`type(v) ~= "nil"`).
- `/vfsecrets` gains a nameplate block (see Testing). It is built **first**: three facts
  decide details of the rest.
- `VuloForeverUI.toc`, `Locales/deDE.lua`, `docs/forever-client-research.md`.

### Suppress.lua

`ns.NP.Suppress(nameplate)` / `Restore(nameplate)`:

- `uf:SetAlpha(0)`, unconditional — never gated on `UnitCanAttack`, which can be false on
  the first frame.
- The unit frame stays parented to the base plate (parking it breaks click selection in
  packs). Its children are reparented to one hidden holder, except `WidgetContainer` and
  `SoftTargetFrame` (reparented to the base plate so they stay alive), and any child that
  `IsForbidden()` or `IsProtected()`. `AurasFrame` goes offscreen separately — its items
  are mouse-enabled and would trap tooltips.
- `pcall(uf.UnregisterAllEvents, uf)`, then re-register `PLAYER_TARGET_CHANGED`,
  `PLAYER_SOFT_FRIEND_CHANGED`, `PLAYER_SOFT_ENEMY_CHANGED`; same `pcall` for
  `uf.castBar`. The driver's next `SetUnit` re-registers everything, so this is repeated
  per unit-added.
- Permanent `hooksecurefunc` on `uf.SetAlpha` (force 0 while we own the plate, with a
  re-entrancy flag) and on `selectionHighlight` `Show`/`SetShown`. Hooked-once state is a
  weak table keyed by frame.
- `hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded")` suppresses before
  `NAME_PLATE_UNIT_ADDED` fires, so Blizzard's plate never flashes.
- Camelot's level box (`PlayerLevelDiffFrame`) and `LevelFrame` are children and go with
  the rest.
- `Restore` returns children and alpha on unit-removed and on module disable.

### Nameplates.lua

- Pool: `CreateFramePool("Frame", UIParent, …)`; pre-warm 20 plates, one per 100 ms,
  starting 2 s after login.
- Manager events: `NAME_PLATE_UNIT_ADDED`/`_REMOVED`, `PLAYER_TARGET_CHANGED`,
  `PLAYER_FOCUS_CHANGED`, `UPDATE_MOUSEOVER_UNIT`, `RAID_TARGET_UPDATE`,
  `PLAYER_REGEN_DISABLED`/`_ENABLED`, `DISPLAY_SIZE_CHANGED`, `UI_SCALE_CHANGED`. All
  through `ns:RegisterEvent` (pcall-wrapped).
- Unit added: `C_NamePlate.GetNamePlateForUnit(unit)`; nil means a forbidden plate — do
  nothing. `UnitIsUnit(unit, "player")` — skip. Attackable → acquire, `Suppress`,
  `plate:SetUnit`. Not attackable → left to Blizzard in stage 1, but watched with
  per-unit `UNIT_FLAGS`/`UNIT_FACTION` so a duel or a faction flip promotes it (and
  demotes it again).
- Target/focus changes touch only the cached old and new plate.
- Mouseover: `UPDATE_MOUSEOVER_UNIT` starts a 0.1 s ticker that lives only while a
  mouseover unit exists.
- CVars, written at enable, each through `pcall(C_CVar.SetCVar, …)`, only when
  `C_CVar.GetCVar(name) ~= nil`, only when the value differs, never in combat (deferred
  to `PLAYER_REGEN_ENABLED`): `nameplateMinScale`/`MaxScale`/`SelectedScale` = 1,
  `nameplateMaxAlpha` = 1, `nameplateMinAlpha` = 0.6, `nameplateMaxAlphaDistance` = 40,
  `nameplateMinAlphaDistance` = -100000, `nameplateOverlapH` = 1,
  `nameplateShowAll` = 1, `ShowClassColorInNameplate`/`nameplateShowClassColor` = 1 (the
  class-colour mirror needs it), `nameplateShowEnemyPets`, and the
  `nameplateStackingTypes` bitfield via `C_CVar.SetCVarBitfield`. The previous values are
  saved once in the profile and restored on module disable. `nameplateOverlapV` is left
  alone.
- Hitbox: out of combat only, `C_NamePlate.SetNamePlateSize(barW * hitboxScaleX%,
  barH * hitboxScaleY%)` and
  `C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, …)`;
  re-applied on display/scale change and after
  `NamePlateDriverFrame.UpdateNamePlateOptions` (hook). Both calls are `HasRestrictions`
  — pcall them and queue for regen-enabled when refused.

### Plate.lua

Frame tree of one plate (all our own, parented to the base plate, `CENTER` on it, frame
level +1, `SetFlattensRenderLayers(true)`):

```
plate
 ├ health (StatusBar)  healthBG, absorb bars + mask, hashLine, highlight, overlay clip
 ├ border (4 edge textures)            ├ glow (8 textures, ADD, from gradient-*.tga)
 ├ textFrame (level 900)  slot texts: top, right, left, center
 ├ iconFrame   raid marker, classification, name-inline raid marker
 ├ arrows (left/right, Media/Icons/arrow_*.tga)
 ├ cast (StatusBar)  castBG, icon, spark, shield, important glow, kick clip
 │                   {kickPositioner, kickMarker, kickTick, kickReadyFill}, text frame
 │                   {castName, castTarget, castTimer}
 └ stackBounds (alpha-0 full-size texture inside a frame → SetStackingBoundsFrame)
```

- Inside the plate subtree, regions that must be placed exactly use two-point anchoring
  (TOP+BOTTOM / LEFT+RIGHT); widths come from settings, never from `GetWidth` — getters
  in this subtree can return secrets.
- `SetUnit` paints health at once; everything else runs in `C_Timer.After(0, …)`.
  Static appearance is cached by generation (`plate.gen` vs. `ns.NP.gen`, bumped on any
  settings change), so plate churn does not restyle.
- Token swap guard: `nameplate.namePlateUnitToken ~= plate.unit` in the health and name
  paths tears down cast/target state and re-evaluates.
- Per-plate unit events (`RegisterUnitEvent`): `UNIT_HEALTH`, `UNIT_MAXHEALTH`,
  `UNIT_ABSORB_AMOUNT_CHANGED`, `UNIT_NAME_UPDATE`, `UNIT_THREAT_LIST_UPDATE`.
- **Text slots** (top, right, left, center). Each element stores its slot; assigning
  evicts the slot's previous occupant to `none`; name-family elements evict each other.
  Elements: `enemyName`, `levelName`, `nameLevel`, `level`, `healthPercent`,
  `healthPercentNoSign`, `healthNumber`, `healthPctNum`, `healthNumPct`,
  `healthPctNumDash`, `healthNumPctDash`, `none`.
  - Name: `UnitName(unit)`; if `ns.Exists(name)` → `SetText`. Combined forms use
    `SetFormattedText("%s | %s", …)`. Width by percent of the bar, optional wrap to two
    lines.
  - Level: `UnitEffectiveLevel`; unreadable or < 0 → `??`. Difficulty colour via
    `GetCreatureDifficultyColor` when readable.
- **Icon slots** (top, right, left, topright, topleft, bottom): stage 1 fills them with
  `raidMarker` (default topright) and `classification` (default topleft); the aura
  elements join in stage 2 using the same eviction rule.
  - Raid marker: `idx = GetRaidTargetIndex(unit)`; `ns.Exists(idx)` →
    `SetRaidTargetIconTexture(tex, idx)`.
  - Classification: Blizzard atlases `nameplates-icon-elite-gold` (elite, worldboss),
    `nameplates-icon-elite-silver` (rareelite), `nameplates-icon-rareelite` (rare);
    hidden inside instances unless the option says otherwise.
- Stacking bounds height = `(4 + nameSize + barH + castH) * stackSpacingScale%`.

### Health.lua

- Fill: `SetMinMaxValues(0, UnitHealthMax(unit))`, `SetValue(UnitHealth(unit))`. Max is
  re-pushed only on `UNIT_MAXHEALTH` (`plate.maxValid` is our flag).
- Absorb: `CreateUnitHealPredictionCalculator()` with
  `SetMaximumHealthMode(WithAbsorbs)` and `SetDamageAbsorbClampMode(MaximumHealth)`;
  `UnitGetDetailedHealPrediction(unit, nil, calc)`. Secret amount → bar range becomes the
  with-absorbs maximum and one absorb StatusBar, anchored to the health fill's edge,
  takes `SetValue(absorb)`. Readable amount → forward/backfill/overflow computed in Lua.
  A mask texture stops sub-pixel bleed. Styles: `blizzard` (Blizzard's absorb art),
  `clean` (flat, own alpha), or any of our bar textures.
- Text: percent is `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` handed to
  `SetFormattedText("%d%%", pct)` / `"%.1f%%"`; number is `AbbreviateNumbers(cur)`.
  **Depends on probe 1** (does `string.format`/`SetFormattedText` take a secret number
  on Forever). If it does not, percent and number elements show nothing in stage 1 and
  the slot dropdown says so; a native-formatter route is then a stage 4 item.
  Dead → `0%` via `UnitIsDeadOrGhost`.
- Coalescer: unit events mark the plate dirty; one OnUpdate frame, shown only while
  something is dirty, drains the set once per frame.

### Colors.lua

Bar colour, highest priority first (stage 1 subset of the reference chain):

1. Tapped (`UnitIsTapDenied`).
2. Threat — only while in a party or raid. `UnitThreatSituation("player", unit)`:
   non-tank ≥3 `dpsHasAggro`, ≥2 `dpsNearAggro`; tank 2 `tankLosingAggro`, <2
   `tankNoAggro`, or `offTankAggro` when another tank holds it (readable role of
   `unit.."target"`; when that is secret, fold per channel with
   `UnitDetailedThreatSituation(tankToken, unit)` as the boolean). `classicTankAggro`
   makes `tankHasAggro` absolute. Tank role: `UnitGroupRolesAssigned("player")`, else the
   option `assumeTank` (Forever has no spec roles — see Open points).
3. Target colour, if enabled. 4. Focus colour, if enabled.
5. Neutral (reaction 4, or attackable and not an enemy) outside instances.
6. Enemy player: class colour. `UnitClass` is identity-restricted, so the colour is read
   from Blizzard's hidden, untainted health bar (`uf.healthBar:GetStatusBarColor()`,
   guarded by `uf.unit == plate.unit`, `IsForbidden`, `type(r) == "number"`) and handed
   straight to `SetStatusBarColor`.
7. Mob tiers from `UnitClassification` / `UnitEffectiveLevel`: boss (worldboss, skull, or
   2+ levels above), miniboss (1+ above, or elite), caster
   (`UnitHasPowerType(unit, Enum.PowerType.Mana)` — verify it exists, else
   `UnitPowerType`), else `enemyInCombat`.
8. Special "has aggro" / "no aggro" colours and their override flags, as in the options.

Non-threat steps pass through the out-of-combat dim: `UnitAffectingCombat(unit)` not a
clean `true` → ×0.6, or the recolour option. Plain colours are compared with the last
applied colour and skipped when equal; secret paths never enter that cache. Triggers:
threat update, combat edges, target/focus change.

Name colour: slot colour, or hostile/neutral by `UnitReaction == 4` when
`enemyNameTextReactionColor` is on.

### CastBar.lua and Kick.lua

- One dispatcher frame registers the `UNIT_SPELLCAST_*` events once
  (`START`, `STOP`, `FAILED`, `INTERRUPTED`, `DELAYED`, `CHANNEL_START`, `CHANNEL_UPDATE`,
  `CHANNEL_STOP`, `INTERRUPTIBLE`, `NOT_INTERRUPTIBLE`, `SUCCEEDED`) and routes by
  `ns.plates[unit]`.
- Start: `UnitCastingInfo(unit)`; `ns.Exists(name)` else `UnitChannelInfo`. Name →
  `SetText`, texture → `SetTexture`. Fill:
  `cast:SetTimerDuration(UnitCastingDuration(unit), nil, Enum.StatusBarTimerDirection.ElapsedTime)`;
  channels `UnitChannelDuration` with `RemainingTime`. `plate.isChannel` is cached at
  start. No duration object → fallback OnUpdate copying min/max/value from Blizzard's
  hidden cast bar.
- Stop handlers hide directly and **never re-read cast info**: under restriction a
  stopped cast can still return a non-nil secret tuple.
- `notInterruptible` is never branched on: shield and grey overlay get
  `SetAlphaFromBoolean`, the fill colour is `ns.FoldColor(notInt, unintCol, castCol)`.
  Re-read on the two interruptible events.
- Kick ready: `Kick.lua` resolves the player's interrupt from a hard-coded per-class id
  list with `C_SpellBook.IsSpellKnownOrInSpellBook` (pet bank wins) — Forever list: Kick,
  Pummel, Shield Bash, Counterspell, Earth Shock, Spell Lock; ids verified in the client.
  `cd = C_Spell.GetSpellCooldownDuration(id)`; `cd:IsZero()` (secret boolean) folds
  `interruptReady` against the base colour. Refreshed on `SPELL_UPDATE_COOLDOWN` /
  `SPELL_UPDATE_USABLE` (registered only while something casts) and a 0.2 s ticker over
  casting plates.
- Kick tick and "ready mid-cast" fill: `kickPositioner` (range 0..total, value elapsed)
  and `kickMarker` (anchored to its fill edge, value = cooldown remaining) inside a clip
  frame; the tick texture hangs on the marker's far edge; `kickReadyFill` spans from
  there to the bar end and collapses by crossing anchors when the kick comes too late.
  Channels use `Enum.StatusBarFillStyle.Reverse`; pixel snapping is re-disabled after
  every `SetFillStyle`. Tick alpha = fold(kickReady, 0, fold(notInt, 0, 1)), every 0.1 s.
- Important cast: `pcall(C_Spell.IsSpellImportant, spellID)` → glow overlay through
  `SetAlphaFromBoolean`, optional bar colour through the fold. One glow style in stage 1
  (pulsing ADD border).
- Cast target: gated by `UnitShouldDisplaySpellTargetName`; `UnitSpellTargetName` →
  `SetText`; class colour from `UnitSpellTargetClass` → `C_ClassColor.GetClassColor` when
  it exists. Combined "spell – target" mode as one `SetFormattedText`.
- Timer text: `durObj:GetRemainingDuration()` → `SetFormattedText("%.1f", …)` at 10 Hz
  from one ticker per casting plate (same probe-1 dependency; without it the timer is
  hidden).
- Interrupted flash, 1 s: bar turns `interruptedFlashColor`, text "Interrupted"; the
  interrupter name from the event's GUID via `GetPlayerInfoByGUID`, else
  `UnitTokenFromGUID` + `UnitName`, passed as a format argument; omitted when nil.
- Icon placement options (outside / part of the bar / right / full height), spark from
  `Media/Castbar/CastingBarSpark.blp`, shield atlas `nameplates-InterruptShield`,
  optional border wrapping health and cast bar, cast scale (eased), focus cast height,
  hide name while casting.

### Target.lua

- Target: glow (8 gradient textures, ADD), border colour, border size, highlight wash,
  overlay texture (any bar texture, split by clip frames into filled and empty part),
  arrows (one style, colour or class colour, scale), hash line at N %, target scale.
- Focus: colour, overlay texture (default none), optional letter "F" with anchor/size/
  offsets, cast height %.
- Hover: highlight wash (default on), overlay texture, glow, border colour/size. Target
  wins over hover.
- Plate scale = target scale × cast scale, eased by one shared OnUpdate that is shown
  only while a plate is animating. Non-target alpha on the plate root (Blizzard's
  occlusion fade still multiplies in), optional "keep focus at full opacity".

### Options.lua

Three pages, grouped like the reference; rows use the builder's two-column layout with
inline swatch / cog / resize-cog icons. Only rows whose function exists in stage 1 are
built. Defaults table = the keys below; stored under the module's profile.

**Display → Style:** `border` none/basic (`showBorder` true), `borderSize` 1–4 (1),
`borderColor` (.067 grey), `wrapBorderCastbar` (false), `bgAlpha` 0–100 (100) + `bgColor`
(.12 grey), `absorbStyle` (blizzard) + `absorbColor` (white) + `absorbAlpha` 5–100,
`healthBarTexture`, `castBarTexture` (LSM statusbar lists, default flat).

**Display → Core Positions:** six icon-slot dropdowns (stage 1 choices: Raid Marker,
Rare/Elite Indicator, None) — `raidMarkerPos` topright, `classificationSlot` topleft; per
slot size 10–50 (26 top/bottom, 24 others), X/Y −300..300, `classificationShowInInstances`
(false), raise strata (false).

**Display → Core Text Positions:** `textSlotTop` enemyName, `textSlotRight`
healthPercent, `textSlotLeft` level, `textSlotCenter` none; per slot colour (white), size
6–30 (10; name 11), X/Y −300..300, wrap, width % 10–150 (100), show % decimal (off).

**Display → Health and Cast Bar:** `healthBarWidth` 100–250 (156), `healthBarHeight`
6–50 (17), `castBarHeight` 10–40 (17), `showCastIcon` (true) + cog: scale 0.5–2 (1),
X/Y −50..50, part of bar, on right, full size, hide border, use target border colour;
`castBgAlpha` (90) + `castBgColor` (.1 grey), `castBorderSize` 0–4 (0) + colour (black),
cast timer none/right/left (right) + colour, size 6–20 (10), X/Y; `castBarOffsetY`
−25..75 (0).

**Display → Cast Colors and Effects:** `castBar` (.70 .40 .90), `interruptReady`
(.92 .35 .20), `castBarUninterruptible` (.45 grey), `castBarImportant` (1 .2 .2) with
`importantCastColorEnabled` (false), shield (true), spark (true); kick hint
none/tick/tick+bar (tick) + `interruptMidCastColor` (.318 .820 .357);
`importantCastGlow` (true) + colour (1 .2 .2); `interruptedFlashEnabled` (true) + colour
(.8 0 0).

**Display → Target, Focus & Hover:** target effect multi-select — glow (on), border
colour, highlight, border size; `targetBorderColor` (white), `targetGlowColor`
(.4117 .6667 1), highlight colour/opacity (white, 20), glow opacity (100), border size
0–4; arrows (off) + colour/class colour + scale 0.5–3 (1); `targetColorEnabled` (false)
+ `target` (.459 .890 .580); `focusColorEnabled` (true) + `focus` (.051 .820 .620);
target/focus/hover overlay texture (none) with colour, opacity 5–100, full alpha on
empty part, don't tint; hover effect multi-select (highlight on), `hoverColor` white,
`hoverAlpha` 30.

**Display → General Text:** spell name side none/left/right/center (left), colour, size
6–20 (10), X/Y, wrap, width % (42), combine with target (false); spell target side
(right), colour / class colour (class), size, X/Y, width % (42), wrap. The two cannot
share a side.

**Colors → Enemy Colors:** `enemyInCombat` (.8 .137 .137), `caster` (.231 .510 .965),
`miniboss`, `boss` (.518 .243 .984), `neutral` (.81 .72 .19), `tapped` (.5 grey),
`darkenEnemiesOOC` (true) + recolour instead (false, .5 grey),
`enemyNameTextReactionColor` (false) + hostile (.39 .11 .09) / neutral colours.

**Colors → Threat Colors (groups only):** `tankLosingAggro` (.81 .72 .19), `tankNoAggro`
(1 .22 .17), `dpsHasAggro` (1 .5 0), `dpsNearAggro` (.81 .72 .19), `dpsNoAggroEnabled`
(false) + `dpsNoAggro` (.35 .75 .35) + overrides (miniboss false, caster false, boss
true), `classicTankAggro` (false), `tankHasAggroEnabled` (false) + `tankHasAggro`
(.05 .82 .62) + overrides (mob type false, boss true), `offTankAggroEnabled` (true) +
`offTankAggro` (.188 .761 .812), `assumeTank` (false).

**General → Spacing:** `stackingEnabled` (true), `stackSpacingScale` 50–200 (100),
`hitboxScaleX`/`Y` 50–250 (100) with an eye that shows the hitbox.

**General → Target and Focus:** hash line (off) + colour + percent 0–100 (30),
`targetScale` 50–200 (100), `nonTargetAlpha` 0–100 (100) + keep focus (true),
`focusCastHeight` 100–200 (100), focus letter (off) + anchor/size 6–40 (18)/X/Y.

**General → Extras:** `castScale` 50–200 (100), `hideEnemyNameWhileCasting` (false),
name raid marker (off) + size 6–32 (14), `showEnemyPets` (false), line-of-sight opacity
(live CVar `nameplateOccludedAlphaMult`, only if it exists; no effect in combat),
`hideEnemyPlatesOOC` (false; writes `nameplateShowEnemies` at the combat edges, read
before write).

Font: the suite-wide nameplate font from GlobalSettings (the row already exists there).
All labels are English locale keys, built inside `GetOptions` — never at file scope;
deDE entries for every new key.

### Media — nothing new

Bar textures `Media/textures/*` + LibSharedMedia; spark `Media/Castbar/CastingBarSpark.blp`;
arrows `Media/Icons/arrow_left.tga`/`arrow_right.tga`; glow drawn from
`Media/textures/gradient-*.tga`; shield, elite/rare icons and the "blizzard" absorb art
are Blizzard atlases. One arrow style; overlay textures come from the bar-texture list.

### Error handling

- Every call on a Blizzard frame is `pcall`ed (`UnregisterAllEvents` is refused on some
  trees). `IsForbidden()` before touching any Blizzard region.
- CVar and hitbox writes: exists-check, pcall, out of combat, retried on regen-enabled.
- Disable restores everything: Blizzard plates, CVars, hitbox insets, driver hooks go
  inert behind an `enabled` flag (hooks cannot be removed).
- An error inside one plate's update must not stop the others: the dispatcher and the
  coalescer call per-plate work through `xpcall` with the addon's error sink.

### Testing

`/vfsecrets` nameplate block, run on a target with a plate, out of combat, with
`/vfsecrets force`, and in a fight:

1. `SetFormattedText("%d%%", UnitHealthPercent(...))` and `string.format` with a secret —
   accepted or thrown.
2. `UnitCastingInfo(target)` while it casts — per field: nil / secret / readable; and
   `UnitCastingDuration` — object or nil.
3. `C_NamePlate.SetNamePlateSize` and `SetNamePlateHitTestInsets` in combat — refused or
   not; `InCombatLockdown()` under the forced CVar.
4. `UnitThreatSituation("player", target)`, `UnitName`, `UnitClassification`,
   `UnitEffectiveLevel`, `GetRaidTargetIndex` state.
5. Which of the scale/alpha/overlap CVars exist.

Results go into `docs/forever-client-research.md`. Then per sub-step: `node check.js` →
`RESULT: OK`; client walk — a pack of mobs (selection by click, stacking), a caster
(cast bar, shield, kick colour with the kick on and off cooldown), a group (threat
colours), a duel (promotion/demotion), `/reload` in combat, module off and on (Blizzard
plates come back intact). Adversarial review of the new files before the stage is called
done.

### To verify in the client source before first use

Found in the 1.60.1 API documentation: `UnitHasPowerType`, `UnitTokenFromGUID`;
`SetRaidTargetIconTexture` is defined in `Blizzard_UnitFrame/Mainline/TargetFrame.lua`.
Not yet located (FrameXML Lua helpers, outside the folders checked so far):
`AbbreviateNumbers`, `GetCreatureDifficultyColor`, `CurveConstants.ScaleTo100`. Each gets
a lookup in the `forever` branch before the code that uses it is written; the fallbacks
are a level text in the slot colour, a percent built with a curve of our own
(`C_CurveUtil.CreateCurve`, 0→0, 1→100), and no health-number element.

### Open points, settled by the probes

- Secret numbers as format arguments (health text, cast timer).
- Whether the hidden Blizzard bar still carries a class colour for enemy players once its
  events are unregistered; if not, `UNIT_NAME_UPDATE`-time colour is read before the
  unregister and kept.
- Tank detection on Forever: if `UnitGroupRolesAssigned` never reports TANK, the
  `assumeTank` option is the only source.
