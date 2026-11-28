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

-- One page per bar with everything on it, one level down per spell, and the
-- bar glows (a buff lights a spell up). The id "spells" is kept for the first
-- tab: other modules jump to it.
mod.tabs = {
    { id = "spells", label = "Cooldown bars" },
    { id = "spell",  label = "Per spell" },
    { id = "glows",  label = "Bar glows" },
}

-- Which bar the page is editing, and which row of it. Not saved: they are a
-- place in the settings window, not a setting.
local selected, selectedRow

-- The fallback is RETURNED, never written back.
--
-- It used to assign, and that was a trap with a long fuse. The options builder
-- runs every row's getter once per page build against the module's DEFAULTS,
-- to find out which settings differ from them -- and the defaults carry only
-- the three starter bars. A getter that writes during that pass writes while
-- the db underneath it is the default one, and the write survives the restore.
-- So selecting a bar you had added landed on "cooldowns" one frame later, on
-- every page build, and a bar added past the first three could not be reached
-- at all.
local function currentKey()
    local db = CM.db()
    CM.EnsureBars()
    if selected and db.bars[selected] then return selected end
    return db.barOrder[1]
end

local function bar()
    return CM.Bar(currentKey())
end

-- Opens this page on the first buff bar (seed TrackedBuff), from another
-- module's page. Without one the page opens on its first bar, where "Add a
-- buff bar" is.
function CM.ShowBuffsBar()
    local db = CM.db()
    CM.EnsureBars()
    for _, key in ipairs(db.barOrder) do
        local b = db.bars[key]
        if b and b.seed == "TrackedBuff" then selected, selectedRow = key, nil; break end
    end
    local UI = ns.UI
    UI:ShowModulePage("cooldownmanager")
    if UI.currentTab ~= "spells" then UI:ShowTab("spells") end
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

-- The same redraw, for the parts of the module that change a bar from OUTSIDE
-- the options page: the plus menu and the drag-and-drop in the live preview.
-- The tab on screen is the one rebuilt, as long as it is one of ours.
function CM.RebuildOptions(tabId)
    local cur = UI.currentTab
    for _, t in ipairs(mod.tabs) do
        if t.id == cur then rebuild(cur); return end
    end
    rebuild(tabId or "spells")
end

-- ---------------------------------------------------------------- widgets --

local rows = ns.OptionRows(bar, apply)
local toggle, slider, color, opacity = rows.toggle, rows.slider, rows.color, rows.opacity

-- The kinds a new bar can be started as. Same three the client's own cooldown
-- viewer keeps, and the same three a fresh profile starts with -- a bar added
-- here is the bar that was there from the beginning, not a lesser one.
-- Built per call, not memoised: a memo of resolved locale strings outlives a
-- language change, and the table next to this one is rebuilt for the same
-- reason. One table per page build is not worth a stale label.
--
-- The NAMES are the raw English the starter bars use, not locale lookups. A
-- bar's name is display text the user edits, and a translated new bar beside
-- three untranslated old ones reads as a mistake.
local function newBarKinds()
    return {
        { seed = "Essential",   name = "Cooldowns", label = L["Add a cooldown bar"] },
        { seed = "Utility",     name = "Utility",   label = L["Add a utility bar"] },
        { seed = "TrackedBuff", name = "Buffs",     label = L["Add a buff bar"] },
    }
end

-- A name nothing else on the list is already using. Two bars called
-- "Cooldowns" address the right bar everywhere -- the dropdown's value is the
-- key -- but everything that SHOWS a name goes ambiguous, including the
-- "already on <bar>" hint when adding a spell.
local function freeName(db, wanted)
    local taken = {}
    for _, key in ipairs(db.barOrder) do
        local b = db.bars[key]
        if b and type(b.name) == "string" then taken[b.name] = true end
    end
    if not taken[wanted] then return wanted end
    for n = 2, CM.MAX_BARS + 1 do
        local try = wanted .. " " .. n
        if not taken[try] then return try end
    end
    return wanted
end

