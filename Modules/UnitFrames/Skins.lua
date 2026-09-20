-- VuloForeverUI / Modules / UnitFrames / Skins
--
-- The two looks an own unit frame can wear, as DATA. The engine creates every
-- child once; a skin only says where each one sits, how big it is and which
-- texture it shows. Anything with an `if` on a unit value does not belong here.
--
-- Classic is a constant table. Modern is BUILT per unit from that unit's
-- settings -- same table shape, numbers out of the profile -- so the options
-- page only ever writes db and asks for a rebuild.
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
        onBar = e.onBar, after = e.after, fontSize = e.fontSize,
    }
end

local DEFAULT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"

local function profileBarTexture()
    local name = ns.db and ns.db.global and ns.db.global.statusbar
    return ns.MediaStatusbar(name, DEFAULT_BAR)
end

-- Layout numbers are Blizzard's Classic PlayerFrame (root 232x100); the target
-- frame is the same table mirrored. Entries: point, relPoint, x, y, w, h.
UF.Skins.classic = {
    width = 232, height = 100,
    art = { file = CLASSIC_ART, coords = COORDS_PLAYER, coordsTarget = COORDS_TARGET },
    flat = false,
    barTexture = function() return DEFAULT_BAR end,
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

    -- Which unit value each text slot carries. Classic's assignment is fixed;
    -- Modern lets the player choose per slot.
    content = { Name = "name", HealthText = "curhp", HealthPct = "perhp", PowerText = "curpp" },
    textClassColor = { Name = true },
}

-- ------------------------------------------------------------- Modern --

local MODERN_GAP = 2            -- breathing space between health and power
local MODERN_PAD = 1            -- the panel edge the bars sit inside
local MODERN_TEXT_INSET = 6
local MODERN_TEXT_GAP = 6       -- between the left and the right text slot

local function identity(e) return e end

