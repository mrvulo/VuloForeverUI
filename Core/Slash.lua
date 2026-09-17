-- VuloForeverUI / Core / Slash: the one place that knows every command we own.
--
-- WHY THIS EXISTS
-- The registrations were nineteen hand-written blocks across sixteen files, in
-- three naming conventions (VFUIPROF, VFUI_RELOAD, SCTTEST) and two idioms (a
-- bare global here, _G.SLASH_ there). Nothing anywhere held the list, with two
-- consequences: no way to show a player what exists, and no way to notice that
-- another addon had claimed the same command.
--
-- HOW A FILE USES IT -- two lines, and the body is untouched:
--
--     ns:RegisterSlash({ key = "CDEDIT", commands = { "/cdedit" },
--                        desc = "Move the cooldown bars.",
--                        module = "cooldownmanager" })
--     ns.Slash.CDEDIT = function(msg) ... end
--
-- The handler is looked up WHEN THE COMMAND RUNS, not when it is registered, so
-- the two lines may sit anywhere in the file and in either order. That is what
-- lets a module keep its handler where it always was.
--
--   key      namespaced to VFUI_<key>, so our keys cannot collide with another
--            addon's by accident the way SCTTEST could
--   commands first one is canonical; the rest are aliases
--   desc     an ENGLISH LOCALE KEY. Translated when the help table is printed,
--            never at file load -- see Core/Locale.lua
--   module   optional owner. Given one, the command says "that module is off"
--            instead of running against a module that is not there
--   note     optional extra line in the help table, for a command that does
--            something a player would not expect
--   hidden   leave out of the help table (diagnostics nobody needs to see)
local _, ns = ...
local L = ns.L

ns.Slash         = ns.Slash or {}
ns.slashCommands = ns.slashCommands or {}

local PREFIX = "VFUI_"
local registered = {}

function ns:RegisterSlash(opts)
    if type(opts) ~= "table" or type(opts.key) ~= "string"
       or type(opts.commands) ~= "table" or opts.commands[1] == nil then
        return
    end

    local key = opts.key
    local id  = PREFIX .. key

    -- Idempotent on purpose. Two callers register from inside OnEnable -- the
    -- disenchant queue and the trinket panel -- so this runs again every time
    -- those modules are switched on. Registering the same key twice is a no-op,
    -- not an error: the handler lives in ns.Slash and is looked up per call, so
    -- there is nothing to refresh.
    if registered[key] then return id end
    registered[key] = true

    for i, cmd in ipairs(opts.commands) do
        _G["SLASH_" .. id .. i] = cmd
    end

    _G.SlashCmdList[id] = function(msg, editBox)
        local fn = ns.Slash[key]
        if type(fn) ~= "function" then
            ns:Print(L["%s has no handler yet — this is a bug, please report it."], opts.commands[1])
            return
        end
        if opts.module and not ns:IsModuleEnabled(opts.module) then
            local m = ns.modules and ns.modules[opts.module]
            ns:Print(L["%s belongs to %s, which is switched off."],
                opts.commands[1], (m and m.name) or opts.module)
            return
        end
        -- A command is typed by a person; an error in one must not read as a
        -- broken addon with no hint of which command caused it.
        local ok, err = pcall(fn, msg, editBox)
        if not ok then
            ns:Print("|cffff5555%s:|r %s", opts.commands[1], tostring(err))
        end
    end

    ns.slashCommands[#ns.slashCommands + 1] = {
        key = key, id = id, commands = opts.commands,
        desc = opts.desc, module = opts.module, note = opts.note, hidden = opts.hidden,
    }
    return id
end

-- Who ELSE claims this command string. Walked only when the help table is
-- printed: by then every addon has loaded, and until then it costs nothing.
-- This is the check that was missing when we took /reloadui off Blizzard.
local function foreignOwner(cmd, ourId)
    local lower = cmd:lower()
    for id in pairs(_G.SlashCmdList) do
        if id ~= ourId then
            for i = 1, 8 do
                local c = _G["SLASH_" .. id .. i]
                if type(c) ~= "string" then break end
                if c:lower() == lower then return id end
            end
        end
    end
    return nil
end

function ns:PrintSlashHelp()
    local rows = {}
    for _, e in ipairs(ns.slashCommands) do
        if not e.hidden then rows[#rows + 1] = e end
    end
    table.sort(rows, function(a, b) return a.commands[1] < b.commands[1] end)

    ns:Print(L["|cff9b6cffCommands|r — %d in total. Grey ones belong to a module that is switched off."], #rows)

    for _, e in ipairs(rows) do
        local off  = e.module and not ns:IsModuleEnabled(e.module)
        local cmds = table.concat(e.commands, ", ")
        local desc = e.desc and L[e.desc] or ""
        if off then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff707070%s — %s|r", cmds, desc))
        else
            -- Same dash the /vfui subcommand list above uses: the two blocks are
            -- one answer to one question and must not read as two formats.
            DEFAULT_CHAT_FRAME:AddMessage(string.format("  |cff9b6cff%s|r — %s", cmds, desc))
        end
        if e.note then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("      |cffaaaaaa%s|r", L[e.note]))
        end
        -- Reported per alias, because only one of several may be contested.
        for _, cmd in ipairs(e.commands) do
            local other = foreignOwner(cmd, e.id)
            if other then
                DEFAULT_CHAT_FRAME:AddMessage(string.format(
                    "      |cffff8800%s|r", string.format(L["%s is also claimed by another addon (%s) — one of the two wins."], cmd, other)))
            end
        end
    end
end
