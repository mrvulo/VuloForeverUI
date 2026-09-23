-- VuloForeverUI / Modules / UnitFrames / Engine
--
-- One engine for both own skins. It creates a secure unit button per unit,
-- paints it through setters that accept secret values, and silences
-- Blizzard frame while an own skin is active. The skins (UnitFramesSkins)
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
local wireEvents

UF.Frames = UF.Frames or {}

-- The four font strings a skin may hand a unit value to. Which value each one
-- carries is the skin's business (UnitFramesSkins, `content`); the painters
-- below only ask "does any slot want a name / health / power right now".
UF.TEXT_SLOTS = { "Name", "HealthText", "HealthPct", "PowerText" }

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
    -- the dark ground behind a bar; the bar own texture draws over it
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    return bar
end

local function newText(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    ns.UI.Font(fs, 11, "OUTLINE")
    -- A slot has a fixed width so the columns line up; a long name has to be
    -- cut off at that width, not wrapped onto a second line the bar has no
    -- room for.
    fs:SetWordWrap(false)
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

    wireEvents(f)
    UF.Frames[unit] = f
    return f
end

function UF.SetSkin(frame, skinName, opts)
    local skin = UF.Skins[skinName]
    if not skin then return end
    -- A registry entry may be a BUILDER: Modern turns the unit's settings into
    -- the same table shape the constant Classic skin has.
    if skin.build then skin = skin.build(opts and opts.cfg) end
    frame.skin, frame.skinOpts = skin, opts
    UF.ApplySkin(frame, skin, opts)
    -- the mover box should match the new size; ApplyMover re-reads it
    frame.mover.opts.width, frame.mover.opts.height = skin.width, skin.height
    ns:RefreshMoverGeometry(frame.mover)
    ns:ApplyMover(frame.mover)
end

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
    -- CanRead FIRST: `not token` is a boolean test, and a boolean test on a
    -- secret throws before any gate behind it gets a say. CanRead is safe on
    -- nil (nothing secret about it) and answers true, so the type check below
    -- is what rejects a missing token.
    if not ns.CanRead(token) then return nil end
    if type(token) ~= "string" then return nil end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
    if not c then return nil end
    return c.r, c.g, c.b
end

-- The colour a text slot wears. Class colour is per slot; a slot that does not
-- ask for it is plain white, whatever it says.
local function textColor(f, fs)
    if not fs.vfClassColor then
        fs:SetTextColor(1, 1, 1)
        return
    end
    local r, g, b = UF.ClassColor(f.unit)
    if r then
        fs:SetTextColor(r, g, b)
        return
    end
    if not UnitIsPlayer(f.unit) then
        -- Same order as ClassColor: the gate goes before the test, and before
        -- the reaction is used as a table key.
        local reaction = UnitReaction(f.unit, "player")
        if ns.CanRead(reaction) and type(reaction) == "number" and FACTION_BAR_COLORS then
            local col = FACTION_BAR_COLORS[reaction]
            if col then
                fs:SetTextColor(col.r, col.g, col.b)
                return
            end
        end
    end
    fs:SetTextColor(1, 1, 1)
end

-- No closures in the painters below: UNIT_HEALTH and UNIT_POWER_UPDATE are the
-- two hottest events in the game, and a per-event closure is garbage the frame
-- pays for forever.
local SLOTS = UF.TEXT_SLOTS

local function healthColor(f)
    local skin = f.skin
    if not skin then return end
    if not skin.flat then
        -- Classic: Blizzard's green, class colour is what the name carries
        f.Health:SetStatusBarColor(0, 1, 0)
        return
    end
    if skin.healthClassColor == false then
        local c = skin.healthColor
        f.Health:SetStatusBarColor(c.r, c.g, c.b)
        return
    end
    local r, g, b = UF.ClassColor(f.unit)
    if r then
        f.Health:SetStatusBarColor(r, g, b)
        return
    end
    -- No boolean test and no field lookup on the returned colour: it comes out
    -- of a secret evaluation, and both would throw. Ask it for its channels
    -- inside the pcall, exactly as the nameplate execute glow does.
    local unit = f.unit
    local ok, r, g, b = pcall(function()
        return UnitHealthPercent(unit, true, getHealthCurve()):GetRGB()
    end)
    if ok then f.Health:SetStatusBarColor(r, g, b) end
end

local function paintHealth(f)
    local unit = f.unit
    ns:SetHealthFill(f.Health, unit)
    local content = f.content
    if not content then return end

    local state
    if not UnitIsConnected(unit) then
        state = L["Offline"]
    elseif UnitIsDeadOrGhost(unit) then
        state = UnitIsGhost(unit) and L["Ghost"] or L["Dead"]
    end
    if state then
        f.Health:SetStatusBarColor(0.5, 0.5, 0.5)
    else
        healthColor(f)
    end

    for i = 1, #SLOTS do
        local key = SLOTS[i]
        local c = content[key]
        if c == "curhp" or c == "perhp" or c == "hpboth" then
            local fs = f[key]
            if state then
                -- the word goes in the first health slot; the rest clear
                fs:SetText(state)
                state = ""
            elseif c == "curhp" then
                -- the argument may be secret; the widget takes it as it is
                fs:SetFormattedText("%s", AbbreviateNumbers(UnitHealth(unit)))
            elseif c == "perhp" then
                fs:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
            else
                fs:SetFormattedText("%s  %d%%", AbbreviateNumbers(UnitHealth(unit)),
                    UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))
            end
            textColor(f, fs)
        end
    end
