-- VuloForeverUI / Modules / UnitFrames / Preview
--
-- The header pinned above the Modern settings: the unit picker, and under it
-- the chosen frame drawn live at its real size. Every setting on the page
-- lands in the preview the moment it changes, in a fight too, and a click on
-- a part of the frame -- a bar, a text, the portrait -- scrolls the page to
-- the setting that owns it and flashes the row.
--
-- It is laid out by the ENGINE. The preview frame gets its regions from
-- UF.BuildRegions and its layout from UF.ModernSkin + UF.ApplySkin, the same
-- three calls a real frame goes through, so size, bars, texts, portrait and
-- colours are what the screen will show. Only the CONTENT is invented: the
-- preview has no unit, so it never asks the client for a value that could be
-- secret. The player's own name, level and class are read once, and only
-- where ns.CanRead says they are readable.
local _, ns = ...
local L  = ns.L
local UF = ns.UF
local UI = ns.UI

local Preview = {}
UF.Preview = Preview

-- Sample names. Proper names of the game world, so none of them needs a
-- translation; the player's own frames show the player's own name.
local ENEMY_NAMES  = { "Defias Pillager", "Murloc Tidehunter", "Scarlet Crusader", "Kobold Geomancer", "Blackrock Champion" }
local BOSS_NAMES   = { "Ragnaros", "Onyxia", "Nefarian", "Hakkar", "Vaelastrasz" }
local FRIEND_NAMES = { "Thrall", "Jaina", "Magni", "Tyrande", "Cairne" }
local PET_NAMES    = { "Wolf", "Cat", "Raptor", "Imp", "Voidwalker" }

local UNIT_LABEL = {
    player       = "Player",
    target       = "Target",
    focus        = "Focus",
    targettarget = "Target of Target",
    focustarget  = "Focus Target",
    pet          = "Pet",
    boss         = "Boss",
}

local header, frame, overlay
local mod
local sample = {}

-- --------------------------------------------------------------- samples --

