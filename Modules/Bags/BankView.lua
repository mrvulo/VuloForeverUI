-- VuloForeverUI / Modules / Bags / BankView
--
-- The bank, looked at from anywhere.
--
-- WHY IT IS A PICTURE AND NOT THE BANK
--
-- The client only hands out the bank's contents while the player is standing
-- at a banker; away from one every bank container reads as empty. So what can
-- be shown from anywhere is what was there at the last visit: a snapshot,
-- taken every time the bank changes during a visit and kept per character.
-- The window says when it was taken, and its slots are plain buttons -- an
-- item cannot be used, moved or taken from a bank that is not open.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local BankView = {}
Bags.BankView = BankView

local PAD, HEADER = 10, 30
local MAX_H = 520

-- ---------------------------------------------------------------- snapshot --

local atBank = false
local queued = false

local function store()
    local char = ns.db and ns.db.char
    if not char then return nil end
    if type(char.bankCache) ~= "table" then char.bankCache = {} end
    return char.bankCache
end

-- The tab names, by container id, from the client's own tab data.
local function tabNames()
    local names = {}
    for i, tab in ipairs(Bags.Sidebar.Tabs()) do
        local id = tab.ID or tab.bankTabID
        if id then names[id] = tab.name or (L["Tab %d"]):format(i) end
    end
    return names
end

function BankView.Snapshot()
    local cache = store()
    if not (cache and atBank) then return end
    local names = tabNames()
    local tabs = {}
    for i, bag in ipairs(Bags.BankBags()) do
        local items = {}
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and type(info.hyperlink) == "string" then
                items[#items + 1] = {
                    link    = info.hyperlink,
                    icon    = info.iconFileID,
                    count   = tonumber(info.stackCount) or 1,
                    quality = info.quality,
                }
            end
        end
        tabs[#tabs + 1] = { name = names[bag] or (L["Tab %d"]):format(i), items = items }
    end
    cache.time = time()
    cache.tabs = tabs
    if BankView.frame and BankView.frame:IsShown() then BankView.Layout() end
end

-- Coalesced: a bank visit fires a burst of bag updates, and one snapshot a
-- moment after the burst reads the settled state.
local function queueSnapshot()
    if queued then return end
    queued = true
    C_Timer.After(0.3, function()
        queued = false
        BankView.Snapshot()
    end)
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "BAG_UPDATE_DELAYED",
    "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED" }) do
    events:RegisterEvent(e)
end
events:SetScript("OnEvent", function(_, event)
    if not (Bags.mod and Bags.mod.active) then return end
    if event == "BANKFRAME_OPENED" then
        atBank = true
        queueSnapshot()
    elseif event == "BANKFRAME_CLOSED" then
        atBank = false
    elseif atBank then
        queueSnapshot()
    end
end)

-- ---------------------------------------------------------------- window --

local function build()
    local db = Bags.db()
    local f = CreateFrame("Frame", "VuloForeverUIBankView", UIParent)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if db.moveWithoutShift or IsShiftKeyDown() then self:StartMoving() end
    end)
    -- Remembered now, in the same shape as the bag windows' own place.
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, dx, dy = self:GetPoint()
        if point then
            Bags.db().bankViewPos = { point = point, relPoint = relPoint or point, x = dx, y = dy }
        end
        if BankView.moverEntry then BankView.moverEntry.sync() end
    end)
    f:Hide()

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.edges = ns.MakeEdges(f, "BORDER")

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
    f.stamp = f:CreateFontString(nil, "OVERLAY")
    f.stamp:SetPoint("LEFT", f.title, "RIGHT", 8, 0)
    f.stamp:SetTextColor(0.55, 0.55, 0.6)
    f.close = ns.UI:CreateCloseX(f, function() f:Hide() end)
    if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, f:GetName()) end

    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
    end)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    f.scroll, f.content = scroll, content

    f.empty = content:CreateFontString(nil, "OVERLAY")
    f.empty:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    f.empty:SetTextColor(0.7, 0.7, 0.75)

    f.heads, f.slots = {}, {}
    BankView.frame = f
    f:SetScale(db.scale or 1)
    BankView.Place()
    return f
end

-- The saved place, or the corner it has always opened in.
function BankView.Place()
    local f = BankView.frame
    if not f then return end
    local store = Bags.db().bankViewPos
    f:ClearAllPoints()
    if type(store) == "table" and type(store.point) == "string" then
        f:SetPoint(store.point, UIParent, store.relPoint or store.point, store.x or 0, store.y or 0)
    else
        f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 40, -120)
    end
    if BankView.moverEntry then BankView.moverEntry.sync() end
end

local function head(f, i)
    local h = f.heads[i]
    if not h then
        h = f.content:CreateFontString(nil, "OVERLAY")
        f.heads[i] = h
    end
    return h
end

