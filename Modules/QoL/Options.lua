-- VuloForeverUI / Modules / QoL / Options
--
-- Four tabs, one per part. Every setter writes and then calls QoL.Apply(),
-- which lets each part decide for itself what changed -- the options never
-- know which switch turns which event on.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local mod = QoL.mod

local function apply()
    QoL.Apply()
end

-- sub is the name of a table inside the module db, or nil for the db itself.
local function tbl(sub)
    local db = QoL.db()
    return sub and db[sub] or db
end

local function toggle(sub, key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return tbl(sub)[key] end,
        set = function(_, v) tbl(sub)[key] = v; apply() end }
end

local function slider(sub, key, label, min, max, step, tooltip)
    return { type = "slider", label = label, min = min, max = max, step = step, tooltip = tooltip,
        get = function() return tbl(sub)[key] end,
        set = function(_, v) tbl(sub)[key] = v; apply() end }
end

local function color(sub, key, label)
    return { type = "color", label = label,
        get = function() return tbl(sub)[key] end,
        set = function(r, g, b)
            local c = tbl(sub)[key]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

local function dropdown(sub, key, label, values, width)
    return { type = "dropdown", label = label, width = width or 200, values = values,
        get = function() return tbl(sub)[key] end,
        set = function(_, v) tbl(sub)[key] = v; apply() end }
end

local function editbox(sub, key, label, width)
    return { type = "editbox", label = label, width = width or 240, editWidth = 140,
        get = function() return tbl(sub)[key] end,
        set = function(_, v) tbl(sub)[key] = v; apply() end }
end

-- ------------------------------------------------------------- vendor --

local function vendorPage()
    return {
        { type = "header", text = L["At the merchant"] },
        toggle(nil, "sellJunk", L["Sell grey items"],
            L["The client drops sell requests past its own rate limit, so the greys are counted again after every pass and the sweep runs until the count stops falling."]),
        toggle(nil, "repairAll", L["Repair everything"]),
        toggle(nil, "repairGuild", L["Use the guild bank when it may"],
            L["The server pays what the allowance covers and charges you the rest; it never refuses the repair for want of guild funds."]),
        toggle(nil, "repairReport", L["Say what it cost"]),
        toggle(nil, "repairCoinIcons", L["Coin icons instead of letters"]),

        { type = "header", text = L["Durability warning"] },
        toggle("durability", "enabled", L["Warn before the gear is gone"]),
        slider("durability", "threshold", L["Warn below"], 5, 95, 5),
        slider("durability", "fontSize", L["Text size"], 10, 48, 1),
        color("durability", "color", L["Text color"]),
        { type = "button", label = L["Show it once"], onClick = function()
            QoL.Vendor.PreviewDurability()
        end },
        { type = "desc", text = L["|cffaaaaaaThe warning stays hidden during a fight: there is nothing you could do about it there.|r"] },
    }
end

-- --------------------------------------------------------------- loot --

local function lootPage()
    return {
        { type = "header", text = L["Looting"] },
        toggle(nil, "quickLoot", L["Loot everything in one click"],
            L["Hold shift while looting to open the window as usual."]),
        slider(nil, "quickLootDelay", L["Between two slots"], 0.02, 0.2, 0.01,
            L["The server answers each slot on its own; a burst past its limit loses the last ones."]),

        { type = "header", text = L["Containers"] },
        toggle(nil, "autoOpen", L["Open what can be opened"],
            L["One container at a time, never while a merchant, the mail or the bank is open, and never while you are casting -- opening something cancels a cast without saying so."]),
        { type = "desc", text = L["|cffaaaaaaA container that changes nothing after being opened -- full bags, a unique you already own -- is left alone until the next login.|r"] },

        { type = "header", text = L["Deleting"] },
        toggle(nil, "autoFillDelete", L["Type the delete word for you"],
            L["Only the box is filled in. The button is still yours to press."]),
    }
end

-- -------------------------------------------------------------- stats --

local function statsPage()
    local page = {
        toggle("stats", "enabled", L["Show the secondary stats"]),
        { type = "desc", text = L["|cffaaaaaaThe client hands these over as secret values in instances, so they are never read here -- they are passed straight to the text widget, which is why they stay live during a fight.|r"] },

        { type = "header", text = L["What it shows"] },
        toggle("stats", "showRating", L["The rating instead of the percentage"]),
        toggle("stats", "showBoth", L["Both, rating and percentage"]),
        toggle("stats", "abbreviate", L["One letter instead of the name"]),
        toggle("stats", "coloredValues", L["Colour the value as well"]),
    }

    -- The rows themselves: hidden is a set, so a row is listed by its absence.
    page[#page + 1] = { type = "header", text = L["The rows"] }
    for _, row in ipairs(QoL.Stats.ROWS) do
        local key = row.key
        page[#page + 1] = { type = "toggle", label = L[row.label],
            get = function() return not QoL.db().stats.hidden[key] end,
            set = function(_, v)
                QoL.db().stats.hidden[key] = (not v) or nil
                apply()
            end }
    end

    page[#page + 1] = { type = "header", text = L["The look"] }
    page[#page + 1] = slider("stats", "fontSize", L["Text size"], 8, 24, 1)
    page[#page + 1] = slider("stats", "rowGap", L["Row spacing"], 0, 12, 1)
    page[#page + 1] = dropdown("stats", "colorMode", L["Label colour"], {
        { value = "palette", text = L["One colour per stat"] },
        { value = "class",   text = L["Your class colour"] },
        { value = "custom",  text = L["A colour of your own"] },
    })
    page[#page + 1] = color("stats", "color", L["Label color"])
    return page
end

-- ------------------------------------------------------------ display --

local function displayPage()
    return {
        { type = "header", text = L["Frame rate and latency"] },
        toggle("fps", "enabled", L["Show the frame rate"]),
        toggle("fps", "showWorld", L["World latency"]),
        toggle("fps", "showLocal", L["Home latency"]),
        toggle("fps", "showLabel", L["Name which is which"]),
        slider("fps", "interval", L["Refresh every"], 0.5, 5, 0.5),
        slider("fps", "fontSize", L["Text size"], 8, 24, 1),
        color("fps", "color", L["Text color"]),

        { type = "header", text = L["Combat line"] },
        toggle("combatAlert", "enabled", L["Say when a fight starts and ends"]),
        dropdown("combatAlert", "mode", L["Show it"], {
            { value = "both",  text = L["On both"] },
            { value = "enter", text = L["Only when a fight starts"] },
            { value = "leave", text = L["Only when a fight ends"] },
        }),
        editbox("combatAlert", "enterText", L["Words when it starts"]),
        editbox("combatAlert", "leaveText", L["Words when it ends"]),
        color("combatAlert", "enterColor", L["Colour when it starts"]),
        color("combatAlert", "leaveColor", L["Colour when it ends"]),
        slider("combatAlert", "fontSize", L["Text size"], 10, 48, 1),
        { type = "button", label = L["Show it once"], onClick = function()
            QoL.Display.ShowAlert("enter")
        end },

        { type = "header", text = L["Crosshair"] },
        toggle("crosshair", "enabled", L["Draw a crosshair"]),
        dropdown("crosshair", "visibility", L["Show it"], {
            { value = "always",    text = L["Always"] },
            { value = "combat",    text = L["Only in combat"] },
            { value = "instances", text = L["Only in instances"] },
        }),
        slider("crosshair", "length", L["Arm length"], 6, 200, 2),
        slider("crosshair", "thickness", L["Arm thickness"], 1, 8, 1),
        color("crosshair", "color", L["Crosshair color"]),
        slider("crosshair", "borderSize", L["Border size"], 0, 4, 1),
        color("crosshair", "borderColor", L["Border color"]),
        slider("crosshair", "xOffset", L["Sideways"], -400, 400, 1),
        slider("crosshair", "yOffset", L["Up and down"], -400, 400, 1),

        { type = "header", text = L["Map coordinates"] },
        toggle(nil, "mapCoords", L["Show coordinates on the world map"]),
        slider(nil, "mapCoordsSize", L["Text size"], 8, 20, 1),

        { type = "header", text = L["Shared by all of them"] },
        dropdown(nil, "font", L["Font"], ns.MediaFontValues(), 220),
        dropdown(nil, "fontOutline", L["Outline"], {
            { value = "NONE",         text = L["None"] },
            { value = "OUTLINE",      text = L["Thin"] },
            { value = "THICKOUTLINE", text = L["Thick"] },
        }),
    }
end

function mod:GetOptions(tabId)
    if tabId == "loot"    then return lootPage() end
    if tabId == "stats"   then return statsPage() end
    if tabId == "display" then return displayPage() end
    return vendorPage()
end
