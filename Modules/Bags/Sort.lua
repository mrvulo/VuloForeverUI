-- VuloForeverUI / Modules / Bags / Sort
--
-- Our own sort for the carried bags.
--
-- WHY NOT THE CLIENT'S
--
-- The client's sort decides its own order, and that order ends with crafting
-- goods and profession tools -- the pickaxe lands in the last slot and the
-- grey items somewhere before it. What a player wants at the end of the bags
-- is the stuff that goes to the vendor. The order is ours, then, and so is the
-- moving.
--
-- HOW ITEMS ARE MOVED
--
-- Only by the container's own pick-up/put-down pair, the same two calls a
-- player's clicks make. Two passes, each one repeated after the bags report
-- back, because the server settles every move on its own time:
--   1. stacks: the emptiest partial stack of an item is dropped on the fullest
--   2. places: every item is swapped towards the slot it belongs in
-- A pass that finds nothing left to do ends the run. Two stacks of the same
-- item are never swapped with each other -- the server would merge them
-- instead of swapping -- the next pass simply reads the new state.
local _, ns = ...
local Bags = ns.Bags

local Sort = {}
Bags.Sort = Sort

local MAX_PASSES = 20
local running = false
local waiter

local function rankOfClass()
    local rank = {}
    for i, key in ipairs(Bags.Categories.ORDER) do rank[key] = i end
    return rank
end

-- Junk the vendor pays for: grey quality and not marked worthless by the
-- client. Shared with the "C" mark on the slot, so the two can never disagree.
function Sort.IsVendorJunk(info)
    if not info then return false end
    if type(info.quality) ~= "number" or info.quality ~= 0 then return false end
    return not info.hasNoValue
end

