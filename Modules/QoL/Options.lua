-- VuloForeverUI / Modules / QoL / Options
--
-- One tab per part, the general tab in front of them. Every setter writes
-- and then calls QoL.Apply(), which lets each part decide for itself what
-- changed -- the options never know which switch turns which event on.
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

-- Where the flight bar's two texts can sit (Flight.lua, TEXT_POS).
local function flightTextPositions()
    return {
        { value = "left",       text = L["Left"] },
        { value = "center",     text = L["Centre"] },
        { value = "right",      text = L["Right"] },
        { value = "aboveLeft",  text = L["Above left"] },
        { value = "aboveRight", text = L["Above right"] },
        { value = "none",       text = L["None"] },
    }
end

local function editbox(sub, key, label, width)
    return { type = "editbox", label = label, width = width or 240, editWidth = 140,
        get = function() return tbl(sub)[key] end,
        set = function(_, v) tbl(sub)[key] = v; apply() end }
end

-- ------------------------------------------------------------ general --

local function generalPage()
    return {
        { type = "header", text = L["Character"] },
        toggle("character", "acceptQuests", L["Accept quests automatically"],
            L["Hold shift while talking to a quest giver to read the quest as usual."]),
        toggle("character", "turnInQuests", L["Hand quests in automatically"],
            L["A quest that lets you pick between rewards stops and waits for you -- that choice is never made for you."]),
        toggle("character", "acceptResurrect", L["Accept a resurrection automatically"],
            L["Never during a fight: a resurrection taken mid-fight puts you straight back on the floor."]),
        toggle("character", "acceptSummon", L["Accept a summon automatically"],
            L["Never during a fight, and never on an offer that has already run out."]),
        toggle("character", "releasePvP", L["Release automatically in battlegrounds and arenas"],
            L["Only there. In the world, releasing stays your decision -- somebody may be on the way to you."]),
        { type = "desc", text = L["|cffaaaaaaThe client can refuse an action taken without a click, and it does so silently. If one of these does nothing, the window you would have clicked simply stays open.|r"] },

        { type = "header", text = L["World"] },
        -- The same switch the Loot tab carries, not a second one: one value,
        -- shown where both layouts look for it. The delay that goes with it
        -- stays on the Loot tab, where there is room to explain it.
        toggle(nil, "quickLoot", L["Loot everything in one click"],
            L["The one-click looting. Its timing sits on the Loot tab."]),
        toggle("world", "gossipSingle", L["Pick a single NPC dialogue option"],
            L["Only when there is exactly one option and no quest on the frame -- a quest would otherwise be clicked past. Hold shift to talk normally."]),

        { type = "header", text = L["Protection"] },
        toggle("world", "blockInvites", L["Block group invites from strangers"],
            L["A stranger is nobody on your friend list, in your guild, or playing one of your Battle.net friends' characters. Each block says who it was."]),
        toggle("world", "blockTrades", L["Block trades from strangers"],
            L["The same rule. The trade window closes again straight away."]),

        { type = "header", text = L["Mail"] },
        toggle("mail", "recipients", L["A recipient list in the send tab"],
            L["A button beside the name field, holding the last dozen names you sent mail to. They are remembered when the mail actually goes out, not while you type."]),

        { type = "header", text = L["Flight time"] },
        toggle("flight", "showBar", L["Show a flight time bar"],
            L["The client never says how long a ride takes, so the first flight of a route is measured and every one after it counts down."]),
        toggle("flight", "chat", L["Say the flight time in chat"]),
        slider("flight", "width", L["Bar width"], 120, 480, 5),
        slider("flight", "height", L["Bar height"], 8, 40, 1),
        dropdown("flight", "texture", L["Bar texture"], ns.MediaStatusbarValues(), 220),
        slider("flight", "borderSize", L["Border size"], 0, 4, 1),
        color("flight", "borderColor", L["Border color"]),
        dropdown("flight", "font", L["Font"], (function()
            local v = { { value = "", text = L["Module font"] } }
            for _, e in ipairs(ns.MediaFontValues()) do v[#v + 1] = e end
            return v
        end)(), 220),
        slider("flight", "fontSize", L["Size"], 0, 24, 1, L["0 follows the bar height."]),
        dropdown("flight", "labelPos", L["Label position"], flightTextPositions()),
        slider("flight", "labelX", L["X Offset"], -100, 100, 1),
        slider("flight", "labelY", L["Y Offset"], -50, 50, 1),
        dropdown("flight", "timePos", L["Time position"], flightTextPositions()),
        slider("flight", "timeX", L["X Offset"], -100, 100, 1),
        slider("flight", "timeY", L["Y Offset"], -50, 50, 1),
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Show it once"], width = 150,
              onClick = function() QoL.Flight.Preview() end },
            { type = "button", label = L["Forget the learned times"], width = 190,
              onClick = function()
                  QoL.Flight.Forget()
                  ns.UI:BuildOptionsPage("qol", "general")
              end },
        } },
        { type = "desc", text = string.format(
            L["|cffaaaaaa%d routes learned. Placing the bar is Edit Mode's job: /vedit.|r"],
            QoL.Flight.LearnedCount()) },
    }
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


        { type = "header", text = L["Splitting a stack"] },
        toggle("stackSplit", "maxButton", L["A button for the whole stack"],
            L["Sits in the client's own split window, which is the one every bag opens -- ours, the client's, the bank."]),
        toggle("stackSplit", "skin", L["Give that window our look"]),
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

        toggle("combatEvents", "interrupted", L["Say when a cast is interrupted"]),
        color("combatEvents", "interruptedColor", L["Colour for that"]),
        toggle("combatEvents", "reflected", L["Say when something is reflected"]),
        color("combatEvents", "reflectedColor", L["Colour for that"]),
        toggle("combatEvents", "avoided", L["Say when a hit is dodged, parried or missed"]),
        color("combatEvents", "avoidedColor", L["Colour for that"]),
        toggle("combatEvents", "partyDeath", L["Say when someone in the group dies"]),
        color("combatEvents", "partyDeathColor", L["Colour for that"]),
        toggle("durability", "line", L["Say when the gear is wearing out"],
            L["A word on this line when the gear crosses the threshold below -- once, and again only after a repair. The warning further down is the same fact said louder, with a threshold of its own."]),
        color("durability", "lineColor", L["Colour for that"]),
        editbox("durability", "lineText", L["Word to say"]),
        slider("durability", "lineThreshold", L["Say it below"], 5, 95, 5),
        { type = "desc", text = L["|cffaaaaaaThese ride on the client's own combat text feed, which reports what kind of thing happened but never a number. A banish, a dispel or a buff handed to someone else lives only in the combat log, and this client hands out no combat log at all.|r"] },

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

        { type = "header", text = L["Durability warning"] },
        toggle("durability", "enabled", L["Warn before the gear is gone"]),
        slider("durability", "threshold", L["Warn below"], 5, 95, 5),
        slider("durability", "fontSize", L["Text size"], 10, 48, 1),
        color("durability", "color", L["Text color"]),
        { type = "button", label = L["Show it once"], onClick = function()
            QoL.Vendor.PreviewDurability()
        end },
        { type = "desc", text = L["|cffaaaaaaThe warning stays hidden during a fight: there is nothing you could do about it there.|r"] },

        { type = "header", text = L["Shared by all of them"] },
        dropdown(nil, "font", L["Font"], ns.MediaFontValues(), 220),
        dropdown(nil, "fontOutline", L["Outline"], {
            { value = "NONE",         text = L["None"] },
            { value = "OUTLINE",      text = L["Thin"] },
            { value = "THICKOUTLINE", text = L["Thick"] },
        }),
    }
