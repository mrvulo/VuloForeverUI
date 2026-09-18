-- VuloForeverUI / Modules / UnitFrames / Skins
--
-- The two looks an own unit frame can wear, as DATA. The engine creates every
-- child once; a skin only says where each one sits, how big it is and which
-- texture it shows. Anything with an `if` on a unit value does not belong here.
local _, ns = ...
ns.UF = ns.UF or {}
local UF = ns.UF

UF.Skins = {}

local CLASSIC_ART = "Interface\\TargetingFrame\\UI-TargetingFrame"
-- The sheet draws the portrait ring on the RIGHT, which is the target frame's
-- side; the player frame reads it mirrored (left > right) to put the ring on
-- the left. Seen the wrong way round in the client on 2026-09-18.
local COORDS_PLAYER = { 1.0, 0.09375, 0, 0.78125 }
local COORDS_TARGET = { 0.09375, 1.0, 0, 0.78125 }

-- Flip a TOPLEFT/TOPRIGHT/BOTTOMLEFT/BOTTOMRIGHT entry to the other side and
-- negate x, so one table describes both the player and the target frame.
local MIRROR = {
    TOPLEFT = "TOPRIGHT", TOPRIGHT = "TOPLEFT",
    BOTTOMLEFT = "BOTTOMRIGHT", BOTTOMRIGHT = "BOTTOMLEFT",
    LEFT = "RIGHT", RIGHT = "LEFT",
}
local function mirrorEntry(e)
    if not e then return nil end
    return {
        MIRROR[e[1]] or e[1], MIRROR[e[2]] or e[2], -(e[3] or 0), e[4] or 0, e[5], e[6],
        justify = (e.justify == "LEFT" and "RIGHT") or (e.justify == "RIGHT" and "LEFT") or e.justify,
    }
end

local function profileBarTexture()
    local name = ns.db and ns.db.global and ns.db.global.statusbar
    return ns.MediaStatusbar(name, "Interface\\TargetingFrame\\UI-StatusBar")
end

-- Layout numbers are Blizzard's Classic PlayerFrame (root 232x100); the target
-- frame is the same table mirrored. Entries: point, relPoint, x, y, w, h.
UF.Skins.classic = {
    width = 232, height = 100,
    art = { file = CLASSIC_ART, coords = COORDS_PLAYER, coordsTarget = COORDS_TARGET },
    flat = false,
    barTexture = function() return "Interface\\TargetingFrame\\UI-StatusBar" end,
    font = { "Fonts\\FRIZQT__.TTF", 10, "OUTLINE" },
    fontNumbers = { "Fonts\\ARIALN.TTF", 12, "OUTLINE" },

    portrait   = { "TOPLEFT", "TOPLEFT", 24, -16, 64, 64 },
    background = { "TOPLEFT", "TOPLEFT", 89.5, -26, 119, 41 },
    health     = { "TOPLEFT", "TOPLEFT", 90, -45, 119, 12 },
    power      = { "TOPLEFT", "TOPLEFT", 90, -56, 119, 12 },
    name       = { "CENTER", "CENTER", 34, 15, 100, 12 },
    level      = { "CENTER", "BOTTOMLEFT", 35.25, 30, 30, 12 },
    healthText = { "LEFT",  "LEFT",  2, 0, 60, 12, justify = "LEFT",  onBar = "health" },
    healthPct  = { "RIGHT", "RIGHT", -2, 0, 40, 12, justify = "RIGHT", onBar = "health" },
    powerText  = { "RIGHT", "RIGHT", -2, 0, 60, 12, justify = "RIGHT", onBar = "power" },
    threatText = { "TOP", "TOP", 34, 2, 100, 12 },
    classIcon  = { "BOTTOMLEFT", "BOTTOMLEFT", 26, 22, 18, 18 },
    tag        = nil,
    mirror = mirrorEntry,
}

UF.Skins.modern = {
    width = 220, height = 46,
    art = nil,
    flat = true,
    barTexture = profileBarTexture,
    font = { nil, 12, "OUTLINE" },          -- nil path = ns.UI.FONT_PATH
    fontNumbers = { nil, 11, "OUTLINE" },

    portrait   = { "RIGHT", "LEFT", -4, 0, 46, 46 },     -- outside, left of the panel
    background = nil,
    health     = { "TOPLEFT", "TOPLEFT", 1, -1, 218, 30 },
    power      = { "BOTTOMLEFT", "BOTTOMLEFT", 1, 1, 218, 12 },
    name       = { "LEFT", "LEFT", 6, 0, 120, 12, justify = "LEFT", onBar = "health" },
    level      = { "LEFT", "RIGHT", 4, 0, 24, 12, justify = "LEFT", after = "name" },
    healthText = nil,
    healthPct  = { "RIGHT", "RIGHT", -6, 0, 50, 12, justify = "RIGHT", onBar = "health" },
    powerText  = { "RIGHT", "RIGHT", -6, 0, 60, 10, justify = "RIGHT", onBar = "power" },
    threatText = { "BOTTOM", "TOP", 0, 3, 120, 12 },
    classIcon  = { "TOPRIGHT", "TOPLEFT", -3, 0, 14, 14 },   -- outside, top-left corner
    tag        = { "LEFT", "RIGHT", 4, 0, 40, 12, justify = "LEFT", after = "level" },
    mirror = function(e) return e end,   -- Modern is symmetric
}

