-- VuloForeverUI / Modules / Bags / BagBar
--
-- The bags themselves, one button each, in a row under the search field:
-- the backpack, the equipped bags, and a free bag slot where one is empty.
-- Switched on and off from the tool row.
--
-- Hover lights the bag's slots in the window, a click shows that bag alone
-- (a second click shows everything again), and a bag is dragged in, out or
-- across the way the client's own bag buttons do it. None of those calls is
-- protected: the client drives them from plain buttons too.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local BagBar = {}
Bags.BagBar = BagBar

local SIZE, GAP = 28, 4

-- The equipment slot a bag sits in. The backpack has none: it is not gear.
local function invSlot(bag)
    if bag == 0 then return nil end
    local ok, id = pcall(C_Container.ContainerIDToInventoryID, bag)
    if ok and type(id) == "number" then return id end
    return nil
end

-- Every bag position there is, filled or not: a slot with nothing in it is
-- where the next bag goes, so it is shown too.
local function bagList()
    local out = { 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) do out[#out + 1] = i end
    local idx = Enum.BagIndex
    if idx and idx.ReagentBag and invSlot(idx.ReagentBag) then out[#out + 1] = idx.ReagentBag end
    return out
end

-- An item on the cursor dropped onto a bag button: into the backpack, or
-- into that bag -- which, when the item is itself a bag, equips it there.
local function drop(bag)
    if bag == 0 then
        PutItemInBackpack()
    else
        local inv = invSlot(bag)
        if inv then PutItemInBag(inv) end
    end
end

local function onEnter(self)
    BagBar.Highlight(self.win, self.bag)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local inv = invSlot(self.bag)
    if not (inv and GameTooltip:SetInventoryItem("player", inv)) then
        GameTooltip:SetText(self.bag == 0 and L["Backpack"] or L["Empty bag slot"], 1, 1, 1)
    end
    GameTooltip:AddLine(L["Click: show only this bag. Drag: move the bag."], 0.6, 0.6, 0.65, true)
    GameTooltip:Show()
end

local function onLeave(self)
    GameTooltip:Hide()
    BagBar.Highlight(self.win, nil)
end

local function onClick(self)
    if CursorHasItem() then drop(self.bag); return end
    local win, key = self.win, "bag:" .. self.bag
    if win.view == key then
        win.view = Bags.db().defaultView or "all"
    else
        win.view = key
    end
    win.Refresh()
end

local function onDragStart(self)
    local inv = invSlot(self.bag)
    if inv then PickupBagFromSlot(inv) end
end

local function onReceiveDrag(self) drop(self.bag) end

local function makeButton(win)
    local b = CreateFrame("Button", nil, win.frame)
    b:SetSize(SIZE, SIZE)
    b:RegisterForDrag("LeftButton")
    local ground = b:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(b)
    ground:SetColorTexture(0.08, 0.08, 0.09, 0.8)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    b.icon = icon
    local count = b:CreateFontString(nil, "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    b.count = count
    -- The action bar's own icon frame, as on the tool row above it.
    local mask = b:CreateMaskTexture()
    mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetAtlas("UI-HUD-ActionBar-IconFrame")
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
    b.border = border
    b:SetHighlightAtlas("UI-HUD-ActionBar-IconFrame-Mouseover", "ADD")
    b:GetHighlightTexture():SetAllPoints(border)
    b.win = win
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnDragStart", onDragStart)
    b:SetScript("OnReceiveDrag", onReceiveDrag)
    return b
end

-- Laid out at the window's left edge from `y` down; returns the height it
-- took, zero when the bar is off.
function BagBar.Layout(win, left, y)
    win.bagButtons = win.bagButtons or {}
    local shown = win.key == "bags" and win.showBagBar
    local list = shown and bagList() or {}

    for i, bag in ipairs(list) do
        local b = win.bagButtons[i] or makeButton(win)
        win.bagButtons[i] = b
        b.bag = bag
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win.frame, "TOPLEFT", left + (i - 1) * (SIZE + GAP), -y)

        local inv = invSlot(bag)
        if bag == 0 then
            b.icon:SetAtlas("bag-main")
            b.icon:Show()
        else
            local tex = inv and GetInventoryItemTexture("player", inv)
            b.icon:SetTexture(tex)
            -- after the texture: the backpack's atlas set on this button
            -- before carried its own coordinates
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            b.icon:SetShown(tex ~= nil)
        end

        local total = C_Container.GetContainerNumSlots(bag) or 0
        local free = C_Container.GetContainerNumFreeSlots(bag) or 0
        ns.UI.FontFor("bags", b.count, 10, "OUTLINE")
        b.count:SetText(total > 0 and tostring(free) or "")

        local lit = win.view == "bag:" .. bag
        if lit then b.border:SetVertexColor(1, 0.82, 0.3) else b.border:SetVertexColor(1, 1, 1) end
        b:Show()
    end
    for i = #list + 1, #win.bagButtons do win.bagButtons[i]:Hide() end

    if #list == 0 then return 0 end
    return SIZE + 6
end

-- Hovering a bag dims every slot that is not in it; nil puts the window back
-- the way the search left it.
function BagBar.Highlight(win, bag)
    for _, placed in ipairs(win.placed or {}) do
        Bags.Slots.SetFiltered(placed.slot, placed.filtered or (bag ~= nil and placed.bag ~= bag))
    end
end
