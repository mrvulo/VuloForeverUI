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

function mod:GetOptions()
    local db = AB.db()
    local page = {
        AB.PreviewItem(),
        { type = "desc", text = L["|cffaaaaaaThe client's own action bars stay. They keep their clicks, their keys and their paging -- everything below dresses them.|r"] },

        { type = "header", text = L["Bar style"] },
        { type = "dropdown", label = L["Style"], width = 280,
          values = {
              { value = "standard", text = AB.StyleLabel("standard") },
              { value = "classic",  text = AB.StyleLabel("classic") },
              { value = "modern",   text = AB.StyleLabel("modern") },
          },
          get = function() return AB.db().style end,
          set = function(_, v) AB.db().style = v; apply() end },
        toggle("skin", L["Skin the action bars"]),
        toggle("classicBar", L["Classic: the whole old bar"],
            L["The stone band with its gryphons, and the buttons, page arrows, micro menu and bags put back in their 1.x places on it. Switched off, only the buttons change."]),
        toggle("backpackFreeSlots", L["Free bag slots on the backpack"],
            L["The classic bar writes how many bag slots are still free on the backpack button."]),
        toggle("skinPetStance", L["Skin the pet and stance buttons too"]),
        color("borderColor", L["Border color"]),

        { type = "header", text = L["Paging by form"] },
        { type = "desc", text = L["|cffaaaaaaCat, bear, stealth, the stances and Shadowform normally swap the main bar to a page of their own. Switch this on to keep your bar where it is in every form.|r"] },
    }

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