local function slot(f, i)
    local s = f.slots[i]
    if s then return s end
    s = CreateFrame("Button", nil, f.content)
    s.ground = s:CreateTexture(nil, "BACKGROUND")
    s.ground:SetAllPoints(s)
    s.ground:SetColorTexture(0.02, 0.02, 0.03, 0.9)
    s.icon = s:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints(s)
    s.count = s:CreateFontString(nil, "OVERLAY")
    s.count:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", -2, 2)
    s.edges = ns.MakeEdges(s, "OVERLAY")
    s:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        GameTooltip:Show()
    end)
    s:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Shift-click links it into chat, like any item anywhere.
    s:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick("CHATLINK") and ChatFrameUtil and ChatFrameUtil.InsertLink then
            ChatFrameUtil.InsertLink(self.link)
        end
    end)
    f.slots[i] = s
    return s
end

function BankView.Layout()
    local f = BankView.frame
    if not f then return end
    local db = Bags.db()
    local cache = store() or {}
    local size = db.slotSize or 37
    local gap = db.spacing or 4
    local columns = math.max(1, db.columns or 12)
    local gridW = columns * size + (columns - 1) * gap

    f.bg:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.97)
    ns.LayoutEdges(f.edges, f, db.borderSize or 1,
        db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.12, 0)
    ns.UI.FontFor("bags", f.title, 13, nil)
    f.title:SetText(L["Bank"])
    ns.UI.FontFor("bags", f.stamp, 11, nil)
    f.stamp:SetText(cache.time and (L["as of %s"]):format(date("%d.%m. %H:%M", cache.time)) or "")

    local y, hi, si = 0, 0, 0
    local tabs = cache.tabs or {}
    ns.UI.FontFor("bags", f.empty, 12, nil)
    if #tabs == 0 then
        f.empty:SetWidth(gridW)
        f.empty:SetText(L["Visit a banker once; the bank is remembered from then on."])
        f.empty:Show()
        y = 40
    else
        f.empty:Hide()
    end

    for _, tab in ipairs(tabs) do
        hi = hi + 1
        local h = head(f, hi)
        ns.UI.FontFor("bags", h, db.categoryTitleSize or 11, nil)
        h:SetTextColor(0.65, 0.65, 0.7)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        h:SetFormattedText("%s (%d)", tab.name or "", #tab.items)
        h:Show()
        y = y + (db.categoryTitleSize or 11) + 7

        local column = 0
        for _, item in ipairs(tab.items) do
            si = si + 1
            local s = slot(f, si)
            s:SetSize(size, size)
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", f.content, "TOPLEFT", column * (size + gap), -y)
            s.link = item.link
            s.icon:SetTexture(item.icon or 134400)
            local zoom = math.max(0, math.min(0.2, db.iconZoom or 0))
            s.icon:SetTexCoord(zoom, 1 - zoom, zoom, 1 - zoom)
            ns.UI.FontFor("bags", s.count, db.countSize or 11, "OUTLINE")
            s.count:SetText((item.count or 1) > 1 and item.count or "")
            local r, g, b = 0.25, 0.25, 0.27
            if db.qualityBorder ~= false and type(item.quality) == "number" and item.quality >= 2
                and C_Item.GetItemQualityColor then
                local ok, qr, qg, qb = pcall(C_Item.GetItemQualityColor, item.quality)
                if ok and type(qr) == "number" then r, g, b = qr, qg, qb end
            end
            ns.LayoutEdges(s.edges, s, 1, r, g, b, 1, -1)
            s:Show()
            column = column + 1
            if column >= columns then column = 0; y = y + size + gap end
        end
        if column > 0 then y = y + size + gap end
        y = y + 4
    end
    for i = hi + 1, #f.heads do f.heads[i]:Hide() end
    for i = si + 1, #f.slots do f.slots[i]:Hide() end

    f.content:SetSize(gridW, math.max(1, y))
    f:SetScale(db.scale or 1)
    f:SetSize(gridW + PAD * 2, math.min(MAX_H, y + HEADER + PAD))
end

function BankView.Toggle()
    local f = BankView.frame or build()
    BankView.previewing, BankView.previewClose = nil, nil
    if f:IsShown() then f:Hide(); return end
    f:Show()
    BankView.Layout()
end

-- A box in our edit mode (Window.AttachMover). The window is only on screen
-- when asked for, so while the edit mode is open it shows the last snapshot.
local function preview(on)
    local f = BankView.frame
    if not f then return end
    if on then
        BankView.previewClose = nil
        if f:IsShown() or not (Bags.mod and Bags.mod.active) then return end
        f:Show()
        BankView.Layout()
        BankView.previewing = true
    elseif BankView.previewing then
        BankView.previewing = nil
        if not f:IsShown() then return end
        if Bags.WindowFactory.Locked(f) then
            BankView.previewClose = true
            Bags.WindowFactory.AfterCombat(function()
                if BankView.previewClose then
                    BankView.previewClose = nil
                    f:Hide()
                end
            end)
        else
            f:Hide()
        end
    end
end

-- Built up front (hidden) so the box exists before the edit mode's snapshot.
function BankView.EnsureMover()
    if BankView.moverEntry then return end
    local f = BankView.frame or build()
    BankView.moverEntry = Bags.WindowFactory.AttachMover(f, {
        key          = "bags_bankview",
        label        = L["Bank (last visit)"],
        storeKey     = "bankViewPos",
        defaultPoint = "TOPLEFT",
        place        = BankView.Place,
        preview      = preview,
    })
end

function BankView.Release()
    if BankView.frame then BankView.frame:Hide() end
end
