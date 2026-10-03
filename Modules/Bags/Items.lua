-- VuloForeverUI / Modules / Bags / Items
--
-- The facts about an item that the bag window asks for over and over: what it
-- binds like, which expansion it is from, which slot it is worn in, whether it
-- belongs to an equipment set.
--
-- Cached per item id, because the layout asks for them once per slot per draw
-- and C_Item.GetItemInfo is a database lookup, not a table read. The cache is
-- only filled with ANSWERED lookups: an item the client has not loaded yet
-- answers with nils, and remembering those would mean the first draw after a
-- login decides the tags for the rest of the session.
--
-- Nothing here is secret. Item data is plain on this client -- the restricted
-- values live on units, not in bags -- so these are ordinary reads.
local _, ns = ...
local Bags = ns.Bags

local Items = {}
Bags.Items = Items

local BIND  = Enum.ItemBind or {}
local ON_EQUIP  = BIND.OnEquip or 2
local TO_WOW    = BIND.ToWoWAccount or 7
local TO_BNET   = BIND.ToBnetAccount or 8
local TO_BNET_E = BIND.ToBnetAccountUntilEquipped or 9

local facts = {}

-- C_Item.GetItemInfo hands back the long list; the three fields wanted here sit
-- at 9 (equip location), 14 (bind type) and 15 (expansion). Asked by position
-- because that is how the client returns them, and checked by type because a
-- client that returns one field fewer must not silently shift the others.
local function lookup(itemID)
    local cached = facts[itemID]
    if cached then return cached end
    if type(C_Item.GetItemInfo) ~= "function" then return nil end

    local _, _, _, _, _, _, _, _, equipLoc, _, _, _, _, bind, expac = C_Item.GetItemInfo(itemID)
    -- Not loaded yet: answered later, from the draw that follows the client's
    -- own GET_ITEM_INFO_RECEIVED.
    if bind == nil and expac == nil and equipLoc == nil then return nil end

    local entry = {
        bind     = type(bind) == "number" and bind or nil,
        expac    = type(expac) == "number" and expac or nil,
        equipLoc = (type(equipLoc) == "string" and equipLoc ~= "") and equipLoc or nil,
    }
    facts[itemID] = entry
    return entry
end

function Items.Facts(info)
    if not (info and type(info.itemID) == "number") then return nil end
    return lookup(info.itemID)
end

-- ---------------------------------------------------------------- tags --

-- "BoE" for something that binds when it is equipped, "WuE" for anything bound
-- to the account rather than to this character. Two short tags rather than the
-- client's own sentences: they sit in the corner of a 37 px icon.
function Items.BindTag(info)
    local f = Items.Facts(info)
    local bind = f and f.bind
    if not bind then return nil end
    if bind == ON_EQUIP then return "BoE" end
    if bind == TO_WOW or bind == TO_BNET or bind == TO_BNET_E then return "WuE" end
    return nil
end

-- Where a piece of gear is worn. INVTYPE_HEAD and its siblings are client
-- strings as well, so the armoury groups come out in the player's language.
function Items.EquipLoc(info)
    local f = Items.Facts(info)
    return f and f.equipLoc or nil
end

function Items.EquipLocLabel(loc)
    local name = _G[loc]
    if type(name) == "string" and name ~= "" then return name end
    return loc
end

-- ---------------------------------------------------------------- sets --

-- Which equipment set a slot's item belongs to. Asked of the CONTAINER, not of
-- C_EquipmentSet: the client already knows the answer for a bag slot and gives
-- it for the exact stack, which is what a bag window is drawing.
--
-- The second return is a list of names when an item is in several sets; the
-- first of them is the one drawn, because one corner of one icon is what there
-- is room for.
function Items.SetName(bagID, slotID)
    local fn = C_Container.GetContainerItemEquipmentSetInfo
    if type(fn) ~= "function" then return nil end
    local ok, inSet, list = pcall(fn, bagID, slotID)
    if not (ok and inSet) then return nil end
    if type(list) ~= "string" or list == "" then return nil end
    local first = list:match("^([^,]+)")
    return first and (first:gsub("^%s+", ""):gsub("%s+$", "")) or nil
