-- VuloForeverUI / Modules / DamageMeter / Options
--
-- The settings page, in five tabs. Every control writes into the profile and
-- repaints at once: nothing here needs a reload.
--
-- While the page is open the windows are forced visible at full opacity and
-- the cast history shows stand-ins, so a setting can be judged without
-- standing in a fight.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local mod = DM.mod

mod.tabs = {
    { id = "general",   label = "General" },
    { id = "window",    label = "Window" },
    { id = "bars",      label = "Bars" },
    { id = "text",      label = "Text" },
    { id = "timer",     label = "Combat Timer" },
    { id = "history",   label = "Cast History" },
    { id = "threat",    label = "Threat Meter" },
}

local function d() return DM.db() end

-- ---------------------------------------------------------------- helpers --

-- A colour row on the profile's {r,g,b} table.
local function colorRow(label, key, onSet)
    return { type = "color", label = label,
        get = function() return d()[key] end,
        set = function(r, g, b)
            local c = d()[key]
            c.r, c.g, c.b = r, g, b
            if onSet then onSet() end
        end }
end

local function toggle(label, key, tooltip, onSet)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return d()[key] end,
        set = function(_, v) d()[key] = v; if onSet then onSet() end end }
end

local function slider(label, key, min, max, step, onSet, tooltip)
    return { type = "slider", label = label, tooltip = tooltip, min = min, max = max, step = step,
        get = function() return d()[key] end,
        set = function(_, v) d()[key] = v; if onSet then onSet() end end }
end

local function dropdown(label, key, values, onSet, width)
    return { type = "dropdown", label = label, width = width or 200, values = values,
        get = function() return d()[key] end,
        set = function(_, v) d()[key] = v; if onSet then onSet() end end }
end

-- Sub-table variants for the timer and the cast history.
local function subToggle(tbl, label, key, tooltip, onSet)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return tbl()[key] end,
        set = function(_, v) tbl()[key] = v; if onSet then onSet() end end }
end

local function subSlider(tbl, label, key, min, max, step, onSet)
    return { type = "slider", label = label, min = min, max = max, step = step,
        get = function() return tbl()[key] end,
        set = function(_, v) tbl()[key] = v; if onSet then onSet() end end }
end

local function subDropdown(tbl, label, key, values, onSet, width)
    return { type = "dropdown", label = label, width = width or 200, values = values,
        get = function() return tbl()[key] end,
        set = function(_, v) tbl()[key] = v; if onSet then onSet() end end }
end

local function subColor(tbl, label, key, onSet)
    return { type = "color", label = label,
        get = function() return tbl()[key] end,
        set = function(r, g, b)
            local c = tbl()[key]
            c.r, c.g, c.b = r, g, b
            if onSet then onSet() end
        end }
end

local function restyle() DM.RestyleAll() end
local function repaint() DM.RefreshAll() end
local function visibility() DM.UpdateVisibilityAll() end

