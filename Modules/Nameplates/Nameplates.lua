-- VuloForeverUI / Modules / Nameplates
--
-- Enemy nameplates built from our own frames. Blizzard's plate stays alive but
-- invisible (Suppress.lua): it keeps click selection, the widget container and
-- the soft-target icon working, and we never have to fight CompactUnitFrame for
-- the layout of a frame it re-lays out on every update.
--
-- The rules every file in this folder follows (docs/superpowers/specs/
-- 2026-09-20-nameplates-design.md has the evidence):
--   * a secret only ever travels into a widget setter;
--   * a two-way choice on a secret boolean is folded by the client
--     (ns.FoldColor, ns.AlphaFromBool), never branched on;
--   * "is there a value" is ns.Exists(v), nothing else;
--   * branches hang on OUR plain state (plate.isCasting, plate.isTarget);
--   * nothing is written onto a Blizzard frame -- weak tables hold that state.
--
-- This file: the module, its defaults, the pool, the manager events, CVars and
-- the clickable area. It loads first and calls into the other files only from
-- OnEnable and event handlers, when all of them exist.
local _, ns = ...
local L = ns.L

local NP = {
    plates  = {},   -- unit token -> our plate
    byNameplate = setmetatable({}, { __mode = "k" }),   -- base plate -> our plate
    pending = {},   -- unit token -> true: has a Blizzard plate we left alone (not attackable)
    gen     = 1,    -- appearance generation; a plate restyles when its own is older
    ctx     = { inGroup = false, isTank = false, inInstance = false },
}
ns.NP = NP

local function c(r, g, b, a) return { r = r, g = g, b = b, a = a } end

-- Which unit a base plate is showing. The field is unitToken and the getter is
-- GetUnit -- the retail name namePlateUnitToken does NOT exist on 1.60.1
-- (proven in the client 2026-09-20: reading it gave nil and UnitIsUnit threw).
function NP.UnitOf(nameplate)
    if not nameplate then return nil end
    local unit = (nameplate.GetUnit and nameplate:GetUnit()) or nameplate.unitToken
    return type(unit) == "string" and unit or nil
end

