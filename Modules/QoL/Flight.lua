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
--
-- THE ROUTE UNDER THE BAR
--
-- The taxi map draws every hop of the ride, so at the click the stops are known
-- in order, with where they sit on the map. A strip under the bar lists them,
-- the last one passed on top, and scrolls one row on each time a stop goes by.
-- Nothing tells an addon that a stop was passed: the player's position on the
-- taxi map says it (past the stop, measured along the hop), and without a
-- position the ride's time against each stop's share of the length does.
--
-- LANDING EARLY
--
-- The same request the client's own leave button sends while on a taxi: the
-- ride ends at the next stop. Such a ride is shorter than its route, so it
-- teaches the learned times nothing.
local _, ns = ...
local L  = ns.L

local QoL = ns.QoL
local Flight = QoL.RegisterPart("flight", {})
QoL.Flight = Flight

local bar, ticker
local startedAt, routeKey, routeLabel, expected, estimated, routeYards
local stops, taxiMap, mapW, mapH -- the route at the click: { name, x, y, at } per stop
local passed = 1                  -- stops behind us; the first is where the ride began
local landing = false             -- early landing requested
local waitForTaxi       -- defined with the flight code below; the click hook needs it
local editPreview      -- defined with the preview at the bottom; the mover needs it
local showExample      -- the same; Refresh redraws the example while it is up
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

-- The ride as the taxi map draws it, read at the click while the map is still
-- open: its length in yards (every hop measured on the map and scaled by the
-- map's size in the world) and its stops in order. A stop's `at` is its share
-- of the length, the hop count standing in when the map has no size.
local function readRoute(slot)
    local mapID = GetTaxiMapID and GetTaxiMapID()
    local w, h
    if mapID and C_Map and C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(mapID) end
    local hops = GetNumRoutes and GetNumRoutes(slot)
    if not (hops and hops > 0) then return nil end
    local sized = w and h and w > 0 and h > 0
    local list, yards = {}, 0
    local function nodeName(i, src)
        local node = TaxiGetNodeSlot and TaxiGetNodeSlot(slot, i, src)
        return node and firstLine(TaxiNodeName(node)) or "?"
    end
    for i = 1, hops do
        local sx, sy = TaxiGetSrcX(slot, i), TaxiGetSrcY(slot, i)
        local dx, dy = TaxiGetDestX(slot, i), TaxiGetDestY(slot, i)
        if i == 1 then list[1] = { name = nodeName(1, true), x = sx, y = sy, at = 0 } end
        if sized and sx and sy and dx and dy then
            yards = yards + math.sqrt(((dx - sx) * w) ^ 2 + ((dy - sy) * h) ^ 2)
        else
            sized = false
        end
        list[i + 1] = { name = nodeName(i, false), x = dx, y = dy, at = yards }
    end
    if not (sized and yards > 0) then yards = nil end
    for i, stop in ipairs(list) do
        stop.at = yards and stop.at / yards or (i - 1) / hops
    end
    return yards, list, mapID, sized and w or nil, sized and h or nil
end

local function onTakeTaxiNode(slot)
    -- The hook cannot be taken off again: with the feature (or the module)
    -- off it does nothing at all.
    local d = db()
    if not (QoL.mod.active and (d.showBar or d.chat)) then return end
    local from = firstLine(currentNodeName())
    local to   = firstLine(TaxiNodeName and TaxiNodeName(slot))
    if not (from and to) then routeKey, routeLabel, routeYards, stops = nil, nil, nil, nil; return end
    routeKey   = from .. " -> " .. to
    routeLabel = to
    local ok, yards, list, mapID, w, h = pcall(readRoute, slot)
    if ok then
        routeYards, stops, taxiMap, mapW, mapH = yards, list, mapID, w, h
    else
        routeYards, stops = nil, nil
    end
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

    -- The route: rows on a strip that slides up inside a clipped window.
    local route = CreateFrame("Frame", nil, bar)
    route:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
    route:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", 0, -2)
    route:SetClipsChildren(true)
    local rbg = route:CreateTexture(nil, "BACKGROUND")
    rbg:SetAllPoints(route)
    rbg:SetColorTexture(0, 0, 0, 0.4)
    route.strip = CreateFrame("Frame", nil, route)
    route.strip:SetPoint("TOPLEFT", route, "TOPLEFT", 0, 0)
    route.strip:SetPoint("RIGHT", route, "RIGHT", 0, 0)
    route.strip:SetHeight(1)
    route.rows = {}
    route.scroll, route.target = 0, 0
    bar.route = route

    -- Land at the next stop: the client's own leave button art.
    local land = CreateFrame("Button", nil, bar)
    land:SetPoint("LEFT", bar, "RIGHT", 3, 0)
    land:SetNormalTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Up")
    land:SetPushedTexture("Interface\\Vehicles\\UI-Vehicles-Button-Exit-Down")
    land:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    for _, t in ipairs({ land:GetNormalTexture(), land:GetPushedTexture() }) do
        t:SetTexCoord(0.140625, 0.859375, 0.140625, 0.859375)
    end
    land:SetScript("OnClick", function(self)
        if not (UnitOnTaxi and UnitOnTaxi("player")) or landing then return end
        -- marked as landing early by the hook on the request (Flight.Apply),
        -- which sees the client's own leave button as well
        TaxiRequestEarlyLanding()
    end)
    land:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, landing and L["Landing at the next stop"] or TAXI_CANCEL)
        if not landing then
            GameTooltip:AddLine(TAXI_CANCEL_DESCRIPTION, 1, 0.82, 0, true)
        end
        GameTooltip:Show()
    end)
    land:SetScript("OnLeave", GameTooltip_Hide)
    -- A disabled button gets no OnEnter; the motion still should.
    land:SetMotionScriptsWhileDisabled(true)
    bar.land = land

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

    bar.land:SetSize(d.height + 4, d.height + 4)
    bar.route.font, bar.route.size = font, math.max(8, size - 1)
    bar.route.rowH = bar.route.size + 5
    bar.route:SetHeight(bar.route.rowH * (d.routeRows or 3) + 2)
    for _, row in ipairs(bar.route.rows) do
        row.name:SetFont(font, bar.route.size, QoL.Outline())
        row.eta:SetFont(font, bar.route.size, QoL.Outline())
    end
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