-- Classic frame art by classification; Modern has no art and answers nil.
local CLASSIC_BY_CLASSIFICATION = {
    elite     = CLASSIC_ART .. "-Elite",
    rareelite = CLASSIC_ART .. "-Rare-Elite",
    rare      = CLASSIC_ART .. "-Rare",
    worldboss = CLASSIC_ART .. "-Elite",
}
function UF.ClassificationArt(skin, classification, opts)
    if not skin.art then return nil end
    if opts and opts.unit == "player" then
        return opts.playerElite and CLASSIC_BY_CLASSIFICATION.elite or skin.art.file
    end
    return CLASSIC_BY_CLASSIFICATION[classification or ""] or skin.art.file
end

local function place(region, e, frame, bars)
    if not e then
        region:Hide()
        return
    end
    region:ClearAllPoints()
    local rel = frame
    if e.onBar then rel = bars[e.onBar] end
    if e.after then rel = frame[e.after] end
    region:SetPoint(e[1], rel, e[2], e[3], e[4])
    if e[5] and e[6] then region:SetSize(e[5], e[6]) end
    if region.SetJustifyH and e.justify then region:SetJustifyH(e.justify) end
    region:Show()
end

local function applyFont(fs, spec)
    local path = spec[1] or ns.UI.FONT_PATH
    fs:SetFont(path, spec[2], spec[3] or "")
end

-- opts: { unit = "player"|"target", playerElite = bool, portrait = bool }
function UF.ApplySkin(frame, skin, opts)
    opts = opts or {}
    local isTarget = opts.unit == "target"
    local function E(key)
        local e = skin[key]
        if isTarget then e = skin.mirror(e, opts.unit) end
        return e
    end

    frame:SetSize(skin.width, skin.height)

    -- frame art vs flat panel
    if skin.art then
        frame.Art:SetTexture(UF.ClassificationArt(skin, frame.classification, opts))
        local c = isTarget and skin.art.coordsTarget or skin.art.coords
        frame.Art:SetTexCoord(c[1], c[2], c[3], c[4])
        frame.Art:ClearAllPoints()
        frame.Art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.Art:SetSize(skin.width, skin.height)
        frame.Art:Show()
        if frame._vcBG then frame._vcBG:Hide() end
        if frame._vcBorders then for _, b in ipairs(frame._vcBorders) do b:Hide() end end
        if frame._vcShadow then for _, t in ipairs(frame._vcShadow) do t:Hide() end end
        frame.AccentLine:Hide()
    else
        frame.Art:Hide()
        ns.UI:StyleBackdrop(frame)
        ns.UI:CreateShadow(frame)
        if frame._vcBG then frame._vcBG:Show() end
        if frame._vcBorders then for _, b in ipairs(frame._vcBorders) do b:Show() end end
        if frame._vcShadow then for _, t in ipairs(frame._vcShadow) do t:Show() end end
        frame.AccentLine:ClearAllPoints()
        frame.AccentLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.AccentLine:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.AccentLine:SetHeight(1)
        frame.AccentLine:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        frame.AccentLine:Show()
    end

    local bars = { health = frame.Health, power = frame.Power }
    place(frame.Background, E("background"), frame, bars)
    place(frame.Health,     E("health"),     frame, bars)
    place(frame.Power,      E("power"),      frame, bars)
    local tex = skin.barTexture()
    frame.Health:SetStatusBarTexture(tex)
    frame.Power:SetStatusBarTexture(tex)

    -- portrait: Classic always, Modern by option
    local wantPortrait = skin.art ~= nil or opts.portrait ~= false
    place(frame.Portrait, wantPortrait and E("portrait") or nil, frame, bars)
    if skin.flat and wantPortrait then
        frame.PortraitBG:ClearAllPoints()
        frame.PortraitBG:SetPoint("TOPLEFT", frame.Portrait, "TOPLEFT", -1, 1)
        frame.PortraitBG:SetPoint("BOTTOMRIGHT", frame.Portrait, "BOTTOMRIGHT", 1, -1)
        frame.PortraitBG:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        frame.PortraitBG:Show()
    else
        frame.PortraitBG:Hide()
    end

    place(frame.Name,       E("name"),       frame, bars)
    place(frame.Level,      E("level"),      frame, bars)
    place(frame.HealthText, E("healthText"), frame, bars)
    place(frame.HealthPct,  E("healthPct"),  frame, bars)
    place(frame.PowerText,  E("powerText"),  frame, bars)
    place(frame.ThreatText, E("threatText"), frame, bars)
    place(frame.ClassIcon,  E("classIcon"),  frame, bars)
    place(frame.Tag,        E("tag"),        frame, bars)

    applyFont(frame.Name, skin.font)
    applyFont(frame.Level, skin.fontNumbers)
    applyFont(frame.HealthText, skin.fontNumbers)
    applyFont(frame.HealthPct, skin.fontNumbers)
    applyFont(frame.PowerText, skin.fontNumbers)
    applyFont(frame.ThreatText, skin.fontNumbers)
    applyFont(frame.Tag, skin.fontNumbers)

    -- the glow is the bars' outline, whatever the skin
    frame.ThreatGlow:ClearAllPoints()
    frame.ThreatGlow:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", -2, 2)
    frame.ThreatGlow:SetPoint("BOTTOMRIGHT", frame.Power, "BOTTOMRIGHT", 2, -2)
end
