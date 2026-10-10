-- VuloForeverUI / Core / Profiler
--
-- A measuring tool that ships switched off, so a user can turn it on and read
-- the numbers back instead of us guessing. Two design rules:
--
--   1. OFF COSTS NOTHING. Not "one boolean" -- nothing. The instrumented
--      dispatch and ticker are separate functions that get swapped into place
--      when profiling starts, so the normal paths carry no flag, no branch and
--      no timer call. An instrumented build you have to hand somebody is a
--      build nobody ever runs.
--   2. It bills MODULES, not call sites. Because events are owned by the module
--      that registered them, dispatch time lands on "bags" or "nameplates"
--      rather than on "BAG_UPDATE" -- which is the question actually worth
--      asking when fifty modules share one addon budget.
--
-- debugprofilestop is a shared global stopwatch: debugprofilestart() would
-- reset it for every other addon mid-measurement, so it is never called here.
-- Only differences between readings are used.
local _, ns = ...
local L = ns.L

local clock = debugprofilestop
local data = {}          -- label -> { ms, calls, peak }
local active, startedAt = false, 0

ns.Prof = {}

-- kb: what the Lua heap grew by while the handler ran -- the garbage it made.
-- A collection step in between can make it negative; that counts as 0.
-- What ran since the hitch watcher last looked (about one frame): the sum,
-- and the single biggest piece.
local frameSum, frameTop, frameTopMs = 0, nil, 0
local prevSum, prevTop, prevTopMs = 0, nil, 0

function ns.Prof.Record(label, ms, kb)
    local d = data[label]
    if not d then d = { ms = 0, calls = 0, peak = 0, kb = 0 }; data[label] = d end
    d.ms = d.ms + ms
    d.calls = d.calls + 1
    if ms > d.peak then d.peak = ms end
    if kb and kb > 0 then d.kb = d.kb + kb end
    frameSum = frameSum + ms
    if ms > frameTopMs then frameTop, frameTopMs = label, ms end
end

-- ---------------------------------------------------------------- hitches --
--
-- Every frame in which the client billed us HITCH_MS or more, with what the
-- measured parts did in it. A hitch whose measured part is small happened in
-- code the dispatch does not see -- an OnUpdate script, a hook, a timer of
-- one of our frames, or the garbage collector cleaning up after us.
local HITCH_MS, MAX_HITCHES = 30, 40
local hitches = {}
local watcher = CreateFrame("Frame")

local function watch()
    local P, E = C_AddOnProfiler, Enum.AddOnProfilerMetric
    local ok, last = pcall(P.GetAddOnMetric, ns.NAME, E.LastTime)
    -- The client's "last frame" and our tally can be one tick apart (timers
    -- may run after this script in the same frame), so the hitch is charged
    -- to whichever of the last two ticks measured more.
    if ok and type(last) == "number" and last >= HITCH_MS and #hitches < MAX_HITCHES then
        local sum, top, topMs = frameSum, frameTop, frameTopMs
        if prevSum > sum then sum, top, topMs = prevSum, prevTop, prevTopMs end
        hitches[#hitches + 1] = { at = clock(), ms = last, sum = sum,
            top = top, topMs = topMs, combat = InCombatLockdown() }
    end
    prevSum, prevTop, prevTopMs = frameSum, frameTop, frameTopMs
    frameSum, frameTop, frameTopMs = 0, nil, 0
end

-- The addon's whole memory, in KB; nil when the client does not answer.
local function addonKB()
    pcall(UpdateAddOnMemoryUsage)
    local ok, kb = pcall(GetAddOnMemoryUsage, ns.NAME)
    return ok and type(kb) == "number" and kb or nil
end
local startKB

-- For hand-instrumenting anything the dispatch and ticker do not cover.
-- Both halves no-op while profiling is off.
function ns.Prof.Begin()
    if not active then return nil end
    return clock()
end

function ns.Prof.End(label, t0)
    if not active or not t0 then return end
    ns.Prof.Record(label, clock() - t0)
end

function ns.Prof.Reset()
    data = {}
    hitches = {}
    startedAt = clock()
    startKB = addonKB()
end

function ns.Prof.SetActive(on)
    on = on and true or false
    if on == active then return end
    active = on
    if on then ns.Prof.Reset() end
    if ns.SetEventProfiling  then ns:SetEventProfiling(on)  end
    if ns.SetTickerProfiling then ns:SetTickerProfiling(on) end
    local P = _G.C_AddOnProfiler
    watcher:SetScript("OnUpdate", (on and P and P.GetAddOnMetric) and watch or nil)
end

function ns.Prof.IsActive() return active end

