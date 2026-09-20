-- VuloForeverUI / Modules / Nameplates / Plate
--
-- One plate: the frame tree, putting it on a unit, taking it off again, static
-- styling and layout, the text and icon slots. What the bars SHOW lives in the
-- sibling files (Health, Colors, CastBar, Target); this file calls them.
--
-- Layout never measures. Widths and heights come from the settings, because a
-- getter on a region inside the nameplate tree can hand back a secret.
local _, ns = ...
local NP = ns.NP

local Plate = {}
NP.Plate = Plate

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TEXT_SLOTS = { "Top", "Right", "Left", "Center" }

-- ---------------------------------------------------------------------------
-- Slots. Every ELEMENT remembers where it sits (db.raidMarkerPos = "topright",
-- db.textSlots.Top.element = "enemyName"); putting something into a slot sends whoever
-- sat there to "none". Names evict names: a plate shows its name once.
-- ---------------------------------------------------------------------------
local NAME_FAMILY = { enemyName = true, levelName = true, nameLevel = true }
-- Icons and aura rows share the six slots and the one rule: assigning an
-- element to a slot sends whoever sat there to "none".
local ICON_KEYS = {
    raidMarker = "raidMarkerPos", classification = "classificationSlot",
    debuffs = "debuffSlot", buffs = "buffSlot", cc = "ccSlot",
}
NP.ICON_KEYS = ICON_KEYS

function NP.AssignTextSlot(slot, element)
    local db = NP.db()
    if element ~= "none" then
        for _, s in ipairs(TEXT_SLOTS) do
            local cur = db.textSlots[s].element
            if s ~= slot and (cur == element or (NAME_FAMILY[element] and NAME_FAMILY[cur])) then
                db.textSlots[s].element = "none"
            end
        end
    end
    db.textSlots[slot].element = element
    NP.Bump()
end

function NP.AssignIconSlot(slot, element)
    local db = NP.db()
    for name, key in pairs(ICON_KEYS) do
        if db[key] == slot and name ~= element then db[key] = "none" end
    end
    if element ~= "none" and ICON_KEYS[element] then db[ICON_KEYS[element]] = slot end
    NP.Bump()
end

-- Which slot an aura kind sits in ("none" when it is switched off).
function NP.SlotOfAura(kind)
    return NP.db()[ICON_KEYS[kind]] or "none"
end

function NP.IconInSlot(slot)
    local db = NP.db()
    for name, key in pairs(ICON_KEYS) do
        if db[key] == slot then return name end
    end
    return "none"
end

-- ---------------------------------------------------------------------------
-- Build: once per pooled frame
-- ---------------------------------------------------------------------------
-- Every event here is registered with RegisterUnitEvent for this plate's unit,
-- so the unit in the payload is never looked at -- for the cast events it may
-- be secret.
local CAST_EVENT = {}
for _, event in ipairs(NP.Cast.EVENTS) do CAST_EVENT[event] = true end

local function onEvent(self, event, ...)
    if not self.unit then return end
    if CAST_EVENT[event] then
        NP.Cast.OnEvent(self, event, ...)
    elseif event == "UNIT_HEALTH" or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        NP.Health.MarkDirty(self)
    elseif event == "UNIT_MAXHEALTH" then
        self.maxValid = false
        NP.Health.MarkDirty(self)
    elseif event == "UNIT_NAME_UPDATE" then
        self:UpdateTexts()
    elseif event == "UNIT_THREAT_LIST_UPDATE" then
        NP.Colors.Apply(self)
    end
end

