-- VuloForeverUI / Modules / Locales / Options
--
-- The page: pick a language, and read what picking it actually gets you.
--
-- The second half is not decoration. A language list that offers a language is
-- read as a promise that the interface speaks it, and this one does not speak
-- it everywhere yet -- so the page says where the translation stops instead of
-- letting somebody find out one page at a time.
local _, ns = ...
local L = ns.L

local Loc = ns.Loc
local mod = Loc.mod

function mod:GetOptions()
    return {
        { type = "header", text = L["Language"] },
        { type = "dropdown", label = L["UI Language"], width = 220,
          tooltip = L["'Auto' follows your game client. Everything else overrides it for this addon only.\n\n|cffaaaaaaTakes full effect after a /reload.|r"],
          values = ns.SUPPORTED_LOCALES,
          get = function() return ns:GetLocaleOverride() end,
          set = function(_, v)
              ns:SetLocaleOverride(v)
              StaticPopup_Show("VFUI_RELOAD_LOCALE")
          end },
        { type = "desc", text = string.format(
            L["|cffaaaaaaAuto follows the game client, which speaks %s here.|r"], Loc.AutoName()) },

        { type = "header", text = L["What is translated"] },
        { type = "desc", text = L["|cffaaaaaaEnglish is the original: every label in the suite is written in it, and a line with no translation yet shows in English rather than not at all.|r"] },
        { type = "desc", text = L["|cffaaaaaaGerman covers the modules. Parts of the frame around them -- profiles, global settings, the editor and the setup -- are still English.|r"] },
        { type = "desc", text = L["|cffaaaaaaMore languages appear in the list as their files ship. Nothing else has to change for them.|r"] },
    }
end
