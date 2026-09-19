-- VuloForeverUI / Core / Init
-- Loaded LAST. Waits for ADDON_LOADED, initializes DB,
-- enables modules, registers slash commands.
local _, ns = ...
local L = ns.L

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= ns.NAME then return end
        -- Wrong client: Namespace.lua already said so. Loading the DB and
        -- enabling modules built on the retail API would only turn one clear
        -- message into a wall of Lua errors.
        if ns.disabled then return end
        ns:InitDB()
        -- Any file-scope L[...] lookup before this point cached the CLIENT
        -- language, because the saved language override only exists now.
        -- Without this reset the override silently never applied.
        if ns.RefreshLocale then ns:RefreshLocale() end
        if ns.RunLocaleReadyCallbacks then ns:RunLocaleReadyCallbacks() end
        ns:EnableModules()

    elseif event == "PLAYER_LOGIN" then
        if ns.disabled then return end
        ns.isInitialised = true
        if ns.RestoreFreeMovers then ns:RestoreFreeMovers() end
        if ns.RestoreProfileKeybinds then ns:RestoreProfileKeybinds() end
        ns:Print(L["v%s loaded. /vfui to open."], ns.VERSION)
        -- Migrations run at ADDON_LOADED, where anything printed can scroll away
        -- before the player is even in the world. They leave their report here.
        for _, n in ipairs(ns.migrationNotes or {}) do
            ns:Print(unpack(n))
        end
        ns.migrationNotes = nil
        if ns.RestrictionsForced and ns.RestrictionsForced() then
            ns:Print("simulated combat restrictions are still ON -- '/vfsecrets force' switches them off.")
        end
        if ns._svSeedNote then
            ns:Print("dev seed: %s", ns._svSeedNote)
            ns._svSeedNote = nil
        end
        -- The first-time setup (UI/Setup.lua) no longer opens by itself: it
        -- relies on "this database is new", and a client that fails to load
        -- saved variables (seen client-wide on the beta, 2026-09-18) makes every
        -- login look new -- an endless loop for the player. /vfui setup and the
        -- button under Global Settings still open it.
    end
end)

-- Slash commands
-- Only the WORDS that follow /vfui live here -- those are this file's business
-- and no registry can know them. The standalone commands come from
-- ns:PrintSlashHelp, which reads the table every command writes itself into.
local function printVfuiHelp()
    local A = (ns.C and ns.C.accent) or "|cff9b6cff"
    ns:Print(L["VuloForeverUI — commands:"])
    ns:Print(A .. "/vfui <module>|r — " .. L["jump to that module's page"])
    ns:Print(A .. "/vfui search <text>|r — " .. L["search the settings for a word"])
    ns:Print(A .. "/vfui modules|r — " .. L["list all modules with on/off state"])
    ns:Print(A .. "/vfui setup|r — " .. L["run the first-time setup again"])
    ns:Print(A .. "/vfui client|r — " .. L["show what client this is and what the addon detected"])
    ns:Print(A .. "/vfui debug|r, " .. A .. "/vfui reset|r")
    if ns.PrintSlashHelp then ns:PrintSlashHelp() end
end

-- /vfui reset wipes every setting of every character on the account. A typo
-- while trying slash commands must not be able to do that silently, so it asks
-- first - the same way deleting a single profile already does.
ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_DB_RESET"] = {
    text = L["Reset ALL VuloForeverUI settings for every character on this account? This cannot be undone."],
    button1 = L["Reset"],
    button2 = CANCEL,
    OnAccept = function()
        if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
        -- The graphics-optimize backup dies with the DB, but the CVars it
        -- covers live in the client's config and would stay optimized with no
        -- way back. "Reset ALL settings" returns those too.
        local gfx = VuloForeverUIDB and VuloForeverUIDB.global
                and VuloForeverUIDB.global.gfxBackup
        if gfx then
            for cvar, v in pairs(gfx) do pcall(SetCVar, cvar, v) end
        end
        VuloForeverUIDB     = nil
        VuloForeverUICharDB = nil
        ns:Print(L["DB reset. UI reloading."])
        ReloadUI()
    end,
    timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    showAlert = 1,
}
end)