local M = ns:RegisterModule("nameplates", {
    name        = "Nameplates",
    group       = "HUD",
    description = "Enemy nameplates with health, cast bar, threat colours and target effects.",
    defaults = {
        enabled = true,

        -- style
        showBorder = true, borderSize = 1, borderColor = c(.067, .067, .067),
        wrapBorderCastbar = false,
        bgColor = c(.12, .12, .12), bgAlpha = 1,
        absorbStyle = "blizzard", absorbColor = c(1, 1, 1), absorbAlpha = 80,
        healthBarTexture = "", castBarTexture = "",
        healthBarWidth = 156, healthBarHeight = 17,

        -- text slots: what each one shows and how. A name element can sit in
        -- one slot only (NP.AssignTextSlot keeps that true).
        textSlots = {
            Top    = { element = "enemyName",     size = 11, color = c(1, 1, 1), x = 0, y = 0, decimal = false },
            Right  = { element = "healthPercent", size = 10, color = c(1, 1, 1), x = 0, y = 0, decimal = false },
            Left   = { element = "level",         size = 10, color = c(1, 1, 1), x = 0, y = 0, decimal = false },
            Center = { element = "none",          size = 10, color = c(1, 1, 1), x = 0, y = 0, decimal = false },
        },
        enemyNameWidthPct = 100, enemyNameWrap = false,
        levelDifficultyColor = true,

        -- icon slots
        raidMarkerPos = "topright", classificationSlot = "topleft",
        classificationShowInInstances = false,
        iconSlots = {
            top     = { size = 26, x = 0, y = 0 }, bottom   = { size = 26, x = 0, y = 0 },
            left    = { size = 24, x = 0, y = 0 }, right    = { size = 24, x = 0, y = 0 },
            topleft = { size = 24, x = 0, y = 0 }, topright = { size = 24, x = 0, y = 0 },
        },
        nameRaidMarkerEnabled = false, nameRaidMarkerSize = 14,

        -- auras: the engine shows them, we only say where and how many
        debuffSlot = "top", buffSlot = "left", ccSlot = "right",
        auras = {
            debuffs = { max = 5, spacing = 2, crop = false, cropPct = 10, hideBorder = false },
            buffs   = { max = 4, spacing = 2, crop = false, cropPct = 10, hideBorder = false },
            cc      = { max = 2, spacing = 2, crop = false, cropPct = 10, hideBorder = false },
        },
        auraText = {
            duration = { position = "topleft",     size = 11, color = c(1, 1, 1), x = 0, y = 0 },
            stacks   = { position = "bottomright", size = 11, color = c(1, 1, 1), x = 0, y = 0 },
        },
        debuffIncludeCC = false, showAllDebuffs = false,
        enemyBuffFilter = "important",

        -- colours: enemy types
        neutral = c(.81, .72, .19), tapped = c(.5, .5, .5),
        enemyInCombat = c(.8, .137, .137), caster = c(.231, .51, .965),
        miniboss = c(.518, .243, .984), boss = c(.518, .243, .984),
        darkenEnemiesOOC = true, darkenOOCRecolor = false, darkenOOCColor = c(.5, .5, .5),
        enemyNameTextReactionColor = false,
        enemyNameHostileColor = c(.39, .11, .09), enemyNameNeutralColor = c(.81, .72, .19),

        -- colours: threat
        tankHasAggro = c(.05, .82, .62), tankHasAggroEnabled = false,
        tankHasAggroOverrideMobType = false, tankHasAggroOverrideBoss = true,
        classicTankAggro = false,
        tankLosingAggro = c(.81, .72, .19), tankNoAggro = c(1, .22, .17),
        offTankAggro = c(.188, .761, .812), offTankAggroEnabled = true,
        dpsHasAggro = c(1, .5, 0), dpsNearAggro = c(.81, .72, .19),
        dpsNoAggro = c(.35, .75, .35), dpsNoAggroEnabled = false,
        dpsNoAggroOverrideMiniBoss = false, dpsNoAggroOverrideCaster = false,
        dpsNoAggroOverrideBoss = true,
        assumeTank = false,

        -- target, focus, hover
        target = c(.459, .89, .58), targetColorEnabled = false,
        focus = c(.051, .82, .62), focusColorEnabled = true,
        targetGlow = true, targetGlowBorderColor = false, targetGlowHighlight = false,
        targetGlowBorderSize = false, targetBorderSizeValue = 2,
        targetBorderColor = c(1, 1, 1), targetGlowColor = c(.4117, .6667, 1), targetGlowAlpha = 1,
        targetHighlightColor = c(1, 1, 1), targetHighlightAlpha = .2,
        targetOverlayTexture = "none", targetOverlayColor = c(1, 1, 1), targetOverlayAlpha = 1,
        targetOverlayFullBgAlpha = false, targetOverlayNoTint = false,
        focusOverlayTexture = "none", focusOverlayColor = c(1, 1, 1), focusOverlayAlpha = 1,
        focusOverlayFullBgAlpha = false, focusOverlayNoTint = false,
        hoverOverlayTexture = "none", hoverOverlayFullBgAlpha = false,
        hoverGlow = false, hoverGlowBorderColor = false, hoverGlowHighlight = true,
        hoverGlowBorderSize = false, hoverBorderSizeValue = 2,
        hoverBorderColor = c(1, 1, 1), hoverGlowColor = c(.4117, .6667, 1), hoverGlowAlpha = 1,
        hoverColor = c(1, 1, 1), hoverAlpha = .3,
        showTargetArrows = false, targetArrowScale = 1,
        targetArrowColor = c(1, 1, 1), targetArrowClassColor = false,
        targetScale = 100, nonTargetAlpha = 100, nonTargetKeepFocus = true,
        hashLineEnabled = false, hashLinePercent = 30, hashLineColor = c(1, 1, 1),
        focusLetterEnabled = false, focusLetterAnchor = "CENTER",
        focusLetterX = 0, focusLetterY = 0, focusLetterSize = 18,
        focusCastHeight = 100,

        -- cast bar
        castBarHeight = 17, castBarOffsetY = 0,
        castBar = c(.7, .4, .9), castBarUninterruptible = c(.45, .45, .45),
        interruptReady = c(.92, .35, .2),
        interruptMidCastEnabled = false, interruptMidCastColor = c(.318, .82, .357),
        kickTickEnabled = true, kickTickColor = c(1, 1, 1),
        castBarImportant = c(1, .2, .2), importantCastColorEnabled = false,
        importantCastGlow = true, importantCastGlowColor = c(1, .2, .2),
        castBarShieldEnabled = true, castBarSparkEnabled = true,
        interruptedFlashEnabled = true, interruptedFlashColor = c(.8, 0, 0),
        castScale = 100,
        castBgColor = c(.1, .1, .1), castBgAlpha = .9,
        castBorderSize = 0, castBorderColor = c(0, 0, 0),
        showCastIcon = true, castIconScale = 1, castIconOffsetX = 0, castIconOffsetY = 0,
        castbarIconInWidth = false, castIconOnRight = false, castIconFullSize = false,
        castIconTargetBorder = false, hideCastIconBorder = false,
        castNameSide = "left", castNameSize = 10, castNameColor = c(1, 1, 1),
        castNameOffsetX = 0, castNameOffsetY = 0, castNameWidthPct = 42, castNameWrap = false,
        castCombineNameTarget = false,
        castTargetSide = "right", castTargetSize = 10, castTargetColor = c(1, 1, 1),
        castTargetClassColor = true, castTargetOffsetX = 0, castTargetOffsetY = 0,
        castTargetWidthPct = 42, castTargetWrap = false,
        showCastTimer = true, castTimerSide = "right", castTimerSize = 10,
        castTimerColor = c(1, 1, 1), castTimerOffsetX = 0, castTimerOffsetY = 0,
        hideEnemyNameWhileCasting = false,

        -- spacing and behaviour
        stackingEnabled = true, stackSpacingScale = 100,
        hitboxScaleX = 100, hitboxScaleY = 100,
        showEnemyPets = false, hideEnemyPlatesOOC = false,
    },
})
NP.mod = M