end

-- ---------------------------------------------------------------- trinkets --

-- The entry picked in a slot's order list, per slot, for the move buttons.
-- Page state, not a setting: it only lives while the page is open.
local picked = { top = 1, bottom = 1 }

-- On the next frame: a dropdown writes its own label AFTER its setter
-- returns, and a page rebuilt inside the setter has already handed that
-- dropdown to another row -- which then showed the wrong trinket's name.
local function rebuild()
    C_Timer.After(0, function()
        local UI = ns.UI
        if UI.currentModule == "qol" and UI.BuildOptionsPage then
            UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
        end
    end)
end

local function queueRows(key, title)
    local T = QoL.Trinkets
    local q = T.Queue(key)
    local list = q.list
    if picked[key] > #list then picked[key] = #list end

    local order = {}
    for i, id in ipairs(list) do
        order[#order + 1] = { value = i, text = ("%d. %s"):format(i, T.ItemName(id)), draggable = true }
    end

    local adds = {}
    local listed = {}
    for _, id in ipairs(list) do listed[id] = true end
    for _, id in ipairs(T.Owned()) do
        if not listed[id] then adds[#adds + 1] = { value = id, text = T.ItemName(id) } end
    end
    if #adds == 0 then adds[1] = { value = 0, text = L["No trinket left to add."], separator = true } end

    local function move(delta)
        local i = picked[key]
        local j = i + delta
        if j < 1 or j > #list then return end
        list[i], list[j] = list[j], list[i]
        picked[key] = j
        T.QueueChanged()
        rebuild()
    end

    return {
        { type = "header", text = title },
        { type = "toggle", label = L["Auto-queue for this slot"],
          tooltip = L["Puts the next ready trinket of the list on once the one in the slot is spent. Out of combat only."],
          get = function() return T.Queue(key).enabled end,
          set = function(_, v) T.Queue(key).enabled = v and true or false; T.QueueChanged() end },
        { type = "dropdown", label = L["Order"], width = 240, values = order,
          get = function() return picked[key] end,
          set = function(_, v) picked[key] = v end,
          reorder = function(from, to)
              local id = table.remove(list, from)
              table.insert(list, to, id)
              picked[key] = to
              T.QueueChanged()
              rebuild()
          end },
        { type = "dropdown", label = L["Add a trinket"], width = 240, values = adds,
          get = function() return nil end,
          set = function(_, id)
              if not id or id == 0 then return end
              -- above the stop marker, so it takes part at once
              local at = #list
              for i, v in ipairs(list) do if v == 0 then at = i; break end end
              table.insert(list, at, id)
              picked[key] = at
              T.QueueChanged()
              rebuild()
          end },
        { type = "group", layout = "row", gap = 8, items = {
            { type = "button", label = L["Move up"], width = 120, onClick = function() move(-1) end },
            { type = "button", label = L["Move down"], width = 120, onClick = function() move(1) end },
            { type = "button", label = L["Remove"], width = 120, onClick = function()
                local i = picked[key]
                if list[i] == nil or list[i] == 0 then return end   -- the marker stays
                table.remove(list, i)
                T.QueueChanged()
                rebuild()
            end },
        } },
    }
end

local function trinketsPage()
    local items = {
        { type = "header", text = L["Trinkets"] },
        { type = "desc", text = L["|cffaaaaaaTwo trinket slots on screen with their cooldowns. Left click uses the trinket, right click picks another, alt-click switches that slot's auto-queue. Trinkets can only be changed out of combat.|r"] },
        toggle("trinkets", "enabled", L["Show the trinket window"]),
        { type = "toggle", label = L["Unlock to move"],
          tooltip = L["Drag the window where you want it, then switch this off to lock it again. Not in combat."],
          get = function() return QoL.db().trinkets.freeMove end,
          set = function(_, v) QoL.Trinkets.SetUnlocked(v) end },
        toggle("trinkets", "vertical", L["Stack the slots vertically"]),
        toggle("trinkets", "tooltips", L["Show tooltips"]),
        slider("trinkets", "scale", L["Size"], 0.5, 2, 0.05),
    }
    for _, spec in ipairs({ { "top", L["Auto-queue: upper slot"] }, { "bottom", L["Auto-queue: lower slot"] } }) do
        for _, row in ipairs(queueRows(spec[1], spec[2])) do items[#items + 1] = row end
    end
    return items
end

function mod:GetOptions(tabId)
    if tabId == "vendor"  then return vendorPage() end
    if tabId == "loot"    then return lootPage() end
    if tabId == "display" then return displayPage() end
    if tabId == "trinkets" then return trinketsPage() end
    return generalPage()
end