local function borderValues()
    local v = { { value = "solid", text = L["Solid"] } }
    for _, e in ipairs(ns.MediaBorderValues()) do
        if e.value ~= "" then v[#v + 1] = e end
    end
    return v
end

local function keyValues()
    local v = { { value = "", text = L["- none -"] } }
    for i = 1, 12 do v[#v + 1] = { value = "F" .. i, text = "F" .. i } end
    for _, m in ipairs({ "SHIFT", "CTRL", "ALT" }) do
        for i = 1, 12 do
            local k = m .. "-F" .. i
            v[#v + 1] = { value = k, text = k }
        end
    end
    return v
end

-- ---------------------------------------------------------------- pages --

local function generalOptions()
    return {
        { type = "header", text = L["Damage Meter"] },
        { type = "desc", text = L["|cffaaaaaaDamage, healing, interrupts, dispels and deaths come from the client's own combat tracking — there is no combat log on this client. Click a row for the breakdown, right-click for the list of meter types.|r"] },

        { type = "dropdown", label = L["Style"], width = 220,
          values = {
              { value = "modern",  text = L["Modern"] },
              { value = "classic", text = L["Classic"] },
          },
          tooltip = L["Classic draws the windows in 1.x art: the tooltip background inside the old chat tab border, a lighter header band and the 1.x buttons. The first switch also sets a near-black window, the game's own bar fill and a dark track behind the bars; after that those settings are yours again."],
          get = function() return d().style end,
          set = function(_, v)
              d().style = v
              if v == "classic" then DM.SeedClassic() end
              restyle()
          end },

        { type = "dropdown", label = L["Visibility"], width = 220, values = ns.VisibilityValues(),
          get = function() return d().visibility end,
          set = function(_, v) d().visibility = v; visibility() end },

        { type = "slider", label = L["Refresh rate"], min = 0.2, max = 2, step = 0.1,
          tooltip = L["Seconds between repaints while you are in combat. Lower is smoother and costs more."],
          get = function() return d().refreshRate end,
          set = function(_, v)
              local floor = d().unsafeRefreshRate and DM.TICK_HARD or DM.TICK_FLOOR
              d().refreshRate = math.max(floor, v)
              DM.RestartTicker()
          end },
        { type = "toggle", label = L["Allow rates below half a second"],
          tooltip = L["Each tick fetches a full session per window, so below half a second the cost climbs faster than the picture improves."],
          get = function() return d().unsafeRefreshRate end,
          set = function(_, v)
              d().unsafeRefreshRate = v
              if not v and d().refreshRate < DM.TICK_FLOOR then d().refreshRate = DM.TICK_FLOOR end
              DM.RestartTicker()
              UI:BuildOptionsPage("damagemeter", "general")
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Keys"] },
        { type = "dropdown", label = L["Reset data"], width = 200, values = keyValues(),
          get = function() return d().resetKey end,
          set = function(_, v) d().resetKey = v; DM.ApplyKeybinds() end },
        { type = "dropdown", label = L["Show and hide the windows"], width = 200, values = keyValues(),
          get = function() return d().toggleKey end,
          set = function(_, v) d().toggleKey = v; DM.ApplyKeybinds() end },
        toggle(L["The key also hides the combat timer"], "toggleIncludeTimer"),
        toggle(L["The key also hides the cast history"], "toggleIncludeSpellHistory"),
        toggle(L["Hide the reset button"], "hideResetButton", nil, restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Windows"] },
        { type = "slider", label = L["Number of windows"], min = 1, max = DM.MAX_WINDOWS, step = 1,
          get = function() return #DM.windows end,
          set = function(_, v)
              v = math.floor(v)
              while #DM.windows < v do DM.AddWindow(DM.windows[#DM.windows]) end
              while #DM.windows > v do DM.RemoveWindow(DM.windows[#DM.windows]) end
          end },
        { type = "desc", text = L["|cffaaaaaaEach window keeps its own meter type, segment, size and place. The gear in a window's header holds its own settings.|r"] },

        { type = "spacer", height = 6 },
        { type = "button", label = L["Reset the data now"], onClick = DM.ResetData },
        { type = "toggle", label = L["Switch off the client's own meter"],
          tooltip = L["The client's meter is hidden while this module runs. Its data keeps being collected either way."],
          get = function() return d().disableBlizzardMeter end,
          set = function(_, v)
              d().disableBlizzardMeter = v
              if C_CVar and C_CVar.SetCVar then pcall(C_CVar.SetCVar, "damageMeterEnabled", v and "0" or "1") end
          end },

        -- Settings out of another suite's profile string (Import.lua).
        { type = "spacer", height = 6 },
        { type = "header", text = L["Import"] },
        { type = "desc", text = L["|cffaaaaaaPaste a profile string from another UI suite. Every damage meter setting it carries that exists here is taken over; window places and sizes stay yours.|r"] },
        { type = "button", label = L["Import damage meter settings"], width = 240, onClick = function()
            ns.UI:ShowStringImportDialog(L["Import damage meter settings"], function(text)
                local taken, err = DM.ImportForeignString(text)
                if not taken then return err end
                ns:Print(L["Damage meter: %d settings taken over."], taken)
                if UI.currentModule == "damagemeter" and UI.BuildOptionsPage then
                    UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
                end
            end)
        end },
    }
end

local function windowOptions()
    return {
        { type = "header", text = L["Background"] },
        slider(L["Opacity"], "bgAlpha", 0, 1, 0.01, restyle),
        colorRow(L["Background color"], "bgColor", restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Border"] },
        dropdown(L["Border style"], "windowBorderTexture", borderValues(), restyle),
        slider(L["Border size"], "windowBorderSize", 0, 8, 1, restyle),
        colorRow(L["Border color"], "windowBorderColor", restyle),
        slider(L["Border opacity"], "windowBorderAlpha", 0, 1, 0.01, restyle),
        slider(L["Border offset X"], "windowBorderOffsetX", -10, 10, 1, restyle),
        slider(L["Border offset Y"], "windowBorderOffsetY", -10, 10, 1, restyle),
        toggle(L["Include the header"], "windowBorderIncludeHeader", nil, restyle),
        toggle(L["Draw behind the bars"], "windowBorderBehind", nil, restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Header"] },
        slider(L["Header height"], "hdrHeight", 14, 40, 1, restyle),
        slider(L["Header opacity"], "hdrBgAlpha", 0, 1, 0.01, restyle),
        colorRow(L["Header color"], "hdrBgColor", restyle),
        slider(L["Header text size"], "hdrFontSize", 8, 18, 1, restyle),
        toggle(L["Accent color for the header text"], "hdrTextUseAccent", nil, restyle),
        colorRow(L["Header text color"], "hdrTextColor", restyle),
        slider(L["Header text offset X"], "hdrTextOffX", -20, 20, 1, restyle),
        slider(L["Header text offset Y"], "hdrTextOffY", -20, 20, 1, restyle),
        slider(L["Bottom border"], "hdrBottomBorderSize", 0, 4, 1, restyle),
        colorRow(L["Bottom border color"], "hdrBottomBorderColor", restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Header icons"] },
        slider(L["Icon size"], "hdrIconSize", 16, 32, 1, restyle),
        toggle(L["Show the icons only on mouseover"], "hdrMouseoverIcons", nil, restyle),
        toggle(L["Accent color for the icons"], "iconColorUseAccent", nil, restyle),
        colorRow(L["Icon color"], "iconColor", restyle),
    }
end

local function barsOptions()
    return {
        { type = "header", text = L["Bars"] },
        dropdown(L["Bar texture"], "barTexture", ns.MediaStatusbarValues(), restyle, 220),
        slider(L["Bar height"], "barHeight", 8, 40, 1, restyle),
        slider(L["Spacing"], "barSpacing", -1, 10, 1, restyle),
        slider(L["Fill opacity"], "barFillAlpha", 0, 1, 0.01, restyle),
        toggle(L["Class color"], "showClassColor", nil, restyle),
        toggle(L["Accent color instead"], "barColorUseAccent", nil, restyle),
        colorRow(L["Bar color"], "barColor", restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Bar background"] },
        slider(L["Background opacity"], "barBgAlpha", 0, 1, 0.01, restyle),
        toggle(L["Class color for the background"], "barBgUseClassColor", nil, restyle),
        colorRow(L["Background color"], "barBgColor", restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Icons"] },
        dropdown(L["Icon style"], "iconStyle", DM.IconStyleValues(), restyle, 220),
        { type = "slider", label = L["Icon zoom"], min = 0, max = 0.2, step = 0.01,
          tooltip = L["Applies to the spec and Blizzard class icons; the other sets are already framed."],
          get = function() return d().classIconZoom end,
          set = function(_, v) d().classIconZoom = v; restyle() end },
        toggle(L["Border around the icon"], "customIconBorder", nil, restyle),
        slider(L["Icon border size"], "iconBorderSize", 0, 4, 1, restyle),
        colorRow(L["Icon border color"], "iconBorderColor", restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Bar border"] },
        dropdown(L["Bar border style"], "borderTexture", borderValues(), restyle),
        slider(L["Bar border size"], "borderSize", 0, 4, 1, restyle),
        colorRow(L["Bar border color"], "borderColor", restyle),
        slider(L["Bar border opacity"], "borderAlpha", 0, 1, 0.01, restyle),
        { type = "toggle", label = L["The border follows the fill"],
          tooltip = L["Wraps only the filled part of a bar instead of the whole row. Always drawn solid."],
          get = function() return d().borderFollowFill end,
          set = function(_, v) d().borderFollowFill = v; restyle() end },
        toggle(L["Include the icon in that border"], "borderFollowFillIcon", nil, restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Breakdown"] },
        toggle(L["Show the breakdown on mouseover"], "showHoverTooltip"),
        toggle(L["Show the game's spell tooltip"], "showSpellTooltips"),
        toggle(L["Show fifteen rows instead of eight"], "showAllBreakdownSpells"),
        dropdown(L["Breakdown texture"], "breakdownBarTexture", (function()
            local v = { { value = "match", text = L["Same as the bars"] } }
            for _, e in ipairs(ns.MediaStatusbarValues()) do v[#v + 1] = e end
            return v
        end)(), repaint, 220),
        dropdown(L["Breakdown position"], "breakdownAnchorPoint", {
            { value = "row",    text = L["Above the row"] },
            { value = "center", text = L["Center of the screen"] },
            { value = "left",   text = L["Left of the window"] },
            { value = "right",  text = L["Right of the window"] },
        }, repaint),
        slider(L["Breakdown scale"], "hoverTooltipScale", 80, 150, 1, repaint),
    }
end

local function textOptions()
    return {
        { type = "header", text = L["Numbers"] },
        dropdown(L["Number format"], "numberFormat", {
            { value = 0, text = L["Per second"] },
            { value = 1, text = L["Total"] },
            { value = 2, text = L["Total (per second)"] },
            { value = 3, text = L["Total | per second"] },
        }, repaint, 220),
        toggle(L["Hide the rank numbers"], "hideNumbers", L["Hides the 1. 2. 3. in front of each name."], restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Left text"] },
        slider(L["Left text size"], "leftFontSize", 8, 18, 1, restyle),
        toggle(L["Class color on the left"], "leftTextUseClassColor", nil, restyle),
        colorRow(L["Left text color"], "leftTextColor", restyle),
        slider(L["Left offset X"], "leftTextOffsetX", -20, 20, 1, restyle),
        slider(L["Left offset Y"], "leftTextOffsetY", -20, 20, 1, restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Right text"] },
        slider(L["Right text size"], "rightFontSize", 8, 18, 1, restyle),
        toggle(L["Class color on the right"], "rightTextUseClassColor", nil, restyle),
        colorRow(L["Right text color"], "rightTextColor", restyle),
        slider(L["Right offset X"], "rightTextOffsetX", -20, 20, 1, restyle),
        slider(L["Right offset Y"], "rightTextOffsetY", -20, 20, 1, restyle),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Your own row"] },
        { type = "toggle", label = L["Always show your own bar"],
          tooltip = L["Pins your bar to the edge of the window while it has scrolled out of sight."],
          get = function() return d().showPinnedSelf end,
          set = function(_, v) d().showPinnedSelf = v; repaint() end },
    }
end

local function timerTbl() return DM.db().timer end

local function timerOptions()
    local t = timerTbl()
    local apply = function() DM.Timer.Apply() end
    local items = {
        { type = "header", text = L["Standalone Combat Timer"] },
        { type = "desc", text = L["|cffaaaaaaShows the length of the current fight on its own. Hold Shift and drag it to move it.|r"] },
        { type = "toggle", label = L["Show the combat timer"],
          get = function() return timerTbl().enabled end,
          set = function(_, v)
              timerTbl().enabled = v
              DM.Timer.Apply()
              if v then DM.Timer.ShowPreview() else DM.Timer.HidePreview() end
              UI:BuildOptionsPage("damagemeter", "timer")
          end },
    }
    if not t.enabled then return items end

    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = subSlider(timerTbl, L["Text size"], "size", 10, 40, 1, apply)
    items[#items + 1] = subDropdown(timerTbl, L["Outline"], "outline", {
        { value = "INHERIT",      text = L["From the font settings"] },
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }, apply)
    items[#items + 1] = subToggle(timerTbl, L["Show tenths of a second"], "decimal", nil, apply)
    items[#items + 1] = subToggle(timerTbl, L["Accent color"], "useAccent", nil, apply)
    items[#items + 1] = subColor(timerTbl, L["Text color"], "color", apply)
    items[#items + 1] = subDropdown(timerTbl, L["Frame strata"], "strata", {
        { value = "BACKGROUND", text = "BACKGROUND" }, { value = "LOW", text = "LOW" },
        { value = "MEDIUM", text = "MEDIUM" }, { value = "HIGH", text = "HIGH" },
        { value = "DIALOG", text = "DIALOG" },
    }, apply)
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = subDropdown(timerTbl, L["Attach to a window"], "anchor", {
        { value = "free",        text = L["Free"] },
        { value = "topleft",     text = L["Top left"] },
        { value = "topright",    text = L["Top right"] },
        { value = "bottomleft",  text = L["Bottom left"] },
        { value = "bottomright", text = L["Bottom right"] },
    }, apply)
    items[#items + 1] = subToggle(timerTbl, L["Align the text left"], "alignLeft", nil, apply)
    items[#items + 1] = subToggle(timerTbl, L["Lock it in place"], "locked",
        L["No dragging, and the mouse goes through it."], apply)
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = subToggle(timerTbl, L["Keep it visible out of combat"], "showOOC",
        L["Shows the last fight's length while you are not fighting."], apply)
    items[#items + 1] = subToggle(timerTbl, L["Grey it out of combat"], "desatOOC", nil, apply)
    return items
end

local function shTbl() return DM.db().spellHistory end

local function historyOptions()
    local sh = shTbl()
    local apply = function() DM.SpellHistory.Apply() end
    local items = {
        { type = "header", text = L["Icon Strip"] },
        { type = "desc", text = L["|cffaaaaaaThe last spells you cast, as icons. Hold Shift and drag to move the strip.|r"] },
        { type = "toggle", label = L["Show the icon strip"],
          get = function() return shTbl().iconEnabled end,
          set = function(_, v)
              shTbl().iconEnabled = v
              DM.SpellHistory.Apply()
              UI:BuildOptionsPage("damagemeter", "history")
          end },
    }
    if sh.iconEnabled then
        items[#items + 1] = subDropdown(shTbl, L["Grow direction"], "growDirection", DM.SpellHistory.GrowValues(), apply)
        items[#items + 1] = subSlider(shTbl, L["Icon size"], "iconSize", 20, 60, 1, apply)
        items[#items + 1] = subSlider(shTbl, L["Icon zoom"], "iconZoom", 0, 0.2, 0.01, apply)
        items[#items + 1] = subSlider(shTbl, L["Number of icons"], "iconCount", 1, 10, 1, apply)
        items[#items + 1] = subSlider(shTbl, L["Icon spacing"], "iconSpacing", 0, 10, 1, apply)
        items[#items + 1] = subSlider(shTbl, L["Icon opacity"], "iconOpacity", 0.1, 1, 0.01, apply)
        items[#items + 1] = subDropdown(shTbl, L["Animation"], "iconAnimation", DM.SpellHistory.AnimationValues(), apply)
        items[#items + 1] = { type = "slider", label = L["Fade after"], min = 0, max = 60, step = 1,
            tooltip = L["Seconds before an icon fades. The clock pauses while you are fighting. Zero keeps them."],
            get = function() return shTbl().iconFadeTime end,
            set = function(_, v) shTbl().iconFadeTime = v; apply() end }
        items[#items + 1] = subToggle(shTbl, L["Hide in dungeons"], "iconHideInDungeon", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide in raids"], "iconHideInRaid", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide in PvP"], "iconHideInPvP", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide out of instances"], "iconHideOutOfInstance", nil, apply)
    end

    items[#items + 1] = { type = "spacer", height = 8 }
    items[#items + 1] = { type = "header", text = L["Cast History"] }
    items[#items + 1] = { type = "toggle", label = L["Show the cast history window"],
        get = function() return shTbl().barEnabled end,
        set = function(_, v)
            shTbl().barEnabled = v
            DM.SpellHistory.Apply()
            UI:BuildOptionsPage("damagemeter", "history")
        end }
    if sh.barEnabled then
        items[#items + 1] = subSlider(shTbl, L["Window width"], "barWidth", 150, 600, 5, apply)
        items[#items + 1] = subSlider(shTbl, L["Bar height"], "barHeight", 12, 32, 1, apply)
        items[#items + 1] = subSlider(shTbl, L["Number of bars"], "maxBars", 1, 10, 1, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide the top bar"], "hideTopBar", nil, apply)
        items[#items + 1] = subSlider(shTbl, L["Background opacity"], "bgAlpha", 0, 1, 0.01, apply)
        items[#items + 1] = subColor(shTbl, L["Background color"], "bgColor", apply)
        items[#items + 1] = subDropdown(shTbl, L["Bar texture"], "barTexture", (function()
            local v = { { value = "match", text = L["Same as the bars"] } }
            for _, e in ipairs(ns.MediaStatusbarValues()) do v[#v + 1] = e end
            return v
        end)(), apply, 220)
        items[#items + 1] = subToggle(shTbl, L["Class color"], "barColorUseClass", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Accent color instead"], "barColorUseAccent", nil, apply)
        items[#items + 1] = subColor(shTbl, L["Bar color"], "barColor", apply)
        items[#items + 1] = subSlider(shTbl, L["Bar opacity"], "barOpacity", 0.1, 1, 0.01, apply)
        items[#items + 1] = subSlider(shTbl, L["Text size"], "textSize", 8, 16, 1, apply)
        items[#items + 1] = subToggle(shTbl, L["Accent color for the text"], "textColorUseAccent", nil, apply)
        items[#items + 1] = subColor(shTbl, L["Text color"], "textColor", apply)
        items[#items + 1] = subToggle(shTbl, L["Hide in dungeons"], "barHideInDungeon", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide in raids"], "barHideInRaid", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide in PvP"], "barHideInPvP", nil, apply)
        items[#items + 1] = subToggle(shTbl, L["Hide out of instances"], "barHideOutOfInstance", nil, apply)
        items[#items + 1] = { type = "button", label = L["Clear the history"],
            onClick = function() DM.SpellHistory.Clear() end }
    end
    return items
end

-- ---------------------------------------------------------------- preview --

-- While the page is open the windows stay visible whatever the visibility
-- rules say, so the settings can be judged. Cleared when the window closes or
-- another module's page is shown.
local hooked = false

local function enterPreview()
    DM.optionsOpen = true
    DM.UpdateVisibilityAll()
    if DM.db().timer.enabled then DM.Timer.ShowPreview() end
    if not hooked then
        hooked = true
        hooksecurefunc(UI, "ShowModulePage", function(_, key)
            if key ~= "damagemeter" and DM.optionsOpen then DM.LeavePreview() end
        end)
        local f = UI.mainFrame
        if f then f:HookScript("OnHide", function() DM.LeavePreview() end) end
    end
end

function DM.LeavePreview()
    if not DM.optionsOpen then return end
    DM.optionsOpen = false
    DM.Timer.HidePreview()
    DM.UpdateVisibilityAll()
end

-- ---------------------------------------------------------------- threat --

local function threatTbl() return DM.db().threat end

local function soundValues()
    local v = {}
    local names = ns.LSM and ns.LSM:List("sound") or { "None" }
    for _, n in ipairs(names) do v[#v + 1] = { value = n, text = n } end
    return v
end

local function threatOptions()
    local t = threatTbl()
    local apply = function() DM.Threat.ApplyStyle(); DM.Threat.Preview() end
    local items = {
        { type = "header", text = L["Threat Meter"] },
        { type = "desc", text = L["|cffaaaaaaThe threat on your target for everyone in your group, one bar each, sorted. Targeting a friend, it shows the enemy that friend is fighting. It can add a bar for the point where you pull aggro, and warn you with a sound.|r"] },
        { type = "toggle", label = L["Show the threat meter"],
          get = function() return threatTbl().enabled end,
          set = function(_, v)
              threatTbl().enabled = v
              DM.Threat.Apply()
              if v then DM.Threat.Preview() end
              UI:BuildOptionsPage("damagemeter", "threat")
          end },
    }
    if not t.enabled then return items end

    items[#items + 1] = subDropdown(threatTbl, L["Visibility"], "visibility", {
        { value = "always",    text = L["Always shown"] },
        { value = "combat",    text = L["In combat"] },
        { value = "noncombat", text = L["Out of combat"] },
    }, apply)
    items[#items + 1] = { type = "header", text = L["Layout"] }
    items[#items + 1] = subSlider(threatTbl, L["Width"], "width", 80, 500, 1, function() DM.Threat.Apply(); DM.Threat.Preview() end)
    items[#items + 1] = subSlider(threatTbl, L["Bar height"], "barHeight", 8, 40, 1, apply)
    items[#items + 1] = subSlider(threatTbl, L["Bar spacing"], "spacing", 0, 10, 1, apply)
    items[#items + 1] = subSlider(threatTbl, L["Bars shown"], "maxBars", 1, 40, 1, apply)
    items[#items + 1] = subToggle(threatTbl, L["Grow upwards"], "growUp", nil, apply)
    items[#items + 1] = subToggle(threatTbl, L["Show the header"], "showHeader", nil, apply)
    items[#items + 1] = subToggle(threatTbl, L["Leave out pets"], "ignorePets", nil, apply)

    items[#items + 1] = { type = "header", text = L["Look"] }
    items[#items + 1] = subDropdown(threatTbl, L["Bar texture"], "texture", ns.MediaStatusbarValues(), apply, 220)
    items[#items + 1] = subSlider(threatTbl, L["Bar opacity"], "barOpacity", 0, 100, 1, apply)
    items[#items + 1] = subSlider(threatTbl, L["Background opacity"], "bgAlpha", 0, 1, 0.05, apply)
    items[#items + 1] = subSlider(threatTbl, L["Border size"], "borderSize", 0, 4, 1, apply)
    items[#items + 1] = subColor(threatTbl, L["Border color"], "borderColor", apply)

    items[#items + 1] = { type = "header", text = L["Text"] }
    items[#items + 1] = subSlider(threatTbl, L["Text size"], "textSize", 6, 24, 1, apply)
    items[#items + 1] = subDropdown(threatTbl, L["Outline"], "outline", {
        { value = "INHERIT",      text = L["From the font settings"] },
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }, apply)
    items[#items + 1] = subToggle(threatTbl, L["Show the threat value"], "showValue", nil, apply)
    items[#items + 1] = subToggle(threatTbl, L["Show the percentage"], "showPercent", nil, apply)

    items[#items + 1] = { type = "header", text = L["Colors"] }
    items[#items + 1] = subToggle(threatTbl, L["Own color for you"], "playerColorOn", nil, apply)
    items[#items + 1] = subColor(threatTbl, L["Your color"], "playerColor", apply)
    items[#items + 1] = subToggle(threatTbl, L["Own color for the tank"], "tankColorOn", nil, apply)
    items[#items + 1] = subColor(threatTbl, L["Tank color"], "tankColor", apply)
    items[#items + 1] = subToggle(threatTbl, L["Show where you pull aggro"], "pullBar", nil, apply)
    items[#items + 1] = subColor(threatTbl, L["Pull aggro color"], "pullColor", apply)

    items[#items + 1] = { type = "header", text = L["Warning"] }
    items[#items + 1] = subToggle(threatTbl, L["Warn with a sound"], "warnSound", nil, apply)
    items[#items + 1] = { type = "dropdown", label = L["Sound"], width = 220, values = soundValues(),
        get = function() return threatTbl().warnSoundKey end,
        set = function(_, v) threatTbl().warnSoundKey = v; DM.Threat.PlayWarning() end }
    items[#items + 1] = subSlider(threatTbl, L["Warn at threat %"], "warnAt", 50, 100, 1, apply)
    items[#items + 1] = subToggle(threatTbl, L["Not while you tank"], "warnSkipTank",
        L["Tank role, Bear or Dire Bear Form, or Defensive Stance."], apply)
    return items
end

function mod:GetOptions(tabId)
    if mod.active then enterPreview() end
    if tabId == "window"  then return windowOptions() end
    if tabId == "bars"    then return barsOptions() end
    if tabId == "text"    then return textOptions() end
    if tabId == "timer"   then return timerOptions() end
    if tabId == "history" then return historyOptions() end
    if tabId == "threat"  then return threatOptions() end
    return generalOptions()
end
