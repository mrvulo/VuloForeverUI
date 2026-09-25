-- VuloForeverUI / Modules / Chat / Options
--
-- Three tabs: the chat itself, its tabs, and the side buttons. Every change
-- goes through one deferred pass, because nothing in this module may run
-- inside the client's own chat code.
--
-- The Chat tab is laid out in the four blocks the user asked for -- display,
-- idle fade, input line, extras -- rather than split by which file happens to
-- implement a setting. Where a setting lives in the code is our problem, not
-- the reader's.
local _, ns = ...
local L  = ns.L
local Chat = ns.Chat

local mod = Chat.mod

mod.tabs = {
    { id = "chat",    label = "Chat" },
    { id = "tabs",    label = "Tabs" },
    { id = "sidebar", label = "Sidebar" },
}

local function apply()
    Chat.Refresh()
end

local function toggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return Chat.db()[key] end,
        set = function(_, v) Chat.db()[key] = v; apply() end }
end

local function slider(key, label, min, max, step)
    return { type = "slider", label = label, min = min, max = max, step = step,
        get = function() return Chat.db()[key] end,
        set = function(_, v) Chat.db()[key] = v; apply() end }
end

local function color(key, label)
    return { type = "color", label = label,
        get = function() return Chat.db()[key] end,
        set = function(r, g, b)
            local c = Chat.db()[key]
            c.r, c.g, c.b = r, g, b
            apply()
        end }
end

-- A toggle that other rows are greyed out by.
--
-- `disabled` is evaluated ONCE, when the page is built -- so a toggle that
-- unlocks rows below it has to rebuild the page, or those rows stay grey and
-- unclickable until the tab is reopened. The plain toggle() above cannot do
-- this for everyone: a rebuild on every switch would be wasted work on the
-- dozen toggles that gate nothing.
local function gateToggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return Chat.db()[key] end,
        set = function(_, v)
            Chat.db()[key] = v
            apply()
            ns.UI:BuildOptionsPage(ns.UI._currentBuildKey, ns.UI.currentTab)
        end }
end

-- The alpha of a colour, as its own row. The colour swatch hands back r, g, b
-- and nothing else, so without this a colour whose alpha is zero is a control
-- that visibly does nothing however often it is changed.
local function opacity(key, label)
    return { type = "slider", label = label, min = 0, max = 1, step = 0.05,
        get = function() return Chat.db()[key].a end,
        set = function(_, v) Chat.db()[key].a = v; apply() end }
end

local function dropdown(key, label, values, width)
    return { type = "dropdown", label = label, width = width or 200, values = values,
        get = function() return Chat.db()[key] end,
        set = function(_, v) Chat.db()[key] = v; apply() end }
end

-- ------------------------------------------------------------- pickers --

local function outlineValues()
    return {
        { value = "NONE",         text = L["None"] },
        { value = "OUTLINE",      text = L["Thin"] },
        { value = "THICKOUTLINE", text = L["Thick"] },
    }
end

