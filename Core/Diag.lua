-- VuloForeverUI / Core / Diag
--
-- A log that can be read away from the game PC. Lua errors, blocked protected
-- calls, everything the addon prints to chat and the full output of every slash
-- command land in VuloForeverUIDiag. The client writes that table to
-- WTF/Account/<account>/SavedVariables/VuloForeverUI.lua at /reload and logout,
-- and from there it is read on the development machine.
--
-- A saved variable of its own on purpose: it is not a setting, it must never
-- ride along in a profile export, and wiping it must never touch a setting.
--
-- Loaded right after Core/Slash.lua, so errors in the files before it are not
-- seen. Nothing here may throw: an error handler that errors is worse than none.
local addonName, ns = ...

local MAX = {
    errors   = 100,   -- distinct messages; a repeat only counts up
    events   = 150,   -- blocked actions, warnings, notes
    chat     = 150,   -- ns:Print lines outside a slash command
    outputs  = 30,    -- slash commands, the last run of each
    sessions = 20,
}
local MAX_LINES = 600    -- per slash command output; the dumps need room
local MAX_TEXT  = 2000   -- per string

local issecretvalue = _G.issecretvalue

local db          -- VuloForeverUIDiag, from our ADDON_LOADED on
local early = { errors = {}, events = {}, chat = {}, outputs = {}, sessions = {} }
local session = 0
local capture     -- the slash command output being recorded right now

local function now()
    return date("%Y-%m-%d %H:%M:%S")
end

local function list(name)
    return (db or early)[name]
end

