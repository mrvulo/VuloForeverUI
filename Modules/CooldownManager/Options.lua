-- VuloForeverUI / Modules / CooldownManager / Options
--
-- One page per bar: pick the bar at the top, everything below belongs to it.
-- The spell list is a draggable row list, because the order on the page is
-- the order on the screen.
--
-- The "Spell" tab is the same idea one level down: pick a row, and every
-- setting there OVERRIDES the bar for that one row. An override that is nil
-- means "whatever the bar says", so every control on that tab has a third
-- position -- "from the bar" -- and that is the one it starts in.
local _, ns = ...
local L  = ns.L
local CM = ns.CM
local UI = ns.UI

local mod = CM.mod

mod.tabs = {
    { id = "spells",     label = "Spells" },
    { id = "spell",      label = "Per spell" },
    { id = "layout",     label = "Layout" },
    { id = "icons",      label = "Icons" },
    { id = "glow",       label = "Glow" },
    { id = "visibility", label = "Visibility" },
}

-- Which bar the page is editing, and which row of it. Not saved: they are a
-- place in the settings window, not a setting.
local selected, selectedRow

local function currentKey()
    local db = CM.db()
    CM.EnsureBars()
    if selected and db.bars[selected] then return selected end
    selected = db.barOrder[1]
    return selected
end

local function bar()
    return CM.Bar(currentKey())
end

local function apply()
    CM.RestyleAll()
    CM.UpdateVisibilityAll()
    -- The preview is not driven by the bars: with the module switched off
    -- there are no bars to drive it, and the page must still answer.
    CM.SetPreviewBar(currentKey())
end

-- Deferred on purpose. A dropdown's set() writes its label AFTER the call
-- returns; rebuilding the page inside set() hands that write to whatever
-- pooled widget the rebuild happened to hand out, and the bar selector ends
-- up showing a spell name.
local function rebuild(tabId)
    ns.NextFrame(function()
        UI:BuildOptionsPage("cooldownmanager", tabId)
    end)
end

-- ---------------------------------------------------------------- widgets --

local function toggle(label, key, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return bar()[key] end,
        set = function(_, v) bar()[key] = v; apply() end }
end

local function slider(label, key, min, max, step)
    return { type = "slider", label = label, min = min, max = max, step = step,
        get = function() return bar()[key] end,
        set = function(_, v) bar()[key] = v; apply() end }
end

