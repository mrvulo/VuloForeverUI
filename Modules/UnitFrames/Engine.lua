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
    player       = "VuloForeverUI_PlayerFrame",
    target       = "VuloForeverUI_TargetFrame",
    focus        = "VuloForeverUI_FocusFrame",
    targettarget = "VuloForeverUI_TargetTargetFrame",
    focustarget  = "VuloForeverUI_FocusTargetFrame",
    pet          = "VuloForeverUI_PetFrame",
}
for i = 1, 5 do FRAME_NAMES["boss" .. i] = "VuloForeverUI_Boss" .. i .. "Frame" end

-- Every unit the Modern style can draw, in the order the options list them.
-- `boss` is one setting for five frames (boss1..boss5) standing in a column.
UF.UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
UF.BOSS_COUNT = 5

-- The db key a real unit reads its settings from: the five boss frames share one.
function UF.ConfigKey(unit)
    if unit:find("^boss%d") then return "boss" end
    return unit
end

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
-- Every region a skin may place, on any frame. The live preview in the options
-- builds a plain frame through the same function, so what it shows is laid out
-- by the very code that lays out the real one.
function UF.BuildRegions(f)
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
end

-- ------------------------------------------------------------ edit mode --
--
-- A unit frame is shown by its unit watch, and so is its mover, which is a
-- child of it: without a focus or a boss there would be nothing to grab. In
-- edit mode the watch is lifted and the frame stands with its own values or,
-- for a unit that is not there, full bars and the unit's name. Leaving edit
-- mode hands it back to the watch. Both are refused in a fight; edit mode
-- closes as a fight begins, and the watch comes back when it ends.
local EDIT_NAME = {
    player = "Player", target = "Target", focus = "Focus", targettarget = "Target of Target",
    focustarget = "Focus Target", pet = "Pet", boss = "Boss",
}

local function standIn(f)
    f.Health:SetMinMaxValues(0, 100)
    f.Health:SetValue(100)
    f.Power:SetMinMaxValues(0, 100)
    f.Power:SetValue(100)
    local content = f.content or {}
    for _, key in ipairs(UF.TEXT_SLOTS) do
        local c = content[key]
        if c == "name" then
            f[key]:SetText(L[EDIT_NAME[UF.ConfigKey(f.unit)]])
            f[key]:SetTextColor(1, 1, 1)
        elseif c == "perhp" then
            f[key]:SetText("100%")
        elseif c and c ~= "none" then
            f[key]:SetText("")
        end
    end
    f.Level:SetText("")
    f.ThreatText:SetText("")
    f.ThreatGlow:Hide()
end

local watchPending = {}

local function rewatch()
    for f in pairs(watchPending) do
        watchPending[f] = nil
        if f.vfActive then RegisterUnitWatch(f) end
    end
end

function UF.EditPreview(list, on)
    for _, f in ipairs(list) do
        if f.vfActive then
            if InCombatLockdown() then
                if not on then
                    watchPending[f] = true
                    ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", rewatch)
                end
            elseif on then
                UnregisterUnitWatch(f)
                f:Show()
                if UnitExists(f.unit) then UF.Paint(f) else standIn(f) end
            else
                RegisterUnitWatch(f)
                UF.Paint(f)
            end
        end
    end
end

-- parent: the boss column hands its holder in; every other frame stands on
-- UIParent with a mover of its own. A frame with a parent has no mover -- the
-- holder is what moves.
function UF.CreateUnitFrame(unit, db, label, parent)
    if UF.Frames[unit] then return UF.Frames[unit] end
    assert(not ns:InCombat(), "unit frames are created out of combat")

    local f = CreateFrame("Button", FRAME_NAMES[unit], parent or UIParent, "SecureUnitButtonTemplate")
    f.unit = unit
    f:SetSize(232, 100)                       -- placeholder; the skin sets the real size
    f:SetFrameStrata("LOW")
    f:SetFrameLevel(5)
    f:RegisterForClicks("AnyUp")
    f:SetAttribute("unit", unit)
    f:SetAttribute("*type1", "target")
    f:SetAttribute("*type2", "togglemenu")
    f:SetAttribute("toggleForVehicle", unit == "player")
    RegisterUnitWatch(f)

    UF.BuildRegions(f)

    -- Position and scale through the mover: /vedit moves it, db.x/y/scale
    -- persist per profile, ApplyMover puts it back at load.
    if not parent then
        f.mover = ns:CreateMover(f, {
            key      = "unitframe_" .. unit,
            label    = label,
            db       = db,
            width    = 232,
            height   = 100,
            scalable = true,
            editPreview = function(on) UF.EditPreview({ f }, on) end,
        })
        ns:ApplyMover(f.mover)
    end

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
    if frame.mover then
        frame.mover.opts.width, frame.mover.opts.height = skin.width, skin.height
        ns:RefreshMoverGeometry(frame.mover)
        ns:ApplyMover(frame.mover)
    end
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
    -- the suite's own book, so the class colours set in the global settings
    -- reach the unit frames too
    local c = ns.ClassColor(token)
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
        if type(pct) ~= "nil" and ns.CanRead(pct) then
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

