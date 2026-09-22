-- VuloForeverUI / Modules / QoL / Flight
--
-- How long this flight still takes.
--
-- THE CLIENT DOES NOT KNOW, SO THE BAR LEARNS
--
-- Nothing in the API says how long a taxi ride lasts. The only honest source is
-- the last time you flew the same route, so the first flight of a route is
-- measured and remembered, and every flight after it gets a bar that counts
-- down. An unknown route still gets a readout -- the time flown so far, with no
-- fill and no promise.
--
-- A route is "from node, to node", and the two are read at the moment you click
-- the destination: `TakeTaxiNode` is hooked for the destination, and the node
-- the client marks CURRENT is the departure. Both are names, not ids, because
-- a name survives the node list being renumbered between builds.
--
-- WHERE THE TIMES LIVE
--
-- In the account-wide store, not in the profile. A flight from Ironforge to
-- Menethil takes what it takes; that is a fact about the world, not a setting,
-- and a second character on the same account should not have to learn it again.
--
-- WHAT ENDS A FLIGHT
--
-- `PLAYER_CONTROL_GAINED` fires when you land -- and also when you are pulled
-- off a flight path or the ride is interrupted. Every end re-checks
-- `UnitOnTaxi` before it records anything, so an interrupted flight teaches the
-- bar nothing rather than teaching it a wrong number.
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local QoL = ns.QoL
local Flight = QoL.RegisterPart("flight", {})
QoL.Flight = Flight

local bar, ticker
local startedAt, routeKey, routeLabel, expected

local function db() return QoL.db().flight end

-- Learned times are world facts, so they live account-wide beside the other
-- account-wide values rather than in whichever profile happened to be active.
local function learned()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.qolFlightTimes) ~= "table" then g.qolFlightTimes = {} end
    return g.qolFlightTimes
end

function Flight.LearnedCount()
    local n = 0
    for _ in pairs(learned()) do n = n + 1 end
    return n
end

function Flight.Forget()
    local g = ns.db and ns.db.global
    if g then g.qolFlightTimes = {} end
end

-- ------------------------------------------------------------- route --

local function currentNodeName()
    local count = NumTaxiNodes and NumTaxiNodes() or 0
    for i = 1, count do
        if TaxiNodeGetType and TaxiNodeGetType(i) == "CURRENT" then
            return TaxiNodeName and TaxiNodeName(i)
        end
    end
    return nil
end

-- A node name carries its zone on a second line ("Thelsamar\nLoch Modan"); the
-- first line is the stop, and that is what makes a readable label.
local function firstLine(name)
    if type(name) ~= "string" then return nil end
    return (name:match("^([^\n]+)")) or name
end

local function onTakeTaxiNode(slot)
    local from = firstLine(currentNodeName())
    local to   = firstLine(TaxiNodeName and TaxiNodeName(slot))
    if not (from and to) then routeKey, routeLabel = nil, nil; return end
    routeKey   = from .. " -> " .. to
    routeLabel = to
end

-- -------------------------------------------------------------- bar --

local function build()
    if bar then return bar end
    local d = db()

    bar = CreateFrame("Frame", "VuloForeverUIFlightBar", UIParent)
    bar:SetSize(d.width or 240, d.height or 18)
    bar:SetFrameStrata("MEDIUM")
    bar:Hide()

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetColorTexture(0, 0, 0, 0.55)

    local fill = CreateFrame("StatusBar", nil, bar)
    fill:SetAllPoints(bar)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    bar.fill = fill

    bar.edges = ns.MakeEdges(bar, "OVERLAY")
    ns.LayoutEdges(bar.edges, bar, 1, 0, 0, 0, 0.8, 0)

    local left = bar:CreateFontString(nil, "OVERLAY")
    left:SetPoint("LEFT", bar, "LEFT", 4, 0)
    left:SetJustifyH("LEFT")
    bar.label = left

    local right = bar:CreateFontString(nil, "OVERLAY")
    right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    right:SetJustifyH("RIGHT")
    bar.time = right

    bar.mover = ns:CreateMover(bar, {
        key      = "qol_flight",
        label    = L["Flight time"],
        db       = db(),
        module   = "qol",
        width    = d.width or 240,
        height   = d.height or 18,
        scalable = true,
    })
    ns:ApplyMover(bar.mover)
    return bar
