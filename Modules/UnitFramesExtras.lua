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