-- The player's frame shows the player's own threat; every other frame shows
-- the player's threat ON that unit.
local function paintThreat(f)
    if f.unit == "player" then
        UF.PaintThreat(f.ThreatText, f.ThreatGlow, "player", nil)
    else
        UF.PaintThreat(f.ThreatText, f.ThreatGlow, "player", f.unit)
    end
end

local TAG_TEXT = { elite = "Elite", rareelite = "Rare Elite", rare = "Rare", worldboss = "Boss" }
local function paintClassification(f)
    local cls = UnitClassification(f.unit)
    if type(cls) ~= "nil" and ns.CanRead(cls) then f.classification = cls end   -- else keep last
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

-- What else repaints a frame whole, per unit: the event that swaps the unit
-- out, and for a unit's target the UNIT_TARGET of the unit it hangs off.
-- targettarget and focustarget get no unit events of their own from the
-- client, so those two are also polled while they are on screen.
local GLOBAL_EVENTS = {
    target       = { "PLAYER_TARGET_CHANGED" },
    focus        = { "PLAYER_FOCUS_CHANGED" },
    targettarget = { "PLAYER_TARGET_CHANGED" },
    focustarget  = { "PLAYER_FOCUS_CHANGED" },
    boss         = { "INSTANCE_ENCOUNTER_ENGAGE_UNIT" },
}
local OWNER_UNIT = { targettarget = "target", focustarget = "focus", pet = "player" }
local POLLED = { targettarget = true, focustarget = true }
local POLL_EVERY = 0.2

local function onPoll(glob, elapsed)
    glob.wait = (glob.wait or 0) + elapsed
    if glob.wait < POLL_EVERY then return end
    glob.wait = 0
    local f = glob.frame
    if f:IsVisible() then UF.Paint(f) end
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
    for _, event in ipairs(GLOBAL_EVENTS[UF.ConfigKey(f.unit)] or {}) do
        pcall(glob.RegisterEvent, glob, event)
    end
    local owner = OWNER_UNIT[f.unit]
    if owner == "player" then
        pcall(glob.RegisterUnitEvent, glob, "UNIT_PET", "player")
    elseif owner then
        pcall(glob.RegisterUnitEvent, glob, "UNIT_TARGET", owner)
    end
    if f.unit:find("^boss%d") then
        pcall(glob.RegisterUnitEvent, glob, "UNIT_TARGETABLE_CHANGED", f.unit)
    end
    glob:SetScript("OnEvent", onGlobalEvent)
    ev:SetScript("OnEvent", onUnitEvent)
end

function UF.SetEventsEnabled(f, on)
    if not f or not f.events then return end
    if on then
        f.events:SetScript("OnEvent", onUnitEvent)
        f.globalEvents:SetScript("OnEvent", onGlobalEvent)
        if POLLED[f.unit] then f.globalEvents:SetScript("OnUpdate", onPoll) end
        UF.Paint(f)
    else
        f.events:SetScript("OnEvent", nil)
        f.globalEvents:SetScript("OnEvent", nil)
        f.globalEvents:SetScript("OnUpdate", nil)
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

-- A whole Blizzard frame to the hidden parent, events off, and put back there
-- whenever something hands it a parent of its own again.
local function silenceWhole(key, frame)
    if not frame or silenced[key] then return end
    unregisterTree(frame, nil)
    frame:Hide()
    frame:SetParent(hiddenParent)
    if not frame._vfuiParentHook then
        frame._vfuiParentHook = true
        hooksecurefunc(frame, "SetParent", function(self, parent)
            if parent ~= hiddenParent and silenced[key] and not ns:InCombat() then
                C_Timer.After(0, function() self:SetParent(hiddenParent) end)
            end
        end)
    end
    silenced[key] = true