function NP.db() return M.db end

-- A settings change: every live plate restyles once, new ones pick it up from
-- the generation stamp.
function NP.Bump()
    NP.gen = NP.gen + 1
    if not M.active then return end
    for _, plate in pairs(NP.plates) do
        plate:ApplyAppearance()
        plate:Refresh()
    end
end

-- One physical pixel in the plate's coordinate space. GetEffectiveScale on a
-- frame inside the nameplate tree may come back secret; then a UIParent pixel
-- is close enough for a border.
function NP.Pixel(frame, n)
    local es = ns.Num(frame and frame:GetEffectiveScale(), nil) or UIParent:GetEffectiveScale()
    local _, physH = GetPhysicalScreenSize()
    if not physH or physH <= 0 then physH = 1080 end
    if es <= 0 then es = 1 end
    return (n or 1) * (768 / physH) / es
end

-- ---------------------------------------------------------------------------
-- Pool
-- ---------------------------------------------------------------------------
-- A plain stack of our own. The client's frame pools hand tainted code a
-- proxied "secure" pool whose behaviour is not ours to rely on; this needs
-- nothing but a table.
local free = {}

function NP.Acquire()
    local plate = table.remove(free)
    if not plate then
        plate = CreateFrame("Frame", nil, UIParent)
        Mixin(plate, NP.Plate)
        plate:Hide()
        plate:Build()
    end
    return plate
end

