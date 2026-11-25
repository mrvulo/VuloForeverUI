-- VuloForeverUI / Modules / QoL / LootRollList
--
-- The rows of the loot roll list (F-81); the data is LootRoll.lua.
--
-- One row per roll: the item's icon with its count, the name in its quality
-- colour with "BoE" beside it, a timer bar under the name, and on the right the
-- roll buttons -- need, greed (transmog when the item allows it), disenchant
-- only when possible, pass -- each with how many players picked it. The art is
-- the client's own loot roll atlases (lootroll-toast-icon-*).
--
-- The list frame is one row in size and carries the mover; the rows hang
-- from it downwards or upwards. One throttled OnUpdate runs the timers, and
-- only while there are rows.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local LR = QoL.LootRoll

local list
local rowsUI = {}
local styleGen = 0

-- Left to right.
local ORDER = { LR.NEED, LR.GREED, LR.TRANSMOG, LR.DISENCHANT, LR.PASS }

local BUTTON_ATLAS = {
    [0] = "lootroll-toast-icon-pass",
    [1] = "lootroll-toast-icon-need",
    [2] = "lootroll-toast-icon-greed",
    [3] = "lootroll-toast-icon-disenchant",
    [4] = "lootroll-toast-icon-transmog",
}

-- The small icon for a player's choice, by EncounterLootDropRollState.
local STATE_ATLAS = {
    [0] = "lootroll-icon-need", [1] = "lootroll-icon-need",
    [2] = "lootroll-icon-transmog", [3] = "lootroll-icon-greed",
    [5] = "lootroll-icon-pass",
}

local function typeName(t)
    if t == LR.NEED then return NEED end
    if t == LR.GREED then return GREED end
    if t == LR.DISENCHANT then return ROLL_DISENCHANT end
    if t == LR.TRANSMOG then return TRANSMOGRIFY end
    return PASS
end

local function atlasMarkup(atlas)
    if not (atlas and CreateAtlasMarkup) then return "" end
    return CreateAtlasMarkup(atlas, 14, 14)
end

local function clock(ms)
    local s = math.max(0, math.floor((ms or 0) / 1000))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function classColor(token)
    local c = type(token) == "string" and ns.CanRead(token) and ns.ClassColor and ns.ClassColor(token)
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

-- ---------------------------------------------------------- tooltips --

-- One player as a tooltip line: the choice, the name in class colour, the
-- winner marked; the roll number on the right once it is known.
local function addPlayer(p)
    local state = ns.Num(p.state)
    local mark = STATE_ATLAS[state] and atlasMarkup(STATE_ATLAS[state]) or "?"
    local left = mark .. " " .. LR.Name(p.playerName)
    if ns.CanRead(p.isWinner) and p.isWinner then
        left = left .. " " .. atlasMarkup("lootroll-icon-checkmark")
    end
    local roll = ns.Num(p.roll)
    local r, g, b = classColor(p.playerClass)
    GameTooltip:AddDoubleLine(left, roll and tostring(roll) or "", r, g, b, 1, 1, 1)
end

