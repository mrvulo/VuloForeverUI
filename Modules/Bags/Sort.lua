-- VuloForeverUI / Modules / Bags / Sort
--
-- Our own sort, for the carried bags and for the bank alike.
--
-- WHY NOT THE CLIENT'S
--
-- The client's sort decides its own order, and that order ends with crafting
-- goods and profession tools -- the pickaxe lands in the last slot and the
-- grey items somewhere before it. What a player wants at the end of the bags
-- is the stuff that goes to the vendor. The order is ours, then, and so is the
-- moving.
--
-- THE ORDER
--
-- Every item gets a list of keys, compared one after the other until two items
-- differ: the hearthstone first, then (by default) the kind of item in a fixed,
-- hand-made order -- consumables, reagents, weapons by type, armour by slot,
-- gems, trade goods, recipes, quest items, the rest -- then item level, quality,
-- name, and finally the item's own GUID, so two identical stacks keep one order
-- from one pass to the next instead of trading places forever. Four orders are
-- on offer (by type, quality, name, item level); they are the same keys in a
-- different sequence.
--
-- A key the client cannot answer yet (name and item level need the item's data
-- loaded) is asked for and the pass is run again once it has arrived, rather
-- than sorted with a guess.
--
-- WHERE THINGS GO
--
-- Vendor junk fills the bags from the LAST slot backwards, everything else
-- from the first slot forwards; the free slots end up between the two. Items
-- that fit a special bag (the reagent bag, a profession bag) are placed there
-- before anything else, and an item that fits fewer special bags gets first
-- pick, so a herb does not lose the herb bag to something that would have fit
-- the reagent bag too.
--
-- HOW ITEMS ARE MOVED
--
-- Only by the container's own pick-up/put-down pair, the same two calls a
-- player's clicks make. First the stacks are combined, then the order is laid
-- out. Each pass plans every move from the state the bags are in NOW, issues
-- the moves into free slots first and the swaps after, skips any slot the
-- server still has locked, and waits for the bags to report back before the
-- next pass. The run ends on the first pass that has nothing left to move.
local _, ns = ...
local Bags = ns.Bags

local Sort = {}
Bags.Sort = Sort

local DONE, MOVED, LOCKED, NODATA = 0, 1, 2, 3
-- A run that has not settled in this long is stuck on something the server
-- will not do (a soulbound stack that refuses to merge, a full special bag).
local TIME_LIMIT = 30

-- The pick-up and put-down sounds. Muted around each burst of moves and given
-- back straight after: a hundred clicks in two seconds are a hundred sounds.
local PICKUP_SOUNDS = {
    567542, 567543, 567544, 567545, 567546, 567547, 567548, 567549, 567550,
    567551, 567552, 567553, 567554, 567555, 567556, 567557, 567558, 567559,
    567560, 567561, 567562, 567563, 567564, 567565, 567566, 567567, 567568,
    567569, 567570, 567571, 567572, 567573, 567574, 567575, 567576, 567577,
    2308876, 2308881, 2308889, 2308894, 2308901, 2308907, 2308914, 2308920,
    2308925, 2308930, 2308935, 2308942, 2308948, 2308956, 2308962, 2308968,
    2308974, 2308985, 2308992, 2309001, 2309006, 2309013, 2309025, 2309036,
    2309051, 2309057, 2309070, 2309078, 2309089, 2309100, 2309109, 2309120,
    2309126, 2309132, 2309137, 2309141,
}

local function mute(on)
    local fn = on and MuteSoundFile or UnmuteSoundFile
    if not fn then return end
    for _, id in ipairs(PICKUP_SOUNDS) do fn(id) end
end

-- Junk the vendor pays for: grey quality and not marked worthless by the
-- client. Shared with the "C" mark on the slot, so the two can never disagree.
function Sort.IsVendorJunk(info)
    if not info then return false end
    if type(info.quality) ~= "number" or info.quality ~= 0 then return false end
    return not info.hasNoValue
end

-- ---------------------------------------------------------------------------
-- The fixed orders. Item class, then the sub-classes where the client's own
-- numbering reads badly (weapons, armour, trade goods), then the equip slot.
-- Anything not listed goes after everything listed, in the client's order.
-- ---------------------------------------------------------------------------
local function rankMap(list)
    local m = {}
    for i, v in ipairs(list) do m[v] = i end
    return m
end