-- ------------------------------------------------------------ route --

local function routeRow(i)
    local r = bar.route
    local row = r.rows[i]
    if not row then
        row = {}
        row.name = r.strip:CreateFontString(nil, "OVERLAY")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.eta = r.strip:CreateFontString(nil, "OVERLAY")
        row.eta:SetJustifyH("RIGHT")
        r.rows[i] = row
    end
    row.name:SetFont(r.font, r.size, QoL.Outline())
    row.eta:SetFont(r.font, r.size, QoL.Outline())
    row.name:ClearAllPoints()
    row.eta:ClearAllPoints()
    local y = -(i - 1) * r.rowH - 1
    row.name:SetPoint("TOPLEFT", r.strip, "TOPLEFT", 4, y)
    row.name:SetPoint("RIGHT", row.eta, "LEFT", -4, 0)
    row.eta:SetPoint("TOPRIGHT", r.strip, "TOPRIGHT", -4, y)
    row.name:SetHeight(r.rowH)
    row.eta:SetHeight(r.rowH)
    row.name:Show(); row.eta:Show()
    return row
end

-- The strip glides to its row instead of jumping, so a stop going by is seen.
local function glide(self, elapsed)
    local diff = self.target - self.scroll
    if math.abs(diff) < 0.5 then
        self.scroll = self.target
        self:SetScript("OnUpdate", nil)
    else
        self.scroll = self.scroll + diff * math.min(1, elapsed * 8)
    end
    self.strip:SetPoint("TOPLEFT", self, "TOPLEFT", 0, self.scroll)
end

local function scrollTo(index, instant)
    local r = bar.route
    r.target = (index - 1) * r.rowH
    if instant then
        r.scroll = r.target
        r.strip:SetPoint("TOPLEFT", r, "TOPLEFT", 0, r.scroll)
        r:SetScript("OnUpdate", nil)
    elseif r.scroll ~= r.target then
        r:SetScript("OnUpdate", glide)
    end
end

