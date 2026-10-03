-- VuloForeverUI / Modules / QoL / Junk
--
-- Junk beyond the greys:
--
--   mark      a right click with the chosen modifier (Alt or Ctrl) on an item
--             in the bags marks every item of that kind as junk, or unmarks
--             it. The list is account-wide (global.qolJunk, item IDs).
--   sell      at a merchant, marked items go after the greys, when "Sell grey
--             items" is on
--   discard   when the bags are full (the client's "Inventory is full"), the
--             cheapest junk stack is destroyed to make room. Off by default.
--
-- WHERE THE CLICK IS CAUGHT
--
-- A bag button sends a modified click to OnModifiedClick, which hands the
-- item to HandleModifiedItemClick(link, itemLocation). A post-hook on that
-- one global sees every bag button -- ours and the client's, whenever they
-- were created -- without touching their click handlers. Alt does nothing
-- else on a bag item; Ctrl also opens the dressing room on gear, which is why
-- Alt is the default.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local J = QoL.RegisterPart("junk", {})
QoL.Junk = J
ns.Junk = J

local POOR = Enum.ItemQuality.Poor
local SELL_STEP = 0.2          -- seconds between two sales: under the rate limit

local hooked, hookedTooltip, registered
local merchantOpen, selling = false, nil

local function db() return QoL.db() end
local carriedBags = ns.CarriedBags

local function list()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.qolJunk) ~= "table" then g.qolJunk = {} end
    return g.qolJunk
end

function J.IsMarked(itemID)
    return type(itemID) == "number" and list()[itemID] == true
end

-- What the bags show as junk and sort last: a grey with a value, or marked.
function J.IsJunk(info)
    if not info then return false end
    if J.IsMarked(info.itemID) then return true end
    return type(info.quality) == "number" and info.quality == POOR and not info.hasNoValue
end

local function refreshBags()
    if ns.Bags and ns.Bags.Refresh and ns:IsModuleEnabled("bags") then ns.Bags.Refresh() end
end

function J.Count()
    local n = 0
    for _ in pairs(list()) do n = n + 1 end
    return n
end

function J.Clear()
    wipe(list())
    refreshBags()
end

-- ------------------------------------------------------------------ mark --

local function modifierDown()
    local m = db().junkModifier
    if m == "CTRL" then return IsControlKeyDown() and not IsAltKeyDown() and not IsShiftKeyDown() end
    return IsAltKeyDown() and not IsControlKeyDown() and not IsShiftKeyDown()
end

local function onModifiedClick(_, itemLocation)
    if not (QoL.mod.active and db().junkClick) then return end
    if GetMouseButtonClicked() ~= "RightButton" or not modifierDown() then return end
    if not (itemLocation and itemLocation.IsBagAndSlot and itemLocation:IsBagAndSlot()) then return end
    local bag, slot = itemLocation:GetBagAndSlot()
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local id = info and info.itemID
    if type(id) ~= "number" then return end
    local l = list()
    local link = info.hyperlink or tostring(id)
    if l[id] then
        l[id] = nil
        ns:Print(L["%s is no longer junk."], link)
    else
        l[id] = true
        if info.hasNoValue then
            ns:Print(L["%s is junk now. It has no sell value, so a merchant will not take it."], link)
        else
            ns:Print(L["%s is junk now and goes at the next merchant."], link)
        end
    end
    refreshBags()
end

local function onItemTooltip(tooltip, data)
    if not (QoL.mod.active and db().junkClick) then return end
    if tooltip ~= GameTooltip then return end
    local id = data and ns.Readable(data.id)
    if J.IsMarked(id) then
        tooltip:AddLine(L["Marked as junk"], 0.93, 0.64, 0.35)
    end
end

-- ------------------------------------------------------------------ sell --

local function nextMarked()
    for _, bag in ipairs(carriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and J.IsMarked(info.itemID) and not info.hasNoValue and not info.isLocked then
                return bag, slot
            end
        end
    end
end

local function stopSelling()
    if selling then selling:Cancel(); selling = nil end
end

-- One item per step. The greys go first through the client's own sale, which
-- has a sweep of its own (Vendor.lua); this starts after it has had its go.
local function sellStep()
    selling = nil
    if not (merchantOpen and db().sellJunk) then return end
    local bag, slot = nextMarked()
    if not bag then return end
    C_Container.UseContainerItem(bag, slot)
    selling = C_Timer.NewTimer(SELL_STEP, sellStep)
end

local function onMerchantShow()
    merchantOpen = true
    stopSelling()
    if J.Count() > 0 then selling = C_Timer.NewTimer(1.5, sellStep) end
end

local function onMerchantClosed()
    merchantOpen = false
    stopSelling()
end

-- --------------------------------------------------------------- discard --

local function cheapestJunk()
    local best, bestBag, bestSlot
    for _, bag in ipairs(carriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and not info.isLocked
                and (J.IsMarked(info.itemID) or (type(info.quality) == "number" and info.quality == POOR)) then
                local price = select(11, C_Item.GetItemInfo(info.itemID))
                local value = (type(price) == "number" and price or 0) * (info.stackCount or 1)
                if not best or value < best then best, bestBag, bestSlot = value, bag, slot end
            end
        end
    end
    return bestBag, bestSlot
end

local function onUIError(_, _, message)
    if not (QoL.mod.active and db().junkDiscard) then return end
    if not (ns.CanRead(message) and message == ERR_INV_FULL) then return end
    if InCombatLockdown() or CursorHasItem() then return end
    local bag, slot = cheapestJunk()
    if not bag then return end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    local link = info and info.hyperlink or "?"
    C_Container.PickupContainerItem(bag, slot)
    if CursorHasItem() then
        DeleteCursorItem()
        ns:Print(L["Bags full: %s destroyed to make room."], link)
    end
end

-- -------------------------------------------------------------- switch --

function J.Apply()
    local d = db()
    local on = QoL.mod.active and true or false
    if on and d.junkClick and not hooked then
        hooked = true
        hooksecurefunc("HandleModifiedItemClick", onModifiedClick)
    end
    if on and d.junkClick and not hookedTooltip and TooltipDataProcessor then
        hookedTooltip = true
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
            pcall(onItemTooltip, tooltip, data)
        end)
    end
    local sellOn = on and d.sellJunk and true or false
    local discardOn = on and d.junkDiscard and true or false
    if registered ~= (sellOn and 1 or 0) + (discardOn and 2 or 0) then
        registered = (sellOn and 1 or 0) + (discardOn and 2 or 0)
        QoL.SyncEvent(sellOn, "MERCHANT_SHOW", onMerchantShow)
        QoL.SyncEvent(sellOn, "MERCHANT_CLOSED", onMerchantClosed)
        QoL.SyncEvent(discardOn, "UI_ERROR_MESSAGE", onUIError)
    end
    if not sellOn then onMerchantClosed() end
end

function J.Disable()
    ns:UnregisterEvent("MERCHANT_SHOW", onMerchantShow)
    ns:UnregisterEvent("MERCHANT_CLOSED", onMerchantClosed)
    ns:UnregisterEvent("UI_ERROR_MESSAGE", onUIError)
    registered = nil
    onMerchantClosed()
end