-- Defaults live in the module (Modules/UnitFrames/UnitFrames.lua); everything
-- read here falls back to the same number, so a skin built from an empty table
-- is the frame as it shipped.
function UF.ModernSkin(cfg)
    cfg = cfg or {}
    local width  = cfg.width or 220
    local hh     = cfg.healthHeight or 30
    local showP  = cfg.showPower ~= false
    local ph     = cfg.powerHeight or 12
    local inner  = width - MODERN_PAD * 2
    local height = MODERN_PAD * 2 + hh + (showP and (MODERN_GAP + ph) or 0)

    -- The left and right slot SHARE the room between the two insets, minus a
    -- gap, so a long name is cut off before it reaches the percent instead of
    -- running under it. Splitting the full inner width between them (55/45)
    -- overlaps by the two insets at every frame width.
    local roomForText = inner - MODERN_TEXT_INSET * 2 - MODERN_TEXT_GAP
    local leftW  = math.max(20, math.floor(roomForText * 0.55))
    local rightW = math.max(20, roomForText - leftW)

    -- A text slot: content "none" means the font string is not placed at all,
    -- which is what hides it.
    local function slot(content, where, size, x, y, bar)
        if not content or content == "none" then return nil end
        local h = size + 4
        if where == "LEFT" then
            return { "LEFT", "LEFT", MODERN_TEXT_INSET + x, y,
                     leftW, h, justify = "LEFT", onBar = bar, fontSize = size }
        elseif where == "RIGHT" then
            return { "RIGHT", "RIGHT", -MODERN_TEXT_INSET + x, y,
                     rightW, h, justify = "RIGHT", onBar = bar, fontSize = size }
        end
        return { "CENTER", "CENTER", x, y,
                 inner - MODERN_TEXT_INSET * 2, h, justify = "CENTER", onBar = bar, fontSize = size }
    end

    local leftE   = slot(cfg.leftText   or "name", "LEFT",   cfg.leftSize   or 12, cfg.leftX   or 0, cfg.leftY   or 0, "health")
    local centerE = slot(cfg.centerText or "none", "CENTER", cfg.centerSize or 12, cfg.centerX or 0, cfg.centerY or 0, "health")
    local rightE  = slot(cfg.rightText  or "perhp", "RIGHT", cfg.rightSize  or 11, cfg.rightX  or 0, cfg.rightY  or 0, "health")
    local powerE  = showP
        and slot(cfg.powerText or "curpp", "RIGHT", cfg.powerTextSize or 11, cfg.powerTextX or 0, cfg.powerTextY or 0, "power")
        or nil

    -- Level and the classification tag ride behind the left text; without it
    -- they start at the health bar's own edge instead of anchoring to a font
    -- string that is not on screen.
    local lvlSize = cfg.levelSize or 11
    local levelE
    if cfg.showLevel ~= false then
        levelE = leftE
            and { "LEFT", "RIGHT", 4, 0, 30, lvlSize + 4, justify = "LEFT", after = "name", fontSize = lvlSize }
            or  { "LEFT", "LEFT", MODERN_TEXT_INSET, 0, 30, lvlSize + 4, justify = "LEFT", onBar = "health", fontSize = lvlSize }
    end
    local tagE
    if cfg.showTag then
        local anchor = levelE and "level" or (leftE and "name" or nil)
        tagE = anchor
            and { "LEFT", "RIGHT", 4, 0, 70, lvlSize + 4, justify = "LEFT", after = anchor, fontSize = lvlSize }
            or  { "LEFT", "LEFT", MODERN_TEXT_INSET, 0, 70, lvlSize + 4, justify = "LEFT", onBar = "health", fontSize = lvlSize }
    end

    local side  = cfg.portraitSide or "left"
    local psize = math.max(12, height + (cfg.portraitSize or 0))
    local portraitE
    if cfg.showPortrait ~= false then
        portraitE = side == "right"
            and { "LEFT", "RIGHT", 4, 0, psize, psize }
            or  { "RIGHT", "LEFT", -4, 0, psize, psize }
    end
    -- The class badge sits on the side the portrait left free.
    local classIconE
    if cfg.showClassIcon then
        classIconE = side == "right"
            and { "TOPRIGHT", "TOPLEFT", -3, 0, 14, 14 }
            or  { "TOPLEFT", "TOPRIGHT", 3, 0, 14, 14 }
    end

    local texture = cfg.texture
    if texture == nil or texture == "" then
        texture = nil
    end

    return {
        width = width, height = height,
        art = nil,
        flat = true,
        barTexture = function()
            return texture and ns.MediaStatusbar(texture, DEFAULT_BAR) or profileBarTexture()
        end,
        font = { nil, 12, "OUTLINE" },          -- nil path = ns.UI.FONT_PATH
        fontNumbers = { nil, 11, "OUTLINE" },

        portrait   = portraitE,
        background = nil,
        health     = { "TOPLEFT", "TOPLEFT", MODERN_PAD, -MODERN_PAD, inner, hh },
        power      = showP and { "BOTTOMLEFT", "BOTTOMLEFT", MODERN_PAD, MODERN_PAD, inner, ph } or nil,
        name       = leftE,
        level      = levelE,
        healthText = centerE,
        healthPct  = rightE,
        powerText  = powerE,
        threatText = cfg.showThreat ~= false and { "BOTTOM", "TOP", 0, 3, 120, 14 } or nil,
        classIcon  = classIconE,
        tag        = tagE,
        mirror     = identity,                  -- the portrait side is a setting

        content = {
            Name       = cfg.leftText   or "name",
            HealthText = cfg.centerText or "none",
            HealthPct  = cfg.rightText  or "perhp",
            PowerText  = showP and (cfg.powerText or "curpp") or "none",
        },
        textClassColor = {
            Name       = cfg.leftClassColor ~= false,
            HealthText = cfg.centerClassColor == true,
            HealthPct  = cfg.rightClassColor == true,
            PowerText  = false,
        },

        healthClassColor = cfg.healthClassColor ~= false,
        healthColor      = cfg.healthColor or { r = 0.15, g = 0.65, b = 0.25 },
        healthBgColor    = cfg.healthBgColor or { r = 0, g = 0, b = 0 },
        healthBgAlpha    = (cfg.healthBgOpacity or 60) / 100,
        healthAlpha      = (cfg.healthOpacity or 100) / 100,
        powerTypeColor   = cfg.powerTypeColor ~= false,
        powerColor       = cfg.powerColor or { r = 0.2, g = 0.4, b = 0.9 },
        powerBgColor     = cfg.powerBgColor or { r = 0, g = 0, b = 0 },
        powerBgAlpha     = (cfg.powerBgOpacity or 60) / 100,
        powerAlpha       = (cfg.powerOpacity or 100) / 100,
    }
end

-- The registry entry is a builder; UF.SetSkin calls it with the unit's own
-- settings table and skins the frame with what comes back.
UF.Skins.modern = { build = UF.ModernSkin }

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

-- `after` names a sibling in the skin's own vocabulary; the frame keys it.
local AFTER_REGION = { name = "Name", level = "Level" }

