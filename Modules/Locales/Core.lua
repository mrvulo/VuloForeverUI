-- VuloForeverUI / Modules / Locales / Core
--
-- The module behind the language page: registration, and the reload prompt.
-- The page itself is Options.lua.
--
-- The switch used to be a row inside Global Settings, between the UI scale and
-- the minimap button. It is here on its own now for two reasons: somebody
-- looking for it is looking for a LANGUAGE, not for a display setting; and a
-- page of its own has room to say the two things the row could not -- what
-- "Auto" resolves to on this client, and how far the translation reaches.
--
-- Why a reload is needed at all: a module's labels are evaluated when its file
-- runs, and the locale files are read before any of them. Switching the
-- language mid-session would leave every already-built page speaking the old
-- one. ns:RefreshLocale() drops the caches, so anything built AFTER the switch
-- is already correct -- the reload is what makes the rest catch up.
--
-- Only the languages that actually exist are offered. ns.SUPPORTED_LOCALES is
-- the list; a language whose locale file ships gets added there, and this
-- module needs no change for it.
local _, ns = ...
local L = ns.L

local Loc = {}
ns.Loc = Loc

local mod = ns:RegisterModule("locales", {
    name        = "Locales",
    group       = "Global",
    description = "The language the suite speaks: the client's own, or one you pick.",
    noToggle    = true,      -- a language cannot be switched off
    optionsGrid = true,
    -- Global Settings carries no order of its own (0) and Edit Mode takes 1,
    -- so this sits third in the group rather than alphabetically above them.
    sidebarOrder = 2,
    defaults    = { enabled = true },
})
Loc.mod = mod

-- Nothing to start: the override is read out of the saved variables by
-- Core/Locale.lua long before a module is enabled.
function mod:OnEnable() end

-- The reload prompt lives with the switch that raises it.
ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_RELOAD_LOCALE"] = {
        text = L["Language changed. /reload required to apply the new language to all UI elements."],
        button1 = L["Reload now"],
        button2 = L["Later"],
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end)

-- What "Auto" picks on this client, named in its own language so the line
-- still reads after the switch has been used.
function Loc.AutoName()
    local code = (GetLocale and GetLocale()) or "enUS"
    for _, entry in ipairs(ns.SUPPORTED_LOCALES) do
        if entry.value == code then return entry.text end
    end
    return ns.SUPPORTED_LOCALES[2] and ns.SUPPORTED_LOCALES[2].text or "English"
end