local CLASS = rankMap({
    18, -- token
    0,  -- consumable
    5,  -- reagent
    6,  -- projectile
    2,  -- weapon
    4,  -- armour
    11, -- quiver
    3,  -- gem
    8,  -- item enhancement
    16, -- glyph
    1,  -- container
    7,  -- trade goods
    19, -- profession
    9,  -- recipe
    10, -- money
    12, -- quest
    13, -- key
    14, -- permanent
    15, -- miscellaneous
    17, -- battle pet
})

local WEAPON = rankMap({
    0, 4, 7, 9, 15, 13, 11, 12, 19,  -- one-handers, daggers, fists, claws, wands
    1, 5, 8, 6, 10,                  -- two-handers, polearms, staves
    2, 18, 3, 16, 17,                -- bows, crossbows, guns, thrown, spears
    14, 20,                          -- miscellaneous, fishing poles
})

local ARMOR = rankMap({
    6, 7, 8, 9, 10, 11,  -- shields and relics
    4, 3, 2, 1,          -- plate, mail, leather, cloth
    0, 5,                -- generic, cosmetic
})

local TRADEGOODS = rankMap({
    18, 1, 4, 7, 6, 5, 12, 16, 10, 9, 8, 11,
    0, 2, 3, 13, 14, 15, 17,
})

local INVSLOT = rankMap({
    17, 13, 21, 14, 23, 26, 22, 15, 25, 24, 27, 28,  -- weapons, off-hands, ranged
    1, 3, 16, 5, 20, 9, 10, 6, 7, 8,                 -- head to feet
    2, 11, 12, 4, 19,                                -- neck, rings, trinkets, shirt, tabard
    29, 30, 18, 31, 32, 33, 34,                      -- profession gear, bags, the rest
    0,                                               -- not wearable
})

local HEARTH = { [6948] = true }

-- ---------------------------------------------------------------------------
-- Sort keys, computed on first use and kept for the rest of the pass. A key
-- that returns nil is one the client cannot answer yet.
-- ---------------------------------------------------------------------------
local function cached(item)
    local id = item.itemID
    if C_Item.IsItemDataCachedByID(id) then return true end
    C_Item.RequestLoadItemDataByID(id)
    return false
end

local FIELDS = {}

FIELDS.itemLevelRaw = function(item)
    if not cached(item) then return nil end
    return C_Item.GetDetailedItemLevelInfo(item.itemLink) or -1
end
FIELDS.invertedItemLevelRaw = function(item)
    local v = item.itemLevelRaw
    return v and -v
end
-- Item level only for what can be worn: a stack of cloth has an item level too,
-- and sorting trade goods by it scatters them across the gear.
FIELDS.invertedItemLevelEquipment = function(item)
    local c = item.classID
    if (c == 2 or c == 4) and item.invSlotID ~= 0 then
        local v = item.itemLevelRaw
        return v and -v
    end
    return 0
end
FIELDS.itemName = function(item)
    if not cached(item) then return nil end
    return C_Item.GetItemNameByID(item.itemID) or ""
end
FIELDS.invertedQuality   = function(item) return -item.quality end
FIELDS.invertedItemID    = function(item) return -item.itemID end
FIELDS.invertedItemCount = function(item) return -item.itemCount end
FIELDS.sortedClassID = function(item)
    return CLASS[item.classID] or (item.classID + 200)
end
FIELDS.sortedSubClassID = function(item)
    local c, s = item.classID, item.subClassID
    if c == 2 then return WEAPON[s] or (s + 200) end
    if c == 4 then return ARMOR[s] or (s + 200) end
    if c == 7 then return TRADEGOODS[s] or (s + 200) end
    return s
end
FIELDS.sortedInvSlotID = function(item)
    return INVSLOT[item.invSlotID] or (item.invSlotID + 200)
end

-- A key that came back nil is remembered as missing, so the comparisons of one
-- pass do not ask the client for the same item's data a thousand times.
local itemMeta = {
    __index = function(self, key)
        local f = FIELDS[key]
        if not f then return nil end
        local miss = rawget(self, "_miss")
        if miss and miss[key] then return nil end
        local v = f(self)
        if v == nil then
            miss = miss or {}
            miss[key] = true
            rawset(self, "_miss", miss)
        else
            rawset(self, key, v)
        end
        return v
    end,
}

