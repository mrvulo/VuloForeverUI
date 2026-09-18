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
