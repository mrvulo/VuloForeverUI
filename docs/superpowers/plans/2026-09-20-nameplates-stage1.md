# Nameplates Stage 1 (enemy plates) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enemy nameplates built from our own frames — health, text slots, colours, full cast bar, target/focus/hover effects, markers, stacking, hitbox, options — that survive combat on the Forever client.

**Architecture:** Pooled plain frames parented to the `C_NamePlate` base plate; Blizzard's unit frame stays alive at alpha 0 with its children parked. Secrets only ever reach widget setters; two-way decisions on secret booleans are folded in C. Event-driven, no per-plate OnUpdate. Spec: `docs/superpowers/specs/2026-09-20-nameplates-design.md`.

**Tech Stack:** Lua 5.1 (WoW 1.60.1, interface 16001, retail 12.x API), house framework on `ns`, `node tools/check.js` as the static gate, the beta client as the runtime test.

## Global Constraints

- Retail API only; no Classic globals, no compat shim.
- Display a secret, never decide on one: no arithmetic, comparison, concatenation, boolean test or table key on a value that can be secret. Existence test is `type(x) ~= "nil"` (`ns.Exists`).
- Everything lives on `ns`; module-shared state on `ns.NP`. No bare globals.
- Never name another addon — code, comments, strings, commits, docs.
- Locale keys are English text; never evaluate `L[...]` at file scope. Every new key gets a `Locales/deDE.lua` entry (no raw ASCII `"` inside German values).
- Nothing is written onto a Blizzard frame; per-frame state goes in weak-keyed tables. Every call on a Blizzard frame is `pcall`ed; check `IsForbidden()` first.
- CVar and hitbox writes: exists-check, `pcall`, out of combat (`ns:RunOutOfCombat`), only when the value differs.
- Lua's 200-locals-per-function cap is enforced by the checker: keep file-scope locals low, put shared state on `ns.NP`.
- Every new file is added to `VuloForeverUI.toc` in load order; `cd tools && node check.js` must print `RESULT: OK` before each commit.
- Before using an API not yet confirmed in the spec, look it up in the `forever` branch of the UI source.
- Commit messages: German, house style, ending with the Co-Authored-By line.
- No new media files.

## File structure

```
Core/Secret.lua                     + ns.Exists, ns.FoldColor, ns.AlphaFromBool, /vfsecrets nameplate block
Modules/Nameplates/Nameplates.lua   module, defaults, ns.NP, pool, manager events, CVars, hitbox
Modules/Nameplates/Suppress.lua     ns.NP.Suppress / Restore / InstallDriverHook
Modules/Nameplates/Health.lua       ns.NP.Health.*
Modules/Nameplates/Colors.lua       ns.NP.Colors.*
Modules/Nameplates/Kick.lua         ns.NP.Kick.*
Modules/Nameplates/CastBar.lua      ns.NP.Cast.*
Modules/Nameplates/Target.lua       ns.NP.Target.*
Modules/Nameplates/Plate.lua        ns.NP.Plate (mixin): Build, SetUnit, Clear, ApplyAppearance, Layout
Modules/Nameplates/Options.lua      M:GetOptions
```

TOC order: `Nameplates.lua` (creates `ns.NP`, registers the module, holds no plate logic at file scope), `Suppress`, `Health`, `Colors`, `Kick`, `CastBar`, `Target`, `Plate`, `Options`. `Nameplates.lua` only calls into the others from `OnEnable` and event handlers, so loading first is safe.

Shared names (every task uses exactly these):

- `ns.NP` — module table; `ns.NP.mod` the registered module; `ns.NP.db()` → `mod.db`; `ns.NP.plates[unit]` → plate; `ns.NP.gen` appearance generation (number); `ns.NP.Bump()` increments it and restyles live plates; `ns.NP.ctx` = `{ inGroup, isTank, inInstance }` (plain booleans, refreshed by Colors).
- Plate fields: `unit`, `nameplate`, `gen`, `isTarget`, `isFocus`, `isHover`, `isCasting`, `isChannel`, `maxValid`, `health`, `healthBG`, `absorb`, `cast`, `texts` (`top/right/left/center` FontStrings), `icons` (`raid`, `classif`, `nameRaid`).

---

### Task 1: Secret helpers and `/vfsecrets` nameplate probes

**Files:** Modify `Core/Secret.lua`, `docs/forever-client-research.md`.