local ORDERS = {
    type = {
        "priority", "sortedClassID", "sortedInvSlotID", "sortedSubClassID",
        "invertedItemLevelRaw", "invertedQuality", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    quality = {
        "priority", "quality", "sortedClassID", "sortedInvSlotID",
        "sortedSubClassID", "itemLevelRaw", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    name = {
        "priority", "sortedClassID", "sortedInvSlotID", "sortedSubClassID",
        "itemName", "invertedItemLevelRaw", "invertedQuality",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
    itemlevel = {
        "priority", "invertedItemLevelEquipment", "sortedClassID",
        "sortedInvSlotID", "sortedSubClassID", "invertedQuality",
        "invertedItemLevelRaw", "itemName",
        "invertedItemID", "invertedItemCount", "itemLink",
    },
}
Sort.ORDERS = ORDERS

-- Sorts the list in place. The second return says a key was missing somewhere,
-- so the result is only provisional and the pass has to be run again.
local function orderList(list, method)
    local keys = ORDERS[method] or ORDERS.type
    local incomplete = false
    -- A missing key makes two items equal on it, which can leave the order
    -- inconsistent enough for table.sort to throw. That is a provisional pass
    -- like any other incomplete one, not a failed sort.
    local ok = pcall(table.sort, list, function(a, b)
        for _, key in ipairs(keys) do
            local va, vb = a[key], b[key]
            if va ~= nil and vb ~= nil then
                if va ~= vb then return va < vb end
            else
                incomplete = true
            end
        end
        return a.index < b.index
    end)
    return list, incomplete or not ok
end

-- ---------------------------------------------------------------------------
-- Reading the bags
-- ---------------------------------------------------------------------------

-- Every item in the given bags, with the plain facts every key is built on.
local function scan(bagIDs)
    local list = {}
    for _, bag in ipairs(bagIDs) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" and info.hyperlink then
                local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(id)
                local item = setmetatable({
                    bag = bag, slot = slot,
                    itemID = id,
                    itemLink = info.hyperlink,
                    quality = tonumber(info.quality) or 1,
                    itemCount = tonumber(info.stackCount) or 1,
                    hasNoValue = info.hasNoValue,
                    locked = info.isLocked,
                    classID = classID or -1,
                    subClassID = subClassID or -1,
                    invSlotID = C_Item.GetItemInventoryTypeByID(id) or -1,
                    priority = HEARTH[id] and 1 or 1000,
                }, itemMeta)
                -- The GUID is what keeps two identical stacks in one order
                -- from pass to pass; a slot that has just emptied has none.
                local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
                item.index = (C_Item.DoesItemExist(loc) and C_Item.GetItemGUID(loc)) or "-1"
                list[#list + 1] = item
            end
        end
    end
    return list
end

-- Which bags only take certain items, and in what order the bags are filled:
-- profession bags first, then the reagent bag, then the ordinary ones. The
-- bank counts too: its tabs are bags in the bank's bag slots, and a herb bag
-- there refuses everything that is not a herb.
local function bagRules(bagIDs)
    local checks, rank = {}, {}
    local reagent = Enum.BagIndex and Enum.BagIndex.ReagentBag
    for _, bag in ipairs(bagIDs) do
        if bag == reagent then
            checks[bag] = function(item)
                return (select(17, C_Item.GetItemInfo(item.itemID))) and true or false
            end
            rank[bag] = 10
        else
            local _, family = C_Container.GetContainerNumFreeSlots(bag)
            if type(family) == "number" and family ~= 0 then
                checks[bag] = function(item)
                    local f = C_Item.GetItemFamily(item.itemID)
                    return type(f) == "number" and item.classID ~= 1 and item.classID ~= 11
                        and bit.band(f, family) ~= 0
                end
                rank[bag] = 5
            end
        end
    end
    for _, bag in ipairs(bagIDs) do rank[bag] = rank[bag] or 250 end
    return { checks = checks, rank = rank }
end

local function locked(bag, slot)
    return C_Item.IsLocked(ItemLocation:CreateFromBagAndSlot(bag, slot))
end

-- ---------------------------------------------------------------------------
-- Pass 1: combine stacks
--
-- Per item: if it takes more stacks than its count needs, or not every stack
-- that could be full is, the smallest partial stack goes onto the largest.
-- One move per item per pass; the next pass reads the new counts.
-- ---------------------------------------------------------------------------
local function combineStacks(bagIDs)
    if InCombatLockdown() then return DONE end
    -- The player picked something up mid-run: a pick-up now would swap it
    -- into our slot. Wait until the cursor is free again.
    if CursorHasItem() then return LOCKED end
    local byID = {}
    for _, item in ipairs(scan(bagIDs)) do
        byID[item.itemID] = byID[item.itemID] or {}
        table.insert(byID[item.itemID], item)
    end

    local moved, waiting, busy = false, false, false
    mute(true)
    for id, stacks in pairs(byID) do
        if #stacks > 1 then
            local size = C_Item.GetItemMaxStackSizeByID(id)
            if type(size) ~= "number" then
                C_Item.RequestLoadItemDataByID(id)
                waiting = true
            elseif size > 1 then
                local total, full = 0, 0
                for _, s in ipairs(stacks) do
                    total = total + s.itemCount
                    if s.itemCount == size then full = full + 1 end
                end
                if #stacks > math.ceil(total / size) or full ~= math.floor(total / size) then
                    local partial = {}
                    for _, s in ipairs(stacks) do
                        if s.itemCount ~= size then partial[#partial + 1] = s end
                    end
                    table.sort(partial, function(a, b) return a.itemCount < b.itemCount end)
                    local from, to = partial[1], partial[#partial]
                    if from and to and from ~= to then
                        if not locked(from.bag, from.slot) and not locked(to.bag, to.slot) then
                            C_Container.PickupContainerItem(from.bag, from.slot)
                            C_Container.PickupContainerItem(to.bag, to.slot)
                            ClearCursor()
                            moved = true
                        else
                            busy = true
                        end
                    end
                end
            end
        end
    end
    mute(false)
    if moved then return MOVED end
    if busy then return LOCKED end
    if waiting then return NODATA end
    return DONE
end

-- ---------------------------------------------------------------------------
-- Pass 2: lay out the order
-- ---------------------------------------------------------------------------

-- The bags in fill order, and the first and last free position in each.
local function usableBags(bagIDs, rules, backwards)
    local order = {}
    for i = 1, #bagIDs do order[i] = i end
    table.sort(order, function(a, b)
        local ra, rb = rules.rank[bagIDs[a]], rules.rank[bagIDs[b]]
        if ra == rb then
            if backwards then return a > b end
            return a < b
        end
        return ra < rb
    end)
    local out = {}
    for _, i in ipairs(order) do
        local bag = bagIDs[i]
        if (C_Container.GetContainerNumSlots(bag) or 0) > 0 then out[#out + 1] = bag end
    end
    return out
end

local function filter(list, fn)
    local out = {}
    for _, v in ipairs(list) do
        if fn(v) then out[#out + 1] = v end
    end
    return out
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function orderBags(bagIDs, method, fromBottom, patient)
    if InCombatLockdown() or UnitIsDead("player") then return DONE end
    if CursorHasItem() then return LOCKED end

    local rules = bagRules(bagIDs)
    local forward  = usableBags(bagIDs, rules, false)
    local backward = usableBags(bagIDs, rules, true)
    local affected = #forward

    local stores = {}
    for _, bag in ipairs(forward) do
        stores[bag] = { first = 1, last = C_Container.GetContainerNumSlots(bag) }
    end

    local items, incomplete = orderList(scan(bagIDs), method)

    -- How many special bags an item fits. The fewer, the earlier it chooses.
    for _, item in ipairs(items) do
        local n = 0
        for _, check in pairs(rules.checks) do
            if check(item) then n = n + 1 end
        end
        item.special = n
    end

    local kept = filter(items, function(i) return not Sort.IsVendorJunk(i) end)
    local junk = filter(items, function(i) return Sort.IsVendorJunk(i) end)
    if fromBottom then kept, junk = junk, kept end

    local toEmpty, toSwap = {}, {}
    local function plan(item, bag, slot)
        if item.bag == bag and item.slot == slot then return end
        local target = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local move = { item.bag, item.slot, bag, slot }
        if C_Item.DoesItemExist(target) then
            toSwap[#toSwap + 1] = move
        else
            toEmpty[#toEmpty + 1] = move
        end
    end

    -- A bag takes the item when it is an ordinary bag on the general sweep, or
    -- a special bag whose rule accepts the item.
    local function accepts(bag, item, specialsOnly)
        local check = rules.checks[bag]
        if check then return check(item) end
        return not specialsOnly
    end

    local function sweepBack(group, specialsOnly)
        for _, item in ipairs(group) do
            for i, bag in ipairs(backward) do
                if accepts(bag, item, specialsOnly) then
                    item.done = true
                    local st = stores[bag]
                    local slot = st.last
                    plan(item, bag, slot)
                    st.last = slot - 1
                    if st.first == slot then table.remove(backward, i) end
                    break
                end
            end
        end
    end

    local function sweepForward(group, specialsOnly)
        for _, item in ipairs(group) do
            for i, bag in ipairs(forward) do
                if accepts(bag, item, specialsOnly) then
                    item.done = true
                    local st = stores[bag]
                    local slot = st.first
                    plan(item, bag, slot)
                    st.first = slot + 1
                    if st.last == slot then table.remove(forward, i) end
                    break
                end
            end
        end
    end

    for n = 1, affected do
        sweepBack(filter(junk, function(i) return i.special == n end), true)
    end
    sweepBack(filter(junk, function(i) return not i.done end), false)

    -- a bag the backward sweep filled to the brim is gone for the forward one
    forward = filter(forward, function(bag) return contains(backward, bag) end)

    for n = 1, affected do
        sweepForward(filter(kept, function(i) return i.special == n end), true)
    end
    sweepForward(filter(kept, function(i) return not i.done end), false)

    -- An order built on missing keys is only provisional, and moving to it
    -- shuffles items that the next pass moves back. Wait for the data first;
    -- only a run that has waited long enough settles for what it has.
    if incomplete and patient then return NODATA end
    if #toEmpty == 0 and #toSwap == 0 then
        return incomplete and NODATA or DONE
    end

    local moved, busy = false, false
    mute(true)
    for _, m in ipairs(toEmpty) do
        if not locked(m[1], m[2]) then
            C_Container.PickupContainerItem(m[1], m[2])
            C_Container.PickupContainerItem(m[3], m[4])
            ClearCursor()
            moved = true
        else
            busy = true
        end
    end
    for _, m in ipairs(toSwap) do
        if not locked(m[1], m[2]) and not locked(m[3], m[4]) then
            C_Container.PickupContainerItem(m[1], m[2])
            C_Container.PickupContainerItem(m[3], m[4])
            ClearCursor()
            moved = true
        else
            busy = true
        end
    end
    mute(false)

    if incomplete then return NODATA end
    if moved then return MOVED end
    if busy then return LOCKED end
    return DONE
end

-- ---------------------------------------------------------------------------
-- The run
--
-- After a pass that moved something, the next one waits for the bags to report
-- back (BAG_UPDATE_DELAYED), with a one-second fallback because a pass whose
-- moves all failed fires nothing at all. A pass that is only waiting for a lock
-- or for item data runs again on the next frame.
-- ---------------------------------------------------------------------------
local running
local driver = CreateFrame("Frame")

local function cancelWait()
    driver:SetScript("OnUpdate", nil)
    driver:UnregisterEvent("BAG_UPDATE_DELAYED")
    if driver.timer then driver.timer:Cancel(); driver.timer = nil end
end

function Sort.Finish()
    cancelWait()
    driver:UnregisterEvent("BANKFRAME_CLOSED")
    running = nil
    Bags.Refresh()
end

local function schedule(status, again, complete)
    cancelWait()
    if not running then return end
    if GetTime() - running.started > TIME_LIMIT or InCombatLockdown() then
        Sort.Finish()
        return
    end
    if status == DONE then
        complete()
    elseif status == MOVED then
        local fired = false
        local function go()
            if fired then return end
            fired = true
            cancelWait()
            again()
        end
        driver:RegisterEvent("BAG_UPDATE_DELAYED")
        driver.onBags = go
        driver.timer = C_Timer.NewTimer(1, go)
    else
        driver:SetScript("OnUpdate", function()
            cancelWait()
            again()
        end)
    end
end

driver:SetScript("OnEvent", function(self, event)
    if event == "BANKFRAME_CLOSED" then
        -- the bank's containers are out of reach the moment the visit ends
        if running and running.isBank then Sort.Finish() end
    elseif self.onBags then
        self.onBags()
    end
end)

function Sort.Running() return running ~= nil end

-- A pass that throws must end the run, not leave it marked as running: the
-- button would do nothing until the next reload.
local function guarded(pass, ...)
    local ok, status = xpcall(pass, geterrorhandler(), ...)
    if ok then return status end
    mute(false)
    Sort.Finish()
    return nil
end

-- kind: "bags" or "bank".
function Sort.Run(kind)
    if running or InCombatLockdown() or CursorHasItem() then return end
    local isBank = (kind == "bank")
    local bagIDs = isBank and Bags.BankBags() or Bags.CarriedBags()
    if #bagIDs == 0 then return end
    local db = Bags.db()
    local method = ORDERS[db.sortMethod] and db.sortMethod or "type"
    local fromBottom = db.sortFromBottom == true

    local run = { started = GetTime(), isBank = isBank }
    running = run
    if isBank then driver:RegisterEvent("BANKFRAME_CLOSED") end

    local function patient() return GetTime() - run.started < 3 end
    local function layout()
        local status = guarded(orderBags, bagIDs, method, fromBottom, patient())
        if status and running == run then schedule(status, layout, Sort.Finish) end
    end
    local function combine()
        local status = guarded(combineStacks, bagIDs)
        if status and running == run then schedule(status, combine, layout) end
    end
    combine()
end