local function color(label, key)
    return { type = "color", label = label,
        get = function() return bar()[key] end,
        set = function(r, g, b)
            local c = bar()[key]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

-- The bar chooser, repeated at the top of every tab so the page always says
-- which bar is being edited.
local function barSelector(tabId)
    local db = CM.db()
    local values = {}
    for _, key in ipairs(db.barOrder) do
        local b = db.bars[key]
        values[#values + 1] = { value = key, text = b.name }
    end
    values[#values + 1] = {
        value = "__add", text = L["Add a bar"], action = true,
        onClick = function()
            local key = CM.AddBar()
            if key then selected = key end
            rebuild(tabId)
        end,
    }
    return { type = "dropdown", label = L["Bar"], width = 240, values = values,
        get = function() return currentKey() end,
        set = function(_, v)
            if v ~= "__add" then selected = v; selectedRow = nil end
            CM.SetPreviewBar(selected)
            rebuild(tabId)
        end }
end

local function entryName(entry)
    if type(entry) ~= "table" then return "?" end
    local name
    if entry.kind == "item" then
        name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.id)
    else
        name = C_Spell.GetSpellName(entry.id)
    end
    if type(name) == "string" and name ~= "" then return name end
    return "#" .. tostring(entry.id)
end

-- ---------------------------------------------------------------- spells --

local function spellsPage()
    local key = currentKey()
    local b = bar()
    local list = CM.Spells(b)

    -- The rows: one per spell, in display order, draggable, each with a
    -- button that takes it off the bar.
    local values = {}
    for i, entry in ipairs(list) do
        values[#values + 1] = {
            value = entry.id,
            text = entryName(entry),
            draggable = true,
            buttons = {
                { icon = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\reset",
                  tooltip = L["Remove from this bar"],
                  onClick = function()
                      CM.RemoveSpell(key, i)
                      rebuild("spells")
                  end },
            },
        }
    end
    if #values == 0 then
        values[1] = { value = "__none", text = L["No spells on this bar yet"], separator = true }
    end

    -- What can still be added. A spell already placed shows where it sits;
    -- picking it moves it here.
    local addValues = {}
    for _, cand in ipairs(CM.Candidates()) do
        local on = CM.SpellBarName(cand.spellID)
        addValues[#addValues + 1] = {
            value = cand.spellID,
            text = on and ("%s  |cff777777(%s)|r"):format(cand.name, on) or cand.name,
        }
    end
    if #addValues == 0 then
        addValues[1] = { value = 0, text = L["The spellbook has nothing to add"], separator = true }
    end

    -- Copying between specialisations. The list belongs to the spec you are
    -- in, so this is how a second spec starts from the first instead of from
    -- nothing.
    local specValues, currentSpec = CM.SpecValues(b)

    return {
        barSelector("spells"),
        CM.PreviewItem(),
        { type = "editbox", label = L["Bar name"], width = 240,
          get = function() return bar().name end,
          set = function(_, v)
              if v and v ~= "" then bar().name = v; apply(); rebuild("spells") end
          end },
        { type = "spacer", height = 6 },

        { type = "header", text = L["Spells on this bar"] },
        { type = "desc", text = L["|cffaaaaaaDrag a row to change the order. The order here is the order on screen.|r"] },
        { type = "dropdown", label = L["Order"], width = 300, values = values,
          get = function() return nil end,
          set = function() end,
          reorder = function(from, to)
              CM.MoveSpell(key, from, to)
              rebuild("spells")
          end },

        { type = "dropdown", label = L["Add a spell"], width = 300, values = addValues,
          get = function() return nil end,
          set = function(_, v)
              if type(v) == "number" and v > 0 then
                  CM.AddSpell(key, v)
                  rebuild("spells")
              end
          end },
        { type = "editbox", label = L["Add an item by its id"], width = 240,
          tooltip = L["A trinket or a potion. The icon then shows how many you carry."],
          get = function() return "" end,
          set = function(_, v)
              local id = tonumber(v)
              if id then CM.AddSpell(key, id, "item"); rebuild("spells") end
          end },

        { type = "spacer", height = 8 },
        { type = "header", text = L["Specialisations"] },
        { type = "desc", text = L["|cffaaaaaaEach specialisation keeps its own rows. This copies another one's rows over the current list.|r"] },
        { type = "dropdown", label = L["Copy the rows of"], width = 240, values = specValues,
          get = function() return currentSpec end,
          set = function(_, v)
              if CM.CopySpec(bar(), v) then apply() end
              rebuild("spells")
          end },

        { type = "spacer", height = 8 },
        { type = "button", label = L["Remove this bar"],
          tooltip = L["The spells go back to the pool; nothing else is lost."],
          onClick = function()
              local db = CM.db()
              if #db.barOrder <= 1 then return end
              CM.RemoveBar(key)
              selected = nil
              rebuild("spells")
          end },
    }
end

-- ---------------------------------------------------------------- per spell --

local function rowList()
    return CM.Spells(bar())
end

local function entry()
    local list = rowList()
    if selectedRow and list[selectedRow] then return list[selectedRow] end
    selectedRow = (#list > 0) and 1 or nil
    return selectedRow and list[selectedRow] or nil
end

local function eApply()
    apply()
end

-- A setting with three positions: from the bar, on, off. nil is the first
-- one, which is why the values are strings and not booleans.
local function eTri(label, key, tooltip)
    return { type = "dropdown", label = label, width = 200, tooltip = tooltip,
        values = {
            { value = "", text = L["From the bar"] },
            { value = "1", text = L["Yes"] },
            { value = "0", text = L["No"] },
        },
        get = function()
            local e = entry()
            local v = e and e[key]
            if v == nil then return "" end
            return v and "1" or "0"
        end,
        set = function(_, v)
            local e = entry()
            if not e then return end
            if v == "" then e[key] = nil else e[key] = (v == "1") end
            eApply()
        end }
end

local function eSlider(label, key, min, max, step, fallbackKey)
    return { type = "slider", label = label, min = min, max = max, step = step,
        get = function()
            local e = entry()
            local v = e and e[key]
            if v ~= nil then return v end
            return bar()[fallbackKey or key] or min
        end,
        set = function(_, v)
            local e = entry()
            if not e then return end
            e[key] = v
            eApply()
        end }
end

local function eColor(label, key, default)
    return { type = "color", label = label,
        get = function()
            local e = entry()
            return (e and e[key]) or default
        end,
        set = function(r, g, b)
            local e = entry()
            if not e then return end
            e[key] = e[key] or {}
            e[key].r, e[key].g, e[key].b = r, g, b
            eApply()
        end }
end

local function soundValues()
    local values = { { value = "", text = L["No sound"] } }
    local seen = {}
    for _, name in ipairs(ns.BUNDLED_SOUNDS or {}) do
        seen[name] = true
        values[#values + 1] = { value = name, text = name }
    end
    local LSM = ns.LSM
    for _, name in ipairs((LSM and LSM:List("sound")) or {}) do
        if not seen[name] then values[#values + 1] = { value = name, text = name } end
    end
    return values
end

local function spellPage()
    local list = rowList()
    local rowValues = {}
    for i, e in ipairs(list) do
        rowValues[#rowValues + 1] = { value = i, text = entryName(e) }
    end
    if #rowValues == 0 then
        return {
            barSelector("spell"),
        CM.PreviewItem(),
            { type = "spacer", height = 6 },
            { type = "desc", text = L["This bar has no rows yet. Add one on the Spells tab first."] },
        }
    end
    entry()   -- settles selectedRow before the controls below read it

    return {
        barSelector("spell"),
        { type = "dropdown", label = L["Spell"], width = 240, values = rowValues,
          get = function() return selectedRow end,
          set = function(_, v) selectedRow = tonumber(v); rebuild("spell") end },
        { type = "desc", text = L["|cffaaaaaaEverything below belongs to this one row and overrides the bar. 'From the bar' hands the setting back.|r"] },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Swipe and countdown"] },
        eTri(L["Show the swipe"], "showSwipe"),
        eSlider(L["Swipe darkness"], "swipeAlpha", 0, 1, 0.01),
        eTri(L["Show the countdown"], "showCountdown"),
        eTri(L["Dim the icon"], "desaturateOnCooldown"),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Threshold"] },
        { type = "desc", text = L["|cffaaaaaaColours the countdown once it drops under this many seconds. Out of combat always; in combat only if the client answers the question, never with a guess.|r"] },
        { type = "slider", label = L["Threshold in seconds"], min = 0, max = 30, step = 0.5,
          get = function() local e = entry(); return (e and e.thresholdTime) or 0 end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.thresholdTime = (v > 0) and v or nil
              eApply()
          end },
        eColor(L["Threshold color"], "thresholdColor", { r = 1, g = 0.3, b = 0.3 }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Charges and sound"] },
        { type = "dropdown", label = L["Charges"], width = 220,
          values = {
              { value = "", text = L["From the bar"] },
              { value = "count", text = L["Show the number"] },
              { value = "none",  text = L["Show nothing"] },
          },
          get = function() local e = entry(); return (e and e.chargeMode) or "" end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.chargeMode = (v ~= "" and v) or nil
              eApply()
          end },
        { type = "dropdown", label = L["Sound when it is ready"], width = 220, values = soundValues(),
          get = function() local e = entry(); return (e and e.readySound) or "" end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.readySound = (v ~= "" and v) or nil
              local path = CM.SoundPath(v)
              if path then pcall(PlaySoundFile, path, "SFX") end
              eApply()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Glow"] },
        { type = "dropdown", label = L["Glow"], width = 200,
          values = {
              { value = "", text = L["From the bar"] },
              { value = "none",  text = L["No glow"] },
              { value = "pixel", text = L["A breathing border"] },
              { value = "shine", text = L["A turning star"] },
              { value = "proc",  text = L["The client's proc ring"] },
          },
          get = function() local e = entry(); return (e and e.glowType) or "" end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.glowType = (v ~= "" and v) or nil
              eApply()
          end },
        eColor(L["Glow color"], "glowColor", bar().glowColor),
        eTri(L["Glow when it is ready"], "readyGlow"),
        eTri(L["Glow on a proc"], "procGlow"),
        { type = "slider", label = L["Glow from this many stacks"], min = 0, max = 10, step = 1,
          get = function() local e = entry(); return (e and e.stackGlow) or 0 end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.stackGlow = (v > 0) and v or nil
              eApply()
          end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Active phase"] },
        { type = "desc", text = L["|cffaaaaaaWhile the buff of this spell is on you, the icon shows the buff running out instead of the cooldown coming back. Auras are closed to addons in combat on this client, so in a fight the icon falls back to the cooldown.|r"] },
        { type = "toggle", label = L["Show the active phase"],
          get = function() local e = entry(); return e and e.activePhase end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.activePhase = v or nil
              eApply()
          end },
        eColor(L["Active phase color"], "activeColor", { r = 0.2, g = 0.9, b = 0.4 }),
        { type = "toggle", label = L["Glow while it is active"],
          get = function() local e = entry(); return e and e.activeGlow end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.activeGlow = v or nil
              eApply()
          end },

        { type = "spacer", height = 8 },
        { type = "button", label = L["Hand every setting back to the bar"],
          onClick = function()
              local e = entry()
              if not e then return end
              local id, kind = e.id, e.kind
              wipe(e)
              e.id, e.kind = id, kind
              apply()
              rebuild("spell")
          end },
    }
end

-- ---------------------------------------------------------------- layout --

local function layoutPage()
    local db = CM.db()
    local key = currentKey()
    local overflowValues = { { value = "", text = L["Nowhere"] } }
    for _, other in ipairs(db.barOrder) do
        if other ~= key then
            overflowValues[#overflowValues + 1] = { value = other, text = db.bars[other].name }
        end
    end

    return {
        barSelector("layout"),
        CM.PreviewItem(),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Layout"] },
        slider(L["Icon size"], "iconSize", 16, 80, 1),
        slider(L["Spacing"], "spacing", -1, 20, 1),
        slider(L["Number of rows"], "rows", 1, 6, 1),
        { type = "dropdown", label = L["Grow"], width = 200,
          values = {
              { value = "CENTER", text = L["From the centre"] },
              { value = "RIGHT",  text = L["To the right"] },
              { value = "LEFT",   text = L["To the left"] },
          },
          get = function() return bar().grow end,
          set = function(_, v) bar().grow = v; apply() end },
        toggle(L["Stand the bar upright"], "vertical"),
        toggle(L["Split the rows"], "splitRows", L["Puts a gap between the rows, so a double row reads as two."]),
        slider(L["Gap between the rows"], "splitGap", 0, 40, 1),
        slider(L["Opacity"], "opacity", 0.1, 1, 0.01),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Size limits"] },
        { type = "desc", text = L["|cffaaaaaaA width limit shrinks the icons until the row fits, and stops at the smallest size rather than turning the bar into a line of dots.|r"] },
        slider(L["Largest width"], "maxWidth", 0, 1200, 10),
        slider(L["Smallest icon"], "minIconSize", 8, 60, 1),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Overflow"] },
        { type = "desc", text = L["|cffaaaaaaEverything past the limit is handed to another bar, which keeps a long list one readable row.|r"] },
        slider(L["Most icons on this bar"], "maxIcons", 0, 24, 1),
        { type = "dropdown", label = L["Hand the rest to"], width = 220, values = overflowValues,
          get = function() return bar().overflowInto or "" end,
          set = function(_, v) bar().overflowInto = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Anchor"] },
        { type = "dropdown", label = L["Hang the bar off"], width = 220, values = CM.AnchorValues(),
          get = function() return bar().anchorTo or "screen" end,
          set = function(_, v) bar().anchorTo = v; apply() end },
        { type = "desc", text = L["|cffaaaaaaAnything but the screen follows that frame, and a bar on the cursor follows the mouse. Drag it as usual; the drop is kept as an offset from whatever it hangs off.|r"] },
        { type = "spacer", height = 6 },
        { type = "desc", text = L["|cffaaaaaaMove the bar with /vedit, like every other frame in the suite.|r"] },
        { type = "button", label = L["Open Edit Mode"], onClick = function()
            ns:SetEditMode(true)
        end },
    }
end

-- ---------------------------------------------------------------- icons --

local function iconsPage()
    return {
        barSelector("icons"),
        CM.PreviewItem(),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Icon"] },
        slider(L["Icon zoom"], "iconZoom", 0, 0.2, 0.01),
        { type = "dropdown", label = L["Icon shape"], width = 200,
          values = {
              { value = "square",  text = L["Square"] },
              { value = "rounded", text = L["Rounded"] },
              { value = "circle",  text = L["Round"] },
              { value = "hexagon", text = L["Six sided"] },
          },
          get = function() return bar().iconShape or "square" end,
          set = function(_, v) bar().iconShape = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Border"] },
        { type = "dropdown", label = L["Border texture"], width = 220,
          values = (function()
              local v = { { value = "", text = L["Flat edges"] } }
              for _, e in ipairs(ns.MediaBorderValues()) do v[#v + 1] = e end
              return v
          end)(),
          tooltip = L["A shaped icon brings its own border; this one is for the square shape."],
          get = function() return bar().borderTexture or "" end,
          set = function(_, v) bar().borderTexture = v; apply() end },
        slider(L["Border size"], "borderSize", 0, 4, 1),
        slider(L["Border offset"], "borderInset", 0, 10, 1),
        toggle(L["Class color for the border"], "borderClassColor"),
        color(L["Border color"], "borderColor"),
        color(L["Background color"], "bgColor"),

        { type = "spacer", height = 6 },
        { type = "header", text = L["While the spell is on cooldown"] },
        toggle(L["Show the swipe"], "showSwipe"),
        slider(L["Swipe darkness"], "swipeAlpha", 0, 1, 0.01),
        { type = "toggle", label = L["Dim the icon"],
          tooltip = L["The client dims it, so it also works while you are in combat."],
          get = function() return bar().desaturateOnCooldown end,
          set = function(_, v) bar().desaturateOnCooldown = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Text"] },
        toggle(L["Show the countdown"], "showCountdown"),
        slider(L["Countdown size"], "countdownSize", 8, 24, 1),
        color(L["Countdown color"], "countdownColor"),
        toggle(L["Show charges"], "showCharges"),
        slider(L["Charge text size"], "chargeSize", 8, 20, 1),
        { type = "toggle", label = L["Show the key"],
          tooltip = L["The key that casts it, taken from your action bars."],
          get = function() return bar().showKeybind end,
          set = function(_, v) bar().showKeybind = v; apply() end },
        slider(L["Key text size"], "keybindSize", 6, 20, 1),
        color(L["Key color"], "keybindColor"),
        { type = "toggle", label = L["Show the count"],
          tooltip = L["How many of an item you carry, and how many stacks a watched buff has."],
          get = function() return bar().showCount end,
          set = function(_, v) bar().showCount = v; apply() end },
        slider(L["Count text size"], "countSize", 6, 20, 1),
        color(L["Count color"], "countColor"),
    }
end

-- ---------------------------------------------------------------- glow --

local function glowPage()
    return {
        barSelector("glow"),
        CM.PreviewItem(),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Glow"] },
        { type = "dropdown", label = L["Kind of glow"], width = 220,
          values = {
              { value = "none",  text = L["No glow"] },
              { value = "pixel", text = L["A breathing border"] },
              { value = "shine", text = L["A turning star"] },
              { value = "proc",  text = L["The client's proc ring"] },
          },
          get = function() return bar().glowType or "pixel" end,
          set = function(_, v) bar().glowType = v; apply() end },
        color(L["Glow color"], "glowColor"),
        toggle(L["Glow when it is ready"], "readyGlow"),
        toggle(L["Glow on a proc"], "procGlow",
            L["The client says which spell lit up. In a fight it sometimes says it secretly, and a proc we cannot place is left alone rather than guessed at."]),
        slider(L["Glow from this many stacks"], "stackGlow", 0, 10, 1),
        { type = "desc", text = L["|cffaaaaaaStacks are readable only while auras are open to addons, which in a fight they are not. The glow then waits rather than flickering.|r"] },
    }
end

-- ---------------------------------------------------------------- visible --

-- The extra conditions, written out here rather than built from CM.CONDS: the
-- locale check reads literals, and a label assembled from a variable would go
-- untranslated in every language.
--
-- Built inside a function, never at file scope: the saved language override
-- only exists from ADDON_LOADED, and a table filled while the file loads
-- would hold the wrong language for the whole session.
local function condLabels()
    return {
        instance = L["In an instance"],
        raid     = L["In a raid"],
        group    = L["In a group"],
        solo     = L["On your own"],
        mounted  = L["Mounted"],
        target   = L["With a target"],
        notarget = L["Without a target"],
        resting  = L["Resting"],
    }
end

local function condRow(cond, labels)
    return { type = "toggle", label = labels[cond.key] or cond.key,
        get = function()
            local c = bar().conds
            return type(c) == "table" and c[cond.key] or false
        end,
        set = function(_, v)
            local b = bar()
            if type(b.conds) ~= "table" then b.conds = {} end
            b.conds[cond.key] = v or nil
            apply()
        end }
end

local function visibilityPage()
    local page = {
        barSelector("visibility"),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Visibility"] },
        { type = "toggle", label = L["Bar enabled"],
          get = function() return bar().enabled end,
          set = function(_, v) bar().enabled = v; apply() end },
        { type = "dropdown", label = L["Show the bar"], width = 220,
          values = {
              { value = "always",    text = L["Always shown"] },
              { value = "combat",    text = L["In combat"] },
              { value = "noncombat", text = L["Out of combat"] },
              { value = "hidden",    text = L["Never"] },
          },
          get = function() return bar().visibility end,
          set = function(_, v) bar().visibility = v; apply() end },
        toggle(L["Fade out of combat"], "oocFade"),
        slider(L["Faded opacity"], "oocAlpha", 0.05, 1, 0.01),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Only under these conditions"] },
        { type = "desc", text = L["|cffaaaaaaPick as many as you like. Every one you pick has to hold, so nothing picked means the bar always follows the rule above.|r"] },
    }
    local labels = condLabels()
    for _, cond in ipairs(CM.CONDS) do
        page[#page + 1] = condRow(cond, labels)
    end
    return page
end

-- ---------------------------------------------------------------- preview --

-- While the page is open every bar stays visible, whatever its rules say.
local hooked = false

-- Bound to the page being SHOWN, never to GetOptions: the settings search
-- calls GetOptions for every module and tab on every keystroke, and doing
-- this there put hidden bars on screen while someone typed.
-- The settings window is built on first use, so at login there is nothing to
-- hook. The window's own close hook is therefore laid here, the first time the
-- page is shown -- laying it at login silently did nothing, and the preview
-- could be entered but never left.
local hookedHide = false

local function enterPreview()
    if CM.optionsOpen then return end
    CM.optionsOpen = true
    if not hookedHide then
        local f = UI.mainFrame
        if f then
            hookedHide = true
            f:HookScript("OnHide", function() CM.LeavePreview() end)
        end
    end
    -- Restyle, not just show: the bars grow by their stand-in icons.
    CM.RestyleAll()
    CM.UpdateVisibilityAll()
end

-- The hook is laid from OnEnable. It used to be laid INSIDE enterPreview,
-- which meant the only thing that could call enterPreview was a hook that
-- nothing had installed yet: the on-screen preview never ran once.
function CM.HookPreview()
    if hooked then return end
    hooked = true
    hooksecurefunc(UI, "ShowModulePage", function(_, key)
        if key == "cooldownmanager" then
            enterPreview()
        elseif CM.optionsOpen then
            CM.LeavePreview()
        end
    end)
end

function CM.LeavePreview()
    if not CM.optionsOpen then return end
    CM.optionsOpen = false
    CM.RestyleAll()
    CM.UpdateVisibilityAll()
end

function mod:GetOptions(tabId)
    CM.EnsureBars()
    if tabId == "spell"      then return spellPage() end
    if tabId == "layout"     then return layoutPage() end
    if tabId == "icons"      then return iconsPage() end
    if tabId == "glow"       then return glowPage() end
    if tabId == "visibility" then return visibilityPage() end
    return spellsPage()
end
