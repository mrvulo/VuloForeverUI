# Unit Frames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Player and target unit frames for VuloForeverUI in three styles — Standard (Blizzard's frames plus extras), Classic (own frame with the original Classic art), Modern (own flat frame in the house style) — built on the secret-value rules of the Forever client.

**Architecture:** One engine creates a `SecureUnitButtonTemplate` frame per unit and paints it through secret-safe setters; two skin tables tell the engine where every child goes; the Standard style creates no frame and instead hooks Blizzard's PlayerFrame/TargetFrame cosmetically. Blizzard's frames are silenced (events unregistered, content hidden or reparented) only while an own skin is active.

**Tech Stack:** WoW Forever 1.60.1 (`## Interface: 16001`, Mainline family), retail API only (`C_Spell`, `C_Item`, `C_Secrets`, `C_CurveUtil`, `AbbreviateNumbers`, `UnitHealthPercent`), the VuloForeverUI framework (`ns:RegisterModule`, `ns:CreateMover`, `ns.UI:StyleBackdrop`, `ns.UI:CreateShadow`, `ns.UI.Font`, `ns.MediaStatusbar`, `Core/Secret.lua`), `tools/check.js` as the static test.

## Global Constraints

Copied from `CLAUDE.md` and the spec (`docs/superpowers/specs/2026-09-18-unitframes-design.md`); every task's requirements include these.

- Retail API only. `GetSpellInfo`, `UnitAura`, `GetItemInfo`, `EasyMenu`, `IsAddOnLoaded` do not exist. No compat shims.
- **Display a secret, never decide on one.** No arithmetic, comparison, concatenation or table-keying on anything from `UnitHealth`, `UnitHealthPercent`, `UnitPower`, an aura API or a cooldown API. Such values go straight into a widget setter. Every decision on a unit value that *can* be secret goes through `ns.CanRead(v)` / `ns.Num(v, fallback)` and has a "cannot read" branch.
- `C_UnitAuras.*` **throws** for us in combat (confirmed 2026-09-18). No aura call anywhere in this feature.
- No combat log. Nothing here reads `COMBAT_LOG_EVENT_UNFILTERED`.
- Everything lives on `ns`. No bare globals except the addon table. The checker enforces this; frame *names* passed to `CreateFrame` are fine.
- Never name another addon in code, comments, strings, docs or commit messages. Say "the reference".
- Locale keys are English text; never evaluate `L[...]` at file scope. Use `ns.OnLocaleReady(fn)` for file-scope blocks (StaticPopup registration).
- Before assuming an API exists, check Forever's source: Gethe/wow-ui-source branch `forever`. The facts below were checked there on 2026-09-18.
- `cd tools && node check.js` must print `RESULT: OK` before every commit. The checker verifies the TOC list matches disk, so a new file and its TOC line land in the same task.
- Commit messages in German, no third-party addon names, end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Files in this repo use CRLF; the Write/Edit tools and git's autocrlf handle it. Shell `sed`/`python` edits must preserve CRLF (`newline=''` in Python).

## Client facts used by the tasks (checked 2026-09-18)

| Fact | Where it was verified |
|---|---|
| `UnitHealth`, `UnitHealthPercent`, `UnitPower` of the player are secret always, even out of combat; `UnitHealthMax`, `UnitPowerMax`, `UnitThreatSituation("player","target")` readable in combat | `/vfsecrets` in the beta client |
| `UnitLevel`, `UnitClassification`, `UnitPowerType` carry no secret flag; `UnitClass` is secret when unit identity is restricted; `UnitName` may be secret | `Blizzard_APIDocumentationGenerated/UnitDocumentation.lua` (forever) |
| `AbbreviateNumbers(number, options)` has `SecretArguments = "AllowedWhenTainted"` — a secret goes in, a (secret) string comes out | `LocalizationDocumentation.lua` (forever) |
| `UnitHealthPercent(unit, usePredicted, curve)` — `SecretReturns = true`, accepts a `LuaCurveObjectBase` | `UnitDocumentation.lua` line ~1508 |
| `C_CurveUtil.CreateCurve()` / `CreateColorCurve()`; curve objects have `AddPoint(x, y)`, `SetType(Enum.LuaCurveType.Linear)`; `CurveConstants.ScaleTo100` exists | `CurveUtilDocumentation.lua`, `LuaColorCurveObjectAPIDocumentation.lua`, `Blizzard_SharedXMLBase/CurveConstants.lua` |
| Blizzard's own `UnitFrameHealthBar_Update(statusbar, unit)` passes `UnitHealth(unit)` straight into `statusbar:SetValue` and sets the bar colour with `SetStatusBarColor(0, 1, 0)` — global function, hookable | `Blizzard_UnitFrame/Mainline/UnitFrame.lua` lines 819–837 |
| Forever PlayerFrame health bar: `PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar`; mana bar: `…PlayerFrameContentMain.ManaBarArea.ManaBar`; portrait: `PlayerFrame.PlayerFrameContainer.PlayerPortrait`; level circle `…PlayerFrameContentMain.LevelBackgroundCircle` | `Mainline/PlayerFrame.xml` + `.lua` (forever) |
| Forever TargetFrame: `TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar`, `…TargetFrameContentMain.ManaBar`, `…TargetFrameContentMain.Name`, `…LevelText`, portrait `TargetFrame.TargetFrameContainer.Portrait`; children `TargetFrame.spellbar`, `TargetFrame.totFrame` | `Mainline/TargetFrame.xml` + `.lua` (forever) |
| `PetFrame` has `parent="PlayerFrame"` and inherits `PlayerBottomManagedFrameTemplate` — reparenting PlayerFrame would hide the pet frame, so PlayerFrame is silenced by hiding its two content containers, not by reparenting | `Mainline/PetFrame.xml` (forever) |
| Classic art present: `Interface\TargetingFrame\UI-TargetingFrame`, `-Elite`, `-Rare`, `-Rare-Elite` (`SetTexture` returns true) | `/run` probe in the beta client |
| Classic PlayerFrame layout (root 232×100): portrait 64×64 `TOPLEFT 24,-16`; background 119×41 `TOPLEFT 89.5,-26`; name 100×12 `CENTER 34,15`; level `CENTER` of `BOTTOMLEFT 35.25,30`; health 119×12 `TOPLEFT 90,-45`; mana 119×12 `TOPLEFT 90,-56`. TargetFrame mirrored: portrait `TOPRIGHT -24,-16`, background `TOPRIGHT -89.5,-26`, name `CENTER -34,15`, health `TOPRIGHT -90,-45`, mana `TOPRIGHT -90,-56` | `Blizzard_UnitFrame/Classic/PlayerFrame.xml`, `TargetFrame.xml` (classic_era branch) |
| Frame art texcoords: target `(1.0, 0.09375, 0, 0.78125)` at 232×100 `TOPLEFT 0,0`; player is the mirror `(0.09375, 1.0, 0, 0.78125)` | the previous product's `STYLES` table (`l = 256/256, r = 24/256, b = 101/128`) and the classic XML |

## Framework contracts used by the tasks

- `ns:RegisterModule(key, def)` → module table `M` with `M.db` (per-profile, defaults merged), `M:RegisterEvent(event, handler)` (registry-owned, unregistered on disable), `M.OnEnable/OnDisable/GetOptions`.
- `ns:RegisterEventOnce(event, handler)` — one-shot registry event, taken out before the call.
- `ns:InCombat()` — true in combat lockdown.
- `ns:CreateMover(target, { key, label, db, width, height, scalable = true })` → mover; `ns:ApplyMover(mover)` positions the target at `CENTER UIParent CENTER db.x, db.y` and applies `db.scale` when `scalable`. The mover writes `db.x`, `db.y`, `db.scale`.
- `ns.UI:StyleBackdrop(frame, { bg = {r,g,b,a}, border = {r,g,b,a} })`, `ns.UI:CreateShadow(frame)`, `ns.UI.Font(fontString, size, flags)`, `ns.UI.FONT_PATH`.
- `ns.MediaStatusbar(name, fallback)` → texture path; `ns.db.global.statusbar` holds the profile's chosen LibSharedMedia name in `GlobalSettings` (read it as `ns.db and ns.db.global and ns.db.global.statusbar`).
- `ns.COLORS.accent = { r, g, b }`, `ns.COLORS.bg`, `ns.COLORS.border`; `ns.C.accent` is the `|cff…` string.
- `Core/Secret.lua`: `ns.IsSecret(v)`, `ns.CanRead(v)`, `ns.Num(v, fallback)`, `ns:SetHealthFill(bar, unit)`, `ns:SetPowerFill(bar, unit, powerType)`.
- Options items: `{ type = "dropdown", label, values = { { value, text } }, get, set, width }`, `{ type = "toggle", label, tooltip, get, set }`, `{ type = "header", text }`, `{ type = "desc", text }`, `{ type = "spacer", height }`, `{ type = "slider", label, min, max, step, get, set }`, `{ type = "button", label, onClick, primary }`.
- Reload popup pattern (from `Modules/Profiles.lua`): `StaticPopupDialogs["VFUI_…"] = { text, button1, button2, OnAccept = ReloadUI, timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3 }` inside `ns.OnLocaleReady`.

## File structure

```
Modules/UnitFrames.lua          module registration, db defaults, options page,
                                style switch + reload popup, enable/disable wiring
Modules/UnitFramesSkins.lua     ns.UF.Skins.classic / .modern (data) + ns.UF.ApplySkin
Modules/UnitFramesEngine.lua    ns.UF.CreateUnitFrame, painters, per-unit event frame,
                                Blizzard silencing, combat deferral
Modules/UnitFramesExtras.lua    ns.UF.Extras.Enable / Disable — Standard-style hooks
```

Load order in `VuloForeverUI.toc`, after `Modules\Minimap.lua`:
`UnitFramesSkins.lua`, `UnitFramesEngine.lua`, `UnitFramesExtras.lua`, `UnitFrames.lua` — the module file last, because it calls into the other three at `OnEnable` and its `GetOptions` reads `ns.UF.Skins`.

Shared table: `ns.UF = ns.UF or {}` at the top of every file (the first file loaded creates it).

DB layout (`mod.db`):

```lua
{
    enabled     = true,
    style       = "standard",      -- "standard" | "classic" | "modern"
    classColor  = true,            -- Standard extras
    threat      = true,
    classIcon   = true,
    playerElite = true,            -- Classic only
    portrait    = true,            -- Modern only
    player      = { x = -260, y = -180, scale = 1 },   -- mover db
    target      = { x =  260, y = -180, scale = 1 },
}
```

