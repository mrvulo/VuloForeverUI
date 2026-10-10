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
    { id = "guide",   label = "Levelling guide" },
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
        rows.toggle("weaponDps", L["Weapon DPS"], L["Damage per second beside each weapon slot, above its enchant."]),

        { type = "header", text = L["Stats"] },
        rows.toggle("statSections", L["Fold stat sections"], L["A click on a section title in the stats folds it; the window remembers it."]),
    }
end

local guideRows = ns.OptionRows(function() return mod.db.guide end, function()
    if Skins.Guide then Skins.Guide.Apply() end
end)

local function guidePage()
    local items = {
        { type = "header", text = L["Levelling guide"] },
    }
    if not (Skins.Guide and Skins.Guide.Installed()) then
        items[#items + 1] = { type = "desc", text = L["|cffaaaaaaNo levelling guide addon is loaded.|r"] }
    end
    items[#items + 1] = guideRows.toggle("enabled", L["Skin the levelling guide"],
        L["Its guide window and the current-step boxes. Switching it off takes effect after /reload."])
    items[#items + 1] = guideRows.dropdown("style", L["Style"], {
        { value = "standard", text = L["Standard"] },
        { value = "modern",   text = L["Modern"] },
    }, L["Standard: the game's tooltip frame. Modern: flat and dark like our windows."])
    return items
end

function mod:GetOptions(tabId)
    if tabId == "guide" then return guidePage() end
    return windowsPage()
end
