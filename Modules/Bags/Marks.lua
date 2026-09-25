-- VuloForeverUI / Modules / Bags / Marks
--
-- Two marks an item can carry: PINNED, which the player sets and which
-- survives a logout, and RECENT, which the bag notices by itself.
--
-- Recent is worked out by comparing what is in the bags now against what was
-- in them a moment ago. There is no event that says "this item is new" -- only
-- BAG_UPDATE_DELAYED, which says the bags changed and nothing more -- so the
-- snapshot IS the mechanism. It lives for the session only: an item that was
-- new yesterday is not news today, and writing it out would only make the
-- saved variables grow.
local _, ns = ...
local Bags = ns.Bags

local Marks = {}
Bags.Marks = Marks

local seen = {}        -- itemID -> count at the last scan
local fresh = {}       -- itemID -> when it appeared
local primed = false   -- the first scan only fills `seen`
local quietUntil = 0   -- scans before this only fill `seen`, too

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

-- How long something counts as new. Long enough to still be new after a walk
-- back to town, short enough that a bag is not permanently half highlighted.
local RECENT_WINDOW = 30 * 60

function Marks.IsRecent(itemID)
    if type(itemID) ~= "number" then return false end
    local at = fresh[itemID]
    if not at then return false end
    if GetTime() - at > RECENT_WINDOW then
        fresh[itemID] = nil
        return false
    end
    return true
end

-- One pass over the bags: anything whose count went UP is new, anything that
-- is gone is forgotten. The first pass after a login only primes the snapshot,
-- because otherwise every item a player owns would be "just picked up".
function Marks.Scan()
    local now, counts = GetTime(), {}
    for _, bag in ipairs(Bags.CarriedBags()) do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if type(id) == "number" then
                counts[id] = (counts[id] or 0) + (tonumber(info.stackCount) or 1)
            end
        end
    end

    -- An empty scan (at login, or bags reporting nothing for a moment) marks
    -- nothing and keeps the old snapshot: replacing it would make the next
    -- full scan mark everything the player owns.
    if next(counts) == nil then return end

    if primed and now >= quietUntil then
        for id, count in pairs(counts) do
            if count > (seen[id] or 0) then fresh[id] = now end
        end
    end
    for id in pairs(fresh) do
        if not counts[id] then fresh[id] = nil end
    end

    seen = counts
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