function NP.Release(plate)
    plate:Clear()
    free[#free + 1] = plate
end

-- Building a plate is a few dozen regions; twenty of them on the first pull is
-- a visible hitch. Spread them out while nothing is happening.
local function prewarm()
    local made, handle = 0, nil
    handle = ns:AddTicker(0.1, function()
        if not M.active or made >= 20 then
            ns:CancelTicker(handle)
            if NP._warm then
                for _, plate in ipairs(NP._warm) do NP.Release(plate) end
                NP._warm = nil
            end
            return
        end
        made = made + 1
        -- One new plate per tick: hold the ones taken so far, give all back at the end.
        NP._warm = NP._warm or {}
        NP._warm[made] = NP.Acquire()
        if made >= 20 then
            for i = 1, made do NP.Release(NP._warm[i]) end
            NP._warm = nil
        end
    end, nil, "nameplates")
end

-- ---------------------------------------------------------------------------
-- Plates coming and going
-- ---------------------------------------------------------------------------
-- Attackable is the line between "ours" and "Blizzard's" in this stage. A plain
-- true only: a secret or nil answer leaves the plate with Blizzard.
local function isEnemy(unit)
    local can = UnitCanAttack("player", unit)
    return not ns.IsSecret(can) and can == true
end

local function attach(unit)
    local have = NP.plates[unit]
    if have then
        -- Our event can arrive before the driver has put its unit frame on the
        -- plate; then there was nothing to suppress yet. The driver hook calls
        -- in again right after, and this is where that frame is taken over.
        if not have.blizz and have.nameplate then have.blizz = NP.Suppress(have.nameplate) end
        return
    end
    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)
    if not nameplate then return end            -- forbidden plate: not ours to touch
    local isSelf = UnitIsUnit(unit, "player")
    if not ns.IsSecret(isSelf) and isSelf then return end
    if not isEnemy(unit) then
        -- "Attackable" can still read false on a unit's very first frame.
        if not NP.pending[unit] then
            NP.pending[unit] = true
            C_Timer.After(0.1, function() if NP.pending[unit] and NP.mod.active then NP.Attach(unit) end end)
        end
        return
    end
    NP.pending[unit] = nil
    local blizz = NP.Suppress(nameplate)
    local plate = NP.Acquire()
    NP.plates[unit] = plate
    plate.blizz = blizz
    plate:SetUnit(unit, nameplate)
end

local function detach(unit)
    NP.pending[unit] = nil
    local plate = NP.plates[unit]
    if not plate then return end
    NP.plates[unit] = nil
    local blizz = plate.blizz
    plate.blizz = nil
    NP.Release(plate)
    NP.Restore(blizz)
end
NP.Attach, NP.Detach = attach, detach

-- A duel starting or ending, a faction flip: the unit keeps its plate and its
-- token, only the answer to "attackable" changes.
local function recheck(_, unit)
    if type(unit) ~= "string" then return end
    if NP.pending[unit] then
        attach(unit)
    elseif NP.plates[unit] and not isEnemy(unit) then
        detach(unit)
        NP.pending[unit] = true
    end
end

-- ---------------------------------------------------------------------------
-- CVars. The client scales and fades plates on its own; we own both, so its
-- share is set to neutral. Every write: the CVar exists, the value differs,
-- out of combat, in a pcall. The values found are kept once and given back
-- when the module is switched off.
-- ---------------------------------------------------------------------------
local CVARS = {
    nameplateMinScale = "1", nameplateMaxScale = "1", nameplateSelectedScale = "1",
    nameplateMaxAlpha = "1", nameplateMinAlpha = "0.6",
    nameplateMaxAlphaDistance = "40", nameplateMinAlphaDistance = "-100000",
    nameplateOverlapH = "1",
    nameplateShowAll = "1",
    -- the class colour of enemy players is read off Blizzard's hidden bar.
    -- (ShowClassColorInNameplate, the retail sibling, does not exist here.)
    nameplateShowClassColor = "1",
}

local showEnemies

local function getCVar(name)
    local ok, v = pcall(C_CVar.GetCVar, name)
    if ok then return v end
end

local function setCVar(name, value)
    local cur = getCVar(name)
    if cur == nil or cur == value then return end
    local saved = M.db.savedCVars
    if saved[name] == nil then saved[name] = cur end
    pcall(C_CVar.SetCVar, name, value)
