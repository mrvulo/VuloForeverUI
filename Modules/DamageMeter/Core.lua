-- VuloForeverUI / Modules / DamageMeter / Core
--
-- Damage meter windows on C_DamageMeter, the client's own combat bookkeeping.
-- There is no combat log for addons on this client, so everything shown here
-- is what the client aggregates itself: sources, spells, sessions. The data
-- arrives pre-sorted and, in combat, as SECRET VALUES -- names, totals, per
-- second and GUIDs may not be compared, computed with or used as keys. Every
-- number goes straight from the API into a widget: SetMinMaxValues/SetValue
-- for the bar fill, AbbreviateNumbers plus SetText for the amount, SetText
-- for the name. The few things that must be decided (own row, class colour,
-- icon) hang on fields the API documents as NeverSecret: isLocalPlayer,
-- classFilename, specIconID, deathRecapID.
--
-- This file: registration, defaults, the shared helpers, combat state, the
-- one shared ticker, keybinds and the hotkey toggle. The window itself is in
-- Window.lua, the breakdown views in Breakdown.lua, the standalone timer in
-- Timer.lua, the cast history in SpellHistory.lua, the options in Options.lua.
local _, ns = ...
local L = ns.L

local DM = {}
ns.DM = DM

DM.MAX_WINDOWS   = 5
DM.MIN_W, DM.MIN_H = 150, 50
DM.BAR_POOL      = 40
DM.TICK_FLOOR    = 0.5      -- refresh rate floor; each tick fetches a full session per window
DM.TICK_HARD     = 0.2      -- absolute floor, the "unsafe" slider's minimum
DM.ICON_ALPHA    = 0.4
DM.ICON_HOVER    = 0.9
DM.SNAP          = 6

DM.WHITE = "Interface\\Buttons\\WHITE8X8"
DM.ICON  = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\"

