-- VuloForeverUI / Modules / Nameplates / Preview
--
-- The live plate that sits at the top of every nameplate settings page, and
-- the click targets on it: a click on the name, the bar, the cast bar or an
-- aura row opens the setting that owns it.
--
-- It is a REAL plate. The frame goes through NP.Plate:Build and
-- Plate:ApplyAppearance, the same two passes a plate on screen goes through,
-- so every size, offset, colour, border and slot is what the client will
-- show. Only the CONTENT is invented: a preview has no unit, and every update
-- path in this module already returns on a plate without one (Health.Update,
-- Plate:UpdateTexts, Cast.OnEvent), so nothing here can touch a secret.
--
-- Two things are drawn rather than driven:
--   * the auras, because the engine only fills an aura container from a unit.
--     The icons here sit in the same slot, at the slot's size and spacing, with
--     the same border and text corners -- an image of the layout, not of a
--     real aura.
--   * the cast bar, which runs on a loop of its own so the page shows a cast
--     even when nothing in the world is casting.
local _, ns = ...
local L  = ns.L
local NP = ns.NP
local UI = ns.UI

local Preview = {}
NP.Preview = Preview

local PANEL_H   = 170
local CAST_LOOP = 2.8        -- seconds per preview cast
local TICK      = 0.05

-- Sample values. The numbers are never read from anywhere: they exist so the
-- text elements have something of a realistic LENGTH to show.
local SAMPLE_PCT   = 62
local SAMPLE_LEVEL = "60"
local SAMPLE_HP    = "12.4k"
local SAMPLE_ICONS = {
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Spell_Fire_Immolation",
    "Interface\\Icons\\Spell_Frost_FrostNova",
    "Interface\\Icons\\Ability_Warrior_Charge",
    "Interface\\Icons\\Spell_Nature_Lightning",
}
local SAMPLE_STACK = { "3", "8", "2", "5", "4" }
local SAMPLE_DUR   = { "14", "8", "26", "4", "11" }

local panel, plate, spots, auraRows
local elapsedCast = 0

-- ---------------------------------------------------------------------------
-- Click targets
--
-- A target names the row it opens: the TRANSLATED row label and the
-- TRANSLATED section title, which is what UI:RevealRow matches on. Every
-- nameplate setting a preview element stands for lives on the Display page.
-- ---------------------------------------------------------------------------
local function reveal(label, section)
    if not (UI and UI.RevealRow) then return end
    UI:RevealRow({ mod = "nameplates", tab = "display", label = label, section = section })
end

-- One invisible button over a region, with a border on hover so the target is
-- visible before the click. Created once per key and re-anchored on refresh.
local function spot(key, region, label, section, pad)
    if not region then return end
    local b = spots[key]
    if not b then
        b = CreateFrame("Button", nil, panel)
        b:SetFrameStrata("HIGH")
        b:SetFrameLevel(940)                 -- over the plate's text layer (900)
        b.edges = ns.MakeEdges(b, "OVERLAY")
        b:SetScript("OnEnter", function(self)
            local c = ns.COLORS and ns.COLORS.accent
            ns.LayoutEdges(self.edges, self, 1, (c and c.r) or 0.61, (c and c.g) or 0.42,
                (c and c.b) or 1, 1, 1)
            UI:ShowTooltip(self, { title = self.vfLabel, accent = true,
                lines = { L["Click to open the setting"] } })
        end)
        b:SetScript("OnLeave", function(self)
            ns.LayoutEdges(self.edges, self, 0, 1, 1, 1, 1)
            UI:HideTooltip()
        end)
        b:SetScript("OnClick", function(self) reveal(self.vfLabel, self.vfSection) end)
        spots[key] = b
    end
    b.vfLabel, b.vfSection = label, section
    ns.LayoutEdges(b.edges, b, 0, 1, 1, 1, 1)
    pad = pad or 1
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", region, "TOPLEFT", -pad, pad)
    b:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", pad, -pad)
    b:Show()
    return b
end

local function hideSpot(key)
    local b = spots[key]
    if b then b:Hide() end
end