## Testing in this repo

There is no Lua unit-test runner. The test cycle of every task is:

1. `cd tools && node check.js` → must end with `RESULT: OK`. This is the syntax, locals-cap, house-rules, locale and TOC test.
2. An in-game probe, spelled out per task as `/run` lines or a click sequence, with the expected chat output. The client is `_classic_beta_\WowB.exe`; `/reload` after every file change; `/console scriptErrors 1` once so Lua errors show.

A task is done when both pass.

---

### Task 1: Skins — the two layout tables

**Files:**
- Create: `Modules/UnitFramesSkins.lua`
- Modify: `VuloForeverUI.toc` (add `Modules\UnitFramesSkins.lua` after `Modules\Minimap.lua`)

**Interfaces:**
- Consumes: `ns.MediaStatusbar(name, fallback)`, `ns.COLORS`, `ns.UI.FONT_PATH`.
- Produces:
  - `ns.UF.Skins.classic`, `ns.UF.Skins.modern` — skin tables, shape below.
  - `ns.UF.ApplySkin(frame, skin, opts)` — `frame` is an engine frame (Task 2) with the children `frame.Health`, `frame.Power`, `frame.Name`, `frame.Level`, `frame.HealthText`, `frame.HealthPct`, `frame.PowerText`, `frame.Portrait`, `frame.PortraitBG`, `frame.Art`, `frame.Background`, `frame.ThreatText`, `frame.ThreatGlow`, `frame.ClassIcon`, `frame.Tag`; `opts = { unit = "player"|"target", playerElite = bool, portrait = bool }`. Returns nothing; sizes and anchors every child, shows or hides the ones the skin does not use.
  - `ns.UF.ClassificationArt(skin, classification, opts)` → texture path or nil (Classic only; nil for Modern).

Skin table shape (both skins fill every key; `nil` anchors mean "hidden"):

```lua
{
    width = 232, height = 100,
    art = { file = "…", coords = { l, r, t, b } } or nil,   -- Classic frame art
    flat = false,                                           -- Modern: backdrop + shadow instead of art
    barTexture = function() return path end,
    font = { path, size, flags },
    -- every child: { point, relPoint, x, y, w, h } relative to the frame, or nil
    portrait = {...}, background = {...}, health = {...}, power = {...},
    name = {...}, level = {...}, healthText = {...}, healthPct = {...}, powerText = {...},
    threatText = {...}, classIcon = {...}, tag = {...},
    mirror = function(entry, unit) … end,   -- Classic: flips TOPLEFT/TOPRIGHT for the target
}
```

- [ ] **Step 1: Write the file**

```lua
-- VuloForeverUI / Modules / UnitFramesSkins
--
-- The two looks an own unit frame can wear, as DATA. The engine creates every
-- child once; a skin only says where each one sits, how big it is and which
-- texture it shows. Anything with an `if` on a unit value does not belong here.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Skins = {}

local CLASSIC_ART = "Interface\\TargetingFrame\\UI-TargetingFrame"
-- Player art reads the sheet left-to-right; the target frame is the mirror.
local COORDS_PLAYER = { 0.09375, 1.0, 0, 0.78125 }
local COORDS_TARGET = { 1.0, 0.09375, 0, 0.78125 }

-- Flip a TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT entry to the other side and
-- negate x, so one table describes both the player and the target frame.
local MIRROR = {
    TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
    BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
    LEFT = "RIGHT", RIGHT = "LEFT",
}
local function mirrorEntry(e)
    if not e then return nil end
    return {
        MIRROR[e[1]] or e[1], MIRROR[e[2]] or e[2], -(e[3] or 0), e[4] or 0, e[5], e[6],
        justify = (e.justify == "LEFT" and "RIGHT") or (e.justify == "RIGHT" and "LEFT") or e.justify,
    }
end

local function profileBarTexture()
    local name = ns.db and ns.db.global and ns.db.global.statusbar
    return ns.MediaStatusbar(name, "Interface\\TargetingFrame\\UI-StatusBar")
end

-- Layout numbers are Blizzard's Classic PlayerFrame (root 232x100); the target
-- frame is the same table mirrored. Entries: point, relPoint, x, y, w, h.
UF.Skins.classic = {
    width = 232, height = 100,
    art = { file = CLASSIC_ART, coords = COORDS_PLAYER, coordsTarget = COORDS_TARGET },
    flat = false,
    barTexture = function() return "Interface\\TargetingFrame\\UI-StatusBar" end,
    font = { "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" },
    fontNumbers = { "Fonts\\ARIALN.TTF", 12, "OUTLINE" },

    portrait   = { "TOPLEFT", "TOPLEFT", 24, -16, 64, 64 },
    background = { "TOPLEFT", "TOPLEFT", 89.5, -26, 119, 41 },
    health     = { "TOPLEFT", "TOPLEFT", 90, -45, 119, 12 },
    power      = { "TOPLEFT", "TOPLEFT", 90, -56, 119, 12 },
    name       = { "CENTER", "CENTER", 34, 15, 100, 12 },
    level      = { "CENTER", "BOTTOMLEFT", 35.25, 30, 30, 12 },
    healthText = { "LEFT",  "LEFT",  2, 0, 60, 12, justify = "LEFT",  onBar = "health" },
    healthPct  = { "RIGHT", "RIGHT", -2, 0, 40, 12, justify = "RIGHT", onBar = "health" },
    powerText  = { "RIGHT", "RIGHT", -2, 0, 60, 12, justify = "RIGHT", onBar = "power" },
    threatText = { "TOP", "TOP", 34, 2, 100, 12 },
    classIcon  = { "BOTTOMLEFT", "BOTTOMLEFT", 26, 22, 18, 18 },
    tag        = nil,
    mirror = mirrorEntry,
}

UF.Skins.modern = {
    width = 220, height = 46,
    art = nil,
    flat = true,
    barTexture = profileBarTexture,
    font = { nil, 12, "OUTLINE" },          -- nil path = ns.UI.FONT_PATH
    fontNumbers = { nil, 11, "OUTLINE" },

    portrait   = { "RIGHT", "LEFT", -4, 0, 46, 46 },     -- outside, left of the panel
    background = nil,
    health     = { "TOPLEFT", "TOPLEFT", 1, -1, 218, 30 },
    power      = { "BOTTOMLEFT", "BOTTOMLEFT", 1, 1, 218, 12 },
    name       = { "LEFT", "LEFT", 6, 0, 120, 12, justify = "LEFT", onBar = "health" },
    level      = { "LEFT", "RIGHT", 4, 0, 24, 12, justify = "LEFT", after = "name" },
    healthText = nil,
    healthPct  = { "RIGHT", "RIGHT", -6, 0, 50, 12, justify = "RIGHT", onBar = "health" },
    powerText  = { "RIGHT", "RIGHT", -6, 0, 60, 10, justify = "RIGHT", onBar = "power" },
    threatText = { "BOTTOM", "TOP", 0, 3, 120, 12 },
    classIcon  = { "TOPRIGHT", "TOPLEFT", -3, 0, 14, 14 },   -- outside, top-left corner
    tag        = { "LEFT", "RIGHT", 4, 0, 40, 12, justify = "LEFT", after = "level" },
    mirror = function(e) return e end,   -- Modern is symmetric
}

-- Classic frame art by classification; Modern has no art and answers nil.
local CLASSIC_BY_CLASSIFICATION = {
    elite     = CLASSIC_ART .. "-Elite",
    rareelite = CLASSIC_ART .. "-Rare-Elite",
    rare      = CLASSIC_ART .. "-Rare",
    worldboss = CLASSIC_ART .. "-Elite",
}
function UF.ClassificationArt(skin, classification, opts)
    if not skin.art then return nil end
    if opts and opts.unit == "player" then
        return opts.playerElite and CLASSIC_BY_CLASSIFICATION.elite or skin.art.file
    end
    return CLASSIC_BY_CLASSIFICATION[classification or ""] or skin.art.file
end

local function place(region, e, frame, bars)
    if not e then
        region:Hide()
        return
    end
    region:ClearAllPoints()
    local rel = frame
    if e.onBar then rel = bars[e.onBar] end
    if e.after then rel = frame[e.after] end
    region:SetPoint(e[1], rel, e[2], e[3], e[4])
    if e[5] and e[6] then region:SetSize(e[5], e[6]) end
    if region.SetJustifyH and e.justify then region:SetJustifyH(e.justify) end
    region:Show()
end

local function applyFont(fs, spec)
    local path = spec[1] or ns.UI.FONT_PATH
    fs:SetFont(path, spec[2], spec[3] or "")
end

-- opts: { unit = "player"|"target", playerElite = bool, portrait = bool }
function UF.ApplySkin(frame, skin, opts)
    opts = opts or {}
    local isTarget = opts.unit == "target"
    local function E(key)
        local e = skin[key]
        if isTarget then e = skin.mirror(e, opts.unit) end
        return e
    end

    frame:SetSize(skin.width, skin.height)

    -- frame art vs flat panel
    if skin.art then
        frame.Art:SetTexture(UF.ClassificationArt(skin, frame.classification, opts))
        local c = isTarget and skin.art.coordsTarget or skin.art.coords
        frame.Art:SetTexCoord(c[1], c[2], c[3], c[4])
        frame.Art:ClearAllPoints()
        frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.Art:SetSize(skin.width, skin.height)
        frame.Art:Show()
        if frame._vcBG then frame._vcBG:Hide() end
        if frame._vcBorders then for _, b in ipairs(frame._vcBorders) do b:Hide() end end
        if frame._vcShadow then for _, t in ipairs(frame._vcShadow) do t:Hide() end end
        frame.AccentLine:Hide()
    else
        frame.Art:Hide()
        ns.UI:StyleBackdrop(frame)
        ns.UI:CreateShadow(frame)
        if frame._vcBG then frame._vcBG:Show() end
        if frame._vcBorders then for _, b in ipairs(frame._vcBorders) do b:Show() end end
        if frame._vcShadow then for _, t in ipairs(frame._vcShadow) do t:Show() end end
        frame.AccentLine:ClearAllPoints()
        frame.AccentLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.AccentLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.AccentLine:SetHeight(1)
        frame.AccentLine:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        frame.AccentLine:Show()
    end

    local bars = { health = frame.Health, power = frame.Power }
    place(frame.Background, E("background"), frame, bars)
    place(frame.Health,     E("health"),     frame, bars)
    place(frame.Power,      E("power"),      frame, bars)
    local tex = skin.barTexture()
    frame.Health:SetStatusBarTexture(tex)
    frame.Power:SetStatusBarTexture(tex)

    -- portrait: Classic always, Modern by option
    local wantPortrait = skin.art ~= nil or opts.portrait ~= false
    place(frame.Portrait, wantPortrait and E("portrait") or nil, frame, bars)
    if skin.flat and wantPortrait then
        frame.PortraitBG:ClearAllPoints()
        frame.PortraitBG:SetPoint("TOPLEFT", frame.Portrait, "TOPLEFT", -1, 1)
        frame.PortraitBG:SetPoint("BOTTOMRIGHT", frame.Portrait, "BOTTOMRIGHT", 1, -1)
        frame.PortraitBG:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        frame.PortraitBG:Show()
    else
        frame.PortraitBG:Hide()
    end

    place(frame.Name,       E("name"),       frame, bars)
    place(frame.Level,      E("level"),      frame, bars)
    place(frame.HealthText, E("healthText"), frame, bars)
    place(frame.HealthPct,  E("healthPct"),  frame, bars)
    place(frame.PowerText,  E("powerText"),  frame, bars)
    place(frame.ThreatText, E("threatText"), frame, bars)
    place(frame.ClassIcon,  E("classIcon"),  frame, bars)
    place(frame.Tag,        E("tag"),        frame, bars)

    applyFont(frame.Name, skin.font)
    applyFont(frame.Level, skin.fontNumbers)
    applyFont(frame.HealthText, skin.fontNumbers)
    applyFont(frame.HealthPct, skin.fontNumbers)
    applyFont(frame.PowerText, skin.fontNumbers)
    applyFont(frame.ThreatText, skin.fontNumbers)
    applyFont(frame.Tag, skin.fontNumbers)

    -- the glow is the bars' outline, whatever the skin
    frame.ThreatGlow:ClearAllPoints()
    frame.ThreatGlow:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", -2, 2)
    frame.ThreatGlow:SetPoint("BOTTOMRIGHT", frame.Power, "BOTTOMRIGHT", 2, -2)
end
```