end

local function style()
    local d = db()
    build()
    bar:SetSize(d.width, d.height)
    bar.fill:SetStatusBarTexture(ns.MediaStatusbar(d.texture))
    local c = ns.COLORS.accent
    bar.fill:SetStatusBarColor(c.r, c.g, c.b, 0.85)
    local size = math.max(8, math.floor(d.height * 0.62))
    bar.label:SetFont(QoL.Font(), size, QoL.Outline())
    bar.time:SetFont(QoL.Font(), size, QoL.Outline())
    if bar.mover then
        bar.mover.opts.width, bar.mover.opts.height = d.width, d.height
        ns:RefreshMoverGeometry(bar.mover)
        ns:ApplyMover(bar.mover)
    end
end

local function clock(seconds)
    if seconds < 0 then seconds = 0 end
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function tick()
    if not (startedAt and bar) then return end
    local flown = GetTime() - startedAt
    if expected and expected > 0 then
        local left = expected - flown
        bar.fill:SetValue(math.min(1, flown / expected))
        bar.time:SetText(clock(left))
    else
        -- Nothing to count down to yet, so the bar says what it knows: how long
        -- you have been in the air. An empty bar that pretends to fill would be
        -- a guess dressed up as a measurement.
        bar.fill:SetValue(0)
        bar.time:SetText(clock(flown))
    end
end

-- ----------------------------------------------------------- flight --

local function startFlight()
    if not UnitOnTaxi or not UnitOnTaxi("player") then return end
    startedAt = GetTime()
    expected  = routeKey and tonumber(learned()[routeKey]) or nil

    if db().showBar then
        style()
        bar.label:SetText(routeLabel or L["In flight"])
        bar.fill:SetValue(0)
        bar:Show()
        if ticker then ns:CancelTicker(ticker) end
        ticker = ns:AddTicker(0.1, tick, nil, "qol.flight")
        tick()
    end
end

local function endFlight()
    if not startedAt then return end
    -- Still airborne: this was a control change, not a landing.
    if UnitOnTaxi and UnitOnTaxi("player") then return end

    local flown = GetTime() - startedAt
    startedAt = nil
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if bar then bar:Hide() end

    -- Under five seconds is not a flight; that is the ride being cut short.
    if routeKey and flown >= 5 then
        learned()[routeKey] = flown
    end
    if db().chat and flown >= 5 then
        ns:Print(L["Flight took %s."], clock(flown))
    end
    routeKey, routeLabel, expected = nil, nil, nil
end

-- ------------------------------------------------------------ apply --

local hooked

function Flight.Apply()
    local d = db()
    local on = d.showBar or d.chat

    if on and not hooked and _G.TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", onTakeTaxiNode)
        hooked = true
    end
    QoL.SyncEvent(on, "PLAYER_CONTROL_LOST",   startFlight)
    QoL.SyncEvent(on, "PLAYER_CONTROL_GAINED", endFlight)

    if not d.showBar then
        if bar then bar:Hide() end
        if ticker then ns:CancelTicker(ticker); ticker = nil end
        return
    end
    style()
    -- Enabled mid-flight: pick the ride up rather than waiting for the next one.
    if startedAt then bar:Show(); tick() end
end

function Flight.Disable()
    QoL.SyncEvent(false, "PLAYER_CONTROL_LOST",   startFlight)
    QoL.SyncEvent(false, "PLAYER_CONTROL_GAINED", endFlight)
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if bar then bar:Hide() end
end

-- The preview the options page shows, so the width and height sliders can be
-- judged while they are dragged instead of on the next flight.
function Flight.Preview()
    if not db().showBar then return end
    style()
    bar.label:SetText(L["Flight time"])
    bar.time:SetText("1:30")
    bar.fill:SetValue(0.4)
    bar:Show()
    C_Timer.After(4, function()
        if not startedAt and bar then bar:Hide() end
    end)
end