-- Every slot of the given bags, in bag and slot order.
local function slotsOf(bags)
    local out = {}
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            out[#out + 1] = { bag = bag, slot = slot }
        end
    end
    return out
end

local function maxStack(itemID)
    local get = C_Item.GetItemMaxStackSizeByID
    local n = get and get(itemID)
    return (type(n) == "number" and n > 0) and n or 1
end

local function locked(bag, slot)
    local info = C_Container.GetContainerItemInfo(bag, slot)
    return info and info.isLocked
end

-- Pass 1. True when it moved something.
local function mergeStacks(bags)
    local partial = {}
    for _, s in ipairs(slotsOf(bags)) do
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        local id = info and info.itemID
        if type(id) == "number" and not info.isLocked then
            local count = tonumber(info.stackCount) or 1
            if count < maxStack(id) then
                partial[id] = partial[id] or {}
                table.insert(partial[id], { bag = s.bag, slot = s.slot, count = count })
            end
        end
    end
    local moved = false
    for _, list in pairs(partial) do
        if #list >= 2 then
            table.sort(list, function(a, b) return a.count < b.count end)
            -- emptiest onto fullest, pairwise: every slot is touched once per
            -- pass, so the whole pass can be issued at once
            local lo, hi = 1, #list
            while lo < hi do
                ClearCursor()
                C_Container.PickupContainerItem(list[lo].bag, list[lo].slot)
                C_Container.PickupContainerItem(list[hi].bag, list[hi].slot)
                ClearCursor()
                moved = true
                lo, hi = lo + 1, hi - 1
            end
        end
    end
    return moved
end

-- Pass 2. True when it moved something.
local function placeItems(bags)
    local slots = slotsOf(bags)
    local classRank = rankOfClass()
    local items = {}
    for pos, s in ipairs(slots) do
        local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
        if info and type(info.itemID) == "number" then
            local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(info.itemID)
            items[#items + 1] = {
                pos   = pos,
                id    = info.itemID,
                junk  = Sort.IsVendorJunk(info),
                class = classRank[Bags.Categories.ClassOf(info)] or 99,
                q     = tonumber(info.quality) or 1,
                name  = type(name) == "string" and name or "",
                count = tonumber(info.stackCount) or 1,
            }
        end
    end
    if #items == 0 then return false end

    -- The order: everything that is kept, by category, best quality first,
    -- then by name; vendor junk after all of it.
    table.sort(items, function(a, b)
        if a.junk ~= b.junk then return b.junk end
        if a.class ~= b.class then return a.class < b.class end
        if a.q ~= b.q then return a.q > b.q end
        if a.name ~= b.name then return a.name < b.name end
        if a.id ~= b.id then return a.id < b.id end
        if a.count ~= b.count then return a.count > b.count end
        return a.pos < b.pos
    end)

    -- Where each item belongs: what is kept fills the bags from the first
    -- slot, the vendor junk fills them from the LAST -- bottom right in the
    -- window -- with the free slots left between the two.
    local target = {}
    for i, it in ipairs(items) do
        target[i] = it.junk and (#slots - #items + i) or i
    end

    -- Selection sort over slot positions: item i belongs in slot target[i].
    -- `at` maps a slot to the item in it, `where` an item to its slot; both
    -- are kept up to date as the swaps are planned.
    local at, where, idAt = {}, {}, {}
    for i, it in ipairs(items) do
        at[it.pos] = i
        where[i] = it.pos
        idAt[it.pos] = it.id
    end
    local moved = false
    for i = 1, #items do
        local from, to = where[i], target[i]
        if from ~= to then
            local other = at[to]
            -- same item in both slots: a swap would be a merge
            if not (other and idAt[from] == idAt[to])
                and not locked(slots[from].bag, slots[from].slot)
                and not locked(slots[to].bag, slots[to].slot) then
                ClearCursor()
                C_Container.PickupContainerItem(slots[from].bag, slots[from].slot)
                C_Container.PickupContainerItem(slots[to].bag, slots[to].slot)
                ClearCursor()
                moved = true
                where[i], at[to] = to, i
                if other then where[other] = from end
                at[from] = other
                idAt[from], idAt[to] = idAt[to], idAt[from]
            end
        end
    end
    return moved
end

-- One pass of the current phase, then wait for the bags to settle and go
-- again. The wait is on BAG_UPDATE_DELAYED with a timeout, because a pass
-- whose moves all failed fires nothing at all.
local function step(state)
    if InCombatLockdown() then Sort.Finish(state); return end
    local moved
    if state.phase == "stacks" then
        moved = mergeStacks(state.bags)
        if not moved then state.phase = "places"; state.passes = 0; return step(state) end
    else
        moved = placeItems(state.bags)
        if not moved then
            state.index = state.index + 1
            local nextBags = state.groups[state.index]
            if not nextBags then Sort.Finish(state); return end
            state.bags, state.phase, state.passes = nextBags, "stacks", 0
            return step(state)
        end
    end
    state.passes = state.passes + 1
    if state.passes > MAX_PASSES then
        -- Stacks the server will not merge (bound differently, say) must not
        -- cost the whole sort: give up on merging, not on sorting.
        if state.phase == "stacks" then
            state.phase, state.passes = "places", 0
            return step(state)
        end
        Sort.Finish(state)
        return
    end

    waiter = waiter or CreateFrame("Frame")
    local token = {}
    state.token = token
    local function again()
        if state.token ~= token then return end
        state.token = nil
        waiter:UnregisterEvent("BAG_UPDATE_DELAYED")
        C_Timer.After(0.1, function() step(state) end)
    end
    waiter:SetScript("OnEvent", again)
    waiter:RegisterEvent("BAG_UPDATE_DELAYED")
    C_Timer.After(1.5, again)
end

function Sort.Finish(state)
    running = false
    if state and state.sfx ~= nil then SetCVar("Sound_EnableSFX", state.sfx) end
    if waiter then waiter:UnregisterEvent("BAG_UPDATE_DELAYED") end
    Bags.Refresh()
end

function Sort.Running() return running end

-- The carried bags, the reagent bag on its own: it only holds reagents, so
-- mixing its slots into the order would plan moves the server refuses.
function Sort.Run()
    if running or InCombatLockdown() or CursorHasItem() then return end
    local reagent = Enum.BagIndex and Enum.BagIndex.ReagentBag
    local main, extra = {}, {}
    for _, bag in ipairs(Bags.CarriedBags()) do
        if bag == reagent then extra[#extra + 1] = bag else main[#main + 1] = bag end
    end
    local groups = { main }
    if #extra > 0 then groups[2] = extra end
    running = true
    local state = { groups = groups, index = 1, bags = main, phase = "stacks", passes = 0 }
    -- A hundred pick-up clicks in two seconds are a hundred click sounds.
    state.sfx = GetCVar("Sound_EnableSFX")
    SetCVar("Sound_EnableSFX", "0")
    -- The sound switch is a saved setting: a reload or logout mid-sort would
    -- otherwise leave the game silent for good. Put it back on the way out.
    ns:RegisterEventOnce("PLAYER_LOGOUT", function()
        if running and state.sfx ~= nil then SetCVar("Sound_EnableSFX", state.sfx) end
    end)
    step(state)
end
