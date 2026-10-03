-- VuloForeverUI / Modules / Bags / Options
--
-- Two tabs: the bags and the bank.
--
-- The bag tab is a strict two-column grid (optionsGrid): every setting keeps
-- its half of the page, including one that has no partner. A lone control on
-- full width puts its switch four hundred pixels from its own label, and a bag
-- page is mostly switches.
--
-- The settings are grouped the way the window is built: DISPLAY is everything
-- the eye sees on a slot or a shelf, EXTRAS is everything that is a tool
-- rather than a look.
local _, ns = ...
local L = ns.L
local Bags = ns.Bags

local mod = Bags.mod

mod.tabs = {
    { id = "bags", label = "Bags" },
    { id = "bank", label = "Bank" },
}
mod.optionsGrid = true

local function apply()
    if Bags.Window then Bags.Window.Refresh() end
    -- The client's bag frames follow the takeover switch both ways.
    if Bags.db().replaceBlizzard then Bags.ParkBlizzard() else Bags.UnparkBlizzard() end
    if Bags.Bank then
        -- bank takeover switched off: the client's own frame comes back
        if not Bags.db().bank then
            if Bags.Bank.IsShown() then Bags.Bank.Close() end
            Bags.Bank.RestoreBlizzard()
        end
        Bags.Bank.Refresh()
    end
end

local function db() return Bags.db() end

local rows = ns.OptionRows(db, apply)
local toggle, slider, dropdown, swatch = rows.toggle, rows.slider, rows.dropdown, rows.swatch
local gear, section = ns.OptionGear, ns.OptionSection

-- ---------------------------------------------------------------------------
-- The two multi-selects. Both write a SET (key -> true), because both answer
-- "which of these" and a list would have to be searched on every draw. The
-- box wants isChecked/toggle rather than get/set: the menu stays open and
-- repaints one row per click.
-- ---------------------------------------------------------------------------
local function setStore(key)
    return function()
        local t = db()[key]
        if type(t) ~= "table" then t = {}; db()[key] = t end
        return t
    end
end

local function multiRow(label, values, store, tooltip)
    return { type = "dropdown", label = label, values = values, width = 240,
        tooltip = tooltip, multi = true,
        isChecked = function(value) return store()[value] == true end,
        toggle = function(value)
            local t = store()
            t[value] = (t[value] == nil) and true or nil
            apply()
        end }
end

