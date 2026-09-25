-- VuloForeverUI / Modules / QoL / Flight
--
-- How long this flight still takes.
--
-- THE CLIENT DOES NOT KNOW, SO THE BAR LEARNS -- AND ESTIMATES UNTIL IT HAS
--
-- Nothing in the API says how long a taxi ride lasts. The best source is the
-- last time you flew the same route, so every flight is measured and
-- remembered, and a known route fills against its own time.
--
-- A route flown for the first time is ESTIMATED: the taxi map knows the hops
-- the ride takes, their length in yards follows from the map's world size, and
-- that divided by the flight speed is the time. The speed itself is learned --
-- every landing on a measured route corrects it a little -- so the estimate
-- gets better the more you fly. An estimate is shown with a "~" in front.
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
local startedAt, routeKey, routeLabel, expected, estimated, routeYards
local waitForTaxi       -- defined with the flight code below; the click hook needs it
local editPreview      -- defined with the preview at the bottom; the mover needs it
local editing = false  -- our edit mode is open

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
    if g then g.qolFlightTimes = {}; g.qolFlightSpeed = nil end
end

-- Yards a second on a flight path: a first guess, then whatever the rides
-- measured say. Kept beside the learned times, account-wide.
local DEFAULT_SPEED = 32

local function speed()
    local g = ns.db and ns.db.global
    local v = g and tonumber(g.qolFlightSpeed)
    return (v and v > 5) and v or DEFAULT_SPEED
end

local function learnSpeed(yards, seconds)
    local g = ns.db and ns.db.global
    if not (g and yards and yards > 0 and seconds and seconds >= 5) then return end
    local sample = yards / seconds
    -- A wild sample is a ride that was not what the map said; it teaches nothing.
    if sample < 10 or sample > 120 then return end
    local old = tonumber(g.qolFlightSpeed)
    g.qolFlightSpeed = old and (old * 0.7 + sample * 0.3) or sample
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

-- The ride's length in yards: every hop the taxi map draws for this
-- destination, measured on the map and scaled by the map's size in the world.
-- Read at the click, while the map is still open; nil when anything is missing.
local function routeLength(slot)
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local w, h
    if mapID and C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
    local hops = GetNumRoutes and GetNumRoutes(slot)
    if not (w and h and w > 0 and h > 0 and hops and hops > 0) then return nil end
    local yards = 0
    for i = 1, hops do
        local sx, sy = TaxiGetSrcX(slot, i), TaxiGetSrcY(slot, i)
        local dx, dy = TaxiGetDestX(slot, i), TaxiGetDestY(slot, i)
        if not (sx and sy and dx and dy) then return nil end
        yards = yards + math.sqrt(((dx - sx) * w) ^ 2 + ((dy - sy) * h) ^ 2)
    end
    return yards > 0 and yards or nil
end

local function onTakeTaxiNode(slot)
    -- The hook cannot be taken off again: with the feature (or the module)
    -- off it does nothing at all.
    local d = db()
    if not (QoL.mod.active and (d.showBar or d.chat)) then return end
    local from = firstLine(currentNodeName())
    local to   = firstLine(TaxiNodeName and TaxiNodeName(slot))
    if not (from and to) then routeKey, routeLabel, routeYards = nil, nil, nil; return end
    routeKey   = from .. " -> " .. to
    routeLabel = to
    local ok, yards = pcall(routeLength, slot)
    routeYards = ok and yards or nil
    waitForTaxi()
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

    -- The texts and the border on a frame of their own ABOVE the fill. The
    -- fill is a child frame, and a child draws over every layer of its parent:
    -- text on the bar itself sat under the fill and read washed out.
    local top = CreateFrame("Frame", nil, bar)
    top:SetAllPoints(bar)
    top:SetFrameLevel(fill:GetFrameLevel() + 2)
    bar.top = top

    bar.edges = ns.MakeEdges(top, "OVERLAY")
    bar.label = top:CreateFontString(nil, "OVERLAY")
    bar.time = top:CreateFontString(nil, "OVERLAY")

    bar.mover = ns:CreateMover(bar, {
        key      = "qol_flight",
        label    = L["Flight time"],
        db       = db(),
        module   = "qol",
        width    = d.width or 240,
        height   = d.height or 18,
        scalable = true,
        -- The bar is hidden between flights, and its mover with it: while our
        -- edit mode is open it shows an example ride, so there is a box to drag.
        editPreview = function(on) editPreview(on) end,
    })
    ns:ApplyMover(bar.mover)
    return bar