end

-- The client answers GET_ITEM_INFO_RECEIVED for items it had to fetch. Facts
-- cached from an answered lookup stay; this only drops the ones never cached,
-- which costs nothing and is what makes a tag appear on the next draw.
function Items.Forget(itemID)
    if type(itemID) == "number" then facts[itemID] = nil end
end

-- ---------------------------------------------------------------- upgrade --

-- Where an equip location is worn. Two slots for rings, trinkets and a
-- one-hand weapon: the bag item is an upgrade when it beats the WEAKER of the
-- two, because that is the one it would replace.
local MAIN, OFF = 16, 17
local WORN = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { MAIN, OFF }, INVTYPE_2HWEAPON = { MAIN },
    INVTYPE_WEAPONMAINHAND = { MAIN }, INVTYPE_WEAPONOFFHAND = { OFF },
    INVTYPE_HOLDABLE = { OFF }, INVTYPE_SHIELD = { OFF },
}

-- This client has no ranged slot of its own: a bow, a wand or a gun is worn
-- in the main hand.
local RANGED = {
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true, INVTYPE_RELIC = true,
}

local function mainIsTwoHanded()
    local id = GetInventoryItemID("player", MAIN)
    if type(id) ~= "number" then return false end
    local _, _, _, loc = C_Item.GetItemInfoInstant(id)
    return loc == "INVTYPE_2HWEAPON" or (loc ~= nil and RANGED[loc] == true)
end

-- The slots a bag item would go into. An off hand only counts while it can
-- be worn at all: not beside a two-hander, and a one-hand weapon goes there
-- only for a character that can wield two.
local function slotsFor(loc)
    if RANGED[loc] then return { MAIN } end
    if loc == "INVTYPE_WEAPON" then
        if CanDualWield() and not mainIsTwoHanded() then return { MAIN, OFF } end
        return { MAIN }
    end
    local slots = WORN[loc]
    if slots and slots[1] == OFF and mainIsTwoHanded() then return nil end
    return slots
end

-- What is worn, by slot: its item level, or false for an empty slot. Asked
-- once per slot until the equipment changes.
local worn = {}

local function wornLevel(invSlot)
    local cached = worn[invSlot]
    if cached ~= nil then return cached end
    local loc = ItemLocation:CreateFromEquipmentSlot(invSlot)
    local value = false
    if C_Item.DoesItemExist(loc) then
        local ok, level = pcall(C_Item.GetCurrentItemLevel, loc)
        value = (ok and type(level) == "number") and level or 0
    end
    worn[invSlot] = value
    return value
end

function Items.ForgetWorn()
    wipe(worn)
end

-- Would the player be better off wearing this? Judged by item level alone,
-- and only for gear this character can wear today: the client's own "can use"
-- covers class and armour type, the level requirement is checked here.
function Items.IsUpgrade(bagID, slotID, info)
    if not (info and type(info.itemID) == "number") then return false end
    local loc = Items.EquipLoc(info)
    local targets = loc and slotsFor(loc)
    if not targets then return false end
    if not C_Item.IsEquippableItem(info.itemID) then return false end
    if C_PlayerInfo.CanUseItem and not C_PlayerInfo.CanUseItem(info.itemID) then return false end
    local minLevel = select(5, C_Item.GetItemInfo(info.itemID))
    if type(minLevel) == "number" and minLevel > UnitLevel("player") then return false end

    local here = ItemLocation:CreateFromBagAndSlot(bagID, slotID)
    local ok, level = pcall(C_Item.GetCurrentItemLevel, here)
    if not (ok and type(level) == "number") then return false end

    local weakest
    for _, invSlot in ipairs(targets) do
        local w = wornLevel(invSlot)
        if w == false then return true end
        if not weakest or w < weakest then weakest = w end
    end
    -- A two-hander replaces the off hand as well, but comparing it against
    -- the main hand alone is the honest guess an item level allows.
    return weakest ~= nil and level > weakest
end
