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

-- ---------------------------------------------------------------- per bar --
--
-- The Modern settings belong to the bar picked at the top of the block. Every
-- bar follows the shared values until something is changed for it; "Apply to
-- all bars" makes the picked bar's values the shared ones and drops every
-- bar's own.

local function sel() return AB.selectedBar or "bar1" end
local function pget(key) return AB.Cfg(sel())[key] end
local function pset(key, v) AB.OwnCfg(sel())[key] = v; apply() end

local function rebuild()
    ns.NextFrame(function() ns.UI:BuildOptionsPage("actionbars") end)
end

local function pToggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return pget(key) end,
        set = function(_, v) pset(key, v) end }
end

local function pSlider(key, label, min, max, step, tooltip)
    return { type = "slider", label = label, tooltip = tooltip, min = min, max = max, step = step,
        get = function() return pget(key) end,
        set = function(_, v) pset(key, v) end }
end

local function pDropdown(key, label, values, tooltip)
    return { type = "dropdown", label = label, tooltip = tooltip, width = 200, values = values,
        get = function() return pget(key) end,
        set = function(_, v) pset(key, v) end }
end

-- A colour is written as a fresh table: the shared one must never be edited
-- through a bar that only borrowed it.
local function pColor(key, label)
    return { type = "color", label = label,
        get = function() return pget(key) end,
        set = function(r, g, b)
            local old = pget(key)
            pset(key, { r = r, g = g, b = b, a = old and old.a })
        end }
end

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = x end
    return t
end

local function applyToAll()
    local db, view = AB.db(), AB.Cfg(sel())
    local values = {}
    for _, key in ipairs(AB.PER_BAR_KEYS) do values[key] = copyValue(view[key]) end
    for key, v in pairs(values) do db[key] = v end
    db.perBar = {}
    apply(); rebuild()
end

local function resetBar()
    local db = AB.db()
    if db.perBar then db.perBar[sel()] = nil end
    apply(); rebuild()
end

-- The Modern look's own settings, shown only while Modern is the style.
local function modernOptions(page)
    local add = function(item) page[#page + 1] = item end

    add({ type = "header", text = L["Bar"] })
    add({ type = "desc", text = L["|cffaaaaaaThe settings below belong to the bar picked here. A bar you never changed follows the shared settings, and Apply to all bars makes this bar's settings the shared ones.|r"] })
    add({ type = "dropdown", label = L["Bar"], width = 200, values = AB.BarList(),
        get = sel,
        set = function(_, v)
            AB.selectedBar = v
            AB.RefreshPreview(true)
            rebuild()
        end })
    add({ type = "group", layout = "row", gap = 6, items = {
        { type = "button", label = L["Apply to all bars"], width = 190, onClick = applyToAll },
        { type = "button", label = L["Reset this bar"], width = 190, onClick = resetBar },
    } })

    add({ type = "header", text = L["Icons"] })
    add(pDropdown("borderSize", L["Border size"], {
        { value = "none",   text = L["None"] },
        { value = "thin",   text = L["Thin"] },
        { value = "normal", text = L["Normal"] },
        { value = "heavy",  text = L["Heavy"] },
        { value = "strong", text = L["Strong"] },
    }))
    add(pColor("borderColor", L["Border color"]))
    add(pToggle("borderClassColor", L["Class-colored border"]))
    add(pSlider("iconZoom", L["Icon zoom"], 0, 10, 0.5,
        L["Trims the icon's rim. 0 shows the whole icon with its drawn frame."]))
    add(pSlider("iconBgOpacity", L["Icon background"], 0, 100, 5,
        L["The dark ground behind the icon, seen on empty slots and around see-through icons."]))
    add(pColor("iconBgColor", L["Icon background color"]))
    add(pToggle("outOfRange", L["Out of range coloring"],
        L["Tints the icon while your target is out of range of that action."]))
    add(pColor("outOfRangeColor", L["Out of range color"]))
    add({ type = "toggle", label = L["Show cooldown numbers"],
        tooltip = L["The game's own countdown on the icon. A game setting, so it applies to every bar."],
        get = function() return C_CVar.GetCVar("countdownForCooldowns") == "1" end,
        set = function(_, v) C_CVar.SetCVar("countdownForCooldowns", v and "1" or "0") end })

    add({ type = "header", text = L["Interactions"] })
    add(pColor("pressColor", L["Interaction color"]))
    add(pToggle("pressClassColor", L["Class-colored interactions"]))
    add(pDropdown("pushedType", L["Pushed look"], pressTypes(),
        L["What a button shows while its key or mouse button is held."]))
    add(pDropdown("highlightType", L["Hover look"], pressTypes()))
    add(pToggle("castHighlight", L["Highlight on spell cast"],
        L["The button of the spell being cast or channelled glows white."]))

    add({ type = "header", text = L["Text"] })
    add(pToggle("keybindHide", L["Hide keybind text"]))
    add(pSlider("keybindSize", L["Keybind text size"], 6, 30, 1))
    add(pDropdown("keybindPos", L["Keybind position"], textPositions()))
    add(pToggle("macroHide", L["Hide macro text"]))
    add(pSlider("macroSize", L["Macro text size"], 6, 30, 1))
    add(pSlider("countSize", L["Charges text size"], 6, 30, 1))
    add(pSlider("cooldownSize", L["Cooldown text size"], 6, 30, 1))
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
              -- The Modern block comes and goes with the style. A frame
              -- later: the dropdown still writes its own label after this
              -- setter returns, and a rebuild now would hand it another row.
              ns.NextFrame(function() ns.UI:BuildOptionsPage("actionbars") end)
          end },
        toggle("skin", L["Skin the action bars"]),
        { type = "toggle", label = L["Classic: the whole old bar"],
          tooltip = L["The stone band with its gryphons, and the buttons, page arrows, micro menu and bags put back in their 1.x places on it. Switched off, only the buttons change."],
          get = function() return AB.db().classicBar end,
          set = function(_, v)
              AB.db().classicBar = v
              apply()
              -- the bar art switches below come and go with the band
              rebuild()
          end },
        toggle("backpackFreeSlots", L["Free bag slots on the backpack"],
            L["The classic bar writes how many bag slots are still free on the backpack button."]),
        toggle("skinPetStance", L["Skin the pet and stance buttons too"]),
    }
    -- The client's own bar art is there in every look but the Classic band.
    if not (db.style == "classic" and db.classicBar) then
        page[#page + 1] = toggle("showBarFrame", L["Show bar background"],
            L["Action bar 1's frame and the dividers between its buttons."])
        page[#page + 1] = toggle("showEndCaps", L["Show end caps"],
            L["The figures at both ends of action bar 1."])
    end
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