- [ ] **Step 2: Add the TOC line**

In `VuloForeverUI.toc`, after the line `Modules\Minimap.lua`, add:

```
Modules\UnitFramesSkins.lua
```

- [ ] **Step 3: Run the checker**

Run: `cd tools && node check.js`
Expected: last line `RESULT: OK (warnings above, if any)`. If it reports a bare global, the name is one of the `frame.*` children — they are table fields, not globals; re-read the offending line.

- [ ] **Step 4: In-game smoke probe**

The skin file is pure data plus one function nobody calls yet, so the probe is load-time only: `/reload` with `/console scriptErrors 1` on. Expected: no red error at login, chat shows the normal `VuloForeverUI: v0.1.0 loaded.` line. The first real use of `ApplySkin` is Task 2's probe.

- [ ] **Step 5: Commit**

```bash
git add Modules/UnitFramesSkins.lua VuloForeverUI.toc
git commit -F - <<'EOF'
Unit Frames: die zwei Skin-Tabellen

Classic (Original-Rahmenkunst, Masse des klassischen Spielerrahmens,
Zielrahmen gespiegelt) und Modern (flaches Panel im Hausstil) als reine
Daten plus ApplySkin, das jedes Kind eines Engine-Frames setzt.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 2: Engine part 1 — frame creation, secure attributes, mover

**Files:**
- Create: `Modules/UnitFramesEngine.lua`
- Modify: `VuloForeverUI.toc` (add `Modules\UnitFramesEngine.lua` after `Modules\UnitFramesSkins.lua`)

**Interfaces:**
- Consumes: `ns.UF.ApplySkin(frame, skin, opts)` (Task 1), `ns:CreateMover`, `ns:ApplyMover`, `ns.UI.Font`.
- Produces:
  - `ns.UF.CreateUnitFrame(unit, db, label)` → frame. `unit` is `"player"` or `"target"`; `db` is the mover db table (`mod.db.player` / `mod.db.target`); `label` is the mover label. Must be called out of combat. Returns the existing frame on a second call.
  - Frame fields (all created here, positioned by Task 1): `frame.unit`, `frame.Health`, `frame.Power` (StatusBars), `frame.Name`, `frame.Level`, `frame.HealthText`, `frame.HealthPct`, `frame.PowerText`, `frame.ThreatText`, `frame.Tag` (FontStrings), `frame.Portrait`, `frame.PortraitBG`, `frame.Art`, `frame.Background`, `frame.ThreatGlow`, `frame.ClassIcon`, `frame.AccentLine` (Textures), `frame.mover`, `frame.classification` (string, last known), `frame.events` (Frame, wired in Task 3).
  - `ns.UF.Frames` — `{ player = frame, target = frame }` once created.
  - `ns.UF.SetSkin(frame, skinName, opts)` — applies `ns.UF.Skins[skinName]` and remembers `frame.skin`, `frame.skinOpts`; re-applies the mover so the size change lands.

- [ ] **Step 1: Write the file (creation only; painters and events come in Task 3)**

```lua
-- VuloForeverUI / Modules / UnitFramesEngine
--
-- One engine for both own skins. It creates a secure unit button per unit,
-- paints it through setters that accept secret values, and silences
-- Blizzard's frame while an own skin is active. The skins (UnitFramesSkins)
-- own the layout; the module (UnitFrames) owns the options and the switch.
--
-- The rule every painter here follows: DISPLAY a secret, never DECIDE on
-- one. Health, power and the percent go straight into SetValue /
-- SetFormattedText. Where a decision is unavoidable (level colour, frame art
-- by classification, class colour) the value is checked with ns.CanRead and
-- the last known state stays when the answer is no.
local _, ns = ...
local L = ns.L
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Frames = UF.Frames or {}

local FRAME_NAMES = {
    player = "VuloForeverUI_PlayerFrame",
    target = "VuloForeverUI_TargetFrame",
}

local function newBar(parent, level)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetFrameLevel(parent:GetFrameLevel() + level)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    -- the dark ground behind a bar; the bar's own texture draws over it
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

local function newText(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    ns.UI.Font(fs, 11, "OUTLINE")
    fs:SetText("")
    return fs
end

function UF.CreateUnitFrame(unit, db, label)
    if UF.Frames[unit] then return UF.Frames[unit] end
    assert(not ns:InCombat(), "unit frames are created out of combat")

    local f = CreateFrame("Button", FRAME_NAMES[unit], UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
    f:SetSize(232, 100)                       -- placeholder; the skin sets the real size
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(5)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:SetAttribute("toggleForVehicle", true)
    RegisterUnitWatch(f)

    -- art + flat panel pieces (one of the two sets is shown per skin)
    f.Art        = f:CreateTexture(nil, "BORDER")
    f.Background = f:CreateTexture(nil, "BACKGROUND")
    f.Background:SetColorTexture(0, 0, 0, 0.5)
    f.AccentLine = f:CreateTexture(nil, "OVERLAY")

    f.PortraitBG = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    f.Portrait   = f:CreateTexture(nil, "ARTWORK")

    f.Health = newBar(f, 1)
    f.Power  = newBar(f, 1)

    f.Name       = newText(f.Health)
    f.Level      = newText(f)
    f.HealthText = newText(f.Health)
    f.HealthPct  = newText(f.Health)
    f.PowerText  = newText(f.Power)
    f.ThreatText = newText(f)
    f.Tag        = newText(f)

    f.ThreatGlow = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    f.ThreatGlow:SetColorTexture(1, 0, 0, 0.35)
    f.ThreatGlow:Hide()

    f.ClassIcon = f:CreateTexture(nil, "OVERLAY")
    f.ClassIcon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    f.ClassIcon:Hide()

    f.classification = "normal"

    -- Position and scale through the mover: /vedit moves it, db.x/y/scale
    -- persist per profile, ApplyMover puts it back at load.
    f.mover = ns:CreateMover(f, {
        key      = "unitframe_" .. unit,
        label    = label,
        db       = db,
        width    = 232,
        height   = 100,
        scalable = true,
    })
    ns:ApplyMover(f.mover)

    UF.Frames[unit] = f
    return f
end

function UF.SetSkin(frame, skinName, opts)
    local skin = UF.Skins[skinName]
    if not skin then return end
    frame.skin, frame.skinOpts = skin, opts
    UF.ApplySkin(frame, skin, opts)
    -- the mover box should match the new size; ApplyMover re-reads it
    frame.mover.opts.width, frame.mover.opts.height = skin.width, skin.height
    ns:RefreshMoverGeometry(frame.mover)
    ns:ApplyMover(frame.mover)
end
```

- [ ] **Step 2: Add the TOC line**

In `VuloForeverUI.toc`, after `Modules\UnitFramesSkins.lua`, add `Modules\UnitFramesEngine.lua`.

- [ ] **Step 3: Run the checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`. `RegisterUnitWatch`, `CreateFrame`, `UIParent` are Blizzard globals the checker knows; `assert` is Lua.

- [ ] **Step 4: In-game probe — create a frame by hand and click it**

This task has no module yet, so drive the engine from chat once (out of combat):

```
/run local ns=select(2,...) -- (not reachable) 
```

Chat cannot see `ns`; instead add a **temporary** slash in the same file, removed in Task 4:

```lua
-- TEMP (removed in Task 4): create the frames from chat for the engine probe
ns:RegisterSlash({ key = "UFPROBE", commands = { "/vfufprobe" },
    desc = "Temporary: create raw unit frames for the engine probe." })
ns.Slash.UFPROBE = function()
    local db = ns.db.profile.modules.unitframes or {}
    db.player = db.player or { x = -260, y = -180, scale = 1 }
    db.target = db.target or { x =  260, y = -180, scale = 1 }
    local p = UF.CreateUnitFrame("player", db.player, "PLAYER")
    local t = UF.CreateUnitFrame("target", db.target, "TARGET")
    UF.SetSkin(p, "classic", { unit = "player", playerElite = true })
    UF.SetSkin(t, "classic", { unit = "target" })
    ns:Print("probe frames up: %s %s", p:GetName(), t:GetName())
end
```

`/reload`, then `/vfufprobe`. Expected: two 232×100 frames with the Classic dragon art, empty bars; the player one always visible, the target one appearing when you target something and vanishing when you clear the target (that is `RegisterUnitWatch` working). Left-click on the target frame keeps the target; right-click on the player frame opens the unit menu; `/vedit` shows two movers labelled PLAYER / TARGET that drag and survive `/reload`.
If a frame does not appear: `/fstack` over the spot — the frame name must be `VuloForeverUI_PlayerFrame`.

- [ ] **Step 5: Commit**

```bash
git add Modules/UnitFramesEngine.lua VuloForeverUI.toc
git commit -F - <<'EOF'
Unit Frames: Engine, Teil 1 -- Frames, Secure-Attribute, Mover

Ein SecureUnitButton pro Einheit mit RegisterUnitWatch, Klick auf Ziel und
Menue, alle Kinder einmal erzeugt; Position und Skalierung ueber den Mover.
Ein temporaerer Probe-Befehl bleibt bis zum Modul-Anschluss.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 3: Engine part 2 — painters and per-unit events

**Files:**
- Modify: `Modules/UnitFramesEngine.lua` (append below `UF.SetSkin`; change `UF.CreateUnitFrame` to call `wireEvents(f)` before `UF.Frames[unit] = f`)

**Interfaces:**
- Consumes: `ns:SetHealthFill`, `ns:SetPowerFill`, `ns.CanRead`, `ns.Num`, `ns.Prof.Begin/End`, `UF.ClassificationArt`, frame fields from Task 2.
- Produces:
  - `ns.UF.Paint(frame)` — full repaint (every channel).
  - `ns.UF.PaintThreat(fs, glow, unit, mobUnit)` — shared with Task 5 (Extras). `fs` FontString, `glow` Texture or nil, `mobUnit` `"target"` or nil.
  - `ns.UF.ClassColor(unit)` → `r, g, b` or nil when the class token is unreadable.
  - `frame.events` — the per-unit event frame; `frame:SetShown` is owned by `RegisterUnitWatch`, never by us.

- [ ] **Step 1: Append the painters**

```lua
-- ---------------------------------------------------------------- painters --

-- Health colour when the class is not readable: a colour curve the ENGINE
-- evaluates for us. The percent never reaches Lua -- the returned colour may
-- itself be secret and goes into SetStatusBarColor uninspected.
local healthCurve
local function getHealthCurve()
    if healthCurve then return healthCurve end
    healthCurve = C_CurveUtil.CreateColorCurve()
    healthCurve:AddPoint(0.0, CreateColor(0.89, 0.19, 0.19, 1))
    healthCurve:AddPoint(0.5, CreateColor(0.93, 0.93, 0.20, 1))
    healthCurve:AddPoint(1.0, CreateColor(0.00, 0.80, 0.00, 1))
    return healthCurve
end

function UF.ClassColor(unit)
    local _, token = UnitClass(unit)
    if not token or not ns.CanRead(token) then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not c then return nil end
    return c.r, c.g, c.b
end

local function paintHealth(f)
    local unit = f.unit
    ns:SetHealthFill(f.Health, unit)
    if not UnitIsConnected(unit) then
        f.HealthText:SetText(L["Offline"])
        f.HealthPct:SetText("")
        f.Health:SetStatusBarColor(0.5, 0.5, 0.5)
        return
    end
    if UnitIsDeadOrGhost(unit) then
        f.HealthText:SetText(UnitIsGhost(unit) and L["Ghost"] or L["Dead"])
        f.HealthPct:SetText("")
        f.Health:SetStatusBarColor(0.5, 0.5, 0.5)
        return
    end
    -- both arguments may be secret; the widget takes them as they are
    f.HealthText:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(unit)))
    f.HealthPct:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))

    local r, g, b = UF.ClassColor(unit)
    if r and f.skin and f.skin.flat then
        f.Health:SetStatusBarColor(r, g, b)
    elseif f.skin and f.skin.flat then
        local color = UnitHealthPercent(unit, true, getHealthCurve())
        if color and color.GetRGB then
            f.Health:SetStatusBarColor(color:GetRGB())
        end
    else
        -- Classic: Blizzard's green, class colour is what the name carries
        f.Health:SetStatusBarColor(0, 1, 0)
    end