function Plate:Build()
    self:SetFlattensRenderLayers(true)
    self:SetScript("OnEvent", onEvent)

    local health = CreateFrame("StatusBar", nil, self)
    health:SetAllPoints(self)
    health:SetStatusBarTexture(WHITE)
    self.health = health

    local bg = health:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(health)
    self.healthBG = bg

    self.borderHost = CreateFrame("Frame", nil, self)
    self.borderHost:SetAllPoints(health)
    self.borderHost:SetFrameLevel(health:GetFrameLevel() + 3)
    self.border = ns.MakeEdges(self.borderHost, "OVERLAY")

    -- Flattened render layers put everything in one plane; text and icons get
    -- their own strata and a high level so a neighbour's bar cannot cover them.
    local textFrame = CreateFrame("Frame", nil, self)
    textFrame:SetAllPoints(health)
    textFrame:SetFrameStrata("MEDIUM")
    textFrame:SetFrameLevel(900)
    self.textFrame = textFrame
    self.texts = {}
    for _, slot in ipairs(TEXT_SLOTS) do
        local fs = textFrame:CreateFontString(nil, "OVERLAY")
        fs:SetFont(ns.ModuleFontPath("nameplates"), 10, "OUTLINE")
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 1)
        self.texts[slot] = fs
    end

    local iconFrame = CreateFrame("Frame", nil, self)
    iconFrame:SetAllPoints(health)
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:SetFrameLevel(15)
    self.iconFrame = iconFrame
    self.icons = {
        raidMarker     = iconFrame:CreateTexture(nil, "OVERLAY"),
        classification = iconFrame:CreateTexture(nil, "OVERLAY"),
        nameRaid       = textFrame:CreateTexture(nil, "OVERLAY"),
    }
    self.icons.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    self.icons.nameRaid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")

    -- What the client stacks plates by. It reads RENDERED bounds, not the size
    -- set on the frame, so the frame carries a full-size invisible texture.
    local stack = CreateFrame("Frame", nil, self)
    local fill = stack:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(stack)
    fill:SetColorTexture(1, 1, 1, 0)
    self.stack = stack

    NP.Health.Build(self)
    NP.Cast.Build(self)
    NP.Target.Build(self)
    NP.Extras.Build(self)
end

-- ---------------------------------------------------------------------------
-- Static appearance: everything that only changes when a setting changes.
-- ---------------------------------------------------------------------------
local function slotAnchor(plate, slot, size, db)
    local h = plate.health
    local top, cfg = db.textSlots.Top, db.iconSlots[slot]
    local nameRoom = (top.element ~= "none") and (top.size + 4) or 2
    local x, y = cfg.x, cfg.y
    if slot == "top" then          return "BOTTOM", h, "TOP", x, nameRoom + y
    elseif slot == "topleft" then  return "BOTTOMLEFT", h, "TOPLEFT", x, nameRoom + y
    elseif slot == "topright" then return "BOTTOMRIGHT", h, "TOPRIGHT", x, nameRoom + y
    elseif slot == "left" then     return "RIGHT", h, "LEFT", -2 + x, y
    elseif slot == "right" then    return "LEFT", h, "RIGHT", 2 + x, y
    end
    return "TOP", plate.cast or h, "BOTTOM", x, -2 + y
end

local function placeIcon(plate, tex, slot, db)
    tex:ClearAllPoints()
    if slot == "none" or not slot then tex:Hide(); tex.slotted = false; return end
    local size = db.iconSlots[slot].size
    tex:SetSize(size, size)
    tex:SetPoint(slotAnchor(plate, slot, size, db))
    tex.slotted = true
end

