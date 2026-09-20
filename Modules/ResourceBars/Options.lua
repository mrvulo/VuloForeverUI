-- VuloForeverUI / Modules / ResourceBars / Options
--
-- Three tabs, one per kind of bar, and inside each tab one section per bar.
-- Every bar has the same shape, so the look controls are written once and
-- handed the key they belong to; only the few settings that are particular to
-- a kind of bar are written out separately.
local _, ns = ...
local L  = ns.L
local RB = ns.RB
local UI = ns.UI

local mod = RB.mod

mod.tabs = {
    { id = "resources", label = "Resources" },
    { id = "cast",      label = "Cast bar" },
    { id = "swing",     label = "Swing timer" },
}

-- Deferred: a dropdown writes its own label after set() returns, and
-- rebuilding the page from inside set() hands that write to whatever pooled
-- widget the rebuild happened to hand out.
local function rebuild(tabId)
    ns.NextFrame(function()
        UI:BuildOptionsPage("resourcebars", tabId)
    end)
end

local function apply()
    RB.StyleAll()
    RB.Power.Rescan()
    -- Not in combat: this one reaches for Blizzard's own cast bar, a protected
    -- frame, and a slider being dragged calls apply() once per frame. Out of
    -- combat it is free; in combat it would be a blocked action per frame, and
    -- a blocked call on this client raises nothing that would warn us.
    if not ns:InCombat() then RB.Cast.Apply() end
    RB.UpdateAll()
end

-- ---------------------------------------------------------------- widgets --

local function toggle(key, field, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip, subKey = key .. field,
        get = function() return RB.Bar(key)[field] end,
        set = function(_, v) RB.Bar(key)[field] = v; apply() end }
end

local function slider(key, field, label, min, max, step)
    return { type = "slider", label = label, min = min, max = max, step = step, subKey = key .. field,
        get = function() return RB.Bar(key)[field] end,
        set = function(_, v) RB.Bar(key)[field] = v; apply() end }
end

