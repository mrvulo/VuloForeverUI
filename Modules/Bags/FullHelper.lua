-- VuloForeverUI / Modules / Bags / FullHelper
--
-- Bags full while looting: a bar under the loot window names the one stack
-- that can go -- junk first, then the cheapest stack by vendor price -- and
-- one click destroys it and loots what was left lying.
--
-- WHEN IT SHOWS
--
-- On the client's "Inventory is full" while a loot window is open, and only
-- once that error has settled: an item that stacks onto a partial stack never
-- raises it, and the QoL junk discard (Junk.lua) may already have made room
-- on the same error. So the bar looks again a moment later and stays away if
-- a general slot is free by then.
--
-- WHAT IS NEVER SUGGESTED
--
-- Quest items, profession tools, class reagents, ammunition and quivers,
-- bags, keys, anything without a vendor price, anything the player pinned,
-- any armour or weapon above grey, and nothing rare or better. Only the general bags count: a slot freed in a reagent or profession
-- bag does not take an ordinary item.
--
-- THE CLICK
--
-- The click is the hardware event that pickup and delete need. The stack is
-- checked again first (same item, not locked, cursor empty), then destroyed;
-- the loot is taken once the bags report a general slot free, so LootSlot
-- never races the server's answer to the delete.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local FullHelper = {}
Bags.FullHelper = FullHelper

local SETTLE = 0.25            -- seconds between the error and the look at the bags
local LOOT_FALLBACK = 1.0      -- loot anyway if the bag event does not come

-- Item classes (Enum.ItemClass) that never go.
local KEEP_CLASS = {
    [1] = true,     -- Container
    [5] = true,     -- Reagent (class reagents: ankhs, symbols, powders)
    [6] = true,     -- Projectile
    [11] = true,    -- Quiver
    [12] = true,    -- Questitem
    [13] = true,    -- Key
    [19] = true,    -- Profession (tools and gear of a profession)
}
local GEAR = { [2] = true, [4] = true }      -- Weapon, Armor

-- Profession tools, by item id. A fishing pole is a weapon and already kept.
local TOOLS = {
    [2901] = true,  -- Mining Pick
    [5956] = true,  -- Blacksmith Hammer
    [7005] = true,  -- Skinning Knife
    [6219] = true,  -- Arclight Spanner
    [10498] = true, -- Gyromatic Micro-Adjustor
    [6218] = true,  -- Runed Copper Rod
    [6339] = true,  -- Runed Silver Rod
    [11130] = true, -- Runed Golden Rod
    [11145] = true, -- Runed Truesilver Rod
    [16207] = true, -- Runed Arcanite Rod
    [9149] = true,  -- Philosopher's Stone
    [4471] = true,  -- Flint and Tinder
    [5060] = true,  -- Thieves' Tools
}

local bar, events
local lootOpen = false
local candidates, pick = {}, 1
local waitLoot, settleTimer, lootTimer

local function db() return Bags.db() end
local function on() return Bags.mod.active and db().fullHelper ~= false end

-- ------------------------------------------------------------ the bags --