local sorted = {}
function ns.Prof.Report()
    wipe(sorted)
    local total = 0
    for label, d in pairs(data) do
        sorted[#sorted + 1] = { label = label, d = d }
        total = total + d.ms
    end
    if #sorted == 0 then
        ns:Print(L["Nothing measured yet: no module event handler or ticker has run since measuring started. With only the framework modules loaded that is expected."])
        return
    end
    table.sort(sorted, function(a, b) return a.d.ms > b.d.ms end)

    -- Wall clock since the last reset, so the numbers can be read as a share of
    -- real time rather than as an unanchored sum. The stopwatch is shared with
    -- every other addon, so another one calling debugprofilestart mid-run can
    -- push this negative -- show 0 rather than a nonsense duration.
    local span = clock() - startedAt
    if span < 0 then span = 0 end
    ns:Print(L["Measured over %.1f s -- %.1f ms total, %.2f%% of it ours:"],
        span / 1000, total, span > 0 and (total / span * 100) or 0)
    local nowKB = addonKB()
    if nowKB and startKB then
        ns:Print(L["Memory: %.0f KB now, %.0f KB at the start."], nowKB, startKB)
    end
    -- The client's own numbers cover everything, also what the dispatch does
    -- not see (OnUpdate scripts, hooks, timers of our frames).
    local P, E = _G.C_AddOnProfiler, _G.Enum and _G.Enum.AddOnProfilerMetric
    if P and E and P.GetAddOnMetric then
        local ok1, avg = pcall(P.GetAddOnMetric, ns.NAME, E.RecentAverageTime)
        local ok2, peak = pcall(P.GetAddOnMetric, ns.NAME, E.PeakTime)
        if ok1 and ok2 and type(avg) == "number" and type(peak) == "number" then
            ns:Print(L["Client: %.3f ms per frame on average, peak %.1f ms."], avg, peak)
        end
        -- How often a frame of ours went over 10 / 50 / 100 ms in this
        -- session: one hitch at login reads very differently from one a minute.
        local ok3, c10 = pcall(P.GetAddOnMetric, ns.NAME, E.CountTimeOver10Ms)
        local ok4, c50 = pcall(P.GetAddOnMetric, ns.NAME, E.CountTimeOver50Ms)
        local ok5, c100 = pcall(P.GetAddOnMetric, ns.NAME, E.CountTimeOver100Ms)
        if ok3 and ok4 and ok5 and type(c10) == "number" and type(c50) == "number" and type(c100) == "number" then
            ns:Print(L["Frames over 10 / 50 / 100 ms this session: %d / %d / %d."], c10, c50, c100)
        end
    end
    for i = 1, math.min(#sorted, 20) do
        local e = sorted[i]
        local line = string.format("  %-22s %7.1f ms  %6d x  peak %.2f ms  %7.0f KB",
            e.label, e.d.ms, e.d.calls, e.d.peak, e.d.kb)
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. line .. "|r")
        -- the chat print above is not captured; the diag log keeps the table
        if ns.Diag then ns.Diag.Record(line) end
    end
    if #hitches > 0 then
        ns:Print(L["Hitches of %d ms or more: %d. Measured part and its biggest piece:"], HITCH_MS, #hitches)
        for i = 1, math.min(#hitches, 15) do
            local h = hitches[i]
            local line = string.format("  +%6.1f s  %6.1f ms  measured %5.1f ms  %s%s",
                (h.at - startedAt) / 1000, h.ms, h.sum,
                h.top and string.format("%s %.1f ms", h.top, h.topMs) or "-",
                h.combat and "  [combat]" or "")
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8080" .. line .. "|r")
            if ns.Diag then ns.Diag.Record(line) end
        end
    end
end

ns:RegisterSlash({ key = "PROFILER", commands = { "/vfuiprof" },
    desc = "Measure which of our modules cost the most time in their event handlers and tickers.",
    note = "Only our own modules are billed; a module that registers no events shows nothing.",
})
ns.Slash.PROFILER = function(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "off" then
        -- Print BEFORE stopping. Switching off is the natural thing to do once
        -- you have the sample you wanted, and turning it back on resets the
        -- numbers -- so without this the reading is simply gone.
        ns.Prof.Report()
        ns.Prof.SetActive(false)
        ns:Print(L["Measurement off."])
    elseif cmd == "report" or cmd == "show" then
        ns.Prof.Report()
    elseif cmd == "reset" then
        ns.Prof.Reset()
        ns:Print(L["Measurement reset."])
    elseif cmd == "" and ns.Prof.IsActive() then
        ns.Prof.Report()
    else
        ns.Prof.SetActive(true)
        ns:Print(L["Measurement on. Play, then type /vfuiprof again to read it."])
    end
end