local function color(key, field, label)
    return { type = "color", label = label, subKey = key .. field,
        get = function() return RB.Bar(key)[field] end,
        set = function(r, g, b)
            local c = RB.Bar(key)[field]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

local function dropdown(key, field, label, values, width)
    return { type = "dropdown", label = label, width = width or 200, values = values, subKey = key .. field,
        get = function() return RB.Bar(key)[field] end,
        set = function(_, v) RB.Bar(key)[field] = v; apply() end }
end

-- The look every bar shares. Returned as a flat list so a page can put its own
-- rows before and after it.
local function lookRows(key)
    local rows = {
        { type = "header", text = L["Size and texture"] },
        slider(key, "width", L["Width"], 60, 600, 2),
        slider(key, "height", L["Height"], 4, 60, 1),
        dropdown(key, "texture", L["Bar texture"], ns.MediaStatusbarValues(), 220),
        toggle(key, "showSpark", L["Show the spark"]),
        slider(key, "borderSize", L["Border size"], 0, 4, 1),
        color(key, "borderColor", L["Border color"]),
        color(key, "bgColor", L["Background color"]),
        color(key, "fillColor", L["Fill color"]),

        { type = "header", text = L["Text"] },
        slider(key, "fontSize", L["Text size"], 6, 24, 1),
        color(key, "textColor", L["Text color"]),
        dropdown(key, "leftText", L["Left text"], {
            { value = "none",  text = L["Nothing"] },
            { value = "name",  text = L["The name"] },
            { value = "label", text = L["A fixed label"] },
        }),
        dropdown(key, "rightText", L["Right text"], {
            { value = "none",     text = L["Nothing"] },
            { value = "value",    text = L["The value"] },
            { value = "valuemax", text = L["Value and maximum"] },
            { value = "percent",  text = L["Percent"] },
            { value = "time",     text = L["The remaining time"] },
        }),

        { type = "header", text = L["Visibility"] },
        dropdown(key, "visibility", L["Show the bar"], {
            { value = "always",    text = L["Always shown"] },
            { value = "combat",    text = L["In combat"] },
            { value = "noncombat", text = L["Out of combat"] },
            { value = "hidden",    text = L["Never"] },
        }, 220),
        slider(key, "opacity", L["Opacity"], 0.1, 1, 0.01),
        toggle(key, "oocFade", L["Fade out of combat"]),
        slider(key, "oocAlpha", L["Faded opacity"], 0.05, 1, 0.01),
    }
    return rows
end

local function tickRows(key)
    return {
        { type = "header", text = L["Tick marks"] },
        { type = "desc", text = L["|cffaaaaaaNumbers separated by commas, for instance 30,60,90. They are your numbers, so they are drawn whatever the client lets us read of the bar itself.|r"] },
        { type = "editbox", label = L["Ticks"], width = 220, subKey = key .. "ticks",
          get = function() return RB.Bar(key).ticks end,
          set = function(_, v) RB.Bar(key).ticks = v or ""; apply() end },
        toggle(key, "tickPercent", L["The ticks are percentages"],
            L["Off means they are plain values, drawn against the maximum."]),
        slider(key, "tickWidth", L["Tick width"], 1, 4, 1),
        color(key, "tickColor", L["Tick color"]),
    }
end

-- Each bar gets its own collapsible section, so a tab with three bars in it
-- opens as three lines rather than as a wall of sliders.
local function section(key, items)
    return { type = "section", title = RB.Label(key), items = items,
             collapsible = true, key = key }
end

local function enabledRow(key)
    return { type = "toggle", label = L["Bar enabled"], subKey = key .. "enabled",
        get = function() return RB.Bar(key).enabled end,
        set = function(_, v) RB.Bar(key).enabled = v; apply() end }
end

-- ---------------------------------------------------------------- pages --

local function resourcesPage()
    local power = { enabledRow("power") }
    for _, row in ipairs({
        { type = "toggle", label = L["Use the colour of the power"], subKey = "powerUseTypeColor",
          tooltip = L["Mana blue, rage red, and so on, as the client names them."],
          get = function() return RB.Bar("power").useTypeColor end,
          set = function(_, v) RB.Bar("power").useTypeColor = v; apply() end },
        { type = "header", text = L["Threshold"] },
        { type = "desc", text = L["|cffaaaaaaColours the bar below this many percent. The client evaluates it against your power itself -- the number never reaches the addon, which is why it also works in combat.|r"] },
        slider("power", "thresholdPct", L["Threshold in percent"], 0, 100, 1),
        color("power", "thresholdColor", L["Threshold color"]),
    }) do power[#power + 1] = row end
    for _, row in ipairs(tickRows("power")) do power[#power + 1] = row end
    for _, row in ipairs(lookRows("power")) do power[#power + 1] = row end

    local mana = { enabledRow("mana"),
        { type = "toggle", label = L["Only while a form hides it"], subKey = "manaOnlyInForms",
          tooltip = L["The bar stays away while mana is your normal resource anyway."],
          get = function() return RB.Bar("mana").onlyInForms end,
          set = function(_, v) RB.Bar("mana").onlyInForms = v; apply() end },
    }
    for _, row in ipairs(tickRows("mana")) do mana[#mana + 1] = row end
    for _, row in ipairs(lookRows("mana")) do mana[#mana + 1] = row end

    return {
        { type = "desc", text = L["|cffaaaaaaTwo bars: the power you spend, and the mana a form keeps out of sight. Move both with /vedit.|r"] },
        section("power", power),
        section("mana", mana),
        { type = "button", label = L["Open Edit Mode"], onClick = function() ns:SetEditMode(true) end },
    }
end

local function castPage()
    local style = RB.Bar("cast").castStyle or "standard"

    local page = {
        { type = "dropdown", label = L["Cast bar style"], width = 260, subKey = "castStyle",
          values = {
              { value = "standard", text = L["Standard -- the client's own bar"] },
              { value = "classic",  text = L["Classic -- the client's bar in the old shape"] },
              { value = "modern",   text = L["Modern -- our own bar"] },
          },
          get = function() return RB.Bar("cast").castStyle end,
          set = function(_, v)
              RB.Bar("cast").castStyle = v
              apply()
              rebuild("cast")
          end },
    }

    if style == "modern" then
        page[#page + 1] = { type = "desc", text = L["|cffaaaaaaOur own bar, placed with /vedit like every other bar here. The client's own cast bar is hidden while this style is on.|r"] }
        page[#page + 1] = enabledRow("cast")
        page[#page + 1] = { type = "toggle", label = L["Hide the client's own cast bar"], subKey = "castHideBlizzard",
            tooltip = L["Its frame belongs to the protected part of the interface, so it is hidden rather than moved."],
            get = function() return RB.Bar("cast").hideBlizzard end,
            set = function(_, v) RB.Bar("cast").hideBlizzard = v; apply() end }
        page[#page + 1] = toggle("cast", "showIcon", L["Show the spell icon"])
        page[#page + 1] = dropdown("cast", "iconSide", L["Icon side"], {
            { value = "LEFT",  text = L["Left of the bar"] },
            { value = "RIGHT", text = L["Right of the bar"] },
        })
        page[#page + 1] = { type = "header", text = L["Colours"] }
        page[#page + 1] = color("cast", "channelColor", L["Channel color"])
        page[#page + 1] = color("cast", "uninterruptibleColor", L["Uninterruptible color"])
        page[#page + 1] = toggle("cast", "showShield", L["Show the shield on an uninterruptible cast"])
        page[#page + 1] = { type = "desc", text = L["|cffaaaaaaWhether a cast can be interrupted is a secret on this client, so the client picks between the two colours itself and the addon never learns which one it took.|r"] }
        for _, row in ipairs(lookRows("cast")) do page[#page + 1] = row end
        return page
    end

    -- Standard and Classic both keep the client's bar, so everything below is
    -- about what we put NEXT to it -- the bar itself is not ours to lay out.
    if style == "classic" then
        page[#page + 1] = { type = "desc", text = L["|cffaaaaaaThe client's own bar, dressed back to the old shape: 195 by 13, the old border, the plain fill in the four old colours, and none of the modern glow.|r"] }
    else
        page[#page + 1] = { type = "desc", text = L["|cffaaaaaaThe client's own bar, exactly as it comes. Everything below is added beside it and changes nothing about the bar itself.|r"] }
    end

    page[#page + 1] = { type = "header", text = L["The spell icon"] }
    page[#page + 1] = { type = "toggle", label = L["Show the spell icon"], subKey = "castAttachIcon",
        get = function() return RB.Bar("cast").attachIcon end,
        set = function(_, v) RB.Bar("cast").attachIcon = v; apply() end }
    page[#page + 1] = slider("cast", "attachIconSize", L["Icon size"], 8, 48, 1)
    page[#page + 1] = slider("cast", "attachIconX", L["Icon sideways"], -200, 200, 1)
    page[#page + 1] = slider("cast", "attachIconY", L["Icon up and down"], -100, 100, 1)

    page[#page + 1] = { type = "header", text = L["The cast time"] }
    page[#page + 1] = { type = "toggle", label = L["Show the cast time"], subKey = "castAttachTime",
        get = function() return RB.Bar("cast").attachTime end,
        set = function(_, v) RB.Bar("cast").attachTime = v; apply() end }
    page[#page + 1] = slider("cast", "attachTimeSize", L["Text size"], 6, 24, 1)
    page[#page + 1] = slider("cast", "attachTimeX", L["Time sideways"], -200, 200, 1)
    page[#page + 1] = slider("cast", "attachTimeY", L["Time up and down"], -100, 100, 1)
    page[#page + 1] = { type = "desc", text = L["|cffaaaaaaThe time is written by the client from the cast's own duration, which is the only way to show it while the numbers behind it are secret.|r"] }

    return page
end

local function swingPage()
    local page = {
        { type = "desc", text = L["|cffaaaaaaThere is no combat log on this client, so these bars are driven by the client's own swing event instead -- one bar per weapon, each shown while that weapon is between swings.|r"] },
    }
    for _, key in ipairs({ "swingMain", "swingOff", "swingRanged" }) do
        local rows = {
            enabledRow(key),
            toggle(key, "showRange", L["Colour it when the target is out of reach"]),
            color(key, "outOfRangeColor", L["Out of reach color"]),
        }
        for _, row in ipairs(lookRows(key)) do rows[#rows + 1] = row end
        page[#page + 1] = section(key, rows)
    end
    return page
end

-- ---------------------------------------------------------------- preview --

-- While the page is open every bar is on screen, transient ones included:
-- a swing bar cannot be placed in the seconds it is actually visible.
-- The settings window does not exist at login -- it is built the first time
-- someone opens it. So the hook that ends the preview when the window closes
-- cannot be laid at login either; it is laid here, the first time the page is
-- actually shown, which is the first moment the window is there to hook.
local hookedHide = false

local function enterPreview()
    if RB.optionsOpen then return end
    RB.optionsOpen = true
    if not hookedHide then
        local f = UI.mainFrame
        if f then
            hookedHide = true
            f:HookScript("OnHide", function() RB.LeavePreview() end)
        end
    end
    RB.Each(function(key) RB.BuildBar(key) end)
    RB.StyleAll()
    RB.UpdateAll()
end

-- Installed from OnEnable, not from inside the preview itself: a hook that is
-- only laid by the function it is supposed to call never fires at all, which
-- is exactly what had happened to the cooldown bars' preview.
local hooked = false

function RB.HookPreview()
    if hooked then return end
    hooked = true
    hooksecurefunc(UI, "ShowModulePage", function(_, key)
        if key == "resourcebars" then
            enterPreview()
        elseif RB.optionsOpen then
            RB.LeavePreview()
        end
    end)
end

function RB.LeavePreview()
    if not RB.optionsOpen then return end
    RB.optionsOpen = false
    RB.UpdateAll()
end

function mod:GetOptions(tabId)
    if tabId == "cast"  then return castPage() end
    if tabId == "swing" then return swingPage() end
    return resourcesPage()
end
