-- VuloForeverUI / Modules / Minimap / StyleOptions: the minimap style options page
local _, ns = ...
local L = ns.L
local MM = ns.MM
local mod = MM.mod

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local function set(key, after)
    return function(_, v)
        mod.db[key] = v
        if after then after() else mod:Apply() end
    end
end

function mod:GetOptions()
    local d = self.db
    local modern = function() return d.style ~= "modern" end
    local positions = ns.AnchorPointValues()

    local rows = {
        { type = "dropdown", label = L["Minimap Style"],
          tooltip = L["Standard leaves the game's own minimap alone. Classic rebuilds the old ring. Modern is a flat map with a thin border."],
          values = {
              { value = "standard", text = L["Standard (as the game ships it)"] },
              { value = "classic",  text = L["Classic (the old ring)"] },
              { value = "modern",   text = L["Modern (flat)"] },
          },
          get = function() return d.style end, set = set("style") },

        { type = "section", title = L["Shape and Size"], items = {
            { type = "dropdown", label = L["Shape"], disabled = modern,
              values = { { value = "round", text = L["Round"] }, { value = "square", text = L["Square"] } },
              get = function() return d.shape end, set = set("shape") },
            { type = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05,
              get = function() return d.scale end, set = set("scale") },
            ns.BorderRows(ns.OptionRows(function() return mod.db end, function() mod:Apply() end),
                { size = "borderSize", color = "borderColor", classColor = "borderClassColor" },
                { disabled = modern }),
        } },

        { type = "section", title = L["Around the Map"], items = {
            { type = "toggle", label = L["Zoom with the mouse wheel"],
              get = function() return d.scrollZoom end, set = set("scrollZoom") },
            { type = "toggle", label = L["Hide Zoom Buttons"],
              get = function() return d.hideZoom end, set = set("hideZoom") },
            { type = "toggle", label = L["Hide Tracking Button"],
              get = function() return d.hideTracking end, set = set("hideTracking") },
            { type = "toggle", label = L["Hide Mail Icon"],
              get = function() return d.hideMail end, set = set("hideMail") },
            { type = "toggle", label = L["Hide Day/Night Indicator"],
              tooltip = L["The sun and moon dial this client shows next to the map."],
              get = function() return d.hideDiel end, set = set("hideDiel") },
            { type = "toggle", label = L["Hide the game's own clock"],
              tooltip = L["Only in the classic look. Modern draws its own clock instead, and standard leaves the game's alone."],
              disabled = function() return d.style ~= "classic" end,
              get = function() return d.hideClock end, set = set("hideClock") },
            { type = "slider", label = L["Queue eye size"], min = 0.5, max = 1.5, step = 0.05,
              tooltip = L["The eye that shows a dungeon or battleground queue, on top of the size the game's own editor gives it. Its place is set in Edit Mode: /vedit."],
              get = function() return d.queueScale end, set = set("queueScale") },
            { type = "slider", label = L["Zoom back out after"], min = 0, max = 60, step = 5,
              tooltip = L["Seconds of quiet before the map returns to its widest zoom. 0 leaves it alone."],
              get = function() return d.zoomReset end, set = set("zoomReset") },
            { type = "toggle", label = L["Middle click opens the menu"],
              get = function() return d.middleClickMenu end, set = set("middleClickMenu") },
        } },

        { type = "section", title = L["When to show the map"], items = {
            { type = "dropdown", label = L["Show the minimap"],
              values = {
                  { value = "always",    text = L["Always"] },
                  { value = "instances", text = L["Only in instances"] },
                  { value = "never",     text = L["Never"] },
              },
              get = function() return d.visibility end,
              set = set("visibility", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide while mounted"],
              get = function() return d.visHideMounted end,
              set = set("visHideMounted", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide without a target"],
              get = function() return d.visHideNoTarget end,
              set = set("visHideNoTarget", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide without an enemy target"],
              get = function() return d.visHideNoEnemy end,
              set = set("visHideNoEnemy", function() MM.Elements.ApplyVisibility() end) },
        } },
    }

    for _, section in ipairs(MM.Elements.Options(set, positions)) do
        rows[#rows + 1] = section
    end
    return rows
end