-- ---------------------------------------------------------------------------
-- Sample content
-- ---------------------------------------------------------------------------
local function pctText(decimal)
    return decimal and string.format("%.1f%%", SAMPLE_PCT) or (SAMPLE_PCT .. "%")
end

-- The name element shows the WORD "Enemy Name" rather than an invented name:
-- the preview is a diagram of the plate, and a label says what a slot is for
-- in every language.
local function sampleText(element, decimal)
    if element == "enemyName" then return L["Enemy Name"]
    elseif element == "level" then return SAMPLE_LEVEL
    elseif element == "levelName" then return SAMPLE_LEVEL .. " | " .. L["Enemy Name"]
    elseif element == "nameLevel" then return L["Enemy Name"] .. " | " .. SAMPLE_LEVEL
    elseif element == "healthPercent" then return pctText(decimal)
    elseif element == "healthPercentNoSign" then return decimal and string.format("%.1f", SAMPLE_PCT) or tostring(SAMPLE_PCT)
    elseif element == "healthNumber" then return SAMPLE_HP
    elseif element == "healthPctNum" then return pctText(decimal) .. " | " .. SAMPLE_HP
    elseif element == "healthNumPct" then return SAMPLE_HP .. " | " .. pctText(decimal)
    elseif element == "healthPctNumDash" then return pctText(decimal) .. " - " .. SAMPLE_HP
    elseif element == "healthNumPctDash" then return SAMPLE_HP .. " - " .. pctText(decimal)
    end
    return ""
end

local TEXT_SPOT = {
    Top    = "Top Text",
    Right  = "Right Text",
    Left   = "Left Text",
    Center = "Center Text",
}

local function fillTexts(db)
    for slot, fs in pairs(plate.texts) do
        local cfg = db.textSlots[slot]
        local element = cfg.element
        if element == "none" then
            fs:SetText("")
            hideSpot("text" .. slot)
        else
            fs:SetText(sampleText(element, cfg.decimal))
            spot("text" .. slot, fs, L[TEXT_SPOT[slot]], L["Core Text Positions"], 2)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Icons: raid marker and rare/elite. Both sit in a slot, and a slot set to
-- "none" hides the icon -- the same rule the live plate follows.
-- ---------------------------------------------------------------------------
local SLOT_LABEL = { top = "Top", right = "Right", left = "Left",
                     topright = "Top right", topleft = "Top left", bottom = "Bottom" }

local function fillIcons(db)
    local marker = plate.icons.raidMarker
    if db.raidMarkerPos ~= "none" then
        SetRaidTargetIconTexture(marker, 8)      -- skull
        marker:Show()
        spot("raidMarker", marker, L[SLOT_LABEL[db.raidMarkerPos]], L["Core Positions"])
    else
        marker:Hide()
        hideSpot("raidMarker")
    end

    local class = plate.icons.classification
    if db.classificationSlot ~= "none" then
        class:SetTexture(nil)
        class:SetAtlas("nameplates-icon-elite-gold")
        class:Show()
        spot("classification", class, L[SLOT_LABEL[db.classificationSlot]], L["Core Positions"])
    else
        class:Hide()
        hideSpot("classification")
    end

    local inline = plate.icons.nameRaid
    if db.nameRaidMarkerEnabled and db.textSlots.Top.element ~= "none" then
        SetRaidTargetIconTexture(inline, 8)
        inline:Show()
    else
        inline:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Auras. Drawn, not driven -- see the note at the top of the file. The slot