end

local POWER_FALLBACK = { r = 0, g = 0, b = 1 }   -- mana
local function paintPower(f)
    local unit = f.unit
    ns:SetPowerFill(f.Power, unit)
    local skin = f.skin
    if skin and skin.flat and skin.powerTypeColor == false then
        local c = skin.powerColor
        f.Power:SetStatusBarColor(c.r, c.g, c.b)
    else
        local ptype, ptoken = UnitPowerType(unit)
        local info
        if ptoken and ns.CanRead(ptoken) then info = PowerBarColor[ptoken] end
        if not info and ptype and ns.CanRead(ptype) then info = PowerBarColor[ptype] end
        info = info or POWER_FALLBACK
        f.Power:SetStatusBarColor(info.r, info.g, info.b)
    end

    local content = f.content
    if not content then return end
    local blank = UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit)
    for i = 1, #SLOTS do
        local key = SLOTS[i]
        local c = content[key]
        if c == "curpp" or c == "ppboth" then
            local fs = f[key]
            if blank then
                fs:SetText("")
            elseif c == "curpp" then
                fs:SetFormattedText("%s", AbbreviateNumbers(UnitPower(unit)))
            else
                -- no percent: dividing a secret current by a secret max is the
                -- arithmetic that throws, and power has no percent API
                fs:SetFormattedText("%s/%s", AbbreviateNumbers(UnitPower(unit)),
                    AbbreviateNumbers(UnitPowerMax(unit)))
            end
            textColor(f, fs)
        end
    end
end

local function paintName(f)
    local content = f.content
    if not content then return end
    for i = 1, #SLOTS do
        local key = SLOTS[i]
        if content[key] == "name" then
            local fs = f[key]
            fs:SetText(UnitName(f.unit))    -- may be secret; SetText accepts it
            textColor(f, fs)
        end
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
    local status
    if mobUnit then status = UnitThreatSituation(unit, mobUnit) else status = UnitThreatSituation(unit) end
    if type(status) == "nil" or not ns.CanRead(status) then
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
    -- CanRead before anything else: `token and ...` is a boolean test, and on a
    -- secret token that throws before the gate behind it is ever reached.
    local coords = ns.CanRead(token) and token and UnitIsPlayer(f.unit)
        and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
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

wireEvents = function(f)
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

-- pcall around every UnregisterAllEvents: frames that Blizzard loads into the
-- secure environment (the target frame's aura container, TargetFrame.xml:338)
-- refuse event changes from tainted code with "forbidden aspect
-- 'EventRegistrations'" (seen 2026-09-18). They stay registered but hidden
-- with their parent, which is all the silencing needs from them.
local function unregisterTree(frame, skip)
    if not frame or frame == skip then return end
    if frame.UnregisterAllEvents then pcall(frame.UnregisterAllEvents, frame) end
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
    if mod.db.style ~= "modern" then return end
    for _, unit in ipairs({ "player", "target" }) do
        local f = UF.CreateUnitFrame(unit, mod.db[unit], LABELS[unit])
        UF.SetSkin(f, "modern", { unit = unit, cfg = mod.db[unit].modern })
        RegisterUnitWatch(f)
        UF.SetEventsEnabled(f, true)
        UF.SilenceBlizzard(unit)
    end
end

-- A setting changed: rebuild that unit's skin from db and repaint. SetSkin
-- calls SetSize on a secure unit button, which the client refuses in combat,
-- so a change made mid-fight lands when the fight ends.
local refreshPending = {}

function UF.RefreshModern(mod, unit)
    if mod.db.style ~= "modern" then return end
    local f = UF.Frames[unit]
    if not f then return end
    if ns:InCombat() then
        if not refreshPending[unit] then
            refreshPending[unit] = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                refreshPending[unit] = nil
                UF.RefreshModern(mod, unit)
            end)
        end
        return
    end
    UF.SetSkin(f, "modern", { unit = unit, cfg = mod.db[unit].modern })
    UF.Paint(f)
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