function Plate:ApplyAppearance()
    local db = NP.db()
    self.gen = NP.gen
    local w, h = db.healthBarWidth, db.healthBarHeight
    self:SetSize(w, h)

    self.health:SetStatusBarTexture(ns.MediaStatusbar(db.healthBarTexture, WHITE))
    local bg = db.bgColor
    self.healthBG:SetColorTexture(bg.r, bg.g, bg.b, db.bgAlpha)

    local bc = db.borderColor
    ns.LayoutEdges(self.border, self.borderHost, db.showBorder and db.borderSize or 0, bc.r, bc.g, bc.b, 1)

    -- text slots
    local font = ns.ModuleFontPath("nameplates")
    for _, slot in ipairs(TEXT_SLOTS) do
        local fs = self.texts[slot]
        local cfg = db.textSlots[slot]
        local element, col, x, y = cfg.element, cfg.color, cfg.x, cfg.y
        fs:SetFont(font, cfg.size, "OUTLINE")
        fs:SetTextColor(col.r, col.g, col.b)
        fs:ClearAllPoints()
        fs:SetWordWrap(false)
        fs:SetWidth(0)
        if slot == "Top" then
            fs:SetPoint("BOTTOM", self.health, "TOP", x, 2 + y)
            fs:SetJustifyH("CENTER")
        elseif slot == "Right" then
            fs:SetPoint("RIGHT", self.health, "RIGHT", -3 + x, y)
            fs:SetJustifyH("RIGHT")
        elseif slot == "Left" then
            fs:SetPoint("LEFT", self.health, "LEFT", 3 + x, y)
            fs:SetJustifyH("LEFT")
        else
            fs:SetPoint("CENTER", self.health, "CENTER", x, y)
            fs:SetJustifyH("CENTER")
        end
        if NAME_FAMILY[element] then
            fs:SetWidth(w * db.enemyNameWidthPct / 100)
            fs:SetWordWrap(db.enemyNameWrap)
            fs:SetMaxLines(db.enemyNameWrap and 2 or 1)
        end
        fs:SetShown(element ~= "none")
        fs.element = element
    end

    -- icon slots
    placeIcon(self, self.icons.raidMarker, db.raidMarkerPos, db)
    placeIcon(self, self.icons.classification, db.classificationSlot, db)
    local nr = self.icons.nameRaid
    nr:ClearAllPoints()
    nr:SetSize(db.nameRaidMarkerSize, db.nameRaidMarkerSize)
    nr:SetPoint("RIGHT", self.texts.Top, "LEFT", -2, 0)

    -- stacking bounds: name + bar + cast bar, scaled by the spacing setting
    local castH = db.castBarHeight
    local nameSize = db.textSlots.Top.size
    local total = (4 + nameSize + h + castH) * db.stackSpacingScale / 100
    self.stack:ClearAllPoints()
    self.stack:SetSize(w, total)
    self.stack:SetPoint("TOP", self.health, "TOP", 0, (nameSize + 4) * db.stackSpacingScale / 100)

    self.lastR = nil        -- a new bar texture may come without the colour
    NP.Auras.ApplyAppearance(self)
    NP.Health.ApplyAppearance(self)
    NP.Cast.ApplyAppearance(self)
    NP.Target.ApplyAppearance(self)
    NP.Extras.ApplyAppearance(self)
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------
local HEALTH_ELEMENTS = {
    healthPercent = true, healthPercentNoSign = true, healthNumber = true,
    healthPctNum = true, healthNumPct = true, healthPctNumDash = true, healthNumPctDash = true,
}
NP.HEALTH_ELEMENTS = HEALTH_ELEMENTS

local function levelText(unit)
    local lvl = ns.Num(UnitEffectiveLevel(unit), nil)
    if not lvl or lvl < 0 then return "??", nil end
    return tostring(lvl), lvl
end

function Plate:UpdateTexts()
    local unit = self.unit
    if not unit then return end
    local db = NP.db()
    local name = UnitName(unit)          -- may be secret: only ever handed on
    local hasName = ns.Exists(name)
    for _, slot in ipairs(TEXT_SLOTS) do
        local fs = self.texts[slot]
        local element = fs.element
        if element == "enemyName" then
            if hasName then fs:SetText(name) else fs:SetText("") end
        elseif element == "level" then
            local text, lvl = levelText(unit)
            fs:SetText(text)
            local col = db.textSlots[slot].color
            local r, g, b = col.r, col.g, col.b
            if db.levelDifficultyColor and lvl and GetCreatureDifficultyColor then
                local dc = GetCreatureDifficultyColor(lvl)
                if dc then r, g, b = dc.r, dc.g, dc.b end
            end
            fs:SetTextColor(r, g, b)
        elseif element == "levelName" then
            if hasName then fs:SetFormattedText("%s | %s", levelText(unit), name) else fs:SetText("") end
        elseif element == "nameLevel" then
            if hasName then fs:SetFormattedText("%s | %s", name, (levelText(unit))) else fs:SetText("") end
        end
    end
    NP.Colors.Name(self)
    NP.Health.UpdateText(self)
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------
local CLASSIFICATION_ATLAS = {
    elite     = "nameplates-icon-elite-gold",
    worldboss = "nameplates-icon-elite-gold",
    rareelite = "nameplates-icon-elite-silver",
    rare      = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Rare-Star",
}

function Plate:UpdateRaidMarker()
    local unit = self.unit
    if not unit then return end
    local db = NP.db()
    local idx = GetRaidTargetIndex(unit)        -- secret: existence by type only
    local has = ns.Exists(idx)
    local main, inline = self.icons.raidMarker, self.icons.nameRaid
    if has and main.slotted then
        SetRaidTargetIconTexture(main, idx)
        main:Show()
    else
        main:Hide()
    end
    if has and db.nameRaidMarkerEnabled and db.textSlots.Top.element ~= "none" then
        SetRaidTargetIconTexture(inline, idx)
        inline:Show()
    else
        inline:Hide()
    end
