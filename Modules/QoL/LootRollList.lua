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
local BAR_GAP = 6          -- between the line of buttons and the timer bar
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
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, 0)
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
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    row.edges = ns.MakeEdges(row, "BORDER")

    local icon = CreateFrame("Button", nil, row)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 3, -3)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints(icon)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.count = icon:CreateFontString(nil, "OVERLAY")
    icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    -- a frame in the item's quality colour, like the bag slots
    icon.edges = ns.MakeEdges(icon, "OVERLAY")
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
    -- a bright edge where the time runs out
    bar.spark = bar:CreateTexture(nil, "OVERLAY")
    bar.spark:SetColorTexture(1, 1, 1, 0.9)
    bar.spark:SetBlendMode("ADD")
    bar.time = bar:CreateFontString(nil, "OVERLAY")
    bar.time:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.result = bar:CreateFontString(nil, "OVERLAY")
    bar.result:SetPoint("LEFT", bar, "LEFT", 3, 0)
    bar.result:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    bar.result:SetJustifyH("CENTER")
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

    row.icon:SetSize(h - 6, h - 6)
    ns.LayoutEdges(row.icon.edges, row.icon, 1, 0, 0, 0, 1, 0)
    row.icon.count:SetFont(font, math.max(8, fs - 1), "OUTLINE")
    row.name:SetFont(font, fs, outline)
    row.boe:SetFont(font, small, outline)
    row.bar.time:SetFont(font, small, outline)
    row.bar.result:SetFont(font, small, outline)
    row.bar:SetStatusBarTexture(ns.MediaStatusbar(d.barTexture))

    -- a slim bar along the bottom; name and buttons share the line above it
    -- a clear gap between the buttons and the bar: the counts and the time
    -- sit in it instead of on top of each other
    row.barH = math.max(5, math.floor(h * 0.2))
    row.topH = h - row.barH - 3 - BAR_GAP - 3
    local bs = math.max(14, math.min(row.topH, math.floor(h * 0.6)))
    for _, b in pairs(row.btn) do
        b:SetSize(bs, bs)
        b.count:SetFont(font, math.max(8, fs - 3), "OUTLINE")
    end
    row.btnSize = bs
    row.bar.spark:SetSize(ns:Pixel(row.bar, 2), row.barH + 4)
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
    local mid = -(3 + row.topH / 2)       -- the middle of the line above the bar
    for i = #ORDER, 1, -1 do
        local t = ORDER[i]
        local b = row.btn[t]
        b:ClearAllPoints()
        if shown[t] then
            b:SetPoint("RIGHT", row, "TOPRIGHT", x, mid)
            b:Show()
            x = x - bs - 3
        else
            b:Hide()
        end
    end
    local left = row.icon:GetWidth() + 10
    row.boe:ClearAllPoints()
    row.boe:SetPoint("RIGHT", row, "TOPRIGHT", x - pad + 3, mid)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "TOPLEFT", left, mid)
    row.name:SetPoint("RIGHT", row.boe, "LEFT", -4, 0)
    -- the bar runs the whole width, under the buttons too
    row.bar:ClearAllPoints()
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", left, 3)
    row.bar:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.bar:SetHeight(row.barH)
end

local function updateTimer(row)
    local r = row.roll
    if not r or r.doneAt then return end
    local left = LR.TimeLeft(r)
    row.bar:SetValue(left)
    row.bar.time:SetText(clock(left))
    local dur = r.duration or 1
    local frac = dur > 0 and math.min(1, math.max(0, left / dur)) or 0
    row.bar.spark:ClearAllPoints()
    row.bar.spark:SetPoint("CENTER", row.bar, "LEFT", row.bar:GetWidth() * frac, 0)
    row.bar.spark:SetShown(frac > 0 and frac < 1)
end

local function fillRow(row, r)
    row.roll = r
    row.icon.tex:SetTexture(r.texture)
    row.icon.count:SetText((r.count or 1) > 1 and tostring(r.count) or "")
    local cr, cg, cb = LR.QualityColor(r.quality)
    for _, t in pairs(row.icon.edges) do t:SetColorTexture(cr, cg, cb, 1) end
    row.name:SetText(r.name)
    row.name:SetTextColor(cr, cg, cb)
    row.boe:SetText(r.boe and L["BoE"] or "")

    local bar = row.bar
    bar:SetMinMaxValues(0, r.duration or 1)
    if r.doneAt then
        local text, won = LR.ResultText(r)
        bar:SetValue(r.duration or 1)
        if won then bar:SetStatusBarColor(0.2, 0.75, 0.3) else bar:SetStatusBarColor(0.45, 0.45, 0.45) end
        bar.bg:SetColorTexture(1, 1, 1, 0.08)
        bar.spark:Hide()
        bar.result:SetText(text)
        bar.result:Show()
        bar.time:Hide()
    else
        bar:SetStatusBarColor(cr, cg, cb)
        bar.bg:SetColorTexture(cr * 0.35, cg * 0.35, cb * 0.35, 0.6)
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

