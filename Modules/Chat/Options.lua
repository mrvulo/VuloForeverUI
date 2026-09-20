-- VuloForeverUI / Modules / Chat / Options
--
-- Four tabs: the window, the text, the side buttons and the behaviour. Every
-- change goes through one deferred pass, because nothing in this module may
-- run inside the client's own chat code.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local Chat = ns.Chat

local mod = Chat.mod

mod.tabs = {
    { id = "window",   label = "Window" },
    { id = "text",     label = "Text" },
    { id = "buttons",  label = "Side buttons" },
    { id = "behaviour", label = "Behaviour" },
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

-- ---------------------------------------------------------------- pages --

local function windowPage()
    local page = {
        { type = "desc", text = L["|cffaaaaaaThe client's own chat windows stay where they are and keep every click -- this draws the text again, in the suite's font, and makes the client's copy invisible.|r"] },
        { type = "header", text = L["The panel"] },
        color("bgColor", L["Background color"]),
        toggle("showBorder", L["Show a border"]),
        slider("borderSize", L["Border size"], 0, 4, 1),
        color("borderColor", L["Border color"]),
        slider("padding", L["Padding"], 0, 20, 1),

        { type = "header", text = L["The tabs"] },
        slider("tabFontSize", L["Tab text size"], 6, 20, 1),
        toggle("activeUnderline", L["Underline the active tab"]),
        { type = "desc", text = L["|cffaaaaaaThe tabs you see are drawn by us, but the tab you CLICK is the client's own underneath -- selecting a window from addon code is what breaks whispers, so it is left to the client.|r"] },
    }
    local status = Chat.Panel.StatusText()
    if status then
        page[#page + 1] = { type = "desc", text = "|cffffcc55" .. status .. "|r" }
    end
    return page
end

local function textPage()
    return {
        { type = "header", text = L["The text"] },
        slider("fontSize", L["Text size"], 8, 24, 1),
        { type = "dropdown", label = L["Outline"], width = 200,
          values = {
              { value = "NONE",   text = L["None"] },
              { value = "OUTLINE", text = L["Thin"] },
              { value = "THICKOUTLINE", text = L["Thick"] },
          },
          get = function() return Chat.db().fontOutline end,
          set = function(_, v) Chat.db().fontOutline = v; apply() end },

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

        { type = "header", text = L["Timestamps"] },
        toggle("timestamps", L["Show a timestamp"]),
        { type = "dropdown", label = L["Timestamp format"], width = 200,
          values = {
              { value = "%H:%M",    text = "14:05" },
              { value = "%H:%M:%S", text = "14:05:37" },
              { value = "%I:%M",    text = "02:05" },
          },
          get = function() return Chat.db().timestampFormat end,
          set = function(_, v) Chat.db().timestampFormat = v; apply() end },
        color("timestampColor", L["Timestamp color"]),
        { type = "desc", text = L["|cffaaaaaaA line the client hands over as a secret -- which happens in instances and on Battle.net whispers -- is shown exactly as it came, without a timestamp: a secret may not be joined to anything.|r"] },
    }
end

local function buttonsPage()
    return {
        toggle("sidebar", L["Show the side buttons"]),
        toggle("sidebarRight", L["Put them on the right"]),
        slider("sidebarScale", L["Button size"], 0.6, 2, 0.05),
        slider("sidebarSpacing", L["Space between them"], 2, 30, 1),
        { type = "header", text = L["Which buttons"] },
        toggle("showCopy", L["Copy the chat"]),
        toggle("showFriends", L["Friends"]),
        toggle("showGuild", L["Guild"]),
        toggle("showSettings", L["Chat settings"]),
        toggle("showScroll", L["Jump to the newest line"]),
        { type = "desc", text = L["|cffaaaaaaThe copy button takes what is visible in the active window. Lines the client marked secret are left out -- they cannot be copied without reading them.|r"] },
    }
end

local function behaviourPage()
    return {
        { type = "header", text = L["Fading"] },
        toggle("idleFade", L["Fade when nothing happens"]),
        slider("idleFadeDelay", L["Wait this many seconds"], 3, 60, 1),
        slider("idleFadeStrength", L["How far it fades"], 0, 100, 5),

        { type = "header", text = L["The input line"] },
        toggle("inputOnTop", L["Put the input line above the chat"]),

        { type = "header", text = L["Scrollback"] },
        toggle("history", L["Keep the last lines across a reload"]),
        slider("historyLines", L["How many lines"], 10, 500, 10),
        { type = "desc", text = L["|cffaaaaaaKept per character, and only what was said in the open world: inside an instance the client hands chat over as secrets, which cannot be stored. Links in a restored line are text, not links.|r"] },
        { type = "button", label = L["Forget the stored lines"],
          onClick = function()
              Chat.History.Clear()
              ns:Print(L["The stored chat lines are gone."])
          end },
    }
end

function mod:GetOptions(tabId)
    if tabId == "text"      then return textPage() end
    if tabId == "buttons"   then return buttonsPage() end
    if tabId == "behaviour" then return behaviourPage() end
    return windowPage()
end