**Produces:** `ns.Exists(v) -> boolean`; `ns.FoldColor(bool, r1,g1,b1, r2,g2,b2) -> r,g,b` (first colour when `bool` is true; plain booleans take a Lua branch, anything else goes through `C_CurveUtil.EvaluateColorValueFromBoolean` per channel); `ns.AlphaFromBool(region, bool)` (`region:SetAlphaFromBoolean(bool)`, or `SetAlpha(bool and 1 or 0)` for a plain boolean).

- [ ] Look up the exact signatures of `EvaluateColorValueFromBoolean` and `SetAlphaFromBoolean` in the `forever` docs (`CurveUtilDocumentation.lua`, `SimpleRegionAPIDocumentation.lua`); write the three helpers.
- [ ] Add the nameplate block to the `/vfsecrets` report, each probe in its own `pcall` (existing `probe` helper), target required:
  1. `SetFormattedText("%d%%", UnitHealthPercent("target", true, CurveConstants.ScaleTo100))` on a scratch FontString; `string.format("%d", secret)`; `AbbreviateNumbers(UnitHealth("target"))` into `SetText` — report accepted / throws; also report whether `CurveConstants`, `AbbreviateNumbers`, `GetCreatureDifficultyColor` exist.
  2. `UnitCastingInfo("target")` / `UnitChannelInfo` — per field nil / secret / readable; `UnitCastingDuration("target")` — object or nil.
  3. `C_NamePlate.SetNamePlateSize(GetNamePlateSize())` and `C_NamePlateManager.SetNamePlateHitTestInsets` with the current insets — ok / refused (values unchanged, so the probe has no side effect).
  4. State of `UnitThreatSituation("player","target")`, `UnitName`, `UnitClassification`, `UnitEffectiveLevel`, `UnitClass`, `GetRaidTargetIndex`, `UnitIsUnit(nameplate token, "target")`.
  5. Existence (`C_CVar.GetCVar(name) ~= nil`) of `nameplateMinScale`, `nameplateMaxScale`, `nameplateSelectedScale`, `nameplateMinAlpha`, `nameplateMaxAlpha`, `nameplateMaxAlphaDistance`, `nameplateMinAlphaDistance`, `nameplateOverlapH`, `nameplateOccludedAlphaMult`, `nameplateStackingTypes`, `nameplateShowAll`, `nameplateShowEnemyPets`, `nameplateShowClassColor`.
  6. The player's interrupt: which of the candidate spell ids is known (`C_SpellBook.IsSpellKnownOrInSpellBook`), and `C_Spell.GetSpellCooldownDuration(id)` → object / nil.
- [ ] `node check.js` → `RESULT: OK`. Commit.
- [ ] **Client checkpoint (user):** run `/vfsecrets` with a casting target out of combat, with `/vfsecrets force`, and in a fight; paste the output. Record results in the research doc (and correct its "cast bars of other units work" line). Decisions that follow: health-text path (format argument vs. empty), hitbox-in-combat handling, CVar list.

Tasks 2–8 do not wait for the checkpoint; only Task 4's text path and Task 2's CVar list are adjusted by it.

### Task 2: Module skeleton, pool, suppression

**Files:** Create `Modules/Nameplates/Nameplates.lua`, `Suppress.lua`, `Plate.lua` (bar-only first version); modify `VuloForeverUI.toc`, `Locales/deDE.lua`. `UI/Sidebar.lua` already lists `nameplates`.

**Produces:** `ns.NP` with the shared names above; `ns.NP.Suppress(nameplate)`, `ns.NP.Restore(nameplate)`, `ns.NP.InstallDriverHook()`; `ns.NP.Plate:Build()`, `:SetUnit(unit, nameplate)`, `:Clear()`; `ns.NP.Acquire()`, `ns.NP.Release(plate)`.