local function rowEnter(self)
    local r = self.roll
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(r.name, LR.QualityColor(r.quality))
    local players = LR.Players(r)
    if players and #players > 0 then
        for _, p in ipairs(players) do addPlayer(p) end
    else
        GameTooltip:AddLine(L["The loot history does not know this roll."], 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function iconEnter(self)
    local r = self:GetParent().roll
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if r.test or type(r.id) ~= "number" then
        GameTooltip:SetText(r.name, LR.QualityColor(r.quality))
    else
        GameTooltip:SetLootRollItem(r.id)
    end
    GameTooltip:Show()
end

local function iconClick(self)
    local r = self:GetParent().roll
    if r and r.link and HandleModifiedItemClick then HandleModifiedItemClick(r.link) end
end

local function buttonEnter(self)
    local r = self:GetParent().roll
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(typeName(self.rollType))
    if self.reason then GameTooltip:AddLine(self.reason, 1, 0.3, 0.3, true) end
    local slot = LR.SlotOfType(self.rollType)
    local players = slot and LR.Players(r)
    if players then
        for _, p in ipairs(players) do
            if LR.SlotOfState(p.state) == slot then
                GameTooltip:AddLine(LR.Name(p.playerName), classColor(p.playerClass))
            end
        end
    end
    GameTooltip:Show()
end

local function buttonClick(self)
    local r = self:GetParent().roll
    if r then LR.Roll(r, self.rollType) end
end

-- -------------------------------------------------------------- rows --

local function makeButton(row, t)
    local b = CreateFrame("Button", nil, row)
    b.rollType = t
    local a = BUTTON_ATLAS[t]
    b:SetNormalAtlas(a .. "-up")
    b:SetPushedAtlas(a .. "-down")
    b:SetHighlightAtlas(a .. "-highlight", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b:SetMotionScriptsWhileDisabled(true)
    b:SetScript("OnClick", buttonClick)
    b:SetScript("OnEnter", buttonEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    return b
end

local function makeRow()
    local row = CreateFrame("Frame", nil, list)
    row:EnableMouse(true)
    row:SetScript("OnEnter", rowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetColorTexture(0, 0, 0, 0.6)
    row.edges = ns.MakeEdges(row, "BORDER")

    local icon = CreateFrame("Button", nil, row)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints(icon)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.count = icon:CreateFontString(nil, "OVERLAY")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.sep = icon:CreateTexture(nil, "OVERLAY")
    icon.sep:SetColorTexture(0, 0, 0, 1)
    icon.sep:SetPoint("TOPLEFT", icon, "TOPRIGHT", 0, 0)
    icon.sep:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 0, 0)
    icon:SetScript("OnEnter", iconEnter)
    icon:SetScript("OnLeave", GameTooltip_Hide)
    icon:SetScript("OnClick", iconClick)
    row.icon = icon

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.boe = row:CreateFontString(nil, "OVERLAY")
    row.boe:SetJustifyH("RIGHT")

    local bar = CreateFrame("StatusBar", nil, row)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints(bar)
    bar.bg:SetColorTexture(1, 1, 1, 0.08)
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.result = bar:CreateFontString(nil, "OVERLAY")
    bar.result:SetPoint("LEFT", bar, "LEFT", 3, 0)
    bar.result:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.result:SetJustifyH("LEFT")
    bar.result:SetWordWrap(false)
    row.bar = bar

    row.btn = {}
    for _, t in ipairs(ORDER) do row.btn[t] = makeButton(row, t) end
    return row
end

local function styleRow(row, d)
    local h, fs = d.iconSize, d.fontSize
    local font, outline = QoL.Font(), QoL.Outline()
    local small = math.max(8, fs - 2)
    row:SetSize(d.width, h)
    ns.LayoutEdges(row.edges, row, 1, 0, 0, 0, 1, 0)

    row.icon:SetSize(h, h)
    row.icon.sep:SetWidth(ns:Pixel(row.icon, 1))
    row.icon.count:SetFont(font, math.max(8, fs - 1), "OUTLINE")
    row.name:SetFont(font, fs, outline)
    row.boe:SetFont(font, small, outline)
    row.bar.time:SetFont(font, small, outline)
    row.bar.result:SetFont(font, small, outline)
    row.bar:SetStatusBarTexture(ns.MediaStatusbar(d.barTexture))

    local bs = math.max(14, math.floor(h * 0.62))
    for _, b in pairs(row.btn) do
        b:SetSize(bs, bs)
        b.count:SetFont(font, math.max(8, fs - 3), "OUTLINE")
    end
    row.btnSize = bs
    row.barH = math.max(6, math.floor(h * 0.36))
    row.btnKey = nil      -- the buttons are placed again with the new size
    row.gen = styleGen
end

-- The buttons from the right edge, the name and the bar up to them. Only
-- re-anchored when the set changes: re-anchoring under the mouse would fire
-- OnLeave/OnEnter and blink the tooltip.
local function placeButtons(row, shown)
    local key = ""
    for _, t in ipairs(ORDER) do key = key .. (shown[t] and "1" or "0") end
    if row.btnKey == key then return end
    row.btnKey = key
    local x, bs, pad = -4, row.btnSize, 4
    for i = #ORDER, 1, -1 do
        local t = ORDER[i]
        local b = row.btn[t]
        b:ClearAllPoints()
        if shown[t] then
            b:SetPoint("RIGHT", row, "RIGHT", x, 0)
            b:Show()
            x = x - bs - 3
        else
            b:Hide()
        end
    end
    local left = row.icon:GetWidth() + 6
    row.boe:ClearAllPoints()
    row.boe:SetPoint("TOPRIGHT", row, "TOPRIGHT", x - pad + 3, -4)
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", left, -4)
    row.name:SetPoint("RIGHT", row.boe, "LEFT", -4, 0)
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 4)
    row.bar:SetPoint("RIGHT", row, "RIGHT", x - pad + 3, 0)
    row.bar:SetHeight(row.barH)
end

local function updateTimer(row)
    local r = row.roll
    if not r or r.doneAt then return end
    local left = LR.TimeLeft(r)
    row.bar:SetValue(left)
    row.bar.time:SetText(clock(left))
end

local function fillRow(row, r)
    row.roll = r
    row.icon.tex:SetTexture(r.texture)
    row.icon.count:SetText((r.count or 1) > 1 and tostring(r.count) or "")
    local cr, cg, cb = LR.QualityColor(r.quality)
    row.name:SetText(r.name)
    row.name:SetTextColor(cr, cg, cb)
    row.boe:SetText(r.boe and L["BoE"] or "")

    local bar = row.bar
    bar:SetMinMaxValues(0, r.duration or 1)
    if r.doneAt then
        local text, won = LR.ResultText(r)
        bar:SetValue(r.duration or 1)
        if won then bar:SetStatusBarColor(0.2, 0.75, 0.3) else bar:SetStatusBarColor(0.45, 0.45, 0.45) end
        bar.result:SetText(text)
        bar.result:Show()
        bar.time:Hide()
    else
        bar:SetStatusBarColor(cr, cg, cb)
        bar.result:Hide()
        bar.time:Show()
        updateTimer(row)
    end

    local shown = {
        [LR.NEED] = true, [LR.PASS] = true,
        [LR.GREED] = not r.canTransmog, [LR.TRANSMOG] = r.canTransmog,
        [LR.DISENCHANT] = r.canDE,
    }
    local can = {
        [LR.NEED] = r.canNeed, [LR.GREED] = r.canGreed, [LR.TRANSMOG] = r.canTransmog,
        [LR.DISENCHANT] = r.canDE, [LR.PASS] = true,
    }
    placeButtons(row, shown)

    local counts = LR.Counts(r)
    local decided = r.closed or r.doneAt or r.choice ~= nil
    for t, b in pairs(row.btn) do
        local enabled, lit = can[t] and true or false, false
        if decided then enabled, lit = false, r.choice == t end
        b:SetEnabled(enabled)
        local dim = not enabled and not lit
        local nt = b:GetNormalTexture()
        if nt then nt:SetDesaturated(dim) end
        b:SetAlpha(dim and 0.35 or 1)
        if lit then b:LockHighlight() else b:UnlockHighlight() end
        b.reason = nil
        if not can[t] then
            local why = (t == LR.NEED and r.reasonNeed) or ((t == LR.GREED) and r.reasonGreed) or nil
            b.reason = why and _G["LOOT_ROLL_INELIGIBLE_REASON" .. why] or nil
        end
        local slot = LR.SlotOfType(t)
        local n = counts and slot and counts[slot]
        b.count:SetText((n and n > 0) and tostring(n) or "")
    end
end

-- --------------------------------------------------------------- list --

local tick = 0
local function onUpdate(_, elapsed)
    tick = tick + elapsed
    if tick < 0.1 then return end
    tick = 0
    if LR.Expire() then LR.Layout(); return end
    for _, row in ipairs(rowsUI) do
        if row:IsShown() then updateTimer(row) end
    end
end

local function build()
    if list then return end
    local d = LR.db()
    list = CreateFrame("Frame", nil, UIParent)
    list:SetFrameStrata("MEDIUM")
    list:SetSize(d.width, d.iconSize)
    list.mover = ns:CreateMover(list, {
        key      = "qol_lootroll",
        label    = L["Loot roll list"],
        db       = d,
        module   = "qol",
        width    = d.width,
        height   = d.iconSize,
        scalable = true,
        -- empty between rolls: our edit mode shows the examples
        editPreview = function(on) LR.EditPreview(on) end,
    })
    ns:ApplyMover(list.mover)
end

function LR.Layout()
    if not list then return end
    local d = LR.db()
    local h, gap, up = d.iconSize, d.spacing, d.grow == "UP"
    local rolls = LR.rolls
    for i, r in ipairs(rolls) do
        local row = rowsUI[i]
        if not row then row = makeRow(); rowsUI[i] = row end
        if row.gen ~= styleGen then styleRow(row, d) end
        local place = (up and "U" or "D") .. i .. ":" .. h .. ":" .. gap
        if row.place ~= place then
            row.place = place
            row:ClearAllPoints()
            local off = (i - 1) * (h + gap)
            if up then
                row:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, off)
            else
                row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -off)
            end
        end
        fillRow(row, r)
        row:Show()
    end
    for i = #rolls + 1, #rowsUI do
        rowsUI[i]:Hide()
        rowsUI[i].roll = nil
    end
    list:SetScript("OnUpdate", (#rolls > 0) and onUpdate or nil)
end

-- Size, look and place from the settings; every row is styled again.
function LR.Style()
    build()
    local d = LR.db()
    styleGen = styleGen + 1
    list:SetSize(d.width, d.iconSize)
    for _, row in ipairs(rowsUI) do row.place = nil end
    if list.mover then
        -- re-pointed for a profile switch
        list.mover.opts.db = d
        list.mover.opts.width, list.mover.opts.height = d.width, d.iconSize
        ns:RefreshMoverGeometry(list.mover)
        ns:ApplyMover(list.mover)
    end
    list:Show()
    LR.Layout()
end

function LR.HideList()
    if not list then return end
    for _, row in ipairs(rowsUI) do row:Hide(); row.roll = nil end
    list:SetScript("OnUpdate", nil)
    list:Hide()
end