-- Every row's text and colour: passed grey, the next stop bright with the
-- time until it, the ones after it plain -- or struck from the ride once an
-- early landing has been asked for.
local function drawRoute(list, at, flown, total, guess)
    local r = bar.route
    for i, stop in ipairs(list) do
        local row = routeRow(i)
        row.name:SetText(stop.name)
        local eta = ""
        if i <= at then
            row.name:SetTextColor(0.5, 0.5, 0.5)
        elseif landing and i > at + 1 then
            row.name:SetTextColor(0.4, 0.25, 0.25)
        elseif i == at + 1 then
            local c = ns.COLORS.accent
            row.name:SetTextColor(c.r, c.g, c.b)
        else
            row.name:SetTextColor(0.85, 0.85, 0.85)
        end
        if i > at and total and total > 0 and not (landing and i > at + 1) then
            eta = (guess and "~" or "") .. clock(total * stop.at - flown)
        end
        row.eta:SetText(eta)
        row.eta:SetTextColor(0.75, 0.75, 0.75)
    end
    for i = #list + 1, #r.rows do
        r.rows[i].name:Hide(); r.rows[i].eta:Hide()
    end
    r.strip:SetHeight(math.max(1, #list * r.rowH))
end

-- Past the next stop? Measured along the hop on the taxi map: the player's
-- position projected onto the line between the two stops. nil when there is
-- no position to go by.
local function pastByPosition(from, to)
    if not (taxiMap and from.x and from.y and to.x and to.y
            and C_Map and C_Map.GetPlayerMapPosition) then return nil end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, taxiMap, "player")
    if not ok or type(pos) ~= "table" then return nil end
    local px, py = pos:GetXY()
    if ns.IsSecret(px) or ns.IsSecret(py) or type(px) ~= "number" or type(py) ~= "number" then return nil end
    local sw, sh = mapW or 1, mapH or 1
    local vx, vy = (to.x - from.x) * sw, (to.y - from.y) * sh
    local len2 = vx * vx + vy * vy
    if len2 <= 0 then return true end
    local t = ((px - from.x) * sw * vx + (py - from.y) * sh * vy) / len2
    return t >= 0.98
end

local function advance(flown)
    -- The last stop is the landing, and the landing ends the ride.
    if not stops or passed >= #stops - 1 then return false end
    local from, to = stops[passed], stops[passed + 1]
    -- The position decides; the time is the fallback without one, and a
    -- second opinion with one: a path that bends away from the straight hop
    -- may never reach its end on the map, and the strip must not stick.
    local byTime = expected and expected > 0 and flown / expected or nil
    local past = pastByPosition(from, to)
    if past == nil then
        past = byTime ~= nil and byTime >= to.at
    elseif not past and byTime then
        past = byTime >= to.at + 0.08
    end
    if past then passed = passed + 1 end
    return past
end

-- Landing early only means something while a stop lies before the last one:
-- on the last hop the ride ends where it would anyway. Without a route (a
-- reload mid-flight) there is no telling, so the button stays.
local function canLandEarly()
    return not landing and (stops == nil or passed + 1 < #stops)
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
    if bar.route:IsShown() and stops then
        if advance(flown) then
            scrollTo(passed)
            -- the last hop begun: nothing left to land early at
            if not canLandEarly() then Flight.Refresh() end
        end
        drawRoute(stops, passed, flown, expected, estimated)
    end
end

-- The bar's parts that follow the settings and the ride: the route strip and
-- the landing button. Called on every start and whenever the options change.
function Flight.Refresh()
    if not bar then return end
    -- No ride: the example (options preview or our edit mode) is drawn again
    -- with the new settings rather than losing its strip and button.
    if not startedAt then
        if bar:IsShown() then showExample() end
        return
    end
    local d = db()
    bar.route:SetShown(d.showRoute and stops ~= nil and #stops > 1)
    bar.land:SetShown(d.landButton)
    local can = canLandEarly()
    bar.land:SetEnabled(can)
    bar.land:GetNormalTexture():SetDesaturated(not can)
    if landing and stops and stops[passed + 1] then
        bar.label:SetText(stops[passed + 1].name)
    end
    tick()
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
    passed, landing = 1, false
    -- Runs with the bar off too: it is also what notices the landing.
    if ticker then ns:CancelTicker(ticker) end
    ticker = ns:AddTicker(0.1, tick, nil, "qol.flight")
    if bar then
        scrollTo(1, true)
        Flight.Refresh()
    else
        tick()
    end
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
            stops = nil
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

    -- Under five seconds is not a flight; that is the ride being cut short.
    -- A ride landed early is shorter than its route and teaches nothing.
    if routeKey and flown >= 5 and not landing then
        learned()[routeKey] = flown
        learnSpeed(routeYards, flown)
    end
    if db().chat and flown >= 5 then
        ns:Print(L["Flight took %s."], clock(flown))
    end
    routeKey, routeLabel, expected, estimated, routeYards = nil, nil, nil, false, nil
    stops, passed, landing = nil, 1, false
    -- Landed with our edit mode open: the example comes back, box and all --
    -- after the reset, or it would be drawn with this ride's struck stops.
    if editing then editPreview(true) end
end

-- ------------------------------------------------------------ apply --

local hooked

function Flight.Apply()
    local d = db()
    local on = d.showBar or d.chat

    if on and not hooked and _G.TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", onTakeTaxiNode)
        -- An early landing, from our button or the client's leave button:
        -- the ride ends at the next stop and teaches the times nothing.
        if _G.TaxiRequestEarlyLanding then
            hooksecurefunc("TaxiRequestEarlyLanding", function()
                if startedAt and not landing then
                    landing = true
                    Flight.Refresh()
                end
            end)
        end
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
    if startedAt then bar:Show() end
    Flight.Refresh()
end

function Flight.Disable()
    QoL.SyncEvent(false, "PLAYER_CONTROL_LOST",   waitForTaxi)
    QoL.SyncEvent(false, "TAXIMAP_CLOSED",        waitForTaxi)
    QoL.SyncEvent(false, "PLAYER_CONTROL_GAINED", endFlight)
    stopWaiting()
    startedAt = nil
    routeKey, routeLabel, expected, estimated, routeYards = nil, nil, nil, false, nil
    stops, passed, landing = nil, 1, false
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if bar then bar:Hide() end
end

-- An example ride on the bar: for the options page's sliders and for our
-- edit mode. A real flight always wins -- the example never paints over one.

function showExample()
    style()
    bar.label:SetText(L["Flight time"])
    bar.time:SetText("0:36 / 1:30")
    bar.fill:SetValue(0.4)
    local d = db()
    bar.land:SetShown(d.landButton)
    bar.land:SetEnabled(true)
    bar.land:GetNormalTexture():SetDesaturated(false)
    bar.route:SetShown(d.showRoute)
    if d.showRoute then
        local list = {}
        for i = 1, 5 do list[i] = { name = string.format(L["Stop %d"], i), at = (i - 1) / 4 } end
        drawRoute(list, 2, 36, 90, false)
        scrollTo(2, true)
    end
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
