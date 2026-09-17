-- VuloForeverUI / Core / Schedule
-- Two shared schedulers every module needs and nearly every module used to
-- hand-roll: a throttled ticker registry and a combat-deferral queue.
local _, ns = ...

-- ---------------------------------------------------------------------------
-- Shared ticker
--
-- A dozen modules each carried the same three lines: own frame, own OnUpdate,
-- own accumulator, early-return until the interval is up. Every one of them is
-- a separate C-to-Lua call on EVERY rendered frame, even while the module is
-- idle -- an empty OnUpdate still pays the call, which is the whole cost.
--
-- One driver takes that down to a single call per frame plus a cheap in-VM walk,
-- and -- the part that actually matters -- it HIDES itself when the last
-- subscriber leaves. A hidden frame runs no OnUpdate at all, so an idle UI costs
-- exactly nothing. Blizzard parks its own state-driver manager the same way.

local driver = CreateFrame("Frame")
driver:Hide()

local subs, count = {}, 0

local function tick(_, elapsed)
    local i = 1
    while i <= count do
        local s = subs[i]
        s.acc = s.acc + elapsed
        if s.acc >= s.interval then
            s.acc = 0
            -- Protected: the per-module OnUpdate frames this replaced were
            -- isolated by the client, one script each. Sharing one walk would
            -- otherwise let a single throwing subscriber starve every
            -- subscriber behind it, every frame.
            local ok, err = pcall(s.fn, s.arg)
            if not ok then geterrorhandler()(err) end
        end
        -- A callback may cancel itself (or a neighbour). Removal swaps the last
        -- entry into this slot, so only advance when the slot is untouched --
        -- otherwise the entry that moved here would be skipped for this tick.
        -- (Cancelling an entry BEFORE this one costs the moved entry a single
        -- frame of accumulation. Self-correcting, and it needs a cancel on
        -- every frame to matter.)
        if subs[i] == s then i = i + 1 end
    end
end
-- Measuring variant, swapped in wholesale by the profiler so the walk above
-- stays exactly as reviewed when profiling is off.
local function tickProfiled(_, elapsed)
    local record, clock = ns.Prof.Record, debugprofilestop
    local i = 1
    while i <= count do
        local s = subs[i]
        s.acc = s.acc + elapsed
        if s.acc >= s.interval then
            s.acc = 0
            local t0 = clock()
            local ok, err = pcall(s.fn, s.arg)
            if not ok then geterrorhandler()(err) end
            record(s.label or "ticker", clock() - t0)
        end
        if subs[i] == s then i = i + 1 end
    end
end

driver:SetScript("OnUpdate", tick)

function ns:SetTickerProfiling(on)
    driver:SetScript("OnUpdate", on and tickProfiled or tick)
end

-- interval in seconds, fn(arg). Returns a handle for ns:CancelTicker.
-- The first call is one full interval away, exactly like the hand-rolled form
-- (a ticker added from inside the walk gets this frame's elapsed as well).
-- `label` is only read by the profiler.
function ns:AddTicker(interval, fn, arg, label)
    if type(fn) ~= "function" then return nil end
    local s = { interval = interval or 0.1, fn = fn, arg = arg, acc = 0, label = label }
    count = count + 1
    subs[count] = s
    s.slot = count
    if count == 1 then driver:Show() end
    return s
end

function ns:CancelTicker(handle)
    if not handle then return false end
    local slot = handle.slot
    if not slot or subs[slot] ~= handle then return false end   -- already gone
    local last = subs[count]
    subs[slot] = last
    last.slot = slot
    subs[count] = nil
    count = count - 1
    handle.slot = nil
    if count == 0 then driver:Hide() end
    return true
end

-- Debug aid: how much is actually running right now.
function ns:TickerCount() return count end

-- ---------------------------------------------------------------------------
-- Combat deferral
--
-- Nine call sites in Modules/ carry this guard by hand. NONE of them has been
-- moved onto it, and that is deliberate: their guard halves are identical, but
-- their drains are not -- each re-decides state in BOTH directions, or flushes a
-- second pending flag, or is driven by a ticker rather than the regen event.
-- Replacing those would change WHEN three of them run, so they were left alone
-- after review. This exists for NEW code, which should not hand-roll a tenth
-- copy, and for the sites that turn out to be genuine one-shots.
--
-- The framework offers three shapes; pick by what has to be true afterwards:
--   ns:RegisterEventOnce("PLAYER_REGEN_ENABLED", fn)  -- must survive the module
--                                                        being switched off
--   ns:RunOutOfCombat(fn, ...)                        -- just do it when safe
--   ns:RunOutOfCombatOnce(key, fn, ...)               -- ...and only once

local pending = {}
local keyed = {}
local regen = CreateFrame("Frame")

local function drain()
    -- The event firing is not proof lockdown has lifted (rapid re-entry, and it
    -- also fires around loading screens), so ask the live API.
    if InCombatLockdown() then return end
    if #pending == 0 then return end
    -- Swap BEFORE draining: a job that queues another job must land in a fresh
    -- list, not in the one being walked.
    local jobs = pending
    pending = {}
    for i = 1, #jobs do
        local j = jobs[i]
        if not j.dead then
            if j.key then keyed[j.key] = nil end
            -- unpack with the stored count: an explicit nil in the middle must
            -- not truncate the argument list the way # would.
            local ok, err = pcall(j.fn, unpack(j, 1, j.n))
            if not ok then geterrorhandler()(err) end
        end
    end
end

regen:RegisterEvent("PLAYER_REGEN_ENABLED")
regen:SetScript("OnEvent", drain)

-- Runs fn(...) now when out of combat, otherwise once combat ends.
function ns:RunOutOfCombat(fn, ...)
    if type(fn) ~= "function" then return end
    if not InCombatLockdown() then
        fn(...)
        return
    end
    pending[#pending + 1] = { fn = fn, n = select("#", ...), ... }
end

-- Same, but at most one queued job per key: a layout that gets requested forty
-- times during a fight must not run forty times when it ends.
function ns:RunOutOfCombatOnce(key, fn, ...)
    if type(fn) ~= "function" or key == nil then return end

    if not InCombatLockdown() then
        -- InCombatLockdown() goes false BEFORE PLAYER_REGEN_ENABLED reaches the
        -- frame, so an already-queued job for this key may still be sitting in
        -- the list. Kill it rather than just dropping the flag, or the work runs
        -- twice -- which is the one thing this function exists to prevent.
        local job = keyed[key]
        if job then job.dead = true; keyed[key] = nil end
        fn(...)
        return
    end

    if keyed[key] then return end
    local job = { key = key, fn = fn, n = select("#", ...), ... }
    keyed[key] = job
    pending[#pending + 1] = job
end