local function categoryRow()
    local values = {}
    for _, key in ipairs(Bags.Categories.OPTIONAL) do
        values[#values + 1] = { value = key, text = Bags.Categories.Label(key) }
    end
    return multiRow(L["Enabled categories"], values, setStore("enabledCategories"),
        L["Categories switched off here are folded into 'Everything else'. Nothing is hidden."])
end

-- The currencies this character actually has. Asked of the client rather than
-- hard-coded: a currency list is per expansion and per character, and a fixed
-- list would be wrong on the first character who has something else.
local function currencyRow()
    local values = {}
    local size = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize)
        and C_CurrencyInfo.GetCurrencyListSize() or 0
    for i = 1, size do
        local ok, entry = pcall(C_CurrencyInfo.GetCurrencyListInfo, i)
        if ok and type(entry) == "table" and not entry.isHeader and entry.currencyID then
            values[#values + 1] = { value = tostring(entry.currencyID), text = entry.name or tostring(entry.currencyID) }
        end
    end
    if #values == 0 then
        values[1] = { value = "none", text = L["This character has no currencies yet."], separator = true }
    end
    return multiRow(L["Enabled currencies"], values, setStore("currencies"))
end

-- ---------------------------------------------------------------------------
-- The bag page
-- ---------------------------------------------------------------------------
local function bagsPage()
    local d = db()

    local display = section(L["Display"], {
        slider("scale", L["Window scale"], 60, 160, 1, { scale = 100 }),
        slider("iconZoom", L["Icon zoom"], 0, 0.2, 0.01),
        toggle("roundSlots", L["Rounded slots"],
            L["Icons, borders and empty slots get rounded corners."]),

        toggle("hideEmptyCategories", L["Hide categories with 0 items"]),
        toggle("autoSize", L["Size automatically"],
            L["The window picks its own number of columns."]),

        toggle("mergeDuplicates", L["Merge duplicate items"],
            L["One icon per item, with the total underneath. The click still belongs to the stack that is drawn."]),
        toggle("dimJunk", L["Desaturate junk items"]),
        toggle("markJunk", L["Mark vendor junk with a C"],
            L["Grey items a vendor pays for get a C in the corner. Sorting puts them at the very end."]),

        toggle("splitEquipmentSets", L["Split set gear by set"]),
        toggle("showSetNames", L["Show set names on gear"], { inline = {
            swatch("setNameColor", { tooltip = L["Text color"], disabled = function() return not d.showSetNames end }),
            gear(L["Set names"], {
                slider("setNameSize", L["Size"], 6, 16, 1),
                slider("setNameLetters", L["Letters shown"], 1, 6, 1),
            }, { disabled = function() return not d.showSetNames end }),
        } }),

        toggle("showBindTags", L["Show BoE / warbound"], { inline = {
            swatch("bindTagColor", { tooltip = L["BoE color"], disabled = function() return not d.showBindTags end }),
            gear(L["BoE / warbound"], {
                slider("bindTagSize", L["Size"], 6, 16, 1),
            }, { disabled = function() return not d.showBindTags end }),
        } }),

        slider("categoryTitleSize", L["Category title size"], 8, 20, 1),
        -- The size of this one sits in its own row further down, the way the
        -- page pairs "show it" with "how big": the gear here would be a second
        -- control for the same number.
        toggle("showItemLevel", L["Show item level"], { inline = {
            swatch("itemLevelColor", { tooltip = L["Text color"], disabled = function() return not d.showItemLevel end }),
        } }),

        categoryRow(),
        currencyRow(),

        slider("countSize", L["Item count text size"], 7, 18, 1),
        slider("itemLevelSize", L["Item level text size"], 7, 18, 1,
            { disabled = function() return not d.showItemLevel end }),
    })

    local extras = section(L["Extras"], {
        toggle("showSortButton", L["Show the sort button"]),
        dropdown("sortMethod", L["Sort order"], {
            { value = "type",      text = L["By type"] },
            { value = "quality",   text = L["By quality"] },
            { value = "name",      text = L["By name"] },
            { value = "itemlevel", text = L["By item level"] },
        }, { tooltip = L["How the sort button lays out the bags and the bank. Stacks are combined first, the hearthstone always comes first and vendor junk always goes to the far end."] }),
        toggle("sortFromBottom", L["Sort from the bottom"],
            L["Fills the bags from the last slot upwards, with vendor junk at the top instead."]),
        toggle("goldTracking", L["Gold tracking and history"],
            L["The money line lists every character on the account and what this session has gained or lost."]),

        toggle("showPinned", L["Show pinned items"],
            L["Pinned items get a shelf of their own. The pin button in the window's tool row sets them."]),
        toggle("showRecent", L["Show recent items"],
            L["Anything picked up in the last half hour gets a shelf and a border."]),

        toggle("pinnedTips", L["Show pinned & recent tips"]),
        toggle("hideBagWarnings", L["Hide the bag warnings"],
            L["The window says when a fight stopped it from building more slots. This silences that."]),

        toggle("moveWithoutShift", L["Move bags without shift"]),

        toggle("groupArmoryBySlot", L["Group armoury by slot"],
            L["Gear is shelved by where it is worn instead of by category."]),
        toggle("stackSplitter", L["Stack splitter"],
            L["Adds a split tool to the window's tool row."]),

        toggle("replaceBlizzard", L["Open instead of the client's bags"],
            L["The client's own bag windows are closed again whenever they open."]),
        toggle("categories", L["Sort into categories"]),

        slider("columns", L["Columns"], 6, 20, 1, { disabled = function() return d.autoSize end }),
        slider("slotSize", L["Slot size"], 24, 52, 1),

        slider("spacing", L["Spacing"], 0, 12, 1),
        ns.BorderRows(rows, { size = "borderSize", color = "borderColor" }),

        toggle("search", L["Show the search box"]),
        toggle("qualityBorder", L["Colour the border by quality"]),
        toggle("markBagFamily", L["Mark profession bag slots"],
            L["Slots in a herb, enchanting, mining or other profession bag are tinted in that bag's colour, so they stand apart from the normal bag space."]),

        toggle("showFreeSlots", L["Show the free slots"]),
        toggle("showMoney", L["Show your money"]),

        toggle("showCount", L["Show the stack count"]),
        { type = "button", label = L["Open the bags"], onClick = function()
            if Bags.Window then Bags.Window.Toggle() end
        end },
    })

    -- The view first, on its own: which way the window lays the bags out is the
    -- first thing anyone looks for, and inside the display list it was lost
    -- between the gear switches.
    local view = section(L["Bag view"], {
        dropdown("defaultView", L["Bag view"], Bags.Categories.ViewValues(),
            { tooltip = L["All items sorted into categories, all bags as one block, or one block per bag. The window opens on this; its side bar switches between them."] }),
    })

    return {
        { type = "desc", text = L["|cffaaaaaaHold shift and drag to move the bag window. Clicking an item in the window uses it, exactly as it does in the client's own bags -- the pin and split tools sit in the window's own tool row because of that.|r"] },
        view,
        display,
        extras,
    }
end

-- ---------------------------------------------------------------------------
-- The bank page
--
-- Only what is the BANK'S own: how it groups, and its side bar. Everything
-- about how a slot looks -- scale, icon zoom, item level, the marks -- is one
-- set of settings for both windows, and the hint at the top says so rather
-- than the page carrying a second copy of every slider.
-- ---------------------------------------------------------------------------
local function bankPage()
    local d = db()
    local ungrouped = function()
        return not d.bankGroupByCategory
    end

    return {
        { type = "desc", text = L["Right-click a tab in the bank sidebar to rename it or set its deposit filters."] },
        { type = "desc", text = L["Window scale, icon zoom and item level settings are shared with the Bags page."] },

        section(L["Bank"], {
            toggle("bank", L["Take over the bank as well"]),
            { type = "button", label = L["Reset the bank position"], onClick = function()
                Bags.db().bankPos = nil
                if Bags.Bank then Bags.Bank.Refresh() end
            end },
            { type = "desc", text = L["|cffaaaaaaThe bank window opens when you step up to a banker. The client's own bank frame is only hidden, never closed -- closing it would end the visit.|r"] },
        }),

        section(L["Grouping"], {
            toggle("bankGroupByCategory", L["Group by category"]),
        }),

        section(L["Sidebar"], {
            toggle("bankSidebar", L["Category sidebar"],
                L["A column of buttons down the left edge: everything, each bank tab, each shelf. A click filters the window to one of them."]),
            toggle("bankHideTabsInSidebar", L["Hide bank tabs in sidebar"], { disabled = function() return not d.bankSidebar end }),

            toggle("bankHideEmptyWhenGrouped", L["Hide empty slots when grouped"], { disabled = ungrouped }),
        }),
    }
end

function mod:GetOptions(tabId)
    if tabId == "bank" then return bankPage() end
    return bagsPage()
end
