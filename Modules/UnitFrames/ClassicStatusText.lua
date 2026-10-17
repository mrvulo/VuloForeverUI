-- VuloForeverUI / Modules / UnitFrames / ClassicStatusText
--
-- The player frame's bar texts in the Classic style, when "Status text on the
-- bars" is on: percent on the left, value on the right -- the same as the
-- target frame shows.
--
-- WHY OUR OWN TEXTS
--
-- The status text CVar says BOTH, and the target frame shows it. The player's
-- health and power are SECRET on this client, even out of combat (measured:
-- issecretvalue(UnitHealthMax("player")) is true). TextStatusBar works the
-- percent out by dividing the value by the max, which a secret does not
-- allow, so Blizzard's player bars fall back to the numeric "594 / 594",
-- centred -- a different layout from the target frame right next to it.
--
-- So the player's two bars get two strings of ours each, filled from the
-- APIs that hand the percent over ready-made (UnitHealthPercent,
-- UnitPowerPercent with CurveConstants.ScaleTo100) and the value through
-- AbbreviateNumbers; secrets go into SetFormattedText as they are. Blizzard's
-- three strings on those bars go to alpha 0 meanwhile -- alpha, never Hide().
-- Like Blizzard's BOTH, a power that is not mana shows the value only.
-- Dead, a ghost or in a vehicle: Blizzard's text comes back, ours steps aside.
local _, ns = ...
local UF = ns.UF
local Classic = UF.Classic

local texts                -- { health = { bar, left, right }, power = {...} }
local events

local function bars()
    local pf = _G.PlayerFrame
    local main = pf and pf.PlayerFrameContent and pf.PlayerFrameContent.PlayerFrameContentMain
    local hc = main and main.HealthBarsContainer
    local mba = main and main.ManaBarArea
    return hc and hc.HealthBar, mba and mba.ManaBar
end

local function wanted()
    local m = Classic.Mod()
    return Classic.IsActive() and m and m.db and m.db.classicStatusText and true or false
end

local function blizzardAlpha(bar, a)
    for _, key in ipairs({ "TextString", "LeftText", "RightText" }) do
        local fs = bar[key]
        if fs and fs.SetAlpha then fs:SetAlpha(a) end
    end
end

-- Two strings on a frame of ours, in the face, size and colour of Blizzard's
-- own, on the points Blizzard's left and right texts sit on. The host hangs
-- where Blizzard's TEXTS hang (the Classic player moves them onto the frame
-- container), never on the bar: the Classic style keeps Blizzard's bars at
-- alpha 0 under its own, and a child of the bar would be invisible with it.
local function makePair(bar)
    local model = bar.LeftText or bar.TextString
    local parent = (model and model:GetParent()) or bar
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:SetFrameLevel(parent:GetFrameLevel() + 3)
    local function one(model, point)
        local fs = host:CreateFontString(nil, "OVERLAY")
        if model then
            local font, size, flags = model:GetFont()
            if font then fs:SetFont(font, size, flags) end
            fs:SetTextColor(model:GetTextColor())
            local sx, sy = model:GetShadowOffset()
            if sx then fs:SetShadowOffset(sx, sy); fs:SetShadowColor(model:GetShadowColor()) end
            fs:SetPoint(point, model, point, 0, 0)
        end
        return fs
    end
    return { bar = bar, host = host, left = one(bar.LeftText, "LEFT"), right = one(bar.RightText, "RIGHT") }
end

-- each answer read before it is tested: a secret boolean throws on `if`
local function aside()
    local dead = UnitIsDeadOrGhost("player")
    if ns.CanRead(dead) and dead then return true end
    local vehicle = UnitHasVehicleUI and UnitHasVehicleUI("player")
    return ns.CanRead(vehicle) and vehicle and true or false
end

-- alpha, not Show/Hide: the host is a child of a protected frame
local function show(pair, on)
    pair.host:SetAlpha(on and 1 or 0)
    blizzardAlpha(pair.bar, on and 0 or 1)
end

local function paint()
    if not texts then return end
    local on = wanted() and not aside()
    show(texts.health, on)
    show(texts.power, on)
    if not on then return end

    local scale = CurveConstants and CurveConstants.ScaleTo100
    local h = texts.health
    h.left:SetFormattedText("%d%%", UnitHealthPercent("player", true, scale))
    h.right:SetFormattedText("%s", AbbreviateNumbers(UnitHealth("player")))

    local p = texts.power
    local _, token = UnitPowerType("player")
    if ns.CanRead(token) and token == "MANA" then
        p.left:SetFormattedText("%d%%", UnitPowerPercent("player", nil, false, scale))
    else
        p.left:SetText("")
    end
    p.right:SetFormattedText("%s", AbbreviateNumbers(UnitPower("player")))
end

local function onEvent()
    Classic.Guard("player.statustext", paint)
end

Classic.RegisterPart({
    name = "statustext",

    enable = function()
        if not texts then
            local hb, mb = bars()
            if not (hb and mb) then return end
            texts = { health = makePair(hb), power = makePair(mb) }
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", onEvent)
            for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE",
                                 "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }) do
                events:RegisterUnitEvent(e, "player")
            end
            for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST",
                                 "UNIT_ENTERED_VEHICLE", "UNIT_EXITED_VEHICLE" }) do
                events:RegisterEvent(e)
            end
        end
        paint()
    end,

    -- Blizzard's strings back, ours away.
    disable = function()
        if not texts then return end
        show(texts.health, false)
        show(texts.power, false)
    end,
})