-- geometry follows Auras.Layout: the row hangs off the health bar (off the
-- cast bar for "bottom"), and a row above the bar clears the name line.
-- ---------------------------------------------------------------------------
local KINDS = { "debuffs", "buffs", "cc" }
local KIND_LABEL = { debuffs = "Debuffs", buffs = "Buffs", cc = "Crowd Control" }
local ANCHOR = {
    top      = { "BOTTOM", "TOP", 0, 1 },
    bottom   = { "TOP", "BOTTOM", 0, -1 },
    left     = { "RIGHT", "LEFT", -1, 0 },
    right    = { "LEFT", "RIGHT", 1, 0 },
    topleft  = { "BOTTOMLEFT", "TOPLEFT", 0, 1 },
    topright = { "BOTTOMRIGHT", "TOPRIGHT", 0, 1 },
}
local TEXT_CORNER = {
    topleft     = { "TOPLEFT",      1, -1 },
    topright    = { "TOPRIGHT",    -1, -1 },
    bottomleft  = { "BOTTOMLEFT",   1,  1 },
    bottomright = { "BOTTOMRIGHT", -1,  1 },
    centre      = { "CENTER",       0,  0 },
}

local function newIcon(host)
    local f = CreateFrame("Frame", nil, host)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(920)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints(f)
    f.edges = ns.MakeEdges(f, "OVERLAY")
    f.dur = f:CreateFontString(nil, "OVERLAY")
    f.stacks = f:CreateFontString(nil, "OVERLAY")
    return f
end

local function placeCorner(fs, cfg, host)
    local a = TEXT_CORNER[cfg.position] or TEXT_CORNER.topleft
    fs:ClearAllPoints()
    fs:SetPoint(a[1], host, a[1], a[2] + cfg.x, a[3] + cfg.y)
end