local function push(name, entry)
    local t = list(name)
    t[#t + 1] = entry
    while #t > MAX[name] do table.remove(t, 1) end
end

-- A saved variable cannot hold a secret, and the string library refuses to look
-- into one. Colour codes are stripped: the file is read as text, not as chat.
local function clean(v)
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) ~= "string" then v = tostring(v) end
    v = (v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    if #v > MAX_TEXT then v = v:sub(1, MAX_TEXT) .. " ..." end
    return v
end

local function mentionsUs(...)
    for i = 1, select("#", ...) do
        local s = select(i, ...)
        if type(s) == "string" and s:find(addonName, 1, true) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Lua errors
---------------------------------------------------------------------------
local function recordError(msg, stack)
    local errors = list("errors")
    for i = #errors, 1, -1 do
        local e = errors[i]
        if e.msg == msg then
            e.count, e.last, e.session = e.count + 1, now(), session
            return
        end
    end
    push("errors", {
        msg = msg, stack = stack, count = 1, first = now(), last = now(),
        session = session, ours = mentionsUs(msg, stack),
    })
end

-- Every error goes in, not only ours: a Blizzard error that our taint caused
-- names Blizzard's file, not ours. "ours" marks the ones that name us.
-- The stack at the fault, not at this handler: the same arithmetic as the
-- client's own handler (Blizzard_ScriptErrors).
local function faultStack()
    local level = 3
    local errHeight = GetErrorCallstackHeight and GetErrorCallstackHeight()
    if errHeight and GetCallstackHeight then
        level = GetCallstackHeight() - (errHeight - 1)
    end
    return debugstack(level) or ""
end

local function captureError(msg)
    recordError(clean(msg), clean(faultStack()))
end

local prevHandler
local inHandler = false
local function errorHandler(msg, ...)
    -- Re-entry means another handler in the chain called back into this one.
    -- Returning breaks the loop; the first pass already recorded the error.
    if inHandler then return end
    inHandler = true
    pcall(captureError, msg)
    local prev = prevHandler
    local ok, res = true, nil
    if prev then ok, res = pcall(prev, msg, ...) end
    inHandler = false
    if ok then return res end
end

-- Whoever calls seterrorhandler after us replaces this handler, and on the
-- first test nothing was recorded at all. So the handler takes its place back
-- and chains to the newcomer -- noting who it was. Capped, so two addons that
-- both insist on going last cannot trade places forever.
local reclaims, reclaiming = 0, false
local function installHandler()
    local current = geterrorhandler()
    if current == errorHandler then return end
    prevHandler = current
    reclaiming = true
    seterrorhandler(errorHandler)
    reclaiming = false
end
installHandler()
-- An error-collecting addon may own the handler outright: it swaps
-- seterrorhandler for its own and never calls the client's handler again.
-- The call above then returns without effect. Kept on the record per session
-- so a report says which path did the work.
local handlerTook = geterrorhandler() == errorHandler

-- The second path, for when the handler is the client's own but not ours: it
-- (Blizzard_ScriptErrors, HandleLuaError) passes every error it may read to
-- C_Log.LogErrorMessage as "Lua Error: <message>\n<stack>". A secure post-hook
-- sees it without touching the caller's taint. Under an error-collecting addon
-- that owns the handler neither path sees anything; its own saved file does. Skipped while our own
-- handler runs, which calls the client's and would record the error twice.
if C_Log and C_Log.LogErrorMessage then
    hooksecurefunc(C_Log, "LogErrorMessage", function(text)
        if inHandler then return end
        pcall(function()
            local t = clean(text)
            local msg, stack = t:match("^Lua Error: (.-)\n(.*)$")
            recordError(msg or t, stack or "")
        end)
    end)
end

hooksecurefunc("seterrorhandler", function(h)
    if reclaiming or h == errorHandler or reclaims >= 10 then return end
    reclaims = reclaims + 1
    local by = (debugstack(3, 1, 0) or ""):match("^[^\n]*") or "?"
    if ns.Diag then ns.Diag.Note("handler", "error handler replaced by " .. by) end
    installHandler()
end)

---------------------------------------------------------------------------
-- Chat lines and slash command output
---------------------------------------------------------------------------
local basePrint = ns.Print
function ns:Print(msg, ...)
    basePrint(self, msg, ...)
    local ok, text = pcall(string.format, msg, ...)
    text = clean(ok and text or msg)
    if capture then
        if #capture.lines < MAX_LINES then capture.lines[#capture.lines + 1] = text end
    else
        push("chat", { t = now(), text = text })
    end
end

ns.Diag = {}

-- Called by Core/Slash.lua around every command we own.
function ns.Diag.BeginOutput(cmd, msg)
    local args = clean(msg or ""):match("^%s*(.-)%s*$")
    capture = { cmd = args ~= "" and (cmd .. " " .. args) or cmd, t = now(),
                session = session, lines = {} }
end

function ns.Diag.EndOutput(ok, err)
    local c = capture
    capture = nil
    if not c then return end
    if not ok then c.lines[#c.lines + 1] = "ERROR: " .. clean(err) end
    if #c.lines == 0 then return end
    -- One entry per command line: the newest run replaces the last one.
    local outputs = list("outputs")
    for i = #outputs, 1, -1 do
        if outputs[i].cmd == c.cmd then table.remove(outputs, i) end
    end
    push("outputs", c)
end

-- A line for the running command's output, not for the chat: the dumps in
-- Core/DiagDump.lua are far too long to print. Outside a command it becomes an
-- event, so nothing is lost.
function ns.Diag.Record(text)
    if capture then
        if #capture.lines < MAX_LINES then capture.lines[#capture.lines + 1] = clean(text) end
        return #capture.lines < MAX_LINES
    end
    push("events", { t = now(), kind = "record", text = clean(text), session = session })
    return true
end

-- Subcommands other files add to /vfdiag: [word] = function(rest).
ns.Diag.Commands = {}

-- For code that wants something on the record without printing it.
function ns.Diag.Note(kind, text)
    push("events", { t = now(), kind = kind, text = clean(text), session = session })
end

---------------------------------------------------------------------------
-- Saved variable, session stamp, blocked actions
---------------------------------------------------------------------------
local function bind()
    if type(VuloForeverUIDiag) ~= "table" then VuloForeverUIDiag = {} end
    db = VuloForeverUIDiag
    for name in pairs(MAX) do
        if type(db[name]) ~= "table" then db[name] = {} end
    end
    db.nextSession = (tonumber(db.nextSession) or 0) + 1
    session = db.nextSession
    local version, build = GetBuildInfo()
    local pending = early
    early = nil
    push("sessions", { id = session, t = now(), addon = ns.VERSION,
                       client = tostring(version) .. "." .. tostring(build) })
    for name, entries in pairs(pending) do
        for _, e in ipairs(entries) do
            e.session = session
            if name == "errors" then recordError(e.msg, e.stack) else push(name, e) end
        end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("ADDON_ACTION_BLOCKED")
frame:RegisterEvent("ADDON_ACTION_FORBIDDEN")
frame:RegisterEvent("LUA_WARNING")
frame:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" then
        if a == addonName then bind() end
    elseif event == "PLAYER_LOGIN" then
        -- Some later code may have set its own handler; chain onto it.
        installHandler()
        local s = list("sessions")
        local cur = s[#s]
        if cur and cur.id == session then
            cur.handlerAtLoad = handlerTook
            cur.handlerAtLogin = geterrorhandler() == errorHandler
            local _, class = UnitClass("player")
            cur.char = clean(UnitName("player")) .. "-" .. clean(GetRealmName())
            cur.class = class
        end
    elseif event == "LUA_WARNING" then
        -- Most warnings are about other addons' files; keep the ones naming us.
        if mentionsUs(b) then ns.Diag.Note(event, b) end
    else
        ns.Diag.Note(event, tostring(a) .. ": " .. tostring(b))
    end
end)

---------------------------------------------------------------------------
-- /vfdiag
---------------------------------------------------------------------------
ns:RegisterSlash({ key = "DIAG", commands = { "/vfdiag" },
    desc = "Diagnostics log for bug reports: errors, blocked actions and command output.",
    note = "'/vfdiag note <text>' adds a note, '/vfdiag mouse' records every frame and texture under the cursor, '/vfdiag frame <name>' one frame, '/vfdiag db <module>' a module's settings, '/vfdiag test' records a test error, '/vfdiag clear' empties the log. It is saved at /reload and logout.",
})

ns.Slash.DIAG = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "clear" then
        for name in pairs(MAX) do
            if name ~= "sessions" then wipe(list(name)) end
        end
        ns:Print("Diagnostics log cleared.")
    elseif cmd == "note" and rest ~= "" then
        ns.Diag.Note("note", rest)
        ns:Print("Note saved. /reload writes it to disk.")
    elseif ns.Diag.Commands[cmd] then
        ns.Diag.Commands[cmd](rest)
    elseif cmd == "test" then
        C_Timer.After(0, function() error(addonName .. ": /vfdiag test error") end)
        ns:Print("Test error raised. /reload writes it to disk.")
    else
        local errors, ours = list("errors"), 0
        for _, e in ipairs(errors) do
            if e.ours then ours = ours + 1 end
        end
        ns:Print("Diagnostics log, session %d: %d errors (%d naming this addon), "
            .. "%d events, %d command outputs, errors %s. /reload writes it to disk.",
            session, #errors, ours, #list("events"), #list("outputs"),
            geterrorhandler() == errorHandler and "owned" or "via client log")
    end
end