end

function Plate:UpdateClassification()
    local tex = self.icons.classification
    local unit = self.unit
    if not unit or not tex.slotted then tex:Hide(); return end
    local db = NP.db()
    if NP.Extras.IsQuestMob(unit) then
        -- SetTexture replaces whatever atlas was on it; clearing first is not
        -- worth the risk of SetAtlas(nil) being refused.
        tex:SetTexture(NP.QUEST_ICON)
        tex:Show()
        return
    end
    if NP.ctx.inInstance and not db.classificationShowInInstances then tex:Hide(); return end
    local class = UnitClassification(unit)
    local atlas = ns.CanRead(class) and CLASSIFICATION_ATLAS[class]
    if atlas then
        tex:SetTexture(nil)
        tex:SetAtlas(atlas)
        tex:Show()
    else
        tex:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- On and off a unit
-- ---------------------------------------------------------------------------
local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED",
                      "UNIT_NAME_UPDATE", "UNIT_THREAT_LIST_UPDATE" }

-- Everything the plate shows, from scratch. Cheap enough to be the answer to
-- "something about this unit changed and I do not know what".
-- The client stacks plates by this frame. It cannot be taken away again (the
-- argument is not nilable), so "off" hands the base plate itself back.
function Plate:ApplyStacking()
    local nameplate = self.nameplate
    if not (nameplate and nameplate.SetStackingBoundsFrame) then return end
    pcall(nameplate.SetStackingBoundsFrame, nameplate, NP.db().stackingEnabled and self.stack or nameplate)
end

function Plate:Refresh()
    if not self.unit then return end
    self.maxValid = false
    self:ApplyStacking()
    NP.Health.Update(self)
    self:UpdateTexts()
    self:UpdateRaidMarker()
    self:UpdateClassification()
    NP.Colors.Apply(self)
    NP.Target.Apply(self)
    NP.Extras.Update(self)
    NP.Cast.Resume(self)
end

function Plate:SetUnit(unit, nameplate)
    self.unit, self.nameplate = unit, nameplate
    self.maxValid = false
    self:SetParent(nameplate)
    self:ClearAllPoints()
    self:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    -- a getter on a Blizzard frame may come back secret
    self:SetFrameLevel(ns.Num(nameplate:GetFrameLevel(), 0) + 1)
    self:SetScale(1)
    self:SetAlpha(1)
    if self.gen ~= NP.gen then self:ApplyAppearance() end

    for _, event in ipairs(UNIT_EVENTS) do
        pcall(self.RegisterUnitEvent, self, event, unit)
    end
    for _, event in ipairs(NP.Cast.EVENTS) do
        pcall(self.RegisterUnitEvent, self, event, unit)
    end
    NP.byNameplate[nameplate] = self
    NP.Auras.Attach(self)

    -- Everything at once, so a recycled plate never shows its last unit; and
    -- once more a frame later, when the unit has settled (name, classification
    -- and attackability can still be missing on the frame a plate appears).
    xpcall(self.Refresh, geterrorhandler(), self)
    self:Show()
    local token = unit
    C_Timer.After(0, function()
        if self.unit == token then self:Refresh() end
    end)
end

function Plate:Clear()
    local nameplate = self.nameplate
    self:UnregisterAllEvents()
    if self.unit then NP.Extras.ForgetQuest(self.unit) end
    NP.Auras.Detach(self)
    NP.Cast.Stop(self, "clear")
    NP.Target.Reset(self)
    NP.Health.Forget(self)
    if nameplate then
        NP.byNameplate[nameplate] = nil
        if nameplate.SetStackingBoundsFrame then
            pcall(nameplate.SetStackingBoundsFrame, nameplate, nameplate)
        end
    end
    -- the focus cast bar has its own height; the next unit must lay it out anew
    if self.isFocus then self.gen = nil end
    for _, fs in pairs(self.texts) do fs:SetText("") end
    for _, tex in pairs(self.icons) do tex:Hide() end
    self.unit, self.nameplate = nil, nil
    self.isTarget, self.isFocus, self.isHover = false, false, false
    if self.executeGlow then self.executeGlow:Hide() end
    if self.comboBar then self.comboBar:Hide() end
    self:Hide()
    self:SetParent(UIParent)
    self:ClearAllPoints()
end