end

-- Where a text can sit: inside the bar at one of three points, or above it.
local TEXT_POS = {
    left       = { "LEFT", "LEFT", 4, 0, "LEFT" },
    center     = { "CENTER", "CENTER", 0, 0, "CENTER" },
    right      = { "RIGHT", "RIGHT", -4, 0, "RIGHT" },
    aboveLeft  = { "BOTTOMLEFT", "TOPLEFT", 0, 2, "LEFT" },
    aboveRight = { "BOTTOMRIGHT", "TOPRIGHT", 0, 2, "RIGHT" },
}

local function placeText(fs, pos, x, y)
    local p = TEXT_POS[pos]
    fs:ClearAllPoints()
    if not p then fs:Hide(); return end        -- "none"
    fs:SetPoint(p[1], bar, p[2], p[3] + (x or 0), p[4] + (y or 0))
    fs:SetJustifyH(p[5])
    fs:Show()
end

local function style()
    local d = db()
    build()
    bar:SetSize(d.width, d.height)
    bar.fill:SetStatusBarTexture(ns.MediaStatusbar(d.texture))
    local c = ns.COLORS.accent
    bar.fill:SetStatusBarColor(c.r, c.g, c.b, 0.85)

    local bc = d.borderColor or { r = 0, g = 0, b = 0, a = 0.8 }
    ns.LayoutEdges(bar.edges, bar, d.borderSize or 1, bc.r, bc.g, bc.b, bc.a or 0.8, 0)

    -- "" and 0 follow the module font and the bar height, as the bar always did.
    local font = (type(d.font) == "string" and d.font ~= "") and ns.MediaFont(d.font) or QoL.Font()
    local size = (d.fontSize or 0) > 0 and d.fontSize or math.max(8, math.floor(d.height * 0.62))
    bar.label:SetFont(font, size, QoL.Outline())
    bar.time:SetFont(font, size, QoL.Outline())
    placeText(bar.label, d.labelPos or "left", d.labelX, d.labelY)
    placeText(bar.time, d.timePos or "right", d.timeX, d.timeY)
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

local endFlight

local function tick()
    if not startedAt then return end
    -- The landing, seen from here as well: the event for it is the same one
    -- a stun or a vehicle sends, and a missed one left the bar up for good.
    if UnitOnTaxi and not UnitOnTaxi("player") then endFlight(); return end
    if not (bar and bar:IsShown()) then return end
    local flown = GetTime() - startedAt
    if expected and expected > 0 then
        -- Time flown against the whole ride, and the bar filling with it. An
        -- estimate says so with its "~"; one that ran short simply stays full.
        bar.fill:SetValue(math.min(1, flown / expected))
        bar.time:SetText(clock(flown) .. " / " .. (estimated and "~" or "") .. clock(expected))
    else
        -- No route to go by (a reload mid-flight): only what is known, the
        -- time in the air so far.
        bar.fill:SetValue(0)
        bar.time:SetText(clock(flown))
    end
end

-- ----------------------------------------------------------- flight --

local function startFlight()
    if startedAt or not (UnitOnTaxi and UnitOnTaxi("player")) then return end
    startedAt = GetTime()
    expected  = routeKey and tonumber(learned()[routeKey]) or nil
    estimated = false
    if not expected and routeYards then
        expected, estimated = routeYards / speed(), true
    end

    if db().showBar then
        style()
        bar.label:SetText(routeLabel or L["In flight"])
        bar.fill:SetValue(0)
        bar:Show()
    end
    -- Runs with the bar off too: it is also what notices the landing.
    if ticker then ns:CancelTicker(ticker) end
    ticker = ns:AddTicker(0.1, tick, nil, "qol.flight")
    tick()