local function pick(list) return list[math.random(#list)] end

-- The player's own values, where they are readable; a stand-in where not.
local function playerFacts()
    local name = UnitName("player")
    if not (ns.CanRead(name) and type(name) == "string") then name = L["Player"] end
    local level = ns.Num(UnitLevel("player"), 60)
    local _, token = UnitClass("player")
    if not (ns.CanRead(token) and type(token) == "string") then token = "WARRIOR" end
    local _, ptoken = UnitPowerType("player")
    if not (ns.CanRead(ptoken) and type(ptoken) == "string") then ptoken = "MANA" end
    return name, level, token, ptoken
end

-- New numbers and names for the unit on show. Called when the unit changes,
-- never on a setting change: a slider drag must not make the frame flicker
-- between names.
local function roll(unit)
    local pname, plevel, pclass, ppower = playerFacts()
    sample.unit    = unit
    sample.hpPct   = math.random(60, 90)
    sample.ppPct   = math.random(50, 95)
    sample.isPlayer = false
    sample.class   = "WARRIOR"        -- what UnitClass answers for most creatures
    sample.power   = "MANA"
    sample.tag     = nil
    sample.threat  = "100%"
    if unit == "player" then
        sample.name, sample.level, sample.class, sample.power = pname, plevel, pclass, ppower
        sample.isPlayer, sample.hpMax, sample.threat = true, 4200, L["Aggro"]
    elseif unit == "targettarget" then
        sample.name, sample.level, sample.class, sample.power = pname, plevel, pclass, ppower
        sample.isPlayer, sample.hpMax = true, 4200
    elseif unit == "focustarget" then
        sample.name, sample.level, sample.class = pick(FRIEND_NAMES), plevel, pclass
        sample.isPlayer, sample.hpMax = true, 3900
    elseif unit == "pet" then
        sample.name, sample.level, sample.hpMax = pick(PET_NAMES), plevel, 2100
        sample.power = PowerBarColor and PowerBarColor.FOCUS and "FOCUS" or "MANA"
    elseif unit == "boss" then
        sample.name, sample.level, sample.hpMax, sample.tag = pick(BOSS_NAMES), -1, 1250000, "Boss"
    else
        sample.name, sample.level, sample.hpMax = pick(ENEMY_NAMES), plevel + 1, 5600
        sample.tag = unit == "target" and "Elite" or nil
        sample.power = "RAGE"
    end
end

-- ------------------------------------------------------------ click spots --

-- A part of the frame opens the row that owns it: by its label, or by the
-- gear key a text slot row carries.
local function spot(key, region, row, section, level)
    row.mod, row.section = "unitframes", section
    header:Spot(key, region, row, level)
end

local function placeSpots()
    local F, T, X = L["Frame"], L["Text"], L["Extras"]
    spot("health",   frame.Health,     { label = L["Health bar height"] }, F, 0)
    spot("power",    frame.Power,      { label = L["Power bar height"] },  F, 0)
    spot("portrait", frame.Portrait,   { label = L["Show portrait"] },     F, 0)
    spot("left",     frame.Name,       { label = L["Left text"],   subKey = "uf/leftText" },   T, 2)
    spot("center",   frame.HealthText, { label = L["Center text"], subKey = "uf/centerText" }, T, 2)
    spot("right",    frame.HealthPct,  { label = L["Right text"],  subKey = "uf/rightText" },  T, 2)
    spot("ptext",    frame.PowerText,  { label = L["Power bar text"], subKey = "uf/powerText" }, T, 2)
    spot("level",    frame.Level,      { label = L["Show level"] },        X, 3)
    spot("tag",      frame.Tag,        { label = L["Show classification"] }, X, 3)
    spot("class",    frame.ClassIcon,  { label = L["Class icon beside the frame"] }, X, 3)
    spot("threat",   frame.ThreatText, { label = L["Threat text above the frame"] }, X, 3)
end

-- ---------------------------------------------------------------- filling --

local function classRGB(token)
    local c = ns.ClassColor(token)
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function slotText(content)
    local hp = math.floor(sample.hpMax * sample.hpPct / 100)
    local ppMax = sample.isPlayer and 3000 or 2400
    local pp = math.floor(ppMax * sample.ppPct / 100)
    if content == "name" then return sample.name
    elseif content == "curhp" then return AbbreviateNumbers(hp)
    elseif content == "perhp" then return sample.hpPct .. "%"
    elseif content == "hpboth" then return AbbreviateNumbers(hp) .. "  " .. sample.hpPct .. "%"
    elseif content == "curpp" then return AbbreviateNumbers(pp)
    elseif content == "ppboth" then return AbbreviateNumbers(pp) .. "/" .. AbbreviateNumbers(ppMax)
    end
    return ""
end

local PORTRAIT_ICON = {
    target = "Interface\\Icons\\INV_Misc_Head_Orc_01",
    focus  = "Interface\\Icons\\INV_Misc_Head_Orc_01",
    boss   = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    pet    = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
}

local function fill(skin)
    local f = frame
    f.Health:SetMinMaxValues(0, 100)
    f.Health:SetValue(sample.hpPct)
    f.Power:SetMinMaxValues(0, 100)
    f.Power:SetValue(sample.ppPct)

    if skin.healthClassColor then
        f.Health:SetStatusBarColor(classRGB(sample.class))
    else
        local c = skin.healthColor
        f.Health:SetStatusBarColor(c.r, c.g, c.b)
    end
    if skin.powerTypeColor then
        local info = PowerBarColor and PowerBarColor[sample.power] or { r = 0, g = 0, b = 1 }
        f.Power:SetStatusBarColor(info.r, info.g, info.b)
    else
        local c = skin.powerColor
        f.Power:SetStatusBarColor(c.r, c.g, c.b)
    end

    for _, key in ipairs(UF.TEXT_SLOTS) do
        local fs = f[key]
        fs:SetText(slotText(f.content[key]))
        if fs.vfClassColor then fs:SetTextColor(classRGB(sample.class)) else fs:SetTextColor(1, 1, 1) end
    end

    if sample.level < 0 then
        f.Level:SetText("??")
        f.Level:SetTextColor(1, 0, 0)
    else
        f.Level:SetFormattedText("%d", sample.level)
        local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(sample.level)
        if c then f.Level:SetTextColor(c.r, c.g, c.b) else f.Level:SetTextColor(1, 0.82, 0) end
    end
    f.Tag:SetText(sample.tag or "Elite")

    local icon = PORTRAIT_ICON[sample.unit]
    if icon then
        f.Portrait:SetTexture(icon)
        f.Portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        f.Portrait:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(f.Portrait, "player")
    end

    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[sample.class]
    if skin.classIcon and sample.isPlayer and coords then
        f.ClassIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        f.ClassIcon:Show()
    else
        f.ClassIcon:Hide()
    end

    f.ThreatText:SetText(sample.threat)
    f.ThreatText:SetTextColor(1, 0, 0)
    f.ThreatGlow:Hide()
end

-- How far the frame reaches past its own box, in frame units: the portrait and
-- the class badge to the sides, the portrait and the threat line above.
local function extents(cfg, skin)
    local side = cfg.portraitSide or "left"
    local l, r, up, down = 0, 0, 0, 0
    if skin.portrait then
        local ps = skin.portrait[5]
        if side == "right" then r = ps + 4 else l = ps + 4 end
        local over = math.max(0, (ps - skin.height) / 2)
        up, down = over, over
    end
    if skin.classIcon then
        if side == "right" then l = math.max(l, 17) else r = math.max(r, 17) end
    end
    if skin.threatText then up = math.max(up, 17) end
    return l, r, up, down
end

-- --------------------------------------------------------------- refresh --

-- `force`: the page build, where the header is not on screen yet but its
-- height is exactly what the builder is asking for.
function Preview.Refresh(force)
    if not (header and mod) then return end
    if not force and not header:IsLive() then return end
    local unit = mod.GetOptUnit()
    if sample.unit ~= unit then roll(unit) end
    local db = mod.db[unit]
    local cfg = db.modern
    local skin = UF.ModernSkin(cfg)

    UF.ApplySkin(frame, skin, { unit = unit, cfg = cfg })
    fill(skin)

    -- Real size: one frame pixel here is one frame pixel on screen, times the
    -- frame's own scale. Only a frame wider than the page is shrunk to fit.
    local l, r, up, down = extents(cfg, skin)
    local wide, high = l + skin.width + r, up + skin.height + down
    local s = header:Fit(wide, high, db.scale or 1)
    frame:SetScale(s)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", header.stage, "CENTER", (l - r) / 2, (down - up) / 2)

    overlay:SetShown(db.enabled == false)
    placeSpots()
    return header:SetStageHeight(high * s)
end

-- ----------------------------------------------------------------- build --

local function unitValues()
    local list = {}
    for _, unit in ipairs(UF.UNITS) do
        list[#list + 1] = { value = unit, text = L[UNIT_LABEL[unit]] }
    end
    return list
end

local function build()
    header = UI:CreatePreviewHeader({ key = "unitframes", hint = true })

    frame = CreateFrame("Frame", nil, header.stage)
    frame:SetSize(220, 44)
    UF.BuildRegions(frame)

    -- A unit switched off still shows, under a veil that says so.
    overlay = CreateFrame("Frame", nil, frame)
    overlay:SetAllPoints(frame)
    overlay:SetFrameLevel(frame:GetFrameLevel() + 15)
    local veil = overlay:CreateTexture(nil, "OVERLAY")
    veil:SetAllPoints(overlay)
    veil:SetColorTexture(0, 0, 0, 0.6)
    local off = overlay:CreateFontString(nil, "OVERLAY")
    UI.Font(off, 12)
    off:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    off:SetText(L["Disabled"])
    overlay:Hide()
end

-- Called by the options builder for every page build; returns the height.
function Preview.BuildHeader(host, owner)
    mod = owner
    if not header then build() end
    header:Mount(host, { control = {
        values = unitValues(),
        get    = function() return mod.GetOptUnit() end,
        set    = function(_, v)
            if v == mod.GetOptUnit() then return end
            mod.SetOptUnit(v)
        end,
    } })
    return Preview.Refresh(true) or 0
end