local mod = ns:RegisterModule("damagemeter", {
    name        = "Damage Meter",
    group       = "HUD",
    description = "Damage, healing, interrupts, dispels and deaths from the client's own combat data, in up to five windows with breakdowns per player.",
    defaults = {
        enabled = true,
        visibility        = "always",       -- always | mouseover | combat | noncombat | hidden
        refreshRate       = 1,
        unsafeRefreshRate = false,
        hideResetButton   = false,
        resetKey          = "",
        toggleKey         = "",
        toggleIncludeTimer        = false,
        toggleIncludeSpellHistory = false,
        disableBlizzardMeter      = true,   -- the stock meter is switched off while this runs

        -- "classic" is the 1.x box (Classic.lua), the default; "modern" the flat look
        style = "classic",

        -- window
        bgColor = { r = 0, g = 0, b = 0 }, bgAlpha = 0.75,
        windowBorderTexture = "solid", windowBorderSize = 0,
        windowBorderColor = { r = 0, g = 0, b = 0 }, windowBorderAlpha = 1,
        windowBorderOffsetX = 0, windowBorderOffsetY = 0,
        windowBorderIncludeHeader = true, windowBorderBehind = false,
        showPinnedSelf = false,

        -- header
        hdrHeight = 22, hdrFontSize = 11, hdrIconSize = 22,
        hdrTextOffX = 0, hdrTextOffY = 0,
        hdrBgColor = { r = 0.106, g = 0.106, b = 0.106 }, hdrBgAlpha = 1,
        hdrTextUseAccent = true, hdrTextColor = { r = 1, g = 1, b = 1 },
        hdrBottomBorderSize = 0, hdrBottomBorderColor = { r = 0, g = 0, b = 0 }, hdrBottomBorderAlpha = 1,
        hdrMouseoverIcons = false,
        iconColorUseAccent = false, iconColor = { r = 1, g = 1, b = 1 },

        -- bars
        barTexture = "Atrocity", barHeight = 18, barSpacing = 2, barFillAlpha = 1,
        showClassColor = true, barColorUseAccent = true, barColor = { r = 0.35, g = 0.55, b = 0.8 },
        barBgColor = { r = 0, g = 0, b = 0 }, barBgAlpha = 0, barBgUseClassColor = false,
        iconStyle = "spec", classIconZoom = 0.06,
        borderTexture = "solid", borderSize = 0, borderColor = { r = 0, g = 0, b = 0 }, borderAlpha = 1,
        borderFollowFill = false, borderFollowFillIcon = false,
        customIconBorder = false, iconBorderSize = 0, iconBorderColor = { r = 0, g = 0, b = 0 }, iconBorderAlpha = 1,

        -- text
        numberFormat = 2,           -- 0 per second | 1 total | 2 total (per second) | 3 total | per second
        hideNumbers  = false,
        leftFontSize = 11, rightFontSize = 11,
        leftTextUseClassColor = false, rightTextUseClassColor = false,
        leftTextColor = { r = 1, g = 1, b = 1 }, rightTextColor = { r = 1, g = 1, b = 1 },
        leftTextOffsetX = 0, leftTextOffsetY = 0, rightTextOffsetX = 0, rightTextOffsetY = 0,

        -- breakdown
        showHoverTooltip = true, showSpellTooltips = true,
        breakdownAnchorPoint = "row",   -- row | center | left | right
        breakdownBarTexture = "match", hoverTooltipScale = 100, showAllBreakdownSpells = true,

        -- standalone combat timer
        timer = {
            enabled = false, size = 26, decimal = false, useAccent = false,
            color = { r = 1, g = 1, b = 1 }, anchor = "free", strata = "HIGH",
            showOOC = false, desatOOC = false, locked = false, alignLeft = false,
            outline = "INHERIT", pos = false,
        },

        -- threat meter (Threat.lua)
        threat = {
            enabled = false, visibility = "always",
            width = 220, barHeight = 18, spacing = 1, maxBars = 10,
            growUp = false, showHeader = true, ignorePets = false,
            texture = "", barOpacity = 100, bgAlpha = 0.6,
            borderSize = 1, borderColor = { r = 0, g = 0, b = 0 },
            textSize = 12, outline = "INHERIT",
            showValue = true, showPercent = true,
            playerColorOn = false, playerColor = { r = 0.8, g = 0.1, b = 0.1 },
            tankColorOn = false, tankColor = { r = 0.1, g = 0.6, b = 0.1 },
            pullBar = true, pullColor = { r = 0.0, g = 0.55, b = 0.0 },
            warnSound = false, warnSoundKey = "None", warnAt = 80, warnSkipTank = true,
            mover = { x = 400, y = -100 },
        },

        -- cast history
        spellHistory = {
            iconEnabled = false, growDirection = "LEFT", iconSize = 36, iconZoom = 0.08,
            iconCount = 5, iconSpacing = 1, iconOpacity = 1, iconAnimation = "slide", iconFadeTime = 0,
            iconHideInDungeon = false, iconHideInRaid = false, iconHideInPvP = false, iconHideOutOfInstance = false,
            iconPos = false,
            barEnabled = false, bgColor = { r = 0, g = 0, b = 0 }, bgAlpha = 0.25, hideTopBar = false,
            barHeight = 18, maxBars = 5, barTexture = "match", barWidth = 300, barLocked = false, barPos = false,
            textSize = 11, textColor = { r = 1, g = 1, b = 1 }, textColorUseAccent = false,
            barColorUseClass = false, barColorUseAccent = false, barColor = { r = 0.298, g = 0.565, b = 0.494 },
            barOpacity = 1,
            barHideInDungeon = false, barHideInRaid = false, barHideInPvP = false, barHideOutOfInstance = false,
        },

        -- per window: { width, height, pos, locked, snapDisabled, hideTimer, dmType, session,
        --               hideInDungeon, hideInRaid, hideInPvP, hideOutOfInstance,
        --               autoCurrentOnCombat, syncSegments }
        windowCount = 1,
        windows     = {},
        bookmarks   = false,    -- seeded on first use, see DM.Bookmarks()
    },
})
DM.mod = mod

function DM.db() return mod.db end

-- ---------------------------------------------------------------- types --

-- Enum values read once; a missing member (a client without the meter at all)
-- leaves the table short instead of throwing at load.
local E = Enum.DamageMeterType or {}
local ES = Enum.DamageMeterSessionType or {}

DM.T = {
    DamageDone = E.DamageDone, HealingDone = E.HealingDone, DamageTaken = E.DamageTaken,
    AvoidableDamageTaken = E.AvoidableDamageTaken, EnemyDamageTaken = E.EnemyDamageTaken,
    Interrupts = E.Interrupts, Dispels = E.Dispels, Deaths = E.Deaths,
}
DM.S = { Current = ES.Current, Overall = ES.Overall }