ns:RegisterSlash({ key = "OPTIONS", commands = { "/vfui", "/vulo" },
    desc = "Open the settings window. Add a word for more: help, modules, client, debug, reset.",
})
ns.Slash.OPTIONS = function(msg)
    local raw = (msg or ""):match("^%s*(.-)%s*$")
    msg = raw:lower()

    -- Answered BEFORE the UI check below. If the interface failed to load, the
    -- list of commands is the one thing that still helps, and printing it needs
    -- no interface.
    if msg == "help" or msg == "?" or msg == "commands" then
        printVfuiHelp()
        return
    end

    -- Also answered early, and on purpose: on the wrong client this is the only
    -- command that still does something useful.
    if msg == "client" then
        local name, build, _, iface = GetBuildInfo()
        ns:Print(L["Client %s (build %s), interface %d."], name, build, iface)
        ns:Print(L["Forever detected: %s"], tostring(ns.isForever))
        if _G.C_GameRules and C_GameRules.GetActiveGameMode then
            ns:Print("  GetActiveGameMode() = %s", tostring(C_GameRules.GetActiveGameMode()))
        end
        ns:Print("  WOW_PROJECT_ID = %s", tostring(_G.WOW_PROJECT_ID))
        return
    end

    if not ns.UI or not ns.UI.ToggleMainFrame then
        ns:Print(L["UI not loaded. Likely a Lua error during init. Enable /console scriptErrors 1 and /reload."])
        return
    end

    local ok, err = pcall(function()
        if msg == "" or msg == "config" or msg == "options" then
            ns.UI:ToggleMainFrame()

        elseif msg == "reset" then
            if ns:InCombat() then ns:Print(L["Not possible in combat."]); return end
            StaticPopup_Show("VFUI_DB_RESET")

        elseif msg == "debug" then
            ns.db.global.debug = not ns.db.global.debug
            ns:Print(L["Debug = %s"], tostring(ns.db.global.debug))

        elseif msg == "modules" then
            ns:Print(L["Registered modules:"])
            for _, key in ipairs(ns.moduleOrder) do
                local m = ns.modules[key]
                ns:Print("  - %s (%s) [%s]", m.name, key, ns:IsModuleEnabled(key) and L["ON"] or L["off"])
            end

        elseif msg == "setup" then
            if ns.ShowSetup then ns:ShowSetup() end

        elseif msg == "search" or msg == "suche" or msg == "find"
            or msg:match("^search%s") or msg:match("^suche%s") or msg:match("^find%s") then
            -- The window opens with the word already in the search box and the
            -- results open, so a setting is one Enter away from the chat line.
            local arg = raw:match("^%S+%s+(.-)$") or ""
            if ns.UI.OpenSearch then ns.UI:OpenSearch(arg) end

        elseif ns.modules[msg] then
            if not ns.UI.mainFrame or not ns.UI.mainFrame:IsShown() then
                ns.UI:ToggleMainFrame()
            end
            ns.UI:ShowModulePage(msg)

        else
            ns:Print(L["Type |cff9b6cff/vfui help|r for the full command list."])
        end
    end)

    if not ok then
        ns:Print(L["|cffff5555Error while executing:|r %s"], tostring(err))
    end
end

ns:RegisterSlash({ key = "RELOAD", commands = { "/rl", "/reloadui" },
    desc = "Reload the interface. Refused while in combat.",
    note = "Replaces the game's own /reloadui so it cannot be run mid-fight.",
})
ns.Slash.RELOAD = function()
    if InCombatLockdown and InCombatLockdown() then
        ns:Print(L["Not possible in combat."])
        return
    end
    ReloadUI()
end