end

local POWER_FALLBACK = { r = 0, g = 0, b = 1 }   -- mana
local function paintPower(f)
    local unit = f.unit
    ns:SetPowerFill(f.Power, unit)
    local ptype, ptoken = UnitPowerType(unit)
    local info
    if ptoken and ns.CanRead(ptoken) then info = PowerBarColor[ptoken] end
    if not info and ptype and ns.CanRead(ptype) then info = PowerBarColor[ptype] end
    info = info or POWER_FALLBACK
    f.Power:SetStatusBarColor(info.r, info.g, info.b)
    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then
        f.PowerText:SetText("")
    else
        f.PowerText:SetFormattedText("%s", AbbreviateNumbers(UnitPower(unit)))
    end
end

local function paintName(f)
    local unit = f.unit
    f.Name:SetText(UnitName(unit))          -- may be secret; SetText accepts it
    local r, g, b = UF.ClassColor(unit)
    if r then
        f.Name:SetTextColor(r, g, b)
    elseif UnitIsPlayer(unit) then
        f.Name:SetTextColor(1, 1, 1)
    else
        local reaction = UnitReaction(unit, "player")
        local col = reaction and ns.CanRead(reaction) and FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if col then f.Name:SetTextColor(col.r, col.g, col.b) else f.Name:SetTextColor(1, 1, 1) end
    end
end

local function paintLevel(f)
    local unit = f.unit
    local level = ns.Num(UnitLevel(unit), nil)
    if level == nil then return end        -- unreadable: keep the last text
    if level < 0 then
        f.Level:SetText("??")
        f.Level:SetTextColor(1, 0, 0)
    else
        f.Level:SetFormattedText("%d", level)
        local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(level)
        if c then f.Level:SetTextColor(c.r, c.g, c.b) else f.Level:SetTextColor(1, 0.82, 0) end
    end
end

local function paintPortrait(f)
    if f.Portrait:IsShown() then
        SetPortraitTexture(f.Portrait, f.unit)
    end
end

local THREAT_COLOR = {
    [0] = { 0.69, 0.69, 0.69 },
    [1] = { 1.00, 1.00, 0.47 },
    [2] = { 1.00, 0.60, 0.00 },
    [3] = { 1.00, 0.00, 0.00 },
}
-- Shared with the Standard-style extras: one painter, two callers.
function UF.PaintThreat(fs, glow, unit, mobUnit)
    local status = mobUnit and UnitThreatSituation(unit, mobUnit) or UnitThreatSituation(unit)
    if status == nil or not ns.CanRead(status) then
        fs:SetText("")
        if glow then glow:Hide() end
        return
    end
    local c = THREAT_COLOR[status] or THREAT_COLOR[0]
    if status == 0 then
        fs:SetText("")
        if glow then glow:Hide() end
        return
    end
    if mobUnit then
        local _, _, pct = UnitDetailedThreatSituation(unit, mobUnit)
        if pct and ns.CanRead(pct) then
            fs:SetFormattedText("%d%%", pct)
        else
            fs:SetText(status >= 2 and L["Aggro"] or L["Threat"])
        end
    else
        fs:SetText(status >= 2 and L["Aggro"] or L["Threat"])
    end
    fs:SetTextColor(c[1], c[2], c[3])
    if glow then
        glow:SetColorTexture(c[1], c[2], c[3], 0.35)
        glow:SetShown(status >= 2)
    end
end

local function paintThreat(f)
    if f.unit == "target" then
        UF.PaintThreat(f.ThreatText, f.ThreatGlow, "player", "target")
    else
        UF.PaintThreat(f.ThreatText, f.ThreatGlow, "player", nil)
    end
end

