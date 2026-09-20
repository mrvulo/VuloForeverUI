-- VuloForeverUI / Modules / Bags / Categories
--
-- Which shelf an item belongs on.
--
-- Decided from the item's CLASS NUMBER, never from the type name: the names
-- the client returns are translated, so "Armor" only ever matches on an
-- English client and a German one would put every piece of armour in the
-- leftovers. The numbers are the same everywhere.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local Categories = {}
Bags.Categories = Categories

local C = Enum.ItemClass or {}

-- The shelves, in the order they are drawn. The key is what the layout uses,
-- the label is built lazily further down.
Categories.ORDER = {
    "equipment", "consumable", "tradegoods", "quest", "reagent", "misc", "junk",
}

-- A label read at file scope would be read before the saved language exists.
function Categories.Label(key)
    local labels = {
        equipment  = L["Equipment"],
        consumable = L["Consumables"],
        tradegoods = L["Trade goods"],
        quest      = L["Quest"],
        reagent    = L["Reagents"],
        misc       = L["Everything else"],
        junk       = L["Junk"],
    }
    return labels[key] or key
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

-- The one classification call. `info` is what the client handed us for the
-- slot, so the quality is already known and only the class has to be looked up.
function Categories.For(info)
    if not info then return nil end

    -- Grey items are their own shelf whatever they are otherwise: the point of
    -- the pile is that it can all be sold.
    if type(info.quality) == "number" and info.quality == POOR then return "junk" end

    local itemID = info.itemID
    if type(itemID) ~= "number" then return "misc" end

    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    if type(classID) ~= "number" then return "misc" end
    return BY_CLASS[classID] or "misc"
end

-- Is this item a piece of gear, and therefore worth an item level on it? The
-- same class numbers, asked separately because the shelf lumps weapons and
-- armour together while the item level belongs on both but on nothing else.
function Categories.IsGear(info)
    if not (info and type(info.itemID) == "number") then return false end
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(info.itemID)
    return classID == (C.Weapon or 2) or classID == (C.Armor or 4)
end