local function layoutRow(kind, db)
    local row = auraRows[kind]
    if not row then row = {}; auraRows[kind] = row end
    local slot = NP.SlotOfAura(kind)
    if slot == "none" or not ANCHOR[slot] then
        for _, f in ipairs(row) do f:Hide() end
        hideSpot("aura" .. kind)
        return
    end

    local cfg   = db.iconSlots[slot]
    local a     = db.auras[kind]
    local size  = cfg.size
    local count = math.min(a.max, 3)
    local step  = size + a.spacing
    local anc   = ANCHOR[slot]
    local top   = db.textSlots.Top
    local gap   = (anc[4] > 0 and top.element ~= "none") and (top.size + 4) or 2
    local host  = (slot == "bottom") and plate.cast or plate.health
    local x0    = anc[3] * 2 + cfg.x
    local y0    = anc[4] * gap + cfg.y
    -- The same direction and pin as the real plates (Auras.GrowOf). A row
    -- left on "auto" above or below the bar is centred on it.
    local grow, point = NP.Auras.GrowOf(a.grow, slot, anc[1])
    local centred = (a.grow == nil or a.grow == "auto") and (slot == "top" or slot == "bottom")
    local width  = count * size + (count - 1) * a.spacing
    local font   = ns.ModuleFontPath("nameplates")
    local durCfg, stackCfg = db.auraText.duration, db.auraText.stacks

    local first, last
    for i = 1, count do
        local f = row[i]
        if not f then f = newIcon(plate); row[i] = f end
        f:SetSize(size, size)
        f:ClearAllPoints()
        local dx, dy = x0, y0
        local n = (i - 1) * step
        if centred then
            dx = x0 - width / 2 + size / 2 + n            -- centred on the bar
        elseif grow == "up" then dy = y0 + n
        elseif grow == "down" then dy = y0 - n
        elseif grow == "left" then dx = x0 - n
        else dx = x0 + n end
        f:SetPoint(point, host, anc[2], dx, dy)
        local crop = a.crop and (a.cropPct / 100) or 0
        f.tex:SetTexture(SAMPLE_ICONS[((i - 1) % #SAMPLE_ICONS) + 1])
        f.tex:SetTexCoord(crop, 1 - crop, crop, 1 - crop)
        local bSize, bc = NP.AuraStyle.Border(a)
        if bc then
            ns.LayoutEdges(f.edges, f, bSize, bc.r, bc.g, bc.b, bc.a or 1)
        else
            ns.LayoutEdges(f.edges, f, 0, 0, 0, 0, 1)
        end

        f.dur:SetFont(font, durCfg.size, "OUTLINE")
        f.dur:SetTextColor(durCfg.color.r, durCfg.color.g, durCfg.color.b)
        f.dur:SetText(durCfg.position ~= "none" and SAMPLE_DUR[i] or "")
        placeCorner(f.dur, durCfg, f)

        f.stacks:SetFont(font, stackCfg.size, "OUTLINE")
        f.stacks:SetTextColor(stackCfg.color.r, stackCfg.color.g, stackCfg.color.b)
        f.stacks:SetText(stackCfg.position ~= "none" and SAMPLE_STACK[i] or "")
        placeCorner(f.stacks, stackCfg, f)

        f:Show()
        first = first or f
        last = f
    end
    for i = count + 1, #row do row[i]:Hide() end

    -- One click target over the whole row. Which icon is the top left corner
    -- and which the bottom right depends on the direction the row grew.
    local b = spot("aura" .. kind, first, L[KIND_LABEL[kind]], L["Auras"], 2)
    if b and last and last ~= first then
        local tl, br = first, last
        if grow == "up" or grow == "left" then tl, br = last, first end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tl, "TOPLEFT", -2, 2)
        b:SetPoint("BOTTOMRIGHT", br, "BOTTOMRIGHT", 2, -2)
    end
end

-- ---------------------------------------------------------------------------
-- Cast bar. Its own loop, so the page always shows one.
-- ---------------------------------------------------------------------------
local function fillCast(db)
    local cast = plate.cast
    cast:SetMinMaxValues(0, CAST_LOOP)
    cast:SetValue(elapsedCast)
    local c = db.castBar
    cast:SetStatusBarColor(c.r, c.g, c.b)
    cast:Show()

    plate.castIcon:SetTexture(SAMPLE_ICONS[5])
    plate.castName:SetText(L["Spell Name"])
    plate.castTarget:SetText(L["Enemy Name"])
    plate.castTimer:SetFormattedText("%.1f", CAST_LOOP - elapsedCast)

    spot("cast", cast, L["Cast Bar Height"], L["Health and Cast Bar"])
    if db.showCastIcon then
        spot("castIcon", plate.castIconFrame, L["Spell Icon"], L["Health and Cast Bar"])
    else
        hideSpot("castIcon")
    end
    if db.castNameSide ~= "none" then
        spot("castName", plate.castName, L["Spell Name"], L["Cast Bar Text"], 2)
    else
        hideSpot("castName")
    end
    if db.showCastTimer then
        spot("castTimer", plate.castTimer, L["Cast Timer"], L["Health and Cast Bar"], 2)
    else
        hideSpot("castTimer")
    end
end

local function tick(self, elapsed)
    self.wait = (self.wait or 0) + elapsed
    if self.wait < TICK then return end
    self.wait = 0
    elapsedCast = elapsedCast + TICK
    if elapsedCast > CAST_LOOP then elapsedCast = 0 end
    if not plate then return end
    plate.cast:SetValue(elapsedCast)
    plate.castTimer:SetFormattedText("%.1f", CAST_LOOP - elapsedCast)
end

-- ---------------------------------------------------------------------------
-- The plate
-- ---------------------------------------------------------------------------
local function ensurePlate()
    if plate then return end
    plate = CreateFrame("Frame", nil, panel)
    Mixin(plate, NP.Plate)
    plate.isPreview = true
    plate:Build()
    -- A plate on screen pins its text and icon layers to MEDIUM so a
    -- neighbouring plate cannot cover them. Inside the settings window (HIGH)
    -- that would put them behind the page, so the preview lifts them.
    plate.textFrame:SetFrameStrata("HIGH")
    plate.iconFrame:SetFrameStrata("HIGH")
    plate:SetPoint("CENTER", panel, "CENTER", 0, 0)   -- Refresh settles the offset
    plate:Show()
end

-- How far the plate reaches above and below the health bar, and how far out to
-- the side, in plate coordinates: name line, icon rows, cast bar, side slots.
local function extents(db)
    local up = (db.textSlots.Top.element ~= "none") and (db.textSlots.Top.size + 4) or 2
    local topRow = 0
    for _, slot in ipairs({ "top", "topleft", "topright" }) do
        if NP.IconInSlot(slot) ~= "none" then
            topRow = math.max(topRow, db.iconSlots[slot].size + 2)
        end
    end
    local down = db.castBarHeight + 4
    if NP.IconInSlot("bottom") ~= "none" then down = down + db.iconSlots.bottom.size + 2 end
    local side = 0
    for _, slot in ipairs({ "left", "right" }) do
        if NP.IconInSlot(slot) ~= "none" then
            side = math.max(side, db.iconSlots[slot].size + 2)
        end
    end
    return up + topRow, down, side
end

function Preview.Refresh()
    if not (panel and panel:IsShown()) then return end
    local db = NP.db()
    if not db then return end
    ensurePlate()

    plate:SetScale(1)
    plate:ApplyAppearance()

    -- Fill: plain numbers on a plate with no unit. Absorb shares the health
    -- range and hangs off the fill's edge, exactly as it does on screen.
    plate.health:SetMinMaxValues(0, 100)
    plate.health:SetValue(SAMPLE_PCT)
    local hc = db.enemyInCombat
    plate.health:SetStatusBarColor(hc.r, hc.g, hc.b)
    plate.absorb:SetMinMaxValues(0, 100)
    plate.absorb:SetValue(12)
    plate.hashLine:SetShown(db.hashLineEnabled)

    fillTexts(db)
    fillIcons(db)
    fillCast(db)
    for _, kind in ipairs(KINDS) do layoutRow(kind, db) end

    spot("health", plate.health, L["Health Bar Width"], L["Health and Cast Bar"])

    -- Fit. A 250 px bar with an aura column on each side is wider than the
    -- page, and a preview that runs off the card shows half a setting. The
    -- extents are computed from the SETTINGS, never measured: a getter on a
    -- region of a plate is exactly what this module does not do.
    local up, down, side = extents(db)
    local room  = math.max(120, (panel:GetWidth() or 480) - 24)
    local tall  = PANEL_H - 34
    local wide  = db.healthBarWidth + 2 * side
    local high  = up + db.healthBarHeight + down
    local scale = math.min(1, room / math.max(wide, 1), tall / math.max(high, 1))
    scale = math.max(0.4, scale)
    plate:SetScale(scale)

    -- The health bar is the plate's centre, but the composition is not: the
    -- name and a top aura row sit above it, the cast bar below. Shifting by
    -- half the difference puts the whole plate in the middle of the card.
    plate:ClearAllPoints()
    plate:SetPoint("CENTER", panel, "CENTER", 0, (down - up) / 2 * scale - 5)
end

-- ---------------------------------------------------------------------------
-- The options item
-- ---------------------------------------------------------------------------
local function build(parent)
    if not panel then
        panel = CreateFrame("Frame", nil, parent)
        panel:SetHeight(PANEL_H)
        spots, auraRows = {}, {}

        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(panel)
        bg:SetColorTexture(0, 0, 0, 0.25)

        panel.edges = ns.MakeEdges(panel, "BORDER")
        ns.LayoutEdges(panel.edges, panel, 1, 1, 1, 1, 0.08, 0)

        local caption = panel:CreateFontString(nil, "OVERLAY")
        UI.FontFor("nameplates", caption, 11, nil)
        caption:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
        caption:SetTextColor(0.6, 0.6, 0.6)
        caption:SetText(L["Live preview"])

        local hint = panel:CreateFontString(nil, "OVERLAY")
        UI.FontFor("nameplates", hint, 11, nil)
        hint:SetPoint("BOTTOM", panel, "BOTTOM", 0, 6)
        hint:SetTextColor(0.45, 0.45, 0.5)
        hint:SetText(L["Click an element to open its settings"])

        panel:SetScript("OnUpdate", tick)
    end
    -- A page rebuild orphans anything the builder does not recognise, so the
    -- panel re-adopts itself every time it is asked for, and takes its width
    -- from the page -- a custom widget is anchored by one corner only.
    panel:SetParent(parent)
    panel:SetWidth(math.max(160, (parent:GetWidth() or 540) - 28))
    panel:Show()
    Preview.Refresh()
    return panel
end

function Preview.Item()
    return { type = "custom", height = PANEL_H, build = build }
end
