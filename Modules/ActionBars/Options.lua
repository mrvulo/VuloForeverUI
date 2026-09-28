-- VuloForeverUI / Modules / ActionBars / Options
--
-- One page, in two blocks: the style the bars are dressed in, and the one
-- thing here that is not about looks at all.
local _, ns = ...
local L  = ns.L
local AB = ns.AB

local mod = AB.mod

local function apply()
    AB.Apply()
    AB.RefreshPreview()
end

local function toggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return AB.db()[key] end,
        set = function(_, v) AB.db()[key] = v; apply() end }
end

local function color(key, label)
    return { type = "color", label = label,
        get = function() return AB.db()[key] end,
        set = function(r, g, b)
            local c = AB.db()[key]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

local function slider(key, label, min, max, step, tooltip)
    return { type = "slider", label = label, tooltip = tooltip, min = min, max = max, step = step,
        get = function() return AB.db()[key] end,
        set = function(_, v) AB.db()[key] = v; apply() end }
end

local function dropdown(key, label, values, tooltip)
    return { type = "dropdown", label = label, tooltip = tooltip, width = 200, values = values,
        get = function() return AB.db()[key] end,
        set = function(_, v) AB.db()[key] = v; apply() end }
end

local function pressTypes()
    return {
        { value = 1, text = L["Light"] },
        { value = 2, text = L["Medium"] },
        { value = 3, text = L["Strong"] },
        { value = 4, text = L["Solid color"] },
        { value = 6, text = L["None"] },
    }
end

local function textPositions()
    return {
        { value = "default",     text = L["Default"] },
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOP",         text = L["Top"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
end

-- The Modern look's own settings, shown only while Modern is the style.
local function modernOptions(page)
    local add = function(item) page[#page + 1] = item end

    add({ type = "header", text = L["Icons"] })
    add(dropdown("borderSize", L["Border size"], {
        { value = "none",   text = L["None"] },
        { value = "thin",   text = L["Thin"] },
        { value = "normal", text = L["Normal"] },
        { value = "heavy",  text = L["Heavy"] },
        { value = "strong", text = L["Strong"] },
    }))
    add(color("borderColor", L["Border color"]))
    add(toggle("borderClassColor", L["Class-colored border"]))
    add(slider("iconZoom", L["Icon zoom"], 0, 10, 0.5,
        L["Trims the icon's rim. 0 shows the whole icon with its drawn frame."]))
    add(slider("iconBgOpacity", L["Icon background"], 0, 100, 5,
        L["The dark ground behind the icon, seen on empty slots and around see-through icons."]))
    add(color("iconBgColor", L["Icon background color"]))
    add({ type = "toggle", label = L["Show cooldown numbers"],
        tooltip = L["The game's own countdown on the icon (the game setting of the same name)."],
        get = function() return C_CVar.GetCVar("countdownForCooldowns") == "1" end,
        set = function(_, v) C_CVar.SetCVar("countdownForCooldowns", v and "1" or "0") end })

    add({ type = "header", text = L["Interactions"] })
    add(color("pressColor", L["Interaction color"]))
    add(toggle("pressClassColor", L["Class-colored interactions"]))
    add(dropdown("pushedType", L["Pushed look"], pressTypes(),
        L["What a button shows while its key or mouse button is held."]))
    add(dropdown("highlightType", L["Hover look"], pressTypes()))
    add(toggle("castHighlight", L["Highlight on spell cast"],
        L["The button of the spell being cast or channelled glows white."]))

    add({ type = "header", text = L["Text"] })
    add(toggle("keybindHide", L["Hide keybind text"]))
    add(slider("keybindSize", L["Keybind text size"], 6, 30, 1))
    add(dropdown("keybindPos", L["Keybind position"], textPositions()))
    add(toggle("macroHide", L["Hide macro text"]))
    add(slider("macroSize", L["Macro text size"], 6, 30, 1))
    add(slider("countSize", L["Charges text size"], 6, 30, 1))
    add(slider("cooldownSize", L["Cooldown text size"], 6, 30, 1))
end

function mod:GetOptions()
    local db = AB.db()
    local page = {
        { type = "desc", text = L["|cffaaaaaaThe client's own action bars stay. They keep their clicks, their keys and their paging -- everything below dresses them.|r"] },

        { type = "header", text = L["Bar style"] },
        { type = "dropdown", label = L["Style"], width = 280,
          values = {
              { value = "standard", text = AB.StyleLabel("standard") },
              { value = "classic",  text = AB.StyleLabel("classic") },
              { value = "modern",   text = AB.StyleLabel("modern") },
          },
          get = function() return AB.db().style end,
          set = function(_, v)
              AB.db().style = v
              apply()
              -- the Modern block comes and goes with the style
              ns.UI:BuildOptionsPage("actionbars")
          end },
        toggle("skin", L["Skin the action bars"]),
        toggle("classicBar", L["Classic: the whole old bar"],
            L["The stone band with its gryphons, and the buttons, page arrows, micro menu and bags put back in their 1.x places on it. Switched off, only the buttons change."]),
        toggle("backpackFreeSlots", L["Free bag slots on the backpack"],
            L["The classic bar writes how many bag slots are still free on the backpack button."]),
        toggle("skinPetStance", L["Skin the pet and stance buttons too"]),
    }
    if db.style == "modern" then modernOptions(page) end
    local rest = {
        { type = "header", text = L["Paging by form"] },
        { type = "desc", text = L["|cffaaaaaaCat, bear, stealth, the stances and Shadowform normally swap the main bar to a page of their own. Switch this on to keep your bar where it is in every form.|r"] },
    }

    for _, item in ipairs(rest) do page[#page + 1] = item end

    -- The switch is only offered where it can actually do something. On this
    -- client the machinery behind it may not load at all, and a control that
    -- silently does nothing is worse than a line saying so.
    if AB.Paging.supported == false then
        page[#page + 1] = { type = "desc",
            text = "|cffffcc55" .. L["This client cannot pin the action bar page: the machinery behind it does not load here."] .. "|r" }
    else
        page[#page + 1] = toggle("keepPage", L["Keep the main bar on its page in every form"])
    end

    return page
end

-- The twelve buttons, pinned above the page (Preview.lua).
function mod.BuildPageHeader(host)
    return AB.BuildPreviewHeader(host)
end