end
NP.SetCVar = setCVar

local function applyCVars()
    if not M.active then return end      -- queued in a fight the module was switched off in
    M.db.savedCVars = M.db.savedCVars or {}
    for name, value in pairs(CVARS) do setCVar(name, value) end
    setCVar("nameplateShowEnemyPets", M.db.showEnemyPets and "1" or "0")
    if Enum.NamePlateStackType and getCVar("nameplateStackingTypes") ~= nil then
        local bit = Enum.NamePlateStackType.Enemy
        if M.db.savedStacking == nil and C_CVar.GetCVarBitfield then
            local ok, was = pcall(C_CVar.GetCVarBitfield, "nameplateStackingTypes", bit)
            if ok then M.db.savedStacking = was and true or false end
        end
        pcall(C_CVar.SetCVarBitfield, "nameplateStackingTypes", bit, M.db.stackingEnabled and true or false)
    end
end

local function restoreCVars()
    if M.db.hideEnemyPlatesOOC then pcall(C_CVar.SetCVar, "nameplateShowEnemies", "1") end
    if M.db.savedStacking ~= nil and Enum.NamePlateStackType then
        pcall(C_CVar.SetCVarBitfield, "nameplateStackingTypes", Enum.NamePlateStackType.Enemy, M.db.savedStacking)
        M.db.savedStacking = nil
    end
    local saved = M.db.savedCVars
    if not saved then return end
    for name, value in pairs(saved) do pcall(C_CVar.SetCVar, name, value) end
    M.db.savedCVars = nil
end

function NP.ApplyCVars()
    ns:RunOutOfCombatOnce("np-cvars", applyCVars)
end

-- ---------------------------------------------------------------------------
-- Clickable area. The base plate is what the client hit-tests; it is sized to
-- the health bar, and the insets are pushed far out so the client clamps them
-- to exactly that plate. Both setters are PROTECTED: out of combat only, and a
-- change asked for during a fight lands when the fight ends.
-- ---------------------------------------------------------------------------
-- PROTECTED, proven in the client 2026-09-20: called in combat, the client
-- fires ADDON_ACTION_BLOCKED and does nothing -- without raising a Lua error,
-- so the pcall below would report success for a call that was refused. Every
-- caller already goes through RunOutOfCombatOnce; this guard is here so a
-- future one cannot slip past it silently.
local function applyHitbox()
    if not M.active or InCombatLockdown() then return end
    local db = M.db
    if not NP.oldSize then
        local ok, ow, oh = pcall(C_NamePlate.GetNamePlateSize)
        if ok and ns.Num(ow) and ns.Num(oh) then NP.oldSize = { ow, oh } end
    end
    local w = db.healthBarWidth * db.hitboxScaleX / 100
    local h = db.healthBarHeight * db.hitboxScaleY / 100
    pcall(C_NamePlate.SetNamePlateSize, w, h)
    local mgr = C_NamePlateManager
    if mgr and mgr.SetNamePlateHitTestInsets and Enum.NamePlateType then
        local enemy = Enum.NamePlateType.Enemy
        if not NP.oldInsets then
            local ok, l, r, t, b = pcall(mgr.GetNamePlateHitTestInsets, enemy)
            if ok and ns.Num(l) then NP.oldInsets = { l, r, t, b } end
        end
        pcall(mgr.SetNamePlateHitTestInsets, enemy, -10000, -10000, -10000, -10000)
    end
end

-- Switching the module off: insets and plate size as found. The driver is NOT
-- asked to push its size again -- that function writes Blizzard's shared option
-- tables, and written from here they would be tainted for every plate after.
local function restoreHitbox()
    if InCombatLockdown() then return end     -- protected, see applyHitbox
    local old = NP.oldInsets
    if old then
        pcall(C_NamePlateManager.SetNamePlateHitTestInsets, Enum.NamePlateType.Enemy,
            old[1], old[2], old[3], old[4])
    end
    local size = NP.oldSize
    if size then pcall(C_NamePlate.SetNamePlateSize, size[1], size[2]) end
