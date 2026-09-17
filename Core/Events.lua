-- VuloForeverUI / Core / Events
-- Central event dispatcher: ns:RegisterEvent("EVENT", handler) instead of a
-- frame per module.
local _, ns = ...
local L = ns.L

local dispatcher = CreateFrame("Frame", "VuloForeverUIEventDispatcher")
ns.eventFrame = dispatcher

-- event -> handler array. The arrays are treated as IMMUTABLE: register and
-- unregister publish a fresh copy instead of editing in place. A running
-- dispatch keeps iterating the array it started with, so a handler that
-- unregisters itself (or a neighbour) mid-firing can no longer shrink the list
-- under the loop. That used to skip every handler behind it and then call the
-- nil tail -- Lua evaluates the `#list` limit of a numeric for exactly once.
-- Copying costs one table per register/unregister; both are rare, the dispatch
-- path allocates nothing.
local handlers = {}
local onceSets = {}  -- event -> { [handler] = true }, cleared before the call

function ns:RegisterEvent(event, handler)
    if type(handler) ~= "function" then return false end
    local old = handlers[event]
    if not old then
        -- pcall: not all events exist in every WoW version
        -- (e.g. INSPECT_TALENT_READY does not exist in Anniversary). Silently ignore.
        local ok = pcall(dispatcher.RegisterEvent, dispatcher, event)
        if not ok then return false end
        handlers[event] = { handler }
        return true
    end
    -- Same handler twice would mean the same work twice per firing. Modules used
    -- to guard against this by hand, or pile up copies of a deferred handler for
    -- a whole fight; the registry owns the rule now.
    for i = 1, #old do
        if old[i] == handler then return false end
    end
    local new = {}
    for i = 1, #old do new[i] = old[i] end
    new[#new + 1] = handler
    handlers[event] = new
    return true
end

-- For "finish this the moment combat ends" handlers: the registry takes it back
-- out before calling it, so the handler cannot forget to and cannot pile up.
function ns:RegisterEventOnce(event, handler)
    if not ns:RegisterEvent(event, handler) then return false end
    local set = onceSets[event]
    if not set then set = {}; onceSets[event] = set end
    set[handler] = true
    return true
end

function ns:UnregisterEvent(event, handler)
    local old = handlers[event]
    if not old then return end
    local set = onceSets[event]
    if set then
        set[handler] = nil
        if not next(set) then onceSets[event] = nil end
    end
    local new, n = {}, 0
    for i = 1, #old do
        if old[i] ~= handler then n = n + 1; new[n] = old[i] end
    end
    if n == #old then return end   -- not registered: keep the existing array
    if n == 0 then
        handlers[event] = nil
        onceSets[event] = nil
        pcall(dispatcher.UnregisterEvent, dispatcher, event)
    else
        handlers[event] = new
    end
end

-- Per-module ownership. A module used to mirror every registration by hand in
-- OnDisable, one line per event; several simply did not, and one registers
-- anonymous functions that can never be taken back out by identity at all. The
-- registry writes the pairs down instead, so disabling a module detaches it
-- completely without the module having to remember anything. Stored flat
-- (event, handler, event, handler, ...) so a registration costs no extra table.
-- handler -> module key, so the profiler can bill dispatch time to the module
-- that asked for the event rather than to the event name. Only populated for
-- handlers registered through a module; ns:RegisterEvent stays anonymous.
ns.eventOwners = {}

function ns:ModRegisterEvent(mod, event, handler)
    if not ns:RegisterEvent(event, handler) then return false end
    local owned = mod._ownedEvents
    if not owned then owned = {}; mod._ownedEvents = owned end
    owned[#owned + 1] = event
    owned[#owned + 1] = handler
    ns.eventOwners[handler] = mod.key or mod.name
    return true
end

function ns:ModUnregisterAllEvents(mod)
    local owned = mod._ownedEvents
    if not owned then return end
    local key = mod.key or mod.name
    for i = #owned - 1, 1, -2 do
        local handler = owned[i + 1]
        ns:UnregisterEvent(owned[i], handler)
        -- The owner note goes with it. Left behind, this table keeps a hard
        -- reference to every handler a module ever registered, so nothing a
        -- switched-off module built can be collected. It shows most on the
        -- anonymous handlers: those have a fresh identity on every enable, so
        -- switching a module off and on again added one permanent entry each
        -- time. Nothing reads the table unless profiling is on, which is
        -- exactly why it could grow unnoticed.
        --
        -- Only OUR note: if another module registered the same function after
        -- us, the slot belongs to it and has to stay.
        if ns.eventOwners[handler] == key then ns.eventOwners[handler] = nil end
        owned[i], owned[i + 1] = nil, nil
    end
end

-- The combat-heavy events fire thousands of times per second in a raid with
-- several listeners each; a pcall per handler per firing is the hottest shared
-- code in the addon. These dispatch unprotected: an error surfaces through
-- Blizzard's error handler (louder, which such a bug deserves) and skips the
-- remaining handlers for that one firing only. Everything else keeps the
-- isolated per-handler pcall with the friendly chat message.
local HOT = {
    COMBAT_LOG_EVENT_UNFILTERED = true,
    UNIT_AURA = true,
    UNIT_HEALTH = true,
    UNIT_HEALTH_FREQUENT = true,
    UNIT_POWER_UPDATE = true,
    UNIT_POWER_FREQUENT = true,
}

local function takeOnceHandlers(event, list)
    local set = onceSets[event]
    if not set then return end
    -- One-shot handlers come out first; `list` is the snapshot we still walk.
    for i = 1, #list do
        local h = list[i]
        if set[h] then ns:UnregisterEvent(event, h) end
    end
end

local function onEvent(_, event, ...)
    local list = handlers[event]
    if not list then return end
    -- Inline test, then the shared function: an unconditional call here would
    -- add a Lua call per firing to the hottest path in the addon -- thousands
    -- per second in a raid -- for an event that almost never has one-shots.
    if onceSets[event] then takeOnceHandlers(event, list) end
    if HOT[event] then
        for i = 1, #list do
            list[i](event, ...)
        end
        return
    end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            ns:Print(L["|cffff5555Event handler error (%s):|r %s"], event, tostring(err))
        end
    end
end

-- A handler registered straight through ns:RegisterEvent belongs to no module
-- and can only be reported under its event name. There is no way to recover the
-- owner afterwards: WoW does not expose Lua's debug library at all (verified in
-- game -- `debug` is nil), so asking where a function was defined is not an
-- option. The fix is at the registration end: use mod:RegisterEvent and the
-- time lands on the module. Modules/DarkSkin.lua is the worked example -- its
-- handlers were the anonymous ones hiding a 28 ms hitch.
local function labelFor(h, event)
    return ns.eventOwners[h] or event
end

-- Measuring variant. It is NOT reached unless profiling is switched on: the
-- script is swapped wholesale, so the normal path above carries no flag test,
-- no timer call, nothing at all. That is the whole point of shipping this --
-- an instrumented build you have to hand a user is a build nobody runs.
local function onEventProfiled(_, event, ...)
    local list = handlers[event]
    if not list then return end
    -- Inline test, then the shared function: an unconditional call here would
    -- add a Lua call per firing to the hottest path in the addon -- thousands
    -- per second in a raid -- for an event that almost never has one-shots.
    if onceSets[event] then takeOnceHandlers(event, list) end
    local record, clock = ns.Prof.Record, debugprofilestop
    local hot = HOT[event]
    for i = 1, #list do
        local h = list[i]
        local t0 = clock()
        if hot then
            h(event, ...)
        else
            local ok, err = pcall(h, event, ...)
            if not ok then
                ns:Print(L["|cffff5555Event handler error (%s):|r %s"], event, tostring(err))
            end
        end
        -- Stop the clock BEFORE working out the label: Lua evaluates call
        -- arguments left to right, so labelFor would otherwise be counted as
        -- part of the handler it is labelling -- a bias weighted by call count,
        -- i.e. worst exactly where the measurement matters most.
        local dt = clock() - t0
        record(labelFor(h, event), dt)
    end
end

dispatcher:SetScript("OnEvent", onEvent)

function ns:SetEventProfiling(on)
    dispatcher:SetScript("OnEvent", on and onEventProfiled or onEvent)
end