-- Order for the home tiles and the "add" menu.
DM.TYPE_ORDER = {
    E.DamageDone, E.HealingDone, E.DamageTaken, E.AvoidableDamageTaken,
    E.EnemyDamageTaken, E.Interrupts, E.Dispels, E.Deaths,
}

DM.HOME_DEFAULTS = { E.DamageDone, E.HealingDone, E.Interrupts, E.Deaths }

-- The client's own (localised) names where it has them; English otherwise.
local TYPE_FALLBACK = {
    [E.DamageDone or -1]           = { "DAMAGE_METER_TYPE_DAMAGE_DONE",  "Damage Done" },
    [E.HealingDone or -2]          = { "DAMAGE_METER_TYPE_HEALING_DONE", "Healing Done" },
    [E.DamageTaken or -3]          = { "DAMAGE_METER_TYPE_DAMAGE_TAKEN", "Damage Taken" },
    [E.AvoidableDamageTaken or -4] = { "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN", "Avoidable Damage Taken" },
    [E.EnemyDamageTaken or -5]     = { "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN", "Enemy Damage Taken" },
    [E.Interrupts or -6]           = { "DAMAGE_METER_TYPE_INTERRUPTS",   "Interrupts" },
    [E.Dispels or -7]              = { "DAMAGE_METER_TYPE_DISPELS",      "Dispels" },
    [E.Deaths or -8]               = { "DAMAGE_METER_TYPE_DEATHS",       "Deaths" },
}

function DM.TypeName(t)
    local e = TYPE_FALLBACK[t]
    if not e then return "?" end
    local g = _G[e[1]]
    if type(g) == "string" and g ~= "" then return g end
    return L[e[2]]
end

-- Classic-era icon files, present on this client's art.
DM.TYPE_ICONS = {
    [E.DamageDone or -1]           = "Interface\\Icons\\INV_Sword_04",
    [E.HealingDone or -2]          = "Interface\\Icons\\Spell_Holy_Heal",
    [E.DamageTaken or -3]          = "Interface\\Icons\\Ability_Warrior_ShieldWall",
    [E.AvoidableDamageTaken or -4] = "Interface\\Icons\\Spell_Fire_SelfDestruct",
    [E.EnemyDamageTaken or -5]     = "Interface\\Icons\\Ability_Warrior_Challange",
    [E.Interrupts or -6]           = "Interface\\Icons\\Ability_Kick",
    [E.Dispels or -7]              = "Interface\\Icons\\Spell_Holy_DispelMagic",
    [E.Deaths or -8]               = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
}

function DM.SessionName(s)
    if s == ES.Overall then return _G.DAMAGE_METER_OVERALL_SESSION or L["Overall"] end
    return _G.DAMAGE_METER_CURRENT_SESSION or L["Current"]
end

function DM.IsCount(t)  return t == E.Interrupts or t == E.Dispels end
function DM.IsDeaths(t) return t == E.Deaths end

-- ---------------------------------------------------------------- secrets --

local IsSecret = ns.IsSecret
DM.IsSecret = IsSecret

-- "Is there a plain value" without a boolean test on a possible secret.
local function plain(v)
    return type(v) ~= "nil" and not IsSecret(v)
end
DM.Plain = plain

-- ---------------------------------------------------------------- numbers --

local Abbrev = _G.AbbreviateNumbers

local function abbrevOwn(num)
    if num >= 1e9 then return format("%.1fB", num / 1e9) end
    if num >= 1e6 then return format("%.1fM", num / 1e6) end
    if num >= 1e3 then return format("%.1fK", num / 1e3) end
    return format("%.0f", num)
end