- [ ] `Nameplates.lua`: `ns:RegisterModule("nameplates", { name = "Nameplates", group = "HUD", description = …, defaults = { …all stage-1 keys from the spec… } })`. `OnEnable`: install hooks once, register manager events via `self:RegisterEvent`, apply CVars (saving previous values into `db.savedCVars` once), apply hitbox, adopt plates that already exist (`C_NamePlate.GetNamePlates()`), start pool pre-warm (20 plates, one per 100 ms, 2 s after login, via `ns:AddTicker`). `OnDisable`: release all plates, `Restore` every base plate, restore CVars and hitbox insets.
- [ ] Unit added: nil base plate → return; `UnitIsUnit(unit,"player")` → return; `UnitCanAttack("player", unit)` plain true → acquire + suppress + `SetUnit`; otherwise remember in `ns.NP.pending[unit]` and watch `UNIT_FLAGS`/`UNIT_FACTION` for promotion. Unit removed: release, restore, forget.
- [ ] `Suppress.lua` exactly as the spec's Suppress section (alpha 0 unconditional; children to a hidden holder except `WidgetContainer`/`SoftTargetFrame`/forbidden/protected; `AurasFrame` offscreen; pcall'd `UnregisterAllEvents` + three re-registers on `uf` and `uf.castBar`; `SetAlpha` and `selectionHighlight` hooks guarded by weak tables and `ns.NP.mod.active`; driver hook `OnNamePlateAdded`).
- [ ] `Plate.lua` v1: frame + health StatusBar + background + 1 px border via `ns.MakeEdges`/`ns.LayoutEdges`; `SetUnit` parents to the base plate, centres, `SetFlattensRenderLayers(true)`, pushes `SetMinMaxValues(0, UnitHealthMax)` / `SetValue(UnitHealth)`, registers `UNIT_HEALTH`/`UNIT_MAXHEALTH` unit events on the plate frame itself.
- [ ] `node check.js` → OK. Client: plates show as plain bars, Blizzard's are gone, clicking selects, `/reload` in combat is clean, module off brings Blizzard's plates back. Commit.

### Task 3: Layout, text slots, icon slots, stacking, hitbox

**Files:** Modify `Plate.lua`, `Nameplates.lua`.

**Produces:** `Plate:ApplyAppearance()` (static styling, guarded by `self.gen ~= ns.NP.gen`), `Plate:Layout()`, `Plate:UpdateName()`, `Plate:UpdateLevel()`, `Plate:UpdateRaidMarker()`, `Plate:UpdateClassification()`, `ns.NP.ApplyHitbox()`, `ns.NP.SlotOf(element)` / `ns.NP.AssignSlot(kind, slot, element)` (eviction rule: previous occupant → `"none"`, name-family elements evict each other).

- [ ] Text frame at level 900 with four FontStrings; font from `ns.MediaFont` using the GlobalSettings nameplate font row; per-slot size/colour/offset/width %/wrap.
- [ ] Name, level (`??` when unreadable or < 0), combined forms through `SetFormattedText("%s | %s", …)`.
- [ ] Raid marker (`ns.Exists(idx)` → `SetRaidTargetIconTexture`), classification atlases, name-inline raid marker.
- [ ] Stacking bounds frame with an alpha-0 full-size texture → `nameplate:SetStackingBoundsFrame(frame)`; `nameplateStackingTypes` bitfield.
- [ ] Hitbox: `SetNamePlateSize` + enemy hit-test insets, out of combat, re-applied on display/scale change and after `NamePlateDriverFrame.UpdateNamePlateOptions`.
- [ ] Token-swap guard (`nameplate.namePlateUnitToken ~= self.unit`).
- [ ] check.js OK; client: names/levels right, markers show, plates stack in a pack, hitbox matches the bar. Commit.

### Task 4: Health — absorb, text, coalescer

**Files:** Create `Health.lua`; modify `Plate.lua`.

**Produces:** `ns.NP.Health.Build(plate)`, `.Update(plate)`, `.UpdateMax(plate)`, `.UpdateText(plate)`, `.MarkDirty(plate)`.

- [ ] Calculator path (`CreateUnitHealPredictionCalculator`, `WithAbsorbs`, clamp `MaximumHealth`); secret vs. readable absorb branch on `ns.IsSecret(absorb)`; mask against bleed; styles `blizzard` / `clean` / bar texture.
- [ ] Text elements per the probe result; dead → `0%`.
- [ ] Coalescer frame (OnUpdate only while the dirty set is non-empty); per-plate work through `xpcall`.
- [ ] check.js OK; client: fill tracks in combat, no errors with `/vfsecrets force`, absorb shows on a shielded mob. Commit.

### Task 5: Colours

**Files:** Create `Colors.lua`; modify `Plate.lua`, `Nameplates.lua`.