local TAG_TEXT = { elite = "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = "Boss" }
local function paintClassification(f)
    local cls = UnitClassification(f.unit)
    if cls and ns.CanRead(cls) then f.classification = cls end   -- else keep last
    if f.skin and f.skin.art then
        f.Art:SetTexture(UF.ClassificationArt(f.skin, f.classification, f.skinOpts))
    end
    if f.Tag:IsShown() or (f.skin and f.skin.tag) then
        f.Tag:SetText(TAG_TEXT[f.classification] or "")
    end
end

local function paintClassIcon(f)
    local _, token = UnitClass(f.unit)
    local coords = token and ns.CanRead(token) and UnitIsPlayer(f.unit) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
    if coords and f.skin and f.skin.classIcon then
        f.ClassIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        f.ClassIcon:Show()
    else
        f.ClassIcon:Hide()
    end
end

function UF.Paint(f)
    if not f or not UnitExists(f.unit) then return end
    paintName(f)
    paintLevel(f)
    paintClassification(f)
    paintClassIcon(f)
    paintPortrait(f)
    paintHealth(f)
    paintPower(f)
    paintThreat(f)
end

-- ------------------------------------------------------------------ events --

-- Own event frame per unit frame with RegisterUnitEvent, so the client
-- filters delivery C-side and UNIT_HEALTH of thirty raid members never
-- reaches this handler. UNIT_HEALTH / UNIT_POWER_UPDATE are the hottest
-- events in the game; their painters touch nothing but setters.
local CHANNEL = {
    UNIT_HEALTH                  = paintHealth,
    UNIT_MAXHEALTH               = paintHealth,
    UNIT_POWER_UPDATE            = paintPower,
    UNIT_MAXPOWER                = paintPower,
    UNIT_DISPLAYPOWER            = paintPower,
    UNIT_NAME_UPDATE             = paintName,
    UNIT_LEVEL                   = paintLevel,
    UNIT_FACTION                 = paintName,
    UNIT_CLASSIFICATION_CHANGED  = paintClassification,
    UNIT_PORTRAIT_UPDATE         = paintPortrait,
    UNIT_THREAT_SITUATION_UPDATE = paintThreat,
    UNIT_THREAT_LIST_UPDATE      = paintThreat,
    UNIT_CONNECTION              = paintHealth,
}

local function onUnitEvent(ev, event, unit)
    local f = ev.frame
    local t0 = ns.Prof.Begin()
    local painter = CHANNEL[event]
    if painter then painter(f) end
    ns.Prof.End("unitframes", t0)
end

local function onGlobalEvent(ev, event)
    local f = ev.frame
    local t0 = ns.Prof.Begin()
    UF.Paint(f)
    ns.Prof.End("unitframes", t0)
end

local function wireEvents(f)
    local ev = CreateFrame("Frame")
    ev.frame = f
    f.events = ev
    local units = f.unit == "player" and { "player", "vehicle" } or { f.unit }
    for event in pairs(CHANNEL) do
        pcall(ev.RegisterUnitEvent, ev, event, units[1], units[2])
    end
    local glob = CreateFrame("Frame")
    glob.frame = f
    f.globalEvents = glob
    glob:RegisterEvent("PLAYER_ENTERING_WORLD")
    if f.unit == "target" then glob:RegisterEvent("PLAYER_TARGET_CHANGED") end
    glob:SetScript("OnEvent", onGlobalEvent)
    ev:SetScript("OnEvent", onUnitEvent)
end

function UF.SetEventsEnabled(f, on)
    if not f or not f.events then return end
    if on then
        f.events:SetScript("OnEvent", onUnitEvent)
        f.globalEvents:SetScript("OnEvent", onGlobalEvent)
        UF.Paint(f)
    else
        f.events:SetScript("OnEvent", nil)
        f.globalEvents:SetScript("OnEvent", nil)
    end
end
```

Then in `UF.CreateUnitFrame`, just before `UF.Frames[unit] = f`, add:

```lua
    wireEvents(f)
```

- [ ] **Step 2: Add the locale strings the painters use**

The checker's locale pass wants every `L["…"]` key present in the locale table. Open `Locales/` (or wherever `check.js` reports missing keys — run it first) and add: `"Offline"`, `"Ghost"`, `"Dead"`, `"Aggro"`, `"Threat"`. If the repo's locale scheme is "English key is the default value", only the German file needs entries: `Offline` → `Offline`, `Ghost` → `Geist`, `Dead` → `Tot`, `Aggro` → `Aggro`, `Threat` → `Bedrohung`. German values must not contain a raw ASCII `"`.

- [ ] **Step 3: Run the checker**

Run: `cd tools && node check.js`
Expected: `RESULT: OK`. If it flags `PowerBarColor`, `FACTION_BAR_COLORS`, `RAID_CLASS_COLORS`, `CLASS_ICON_TCOORDS`, `CurveConstants`, `CreateColor` as unknown globals, add them to the checker's known-Blizzard-globals list in `tools/check.js` — they are FrameXML tables present on Mainline (`Blizzard_SharedXML/ColorUtil.lua`, `PortraitFrame.lua`, `Blizzard_SharedXMLBase/CurveConstants.lua`).

- [ ] **Step 4: In-game probe — bars fill, texts show, nothing throws**

`/reload`, `/vfufprobe`, then target yourself (`/target player`) and a mob:

Expected out of combat:
- both bars filled to the right amount, health text like `1.2k` and percent `100%`, power text a number, name in class colour on the player frame, level in white/yellow.
- On a mob target: name in the reaction colour, level coloured by difficulty, classification art swaps to the elite dragon on an elite (`/target` an elite in Tirisfal is rare; the probe for this is `/run VuloForeverUI_TargetFrame.classification="elite" ` followed by `/run VuloForeverUI_TargetFrame.Art:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Elite")` — a manual swap, to see the art; the real event path is checked on the next elite you meet).

Expected in combat (hit a mob):
- health and power bars keep moving; texts keep updating; **no red error**. Threat text on the target frame shows a percent or "Aggro"; the glow appears when you have aggro.
- `/vfsecrets` while fighting must still print (that proves the painters did not taint anything they should not).

- [ ] **Step 5: Commit**

```bash
git add Modules/UnitFramesEngine.lua Locales tools/check.js
git commit -F - <<'EOF'
Unit Frames: Engine, Teil 2 -- Maler und Events pro Einheit

Health, Power und Prozent gehen ungesehen in SetValue und
SetFormattedText; die Balkenfarbe kommt aus der Klassenfarbe oder einer
Farbkurve, die der Client auswertet. Level, Klassifikation und Klasse
werden nur gelesen, wenn ns.CanRead ja sagt, sonst bleibt der letzte
Stand. Events per RegisterUnitEvent auf einem eigenen Frame je Einheit.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 4: Engine part 3 + module — silencing Blizzard, the style switch, options

**Files:**
- Modify: `Modules/UnitFramesEngine.lua` (append; remove the TEMP `/vfufprobe` slash)
- Create: `Modules/UnitFrames.lua`
- Modify: `VuloForeverUI.toc` (add `Modules\UnitFrames.lua` **last** of the four, i.e. after `Modules\UnitFramesExtras.lua` once Task 5 adds it; for now after `Modules\UnitFramesEngine.lua`)

**Interfaces:**
- Consumes: everything from Tasks 1–3; `ns:RegisterModule`, `ns:RegisterEventOnce`, `ns:InCombat`, `StaticPopup_Show`.
- Produces:
  - `ns.UF.SilenceBlizzard(unit)` / `ns.UF.SilenceBlizzardDeferred(unit)` — idempotent; in combat the deferred form queues for `PLAYER_REGEN_ENABLED`.
  - `ns.UF.ActivateOwnFrames(mod)` — creates (if needed) both frames, applies the skin named in `mod.db.style`, enables their events, silences Blizzard's frames. Out of combat only; callers gate.
  - `ns.UF.DeactivateOwnFrames()` — hides own frames (`UnregisterUnitWatch` + `Hide`), disables their events. Blizzard's frames stay silenced (that is why switching back asks for a reload).
  - Module `unitframes` with the db layout from the header.

- [ ] **Step 1: Append the silencing + activation code to the engine**

```lua
-- ------------------------------------------------ silencing Blizzard's --

-- Blizzard's frames are not hidden with Hide(): Edit Mode and their own
-- update paths would show them again. They are SILENCED -- events off -- and
-- their visible content parked. Two recipes, because the pet frame is a
-- child of PlayerFrame (Mainline/PetFrame.xml, parent="PlayerFrame") and we
-- do not own it: PlayerFrame keeps its parent and only its content
-- containers go, TargetFrame moves whole to a hidden parent (its children
-- -- spell bar, target-of-target -- are ours to lose in the first version).
local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

local silenced = {}
local pending  = {}

local function unregisterTree(frame, skip)
    if not frame or frame == skip then return end
    if frame.UnregisterAllEvents then frame:UnregisterAllEvents() end
    local kids = { frame:GetChildren() }
    for i = 1, #kids do unregisterTree(kids[i], skip) end
end

local function keepHidden(region)
    if region._vfuiKeepHidden then return end
    region._vfuiKeepHidden = true
    hooksecurefunc(region, "Show", function(self)
        if silenced[self] then C_Timer.After(0, function() self:Hide() end) end
    end)
end

local function silencePlayer()
    local pf = _G.PlayerFrame
    if not pf or silenced.player then return end
    unregisterTree(pf, _G.PetFrame)
    pf:EnableMouse(false)
    for _, key in ipairs({ "PlayerFrameContainer", "PlayerFrameContent" }) do
        local c = pf[key]
        if c then
            silenced[c] = true
            c:Hide()
            keepHidden(c)
        end
    end
    silenced.player = true
end

local function silenceTarget()
    local tf = _G.TargetFrame
    if not tf or silenced.target then return end
    unregisterTree(tf, nil)
    tf:Hide()
    tf:SetParent(hiddenParent)
    if not tf._vfuiParentHook then
        tf._vfuiParentHook = true
        hooksecurefunc(tf, "SetParent", function(self, parent)
            if parent ~= hiddenParent and silenced.target and not ns:InCombat() then
                C_Timer.After(0, function() self:SetParent(hiddenParent) end)
            end
        end)
    end
    silenced.target = true
end

local SILENCER = { player = silencePlayer, target = silenceTarget }

function UF.SilenceBlizzard(unit)
    local fn = SILENCER[unit]
    if fn then fn() end
end

local function flushPending()
    for unit in pairs(pending) do
        pending[unit] = nil
        UF.SilenceBlizzard(unit)
    end
end

function UF.SilenceBlizzardDeferred(unit)
    if ns:InCombat() then
        pending[unit] = true
        ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", flushPending)
    else
        UF.SilenceBlizzard(unit)
    end
end

function UF.IsBlizzardSilenced(unit)
    return silenced[unit] == true
end

-- -------------------------------------------------------- activation --

local LABELS = {
    player = "|cffffffffPLAYER FRAME|r",
    target = "|cffffffffTARGET FRAME|r",
}

function UF.ActivateOwnFrames(mod)
    local style = mod.db.style
    if style ~= "classic" and style ~= "modern" then return end
    for _, unit in ipairs({ "player", "target" }) do
        local db = mod.db[unit]
        local f = UF.CreateUnitFrame(unit, db, LABELS[unit])
        UF.SetSkin(f, style, {
            unit        = unit,
            playerElite = mod.db.playerElite,
            portrait    = mod.db.portrait,
        })
        RegisterUnitWatch(f)
        UF.SetEventsEnabled(f, true)
        UF.SilenceBlizzard(unit)
    end
end

function UF.DeactivateOwnFrames()
    for _, unit in ipairs({ "player", "target" }) do
        local f = UF.Frames[unit]
        if f then
            UF.SetEventsEnabled(f, false)
            UnregisterUnitWatch(f)
            f:Hide()
        end
    end
end
```

Delete the `-- TEMP (removed in Task 4)` block (`/vfufprobe`) from the engine.

- [ ] **Step 2: Write the module**

```lua
-- VuloForeverUI / Modules / UnitFrames
--
-- Player and target frames in three styles. Standard keeps Blizzard's frames
-- and lays extras on them (UnitFramesExtras); Classic and Modern are our own
-- frames (UnitFramesEngine + UnitFramesSkins) and silence Blizzard's.
local _, ns = ...
local L = ns.L
local UF = ns.UF

local mod = ns:RegisterModule("unitframes", {
    name        = "Unit Frames",
    group       = "Unit Frames",
    description = "Player and target frames: Blizzard's own with extras, the Classic look, or a flat Modern look.",
    defaults = {
        enabled     = true,
        style       = "standard",
        classColor  = true,
        threat      = true,
        classIcon   = true,
        playerElite = true,
        portrait    = true,
        player      = { x = -260, y = -180, scale = 1 },
        target      = { x =  260, y = -180, scale = 1 },
    },
})

local function isOwnStyle(style)
    return style == "classic" or style == "modern"
end

-- Going back to Standard needs a reload: Blizzard's frames were silenced and
-- their events cannot be re-registered from here. Said before the switch,
-- not after it.
ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_UNITFRAMES_RELOAD"] = {
        text = L["Blizzard's frames come back after a reload. Reload the UI now?"],
        button1 = L["Reload now"],
        button2 = L["Later"],
        OnAccept = function() ReloadUI() end,
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }
end)

local pendingApply = false

