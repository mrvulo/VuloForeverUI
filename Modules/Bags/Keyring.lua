-- VuloForeverUI / Modules / Bags / Keyring
--
-- The keyring, as a section of the bag window.
--
-- Forever has a real keyring: a container of its own (KEYRING_CONTAINER)
-- that keys go into by themselves. The client shows it in a bag frame of its
-- own -- and with our takeover on, that frame is parked like every other bag
-- frame (Core.lua), so the keys could not be reached at all. Here they get a
-- foldable section at the very bottom of the bag window, switched by a key
-- button in the tool row and by the client's own keyring button.
--
-- The keyring is deliberately NOT one of ns.CarriedBags(): nothing that
-- counts free room, sorts, sells junk or suggests what to destroy may ever
-- see it. This file is the only place that reads it.
--
-- The slots are the bag window's ordinary secure item buttons: the slot pool
-- sets the container id on the button's parent (Slots.Paint), which is all
-- the client's item button needs to use, pick up or take a key.
local _, ns = ...

local Bags = ns.Bags
local Keyring = {}
Bags.Keyring = Keyring

-- The container id, asked each time: a constant read at file scope would be
-- read before the client's bag code has loaded.
local function container()
    local id = _G.KEYRING_CONTAINER
    if type(id) ~= "number" then id = Enum.BagIndex and Enum.BagIndex.Keyring end
    return type(id) == "number" and id or nil
end
Keyring.Container = container

-- Does this client, on this character, have a keyring at all?
local function exists()
    local id = container()
    if not id then return nil end
    if C_ActionBar and C_ActionBar.ShouldShowKeyring then
        local ok, shown = pcall(C_ActionBar.ShouldShowKeyring)
        if ok and shown == false then return nil end
    end
    local slots = C_Container.GetContainerNumSlots(id)
    if type(slots) ~= "number" or slots <= 0 then return nil end
    return id, slots
end

-- How many keys there are, and the last slot worth showing: the keys plus
-- the free places of the started row of four, the way the client's own
-- keyring grows (GetKeyRingSize in its bag button code).
local function measure()
    local id, slots = exists()
    if not id then return nil, 0, 0 end
    local keys, last = 0, 0
    for slot = 1, slots do
        if C_Container.GetContainerItemID(id, slot) then
            keys = keys + 1
            last = slot
        end
    end
    local size = last
    if keys > 0 then
        local rest = last % 4
        if rest ~= 0 or keys >= last then size = last + (4 - rest) end
        size = math.min(size, slots)
    end
    return id, keys, size
end

function Keyring.Enabled()
    local db = Bags.db()
    return db ~= nil and db.showKeyring ~= false
end

-- Is there a keyring to offer in this window? Only the bags have one, and an
-- empty keyring is not worth a button.
function Keyring.Has(win)
    if not (win and win.key == "bags" and Keyring.Enabled()) then return false end
    local _, keys = measure()
    return keys > 0
end

function Keyring.IsOpen()
    return Bags.db().keyringOpen ~= false
end

-- The section's entries, in slot order, and the number of keys among them.
-- Nothing while the section is folded or there is no key.
function Keyring.Entries(win)
    if not (win and win.key == "bags" and Keyring.Enabled() and Keyring.IsOpen()) then return nil, 0 end
    local id, keys, size = measure()
    if not id or keys == 0 then return nil, 0 end
    local out = {}
    for slot = 1, size do
        out[#out + 1] = { bag = id, slot = slot, info = C_Container.GetContainerItemInfo(id, slot) }
    end
    return out, keys
end

-- The key button in the tool row.
function Keyring.Toggle()
    local db = Bags.db()
    db.keyringOpen = not Keyring.IsOpen()
    Bags.Refresh()
end

-- The client's own keyring button: our window comes up with the keyring
-- unfolded; a second click folds it again.
function Keyring.FromClient()
    if not (Bags.mod.active and Bags.db().replaceBlizzard and Keyring.Enabled()) then return end
    -- No key, no section: a click then must not fold what is not there, or
    -- the first key looted later would arrive in a folded section.
    local _, keys = measure()
    if keys == 0 then return end
    local db = Bags.db()
    local shown = Bags.Window.IsShown()
    if shown and Keyring.IsOpen() then
        db.keyringOpen = false
    else
        db.keyringOpen = true
        if not shown then Bags.Window.Open() end
    end
    Bags.Refresh()
end