**Produces:** `ns.NP.Colors.RefreshContext()`, `.Bar(plate) -> r,g,b, isSecretPath`, `.Apply(plate)`, `.Name(plate)`.

- [ ] Context cache on `PLAYER_ENTERING_WORLD`, `GROUP_ROSTER_UPDATE`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_ROLES_ASSIGNED`.
- [ ] The priority chain from the spec, with the out-of-combat dim, the class-colour mirror from Blizzard's hidden bar, the off-tank fold; last-applied cache for plain colours only.
- [ ] Triggers: `UNIT_THREAT_LIST_UPDATE`, combat edges, target/focus change.
- [ ] check.js OK; client: neutral yellow, tapped grey, caster blue, threat colours in a group, dim out of combat. Commit.

### Task 6: Cast bar and kick

**Files:** Create `Kick.lua`, `CastBar.lua`; modify `Plate.lua`.

**Produces:** `ns.NP.Kick.Resolve()`, `.Spell() -> id|nil`, `.Duration() -> durationObject|nil`; `ns.NP.Cast.Build(plate)`, `.Start(plate, isChannel)`, `.Stop(plate, reason)`, `.RefreshInterruptible(plate)`, `.RefreshKick(plate)`, `.InstallDispatcher()`.

- [ ] Dispatcher with the eleven `UNIT_SPELLCAST_*` events, routed through `ns.NP.plates[unit]`; stop handlers never re-read cast info.
- [ ] Fill via `SetTimerDuration`; fallback copy from Blizzard's hidden cast bar; spark, icon placements, shield atlas, background, border, wrap border.
- [ ] Fold for uninterruptible colour and shield alpha; kick-ready fold; kick tick and ready-fill geometry (clip frame, positioner, marker; Reverse fill for channels; pixel snap off after every `SetFillStyle`).
- [ ] Important cast glow + optional colour; cast target text; combined mode; timer text ticker (per probe); interrupted flash with the interrupter's name; cast scale hook into Target's scale easing; focus cast height; hide name while casting.
- [ ] check.js OK; client: caster mob — bar fills, shield on an uninterruptible cast, colour flips with the kick on/off cooldown, tick lands where the kick comes ready, interrupt shows the flash. Commit.

### Task 7: Target, focus, hover

**Files:** Create `Target.lua`; modify `Plate.lua`, `Nameplates.lua`.

**Produces:** `ns.NP.Target.Build(plate)`, `.Apply(plate)`, `.SetHover(plate, on)`, `.SetScale(plate, targetFactor, castFactor)`, `.ApplyAlpha(plate)`.

- [ ] Glow from eight gradient textures (ADD), border colour/size, highlight wash, overlay texture split by clip frames, arrows, hash line, focus letter.
- [ ] Old/new plate caching on target and focus change; mouseover ticker (0.1 s, only while a mouseover unit exists).
- [ ] Shared easing OnUpdate for scale; non-target alpha with keep-focus.
- [ ] check.js OK; client: target glow and scale, focus colour, hover wash, arrows. Commit.

### Task 8: Options, locale, extras

**Files:** Create `Options.lua`; modify `Locales/deDE.lua`, `Nameplates.lua`.

- [ ] Read `UI/OptionsBuilder.lua` for the row types in use (`section`, `group`, `toggle`, `slider`, `dropdown`, `segmented`, `color`, inline cog/swatch rows) and how `Modules/UnitFrames/UnitFrames.lua` builds multi-page options; build the three pages from the spec's option list. Every setter ends in `ns.NP.Bump()` (or the narrower refresh).
- [ ] Slot dropdowns implement the eviction rule through `ns.NP.AssignSlot`.
- [ ] Extras rows: enemy pets CVar, line-of-sight opacity (only if the CVar exists), hide enemy plates out of combat (`nameplateShowEnemies` at the combat edges, read before write), hitbox eye overlay.
- [ ] deDE entries for every new key; check.js locale coverage OK. Commit.

### Task 9: Review and wrap-up

- [ ] Run the adversarial-review skill on `Modules/Nameplates/*` and the `Core/Secret.lua` changes; fix confirmed findings; check.js OK.
- [ ] Full client walk from the spec's Testing section (pack, caster, group, duel, reload in combat, module off/on).
- [ ] Update `docs/forever-client-research.md` (Nameplates moves out of "High, rewrite"; new confirmed facts) and the project memory note. Commit.