-- Shared-media lists all get a "none" entry of their own rather than an empty
-- first row: "none" is a real choice here (the flat fill, no sound), not the
-- absence of one.
local function textureValues()
    local v = { { value = "", text = L["None"] } }
    for _, e in ipairs(ns.MediaStatusbarValues and ns.MediaStatusbarValues() or {}) do
        v[#v + 1] = e
    end
    return v
end

local function soundValues()
    local v = { { value = "", text = L["None"] } }
    for _, name in ipairs(ns.BUNDLED_SOUNDS or {}) do
        v[#v + 1] = { value = name, text = name }
    end
    return v
end

-- The tab font is the module's own setting, not the account-wide one: it is a
-- choice WITHIN the chat, so it sits in the profile beside the other tab
-- settings and its first entry follows the chat font rather than the global.
local function tabFontValues()
    local v = { { value = "", text = L["Chat font"] } }
    for _, e in ipairs(ns.MediaFontValues and ns.MediaFontValues() or {}) do
        v[#v + 1] = e
    end
    return v
end

-- The chat font. Stored account-wide in g.fonts.modules.chat, exactly where the
-- global font settings keep it -- this row is a second way into the same
-- setting, not a second setting. The gear next to it leads to the rest of them.
local function fontValues()
    local v = { { value = "", text = L["Global Font"] } }
    for _, e in ipairs(ns.MediaFontValues and ns.MediaFontValues() or {}) do
        v[#v + 1] = e
    end
    return v
end

local function fontRow()
    return {
        type = "dropdown", label = L["Font"], width = 220, noOverride = true,
        values = fontValues(),
        tooltip = L["The chat messages, the input line and the tab labels."]
            .. "\n\n|cffaaaaaa" .. L["Requires /reload."] .. "|r",
        get = function()
            local m = ns.db.global.fonts.modules
            local o = m and m.chat
            return (o and o.font) or ""
        end,
        set = function(_, v)
            if v == "" then v = nil end
            local m = ns.db.global.fonts.modules
            if v then
                if not m then m = {}; ns.db.global.fonts.modules = m end
                m.chat = m.chat or {}
                m.chat.font = v
            elseif m and m.chat then
                m.chat.font = nil
                if next(m.chat) == nil then m.chat = nil end
                if next(m) == nil then ns.db.global.fonts.modules = nil end
            end
            StaticPopup_Show("VFUI_RELOAD_FONT")
        end,
        subOptions = {
            { type = "button", label = L["All module fonts"],
              onClick = function() ns.UI:ShowModulePage("globalsettings") end },
        },
    }
end

-- ---------------------------------------------------------------- pages --

local function chatPage()
    local page = {
        { type = "desc", text = L["|cffaaaaaaThe client's own chat windows stay where they are and keep every click -- this draws the text again, in the suite's font, and makes the client's copy invisible.|r"] },

        { type = "header", text = L["Display"] },
        dropdown("visibility", L["Visibility"], {
            { value = "always",    text = L["Always"] },
            { value = "mouseover", text = L["On mouseover"] },
            { value = "never",     text = L["Never"] },
        }),
        color("bgColor", L["Background color"]),
        { type = "slider", label = L["Background opacity"], min = 0, max = 1, step = 0.05,
          get = function() return Chat.db().bgColor.a end,
          set = function(_, v) Chat.db().bgColor.a = v; apply() end },
        dropdown("bgTexture", L["Background texture"], textureValues(), 220),
        fontRow(),
        slider("fontSize", L["Text size"], 8, 24, 1),
        dropdown("fontOutline", L["Outline"], outlineValues()),
        toggle("lockChatSize", L["Lock the main chat size"],
            L["Kills the resize grip of the first chat window. The other windows have none.\n\nA change made in combat takes effect the moment combat ends: the chat frames are protected, and the client refuses the call while you are fighting."]),
        toggle("showBorder", L["Show a border"]),
        slider("borderSize", L["Border size"], 0, 4, 1),
        color("borderColor", L["Border color"]),
        slider("padding", L["Padding"], 0, 20, 1),

        { type = "header", text = L["Idle fade"] },
        toggle("idleFade", L["Fade when nothing happens"]),
        slider("idleFadeDelay", L["Wait this many seconds"], 3, 60, 1),
        slider("idleFadeStrength", L["How far it fades"], 0, 100, 5),

        { type = "header", text = L["The input line"] },
        toggle("inputOnTop", L["Put the input line above the chat"]),
        slider("inputHeight", L["Input line height"], 16, 48, 1),
        toggle("inputUseChatFont", L["Input line uses the chat font"]),
        slider("inputFontSize", L["Input line text size"], 8, 24, 1),

        { type = "header", text = L["Extras"] },
        { type = "toggle", label = L["Keep the last lines across a reload"],
          get = function() return Chat.db().history end,
          set = function(_, v) Chat.db().history = v; apply() end,
          subOptions = {
              slider("historyLines", L["How many lines"], 10, 500, 10),
              { type = "desc", text = L["|cffaaaaaaKept per character, and only what was said in the open world: inside an instance the client hands chat over as secrets, which cannot be stored. Links in a restored line are text, not links.|r"] },
              { type = "button", label = L["Forget the stored lines"],
                onClick = function()
                    Chat.History.Clear()
                    ns:Print(L["The stored chat lines are gone."])
                end },
          } },
        toggle("hideTooltipOnHover", L["Hide the tooltip on hover"]),
        dropdown("whisperSound", L["Whisper sound"], soundValues()),
        { type = "toggle", label = L["Show a timestamp"],
          get = function() return Chat.db().timestamps end,
          set = function(_, v) Chat.db().timestamps = v; apply() end,
          subOptions = {
              { type = "dropdown", label = L["Timestamp format"], width = 200,
                values = {
                    { value = "%H:%M",    text = "14:05" },
                    { value = "%H:%M:%S", text = "14:05:37" },
                    { value = "%I:%M",    text = "02:05" },
                },
                get = function() return Chat.db().timestampFormat end,
                set = function(_, v) Chat.db().timestampFormat = v; apply() end },
              color("timestampColor", L["Timestamp color"]),
          } },
        { type = "toggle", label = L["Class colors for names"],
          tooltip = L["The client colours them inside its own formatter -- the addon never touches the text, which it may not."],
          get = function() return Chat.db().classColorNames end,
          set = function(_, v)
              Chat.db().classColorNames = v
              if not Chat.Engine.ApplyNameColors() then
                  ns:Print(L["This client has no switch for class-coloured names."])
              end
              apply()
          end },
        { type = "desc", text = L["|cffaaaaaaA line the client hands over as a secret -- which happens in instances and on Battle.net whispers -- is shown exactly as it came, without a timestamp: a secret may not be joined to anything.|r"] },
    }
    local status = Chat.Panel.StatusText()
    if status then
        page[#page + 1] = { type = "desc", text = "|cffffcc55" .. status .. "|r" }
    end
    return page
end

local function tabsPage()
    local synced = function() return Chat.db().tabBorderSync ~= false end
    return {
        { type = "desc", text = L["|cffaaaaaaThe tabs you see are drawn by us, but the tab you CLICK is the client's own underneath -- selecting a window from addon code is what breaks whispers, so it is left to the client.|r"] },

        { type = "header", text = L["Layout"] },
        { type = "dropdown", label = L["Tab text alignment"], width = 200, values = {
                { value = "CENTER", text = L["Centre"] },
                { value = "LEFT",   text = L["Left"] },
            },
          get = function() return Chat.db().tabAlign end,
          set = function(_, v)
              Chat.db().tabAlign = v
              apply()
              -- the padding row below is only live for "left"; its greyed
              -- state is read when the page is built, so the page is rebuilt
              C_Timer.After(0, function()
                  local UI = ns.UI
                  if UI.currentModule == "chat" and UI.BuildOptionsPage then
                      UI:BuildOptionsPage(UI.currentModule, UI.currentTab)
                  end
              end)
          end },
        { type = "slider", label = L["Inner padding"], min = 0, max = 40, step = 1,
            disabled = function() return Chat.db().tabAlign ~= "LEFT" end,
            get = function() return Chat.db().tabPaddingX end,
            set = function(_, v) Chat.db().tabPaddingX = v; apply() end },
        { type = "desc", text = L["|cffaaaaaaHeight, width and spacing are not here on purpose: a tab of ours is drawn exactly on the client's tab, and moving the drawing off the thing that takes the click means clicking a label and selecting the window next to it.|r"] },

        { type = "header", text = L["Typography"] },
        dropdown("tabFont", L["Tab font"], tabFontValues(), 220),
        slider("tabFontSize", L["Tab text size"], 6, 20, 1),
        color("tabTextColor", L["Tab text color"]),
        color("tabTextColorActive", L["Active tab text color"]),

        { type = "header", text = L["Appearance"] },
        color("tabBgColor", L["Tab background color"]),
        opacity("tabBgColor", L["Tab background opacity"]),
        color("tabBgColorActive", L["Active tab background color"]),
        opacity("tabBgColorActive", L["Active tab background opacity"]),
        dropdown("tabTexture", L["Tab texture"], textureValues(), 220),
        { type = "toggle", label = L["Underline the active tab"],
          get = function() return Chat.db().activeUnderline end,
          set = function(_, v) Chat.db().activeUnderline = v; apply() end,
          subOptions = {
              slider("underlineSize", L["Underline thickness"], 1, 6, 1),
              opacity("underlineColor", L["Underline opacity"]),
              gateToggle("underlineAccent", L["Use the theme color"]),
              { type = "color", label = L["Underline color"],
                disabled = function() return Chat.db().underlineAccent ~= false end,
                get = function() return Chat.db().underlineColor end,
                set = function(r, g, b)
                    local c = Chat.db().underlineColor
                    c.r, c.g, c.b = r, g, b
                    apply()
                end },
          } },

        { type = "header", text = L["Border"] },
        gateToggle("tabBorderSync", L["Match the chat window's border"],
            L["On, a tab wears whatever border the chat panel wears, so there is only one answer to what a border looks like here."]),
        { type = "slider", label = L["Tab border size"], min = 0, max = 4, step = 1,
          disabled = synced,
          get = function() return Chat.db().tabBorderSize end,
          set = function(_, v) Chat.db().tabBorderSize = v; apply() end },
        { type = "slider", label = L["Tab border opacity"], min = 0, max = 1, step = 0.05,
          disabled = synced,
          tooltip = L["Applies to both border colours below."],
          get = function() return Chat.db().tabBorderColor.a end,
          set = function(_, v)
              Chat.db().tabBorderColor.a = v
              Chat.db().tabBorderColorActive.a = v
              apply()
          end },
        { type = "color", label = L["Tab border color"], disabled = synced,
          get = function() return Chat.db().tabBorderColor end,
          set = function(r, g, b)
              local c = Chat.db().tabBorderColor
              c.r, c.g, c.b = r, g, b
              apply()
          end },
        { type = "color", label = L["Active tab border color"], disabled = synced,
          get = function() return Chat.db().tabBorderColorActive end,
          set = function(r, g, b)
              local c = Chat.db().tabBorderColorActive
              c.r, c.g, c.b = r, g, b
              apply()
          end },
    }
end

local function sidebarPage()
    return {
        { type = "header", text = L["The side bar"] },
        -- One dropdown over two keys: "never" is the old on/off being off, so
        -- a profile that had the column switched off keeps it switched off
        -- without a migration to get wrong.
        { type = "dropdown", label = L["Sidebar visibility"], width = 200,
          values = {
              { value = "always",    text = L["Always"] },
              { value = "mouseover", text = L["On mouseover"] },
              { value = "never",     text = L["Never"] },
          },
          get = function()
              local db = Chat.db()
              if not db.sidebar then return "never" end
              return db.sidebarVisibility or "always"
          end,
          set = function(_, v)
              local db = Chat.db()
              if v == "never" then
                  db.sidebar = false
              else
                  db.sidebar = true
                  db.sidebarVisibility = v
              end
              apply()
          end,
          subOptions = {
              toggle("sidebarRight", L["Put them on the right"]),
          } },
        slider("sidebarWidth", L["Sidebar width"], 0, 80, 1),
        { type = "desc", text = L["|cffaaaaaaWidth zero keeps the column exactly as wide as its icons. Anything else is a real width, with the icons centred in it.|r"] },
        toggle("hideSidebarBg", L["Hide the sidebar background"]),
        { type = "toggle", label = L["Separate sidebar"],
          tooltip = L["Pushes the column away from the chat panel instead of letting it sit against it."],
          get = function() return Chat.db().sidebarSeparate end,
          set = function(_, v) Chat.db().sidebarSeparate = v; apply() end,
          subOptions = {
              slider("sidebarSeparateSpacing", L["Gap to the chat"], 0, 40, 1),
          } },

        { type = "header", text = L["Icons"] },
        { type = "color", label = L["Icon color"],
          disabled = function() return Chat.db().iconUseAccent and true or false end,
          get = function() return Chat.db().iconColor end,
          set = function(r, g, b)
              local c = Chat.db().iconColor
              c.r, c.g, c.b = r, g, b
              apply()
          end },
        gateToggle("iconUseAccent", L["Use the theme color"]),
        { type = "toggle", label = L["Move the icons freely"],
          tooltip = L["Drag an icon where you want it. Positions are kept per button, so one you switch off and on again comes back where you left it."],
          get = function() return Chat.db().freeMoveIcons end,
          set = function(_, v) Chat.db().freeMoveIcons = v; apply() end,
          subOptions = {
              { type = "button", label = L["Line them up again"],
                onClick = function()
                    Chat.db().iconPositions = {}
                    apply()
                end },
          } },
        slider("sidebarScale", L["Icon size"], 0.6, 2, 0.05),
        slider("sidebarSpacing", L["Space between them"], 2, 30, 1),
        -- One box over six keys. The order the menu lists them in is the
        -- order the column draws them in, which is the order Sidebar.lua's own
        -- button table has -- a second list here would be a second thing to
        -- keep in step.
        { type = "dropdown", label = L["Sidebar icons"], width = 240,
          multi = true,
          values = {
              { value = "showCopy",     text = L["Copy the chat"] },
              { value = "showFriends",  text = L["Friends"] },
              { value = "showGuild",    text = L["Guild"] },
              { value = "showNewWindow", text = L["New chat window"] },
              { value = "showSettings", text = L["Chat settings"] },
              { value = "showScroll",   text = L["Jump to the newest line"] },
          },
          isChecked = function(key) return Chat.db()[key] and true or false end,
          toggle = function(key)
              local db = Chat.db()
              db[key] = not db[key]
              apply()
          end },
        -- Switching this on switches the button itself on, rather than leaving
        -- a setting that is on and does nothing: the button only exists while
        -- "jump to the newest line" is ticked in the icon menu, and that menu
        -- is a collapsed list where nobody would go looking for the reason.
        { type = "toggle", label = L["Scroll button on the chat window"],
          tooltip = L["Moves the jump-to-newest button into the corner of the chat instead of the column. It leaves the column rather than appearing in both."],
          get = function() return Chat.db().scrollButtonOnChat end,
          set = function(_, v)
              local db = Chat.db()
              db.scrollButtonOnChat = v
              if v then db.showScroll = true end
              apply()
          end },

        { type = "desc", text = L["|cffaaaaaaThe copy button takes what is visible in the active window. Lines the client marked secret are left out -- they cannot be copied without reading them.|r"] },
    }
end

function mod:GetOptions(tabId)
    if tabId == "tabs"    then return tabsPage() end
    if tabId == "sidebar" then return sidebarPage() end
    return chatPage()
end
