-- VuloForeverUI / Modules / Bags / Categories
--
-- Which shelf an item belongs on, and in which order the shelves are drawn.
--
-- Decided from the item's CLASS NUMBER, never from the type name: the names
-- the client returns are translated, so "Armor" only ever matches on an
-- English client and a German one would put every piece of armour in the
-- leftovers. The numbers are the same everywhere.
--
-- On top of the seven fixed shelves there are shelves that only exist while
-- the bag holds something for them: one per equipment set, one per armour
-- slot, plus the two the player drives (pinned, recent).
-- They are KEYS WITH A PREFIX ("set:Tank", "slot:INVTYPE_HEAD"), not
-- entries in a list somebody has to keep in step with the bags.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Categories = {}
Bags.Categories = Categories

local C = Enum.ItemClass or {}

-- The fixed shelves, in the order they are drawn. The key is what the layout
-- uses, the label is built lazily further down.
Categories.ORDER = {
    "equipment", "consumable", "tradegoods", "quest", "reagent", "misc", "junk",
}

-- What the "enabled categories" setting may switch off. Pinned, recent and the
-- free slots are not in here: those are driven by their own settings.
Categories.OPTIONAL = Categories.ORDER

-- A label read at file scope would be read before the saved language exists.
local function fixedLabel(key)
    local labels = {
        equipment  = L["Equipment"],
        consumable = L["Consumables"],
        tradegoods = L["Trade goods"],
        quest      = L["Quest"],
        reagent    = L["Reagents"],
        misc       = L["Everything else"],
        junk       = L["Junk"],
        pinned     = L["Pinned"],
        recent     = L["Recent"],
        free       = L["Free"],
        all        = L["All items"],
    }
    return labels[key]
end

function Categories.Label(key)
    local fixed = fixedLabel(key)
    if fixed then return fixed end
    local kind, rest = tostring(key):match("^(%a+):(.+)$")
    if kind == "set"  then return rest end
    if kind == "slot" then return Bags.Items.EquipLocLabel(rest) end
    return key
end

-- Class numbers to shelves. Anything not named here falls to "misc", which is
-- the honest place for a class this client has and we have not met.
local BY_CLASS = {
    [C.Weapon or 2]        = "equipment",
    [C.Armor or 4]         = "equipment",
    [C.Consumable or 0]    = "consumable",
    [C.Tradegoods or 7]    = "tradegoods",
    [C.Reagent or 5]       = "reagent",
    [C.Questitem or 12]    = "quest",
    [C.Recipe or 9]        = "tradegoods",
    [C.Gem or 3]           = "tradegoods",
    [C.Glyph or 16]        = "tradegoods",
    [C.ItemEnhancement or 8] = "tradegoods",
    [C.Projectile or 6]    = "consumable",
    [C.Container or 1]     = "misc",
    [C.Miscellaneous or 15] = "misc",
}

local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- Is a fixed shelf switched on? An empty setting means all of them: a player
-- who has never opened the list has not switched anything off.
function Categories.Enabled(key)
    local list = Bags.db().enabledCategories
    if type(list) ~= "table" or next(list) == nil then return true end
    return list[key] == true
end

-- The class shelf, before any of the groupings get a say.
local function classOf(info)
    if type(info.quality) == "number" and info.quality == POOR then return "junk" end
    local itemID = info.itemID
    if type(itemID) ~= "number" then return "misc" end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if type(classID) ~= "number" then return "misc" end
    return BY_CLASS[classID] or "misc"
end
Categories.ClassOf = classOf

-- ---------------------------------------------------------------- bucket --

-- WHICH GROUPINGS A WINDOW USES IS THE WINDOW'S OWN BUSINESS. The bags and
-- the bank are two different jobs -- the bags are worked in, the bank is
-- stored in -- so each carries its own switches and the shelf logic below is
-- handed the answers rather than reading the settings itself.
function Categories.Rules(winKey)
    local db = Bags.db()
    if winKey == "bank" then
        return {
            categories = db.bankGroupByCategory,
            hideEmpty  = db.bankHideEmptyWhenGrouped,
        }
    end
    return {
        categories = db.categories,
        armory     = db.groupArmoryBySlot,
        sets       = db.splitEquipmentSets,
        pinned     = db.showPinned,
        recent     = db.showRecent,
    }
end

