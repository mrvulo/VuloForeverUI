-- VuloForeverUI / Modules / Bags / Options
--
-- Three tabs: the window, what a slot shows, and what goes in which section.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local mod = Bags.mod

mod.tabs = {
    { id = "window",     label = "Window" },
    { id = "slots",      label = "Slots" },
    { id = "categories", label = "Categories" },
}

local function apply()
    if Bags.Window then Bags.Window.Refresh() end
    if Bags.Bank then Bags.Bank.Refresh() end
end

local function toggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return Bags.db()[key] end,
        set = function(_, v) Bags.db()[key] = v; apply() end }
end

local function slider(key, label, min, max, step)
    return { type = "slider", label = label, min = min, max = max, step = step,
        get = function() return Bags.db()[key] end,
        set = function(_, v) Bags.db()[key] = v; apply() end }
end

local function color(key, label)
    return { type = "color", label = label,
        get = function() return Bags.db()[key] end,
        set = function(r, g, b)
            local c = Bags.db()[key]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

local function windowPage()
    return {
        toggle("replaceBlizzard", L["Open instead of the client's bags"],
            L["The client's own bag windows are closed again whenever they open."]),
        { type = "header", text = L["Layout"] },
        slider("columns", L["Columns"], 6, 20, 1),
        slider("slotSize", L["Slot size"], 24, 52, 1),
        slider("spacing", L["Spacing"], 0, 12, 1),
        slider("scale", L["Scale"], 0.6, 1.6, 0.05),
        { type = "header", text = L["The frame"] },
        color("bgColor", L["Background color"]),
        slider("borderSize", L["Border size"], 0, 4, 1),
        color("borderColor", L["Border color"]),
        { type = "header", text = L["The header"] },
        toggle("search", L["Show the search box"]),
        toggle("showFreeSlots", L["Show the free slots"]),
        toggle("showMoney", L["Show your money"]),
        { type = "header", text = L["The bank"] },
        toggle("bank", L["Take over the bank as well"]),
        { type = "desc", text = L["|cffaaaaaaThe bank window opens when you step up to a banker. The client's own bank frame is only hidden, never closed -- closing it would end the visit.|r"] },
        { type = "button", label = L["Open the bags"], onClick = function()
            if Bags.Window then Bags.Window.Toggle() end
        end },
    }
end

local function slotsPage()
    return {
        { type = "header", text = L["On every slot"] },
        toggle("qualityBorder", L["Colour the border by quality"]),
        toggle("showCount", L["Show the stack count"]),
        toggle("dimJunk", L["Dim grey items"]),
        { type = "header", text = L["On gear"] },
        toggle("showItemLevel", L["Show the item level"]),
        slider("itemLevelSize", L["Item level size"], 7, 18, 1),
        color("itemLevelColor", L["Item level color"]),
        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaThe slots are the client's own item buttons, so a click uses, equips or moves the item exactly as it does in the client's bags. That also means a slot can only be created outside combat.|r"] },
    }
end

local function categoriesPage()
    local page = {
        toggle("categories", L["Sort into categories"]),
        toggle("hideEmptyCategories", L["Hide empty categories"]),
        { type = "desc", text = L["|cffaaaaaaThe category of an item comes from its class number, not from the name of its type: type names are translated, so a name would only ever match on an English client.|r"] },
        { type = "header", text = L["The order"] },
    }
    for _, key in ipairs(Bags.Categories.ORDER) do
        page[#page + 1] = { type = "desc", text = "|cffcccccc- " .. Bags.Categories.Label(key) .. "|r" }
    end
    return page
end

function mod:GetOptions(tabId)
    if tabId == "slots"      then return slotsPage() end
    if tabId == "categories" then return categoriesPage() end
    return windowPage()
end