local function generalBags()
    local out = {}
    local reagent = Enum.BagIndex and Enum.BagIndex.ReagentBag
    for _, bag in ipairs(ns.CarriedBags()) do
        if bag ~= reagent then
            local _, family = C_Container.GetContainerNumFreeSlots(bag)
            if family == 0 then out[#out + 1] = bag end
        end
    end
    return out
end

local function freeGeneral()
    local n = 0
    for _, bag in ipairs(generalBags()) do
        n = n + (C_Container.GetContainerNumFreeSlots(bag) or 0)
    end
    return n
end

local function isQuest(bag, slot)
    local q = C_Container.GetContainerItemQuestInfo(bag, slot)
    return q and (q.isQuestItem or q.questID) and true or false
end

-- 1 for junk (grey with a price, or marked by the player), 2 for the rest
-- that may go, nil for what is kept.
local function tierOf(bag, slot, info)
    if info.hasLoot or isQuest(bag, slot) then return nil end
    if Bags.Marks and Bags.Marks.IsPinned(info.itemID) then return nil end
    local J = ns.Junk
    if J and J.IsJunk and J.IsJunk(info) then return 1 end
    if info.hasNoValue or TOOLS[info.itemID] then return nil end
    -- an unknown quality keeps the item: the gear and rarity rules need it
    local q = info.quality
    if type(q) ~= "number" or q >= 3 then return nil end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
    if KEEP_CLASS[classID] then return nil end
    if GEAR[classID] and q >= 1 then return nil end
    return 2
end

local function byTierThenValue(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    return a.value < b.value
end

-- A re-collect keeps the stack the player had picked with "Another one":
-- the bags change under a shown bar, and a click right then must hit what
-- the bar shows.
local function collect()
    local was = candidates[pick]
    wipe(candidates)
    for _, bag in ipairs(generalBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and type(info.itemID) == "number" and not info.isLocked then
                local tier = tierOf(bag, slot, info)
                local price = tier and select(11, C_Item.GetItemInfo(info.itemID))
                -- a price not loaded yet is no reason to guess: tier 2 waits
                if tier and (type(price) == "number" or tier == 1) then
                    candidates[#candidates + 1] = {
                        bag = bag, slot = slot, tier = tier, itemID = info.itemID,
                        link = info.hyperlink, icon = info.iconFileID,
                        count = info.stackCount or 1,
                        value = (type(price) == "number" and price or 0) * (info.stackCount or 1),
                    }
                end
            end
        end
    end
    table.sort(candidates, byTierThenValue)
    pick = 1
    if was then
        for i, c in ipairs(candidates) do
            if c.bag == was.bag and c.slot == was.slot and c.itemID == was.itemID then pick = i; break end
        end
    end
end

-- ------------------------------------------------------------ the loot --

local function lootLeft()
    for i = 1, (GetNumLootItems() or 0) do
        if LootSlotHasItem(i) and GetLootSlotType(i) == Enum.LootSlotType.Item then return true end
    end
    return false
end

local function lootItems()
    if lootTimer then lootTimer:Cancel(); lootTimer = nil end
    waitLoot = false
    if not lootOpen then return end
    for i = 1, (GetNumLootItems() or 0) do
        local locked = select(6, GetLootSlotInfo(i))
        if LootSlotHasItem(i) and GetLootSlotType(i) == Enum.LootSlotType.Item and not locked then LootSlot(i) end
    end
end

-- ------------------------------------------------------------- the bar --

local function hide()
    if bar then bar:Hide() end
end

local function build()
    if bar then return end
    local C = ns.COLORS
    bar = CreateFrame("Frame", nil, UIParent)
    bar:SetSize(300, 58)
    bar:SetFrameStrata("DIALOG")
    bar:SetClampedToScreen(true)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(C.bg.r, C.bg.g, C.bg.b, C.bg.a)
    local edges = ns.MakeEdges(bar, "BORDER")
    ns.LayoutEdges(edges, bar, 1, C.border.r, C.border.g, C.border.b, 1)

    bar.title = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.FontFor("bags", bar.title, 12, "OUTLINE")
    bar.title:SetPoint("TOPLEFT", 8, -6)
    bar.title:SetTextColor(1, 0.35, 0.3)
    bar.title:SetText(L["Bags full"])

    local slot = CreateFrame("Button", nil, bar)
    slot:SetSize(28, 28)
    slot:SetPoint("BOTTOMLEFT", 8, 6)
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)
    slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    slot.count = slot:CreateFontString(nil, "OVERLAY")
    ns.UI.FontFor("bags", slot.count, 10, "OUTLINE")
    slot.count:SetPoint("BOTTOMRIGHT", -1, 1)
    slot:SetScript("OnEnter", function(self)
        local c = candidates[pick]
        if not (c and c.link) then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(c.link)
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.slot = slot

    bar.name = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.FontFor("bags", bar.name, 11, "OUTLINE")
    bar.name:SetPoint("TOPLEFT", slot, "TOPRIGHT", 6, 0)
    bar.name:SetJustifyH("LEFT")
    bar.name:SetWordWrap(false)
    bar.value = bar:CreateFontString(nil, "OVERLAY")
    ns.UI.FontFor("bags", bar.value, 10, "OUTLINE")
    bar.value:SetPoint("BOTTOMLEFT", slot, "BOTTOMRIGHT", 6, 0)
    bar.value:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)

    bar.go = ns.UI:CreateButton(bar, { label = L["Destroy & loot"], width = 100, height = 22,
        onClick = function() FullHelper.Destroy() end })
    bar.go:SetPoint("BOTTOMRIGHT", -6, 6)
    bar.name:SetPoint("RIGHT", bar.go, "LEFT", -6, 0)
    bar.other = ns.UI:CreateButton(bar, { label = L["Another one"], width = 60, height = 18,
        onClick = function() FullHelper.Next() end })
    bar.other:SetPoint("TOPRIGHT", -6, -4)
    bar:Hide()
end

local function place()
    bar:ClearAllPoints()
    local lf = _G.LootFrame
    -- whatever its scale: quick loot may still have it shrunk, and the
    -- anchor follows it back to full size
    if lf and lf:IsShown() then
        bar:SetPoint("TOPLEFT", lf, "BOTTOMLEFT", 0, -4)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
end

local function paint()
    local c = candidates[pick]
    if c then
        bar.slot.icon:SetTexture(c.icon)
        bar.slot.count:SetText(c.count > 1 and c.count or "")
        bar.slot:Show()
        bar.name:SetText(c.link or "?")
        bar.value:SetText(Bags.Gold and Bags.Gold.Text(c.value) or tostring(c.value))
        bar.go:Enable()
        bar.go:SetAlpha(1)
    else
        bar.slot:Hide()
        bar.name:SetText(L["Nothing in your bags can safely go."])
        bar.value:SetText("")
        bar.go:Disable()
        bar.go:SetAlpha(0.4)
    end
    bar.other:SetShown(#candidates > 1)
end

local function show()
    if not (on() and lootOpen) or InCombatLockdown() then return end
    if freeGeneral() > 0 or not lootLeft() then hide(); return end
    build()
    collect()
    place()
    paint()
    bar:Show()
end

function FullHelper.Next()
    if #candidates < 2 then return end
    pick = pick % #candidates + 1
    paint()
end

function FullHelper.Destroy()
    local c = candidates[pick]
    if not c or InCombatLockdown() or CursorHasItem() then return end
    local info = C_Container.GetContainerItemInfo(c.bag, c.slot)
    if not (info and info.itemID == c.itemID and not info.isLocked) then
        show()                       -- the bags moved underneath: look again
        return
    end
    C_Container.PickupContainerItem(c.bag, c.slot)
    local kind, id = GetCursorInfo()
    if kind ~= "item" or id ~= c.itemID then
        ClearCursor()
        return
    end
    DeleteCursorItem()
    ns:Print(L["Bags full: %s destroyed to make room."], c.link or "?")
    hide()
    waitLoot = true
    if lootTimer then lootTimer:Cancel() end
    lootTimer = C_Timer.NewTimer(LOOT_FALLBACK, lootItems)
end

-- ------------------------------------------------------------ events --

local function onEvent(_, event, ...)
    if event == "LOOT_OPENED" then
        lootOpen = true
    elseif event == "LOOT_CLOSED" then
        lootOpen, waitLoot = false, false
        if lootTimer then lootTimer:Cancel(); lootTimer = nil end
        if settleTimer then settleTimer:Cancel(); settleTimer = nil end
        hide()
    elseif event == "UI_ERROR_MESSAGE" then
        local _, message = ...
        if not (lootOpen and ns.CanRead(message) and message == ERR_INV_FULL) then return end
        if settleTimer then settleTimer:Cancel() end
        settleTimer = C_Timer.NewTimer(SETTLE, function() settleTimer = nil; show() end)
    elseif event == "BAG_UPDATE_DELAYED" then
        if waitLoot then
            -- another update (a stack, the junk discard) is not our slot yet
            if freeGeneral() > 0 then lootItems() end
        elseif bar and bar:IsShown() then
            show()                   -- the bags changed under a shown bar
        end
    elseif event == "LOOT_SLOT_CLEARED" then
        if bar and bar:IsShown() and not lootLeft() then hide() end
    end
end

function FullHelper.Apply()
    local want = on()
    if want and not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", onEvent)
    end
    if not events then return end
    for _, e in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "UI_ERROR_MESSAGE", "BAG_UPDATE_DELAYED", "LOOT_SLOT_CLEARED" }) do
        if want then events:RegisterEvent(e) else events:UnregisterEvent(e) end
    end
    if not want then
        lootOpen, waitLoot = false, false
        if settleTimer then settleTimer:Cancel(); settleTimer = nil end
        if lootTimer then lootTimer:Cancel(); lootTimer = nil end
        hide()
    end
end
