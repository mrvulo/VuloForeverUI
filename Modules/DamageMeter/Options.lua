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

local rows = ns.OptionRows(d, nil, { dropdownWidth = 200 })
local toggle, slider, dropdown, color = rows.toggle, rows.slider, rows.dropdown, rows.color

local function restyle() DM.RestyleAll() end
local function repaint() DM.RefreshAll() end
local function visibility() DM.UpdateVisibilityAll() end

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
          tooltip = L["Classic draws the windows the way Blizzard frames its own: the metal frame over the rock background, the title in gold on the metal band, and the 1.x buttons. The first switch also sets the game's own bar fill and a dark track behind the bars; after that those settings are yours again."],
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
        toggle("toggleIncludeTimer", L["The key also hides the combat timer"]),
        toggle("toggleIncludeSpellHistory", L["The key also hides the cast history"]),
        toggle("hideResetButton", L["Hide the reset button"], { after = restyle }),

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
        slider("bgAlpha", L["Opacity"], 0, 1, 0.01, { after = restyle }),
        color("bgColor", L["Background color"], { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Border"] },
        ns.BorderRows(rows, { texture = "windowBorderTexture", size = "windowBorderSize",
            color = "windowBorderColor", alpha = "windowBorderAlpha" }, { maxSize = 8, after = restyle }),
        slider("windowBorderOffsetX", L["Border offset X"], -10, 10, 1, { after = restyle }),
        slider("windowBorderOffsetY", L["Border offset Y"], -10, 10, 1, { after = restyle }),
        toggle("windowBorderIncludeHeader", L["Include the header"], { after = restyle }),
        toggle("windowBorderBehind", L["Draw behind the bars"], { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Header"] },
        slider("hdrHeight", L["Header height"], 14, 40, 1, { after = restyle }),
        slider("hdrBgAlpha", L["Header opacity"], 0, 1, 0.01, { after = restyle }),
        color("hdrBgColor", L["Header color"], { after = restyle }),
        slider("hdrFontSize", L["Header text size"], 8, 18, 1, { after = restyle }),
        toggle("hdrTextUseAccent", L["Accent color for the header text"], { after = restyle }),
        color("hdrTextColor", L["Header text color"], { after = restyle }),
        slider("hdrTextOffX", L["Header text offset X"], -20, 20, 1, { after = restyle }),
        slider("hdrTextOffY", L["Header text offset Y"], -20, 20, 1, { after = restyle }),
        { type = "header", text = L["Bottom border"] },
        ns.BorderRows(rows, { size = "hdrBottomBorderSize", color = "hdrBottomBorderColor",
            alpha = "hdrBottomBorderAlpha" }, { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Header icons"] },
        slider("hdrIconSize", L["Icon size"], 16, 32, 1, { after = restyle }),
        toggle("hdrMouseoverIcons", L["Show the icons only on mouseover"], { after = restyle }),
        toggle("iconColorUseAccent", L["Accent color for the icons"], { after = restyle }),
        color("iconColor", L["Icon color"], { after = restyle }),
    }
end

local function barsOptions()
    return {
        { type = "header", text = L["Bars"] },
        dropdown("barTexture", L["Bar texture"], ns.MediaStatusbarValues(), { after = restyle, width = 220 }),
        slider("barHeight", L["Bar height"], 8, 40, 1, { after = restyle }),
        slider("barSpacing", L["Spacing"], -1, 10, 1, { after = restyle }),
        slider("barFillAlpha", L["Fill opacity"], 0, 1, 0.01, { after = restyle }),
        toggle("showClassColor", L["Class color"], { after = restyle }),
        toggle("barColorUseAccent", L["Accent color instead"], { after = restyle }),
        color("barColor", L["Bar color"], { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Bar background"] },
        slider("barBgAlpha", L["Background opacity"], 0, 1, 0.01, { after = restyle }),
        toggle("barBgUseClassColor", L["Class color for the background"], { after = restyle }),
        color("barBgColor", L["Background color"], { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Icons"] },
        dropdown("iconStyle", L["Icon style"], DM.IconStyleValues(), { after = restyle, width = 220 }),
        { type = "slider", label = L["Icon zoom"], min = 0, max = 0.2, step = 0.01,
          tooltip = L["Applies to the spec and Blizzard class icons; the other sets are already framed."],
          get = function() return d().classIconZoom end,
          set = function(_, v) d().classIconZoom = v; restyle() end },
        { type = "header", text = L["Border around the icon"] },
        ns.BorderRows(rows, { show = "customIconBorder", size = "iconBorderSize",
            color = "iconBorderColor", alpha = "iconBorderAlpha" }, { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Bar border"] },
        ns.BorderRows(rows, { texture = "borderTexture", size = "borderSize",
            color = "borderColor", alpha = "borderAlpha" }, { after = restyle }),
        { type = "toggle", label = L["The border follows the fill"],
          tooltip = L["Wraps only the filled part of a bar instead of the whole row. Always drawn solid."],
          get = function() return d().borderFollowFill end,
          set = function(_, v) d().borderFollowFill = v; restyle() end },
        toggle("borderFollowFillIcon", L["Include the icon in that border"], { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Breakdown"] },
        toggle("showHoverTooltip", L["Show the breakdown on mouseover"]),
        toggle("showSpellTooltips", L["Show the game's spell tooltip"]),
        toggle("showAllBreakdownSpells", L["Show fifteen rows instead of eight"]),
        dropdown("breakdownBarTexture", L["Breakdown texture"], (function()
            local v = { { value = "match", text = L["Same as the bars"] } }
            for _, e in ipairs(ns.MediaStatusbarValues()) do v[#v + 1] = e end
            return v
        end)(), { after = repaint, width = 220 }),
        dropdown("breakdownAnchorPoint", L["Breakdown position"], {
            { value = "row",    text = L["Above the row"] },
            { value = "center", text = L["Center of the screen"] },
            { value = "left",   text = L["Left of the window"] },
            { value = "right",  text = L["Right of the window"] },
        }, { after = repaint }),
        slider("hoverTooltipScale", L["Breakdown scale"], 80, 150, 1, { after = repaint }),
    }
end

local function textOptions()
    return {
        { type = "header", text = L["Numbers"] },
        dropdown("numberFormat", L["Number format"], {
            { value = 0, text = L["Per second"] },
            { value = 1, text = L["Total"] },
            { value = 2, text = L["Total (per second)"] },
            { value = 3, text = L["Total | per second"] },
        }, { after = repaint, width = 220 }),
        toggle("hideNumbers", L["Hide the rank numbers"], { tooltip = L["Hides the 1. 2. 3. in front of each name."], after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Left text"] },
        slider("leftFontSize", L["Left text size"], 8, 18, 1, { after = restyle }),
        toggle("leftTextUseClassColor", L["Class color on the left"], { after = restyle }),
        color("leftTextColor", L["Left text color"], { after = restyle }),
        slider("leftTextOffsetX", L["Left offset X"], -20, 20, 1, { after = restyle }),
        slider("leftTextOffsetY", L["Left offset Y"], -20, 20, 1, { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Right text"] },
        slider("rightFontSize", L["Right text size"], 8, 18, 1, { after = restyle }),
        toggle("rightTextUseClassColor", L["Class color on the right"], { after = restyle }),
        color("rightTextColor", L["Right text color"], { after = restyle }),
        slider("rightTextOffsetX", L["Right offset X"], -20, 20, 1, { after = restyle }),
        slider("rightTextOffsetY", L["Right offset Y"], -20, 20, 1, { after = restyle }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Your own row"] },
        { type = "toggle", label = L["Always show your own bar"],
          tooltip = L["Pins your bar to the edge of the window while it has scrolled out of sight."],
          get = function() return d().showPinnedSelf end,
          set = function(_, v) d().showPinnedSelf = v; repaint() end },
    }
end

local function timerTbl() return DM.db().timer end
local timerRows = ns.OptionRows(timerTbl, nil, { dropdownWidth = 200 })

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
    items[#items + 1] = timerRows.slider("size", L["Text size"], 10, 40, 1, { after = apply })
    items[#items + 1] = timerRows.dropdown("outline", L["Outline"], {
        { value = "INHERIT",      text = L["From the font settings"] },
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }, { after = apply })
    items[#items + 1] = timerRows.toggle("decimal", L["Show tenths of a second"], { after = apply })
    items[#items + 1] = timerRows.toggle("useAccent", L["Accent color"], { after = apply })
    items[#items + 1] = timerRows.color("color", L["Text color"], { after = apply })
    items[#items + 1] = timerRows.dropdown("strata", L["Frame strata"], {
        { value = "BACKGROUND", text = "BACKGROUND" }, { value = "LOW", text = "LOW" },
        { value = "MEDIUM", text = "MEDIUM" }, { value = "HIGH", text = "HIGH" },
        { value = "DIALOG", text = "DIALOG" },
    }, { after = apply })
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = timerRows.dropdown("anchor", L["Attach to a window"], {
        { value = "free",        text = L["Free"] },
        { value = "topleft",     text = L["Top left"] },
        { value = "topright",    text = L["Top right"] },
        { value = "bottomleft",  text = L["Bottom left"] },
        { value = "bottomright", text = L["Bottom right"] },
    }, { after = apply })
    items[#items + 1] = timerRows.toggle("alignLeft", L["Align the text left"], { after = apply })
    items[#items + 1] = timerRows.toggle("locked", L["Lock it in place"], { tooltip = L["No dragging, and the mouse goes through it."], after = apply })
    items[#items + 1] = { type = "spacer", height = 6 }
    items[#items + 1] = timerRows.toggle("showOOC", L["Keep it visible out of combat"], { tooltip = L["Shows the last fight's length while you are not fighting."], after = apply })
    items[#items + 1] = timerRows.toggle("desatOOC", L["Grey it out of combat"], { after = apply })
    return items
end

local function shTbl() return DM.db().spellHistory end
local shRows = ns.OptionRows(shTbl, nil, { dropdownWidth = 200 })

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
        items[#items + 1] = shRows.dropdown("growDirection", L["Grow direction"], DM.SpellHistory.GrowValues(), { after = apply })
        items[#items + 1] = shRows.slider("iconSize", L["Icon size"], 20, 60, 1, { after = apply })
        items[#items + 1] = shRows.slider("iconZoom", L["Icon zoom"], 0, 0.2, 0.01, { after = apply })
        items[#items + 1] = shRows.slider("iconCount", L["Number of icons"], 1, 10, 1, { after = apply })
        items[#items + 1] = shRows.slider("iconSpacing", L["Icon spacing"], 0, 10, 1, { after = apply })
        items[#items + 1] = shRows.slider("iconOpacity", L["Icon opacity"], 0.1, 1, 0.01, { after = apply })
        items[#items + 1] = shRows.dropdown("iconAnimation", L["Animation"], DM.SpellHistory.AnimationValues(), { after = apply })
        items[#items + 1] = { type = "slider", label = L["Fade after"], min = 0, max = 60, step = 1,
            tooltip = L["Seconds before an icon fades. The clock pauses while you are fighting. Zero keeps them."],
            get = function() return shTbl().iconFadeTime end,
            set = function(_, v) shTbl().iconFadeTime = v; apply() end }
        items[#items + 1] = shRows.toggle("iconHideInDungeon", L["Hide in dungeons"], { after = apply })
        items[#items + 1] = shRows.toggle("iconHideInRaid", L["Hide in raids"], { after = apply })
        items[#items + 1] = shRows.toggle("iconHideInPvP", L["Hide in PvP"], { after = apply })
        items[#items + 1] = shRows.toggle("iconHideOutOfInstance", L["Hide out of instances"], { after = apply })
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
        items[#items + 1] = shRows.slider("barWidth", L["Window width"], 150, 600, 5, { after = apply })
        items[#items + 1] = shRows.slider("barHeight", L["Bar height"], 12, 32, 1, { after = apply })
        items[#items + 1] = shRows.slider("maxBars", L["Number of bars"], 1, 10, 1, { after = apply })
        items[#items + 1] = shRows.toggle("hideTopBar", L["Hide the top bar"], { after = apply })
        items[#items + 1] = shRows.slider("bgAlpha", L["Background opacity"], 0, 1, 0.01, { after = apply })
        items[#items + 1] = shRows.color("bgColor", L["Background color"], { after = apply })
        items[#items + 1] = shRows.dropdown("barTexture", L["Bar texture"], (function()
            local v = { { value = "match", text = L["Same as the bars"] } }
            for _, e in ipairs(ns.MediaStatusbarValues()) do v[#v + 1] = e end
            return v
        end)(), { after = apply, width = 220 })
        items[#items + 1] = shRows.toggle("barColorUseClass", L["Class color"], { after = apply })
        items[#items + 1] = shRows.toggle("barColorUseAccent", L["Accent color instead"], { after = apply })
        items[#items + 1] = shRows.color("barColor", L["Bar color"], { after = apply })
        items[#items + 1] = shRows.slider("barOpacity", L["Bar opacity"], 0.1, 1, 0.01, { after = apply })
        items[#items + 1] = shRows.slider("textSize", L["Text size"], 8, 16, 1, { after = apply })
        items[#items + 1] = shRows.toggle("textColorUseAccent", L["Accent color for the text"], { after = apply })
        items[#items + 1] = shRows.color("textColor", L["Text color"], { after = apply })
        items[#items + 1] = shRows.toggle("barHideInDungeon", L["Hide in dungeons"], { after = apply })
        items[#items + 1] = shRows.toggle("barHideInRaid", L["Hide in raids"], { after = apply })
        items[#items + 1] = shRows.toggle("barHideInPvP", L["Hide in PvP"], { after = apply })
        items[#items + 1] = shRows.toggle("barHideOutOfInstance", L["Hide out of instances"], { after = apply })
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
        UI:OnMainFrameHide(function() DM.LeavePreview() end)
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
local threatRows = ns.OptionRows(threatTbl, nil, { dropdownWidth = 200 })

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

    items[#items + 1] = threatRows.dropdown("visibility", L["Visibility"], {
        { value = "always",    text = L["Always shown"] },
        { value = "combat",    text = L["In combat"] },
        { value = "noncombat", text = L["Out of combat"] },
    }, { after = apply })
    items[#items + 1] = { type = "header", text = L["Layout"] }
    items[#items + 1] = threatRows.slider("width", L["Width"], 80, 500, 1, { after = function() DM.Threat.Apply(); DM.Threat.Preview() end })
    items[#items + 1] = threatRows.slider("barHeight", L["Bar height"], 8, 40, 1, { after = apply })
    items[#items + 1] = threatRows.slider("spacing", L["Bar spacing"], 0, 10, 1, { after = apply })
    items[#items + 1] = threatRows.slider("maxBars", L["Bars shown"], 1, 40, 1, { after = apply })
    items[#items + 1] = threatRows.toggle("growUp", L["Grow upwards"], { after = apply })
    items[#items + 1] = threatRows.toggle("showHeader", L["Show the header"], { after = apply })
    items[#items + 1] = threatRows.toggle("ignorePets", L["Leave out pets"], { after = apply })

    items[#items + 1] = { type = "header", text = L["Look"] }
    items[#items + 1] = threatRows.dropdown("texture", L["Bar texture"], ns.MediaStatusbarValues(), { after = apply, width = 220 })
    items[#items + 1] = threatRows.slider("barOpacity", L["Bar opacity"], 0, 100, 1, { after = apply })
    items[#items + 1] = threatRows.slider("bgAlpha", L["Background opacity"], 0, 1, 0.05, { after = apply })
    items[#items + 1] = ns.BorderRows(threatRows, { size = "borderSize", color = "borderColor" }, { after = apply })

    items[#items + 1] = { type = "header", text = L["Text"] }
    items[#items + 1] = threatRows.slider("textSize", L["Text size"], 6, 24, 1, { after = apply })
    items[#items + 1] = threatRows.dropdown("outline", L["Outline"], {
        { value = "INHERIT",      text = L["From the font settings"] },
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Outline"] },
        { value = "THICKOUTLINE", text = L["Thick outline"] },
    }, { after = apply })
    items[#items + 1] = threatRows.toggle("showValue", L["Show the threat value"], { after = apply })
    items[#items + 1] = threatRows.toggle("showPercent", L["Show the percentage"], { after = apply })

    items[#items + 1] = { type = "header", text = L["Colors"] }
    items[#items + 1] = threatRows.toggle("playerColorOn", L["Own color for you"], { after = apply })
    items[#items + 1] = threatRows.color("playerColor", L["Your color"], { after = apply })
    items[#items + 1] = threatRows.toggle("tankColorOn", L["Own color for the tank"], { after = apply })
    items[#items + 1] = threatRows.color("tankColor", L["Tank color"], { after = apply })
    items[#items + 1] = threatRows.toggle("pullBar", L["Show where you pull aggro"], { after = apply })
    items[#items + 1] = threatRows.color("pullColor", L["Pull aggro color"], { after = apply })

    items[#items + 1] = { type = "header", text = L["Warning"] }
    items[#items + 1] = threatRows.toggle("warnSound", L["Warn with a sound"], { after = apply })
    items[#items + 1] = { type = "dropdown", label = L["Sound"], width = 220, values = soundValues(),
        get = function() return threatTbl().warnSoundKey end,
        set = function(_, v) threatTbl().warnSoundKey = v; DM.Threat.PlayWarning() end }
    items[#items + 1] = threatRows.slider("warnAt", L["Warn at threat %"], 50, 100, 1, { after = apply })
    items[#items + 1] = threatRows.toggle("warnSkipTank", L["Not while you tank"], { tooltip = L["Tank role, Bear or Dire Bear Form, or Defensive Stance."], after = apply })
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
