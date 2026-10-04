-- VuloForeverUI / Modules / ResourceBars / Options
--
-- Four tabs, one per kind of bar, and inside each tab one section per bar.
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
    { id = "xp",        label = "XP bar" },
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
    -- The preview first: it is drawn whether the module is on or not.
    if RB.RefreshPreview then RB.RefreshPreview() end
    if not RB.mod.active then return end
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

-- Rows of one bar: the db is that bar's table, and subKey keeps two bars'
-- rows of the same field apart in the change tracking.
local rowSets = {}
local function rowsFor(key)
    local set = rowSets[key]
    if not set then
        set = ns.OptionRows(function() return RB.Bar(key) end, apply, { dropdownWidth = 200 })
        rowSets[key] = set
    end
    return set
end

local function toggle(key, field, label, tooltip)
    return rowsFor(key).toggle(field, label, { tooltip = tooltip, subKey = key .. field })
end

local function slider(key, field, label, min, max, step)
    return rowsFor(key).slider(field, label, min, max, step, { subKey = key .. field })
end

local function color(key, field, label)
    return rowsFor(key).color(field, label, { subKey = key .. field })
end

local function opacity(key, field, label, extra)
    extra = extra or {}
    extra.subKey = key .. field
    return rowsFor(key).opacity(field, label, extra)
end

local function dropdown(key, field, label, values, width)
    return rowsFor(key).dropdown(field, label, values, { width = width, subKey = key .. field })
end