end

function NP.ApplyHitbox()
    if not M.active then return end
    ns:RunOutOfCombatOnce("np-hitbox", applyHitbox)
end

-- "Hide enemy nameplates out of combat": the same CVar the client's own
-- show-enemy-plates key binding flips, so writing it at the combat edges is
-- allowed. Read before write -- an unchanged write still fires CVAR_UPDATE.
function showEnemies(inCombat)
    if not M.db.hideEnemyPlatesOOC then return end
    local want = inCombat and "1" or "0"
    if getCVar("nameplateShowEnemies") ~= want then pcall(C_CVar.SetCVar, "nameplateShowEnemies", want) end
end

-- Leaving the option: enemy plates come back for good.
function NP.ApplyShowEnemies()
    if M.db.hideEnemyPlatesOOC then
        showEnemies(InCombatLockdown())
    elseif getCVar("nameplateShowEnemies") ~= "1" then
        pcall(C_CVar.SetCVar, "nameplateShowEnemies", "1")
    end
end

-- ---------------------------------------------------------------------------
-- Enable / disable
-- ---------------------------------------------------------------------------
local hooksInstalled

function M:OnEnable()
    if not hooksInstalled then
        hooksInstalled = true
        NP.InstallDriverHook()
        -- The driver pushes its own plate size whenever its options change.
        if NamePlateDriverFrame and NamePlateDriverFrame.UpdateNamePlateOptions then
            hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", NP.ApplyHitbox)
        end
    end

    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) attach(unit) end)
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) detach(unit) end)
    self:RegisterEvent("UNIT_FLAGS", recheck)
    self:RegisterEvent("UNIT_FACTION", recheck)
    self:RegisterEvent("DISPLAY_SIZE_CHANGED", NP.ApplyHitbox)
    self:RegisterEvent("UI_SCALE_CHANGED", NP.ApplyHitbox)

    self:RegisterEvent("PLAYER_TARGET_CHANGED", NP.Target.OnTargetChanged)
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", NP.Target.OnFocusChanged)
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", NP.Target.OnMouseover)
    self:RegisterEvent("RAID_TARGET_UPDATE", function()
        for _, plate in pairs(NP.plates) do plate:UpdateRaidMarker() end
    end)

    -- combat edges: the out-of-combat dim, and the "only in combat" switch
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function() NP.Colors.RefreshAll(); showEnemies(true) end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() NP.Colors.RefreshAll(); showEnemies(false) end)
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
                             "ZONE_CHANGED_NEW_AREA", "PLAYER_ROLES_ASSIGNED" }) do
        self:RegisterEvent(event, NP.Colors.RefreshAll)
    end
    self:RegisterEvent("SPELLS_CHANGED", function()
        NP.Kick.Resolve()
        NP.AuraStyle.RefreshDispel()
    end)
    self:RegisterEvent("UNIT_PET", NP.Kick.Resolve)

    NP.Colors.RefreshContext()
    NP.Kick.Resolve()
    NP.AuraStyle.RefreshDispel()
    NP.Auras.ApplyCVars()
    NP.Target.OnTargetChanged()
    showEnemies(InCombatLockdown())

    NP.ApplyCVars()
    NP.ApplyHitbox()

    -- Plates that were up before we were (a /reload in a pack).
    for _, nameplate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = NP.UnitOf(nameplate)
        if unit then attach(unit) end
    end

    C_Timer.After(2, function() if M.active then prewarm() end end)
end

function M:OnDisable()
    local units = {}
    for unit in pairs(NP.plates) do units[#units + 1] = unit end
    for _, unit in ipairs(units) do detach(unit) end
    wipe(NP.pending)
    ns:RunOutOfCombatOnce("np-cvars-off", restoreCVars)
    ns:RunOutOfCombatOnce("np-hitbox-off", restoreHitbox)
end