-- How the client is told to write a number. This is the ONLY way to round a
-- per-second value in combat: the value is secret there, so Lua may not look
-- at it, let alone divide it -- but the engine may, and this config is what
-- tells it to. Without it AbbreviateNumbers passes anything below a thousand
-- straight through and a bar reads "94 (8.5454545454545)".
--
-- Per band: a value at or above `breakpoint` is divided by
-- significandDivisor, and fractionDivisor decides how much of the remainder
-- survives -- 1 means none, so the last band prints whole numbers.
local ABBREV_BANDS = {
    { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
    { breakpoint = 1000,       abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
    { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
}

local abbrevCfg   -- nil = not built yet, false = this client has no config API

local function abbrevConfig()
    if abbrevCfg ~= nil then return abbrevCfg end
    abbrevCfg = false
    if _G.CreateAbbreviateConfig and Abbrev then
        local ok, cfg = pcall(_G.CreateAbbreviateConfig, ABBREV_BANDS)
        if ok and cfg then
            -- Proven once on a plain number before any bar depends on it: the
            -- band fields are not in the client's API documentation, and a
            -- wrong one would otherwise throw on every row of every tick.
            local fine, out = pcall(Abbrev, 1234, { config = cfg })
            if fine and type(out) == "string" then abbrevCfg = { config = cfg } end
        end
    end
    return abbrevCfg
end

-- Secret-safe: a secret goes into the client's abbreviator and comes back as a
-- secret string, which the font string takes as it is.
--
-- NOTE the result is never truth-tested. `Abbrev(n) or "0"` reads as harmless
-- and is not: `or` is a boolean test, and a boolean test on a secret throws.
-- type() is the one question a secret answers.
-- One path for both kinds of number. The engine does the formatting, which is
-- what makes the in-combat value read the same as the one out of combat: a
-- secret cannot be rounded in Lua, only handed over with instructions.
function DM.Abbrev(n)
    if type(n) == "nil" then return "0" end
    if Abbrev then
        local cfg = abbrevConfig()
        local s
        if cfg then s = Abbrev(n, cfg) else s = Abbrev(n) end
        if type(s) ~= "nil" then return s end
    end
    -- No abbreviator on this client: a readable number is formatted here, a
    -- secret goes to the font string as it is, which is all we may do with it.
    if type(n) == "number" and not IsSecret(n) then return abbrevOwn(n) end
    if IsSecret(n) then return n end
    local num = tonumber(n)
    if not num then return "?" end
    return abbrevOwn(num)
end

-- The value column. 0: per second, 1: total, 2: total (per second), 3: total | per second.
function DM.FormatValue(amount, perSec, fmt)
    -- Per-second can drop below 1 on a long Overall view and would print a raw
    -- float; clamped for a plain number only, a secret is never compared.
    if plain(perSec) and type(perSec) == "number" and perSec < 1 then perSec = 1 end
    local hasPs = type(perSec) ~= "nil"
    -- `hasPs and perSec or 0` would truth-test perSec, which throws on a
    -- secret. Abbrev already answers nil with "0".
    if fmt == 0 then
        if hasPs then return DM.Abbrev(perSec) end
        return DM.Abbrev(0)
    end
    if fmt == 2 and hasPs then return format("%s (%s)", DM.Abbrev(amount), DM.Abbrev(perSec)) end
    if fmt == 3 and hasPs then return format("%s | %s", DM.Abbrev(amount), DM.Abbrev(perSec)) end
    return DM.Abbrev(amount)
end

function DM.FormatTimer(seconds)
    if type(seconds) ~= "number" or IsSecret(seconds) then return "0:00" end
    return format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

function DM.FormatTimerDecimal(seconds)
    if type(seconds) ~= "number" or IsSecret(seconds) then return "0:00.0" end
    return format("%d:%02d.%d", math.floor(seconds / 60), math.floor(seconds % 60), math.floor((seconds * 10) % 10))
end

-- Realm stripped. Ambiguate takes a secret and hands one back.
function DM.StripRealm(name)
    if type(name) == "nil" then return L["Unknown"] end
    if IsSecret(name) then return name end
    if name == "" then return L["Unknown"] end
    return Ambiguate(name, "short") or name
end

-- ---------------------------------------------------------------- colours --

function DM.Accent()
    local c = ns.COLORS.accent
    return c.r, c.g, c.b
end

-- The colour table itself, for a caller that wants r/g/b as fields.
function DM.ClassColorTable(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    return (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[classFile]
end

function DM.ClassColor(classFile)
    if type(classFile) ~= "string" or classFile == "" then return nil end
    local c = RAID_CLASS_COLORS[classFile]
    if not c then return nil end
    return c.r, c.g, c.b
end

-- Own row: isLocalPlayer is documented NeverSecret; a wrong doc degrades to
-- "not own", never to a thrown comparison.
function DM.IsOwnRow(src)
    local own = src and src.isLocalPlayer
    if type(own) ~= "boolean" or IsSecret(own) then return false end
    return own
end

-- ---------------------------------------------------------------- media --

function DM.BarTexture(name)
    return ns.MediaStatusbar(name, DM.WHITE)
end

-- "match" follows the meter's own texture.
function DM.BreakdownTexture()
    local db = DM.db()
    local n = db.breakdownBarTexture
    if n == "match" or not n then n = db.barTexture end
    return DM.BarTexture(n)
end

function DM.Font(fs, size, flags)
    return ns.UI.FontFor("damagemeter", fs, size, flags)
end

-- ---------------------------------------------------------------- sessions --

-- What the client tracks right now: the last twenty, newest last.
function DM.RecentSessions()
    local list = C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetAvailableCombatSessions()
    local out = {}
    if type(list) ~= "table" then return out end
    local start = math.max(1, #list - 19)
    for i = start, #list do
        local s = list[i]
        local name = s.name
        if not plain(name) or name == "" then name = L["Combat"] end
        out[#out + 1] = { sessionID = s.sessionID, name = name, duration = s.durationSeconds }
    end
    return out
end

function DM.SessionDurationByID(sessionID)
    local list = C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetAvailableCombatSessions()
    if type(list) ~= "table" then return nil end
    for i = 1, #list do
        local s = list[i]
        if s.sessionID == sessionID and plain(s.durationSeconds) then return s.durationSeconds end
    end
    return nil
end

function DM.FetchSession(W)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionFromType) then return nil end
    local ok, session
    if W.sessionID then
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, W.sessionID, W.dmType)
    else
        ok, session = pcall(C_DamageMeter.GetCombatSessionFromType, W.session, W.dmType)
    end
    if ok and type(session) == "table" then return session end
    return nil
end

function DM.FetchSource(W, guid, creatureID)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
    local ok, src
    if W.sessionID then
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, W.sessionID, W.dmType, guid, creatureID)
    else
        ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, W.session, W.dmType, guid, creatureID)
    end
    if ok and type(src) == "table" then return src end
    return nil
end

-- ---------------------------------------------------------------- combat state --

DM.inCombat     = false
DM.combatStart  = 0       -- GetTime() at PLAYER_REGEN_DISABLED, the fallback clock
DM.frozenDur    = 0       -- last fight's length once the group is out
DM.needsFinal   = false   -- player left combat, the group is still in it

local function playerInCombat()
    local v = UnitAffectingCombat("player")
    if not ns.CanRead(v) then return DM.inCombat end
    return v and true or false
end

local function groupInCombat()
    local prefix, n = nil, 0
    if IsInRaid() then prefix, n = "raid", GetNumGroupMembers()
    elseif IsInGroup() then prefix, n = "party", GetNumGroupMembers() - 1 end
    if not prefix then return false end
    for i = 1, n do
        local u = prefix .. i
        if UnitExists(u) then
            local v = UnitAffectingCombat(u)
            if ns.CanRead(v) and v then return true end
        end
    end
    return false
end
DM.GroupInCombat = groupInCombat

-- The duration the bars are rendering: live while fighting, the pinned value
-- afterwards, the session's own length for a past segment.
function DM.ViewDuration(W)
    if W.sessionID then
        return DM.SessionDurationByID(W.sessionID) or 0
    end
    if DM.inCombat or DM.needsFinal then
        local d = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds and C_DamageMeter.GetSessionDurationSeconds(W.session)
        if plain(d) and type(d) == "number" then return d end
        return GetTime() - DM.combatStart
    end
    return DM.frozenDur
end

local function freeze()
    DM.inCombat, DM.needsFinal = false, false
    local d = C_DamageMeter and C_DamageMeter.GetSessionDurationSeconds and C_DamageMeter.GetSessionDurationSeconds(DM.S.Current)
    if plain(d) and type(d) == "number" and d >= (DM.frozenDur or 0) then
        DM.frozenDur = d
    elseif DM.combatStart > 0 then
        DM.frozenDur = GetTime() - DM.combatStart
    end
end

-- ---------------------------------------------------------------- windows --

DM.windows = {}

function DM.ForEach(fn, ...)
    for i = 1, #DM.windows do
        local W = DM.windows[i]
        if W then fn(W, ...) end
    end
end

function DM.RefreshAll()
    DM.ForEach(function(W) W.Refresh() end)
end

function DM.RestyleAll()
    DM.ForEach(function(W) W.Restyle() end)
    if DM.Timer and DM.Timer.Apply then DM.Timer.Apply() end
    if DM.SpellHistory and DM.SpellHistory.Apply then DM.SpellHistory.Apply() end
    if DM.Threat and DM.Threat.ApplyStyle then DM.Threat.ApplyStyle() end
end

function DM.UpdateVisibilityAll()
    DM.ForEach(function(W) W.UpdateVisibility() end)
    if DM.Timer and DM.Timer.UpdateVisibility then DM.Timer.UpdateVisibility() end
    if DM.SpellHistory and DM.SpellHistory.UpdateVisibility then DM.SpellHistory.UpdateVisibility() end
end

-- Per-window settings, created on demand so an old profile grows the table.
function DM.WinDB(idx)
    local db = DM.db()
    db.windows = db.windows or {}
    local w = db.windows[idx]
    if not w then
        w = { width = 375, height = 150 }
        db.windows[idx] = w
    end
    if not w.width  then w.width  = 375 end
    if not w.height then w.height = 150 end
    return w
end

-- Home tiles, shared by every window.
function DM.Bookmarks()
    local db = DM.db()
    if type(db.bookmarks) ~= "table" then
        db.bookmarks = {}
        for i, t in ipairs(DM.HOME_DEFAULTS) do db.bookmarks[i] = t end
    end
    return db.bookmarks
end

-- Segment selection funnel: a synced window drags the others along.
function DM.ApplySegment(W, sessionType, sessionID)
    local function apply(win)
        win.session   = sessionType or win.session
        win.sessionID = sessionID
        if sessionType then win.wdb.session = sessionType end
        win.CloseSource()
        win.Refresh()
    end
    apply(W)
    if W.wdb.syncSegments then
        DM.ForEach(function(o)
            if o ~= W and o.wdb.syncSegments then apply(o) end
        end)
    end
end

-- Entering combat brings a window that looks at a past segment back to the
-- live one, when the window asked for that.
local function autoCurrentOnCombat()
    DM.ForEach(function(W)
        if W.wdb.autoCurrentOnCombat and W.sessionID then
            W.sessionID = nil
            W.session = DM.S.Current
            W.wdb.session = DM.S.Current
            W.CloseSource()
        end
    end)
end

-- ---------------------------------------------------------------- ticker --

-- One ticker for every window, running only in combat. Out of combat the
-- repaints are event driven.
local ticker, timerTicker
local combatGen = 0

local function tickRate()
    local db = DM.db()
    local floor = db.unsafeRefreshRate and DM.TICK_HARD or DM.TICK_FLOOR
    local r = tonumber(db.refreshRate) or 1
    if r < floor then r = floor end
    return r
end

local function stopTicker()
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if timerTicker then ns:CancelTicker(timerTicker); timerTicker = nil end
end

-- One place for "the fight is over", because three paths reach it and each
-- one used to do a slightly different subset. It pins the duration, credits
-- the cast history with the time it spent in combat (its fade clock pauses
-- there) and lets the timer re-decide whether it is shown at all -- the last
-- one is what stops the tenths ticker.
local function combatEnded()
    local fought = DM.combatStart > 0 and (GetTime() - DM.combatStart) or 0
    freeze()
    if fought > 0 and DM.SpellHistory and DM.SpellHistory.OnCombatEnd then
        DM.SpellHistory.OnCombatEnd(fought)
    end
    DM.RefreshAll()
    -- the ticker path ends here too, after the regen handler already ran
    DM.UpdateVisibilityAll()
end

local function tick()
    if DM.needsFinal then
        -- The player is out but the group still fights: keep going until it is
        -- done, with a failsafe so a stale flag cannot tick forever.
        if not groupInCombat() or (GetTime() - (DM.regenAt or 0)) > 5 then
            combatEnded()
            stopTicker()
            return
        end
    end
    DM.RefreshAll()
end

local function tickTimers()
    DM.ForEach(function(W) W.UpdateTimer() end)
    if DM.Timer and DM.Timer.Update then DM.Timer.Update() end
end

local function startTicker()
    if ticker then return end
    ticker = ns:AddTicker(tickRate(), tick, nil, "damagemeter")
    timerTicker = ns:AddTicker(0.5, tickTimers, nil, "damagemeter timer")
end
DM.StartTicker, DM.StopTicker = startTicker, stopTicker

function DM.RestartTicker()
    if not ticker then return end
    stopTicker()
    startTicker()
end

-- ---------------------------------------------------------------- reset --

function DM.ResetData()
    if C_DamageMeter and C_DamageMeter.ResetAllCombatSessions then
        C_DamageMeter.ResetAllCombatSessions()
    end
    DM.frozenDur = 0
    DM.RefreshAll()
end

-- ---------------------------------------------------------------- hotkeys --

-- Two hidden buttons carry override bindings: reset and the window toggle.
-- Override bindings are protected, so a change in combat waits for regen.
local RESET_BTN  = "VuloForeverUIMeterResetBind"
local TOGGLE_BTN = "VuloForeverUIMeterToggleBind"
local bindButtons = {}
local bindsPending = false

local function bindButton(name, onClick)
    local b = bindButtons[name]
    if b then return b end
    b = CreateFrame("Button", name, UIParent)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:Hide()
    b:SetScript("OnClick", function(_, _, down) if not down then onClick() end end)
    bindButtons[name] = b
    return b
end

DM.toggleHidden = false   -- runtime only, never saved

function DM.ApplyToggleState()
    if DM.HidePreview then DM.HidePreview() end
    DM.UpdateVisibilityAll()
end

function DM.ToggleWindows()
    DM.toggleHidden = not DM.toggleHidden
    DM.ApplyToggleState()
end

function DM.ApplyKeybinds()
    if not mod.active then return end
    if InCombatLockdown() then
        if not bindsPending then
            bindsPending = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                bindsPending = false
                DM.ApplyKeybinds()
            end)
        end
        return
    end
    local db = DM.db()
    local reset  = bindButton(RESET_BTN,  DM.ResetData)
    local toggle = bindButton(TOGGLE_BTN, DM.ToggleWindows)
    ClearOverrideBindings(reset)
    ClearOverrideBindings(toggle)
    if db.resetKey and db.resetKey ~= "" then
        SetOverrideBindingClick(reset, true, db.resetKey, RESET_BTN)
    end
    if db.toggleKey and db.toggleKey ~= "" then
        SetOverrideBindingClick(toggle, true, db.toggleKey, TOGGLE_BTN)
    end
end

-- Override bindings are protected, so a disable in combat has to queue the
-- release rather than drop it: the keys would otherwise stay live until the
-- next reload.
function DM.ClearKeybinds()
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("damagemeter_keys", DM.ClearKeybinds)
        return
    end
    for _, b in pairs(bindButtons) do ClearOverrideBindings(b) end
end

-- ---------------------------------------------------------------- stock meter --

local CVAR = "damageMeterEnabled"

local function setStockMeter(on)
    if not (C_CVar and C_CVar.SetCVar) then return end
    pcall(C_CVar.SetCVar, CVAR, on and "1" or "0")
end

-- ---------------------------------------------------------------- lifecycle --

local debounce

local function debouncedRefresh()
    if DM.inCombat then return end
    if debounce then return end
    debounce = C_Timer.NewTimer(0.1, function()
        debounce = nil
        DM.RefreshAll()
    end)
end

local function buildWindows()
    local db = DM.db()
    local n = math.max(1, math.min(DM.MAX_WINDOWS, tonumber(db.windowCount) or 1))
    db.windowCount = n
    for i = 1, n do
        if not DM.windows[i] then DM.windows[i] = DM.CreateWindow(i) end
    end
    DM.RefreshAll()
    DM.UpdateVisibilityAll()
end

function mod:OnEnable()
    if not (C_DamageMeter and Enum.DamageMeterType) then
        ns:Print(L["The client has no damage meter data on this build; the module stays idle."])
        return
    end
    if DM.db().disableBlizzardMeter then setStockMeter(false) end
    -- A profile that is on Classic without ever having switched to it -- a
    -- new one, since Classic is the default -- gets the Classic seed once.
    if DM.IsClassic() then DM.SeedClassic() end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        -- Re-derive the combat state: a reload mid-fight starts with the
        -- ticker off and the frozen duration stale.
        DM.inCombat = playerInCombat()
        if DM.inCombat then
            DM.combatStart = GetTime()
            startTicker()
        elseif groupInCombat() then
            DM.needsFinal = true
            DM.regenAt = GetTime()
            startTicker()
        else
            freeze()
        end
        C_Timer.After(0.5, function()
            DM.RefreshAll()
            DM.UpdateVisibilityAll()
        end)
    end)

    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
        combatGen = combatGen + 1
        DM.inCombat, DM.needsFinal = true, false
        DM.combatStart = GetTime()
        DM.deathStamps = {}
        autoCurrentOnCombat()
        startTicker()
        DM.UpdateVisibilityAll()
        if DM.Timer and DM.Timer.Update then DM.Timer.Update() end
    end)

    self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
        DM.inCombat = false
        DM.regenAt = GetTime()
        if groupInCombat() then
            DM.needsFinal = true     -- the ticker keeps polling until the group is out
        else
            combatEnded()
            local gen = combatGen
            C_Timer.After(0.25, function()
                if gen == combatGen and not DM.inCombat then
                    stopTicker()
                    DM.RefreshAll()
                end
            end)
        end
        DM.UpdateVisibilityAll()
    end)

    self:RegisterEvent("DAMAGE_METER_COMBAT_SESSION_UPDATED", debouncedRefresh)
    self:RegisterEvent("DAMAGE_METER_CURRENT_SESSION_UPDATED", debouncedRefresh)
    self:RegisterEvent("DAMAGE_METER_RESET", function()
        DM.frozenDur = 0
        DM.targetsCache = nil
        DM.RefreshAll()
    end)

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() DM.UpdateVisibilityAll() end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function() DM.UpdateVisibilityAll() end)

    -- LoadBindings (the settings panel's cancel, a binding-set switch) drops
    -- every override binding; put ours back, but not on our own echo.
    self:RegisterEvent("UPDATE_BINDINGS", function()
        if DM.bindEcho and (GetTime() - DM.bindEcho) < 0.5 then return end
        DM.bindEcho = GetTime()
        DM.ApplyKeybinds()
    end)

    -- A profile switch repoints mod.db, and every window closure captured the
    -- OLD per-window table. Without this the gear menu of a window would keep
    -- writing into the profile that was just left. The windows are rebuilt,
    -- the database is not.
    if not DM.profileHooked then
        DM.profileHooked = true
        hooksecurefunc(ns, "LoadProfile", function()
            if DM.IsClassic() then DM.SeedClassic() end
            if mod.active then DM.Rebuild() end
        end)
    end

    if IsLoggedIn() then
        buildWindows()
    else
        ns:RegisterEventOnce("PLAYER_LOGIN", buildWindows)
    end
    DM.ApplyKeybinds()
    if DM.Timer and DM.Timer.Apply then DM.Timer.Apply() end
    if DM.SpellHistory and DM.SpellHistory.Apply then DM.SpellHistory.Apply() end
    if DM.Threat and DM.Threat.Apply then DM.Threat.Apply() end

    ns:RegisterSlash({ key = "METER", commands = { "/vfmeter" },
        desc = "Show or hide the damage meter windows; 'reset' clears the data.",
    })
end

ns.Slash.METER = function(msg)
    msg = (msg or ""):lower()
    if msg:match("^%s*reset") then
        DM.ResetData()
        return
    end
    DM.ToggleWindows()
end

function mod:OnDisable()
    stopTicker()
    DM.ClearKeybinds()
    if DM.HidePreview then DM.HidePreview() end
    DM.ForEach(function(W) W.frame:Hide() end)
    if DM.Timer and DM.Timer.Hide then DM.Timer.Hide() end
    if DM.SpellHistory and DM.SpellHistory.Disable then DM.SpellHistory.Disable() end
    if DM.Threat and DM.Threat.Disable then DM.Threat.Disable() end
    setStockMeter(true)
end

-- Profile switch: the frames are torn down, never the database.
function DM.Rebuild()
    if not mod.active then return end
    DM.HidePreview()
    DM.ForEach(function(W)
        if W.hoverTicker then ns:CancelTicker(W.hoverTicker); W.hoverTicker = nil end
        if W.moTicker then ns:CancelTicker(W.moTicker); W.moTicker = nil end
        -- The new windows register their boxes under the same keys.
        DM.RetireMover(W.mover)
        W.frame:Hide()
        W.frame:SetParent(nil)
    end)
    wipe(DM.windows)
    DM.toggleHidden = false
    buildWindows()
    DM.ApplyKeybinds()
    if DM.Timer and DM.Timer.Apply then DM.Timer.Apply() end
    if DM.SpellHistory and DM.SpellHistory.Apply then DM.SpellHistory.Apply() end
    if DM.Threat and DM.Threat.Apply then DM.Threat.Apply() end
end