local function place(region, e, frame, bars)
    if not e then
        region:Hide()
        return
    end
    region:ClearAllPoints()
    local rel = frame
    if e.onBar then rel = bars[e.onBar] or frame end
    if e.after then rel = frame[AFTER_REGION[e.after] or e.after] or frame end
    region:SetPoint(e[1], rel, e[2], e[3], e[4])
    if e[5] and e[6] then region:SetSize(e[5], e[6]) end
    if region.SetJustifyH and e.justify then region:SetJustifyH(e.justify) end
    region:Show()
end

local function applyFont(fs, spec, e)
    local path = spec[1] or ns.UI.FONT_PATH
    fs:SetFont(path, (e and e.fontSize) or spec[2], spec[3] or "")
end

-- opts: { unit = "player"|"target", playerElite = bool, cfg = <unit settings> }
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

    -- Bar ground and fill opacity. The fill's alpha rides on the TEXTURE, not
    -- on the bar: the texts are children of the bar and would fade with it.
    local hbg = skin.healthBgColor or { r = 0, g = 0, b = 0 }
    frame.Health.bg:SetColorTexture(hbg.r, hbg.g, hbg.b, skin.healthBgAlpha or 0.6)
    local pbg = skin.powerBgColor or { r = 0, g = 0, b = 0 }
    frame.Power.bg:SetColorTexture(pbg.r, pbg.g, pbg.b, skin.powerBgAlpha or 0.6)
    local ht = frame.Health:GetStatusBarTexture()
    if ht then ht:SetAlpha(skin.healthAlpha or 1) end
    local pt = frame.Power:GetStatusBarTexture()
    if pt then pt:SetAlpha(skin.powerAlpha or 1) end

    -- portrait: Classic always, Modern by option
    local portraitE = E("portrait")
    place(frame.Portrait, portraitE, frame, bars)
    if skin.flat and portraitE then
        frame.PortraitBG:ClearAllPoints()
        frame.PortraitBG:SetPoint("TOPLEFT", frame.Portrait, "TOPLEFT", -1, 1)
        frame.PortraitBG:SetPoint("BOTTOMRIGHT", frame.Portrait, "BOTTOMRIGHT", 1, -1)
        frame.PortraitBG:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        frame.PortraitBG:Show()
    else
        frame.PortraitBG:Hide()
    end

    -- The left text is placed before whatever anchors behind it.
    local nameE, levelE = E("name"), E("level")
    place(frame.Name,       nameE,           frame, bars)
    place(frame.Level,      levelE,          frame, bars)
    local centerE, rightE, powerE = E("healthText"), E("healthPct"), E("powerText")
    local threatE, classIconE, tagE = E("threatText"), E("classIcon"), E("tag")
    place(frame.HealthText, centerE,    frame, bars)
    place(frame.HealthPct,  rightE,     frame, bars)
    place(frame.PowerText,  powerE,     frame, bars)
    place(frame.ThreatText, threatE,    frame, bars)
    place(frame.ClassIcon,  classIconE, frame, bars)
    place(frame.Tag,        tagE,       frame, bars)

    applyFont(frame.Name, skin.font, nameE)
    applyFont(frame.Level, skin.fontNumbers, levelE)
    applyFont(frame.HealthText, skin.fontNumbers, centerE)
    applyFont(frame.HealthPct, skin.fontNumbers, rightE)
    applyFont(frame.PowerText, skin.fontNumbers, powerE)
    applyFont(frame.ThreatText, skin.fontNumbers, threatE)
    applyFont(frame.Tag, skin.fontNumbers, tagE)

    -- What each text slot says, and whether it wears the class colour. The
    -- painters read this off the frame; they never look at the skin.
    local content = skin.content or {}
    local classColor = skin.textClassColor or {}
    frame.content = content
    for _, key in ipairs(UF.TEXT_SLOTS) do
        local fs = frame[key]
        if fs then
            fs.vfClassColor = classColor[key] == true
            if content[key] == nil or content[key] == "none" then fs:SetText("") end
        end
    end

    -- the glow is the bars' outline, whatever the skin
    frame.ThreatGlow:ClearAllPoints()
    frame.ThreatGlow:SetPoint("TOPLEFT", frame.Health, "TOPLEFT", -2, 2)
    local bottom = frame.Power:IsShown() and frame.Power or frame.Health
    frame.ThreatGlow:SetPoint("BOTTOMRIGHT", bottom, "BOTTOMRIGHT", 2, -2)
end