local function applyStyle()
    if ns:InCombat() then
        if not pendingApply then
            pendingApply = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                pendingApply = false
                applyStyle()
            end)
        end
        return
    end
    if isOwnStyle(mod.db.style) then
        if UF.Extras then UF.Extras.Disable() end
        UF.ActivateOwnFrames(mod)
    else
        UF.DeactivateOwnFrames()
        if UF.Extras then UF.Extras.Enable(mod) end
        if UF.IsBlizzardSilenced("player") or UF.IsBlizzardSilenced("target") then
            StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
        end
    end
end

mod.ApplyStyle = applyStyle

function mod:OnEnable()
    -- PLAYER_ENTERING_WORLD: Blizzard's frames exist and have laid out by then,
    -- and it also covers a /reload.
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        applyStyle()
    end)
    if IsLoggedIn and IsLoggedIn() then applyStyle() end
end

function mod:OnDisable()
    UF.DeactivateOwnFrames()
    if UF.Extras then UF.Extras.Disable() end
    if UF.IsBlizzardSilenced("player") or UF.IsBlizzardSilenced("target") then
        StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
    end
end

function mod:GetOptions()
    local items = {
        { type = "header", text = L["Style"] },
        { type = "dropdown", label = L["Frame style"], width = 240,
          values = {
              { value = "standard", text = L["Standard (Blizzard's frames plus extras)"] },
              { value = "classic",  text = L["Classic (original frame art)"] },
              { value = "modern",   text = L["Modern (flat house style)"] },
          },
          get = function() return mod.db.style end,
          set = function(_, v)
              if v == mod.db.style then return end
              mod.db.style = v
              applyStyle()
              if ns.UI and ns.UI.BuildOptionsPage then ns.UI:BuildOptionsPage("unitframes") end
          end },
        { type = "desc", text = L["|cffaaaaaaClassic and Modern are our own frames; move them with /vedit. Switching back to Standard asks for a reload.|r"] },
        { type = "spacer", height = 8 },
    }

    if mod.db.style == "standard" then
        items[#items + 1] = { type = "header", text = L["Extras on Blizzard's frames"] }
        items[#items + 1] = { type = "toggle", label = L["Class color on the health bar"],
            get = function() return mod.db.classColor end,
            set = function(_, v) mod.db.classColor = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Threat display on the target frame"],
            get = function() return mod.db.threat end,
            set = function(_, v) mod.db.threat = v; applyStyle() end }
        items[#items + 1] = { type = "toggle", label = L["Class icon on the portrait"],
            get = function() return mod.db.classIcon end,
            set = function(_, v) mod.db.classIcon = v; applyStyle() end }
    elseif mod.db.style == "classic" then
        items[#items + 1] = { type = "header", text = L["Classic"] }
        items[#items + 1] = { type = "toggle", label = L["Elite dragon on the player frame"],
            get = function() return mod.db.playerElite end,
            set = function(_, v) mod.db.playerElite = v; applyStyle() end }
    else
        items[#items + 1] = { type = "header", text = L["Modern"] }
        items[#items + 1] = { type = "toggle", label = L["Show portrait"],
            get = function() return mod.db.portrait end,
            set = function(_, v) mod.db.portrait = v; applyStyle() end }
    end

    if isOwnStyle(mod.db.style) then
        items[#items + 1] = { type = "spacer", height = 8 }
        items[#items + 1] = { type = "header", text = L["Size"] }
        for _, unit in ipairs({ "player", "target" }) do
            local key = unit
            items[#items + 1] = { type = "slider",
                label = unit == "player" and L["Player frame scale"] or L["Target frame scale"],
                min = 0.5, max = 2, step = 0.05,
                get = function() return mod.db[key].scale or 1 end,
                set = function(_, v)
                    mod.db[key].scale = v
                    local f = UF.Frames[key]
                    if f and f.mover then ns:MoverSetScale(f.mover, v) end
                end }
        end
        items[#items + 1] = { type = "button", label = L["Open Edit Mode"],
            onClick = function() ns:SetEditMode(true) end }
    end

    return items
end
```

- [ ] **Step 3: TOC + checker**

Add `Modules\UnitFrames.lua` to `VuloForeverUI.toc` after `Modules\UnitFramesEngine.lua`. Add the new locale keys the checker lists (German: `Style` → `Stil`, `Frame style` → `Rahmenstil`, `Standard (Blizzard's frames plus extras)` → `Standard (Blizzard-Rahmen plus Extras)`, `Classic (original frame art)` → `Classic (originale Rahmenkunst)`, `Modern (flat house style)` → `Modern (flacher Hausstil)`, `Extras on Blizzard's frames` → `Extras auf Blizzard-Rahmen`, `Class color on the health bar` → `Klassenfarbe auf dem Lebensbalken`, `Threat display on the target frame` → `Bedrohungsanzeige am Zielrahmen`, `Class icon on the portrait` → `Klassensymbol auf dem Portrait`, `Elite dragon on the player frame` → `Elite-Drache am Spielerrahmen`, `Show portrait` → `Portrait anzeigen`, `Size` → `Größe`, `Player frame scale` → `Skalierung Spielerrahmen`, `Target frame scale` → `Skalierung Zielrahmen`, `Open Edit Mode` → `Edit Mode öffnen`, the reload popup text → `Blizzards Rahmen kommen nach einem Reload zurück. UI jetzt neu laden?`, and the desc line → `Classic und Modern sind eigene Rahmen; verschieben mit /vedit. Zurück auf Standard fragt nach einem Reload.`).

Run: `cd tools && node check.js` → `RESULT: OK`.

- [ ] **Step 4: In-game probe — the switch, both directions**

`/reload`. Open `/vfui` → Unit Frames.
1. Style **Classic**: Blizzard's player frame content and the whole target frame vanish; our two frames appear; the **pet frame stays** (summon a pet or check `/fstack` that `PetFrame` still has parent `PlayerFrame` and is not under a hidden parent). Target a mob: our target frame shows; clear target: hides.
2. Style **Modern**: same frames re-skinned in place, no reload.
3. Enter combat, switch style in the options: nothing happens until combat ends, then it applies (the pending path).
4. Style **Standard**: our frames hide, the reload popup appears; accept → Blizzard's frames are back.
5. `/vedit` in Classic: drag the player frame, `/reload`, it is where you left it.

- [ ] **Step 5: Commit**

```bash
git add Modules/UnitFrames.lua Modules/UnitFramesEngine.lua VuloForeverUI.toc Locales
git commit -F - <<'EOF'
Unit Frames: Modul, Stilwechsel und das Stilllegen der Blizzard-Rahmen

Standard laesst Blizzards Rahmen stehen, Classic und Modern legen sie still:
Spielerrahmen behaelt sein Parent (der Pet-Rahmen haengt daran), nur seine
Inhalte gehen; der Zielrahmen wandert an ein verstecktes Parent. Im Kampf
wird der Wechsel bis PLAYER_REGEN_ENABLED aufgeschoben, zurueck auf
Standard fragt nach einem Reload.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 5: Extras — Standard-style hooks on Blizzard's frames

**Files:**
- Create: `Modules/UnitFramesExtras.lua`
- Modify: `VuloForeverUI.toc` (add `Modules\UnitFramesExtras.lua` after `Modules\UnitFramesEngine.lua`, **before** `Modules\UnitFrames.lua`)

**Interfaces:**
- Consumes: `ns.UF.PaintThreat(fs, glow, unit, mobUnit)`, `ns.UF.ClassColor(unit)` (Task 3); Forever parent keys from the facts table.
- Produces: `ns.UF.Extras.Enable(mod)`, `ns.UF.Extras.Disable()`. Hooks are installed once and gated by `active`; Disable only hides our regions and lets Blizzard's colour stand.

- [ ] **Step 1: Write the file**

```lua
-- VuloForeverUI / Modules / UnitFramesExtras
--
-- The Standard style: Blizzard's PlayerFrame and TargetFrame stay, we lay
-- three things on top -- class colour on the health bar, a threat readout on
-- the target frame, a class icon over the portrait. Cosmetic only:
-- hooksecurefunc plus our own regions, never Blizzard's secure state, so
-- nothing here taints and nothing here is protected.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Extras = {}
local Extras = UF.Extras

local active, mod = false, nil
local hooked = false

-- Forever's Mainline frame tree (Mainline/PlayerFrame.xml, TargetFrame.xml).
local function playerHealthBar()
    local pf = _G.PlayerFrame
    local main = pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
    return main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
end
local function targetHealthBar()
    local tf = _G.TargetFrame
    local main = tf and tf.TargetFrameContent and tf.TargetFrameContent.TargetFrameContentMain
    return main and main.HealthBarsContainer and main.HealthBarsContainer.HealthBar
end
local function playerPortrait()
    local pf = _G.PlayerFrame
    return pf and pf.PlayerFrameContainer and pf.PlayerFrameContainer.PlayerPortrait
end
local function targetPortrait()
    local tf = _G.TargetFrame
    return tf and tf.TargetFrameContainer and tf.TargetFrameContainer.Portrait
end

local unitOfBar = {}

-- Blizzard sets the health bar green inside UnitFrameHealthBar_Update
-- (Mainline/UnitFrame.lua); we answer AFTER it with the class colour when
-- the class is readable, and say nothing otherwise.
local function recolor(statusbar, unit)
    if not active or not mod.db.classColor then return end
    unit = unit or unitOfBar[statusbar]
    if not unit then return end
    local r, g, b = UF.ClassColor(unit)
    if r then statusbar:SetStatusBarColor(r, g, b) end
end

local threatFS, threatGlow, classIcons

local function ensureRegions()
    if threatFS then return end
    local tf = _G.TargetFrame
    threatFS = tf:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(threatFS, 11, "OUTLINE")
    threatFS:SetPoint("BOTTOM", tf, "TOP", 0, -2)
    threatGlow = tf:CreateTexture(nil, "BACKGROUND", nil, -3)
    threatGlow:SetPoint("TOPLEFT", tf, "TOPLEFT", 8, -8)
    threatGlow:SetPoint("BOTTOMRIGHT", tf, "BOTTOMRIGHT", -8, 8)
    threatGlow:Hide()

    classIcons = {}
    for unit, portrait in pairs({ player = playerPortrait(), target = targetPortrait() }) do
        if portrait then
            local icon = portrait:GetParent():CreateTexture(nil, "OVERLAY")
            icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            icon:SetSize(16, 16)
            icon:SetPoint("BOTTOMLEFT", portrait, "BOTTOMLEFT", -2, -2)
            icon:Hide()
            classIcons[unit] = icon
        end
    end
end

local function paintThreat()
    if not active or not mod.db.threat or not UnitExists("target") then
        if threatFS then threatFS:SetText(""); threatGlow:Hide() end
        return
    end
    UF.PaintThreat(threatFS, threatGlow, "player", "target")
end

local function paintClassIcons()
    for unit, icon in pairs(classIcons or {}) do
        local _, token = UnitClass(unit)
        local coords = active and mod.db.classIcon and UnitExists(unit) and UnitIsPlayer(unit)
            and token and ns.CanRead(token) and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
        if coords then
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            icon:Show()
        else
            icon:Hide()
        end
    end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event)
    if event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE" then
        paintThreat()
    else
        paintThreat()
        paintClassIcons()
        local pb, tb = playerHealthBar(), targetHealthBar()
        if pb then recolor(pb, "player") end
        if tb and UnitExists("target") then recolor(tb, "target") end
    end
end)

local function installHooks()
    if hooked then return end
    hooked = true
    local pb, tb = playerHealthBar(), targetHealthBar()
    if pb then unitOfBar[pb] = "player" end
    if tb then unitOfBar[tb] = "target" end
    hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
        if unitOfBar[statusbar] then recolor(statusbar, unit) end
    end)
    hooksecurefunc("UnitFrameHealthBar_OnValueChanged", function(statusbar)
        if unitOfBar[statusbar] then recolor(statusbar) end
    end)
end

function Extras.Enable(m)
    mod = m
    active = true
    ensureRegions()
    installHooks()
    events:RegisterEvent("PLAYER_TARGET_CHANGED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
    events:RegisterEvent("GROUP_ROSTER_UPDATE")
    -- first paint
    events:GetScript("OnEvent")(events, "PLAYER_ENTERING_WORLD")
end

function Extras.Disable()
    active = false
    events:UnregisterAllEvents()
    if threatFS then threatFS:SetText(""); threatGlow:Hide() end
    for _, icon in pairs(classIcons or {}) do icon:Hide() end
    -- Blizzard repaints its own colour on the next health update; we do not
    -- guess at it here.
end
```

- [ ] **Step 2: TOC + checker**

Add `Modules\UnitFramesExtras.lua` to the TOC between `UnitFramesEngine.lua` and `UnitFrames.lua`. Run `cd tools && node check.js` → `RESULT: OK`.

- [ ] **Step 3: In-game probe — Standard extras**

`/reload`, style **Standard** (the default):
- Your health bar is in your class colour, not green. `/target player` → the target frame health bar too; target a mob → Blizzard's green/red stays.
- Class icon in the portrait corner on the player frame; on a player target too; not on mobs.
- Hit a mob: a threat percent or "Aggro" above the target frame, glow behind it when you have aggro. **No red error**, `/vfsecrets` mid-fight still prints.
- Switch each toggle off and on: the colour, icon and threat text follow (colour only after the next health tick).

- [ ] **Step 4: Commit**

```bash
git add Modules/UnitFramesExtras.lua VuloForeverUI.toc
git commit -F - <<'EOF'
Unit Frames: Extras auf Blizzards Rahmen im Standard-Stil

Klassenfarbe nach UnitFrameHealthBar_Update, Bedrohungsanzeige am
Zielrahmen ueber den geteilten Maler, Klassensymbol am Portrait. Nur
hooksecurefunc und eigene Regionen, nie Blizzards Secure-State.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

### Task 6: Review, docs, memory

**Files:**
- Modify: `docs/forever-client-research.md` (append what the in-game passes proved or disproved)
- Modify: `CLAUDE.md` layout block (`Modules/   feature modules (GlobalSettings, Profiles, Minimap, BarSetups, UnitFrames so far)`)
- Possibly modify: any of the four module files, per review findings

- [ ] **Step 1: Adversarial review**

Invoke the `adversarial-review` skill on the four files with this attack list:
1. Any `if`, `==`, `<`, `+`, `..` or table index on a value from `UnitHealth`, `UnitHealthPercent`, `UnitPower`, `AbbreviateNumbers`, `UnitDetailedThreatSituation` — line by line.
2. `UnitName` secret into `SetText` — fine; `UnitName` into `..` anywhere — bug.
3. Anything called on Blizzard's frames in combat that is protected (`SetParent`, `Show/Hide` on a protected frame, `EnableMouse`): every such call must be behind `ns:InCombat()` or the deferred path.
4. `RegisterUnitWatch` after `UnregisterUnitWatch`: Show/Hide of a secure button is protected in combat — activation must be out of combat (it is, via `applyStyle`'s gate).
5. The `keepHidden` Show hook and the `SetParent` hook: can either fire in combat and call a protected function? (`C_Timer.After` + `Hide` on a non-protected content container is fine; `SetParent` on `TargetFrame` is guarded by `not ns:InCombat()` — confirm.)
6. `wireEvents` `pcall(ev.RegisterUnitEvent, …)` with a nil second unit — `RegisterUnitEvent(event, "target", nil)` is legal; confirm no error line at load.
7. Locale keys at file scope — only inside `ns.OnLocaleReady` or functions.
8. `hooksecurefunc("UnitFrameHealthBar_Update")` — the global exists on Forever (`Mainline/UnitFrame.lua`); confirm the name did not change in the build the user runs by `/run print(UnitFrameHealthBar_Update)`.

Fix CONFIRMED findings, re-run the checker.

- [ ] **Step 2: Full in-game pass (the spec's test list)**

Both skins, out of and in combat, target swap mid-fight, `/vedit` move + reload, style switch each way, pet frame visible in Classic/Modern, `/vfuiprof` after a fight shows `unitframes` with a sane ms count.

- [ ] **Step 3: Record what was learned**

Append to `docs/forever-client-research.md` under "To verify in the beta": whether `SetFormattedText("%d%%", secret)` rendered, whether `UnitHealthPercent(unit, true, colorCurve)` returned a usable colour, whether `RegisterUnitWatch` on a frame created at `PLAYER_ENTERING_WORLD` showed/hid correctly, and any protected-function error seen. Update the `CLAUDE.md` layout line.

- [ ] **Step 4: Commit**

```bash
git add docs/forever-client-research.md CLAUDE.md Modules
git commit -F - <<'EOF'
Unit Frames: Review-Befunde und Doku

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
```

---

## Self-review against the spec

- **Scope (player + target, three styles, no auras):** Tasks 1–5. No aura call anywhere. ✔
- **§1 Module and options:** Task 4 — style dropdown, extras toggles, `playerElite`, `portrait`, mover-backed position/scale, live switch to own skins, reload popup back to Standard, combat deferral via `pendingApply`. ✔
- **§2 Engine:** Task 2 (frames, attributes, `RegisterUnitWatch`, mover), Task 3 (events per channel via `RegisterUnitEvent`, all painters with the secret paths named in the spec), Task 4 (silencing with the pet-frame exception that came out of the client facts — a deliberate deviation from the spec's "reparent PlayerFrame", recorded in the engine comment). ✔
- **§3 Skins:** Task 1 — Classic numbers from the classic XML, Modern in the house style, `apply()` as the only logic. ✔
- **§4 Extras:** Task 5 — class colour via `UnitFrameHealthBar_Update` hook, threat via the shared painter, class icon; rare/elite and permanent text dropped as the spec says. ✔
- **§5 Combat, errors, testing:** every gated action listed sits behind `ns:InCombat()`; Task 6 is the review and the in-game pass. ✔
- **Placeholders:** none; every step has code or an exact click/`/run` sequence.
- **Type consistency:** `ns.UF.CreateUnitFrame(unit, db, label)`, `ns.UF.SetSkin(frame, skinName, opts)`, `ns.UF.ApplySkin(frame, skin, opts)`, `ns.UF.Paint(frame)`, `ns.UF.PaintThreat(fs, glow, unit, mobUnit)`, `ns.UF.ClassColor(unit)`, `ns.UF.SetEventsEnabled(frame, on)`, `ns.UF.SilenceBlizzard(unit)`, `ns.UF.ActivateOwnFrames(mod)`, `ns.UF.DeactivateOwnFrames()`, `ns.UF.Extras.Enable(mod)` / `Disable()` — used with the same names and arities in every task.

---

# Amendment A (2026-09-18, approved) — Classic becomes a reskin

Supersedes Task 4's `applyStyle`/options and adds Task 6a. Tasks 1–3 stand
(committed). Spec: "Amendment A" in `docs/superpowers/specs/2026-09-18-unitframes-design.md`.

Style map after the amendment:

| Style | Blizzard frames | Extras (Task 5) | Classic reskin (Task 6a) | Own frames (engine) |
|---|---|---|---|---|
| standard | shown | on | off | none |
| classic  | shown, reskinned | on | on | none |
| modern   | silenced | off | off | player + target |

Leaving **classic** or **modern** for another style asks for `/reload`
(reskin hooks and silenced frames cannot be undone).

## Task 4 (amended): module + Modern-only activation

Everything in the original Task 4 applies, with these replacements:

1. In the engine's appended code, `UF.ActivateOwnFrames` handles only
   `"modern"`:
   ```lua
   function UF.ActivateOwnFrames(mod)
       if mod.db.style ~= "modern" then return end
       for _, unit in ipairs({ "player", "target" }) do
           local f = UF.CreateUnitFrame(unit, mod.db[unit], LABELS[unit])
           UF.SetSkin(f, "modern", { unit = unit, portrait = mod.db.portrait })
           RegisterUnitWatch(f)
           UF.SetEventsEnabled(f, true)
           UF.SilenceBlizzard(unit)
       end
   end
   ```
2. In `Modules/UnitFrames.lua`, replace `isOwnStyle` and `applyStyle` with:
   ```lua
   local function needsReloadFrom(oldStyle)
       return oldStyle == "classic" or oldStyle == "modern"
   end

   local function applyStyle(oldStyle)
       if ns:InCombat() then
           if not pendingApply then
               pendingApply = true
               ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                   pendingApply = false
                   applyStyle(oldStyle)
               end)
           end
           return
       end
       local style = mod.db.style
       if style == "modern" then
           if UF.Extras  then UF.Extras.Disable() end
           if UF.Classic then UF.Classic.Disable() end
           UF.ActivateOwnFrames(mod)
       elseif style == "classic" then
           UF.DeactivateOwnFrames()
           if UF.Extras  then UF.Extras.Enable(mod) end
           if UF.Classic then UF.Classic.Enable(mod) end
       else
           UF.DeactivateOwnFrames()
           if UF.Classic then UF.Classic.Disable() end
           if UF.Extras  then UF.Extras.Enable(mod) end
       end
       if oldStyle and oldStyle ~= style and needsReloadFrom(oldStyle) then
           StaticPopup_Show("VFUI_UNITFRAMES_RELOAD")
       end
   end
   ```
   The dropdown's `set` passes the previous style: `local old = mod.db.style; mod.db.style = v; applyStyle(old)`. `OnEnable` calls `applyStyle()` with no argument. `OnDisable` deactivates own frames, disables Extras and Classic, and shows the reload popup when the style was classic or modern.
3. Popup text `L["Blizzard's frames come back after a reload. Reload the UI now?"]` stays; it now also covers leaving Classic.
4. Options: the **Classic** section keeps the `playerElite` toggle (its `set` calls `applyStyle()` — the reskin re-reads the flag on Enable). The **Size** sliders and the **Open Edit Mode** button appear for **modern only** (Classic is positioned by Blizzard's Edit Mode). Add under Classic a `desc`: `L["|cffaaaaaaClassic keeps Blizzard's frames underneath: target auras, the target cast bar and the pet frame stay, and Edit Mode moves them.|r"]` (German: `Classic behält Blizzards Rahmen darunter: Ziel-Auren, Ziel-Zauberleiste und Pet-Rahmen bleiben, Edit Mode verschiebt sie.`).
5. Every `UF.Classic` reference is nil-guarded as shown, so Task 4 loads and works before Task 6a exists.
6. Probe (amended): Standard → Modern (own frames, Blizzard silenced, pet visible) → back to Standard (reload popup) is the Task 4 probe. Classic is probed in Task 6a.

## Task 5 (unchanged): Extras — shared by Standard and Classic

No change to the code. Note for the implementer: `Extras.Enable` will also be called while the Classic reskin is active; it must not depend on Blizzard's retail anchors beyond the parent keys it already uses (health bar, portrait), which the reskin moves but keeps.

## Task 6a (new): Classic reskin of Blizzard's frames

**Lane:** high-complexity (`fable-implementer`) — this is surgery on
protected frames' children; judgment about what may be touched matters.

**Files:**
- Create: `Modules/UnitFramesClassic.lua`
- Modify: `VuloForeverUI.toc` — add `Modules\UnitFramesClassic.lua` after `Modules\UnitFramesExtras.lua`, before `Modules\UnitFrames.lua`.

**Interfaces:**
- Consumes: `ns:InCombat()`, `ns:RegisterEventOnce`, the parent keys from the client-facts table.
- Produces: `ns.UF.Classic.Enable(mod)`, `ns.UF.Classic.Disable()`, `ns.UF.Classic.IsActive()`.

**Rules (hard):**
- Widget calls and `hooksecurefunc` only. **No Lua field writes into Blizzard's frames** (no `PlayerFrame.foo = …`); keep our own regions in a local weak-keyed side table `own[frame]`.
- Textures we replace are hidden with `Hide()` **and** `SetAlpha(0)` (Blizzard's `Show()` cannot bring them back visibly). Frames that inherit protected templates are never hidden — alpha only.
- Every `SetPoint` / `SetSize` on a Blizzard region runs out of combat only; in combat the work is flagged and one `PLAYER_REGEN_ENABLED` one-shot replays it (`ns:RegisterEventOnce`).
- No unit value is read except `UnitClassification("target")` (readable) for the art file — the bars keep Blizzard's values and colours; the Extras layer already adds class colour.
- Hooks are installed once and gated by `active`; `Disable()` hides our art and sets `active = false` — it does not try to move regions back (the module asks for a reload).

**Layout (anchors relative to the Blizzard frame, as Blizzard's Classic XML had them):**

| Region | Player | Target |
|---|---|---|
| art overlay (our texture, layer BORDER on a skin frame at `main:GetFrameLevel()+1`) | `UI-TargetingFrame`, texcoords `0.85546875, 0.1015625, 0.0625, 0.6640625`, size 193×77, `CENTER` of PlayerFrame, 0,0 | file by classification (below), texcoords `0.1015625, 1.0, 0.0078125, 0.78125`, size 230×99, `CENTER` of TargetFrame, 18.5, -4 |
| backdrop (our black 50 % texture, BACKGROUND -8) | 119×41 `TOPLEFT 89.5, -26` | 119×41 `TOPRIGHT -89.5, -26` |
| portrait (`PlayerFrameContainer.PlayerPortrait` / `TargetFrameContainer.Portrait`) | 64×64 `TOPLEFT 24, -16` | 64×64 `TOPRIGHT -24, -16` |
| portrait mask (`PlayerPortraitMask` / `PortraitMask`) | retexture to `Interface\Buttons\WHITE8X8`, anchored to the portrait grown 4 px each side — the art's ring hides the corners | same |
| health container (`…HealthBarsContainer`) | 119×12 `TOPLEFT 90, -45` | 119×12 `TOPRIGHT -90, -45` |
| mana bar (`…ManaBarArea.ManaBar` / `…TargetFrameContentMain.ManaBar`) | 119×12 `TOPLEFT 90, -56` | 119×12 `TOPRIGHT -90, -56` |
| name (`_G.PlayerName` / `…TargetFrameContentMain.Name`) | 100×12 `CENTER 34, 15` | 100×12 `CENTER -34, 15` |
| level (`_G.PlayerLevelText` / `…TargetFrameContentMain.LevelText`) | `CENTER` of `BOTTOMLEFT` 35.25, 30 | `CENTER` of `BOTTOMRIGHT` -35.25, 30 |
| hide (Hide + alpha 0) | `PlayerFrameContainer.FrameTexture`, `.AlternatePowerFrameTexture`, `.VehicleFrameTexture`, `PlayerFrameContentMain.LevelBackgroundCircle`, `.StatusTexture` (also `SetTexture(nil)`) | `TargetFrameContainer.FrameTexture`, `.BossPortraitFrameTexture`, `TargetFrameContentMain.LevelBackgroundCircle` |
| bar textures | `HealthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")`, same for `ManaBar` | same |
| classification art (target) | — | `normal → UI-TargetingFrame`, `elite/worldboss → -Elite`, `rare → -Rare`, `rareelite → -Rare-Elite`; player wears `-Elite` when `mod.db.playerElite` |
| raise | — | `TargetFrameContentContextual` to `skin:GetFrameLevel()+1` so Blizzard's auras and icons draw over our art |

**Re-apply hooks (installed once):** `hooksecurefunc("PlayerFrame_ToPlayerArt", relayoutPlayer)`, `"PlayerFrame_ToVehicleArt"`, `"PlayerFrame_UpdateArt"`, `"PlayerFrame_UpdatePlayerNameTextAnchor"`, `"UnitFrameManaBar_UpdateType"` (re-set the bar texture), `hooksecurefunc(TargetFrame, "CheckClassification", relayoutTarget)`, `hooksecurefunc(TargetFrame, "CheckFaction", relayoutTarget)`. Each hook body: `if not active then return end; if ns:InCombat() then pendingX = true; arm() else relayoutX() end`. Verify every hooked global exists on this client first: fetch `Blizzard_UnitFrame/Mainline/PlayerFrame.lua` and `Mainline/UnitFrame.lua` from the `forever` branch of Gethe/wow-ui-source and grep the function names; drop a hook whose function does not exist and say so in the report.

**Code skeleton (the implementer fills the relayout bodies from the table above):**

```lua
-- VuloForeverUI / Modules / UnitFramesClassic
-- The Classic look as a RESKIN of Blizzard's frames: our art on an overlay,
-- Blizzard's regions moved to the Classic coordinates, the retail chrome
-- hidden. Blizzard's untainted code keeps driving bars, texts, auras and the
-- target cast bar -- in combat too. Widget calls and hooksecurefunc only.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF
UF.Classic = {}
local Classic = UF.Classic

local ART = "Interface\\TargetingFrame\\UI-TargetingFrame"
local ART_BY_CLASS = { elite = ART .. "-Elite", worldboss = ART .. "-Elite",
                       rare = ART .. "-Rare", rareelite = ART .. "-Rare-Elite" }
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local active, mod = false, nil
local own = setmetatable({}, { __mode = "k" })   -- Blizzard frame -> our regions
local pendingPlayer, pendingTarget = false, false

local function hideTexture(t) if t then t:Hide(); t:SetAlpha(0) end end
local function fadeFrame(f)  if f then f:SetAlpha(0) end end

local function skinFor(frame, main)
    local s = own[frame]
    if s then return s end
    s = CreateFrame("Frame", nil, frame)
    s:SetAllPoints(frame)
    s:SetFrameLevel((main or frame):GetFrameLevel() + 1)
    s.art = s:CreateTexture(nil, "BORDER")
    s.backdrop = s:CreateTexture(nil, "BACKGROUND", nil, -8)
    s.backdrop:SetColorTexture(0, 0, 0, 0.5)
    own[frame] = s
    return s
end

local function neuterMask(mask, portrait)
    if not mask then return end
    mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", portrait, "TOPLEFT", -4, 4)
    mask:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 4, -4)
end

local arm
local function relayoutPlayer()
    -- rows "Player" of the layout table; first line:
    -- if ns:InCombat() then pendingPlayer = true; arm(); return end
end
local function relayoutTarget()
    -- rows "Target" of the layout table; same combat gate with pendingTarget
end
arm = function()
    ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
        if pendingPlayer then pendingPlayer = false; relayoutPlayer() end
        if pendingTarget then pendingTarget = false; relayoutTarget() end
    end)
end

local hooked = false
local function installHooks()
    if hooked then return end
    hooked = true
    -- the hook list above, each body gated on `active`
end

function Classic.Enable(m)
    mod, active = m, true
    installHooks()
    relayoutPlayer()
    relayoutTarget()
end
function Classic.Disable()
    active = false
    for _, s in pairs(own) do s:Hide() end
end
function Classic.IsActive() return active end
```

**Probe:** `/reload`, style **Classic**: both Blizzard frames wear the Classic art (player with the elite dragon when the toggle is on), portrait square-in-ring, bars 119 px in the art slots, name gold above, level in the ring corner; retail chrome gone; **Blizzard's auras still on the target frame, the target cast bar still shows on a casting mob, pet frame visible**. Target an elite: art swaps. Fight: bars and texts keep moving, no red error, `/vfsecrets` prints. Edit Mode (Blizzard's) still moves the frames. Switch to Standard: reload popup.

## Task 7 (was 6): Review, docs, memory — unchanged, plus

Attack items for the review of `UnitFramesClassic.lua`: every `SetPoint`/`SetSize`/`SetParent`/`Hide` on a Blizzard region — is the region a protected frame (`IsProtected()`), and is the call gated on out-of-combat? Any Lua field write into a Blizzard table? Any hooked global that does not exist on Forever?