end

-- The target-of-target frames are children of the target and focus frames;
-- they go with their parent, and on their own when only they are replaced.
local SILENCER = {
    player       = silencePlayer,
    target       = function() silenceWhole("target", _G.TargetFrame) end,
    focus        = function() silenceWhole("focus", _G.FocusFrame) end,
    targettarget = function() silenceWhole("targettarget", _G.TargetFrame and _G.TargetFrame.totFrame) end,
    focustarget  = function() silenceWhole("focustarget", _G.FocusFrame and _G.FocusFrame.totFrame) end,
    pet          = function() silenceWhole("pet", _G.PetFrame) end,
    boss         = function() silenceWhole("boss", _G.BossTargetFrameContainer) end,
}

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
    player       = "|cffffffffPLAYER FRAME|r",
    target       = "|cffffffffTARGET FRAME|r",
    focus        = "|cffffffffFOCUS FRAME|r",
    targettarget = "|cffffffffTARGET OF TARGET|r",
    focustarget  = "|cffffffffFOCUS TARGET|r",
    pet          = "|cffffffffPET FRAME|r",
    boss         = "|cffffffffBOSS FRAMES|r",
}

-- The real units behind one setting: five for the boss column, one otherwise.
local function unitsOf(key)
    if key ~= "boss" then return { key } end
    local list = {}
    for i = 1, UF.BOSS_COUNT do list[i] = "boss" .. i end
    return list
end
UF.UnitsOf = unitsOf

-- The boss column: a plain holder the mover moves, the five secure frames
-- standing in it one under (or over) the other.
local bossHolder

