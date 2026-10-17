-- VuloForeverUI / Modules / Skins / Options
--
-- One card per thing that can be skinned: its name, a line on what it
-- covers, its look on the right (Off / Standard / Modern), and an arrow that
-- folds out its own settings. New skin targets are new cards on this page,
-- not new tabs. The tab shows even while it is the only one (tabsAlways).
local _, ns = ...
local L = ns.L
local Skins = ns.Skins
local mod = Skins.mod

mod.tabs = {
    { id = "windows", label = "Window skins" },
}
mod.tabsAlways = true

local function looks()
    return {
        { value = "off",      text = L["Off"] },
        { value = "standard", text = L["Standard"] },
        { value = "modern",   text = L["Modern"] },
    }
end

local rows = ns.OptionRows(function() return Skins.db() end, function() Skins.Apply() end)

-- A card's look: "off" is the window's own switch, the rest its style key.
local function lookOf(onKey, styleKey, tbl)
    return function()
        local t = tbl()
        if not t[onKey] then return "off" end
        return t[styleKey] or "standard"
    end, function(_, v)
        local t = tbl()
        if v == "off" then t[onKey] = false else t[onKey] = true; t[styleKey] = v end
        Skins.Apply()
        if Skins.Guide then Skins.Guide.Apply() end
    end
end

function mod:GetOptions()
    local items = {}
    local win = function() return Skins.db() end
    local guide = function() return mod.db.guide end

    local get, set = lookOf("character", "style", win)
    items[#items + 1] = { type = "card", key = "character", icon = "Interface\\Icons\\INV_Shirt_White_01",
        title = L["Character window"],
        desc = L["Equipment slots with quality rings, item level, enchants, durability and weapon DPS; the stats with sections that fold."],
        values = looks(), get = get, set = set,
        items = {
            { type = "header", text = L["On the slots"] },
            rows.toggle("itemLevel", L["Item level"]),
            rows.toggle("enchants", L["Enchants as text"], L["The enchant of each piece beside its slot; on a weapon also the poison, oil or stone on it."]),
            rows.toggle("durability", L["Durability"], L["Yellow below 50 %, red below 20 %. Your own window only."]),
            rows.toggle("weaponDps", L["Weapon DPS"], L["Damage per second beside each weapon slot, above its enchant."]),
            { type = "header", text = L["Average item level"] },
            rows.toggle("avgItemLevel", L["Show average item level"], L["Beside your level above the model: the average of what you wear, as the stats show it."]),
            rows.dropdown("avgItemLevelColor", L["Text color"], {
                { value = "quality", text = L["By quality"] },
                { value = "custom",  text = L["Custom color"] },
            }),
            rows.color("avgItemLevelCustom", L["Custom color"],
                { disabled = function() return Skins.db().avgItemLevelColor ~= "custom" end }),
            { type = "header", text = L["Stats"] },
            rows.toggle("statSections", L["Fold stat sections"], L["A click on a section title in the stats folds it; the window remembers it."]),
        } }

    get, set = lookOf("inspect", "inspectStyle", win)
    items[#items + 1] = { type = "card", key = "inspect", icon = "Interface\\Icons\\INV_Misc_Spyglass_02",
        title = L["Inspect window"],
        desc = L["Another player's equipment: quality rings, item level and enchants, like your own window."],
        values = looks(), get = get, set = set,
        items = {
            rows.toggle("inspectAvgItemLevel", L["Show average item level"],
                L["Beside the player's level, in the colour chosen for your character window."]),
        } }

    get, set = lookOf("enabled", "style", guide)
    local installed = Skins.Guide and Skins.Guide.Installed()
    items[#items + 1] = { type = "card", key = "guide", icon = "Interface\\Icons\\INV_Misc_Book_09",
        title = L["Levelling guide"],
        desc = installed and L["The guide window, the current-step boxes, the waypoint arrow and the targets window. Off takes effect after /reload."]
            or L["No levelling guide addon is loaded."],
        values = looks(), get = get, set = set }
    return items
end