-- ----------------------------------------------------------- header --
--
-- A strip on the anchor side of the list: how many rolls are open, a button
-- that folds the rows away (and back), and one that hides the list until the
-- next roll arrives. Both last for the session only.

local HEAD = 18

local function headTip(self, text, sub)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    if sub then GameTooltip:AddLine(sub, 1, 1, 1, true) end
    GameTooltip:Show()
end

local function toggleCollapsed()
    LR.collapsed = not LR.collapsed or nil
    LR.Layout()
end

-- The header moves the list freely; the place is saved through the mover,
-- so edit mode and the profile see the same spot.
local function dragStart()
    list:SetMovable(true)
    list:SetClampedToScreen(true)
    list:StartMoving()
end

local function dragStop()
    list:StopMovingOrSizing()
    list:SetUserPlaced(false)
    list.head.dragEnd = GetTime()
    local x, y = ns:GetCenterOffsets(list)
    if x and list.mover then
        ns:MoverSetCenter(list.mover, math.floor(x + 0.5), math.floor(y + 0.5))
    end
end

local function headClick(self)
    -- the release that ends a drag is no click
    if self.dragEnd and GetTime() - self.dragEnd < 0.2 then return end
    toggleCollapsed()
end

local function buildHead()
    local head = CreateFrame("Button", nil, list)
    head:SetHeight(HEAD)
    local bg = head:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(head)
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.85)
    head.edges = ns.MakeEdges(head, "BORDER")
    head.title = head:CreateFontString(nil, "OVERLAY")
    head.title:SetPoint("LEFT", head, "LEFT", 6, 0)
    head.title:SetJustifyH("LEFT")
    head:SetScript("OnClick", headClick)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", dragStart)
    head:SetScript("OnDragStop", dragStop)
    head:SetScript("OnEnter", function(self)
        headTip(self, L["Loot roll list"], L["Drag to move the list, click to fold it."])
    end)
    head:SetScript("OnLeave", GameTooltip_Hide)

    local close = ns.UI:CreateCloseX(head, function()
        LR.hidden = true
        GameTooltip_Hide()
        LR.Layout()
    end, "box")
    close:ClearAllPoints()
    close:SetSize(HEAD - 4, HEAD - 4)
    close:SetPoint("RIGHT", head, "RIGHT", -2, 0)
    close:HookScript("OnEnter", function(self)
        headTip(self, CLOSE, L["Hides the list until the next roll. A roll left open counts as pass when its time runs out."])
    end)
    close:HookScript("OnLeave", GameTooltip_Hide)
    head.close = close

    local min = CreateFrame("Button", nil, head)
    min:SetSize(HEAD - 4, HEAD - 4)
    min:SetPoint("RIGHT", close, "LEFT", -3, 0)
    local mbg = min:CreateTexture(nil, "BACKGROUND")
    mbg:SetAllPoints(min)
    mbg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
    min.edges = ns.MakeEdges(min, "BORDER")
    min.text = min:CreateFontString(nil, "OVERLAY")
    min.text:SetPoint("CENTER", min, "CENTER", 0, 1)
    min:SetScript("OnClick", toggleCollapsed)
    min:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        headTip(self, LR.collapsed and L["Expand"] or L["Minimize"])
    end)
    min:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.8, 0.8, 0.8)
        GameTooltip_Hide()
    end)
    head.min = min
    return head
end

local function layoutHead(d, n, up)
    local head = list.head
    if n == 0 or LR.hidden then head:Hide(); return end
    local font, outline = QoL.Font(), QoL.Outline()
    head:SetWidth(d.width)
    ns.LayoutEdges(head.edges, head, 1, 0, 0, 0, 1, 0)
    ns.LayoutEdges(head.min.edges, head.min, 1, 0.32, 0.32, 0.36, 1, 0)
    head.title:SetFont(font, math.max(9, d.fontSize - 2), outline)
    head.title:SetTextColor(0.85, 0.85, 0.85)
    head.title:SetText(L["Loot rolls (%d)"]:format(n))
    head.min.text:SetFont(font, 14, outline)
    head.min.text:SetTextColor(0.8, 0.8, 0.8)
    head.min.text:SetText(LR.collapsed and "+" or "-")
    head:ClearAllPoints()
    if up then
        head:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -d.spacing)
    else
        head:SetPoint("BOTTOMLEFT", list, "TOPLEFT", 0, d.spacing)
    end
    head:Show()
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
    list.head = buildHead()
end

function LR.Layout()
    if not list then return end
    local d = LR.db()
    local h, gap, up = d.iconSize, d.spacing, d.grow == "UP"
    local rolls = LR.rolls
    layoutHead(d, #rolls, up)
    -- folded or closed: the rows wait, their timers and endings run on
    local shownRows = (LR.hidden or LR.collapsed) and 0 or #rolls
    for i = 1, shownRows do
        local r = rolls[i]
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
    for i = shownRows + 1, #rowsUI do
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