end

-- THE RIDE STARTS A MOMENT AFTER THE CLICK. The client takes control away as
-- the destination is clicked, and only a little later is the player on the
-- taxi -- so asking UnitOnTaxi at PLAYER_CONTROL_LOST answered no, and the bar
-- never came up. Every sign of a ride starting (the click, the map closing,
-- control going) now starts a short watch instead, which begins the flight
-- the moment the client says the player is on the taxi.
local waiter, waited
local function stopWaiting()
    if waiter then ns:CancelTicker(waiter); waiter = nil end
end

function waitForTaxi()
    if startedAt then return end
    waited = 0
    if waiter then return end
    waiter = ns:AddTicker(0.2, function()
        waited = waited + 0.2
        if UnitOnTaxi and UnitOnTaxi("player") then
            stopWaiting()
            startFlight()
        elseif waited >= 6 then
            -- the click never became a ride: its route must not stick to the
            -- next one that starts without a click (a scripted taxi)
            stopWaiting()
            routeKey, routeLabel, expected, estimated, routeYards = nil, nil, nil, false, nil
        end
    end, nil, "qol.flight.wait")
end

function endFlight()
    if not startedAt then return end
    -- Still airborne: this was a control change, not a landing.
    if UnitOnTaxi and UnitOnTaxi("player") then return end

    local flown = GetTime() - startedAt
    startedAt = nil
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if bar then bar:Hide() end
    -- Landed with our edit mode open: the example comes back, box and all.
    if editing then editPreview(true) end

    -- Under five seconds is not a flight; that is the ride being cut short.
    if routeKey and flown >= 5 then
        learned()[routeKey] = flown
        learnSpeed(routeYards, flown)
    end
    if db().chat and flown >= 5 then
        ns:Print(L["Flight took %s."], clock(flown))
    end
    routeKey, routeLabel, expected, estimated, routeYards = nil, nil, nil, false, nil
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
    QoL.SyncEvent(on, "PLAYER_CONTROL_LOST",   waitForTaxi)
    QoL.SyncEvent(on, "TAXIMAP_CLOSED",        waitForTaxi)
    QoL.SyncEvent(on, "PLAYER_CONTROL_GAINED", endFlight)
    -- Already in the air (a reload mid-flight): the ride is picked up, with
    -- no route to count down to.
    if on and not startedAt then startFlight() end

    if not d.showBar then
        -- The ticker stays while a ride is on: it also notices the landing.
        if bar then bar:Hide() end
        return
    end
    style()
    -- Enabled mid-flight: pick the ride up rather than waiting for the next one.
    if startedAt then bar:Show(); tick() end
end

function Flight.Disable()
    QoL.SyncEvent(false, "PLAYER_CONTROL_LOST",   waitForTaxi)
    QoL.SyncEvent(false, "TAXIMAP_CLOSED",        waitForTaxi)
    QoL.SyncEvent(false, "PLAYER_CONTROL_GAINED", endFlight)
    stopWaiting()
    startedAt = nil
    routeKey, routeLabel, expected, estimated, routeYards = nil, nil, nil, false, nil
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if bar then bar:Hide() end
end

-- An example ride on the bar: for the options page's sliders and for our
-- edit mode. A real flight always wins -- the example never paints over one.

local function showExample()
    style()
    bar.label:SetText(L["Flight time"])
    bar.time:SetText("0:36 / 1:30")
    bar.fill:SetValue(0.4)
    bar:Show()
end

function editPreview(on)
    editing = on and true or false
    if startedAt or not db().showBar then return end
    if editing then showExample() elseif bar then bar:Hide() end
end

-- The preview the options page shows, so the width and height sliders can be
-- judged while they are dragged instead of on the next flight.
function Flight.Preview()
    if not db().showBar or startedAt then return end
    showExample()
    C_Timer.After(4, function()
        if not (startedAt or editing) and bar then bar:Hide() end
    end)
end