local function ensureBossHolder(db)
    if bossHolder then return bossHolder end
    bossHolder = CreateFrame("Frame", "VuloForeverUI_BossFrames", UIParent)
    bossHolder:SetSize(160, 200)
    bossHolder:SetFrameStrata("LOW")
    bossHolder.mover = ns:CreateMover(bossHolder, {
        key      = "unitframe_boss",
        label    = LABELS.boss,
        db       = db,
        width    = 160,
        height   = 200,
        scalable = true,
        editPreview = function(on)
            local list = {}
            for i = 1, UF.BOSS_COUNT do list[#list + 1] = UF.Frames["boss" .. i] end
            UF.EditPreview(list, on)
        end,
    })
    ns:ApplyMover(bossHolder.mover)
    return bossHolder
end

local function layoutBossColumn(cfg)
    if not bossHolder then return end
    local skin = UF.ModernSkin(cfg)
    local gap = cfg.bossSpacing or 30
    local n = UF.BOSS_COUNT
    local h = n * skin.height + (n - 1) * gap
    bossHolder:SetSize(skin.width, h)
    local up = cfg.bossGrowth == "up"
    for i = 1, n do
        local f = UF.Frames["boss" .. i]
        if f then
            f:ClearAllPoints()
            local off = (i - 1) * (skin.height + gap)
            if up then
                f:SetPoint("BOTTOMLEFT", bossHolder, "BOTTOMLEFT", 0, off)
            else
                f:SetPoint("TOPLEFT", bossHolder, "TOPLEFT", 0, -off)
            end
        end
    end
    local m = bossHolder.mover
    m.opts.width, m.opts.height = skin.width, h
    ns:RefreshMoverGeometry(m)
    ns:ApplyMover(m)
end

local function unitOn(mod, key)
    local db = mod.db[key]
    return db and db.enabled ~= false
end
UF.IsUnitOn = unitOn

-- -------------------------------------------- first place: Blizzard's --

-- A fresh profile's own frames start where Blizzard's stand -- wherever the
-- client's Edit Mode put them -- rather than at numbers of ours. Once per
-- setting, and only on a position nobody has touched (still the default):
-- an imported or dragged one is never overwritten. Profiles from before this
-- carry seeded = true from migration [2], so a layout that already exists
-- stays exactly where it is.
--
-- Read BEFORE the frame is silenced: under the hidden parent its place means
-- nothing any more. The target-of-target frames go with their parents.
local BLIZZARD_FRAME = {
    player       = function() return _G.PlayerFrame end,
    target       = function() return _G.TargetFrame end,
    focus        = function() return _G.FocusFrame end,
    targettarget = function() return _G.TargetFrame and _G.TargetFrame.totFrame end,
    focustarget  = function() return _G.FocusFrame and _G.FocusFrame.totFrame end,
    pet          = function() return _G.PetFrame end,
    boss         = function() return _G.BossTargetFrameContainer end,
}
local SILENCED_WITH = { targettarget = "target", focustarget = "focus" }

local function seedFromBlizzard(mod, key)
    local db, def = mod.db[key], mod.defaults[key]
    if not (db and def) or db.seeded then return end
    if db.x ~= def.x or db.y ~= def.y then db.seeded = true; return end
    if silenced[key] or silenced[SILENCED_WITH[key] or key] then return end
    local get = BLIZZARD_FRAME[key]
    local frame = get and get()
    if not (frame and frame.GetCenter) then return end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    local us = UIParent:GetEffectiveScale()
    if not (fx and fy and px and py and us and us > 0) then return end
    local fs = frame:GetEffectiveScale()
    -- the frame's centre in UIParent units, then in our frame's own: db.x/y
    -- are offsets in the space of a frame scaled by db.scale
    local sx, sy = (fx * fs - px * us) / us, (fy * fs - py * us) / us
    local scale = db.scale or 1
    db.x, db.y = math.floor(sx / scale + 0.5), math.floor(sy / scale + 0.5)
    db.seeded = true
end

function UF.ActivateOwnFrames(mod)
    if mod.db.style ~= "modern" then return end
    for _, key in ipairs(UF.UNITS) do
        if unitOn(mod, key) then
            seedFromBlizzard(mod, key)
            local db = mod.db[key]
            local parent = key == "boss" and ensureBossHolder(db) or nil
            for _, unit in ipairs(unitsOf(key)) do
                local f = UF.CreateUnitFrame(unit, db, LABELS[key], parent)
                UF.SetSkin(f, "modern", { unit = unit, cfg = db.modern })
                -- A frame already running keeps what it has: in edit mode the
                -- watch is lifted for its stand-in, and a second pass here
                -- (a unit switched on while editing) must not put it back.
                if not f.vfActive then
                    RegisterUnitWatch(f)
                    f.vfActive = true
                    if ns:IsEditModeActive() then UF.EditPreview({ f }, true) end
                end
                UF.SetEventsEnabled(f, true)
            end
            if parent then
                parent:Show()
                layoutBossColumn(db.modern)
            end
            UF.SilenceBlizzard(key)
        end
    end
end

-- A setting changed: rebuild that unit's skin from db and repaint. SetSkin
-- calls SetSize on a secure unit button, which the client refuses in combat,
-- so a change made mid-fight lands when the fight ends. The options preview
-- is not secure and follows at once, fight or not.
local refreshPending = {}

function UF.RefreshModern(mod, key)
    if UF.Preview then UF.Preview.Refresh() end
    if mod.db.style ~= "modern" then return end
    if ns:InCombat() then
        if not refreshPending[key] then
            refreshPending[key] = true
            ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", function()
                refreshPending[key] = nil
                UF.RefreshModern(mod, key)
            end)
        end
        return
    end
    -- A unit switched on after login is built here; one switched off is left
    -- to the reload the options ask for.
    if unitOn(mod, key) and not UF.Frames[unitsOf(key)[1]] then
        UF.ActivateOwnFrames(mod)
        return
    end
    local db = mod.db[key]
    for _, unit in ipairs(unitsOf(key)) do
        local f = UF.Frames[unit]
        if f then
            UF.SetSkin(f, "modern", { unit = unit, cfg = db.modern })
            UF.Paint(f)
        end
    end
    if key == "boss" then layoutBossColumn(db.modern) end
end

function UF.DeactivateOwnFrames()
    for _, key in ipairs(UF.UNITS) do
        for _, unit in ipairs(unitsOf(key)) do
            local f = UF.Frames[unit]
            if f then
                UF.SetEventsEnabled(f, false)
                UnregisterUnitWatch(f)
                f.vfActive = nil
                f:Hide()
            end
        end
    end
    if bossHolder then bossHolder:Hide() end
end