-- Is this window grouped at all? "Hide empty slots when grouped" hangs on
-- this, and so does the sidebar: an ungrouped window has one shelf and a bar
-- with one button on it would be furniture.
function Categories.Grouped(rules)
    return (rules.categories or rules.armory or rules.sets) and true or false
end

-- THE ORDER OF THE QUESTIONS IS THE FEATURE. A pinned item is pinned whatever
-- else it is; grey is grey before it is armour; and the three groupings are
-- asked from the most specific to the least, so a tier set piece lands under
-- its set rather than under "Head" or under "Classic".
function Categories.For(entry, rules)
    local info = entry and entry.info
    if not info then return nil end
    local id = info.itemID

    if rules.pinned and Bags.Marks.IsPinned(id) then return "pinned" end
    if rules.recent and Bags.Marks.IsRecent(id) then return "recent" end

    local class = classOf(info)
    if class == "junk" then
        return Categories.Enabled("junk") and "junk" or "misc"
    end

    if class == "equipment" then
        if rules.sets then
            local set = Bags.Items.SetName(entry.bag, entry.slot)
            if set then return "set:" .. set end
        end
        if rules.armory then
            local loc = Bags.Items.EquipLoc(info)
            if loc then return "slot:" .. loc end
        end
    end

    -- Neither grouping is on: one shelf, no heading. The gear groupings above
    -- may still have answered -- somebody can split sets out without wanting
    -- the rest of the bag sorted at all.
    if not rules.categories then return "all" end
    if not Categories.Enabled(class) then return "misc" end
    return class
end

-- ---------------------------------------------------------------- order --

-- Where a shelf sits. The fixed ones keep their place in ORDER; a grouping
-- shelf takes the place of the shelf it replaced, so turning "group armoury
-- by slot" on does not shuffle the window into a new shape every draw.
local RANK = { pinned = -20, recent = -19, free = 100 }
for i, key in ipairs(Categories.ORDER) do RANK[key] = i end

-- The slot order the client itself uses, top to bottom of a character sheet.
-- Alphabetical would put Feet above Head, which reads as a list rather than as
-- a set of armour.
local SLOT_RANK = {}
for i, loc in ipairs({
    "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_CLOAK",
    "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_BODY", "INVTYPE_TABARD",
    "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_WAIST", "INVTYPE_LEGS",
    "INVTYPE_FEET", "INVTYPE_FINGER", "INVTYPE_TRINKET",
    "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND",
    "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "INVTYPE_SHIELD",
    "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN", "INVTYPE_RELIC",
}) do SLOT_RANK[loc] = i end

local function rankOf(key)
    local fixed = RANK[key]
    if fixed then return fixed, 0, key end
    local kind, rest = tostring(key):match("^(%a+):(.+)$")
    -- Both gear groupings sit where "equipment" sits, sets first (a player
    -- made those), then armour slots in character-sheet order.
    if kind == "set"  then return RANK.equipment or 1, -1, rest end
    if kind == "slot" then return RANK.equipment or 1, SLOT_RANK[rest] or 99, rest end
    return 50, 0, tostring(key)
end

-- Sorts the shelves a draw produced. Stable and total: two shelves with the
-- same rank fall back to their own names, so the window never re-orders itself
-- between two draws of the same bags.
function Categories.Sort(keys)
    table.sort(keys, function(a, b)
        local ra, sa, na = rankOf(a)
        local rb, sb, nb = rankOf(b)
        if ra ~= rb then return ra < rb end
        if sa ~= sb then return sa < sb end
        return na < nb
    end)
    return keys
end

-- Is this item a piece of gear, and therefore worth an item level on it? The
-- same class numbers, asked separately because the shelf lumps weapons and
-- armour together while the item level belongs on both but on nothing else.
function Categories.IsGear(info)
    if not (info and type(info.itemID) == "number") then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
    return classID == (C.Weapon or 2) or classID == (C.Armor or 4)
end

-- The dropdown behind "default bag type" and the side bar: the shelves a
-- player can ask for by name, all items first.
function Categories.ViewValues()
    local values = {
        { value = "all", text = L["All items"] },
        { value = "allbags", text = L["All bags"] },
        { value = "perbag", text = L["Per bag"] },
    }
    for _, key in ipairs(Categories.ORDER) do
        values[#values + 1] = { value = key, text = Categories.Label(key) }
    end
    return values
end
