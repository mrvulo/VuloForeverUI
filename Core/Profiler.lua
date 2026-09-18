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

function ns.Prof.Record(label, ms)
    local d = data[label]
    if not d then d = { ms = 0, calls = 0, peak = 0 }; data[label] = d end
    d.ms = d.ms + ms
    d.calls = d.calls + 1
    if ms > d.peak then d.peak = ms end
end

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
    startedAt = clock()
end

function ns.Prof.SetActive(on)
    on = on and true or false
    if on == active then return end
    active = on
    if on then ns.Prof.Reset() end
    if ns.SetEventProfiling  then ns:SetEventProfiling(on)  end
    if ns.SetTickerProfiling then ns:SetTickerProfiling(on) end
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
    for i = 1, math.min(#sorted, 15) do
        local e = sorted[i]
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
            "  |cffffd100%-22s|r %7.1f ms  %6d x  |cff888888peak %.2f ms|r",
            e.label, e.d.ms, e.d.calls, e.d.peak))
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