-- The look every bar shares. Returned as a flat list so a page can put its own
-- rows before and after it. `own` leaves out the fill colour and the two text
-- corners, for a bar that brings its own (the experience bar).
local function lookRows(key, own)
    local rows = {
        { type = "header", text = L["Size and texture"] },
        -- an experience bar is often laid across the whole screen
        slider(key, "width", L["Width"], 60, own and 1600 or 600, 2),
        slider(key, "height", L["Height"], 4, 60, 1),
        dropdown(key, "texture", L["Bar texture"], ns.MediaStatusbarValues(), 220),
        toggle(key, "showSpark", L["Show the spark"]),
        ns.BorderRows(rowsFor(key), { size = "borderSize", color = "borderColor" }, { subKeyPrefix = key }),
        color(key, "bgColor", L["Background color"]),
    }
    if not own then rows[#rows + 1] = color(key, "fillColor", L["Fill color"]) end
    for _, row in ipairs({
        { type = "header", text = L["Text"] },
        slider(key, "fontSize", L["Text size"], 6, 24, 1),
        color(key, "textColor", L["Text color"]),
        { type = "dropdown", label = L["Text layer"], width = 220,
          values = {
              { value = "top",   text = L["Over the bar"] },
              { value = "under", text = L["Under the bar"] },
          },
          get = function() return RB.Bar(key).textLayer or "top" end,
          set = function(_, v) RB.Bar(key).textLayer = v; apply() end },
    }) do rows[#rows + 1] = row end
    if not own then
        rows[#rows + 1] = dropdown(key, "leftText", L["Left text"], {
            { value = "none",  text = L["Nothing"] },
            { value = "name",  text = L["The name"] },
            { value = "label", text = L["A fixed label"] },
        })
        rows[#rows + 1] = dropdown(key, "rightText", L["Right text"], {
            { value = "none",     text = L["Nothing"] },
            { value = "value",    text = L["The value"] },
            { value = "valuemax", text = L["Value and maximum"] },
            { value = "percent",  text = L["Percent"] },
            { value = "time",     text = L["The remaining time"] },
        })
    end
    for _, row in ipairs({
        { type = "header", text = L["Visibility"] },
        dropdown(key, "visibility", L["Show the bar"], {
            { value = "always",    text = L["Always shown"] },
            { value = "combat",    text = L["In combat"] },
            { value = "noncombat", text = L["Out of combat"] },
            { value = "hidden",    text = L["Never"] },
        }, 220),
        opacity(key, "opacity", L["Opacity"], { min = 10 }),
        toggle(key, "oocFade", L["Fade out of combat"]),
        opacity(key, "oocAlpha", L["Faded opacity"], { min = 5 }),
    }) do rows[#rows + 1] = row end
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

-- The power the cast in progress will spend, shaded on the bar.
local function costRows(key)
    return {
        { type = "header", text = L["Spell cost"] },
        toggle(key, "showCost", L["Shade the cost of the current cast"],
            L["While you cast a spell with a cast time, the part of the bar it will spend is shaded."]),
        color(key, "costColor", L["Cost color"]),
        opacity(key, "costOpacity", L["Cost opacity"], { percent = true, step = 5 }),
    }
end

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
    for _, row in ipairs(costRows("power")) do power[#power + 1] = row end
    for _, row in ipairs(tickRows("power")) do power[#power + 1] = row end
    for _, row in ipairs(lookRows("power")) do power[#power + 1] = row end

    local mana = { enabledRow("mana"),
        { type = "toggle", label = L["Only while a form hides it"], subKey = "manaOnlyInForms",
          tooltip = L["The bar stays away while mana is your normal resource anyway."],
          get = function() return RB.Bar("mana").onlyInForms end,
          set = function(_, v) RB.Bar("mana").onlyInForms = v; apply() end },
    }
    for _, row in ipairs(costRows("mana")) do mana[#mana + 1] = row end
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

    page[#page + 1] = { type = "toggle", label = L["Hide the border"], subKey = "castHideBorder",
        tooltip = L["Hides the frame the client draws around its cast bar."],
        get = function() return RB.Bar("cast").hideBorder end,
        set = function(_, v) RB.Bar("cast").hideBorder = v; apply() end }

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

local function xpPage()
    local key = "xp"
    local client = RB.XP.IsClientStyle(RB.Bar(key))
    local rows = {
        enabledRow(key),
        { type = "dropdown", label = L["Where the bar sits"], width = 260, subKey = "xpStyle",
          values = {
              { value = "client", text = L["In the client's experience bar"] },
              { value = "own",    text = L["A bar of its own"] },
          },
          get = function() return RB.Bar(key).xpStyle end,
          set = function(_, v)
              RB.Bar(key).xpStyle = v
              apply()
              rebuild("xp")
          end },
    }
    local function add(list) for _, row in ipairs(list) do rows[#rows + 1] = row end end

    if client then
        add({ { type = "desc", text = L["|cffaaaaaaThe client's own bar keeps its place, its look and its colours -- blue while rested, purple otherwise. The quests, the rest, the texts and the info line are laid over it.|r"] } })
    else
        add({
            toggle(key, "showAtMaxLevel", L["Show at the highest level"],
                L["Once you reach the highest level the bar stays, full, instead of going away."]),
            toggle(key, "hideBlizzard", L["Hide the client's experience bar"],
                L["Only the experience bar itself is hidden; the reputation bar the client shows in its place keeps working."]),
            { type = "header", text = L["Colours"] },
            toggle(key, "useRestColor", L["Blue while rested"],
                L["The fill takes the rested colour while you have rested experience, exactly like the client's own bar."]),
            color(key, "fillColor", L["Normal color"]),
        })
    end

    add({
        { type = "header", text = L["After the fill"] },
        toggle(key, "showRested", L["Show rested experience"],
            L["The stretch of the bar that will earn double experience, in the rested colour."]),
        color(key, "restedFillColor", L["Rested color"]),
        toggle(key, "showQuest", L["Show finished quests"],
            L["The experience the quests ready to hand in will bring, right after the fill."]),
        color(key, "questColor", L["Finished quests color"]),
        toggle(key, "showIncomplete", L["Also show unfinished quests"]),
        color(key, "incompleteColor", L["Unfinished quests color"]),
        opacity(key, "overlayOpacity", L["Overlay opacity"], { min = 10 }),

        { type = "header", text = L["Texts on the bar"] },
        dropdown(key, "leftText", L["Left text"], {
            { value = "none",  text = L["Nothing"] },
            { value = "level", text = L["The level"] },
        }),
        dropdown(key, "centerText", L["Middle text"], {
            { value = "none",         text = L["Nothing"] },
            { value = "value",        text = L["The value"] },
            { value = "valuemax",     text = L["Value and maximum"] },
            { value = "valuemaxrest", text = L["Value, maximum and what is left"] },
            { value = "remaining",    text = L["What is left"] },
        }, 240),
        dropdown(key, "rightText", L["Right text"], {
            { value = "none",         text = L["Nothing"] },
            { value = "percent",      text = L["Percent"] },
            { value = "percentquest", text = L["Percent, with finished quests"] },
        }, 240),
    })
    -- Our own bar has these in its look rows further down.
    if client then
        add({
            slider(key, "fontSize", L["Text size"], 6, 24, 1),
            color(key, "textColor", L["Text color"]),
        })
    end

    add({
        { type = "header", text = L["Info line"] },
        dropdown(key, "infoAnchor", L["Info line position"], {
            { value = "auto",  text = L["Automatic"] },
            { value = "above", text = L["Above the bar"] },
            { value = "below", text = L["Below the bar"] },
        }),
        toggle(key, "showRate", L["Time to level and experience per hour"],
            L["Measured over this session. A /reload keeps the session, a new login starts one."]),
        toggle(key, "showQuestRested", L["Finished quests and rested, in percent"]),
        toggle(key, "showLevelTime", L["Time played on this level"],
            L["Asked from the client once per login; the chat message the client would print for it is held back."]),
        toggle(key, "showSessionTime", L["Time played this session"]),
        slider(key, "infoSize", L["Info text size"], 6, 24, 1),
    })
    if not client then
        add(tickRows(key))
        add(lookRows(key, true))
    end

    return {
        { type = "desc", text = L["|cffaaaaaaYour experience with what the client's bar leaves out: the rested stretch and the quests ready to hand in after the fill, the level and percent on the bar, and an info line with rate and time played.|r"] },
        section(key, rows),
        not client and { type = "button", label = L["Open Edit Mode"], onClick = function() ns:SetEditMode(true) end } or nil,
    }
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
    if RB.optionsOpen or not RB.mod.active then return end
    RB.optionsOpen = true
    if not hookedHide then
        hookedHide = true
        UI:OnMainFrameHide(function() RB.LeavePreview() end)
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
    if not RB.mod.active then return end
    RB.UpdateAll()
end

function mod:GetOptions(tabId)
    if tabId == "cast"  then return castPage() end
    if tabId == "swing" then return swingPage() end
    if tabId == "xp"    then return xpPage() end
    return resourcesPage()
end

-- The bars of the tab, pinned above it (Preview.lua).
function mod.BuildPageHeader(host, tabId)
    return RB.BuildPreviewHeader(host, tabId)
end
