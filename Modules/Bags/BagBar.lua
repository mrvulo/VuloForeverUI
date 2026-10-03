-- VuloForeverUI / Modules / Bags / BagBar
--
-- The bags themselves, one button each, in a row under the search field:
-- the backpack, the equipped bags, and a free bag slot where one is empty.
-- In the bank the same row holds one button per bank tab, then the tabs that
-- are bought but hold no bag yet, then the ones still for sale. Switched on
-- and off from the tool row.
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

-- Where the bag that makes up a bank tab sits: the client keeps the bank's
-- bags as items in a container of their own, one slot per tab. The first tab
-- is the bank itself and has no bag.
local function bankBagSlot(bag)
    local idx = Enum.BagIndex
    if not (idx and idx.Characterbanktab and idx.CharacterBankTab_1) then return end
    local n = bag - idx.CharacterBankTab_1 + 1
    if n > 1 then return idx.Characterbanktab, n end
end

local function bankBagIcon(bag)
    local container, slot = bankBagSlot(bag)
    if not container then return end
    local info = C_Container.GetContainerItemInfo(container, slot)
    return info and info.iconFileID
end

-- A tab nobody gave an icon carries the question mark; that is no icon.
local function tabIcon(tab)
    local icon = tab and tab.icon
    if icon == nil or icon == 0 or icon == "" or icon == QUESTION_MARK_ICON or icon == 134400 then return end
    if type(icon) == "string" and icon:lower():find("questionmark", 1, true) then return end
    return icon
end

local EMPTY_BAG = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

