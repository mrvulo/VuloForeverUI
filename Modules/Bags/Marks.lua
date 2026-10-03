-- VuloForeverUI / Modules / Bags / Marks
--
-- Two marks an item can carry: PINNED, which the player sets and which
-- survives a logout, and RECENT, which the bag notices by itself.
--
-- Recent is worked out per STACK, by the item's GUID, which the client keeps
-- for a stack as long as it exists: a potion stack that is used from, moved
-- or sorted is the same stack, and only a stack the bags have not held before
-- -- or one that grew -- is news. There is no event that says "this item is
-- new", only BAG_UPDATE_DELAYED, so the scan after it IS the mechanism. It
-- lives for the session only: an item that was new yesterday is not news
-- today, and writing it out would only make the saved variables grow.
local _, ns = ...
local Bags = ns.Bags

local Marks = {}
Bags.Marks = Marks

local known = {}       -- guid -> stack count at the last scan it was in (whole session)
local totals = {}      -- itemID -> count at the last scan
local slotGuid = {}    -- [bag][slot] -> guid, from the last scan
local fresh = {}       -- guid -> when it became new
local primed = false   -- the first scan only fills `known`
local quietUntil = 0   -- scans before this only fill `known`, too

-- ---------------------------------------------------------------- pinned --

local function store()
    local db = Bags.db()
    local t = db.pinned
    if type(t) ~= "table" then t = {}; db.pinned = t end
    return t
end

function Marks.IsPinned(itemID)
    if type(itemID) ~= "number" then return false end
    return store()[tostring(itemID)] == true
end

-- The key is a STRING. A saved variables table with number keys comes back
-- from the client as a mixed table, and a pin set on 6948 was then looked up
-- under "6948" and lost at the next login.
function Marks.TogglePin(itemID)
    if type(itemID) ~= "number" then return end
    local t = store()
    local key = tostring(itemID)
    t[key] = (t[key] == nil) and true or nil
    Bags.Refresh()
end

function Marks.AnyPinned()
    return next(store()) ~= nil
end

-- ---------------------------------------------------------------- recent --

-- How long something counts as new, in minutes, from the options. Hovering
-- the item ends it sooner: once the player has looked at it, it is not news.
local function window()
    return (tonumber(Bags.db().recentMinutes) or 5) * 60
end

local function guidAt(bag, slot)
    local t = slotGuid[bag]
    return t and t[slot]
end

function Marks.IsRecent(bag, slot)
    local guid = guidAt(bag, slot)
    local at = guid and fresh[guid]
    if not at then return false end
    if GetTime() - at > window() then
        fresh[guid] = nil
        return false
    end
    return true
end

-- The item under the mouse has been seen. Its border goes now; the shelf it
-- sits on follows at the next layout, not under the cursor.
function Marks.Acknowledge(bag, slot)
    local guid = guidAt(bag, slot)
    if not (guid and fresh[guid]) then return end
    fresh[guid] = nil
    Bags.Repaint()
end

-- A GUID we may use as a table key: a plain string, or nothing.
local function readGuid(bag, slot)
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    if not C_Item.DoesItemExist(loc) then return nil end
    local guid = C_Item.GetItemGUID(loc)
    if ns.IsSecret(guid) or type(guid) ~= "string" or guid == "" then return nil end
    return guid
end

-- One pass over the bags. A stack is new when the bags have not held it
-- before, or when it grew -- AND the player owns more of that item than at
-- the last pass. The second half keeps the bookkeeping quiet: a split makes a
-- stack with a new GUID, a merge makes one grow, a bag that drops out of one
-- pass comes back; none of them changes how many the player has.
-- The first pass after a login only primes, because otherwise every item a
-- player owns would be "just picked up".
function Marks.Scan()
    local now, counts, slots, stacks, unread = GetTime(), {}, {}, {}, {}
    for _, bag in ipairs(ns.CarriedBags()) do
        local n = C_Container.GetContainerNumSlots(bag) or 0
        local inBag = {}
        slots[bag] = inBag
        for slot = 1, n do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" then
                local count = tonumber(info.stackCount) or 1
                counts[id] = (counts[id] or 0) + count
                local guid = readGuid(bag, slot)
                if guid then
                    inBag[slot] = guid
                    stacks[#stacks + 1] = { guid = guid, id = id, count = count }
                else
                    unread[id] = true
                end
            end
        end
    end

    -- An empty scan (at login, or bags reporting nothing for a moment) marks
    -- nothing and keeps the old snapshot: replacing it would make the next
    -- full scan mark everything the player owns.
    if next(counts) == nil then return end

    local present = {}
    local judge = primed and now >= quietUntil
    for _, s in ipairs(stacks) do
        if judge then
            local before = known[s.guid]
            if (before == nil or s.count > before) and counts[s.id] > (totals[s.id] or 0) then
                fresh[s.guid] = now
            end
        end
        known[s.guid] = s.count
        present[s.guid] = true
    end
    for guid in pairs(fresh) do
        if not present[guid] then fresh[guid] = nil end
    end

    -- An item with a stack whose GUID could not be read keeps the total it
    -- had: the stack is judged at the next pass that can see it, and against
    -- what the player had before, not against a total it already counted in.
    for id in pairs(unread) do counts[id] = totals[id] end
    totals, slotGuid = counts, slots
    -- An empty scan primes nothing: at a fresh login the addon loads before
    -- the client has filled the bags, and a snapshot of nothing made every
    -- item the player owns "just picked up" at the first bag update.
    primed = true
end

-- The bags fill bag by bag after a loading screen, over several updates. For
-- a moment after one, a scan only learns what is there.
function Marks.Quiet(seconds)
    quietUntil = GetTime() + (seconds or 5)
end

function Marks.ClearRecent()
    wipe(fresh)
    Bags.Refresh()
end

function Marks.AnyRecent()
    return next(fresh) ~= nil
end