-- The bar chooser, repeated at the top of every tab so the page always says
-- which bar is being edited.
--
-- No label and centred: the row is not one setting among others, it is the
-- question "which bar is this page about", and the page underneath it changes
-- completely with the answer. A label to its left would file it next to the
-- sliders as if it were one of them.
local function barSelector(tabId)
    local db = CM.db()
    local values = {}
    for _, key in ipairs(db.barOrder) do
        local b = db.bars[key]
        values[#values + 1] = { value = key, text = b.name }
    end

    -- The room left, asked once: with the list full, the three add rows would
    -- be three rows that answer "no". Better not to offer them.
    if #db.barOrder < CM.MAX_BARS then
        values[#values + 1] = { value = nil, text = " ", separator = true }
        for _, kind in ipairs(newBarKinds()) do
            local k = kind
            values[#values + 1] = {
                -- The plus sits in the code, not in the locale: it is the
                -- affordance, the same in every language, and nine translators
                -- should not each have to remember to type it.
                value = "__add_" .. k.seed, text = "+ " .. k.label, action = true,
                onClick = function()
                    local key = CM.AddBar(freeName(db, k.name), k.seed)
                    if key then selected = key; selectedRow = nil end
                    CM.SetPreviewBar(selected)
                    rebuild(tabId)
                end,
            }
        end
    end

    return { type = "group", layout = "row", align = "center", items = {
        -- Not a setting, so it has no default to differ from: without this the
        -- builder marks it "changed" and offers a reset dot for "which bar the
        -- page is showing".
        { type = "dropdown", width = 320, values = values, noDefaultMark = true,
          get = function() return currentKey() end,
          set = function(_, v)
              selected = v; selectedRow = nil
              CM.SetPreviewBar(selected)
              rebuild(tabId)
          end },
    } }
end

local function entryName(entry)
    if type(entry) ~= "table" then return "?" end
    if entry.kind == "preset" then
        local p = CM.PRESETS[entry.id]
        if p and p.key == "healthstone" then return L["Healthstone (best in your bags)"] end
        if p and p.key == "soulstone" then return L["Soulstone (best in your bags)"] end
        return "?"
    end
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

-- The head of the bar page: its name. The spells themselves are edited in
-- the live bar above every tab -- a drag orders them, the plus adds one, a
-- click opens a row's menu.
local function barHead()
    return {
        { type = "editbox", label = L["Bar name"], width = 240,
          get = function() return bar().name end,
          set = function(_, v)
              if v and v ~= "" then bar().name = v; apply(); rebuild("spells") end
          end },
        { type = "desc", text = L["|cffaaaaaaThe bar above is the bar on screen: drag an icon to move it, click it for its own settings, the plus adds spells, items, slots and your own ids.|r"] },
    }
end

-- The foot: copying between specialisations and taking the bar away.
local function barExtras()
    local key = currentKey()
    -- The list belongs to the spec you are in, so this is how a second spec
    -- starts from the first instead of from nothing.
    local specValues, currentSpec = CM.SpecValues(bar())
    return {
        { type = "spacer", height = 6 },
        { type = "header", text = L["Extras"] },
        { type = "desc", text = L["|cffaaaaaaEach specialisation keeps its own rows. This copies another one's rows over the current list.|r"] },
        { type = "dropdown", label = L["Copy the rows of"], width = 240, values = specValues,
          get = function() return currentSpec end,
          set = function(_, v)
              if CM.CopySpec(bar(), v) then apply() end
              rebuild("spells")
          end },
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

-- The per-spell opacity, in per cent like the bar's own row; saved 0..1.
local function eOpacity(label, key)
    return { type = "slider", label = label, min = 0, max = 100, step = 1, suffix = "%",
        get = function()
            local e = entry()
            local v = e and e[key]
            if v == nil then v = bar()[key] or 0 end
            return v * 100
        end,
        set = function(_, v)
            local e = entry()
            if not e then return end
            e[key] = v / 100
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
    return ns.MediaSoundValues(L["No sound"])
end

-- The kinds of swipe; `inherit` puts "from the bar" first.
local function swipeValues(inherit)
    local out = {}
    if inherit then out[1] = { value = "", text = L["From the bar"] } end
    out[#out + 1] = { value = "dark",  text = L["Dark"] }
    out[#out + 1] = { value = "light", text = L["Bright"] }
    out[#out + 1] = { value = "edge",  text = L["Only the edge"] }
    return out
end

-- A watched buff row while its buff is not on you.
local function inactiveValues(inherit)
    local out = {}
    if inherit then out[1] = { value = "", text = L["From the bar"] } end
    out[#out + 1] = { value = "show", text = L["Show as it is"] }
    out[#out + 1] = { value = "dim",  text = L["Grey and faint"] }
    out[#out + 1] = { value = "hide", text = L["Hide"] }
    return out
end

-- The picture of a row: a file id or a path, typed into a popup. Empty
-- hands the row its own icon back.
local iconRow
ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_CM_ICON"] = {
        text = L["Icon id or texture path (empty: the spell's own):"],
        button1 = _G.OKAY or _G.ACCEPT or L["Save"], button2 = _G.CANCEL,
        hasEditBox = true, maxLetters = 200,
        OnShow = function(self)
            local box = ns.PopupEditBox(self)
            if box then
                box:SetText(iconRow and iconRow.icon and tostring(iconRow.icon) or "")
                box:SetFocus()
            end
        end,
        OnAccept = function(self)
            local box = ns.PopupEditBox(self)
            if box and CM.SetRowIcon then CM.SetRowIcon(iconRow, box:GetText()) end
        end,
        EditBoxOnEnterPressed = function(self)
            if CM.SetRowIcon then CM.SetRowIcon(iconRow, self:GetText()) end
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end)

local function askIcon(e)
    iconRow = e
    StaticPopup_Show("VFUI_CM_ICON")
end

function CM.SetRowIcon(e, text)
    if not e then return end
    text = strtrim(text or "")
    if text == "" then e.icon = nil else e.icon = tonumber(text) or text end
    apply()
end

local function spellPage()
    local list = rowList()
    local rowValues = {}
    for i, e in ipairs(list) do
        rowValues[#rowValues + 1] = { value = i, text = entryName(e) }
    end
    if #rowValues == 0 then
        return {
            { type = "spacer", height = 6 },
            { type = "desc", text = L["This bar has no rows yet. Add one on the Spells tab first."] },
        }
    end
    entry()   -- settles selectedRow before the controls below read it

    return {
        { type = "dropdown", label = L["Spell"], width = 240, values = rowValues,
          get = function() return selectedRow end,
          set = function(_, v) selectedRow = tonumber(v); rebuild("spell") end },
        { type = "desc", text = L["|cffaaaaaaEverything below belongs to this one row and overrides the bar. 'From the bar' hands the setting back.|r"] },
        { type = "button", label = L["Own icon..."], onClick = function() askIcon(entry()) end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Swipe and countdown"] },
        eTri(L["Show the swipe"], "showSwipe"),
        eOpacity(L["Swipe darkness"], "swipeAlpha"),
        { type = "dropdown", label = L["Kind of swipe"], width = 200,
          values = swipeValues(true),
          get = function() local e = entry(); return (e and e.swipeStyle) or "" end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.swipeStyle = (v ~= "" and v) or nil
              eApply()
          end },
        eTri(L["Hide the global cooldown"], "ignoreGCD"),
        eTri(L["Show the countdown"], "showCountdown"),
        eTri(L["Dim the icon"], "desaturateOnCooldown"),
        eTri(L["Hide while on cooldown"], "cdHide"),
        eTri(L["Only while castable"], "castableOnly", L["Shows the icon only while the spell can be cast right now: usable, off cooldown and with enough power. Its place on the bar stays free. Spells only, also ones added by id."]),

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
        eTri(L["Hide the charges at zero"], "hideZeroCharges"),
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
          values = CM.Glow.Values(true),
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
        eTri(L["Glow at full charges"], "chargeGlow"),
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
        { type = "desc", text = L["|cffaaaaaaWhile the buff of this spell is on you, the icon shows the buff: its icon, a reverse swipe, the time left and its stacks, in combat too. Then the cooldown again.|r"] },
        eTri(L["Show the active phase"], "activePhase"),
        { type = "dropdown", label = L["Without the buff"], width = 200, values = inactiveValues(true),
          get = function() local e = entry(); return (e and e.inactive) or "" end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.inactive = (v ~= "" and v) or nil
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

        { type = "spacer", height = 6 },
        { type = "header", text = L["Dot on the target"] },
        { type = "desc", text = L["|cffaaaaaaShows how long this spell's damage over time still runs on your target, in the middle of the icon. The number turns green once casting it again no longer cuts off ticks: the cast time plus the lead below. The client draws it, so it works in combat too. The cooldown number of this row gives way to it; the swipe stays.|r"] },
        { type = "toggle", label = L["Show the time left on the target"],
          get = function() local e = entry(); return e and e.antiClip end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.antiClip = v or nil
              eApply()
          end },
        { type = "slider", label = L["Lead in seconds"], min = 0, max = 3, step = 0.1,
          tooltip = L["How much earlier than the cast time the number turns green: the global cooldown and your reaction."],
          get = function() local e = entry(); return (e and e.antiClipLead) or CM.AntiClip.DEFAULT_LEAD end,
          set = function(_, v)
              local e = entry()
              if not e then return end
              e.antiClipLead = v
              eApply()
          end },
        eColor(L["Recast color"], "antiClipColor", CM.AntiClip.DEFAULT_COLOR),

        { type = "spacer", height = 8 },
        { type = "button", label = L["Hand every setting back to the bar"],
          onClick = function()
              local e = entry()
              if not e then return end
              -- Talent conditions, the own icon and the bar glows are not bar
              -- settings; they stay.
              local id, kind, talents, icon, glows = e.id, e.kind, e.talents, e.icon, e.glowBuffs
              wipe(e)
              e.id, e.kind, e.talents, e.icon, e.glowBuffs = id, kind, talents, icon, glows
              apply()
              rebuild("spell")
          end },
    }
end

-- ---------------------------------------------------------------- layout --

-- ---------------------------------------------------------------- row menu --
--
-- The same per-row settings as the tab above, one left-click away on an icon
-- of the live preview. Every choice writes the override on the entry and
-- nothing else, so the tab and the menu can never disagree: both read CM.Val's
-- nil-means-the-bar rule. The menu stays open on a choice, so a setting can be
-- tried and changed back without reopening it.

-- The page is only rebuilt when it shows per-row controls; any other tab
-- would be torn down and put back for nothing.
local function menuApply()
    apply()
    if UI.currentTab == "spell" or UI.currentTab == "glows" then rebuild(UI.currentTab) end
end

-- From the bar / Yes / No, as a flyout of three dots.
local function menuTri(e, label, key)
    local function pick(v) return function() e[key] = v; menuApply() end end
    local function is(v) return function() return e[key] == v end end
    return { text = label, submenu = {
        { text = L["From the bar"], radio = true, keepOpen = true, checked = is(nil),   func = pick(nil) },
        { text = L["Yes"],          radio = true, keepOpen = true, checked = is(true),  func = pick(true) },
        { text = L["No"],           radio = true, keepOpen = true, checked = is(false), func = pick(false) },
    } }
end

-- The same three choices as rows of a flyout, under a title: a flyout cannot
-- open a flyout of its own.
local function triRows(e, label, key)
    local function pick(v) return function() e[key] = v; menuApply() end end
    local function is(v) return function() return e[key] == v end end
    return {
        { text = label, title = true },
        { text = L["From the bar"], radio = true, keepOpen = true, checked = is(nil),   func = pick(nil) },
        { text = L["Yes"],          radio = true, keepOpen = true, checked = is(true),  func = pick(true) },
        { text = L["No"],           radio = true, keepOpen = true, checked = is(false), func = pick(false) },
    }
end

-- A flyout of fixed values for a key; `none` is the value that means "off"
-- and is stored as nil.
local function menuPick(e, label, key, values, none)
    local sub = {}
    for _, v in ipairs(values) do
        sub[#sub + 1] = { text = v.text, radio = true, keepOpen = true,
            checked = function() return (e[key] or none) == v.value end,
            func = function()
                if v.value == none then e[key] = nil else e[key] = v.value end
                menuApply()
            end }
    end
    return { text = label, submenu = sub }
end

local function menuColor(e, label, key, default)
    return { text = label, func = function()
        local c = e[key] or default
        local old = e[key] and { r = c.r, g = c.g, b = c.b } or nil
        ns:ShowColorPicker({ r = c.r, g = c.g, b = c.b,
            onChange = function(r, g, b)
                e[key] = e[key] or {}
                e[key].r, e[key].g, e[key].b = r, g, b
                apply()
            end,
            onCancel = function()
                e[key] = old
                apply()
            end })
    end }
end

local function menuToggle(e, label, key)
    return { text = label, keepOpen = true,
        checked = function() return e[key] == true end,
        func = function() e[key] = (not e[key]) or nil; menuApply() end }
end

-- The talent conditions of one row: its own menu, on a right-click in the
-- preview and from the row menu, because the trees need both menu levels.
function CM.TalentMenu(barKey, index)
    local b = CM.Bar(barKey)
    local list = b and CM.Spells(b)
    local e = list and list[index]
    if not e then return nil end
    local menu = CM.Talents.Menu(e, function()
        CM.RestyleAll()
        CM.RefreshPreview()
        if UI.currentTab == "spell" then rebuild("spell") end
    end)
    menu[1].text = ("%s: %s"):format(entryName(e), L["Talent conditions"])
    return menu
end

function CM.RowMenu(barKey, index)
    local b = CM.Bar(barKey)
    local list = b and CM.Spells(b)
    local e = list and list[index]
    if not e then return nil end

    local secs = { { value = 0, text = L["Off"] } }
    for _, s in ipairs({ 2, 3, 5, 10, 15, 30 }) do
        secs[#secs + 1] = { value = s, text = string.format(L["%d seconds"], s) }
    end
    local stacks = { { value = 0, text = L["Off"] } }
    for s = 1, 10 do stacks[#stacks + 1] = { value = s, text = tostring(s) } end
    -- The sound plays on the pick, as it does on the tab.
    local soundItem = menuPick(e, L["Sound when it is ready"], "readySound", soundValues(), "")
    for _, item in ipairs(soundItem.submenu) do
        local pick = item.func
        item.func = function()
            pick()
            local path = CM.SoundPath(e.readySound)
            if path then pcall(PlaySoundFile, path, "SFX") end
        end
    end

    -- The colours ride at the foot of the flyout they belong to: the root
    -- menu windows itself past 18 rows, and a menu that scrolls hides half of
    -- what it offers.
    local threshold = menuPick(e, L["Threshold in seconds"], "thresholdTime", secs, 0)
    threshold.submenu[#threshold.submenu + 1] = { separator = true }
    threshold.submenu[#threshold.submenu + 1] =
        menuColor(e, L["Threshold color"], "thresholdColor", { r = 1, g = 0.3, b = 0.3 })
    threshold.submenu[#threshold.submenu + 1] = { separator = true }
    for _, r in ipairs(triRows(e, L["Show the countdown"], "showCountdown")) do threshold.submenu[#threshold.submenu + 1] = r end

    local glow = menuPick(e, L["Glow"], "glowType", CM.Glow.Values(true), "")
    glow.submenu[#glow.submenu + 1] = { separator = true }
    glow.submenu[#glow.submenu + 1] = menuColor(e, L["Glow color"], "glowColor", b.glowColor)

    -- The root is at the 18 rows a menu shows without scrolling, so two
    -- yes/no settings ride in flyouts as a title plus their three choices.
    local dimHide = { text = L["Dim and hide"], submenu = {} }
    for _, r in ipairs(triRows(e, L["Dim the icon"], "desaturateOnCooldown")) do dimHide.submenu[#dimHide.submenu + 1] = r end
    dimHide.submenu[#dimHide.submenu + 1] = { separator = true }
    for _, r in ipairs(triRows(e, L["Only while castable"], "castableOnly")) do dimHide.submenu[#dimHide.submenu + 1] = r end
    dimHide.submenu[#dimHide.submenu + 1] = { separator = true }
    for _, r in ipairs(triRows(e, L["Hide while on cooldown"], "cdHide")) do dimHide.submenu[#dimHide.submenu + 1] = r end

    -- Swipe, its kind and the global cooldown: one flyout of 15 rows, so the
    -- root stays at the 18 rows a menu shows unscrolled (a flyout windows
    -- itself at 18 as well; the number rides with the threshold).
    local swipe = { text = L["Swipe and global cooldown"], submenu = {} }
    local function into(list) for _, r in ipairs(list) do swipe.submenu[#swipe.submenu + 1] = r end end
    into(triRows(e, L["Show the swipe"], "showSwipe"))
    swipe.submenu[#swipe.submenu + 1] = { separator = true }
    swipe.submenu[#swipe.submenu + 1] = { text = L["Kind of swipe"], title = true }
    into(menuPick(e, L["Kind of swipe"], "swipeStyle", swipeValues(true), "").submenu)
    swipe.submenu[#swipe.submenu + 1] = { separator = true }
    into(triRows(e, L["Hide the global cooldown"], "ignoreGCD"))

    local charges = menuPick(e, L["Charges"], "chargeMode", {
        { value = "",      text = L["From the bar"] },
        { value = "count", text = L["Show the number"] },
        { value = "none",  text = L["Show nothing"] },
    }, "")
    charges.submenu[#charges.submenu + 1] = { separator = true }
    for _, r in ipairs(triRows(e, L["Glow at full charges"], "chargeGlow")) do charges.submenu[#charges.submenu + 1] = r end
    charges.submenu[#charges.submenu + 1] = { separator = true }
    for _, r in ipairs(triRows(e, L["Hide the charges at zero"], "hideZeroCharges")) do charges.submenu[#charges.submenu + 1] = r end

    local active = { text = L["Active phase"], submenu = triRows(e, L["Show the active phase"], "activePhase") }
    for _, r in ipairs({
        { separator = true },
        menuToggle(e, L["Glow while it is active"], "activeGlow"),
        menuColor(e, L["Active phase color"], "activeColor", { r = 0.2, g = 0.9, b = 0.4 }),
        { separator = true },
        { text = L["Without the buff"], title = true },
    }) do active.submenu[#active.submenu + 1] = r end
    for _, r in ipairs(menuPick(e, L["Without the buff"], "inactive", inactiveValues(true), "").submenu) do
        active.submenu[#active.submenu + 1] = r
    end

    return {
        { text = entryName(e), title = true },
        { text = L["Remove from this bar"], func = function()
            CM.RemoveSpell(barKey, index)
            CM.RefreshPreview()
            rebuild(UI.currentTab or "spells")
        end },
        { separator = true },
        swipe,
        dimHide,
        threshold,
        charges,
        soundItem,
        glow,
        menuTri(e, L["Glow when it is ready"], "readyGlow"),
        menuTri(e, L["Glow on a proc"], "procGlow"),
        menuPick(e, L["Glow from this many stacks"], "stackGlow", stacks, 0),
        { text = CM.Talents.Count(e) > 0
                and ("%s  |cff777777(%d)|r"):format(L["Talent conditions"], CM.Talents.Count(e))
                or L["Talent conditions"],
          func = function()
            local menu = CM.TalentMenu(barKey, index)
            if menu then ns:ShowPopupMenu(menu, "cursor") end
        end },
        active,
        { text = e.icon and ("%s  |cff777777(%s)|r"):format(L["Own icon..."], L["set"]) or L["Own icon..."],
          func = function() askIcon(e) end },
        { separator = true },
        { text = L["All settings for this spell..."], func = function()
            selected, selectedRow = barKey, index
            rebuild("spell")
        end },
        { text = L["Hand every setting back to the bar"], func = function()
            -- Talent conditions, the own icon and the bar glows stay.
            local id, kind, talents, icon, glows = e.id, e.kind, e.talents, e.icon, e.glowBuffs
            wipe(e)
            e.id, e.kind, e.talents, e.icon, e.glowBuffs = id, kind, talents, icon, glows
            menuApply()
        end },
    }
end

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
        { type = "spacer", height = 6 },
        { type = "header", text = L["Layout"] },
        slider("iconSize", L["Icon size"], 16, 80, 1),
        slider("spacing", L["Spacing"], -1, 20, 1),
        slider("rows", L["Number of rows"], 1, 6, 1),
        { type = "dropdown", label = L["Grow"], width = 200,
          values = {
              { value = "CENTER", text = L["From the centre"] },
              { value = "RIGHT",  text = L["To the right"] },
              { value = "LEFT",   text = L["To the left"] },
          },
          get = function() return bar().grow end,
          set = function(_, v) bar().grow = v; apply() end },
        toggle("vertical", L["Stand the bar upright"]),
        toggle("splitRows", L["Split the rows"], L["Puts a gap between the rows, so a double row reads as two."]),
        slider("splitGap", L["Gap between the rows"], 0, 40, 1),
        opacity("opacity", L["Opacity"], { min = 10 }),
        toggle("barBg", L["Plate behind the bar"], L["A plate behind the whole bar."]),
        color("barBgColor", L["Background of the bar"], { hasAlpha = true }),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Size limits"] },
        { type = "desc", text = L["|cffaaaaaaA width limit shrinks the icons until the row fits, and stops at the smallest size rather than turning the bar into a line of dots.|r"] },
        slider("maxWidth", L["Largest width"], 0, 1200, 10),
        slider("minIconSize", L["Smallest icon"], 8, 60, 1),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Overflow"] },
        { type = "desc", text = L["|cffaaaaaaEverything past the limit is handed to another bar, which keeps a long list one readable row.|r"] },
        slider("maxIcons", L["Most icons on this bar"], 0, 24, 1),
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
        { type = "spacer", height = 6 },
        { type = "header", text = L["Icon"] },
        slider("iconZoom", L["Icon zoom"], 0, 0.2, 0.01),
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
        ns.BorderRows(rows, { texture = "borderTexture", size = "borderSize", offset = "borderInset",
            color = "borderColor", classColor = "borderClassColor" },
            { flatValue = "", maxOffset = 10,
              tooltips = { texture = L["A shaped icon brings its own border; this one is for the square shape."] } }),
        color("bgColor", L["Background color"]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["While the spell is on cooldown"] },
        toggle("showSwipe", L["Show the swipe"]),
        opacity("swipeAlpha", L["Swipe darkness"]),
        { type = "dropdown", label = L["Kind of swipe"], width = 200, values = swipeValues(false),
          get = function() return bar().swipeStyle or "dark" end,
          set = function(_, v) bar().swipeStyle = v; apply() end },
        toggle("ignoreGCD", L["Hide the global cooldown"], L["The swipe shows the spell's own cooldown only, not the short one after every cast."]),
        { type = "toggle", label = L["Dim the icon"],
          tooltip = L["The client dims it, so it also works while you are in combat."],
          get = function() return bar().desaturateOnCooldown end,
          set = function(_, v) bar().desaturateOnCooldown = v; apply() end },
        toggle("castableOnly", L["Only while castable"], L["Shows the icon only while the spell can be cast right now: usable, off cooldown and with enough power. Its place on the bar stays free. Spells only, also ones added by id."]),
        toggle("cdHide", L["Hide while on cooldown"], L["The icon is gone while the spell's own cooldown runs. Its place on the bar stays free."]),
        toggle("textOnly", L["Numbers only (no icon)"], L["Only the time, the charges and the stacks: no picture, no border, no swipe."]),
        toggle("hideMissing", L["Hide items you do not carry"], L["Item rows, the healthstone and the soulstone take no place on the bar while none is in your bags."]),

        { type = "spacer", height = 6 },
        { type = "header", text = L["Range and power"] },
        toggle("rangeColor", L["Red when out of range"], L["The icon turns red while your target is out of this spell's range. The client answers, so it works in combat too."]),
        toggle("powerColor", L["Blue without enough power"], L["The icon turns blue while you lack the mana, rage or energy for the spell."]),
        toggle("activePhase", L["Show the active phase"], L["While the buff of a spell is on you, its icon shows the buff running out, in combat too. On by default for a Buffs bar."]),
        { type = "dropdown", label = L["Without the buff"], width = 200, values = inactiveValues(false),
          tooltip = L["How a row with the active phase looks while its buff is not on you. The place on the bar always stays, so every buff keeps its spot."],
          get = function() return bar().inactive or "show" end,
          set = function(_, v) bar().inactive = v; apply() end },

        { type = "spacer", height = 6 },
        { type = "header", text = L["Text"] },
        toggle("showCountdown", L["Show the countdown"]),
        slider("countdownSize", L["Countdown size"], 8, 24, 1),
        color("countdownColor", L["Countdown color"]),
        toggle("showCharges", L["Show charges"]),
        slider("chargeSize", L["Charge text size"], 8, 20, 1),
        toggle("hideZeroCharges", L["Hide the charges at zero"], L["The number goes while no charge is left."]),
        { type = "toggle", label = L["Show the key"],
          tooltip = L["The key that casts it, taken from your action bars."],
          get = function() return bar().showKeybind end,
          set = function(_, v) bar().showKeybind = v; apply() end },
        slider("keybindSize", L["Key text size"], 6, 20, 1),
        color("keybindColor", L["Key color"]),
        { type = "toggle", label = L["Show the count"],
          tooltip = L["How many of an item you carry, and how many stacks a watched buff has."],
          get = function() return bar().showCount end,
          set = function(_, v) bar().showCount = v; apply() end },
        slider("countSize", L["Count text size"], 6, 20, 1),
        color("countColor", L["Count color"]),
    }
end

-- ---------------------------------------------------------------- glow --

local function glowPage()
    return {
        { type = "spacer", height = 6 },
        { type = "header", text = L["Glow"] },
        { type = "dropdown", label = L["Kind of glow"], width = 220,
          values = CM.Glow.Values(false),
          get = function() return bar().glowType or "pixel" end,
          set = function(_, v) bar().glowType = v; apply() end },
        color("glowColor", L["Glow color"]),
        toggle("readyGlow", L["Glow when it is ready"]),
        toggle("procGlow", L["Glow on a proc"],
            L["The client says which spell lit up. In a fight it sometimes says it secretly, and a proc we cannot place is left alone rather than guessed at."]),
        toggle("chargeGlow", L["Glow at full charges"],
            L["For spells with charges: glows while every charge is there. The client answers this in combat too."]),
        slider("stackGlow", L["Glow from this many stacks"], 0, 10, 1),
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
        toggle("oocFade", L["Fade out of combat"]),
        opacity("oocAlpha", L["Faded opacity"], { min = 5 }),
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

-- ---------------------------------------------------------------- bar glows --
--
-- A buff lights a spell up (BuffGlow.lua). On this tab a click on an icon of
-- the bar above opens the buffs to tick; the page lists what is set. Stored by
-- id, matched by NAME, like every row: a buff at another rank is the same buff.

local function hasBuff(e, name)
    for id in pairs(e.glowBuffs or {}) do
        if C_Spell.GetSpellName(id) == name then return true end
    end
    return false
end

local function toggleBuff(e, id, name)
    if hasBuff(e, name) then
        for other in pairs(e.glowBuffs) do
            if C_Spell.GetSpellName(other) == name then e.glowBuffs[other] = nil end
        end
        if next(e.glowBuffs) == nil then e.glowBuffs = nil end
    else
        e.glowBuffs = e.glowBuffs or {}
        e.glowBuffs[id] = true
    end
    menuApply()
end

-- The buffs on offer: the rows of every bar that shows an active phase (the
-- Buffs bars), what the client's cooldown viewer follows, and whatever this
-- row already has (an own id stays untickable otherwise).
local function glowCandidates(e)
    local out, seen = {}, {}
    local function add(id)
        if type(id) ~= "number" then return end
        local name = C_Spell.GetSpellName(id)
        if type(name) ~= "string" or name == "" or seen[name] then return end
        seen[name] = true
        out[#out + 1] = { spellID = id, name = name, icon = C_Spell.GetSpellTexture(id) }
    end
    local db = CM.db()
    for _, key in ipairs(db.barOrder or {}) do
        local b = CM.Bar(key)
        if b and (b.seed == "TrackedBuff" or b.activePhase) then
            for _, row in ipairs(CM.Spells(b)) do
                if row.kind == "spell" then add(row.id) end
            end
        end
    end
    for _, t in ipairs(CM.TrackedBuffs()) do add(t.spellID) end
    for id in pairs(e.glowBuffs or {}) do add(id) end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local glowRow
ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_CM_GLOWID"] = {
        text = L["The spell id of the buff:"],
        button1 = _G.OKAY or _G.ACCEPT or L["Save"], button2 = _G.CANCEL,
        hasEditBox = true, maxLetters = 12,
        OnShow = function(self)
            local box = ns.PopupEditBox(self)
            if box then box:SetText(""); box:SetFocus() end
        end,
        OnAccept = function(self)
            local box = ns.PopupEditBox(self)
            local id = box and tonumber(box:GetText())
            if id and glowRow and CM.AddGlowBuff then CM.AddGlowBuff(glowRow, id) end
        end,
        EditBoxOnEnterPressed = function(self)
            local id = tonumber(self:GetText())
            if id and glowRow and CM.AddGlowBuff then CM.AddGlowBuff(glowRow, id) end
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
end)

function CM.AddGlowBuff(e, id)
    local name = C_Spell.GetSpellName(id)
    if type(name) ~= "string" or name == "" then return end
    if not hasBuff(e, name) then toggleBuff(e, id, name) end
end

function CM.GlowMenu(barKey, index)
    local b = CM.Bar(barKey)
    local list = b and CM.Spells(b)
    local e = list and list[index]
    if not e then return nil end
    local menu = {
        { text = entryName(e), title = true },
    }
    for _, r in ipairs(triRows(e, L["Glow when it is ready"], "readyGlow")) do menu[#menu + 1] = r end
    menu[#menu + 1] = { separator = true }
    menu[#menu + 1] = { text = L["Glow while one of these buffs is on you"], title = true }
    local base = #menu
    for _, c in ipairs(glowCandidates(e)) do
        local id, name = c.spellID, c.name
        menu[#menu + 1] = { text = name, icon = c.icon, keepOpen = true,
            checked = function() return hasBuff(e, name) end,
            func = function() toggleBuff(e, id, name) end }
    end
    if #menu == base then
        menu[#menu + 1] = { text = L["No buffs to offer yet"], disabled = true }
    end
    menu[#menu + 1] = { separator = true }
    menu[#menu + 1] = { text = L["Own buff id..."], func = function()
        glowRow = e
        StaticPopup_Show("VFUI_CM_GLOWID")
    end }
    menu[#menu + 1] = { text = L["Missing buffs? Add them in the game's cooldown manager"],
        func = function() CM.OpenClientCooldownViewer() end }
    return menu
end

local function glowsPage()
    local page = {
        { type = "desc", text = L["|cffaaaaaaClick an icon of the bar above and tick the buffs that make it glow. While one of them is on you, the spell lights up, in combat too.|r"] },
        { type = "spacer", height = 6 },
        { type = "header", text = L["Glow"] },
        { type = "dropdown", label = L["Kind of glow"], width = 220, values = CM.Glow.Values(false),
          get = function() return bar().buffGlowType or "proc" end,
          set = function(_, v) bar().buffGlowType = v; apply() end },
        color("buffGlowColor", L["Glow color"]),
        toggle("buffGlowButtons", L["On the action buttons too"],
            L["Every action button that holds the spell glows as well. A stance or form page turned in a fight is followed after it."]),
        { type = "spacer", height = 6 },
        { type = "header", text = L["Spells and their buffs"] },
    }
    local any = false
    for _, e in ipairs(CM.Spells(bar())) do
        local names = {}
        for id in pairs(e.glowBuffs or {}) do
            local n = C_Spell.GetSpellName(id)
            names[#names + 1] = (type(n) == "string" and n ~= "") and n or ("#" .. tostring(id))
        end
        table.sort(names)
        if CM.Val(bar(), e, "readyGlow") then table.insert(names, 1, L["when it is ready"]) end
        if #names > 0 then
            any = true
            page[#page + 1] = { type = "desc",
                text = ("%s  |cff777777\194\171|r  %s"):format(entryName(e), table.concat(names, ", ")) }
        end
    end
    if not any then
        page[#page + 1] = { type = "desc", text = L["|cffaaaaaaNo spell on this bar glows for a buff yet.|r"] }
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
        hookedHide = true
        UI:OnMainFrameHide(function() CM.LeavePreview() end)
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

-- The bar page is every section of a bar in one go, in the order someone
-- setting a bar up reaches for them.
local function barsPage()
    local out = {}
    for _, part in ipairs({ barHead(), visibilityPage(), layoutPage(), iconsPage(), glowPage(), barExtras() }) do
        for _, row in ipairs(part) do out[#out + 1] = row end
    end
    return out
end

function mod:GetOptions(tabId)
    CM.EnsureBars()
    if tabId == "spell" then return spellPage() end
    if tabId == "glows" then return glowsPage() end
    return barsPage()
end

-- The bar picker and the live bar, pinned above every tab (Preview.lua). The
-- picker is the same dropdown the pages used to open with.
function mod.BuildPageHeader(host, tabId)
    CM.EnsureBars()
    local selector = barSelector(tabId or "spells")
    return CM.BuildPreviewHeader(host, selector.items[1])
end
