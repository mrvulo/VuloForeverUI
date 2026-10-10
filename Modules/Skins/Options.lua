-- VuloForeverUI / Modules / Skins / Options
--
-- One tab per kind of skin; "Window skins" is the first. The tab shows even
-- while it is the only one (tabsAlways), so the page keeps its place when
-- the next kind arrives.
local _, ns = ...
local L = ns.L
local Skins = ns.Skins
local mod = Skins.mod

mod.tabs = {
    { id = "windows", label = "Window skins" },
}
mod.tabsAlways = true

local rows = ns.OptionRows(function() return Skins.db() end, function() Skins.Apply() end)

local function windowsPage()
    return {
        { type = "header", text = L["Style"] },
        rows.dropdown("style", L["Style"], {
            { value = "standard", text = L["Standard"] },
            { value = "modern",   text = L["Modern"] },
        }, L["Standard keeps the game's own frame; Modern makes it flat and dark. Both round the slots and ring them in the item's quality colour. Open the character window (C) to see a change at once."]),

        { type = "header", text = L["Windows"] },
        rows.toggle("character", L["Character window"]),
        rows.toggle("inspect", L["Inspect window"]),

        { type = "header", text = L["On the slots"] },
        rows.toggle("itemLevel", L["Item level"]),
        rows.toggle("enchants", L["Enchants as text"], L["The enchant of each piece beside its slot; on a weapon also the poison, oil or stone on it."]),
        rows.toggle("durability", L["Durability"], L["Yellow below 50 %, red below 20 %. Your own window only."]),

        { type = "header", text = L["Stats"] },
        rows.toggle("statSections", L["Fold stat sections"], L["A click on a section title in the stats folds it; the window remembers it."]),
    }
end

function mod:GetOptions()
    return windowsPage()
end
