-- VuloForeverUI / Modules / ResourceBars / Swing
--
-- Three swing timers: main hand, off hand, ranged, each its own bar.
--
-- THIS EXISTS BECAUSE THE COMBAT LOG DOES NOT
--
-- On every other client a swing timer is built from COMBAT_LOG_EVENT_UNFILTERED.
-- Here that event is restricted and CombatLogGetCurrentEventInfo is nil, so the
-- usual design is not merely worse, it is impossible. The client replaces it
-- with an event of its own: PLAYER_SWING(swingDuration, swingType), plus
-- PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange) for the reach.
--
-- The duration arrives as the client's argument and is handed straight to
-- StatusBar:SetTimerDuration when it is an object -- the same route the cast
-- bar takes. Should it arrive as a plain NUMBER instead, it is used as one,
-- but only while it is readable; a secret number cannot even be compared with
-- zero, let alone counted down.
local _, ns = ...
local RB = ns.RB
local L  = ns.L

local Swing = {}
RB.Swing = Swing

local ELAPSED   = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0

local ST = Enum.PlayerSwingType
local BY_TYPE = {
    [(ST and ST.MainHand) or 0] = "swingMain",
    [(ST and ST.OffHand)  or 1] = "swingOff",
    [(ST and ST.Ranged)   or 2] = "swingRanged",
}
Swing.BY_TYPE = BY_TYPE

local LABELS   -- built lazily: a locale key read at file scope bakes the language

local function labelFor(key)
    if not LABELS then
        LABELS = {
            swingMain   = L["Main hand"],
            swingOff    = L["Off hand"],
            swingRanged = L["Ranged"],
        }
    end
    return LABELS[key]
end

-- ---------------------------------------------------------------- one swing --

local function hideLater(key, duration)
    local frame = RB.frames[key]
    if not frame then return end
    -- A readable length lets the bar take itself off screen when the swing is
    -- over. An unreadable one does not, and rather than guess a length the bar
    -- stays until the next swing or the end of the fight -- which is when a
    -- swing timer stops being interesting anyway.
    frame.hideToken = (frame.hideToken or 0) + 1
    local token = frame.hideToken

    local seconds
    if ns.CanRead(duration) and type(duration) == "number" then
        seconds = duration
    elseif type(duration) == "table" and duration.GetRemainingDuration then
        -- The object drives the fill without ever being read, but the LENGTH
        -- of a swing is not combat data the client hides, so asking is allowed
        -- -- and it is the only thing that takes the bar off screen again
        -- between the last swing of a fight and the end of that fight.
        local ok, rem = pcall(duration.GetRemainingDuration, duration)
        if ok and ns.CanRead(rem) and type(rem) == "number" then seconds = rem end
    end
    if not (seconds and seconds > 0) then return end

    C_Timer.After(seconds, function()
        if frame.hideToken == token then RB.SetActive(key, false) end
    end)
end

function Swing.Start(swingType, duration)
    local key = BY_TYPE[swingType]
    if not key then return end
    local frame, bar = RB.frames[key], RB.Bar(key)
    if not (frame and bar and bar.enabled) then return end

    if type(duration) == "table" and frame.fill.SetTimerDuration then
        -- A duration object: the client runs the fill and we never see a time.
        -- Any hand-run fill from an earlier swing is dropped first, or the two
        -- would write the same bar every frame.
        frame:SetScript("OnUpdate", nil)
        frame.fill:SetTimerDuration(duration, IMMEDIATE, ELAPSED)
        if bar.rightText == "time" then
            ns:DurationText(frame, frame.right, duration)
        end
    elseif ns.CanRead(duration) and type(duration) == "number" and duration > 0 then
        frame.fill:SetMinMaxValues(0, duration)
        frame.fill:SetValue(0)
        frame.swingStart, frame.swingLength = GetTime(), duration
        frame:SetScript("OnUpdate", function(self)
            local done = GetTime() - (self.swingStart or 0)
            self.fill:SetValue(math.min(done, self.swingLength or 1))
            if self.right and RB.Bar(key).rightText == "time" then
                self.right:SetFormattedText("%.1f", math.max(0, (self.swingLength or 0) - done))
            end
        end)
    else
        -- Neither shape: show the bar full rather than a bar that lies about a
        -- time we do not have.
        frame.fill:SetMinMaxValues(0, 1)
        frame.fill:SetValue(1)
    end

    RB.SetLeftText(key, nil, labelFor(key))
    Swing.ApplyRangeColor(key)
    RB.SetActive(key, true)
    hideLater(key, duration)
end

-- ---------------------------------------------------------------- range --

-- Whether the target is within reach of this weapon. Both answers may be
-- secret, so both go through a fold: the colour is picked by the engine.
local range = {}

function Swing.SetRange(swingType, isInRange, checksRange)
    local key = BY_TYPE[swingType]
    if not key then return end
    range[key] = { inRange = isInRange, checks = checksRange }
    Swing.ApplyRangeColor(key)
end

function Swing.ApplyRangeColor(key)
    local frame, bar = RB.frames[key], RB.Bar(key)
    if not (frame and bar) then return end
    local fc = bar.fillColor
    local state = range[key]

    if not (bar.showRange and state and ns.Exists(state.inRange)) then
        frame.fill:SetStatusBarColor(fc.r, fc.g, fc.b)
        return
    end
    -- A weapon that does not check range is never out of it.
    if ns.CanRead(state.checks) and state.checks == false then
        frame.fill:SetStatusBarColor(fc.r, fc.g, fc.b)
        return
    end
    local oc = bar.outOfRangeColor
    frame.fill:SetStatusBarColor(ns.FoldColor(state.inRange, fc.r, fc.g, fc.b, oc.r, oc.g, oc.b))
end

-- ---------------------------------------------------------------- events --

function Swing.UpdateAll()
    for _, key in pairs(BY_TYPE) do
        local frame = RB.frames[key]
        if frame then
            RB.SetLeftText(key, nil, labelFor(key))
            Swing.ApplyRangeColor(key)
        end
    end
end

function Swing.Stop()
    for _, key in pairs(BY_TYPE) do
        local frame = RB.frames[key]
        if frame then
            ns:DurationText(frame, frame.right, nil)
        end
        RB.SetActive(key, false)
    end
end

function Swing.RegisterEvents(mod)
    mod:RegisterEvent("PLAYER_SWING", function(_, duration, swingType)
        Swing.Start(swingType, duration)
    end)
    mod:RegisterEvent("PLAYER_SWING_RANGE_UPDATE", function(_, swingType, isInRange, checksRange)
        Swing.SetRange(swingType, isInRange, checksRange)
    end)
    -- Out of combat nothing swings, so the three bars go away together --
    -- which is also the fallback for a duration we could not read a length
    -- from and therefore could not schedule a hide for.
    mod:RegisterEvent("PLAYER_REGEN_ENABLED", function() Swing.Stop() end)
end
