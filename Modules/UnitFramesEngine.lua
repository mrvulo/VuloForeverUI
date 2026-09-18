-- VuloForeverUI / Modules / UnitFramesEngine
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

-- TEMP (removed in Task 4): create the frames from chat for the engine probe
ns:RegisterSlash({ key = "UFPROBE", commands = { "/vfufprobe" },
    desc = "Temporary: create raw unit frames for the engine probe." })
ns.Slash.UFPROBE = function()
    local mods = ns.db and ns.db.profile and ns.db.profile.modules
    if not mods then ns:Print("db not ready"); return end
    mods.unitframes = mods.unitframes or {}
    local db = mods.unitframes
    db.player = db.player or { x = -260, y = -180, scale = 1 }
    db.target = db.target or { x =  260, y = -180, scale = 1 }
    local p = UF.CreateUnitFrame("player", db.player, "PLAYER")
    local t = UF.CreateUnitFrame("target", db.target, "TARGET")
    UF.SetSkin(p, "classic", { unit = "player", playerElite = true })
    UF.SetSkin(t, "classic", { unit = "target" })
    ns:Print("probe frames up: %s %s", p:GetName(), t:GetName())
end
