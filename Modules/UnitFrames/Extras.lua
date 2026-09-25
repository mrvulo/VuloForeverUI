-- VuloForeverUI / Modules / UnitFrames / Extras
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
--
-- The retail bar art is a pre-coloured green atlas, so a vertex tint cannot
-- turn it white or blue (seen 2026-09-18: a priest's bar stayed green). The
-- bar gets the neutral Classic fill texture first, then the colour.
local NEUTRAL_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local neutralised = setmetatable({}, { __mode = "k" })   -- our note, not a field on Blizzard's bar
local function recolor(statusbar, unit)
    if not active or not mod.db.classColor then return end
    -- Classic draws its own health bar on an overlay and keeps Blizzard's at
    -- alpha 0; the class colour for that one is the Classic files' business
    -- (see Extras.ClassTint below). Nothing to paint here.
    if mod.db.style == "classic" then return end
    unit = unit or unitOfBar[statusbar]
    if not unit then return end
    local r, g, b = UF.ClassColor(unit)
    if r then
        if not neutralised[statusbar] then
            statusbar:SetStatusBarTexture(NEUTRAL_BAR)
            neutralised[statusbar] = true
        end
        statusbar:SetStatusBarColor(r, g, b)
    end
end

local threatFS, threatGlow, classIcons, classRings
local portraitOf = {}

local function ensureRegions()
    if threatFS then return end
    local tf = _G.TargetFrame
    threatFS = tf:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(threatFS, 11, "OUTLINE")
    threatFS:SetPoint("BOTTOM", tf, "TOP", 0, -2)
    -- Behind the bars only: a glow the size of the whole frame reads as a red
    -- slab on the retail art.
    local bars = targetHealthBar() and targetHealthBar():GetParent() or tf
    threatGlow = tf:CreateTexture(nil, "BACKGROUND", nil, -3)
    threatGlow:SetPoint("TOPLEFT", bars, "TOPLEFT", -3, 3)
    threatGlow:SetPoint("BOTTOMRIGHT", bars, "BOTTOMRIGHT", 3, -14)
    threatGlow:Hide()

    classIcons, classRings = {}, {}
    for unit, portrait in pairs({ player = playerPortrait(), target = targetPortrait() }) do
        if portrait then
            local icon = portrait:GetParent():CreateTexture(nil, "OVERLAY", nil, 1)
            icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            icon:SetSize(16, 16)
            -- top corner: the bottom one is where Blizzard's level circle sits
            icon:SetPoint("TOPLEFT", portrait, "TOPLEFT", -2, 2)
            icon:Hide()
            classIcons[unit] = icon
            portraitOf[unit] = portrait
        end
    end

    -- Classic: the target's icon is a badge on the portrait's rim, 20 px in a
    -- gold ring. The ring file's hole is 20 px wide with its centre at
    -- (15.5, -14.5) of 53 x 53, so the ring's centre sits (11, -12) off the
    -- icon's. Native size on purpose (seen 2026-09-19): at 58 px the class
    -- circle, which does not fill its 22 px cell, floats in the hole; at
    -- 48 px the ring's inner bevel covers the circle's edge.
    local icon = classIcons.target
    if icon then
        local ring = icon:GetParent():CreateTexture(nil, "OVERLAY", nil, 2)
        ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        ring:SetSize(53, 53)
        -- (10, -10) rather than the hole's exact (11, -12): the icon sits 1 px
        -- right and 2 px lower in the hole -- the class circles are drawn a
        -- little up and left of their cells, and centred by the numbers they
        -- looked off (seen 2026-09-25)
        ring:SetPoint("CENTER", icon, "CENTER", 10, -10)
        ring:Hide()
        classRings.target = ring
    end
end

-- Which units get an icon, and how big: Standard has its own switch and the
-- plain 16 px icon on both frames, Classic the ringed badge on the target.
local function iconWanted(unit)
    if mod.db.style == "classic" then
        -- 20 px, the size of the ring's hole (22 overran it, 18 read small).
        -- Icon centre 6, -7 off the portrait; the ring (anchored to it, see
        -- above) keeps its centre at 16, -17 where it always was.
        return mod.db.classicClassIcon and unit == "target", 20, true, -4, 3
    end
    return mod.db.classIcon, 16, false, -2, 2
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
        local wanted, size, ringed, x, y
        if active then wanted, size, ringed, x, y = iconWanted(unit) end
        -- CanRead before the token is tested: a boolean test on a secret token
        -- throws, and it would throw before the gate behind it gets a say.
        local coords = wanted and UnitExists(unit) and UnitIsPlayer(unit)
            and ns.CanRead(token) and token and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[token]
        local ring = classRings[unit]
        if coords then
            icon:SetSize(size, size)
            icon:SetPoint("TOPLEFT", portraitOf[unit], "TOPLEFT", x, y)
            icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            icon:Show()
        else
            icon:Hide()
        end
        if ring then ring:SetShown(coords and ringed and true or false) end
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

-- For the Classic style's overlay health bar: class colour for a player
-- unit, nil for anything else (the bar stays green). The caller has checked
-- that UnitIsPlayer's answer is readable.
function Extras.ClassTint(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    return UF.ClassColor(unit)
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
    for _, ring in pairs(classRings or {}) do ring:Hide() end
    -- Blizzard repaints its own colour on the next health update; we do not
    -- guess at it here.
end