-- The bank's tabs: the icon of the bag in that tab, else the tab's own icon.
-- A bought tab without a bag is an empty bag slot; every tab not bought yet
-- follows as a slot for sale, only the next of them can be bought.
local function bankList()
    local info = {}
    for _, tab in ipairs(Bags.Sidebar and Bags.Sidebar.Tabs() or {}) do
        if tab.ID then info[tab.ID] = tab end
    end
    local out, filled = {}, {}
    for _, id in ipairs(Bags.BankBags()) do
        local tab = info[id]
        filled[id] = true
        out[#out + 1] = { bag = id, icon = bankBagIcon(id) or tabIcon(tab), name = tab and tab.name }
    end

    local idx = Enum.BagIndex
    local first = idx and idx.CharacterBankTab_1
    local maxTabs = C_Bank and C_Bank.FetchMaxNumBankTabs
        and C_Bank.FetchMaxNumBankTabs(Enum.BankType.Character)
    if not (first and type(maxTabs) == "number") then return out end
    local nextFound = false
    for n = 1, maxTabs do
        local id = first + n - 1
        if filled[id] then
            -- drawn above
        elseif info[id] then
            if bankBagSlot(id) then out[#out + 1] = { bag = id, kind = "empty" } end
        else
            -- tabs are bought in order: the first one missing is the next
            out[#out + 1] = { bag = id, kind = "buy", next = not nextFound }
            nextFound = true
        end
    end
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

-- A bag on the cursor goes into a bank tab the way the client's own bank
-- does it: the tab's bag sits in a container slot, and that slot takes it.
local function bankPickup(bag)
    local container, slot = bankBagSlot(bag)
    if container then C_Container.PickupContainerItem(container, slot) end
end

local function onEnter(self)
    BagBar.Highlight(self.win, self.bag)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if self.win.key == "bank" then
        local container, slot = bankBagSlot(self.bag)
        if self.kind == "empty" then
            GameTooltip:SetText(L["Empty bag slot"], 1, 1, 1)
            GameTooltip:AddLine(L["Drop a bag here to fill this bank tab."], 0.6, 0.6, 0.65, true)
            GameTooltip:Show()
            return
        end
        if not (container and GameTooltip:SetBagItem(container, slot)) then
            GameTooltip:SetText(self.tabName or L["Bank tab"], 1, 1, 1)
        end
        GameTooltip:AddLine(L["Click: show only this tab."], 0.6, 0.6, 0.65, true)
        GameTooltip:Show()
        return
    end
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
    if CursorHasItem() then
        if self.win.key == "bank" then bankPickup(self.bag) else drop(self.bag) end
        return
    end
    if self.kind == "empty" then return end
    local win, key = self.win, "bag:" .. self.bag
    if win.view == key then
        win.view = Bags.db().defaultView or "all"
    else
        win.view = key
    end
    win.Refresh()
end

local function onDragStart(self)
    if self.win.key == "bank" then
        if self.kind ~= "empty" then bankPickup(self.bag) end
        return
    end
    local inv = invSlot(self.bag)
    if inv then PickupBagFromSlot(inv) end
end

local function onReceiveDrag(self)
    if self.win.key == "bank" then bankPickup(self.bag) else drop(self.bag) end
end

-- A slot for sale: what the next one costs, red when it is more than the
-- character carries.
local function onBuyEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(BANK_BAG_PURCHASE or L["Bank tab"], 1, 1, 1)
    local data = self.next and C_Bank.FetchNextPurchasableBankTabData(Enum.BankType.Character)
    if data and type(data.tabCost) == "number" then
        local g = data.canAfford and 1 or 0.1
        GameTooltip:AddLine((COSTS_LABEL or "") .. " " .. GetMoneyString(data.tabCost, true), 1, g, g)
        GameTooltip:AddLine(L["Click: buy this bank slot."], 0.6, 0.6, 0.65, true)
    else
        GameTooltip:AddLine(L["Buy the slots before it first."], 0.6, 0.6, 0.65, true)
    end
    GameTooltip:Show()
end

local function makeButton(win, template)
    local b = CreateFrame("Button", nil, win.frame, template)
    b:SetSize(SIZE, SIZE)
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
    if template then
        -- The client's own script opens its purchase dialog; a click handler
        -- of ours would make that dialog's purchase an addon call.
        b:SetAttribute("overrideBankType", Enum.BankType.Character)
        b:SetScript("OnEnter", onBuyEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    b:RegisterForDrag("LeftButton")
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
    win.buyButtons = win.buyButtons or {}
    local bank = win.key == "bank"
    local shown = (win.key == "bags" or bank) and win.showBagBar
    local list = {}
    if shown then
        if bank then
            list = bankList()
        else
            for _, bag in ipairs(bagList()) do list[#list + 1] = { bag = bag } end
        end
    end

    local nBag, nBuy = 0, 0
    for i, entry in ipairs(list) do
        local bag = entry.bag
        local x = left + (i - 1) * (SIZE + GAP)
        if entry.kind == "buy" then
            nBuy = nBuy + 1
            local b = win.buyButtons[nBuy] or makeButton(win, "BankPanelPurchaseButtonScriptTemplate")
            win.buyButtons[nBuy] = b
            b.bag, b.next = bag, entry.next
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win.frame, "TOPLEFT", x, -y)
            b.icon:SetTexture(EMPTY_BAG)
            b.icon:SetTexCoord(0, 1, 0, 1)
            b.icon:SetDesaturated(true)
            b.icon:Show()
            b:SetAlpha(entry.next and 0.9 or 0.35)
            if entry.next then b.border:SetVertexColor(1, 0.82, 0.3) else b.border:SetVertexColor(1, 1, 1) end
            b:SetEnabled(entry.next and true or false)
            b:Show()
        else
            nBag = nBag + 1
            local b = win.bagButtons[nBag] or makeButton(win)
            win.bagButtons[nBag] = b
            b.bag, b.tabName, b.kind = bag, entry.name, entry.kind
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", win.frame, "TOPLEFT", x, -y)
            b.icon:SetDesaturated(false)

            local inv = (not bank) and invSlot(bag)
            if entry.kind == "empty" then
                b.icon:SetTexture(EMPTY_BAG)
                b.icon:SetTexCoord(0, 1, 0, 1)
                b.icon:Show()
            elseif bank then
                -- the tab's own icon, else the client's bank bag art
                if entry.icon then
                    b.icon:SetTexture(entry.icon)
                    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                else
                    -- an atlas carries its own coordinates; no crop after it
                    b.icon:SetAtlas("bag-main")
                end
                b.icon:Show()
            elseif bag == 0 then
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
    end
    for i = nBag + 1, #win.bagButtons do win.bagButtons[i]:Hide() end
    for i = nBuy + 1, #win.buyButtons do win.buyButtons[i]:Hide() end

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
