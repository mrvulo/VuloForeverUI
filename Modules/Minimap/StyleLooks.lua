-- VuloForeverUI / Modules / Minimap / StyleLooks: the art, the pieces, the three looks and the queue eye
local _, ns = ...
local L = ns.L
local MM = ns.MM
local mod = MM.mod
local P = mod._style
local remember, restore = P.remember, P.restore
local rememberButtonArt, restoreButtonArt = P.rememberButtonArt, P.restoreButtonArt
local ours, region, hideOurs = P.ours, P.region, P.hideOurs

local CLASSIC_CLUSTER, CLASSIC_MAP = 192, 140

-- Masks are TEXTURE PATHS. The round one the client itself uses is an atlas,
-- which SetMaskTexture does take, but the classic look wants the old circular
-- alpha mask -- the same one portraits use.
local SQUARE_MASK  = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK   = "ui-hud-minimap-frame-generic-mask"
local CIRCLE_MASK  = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- UI-Minimap-Border is ONE sheet holding both the header bar and the ring, so
-- each piece has to be cut out of it. Drawing the whole file is what produced
-- the dark blob over the map on the first attempt.
local CLASSIC_SHEET = "Interface\\Minimap\\UI-Minimap-Border"
local SHEET_TOP  = { 0.25, 1, 0,     0.125 }   -- the header bar
local SHEET_RING = { 0.25, 1, 0.125, 0.875 }   -- the ring around the map
local COMPASS_RING  = "Interface\\Minimap\\CompassRing"
local COMPASS_NORTH = "Interface\\Minimap\\CompassNorthTag"
local TRACK_BORDER  = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MAP_BACKGROUND = "Interface\\Minimap\\UI-Minimap-Background"

-- The zoom buttons come as four states each. Confirmed present on 1.60.1
-- (/vfmmtex reports all thirteen classic files), so no fallback is needed.
local ZOOM_ART = {
    ZoomIn  = "Interface\\Minimap\\UI-Minimap-ZoomInButton-",
    ZoomOut = "Interface\\Minimap\\UI-Minimap-ZoomOutButton-",
}
local ZOOM_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
local CLOCK_PLATE   = "Interface\\TimeManager\\ClockBackground"
local CALENDAR_ART  = "Interface\\Calendar\\UI-Calendar-Button"

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
local function borderRGB()
    local db = mod.db
    if db.borderClassColor then
        local _, class = UnitClass("player")
        local c = class and ((ns.CLASS_COLORS and ns.CLASS_COLORS[class]) or RAID_CLASS_COLORS[class])
        if c then return c.r, c.g, c.b, db.borderColor.a or 1 end
    end
    local c = db.borderColor
    return c.r, c.g, c.b, c.a or 1
end

local function applyShape(round)
    if not Minimap.SetMaskTexture then return end
    pcall(Minimap.SetMaskTexture, Minimap, round and CIRCLE_MASK or SQUARE_MASK)
end

-- The zone name lives on a button in the cluster; its font string is where the
-- size has to land, and the two clients name it differently.
local function zoneFontString()
    local cluster = MinimapCluster
    return (cluster and cluster.ZoneTextButton and cluster.ZoneTextButton.Text)
        or _G.MinimapZoneText
end

local function applyZoneSize()
    local fs = zoneFontString()
    if not fs then return end
    local file, _, flags = fs:GetFont()
    pcall(fs.SetFont, fs, ns.ModuleFontPath("minimapstyle") or file, mod.db.zoneSize, flags)
end

local function setShown(frame, shown)
    if frame then pcall(frame.SetShown, frame, shown) end
end

-- Who shows the zone name and the clock, per style. Getting this wrong is how
-- the zone ended up written twice on the standard map: the client's own text
-- was still there and ours was drawn on top of it.
--
--   standard  the client's, untouched. We add nothing.
--   classic   the client's, moved onto the header bar and under the map.
--   modern    ours, and the client's are hidden.
local BLIZZ_TEXT = {
    standard = { border = true,  zone = true,  clock = true },
    classic  = { border = false, zone = true,  clock = true },
    modern   = { border = false, zone = false, clock = false },
}

-- Which of our own readouts a style allows. Coordinates, framerate and
-- difficulty have no counterpart in the client, so they add nothing twice --
-- but standard means hands off, and that includes ours.
local OWN_TEXT = {
    standard = {},
    classic  = { coords = true, fps = true, diff = true },
    modern   = { coords = true, zone = true, clock = true, fps = true, diff = true },
}

function MM.Allows(key)
    return (OWN_TEXT[mod.db.style] or OWN_TEXT.standard)[key] and true or false
end

-- What sits around the edge. Every one of these is optional and every one is
-- a Blizzard frame, so nothing here is more than a Show or a Hide.
local function applyClutter()
    local db = mod.db
    local cluster = MinimapCluster
    local blizz = BLIZZ_TEXT[db.style] or BLIZZ_TEXT.standard
    setShown(Minimap.ZoomIn, not db.hideZoom)
    setShown(Minimap.ZoomOut, not db.hideZoom)
    if cluster then
        setShown(cluster.Tracking, not db.hideTracking)
        setShown(cluster.IndicatorFrame, not db.hideMail)
        setShown(cluster.DielFrame, not db.hideDiel)
        setShown(cluster.BorderTop, blizz.border)
        setShown(cluster.ZoneTextButton, blizz.zone)
    end
    if _G.TimeManagerClockButton then
        setShown(_G.TimeManagerClockButton, blizz.clock and not (db.style == "classic" and db.hideClock))
    end
end

-- The queue eye is an Edit Mode system: its SetPoint, ClearAllPoints and
-- SetScale are Lua overrides that write Edit Mode state. This hands out the
-- engine method the mixin kept aside instead (see the queue eye further down).
local function engine(f, name)
    local fn = f[name .. "Base"]
    if type(fn) == "function" then return fn end
    local mt = getmetatable(f)
    local idx = mt and mt.__index
    return type(idx) == "table" and idx[name] or f[name]
end

-- ---------------------------------------------------------------------------
-- The three looks
-- ---------------------------------------------------------------------------
local function applyStandard()
    local cluster = MinimapCluster
    -- Minimap included: the modern border lives there, and a leftover border is
    -- exactly what made a switch look broken.
    hideOurs(cluster)
    hideOurs(MinimapBackdrop)
    hideOurs(Minimap)
    if cluster then
        hideOurs(cluster.Tracking)
        hideOurs(cluster.IndicatorFrame)
        hideOurs(cluster.IndicatorFrame and cluster.IndicatorFrame.MailFrame)
    end
    -- the stone plate and the rings the classic look hangs on these
    hideOurs(_G.TimeManagerClockButton)
    hideOurs(_G.QueueStatusButton)
    restoreButtonArt(Minimap.ZoomIn, "ZoomIn")
    restoreButtonArt(Minimap.ZoomOut, "ZoomOut")
    restore(cluster and cluster.Tracking and cluster.Tracking.Background, "trackbg")
    restoreButtonArt(cluster and cluster.Tracking and cluster.Tracking.Button, "track")
    restore(cluster and cluster.MinimapContainer, "container")
    restore(Minimap, "map")
    restore(MinimapBackdrop, "backdrop")
    restore(cluster and cluster.ZoneTextButton, "zonebtn")
    restore(Minimap.ZoomIn, "zoomin")
    restore(Minimap.ZoomOut, "zoomout")
    restore(cluster, "cluster")
    restore(cluster and cluster.Tracking, "tracking")
    restore(cluster and cluster.Tracking and cluster.Tracking.Button, "trackbtn")
    restore(cluster and cluster.IndicatorFrame, "mail")
    restore(cluster and cluster.DielFrame, "diel")
    restore(cluster and cluster.InstanceDifficulty, "difficulty")
    restore(MinimapBackdrop and MinimapBackdrop.StaticOverlayTexture, "staticoverlay")
    restore(MinimapCompassTexture, "compass")
    restore(MinimapCompassTextureUnderlay, "underlay")
    restore(_G.QueueStatusButton, "queue")
    restore(_G.ExpansionLandingPageMinimapButton, "landing")
    restore(_G.AddonCompartmentFrame, "compartment")
    restore(_G.TimeManagerClockTicker, "clockticker")
    local clock = _G.TimeManagerClockButton
    if clock then
        for i, r in ipairs({ clock:GetRegions() }) do restore(r, "clockreg" .. i) end
    end
    restore(clock, "clock")
    local cal = _G.GameTimeFrame
    if cal then
        restoreButtonArt(cal, "calendar")
        for i, r in ipairs({ cal:GetRegions() }) do restore(r, "calreg" .. i) end
        restore(cal:GetFontString(), "calfs")
    end
    setShown(MinimapCompassTexture, true)

    -- The Camelot skin that owns this look lives in a local function we cannot
    -- call, so the two things it sets are set here by hand: the round frame
    -- from its atlas, and the matching mask.
    local rotate = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("rotateMinimap")
    if MinimapCompassTexture then
        pcall(MinimapCompassTexture.SetAtlas, MinimapCompassTexture,
            rotate and "UI-HUD-Minimap-Frame-Pointer" or "UI-HUD-Minimap-Frame")
    end
    pcall(Minimap.SetMaskTexture, Minimap, ROUND_MASK)
    if cluster then cluster:SetScale(mod.db.scale) end
end

-- The calendar: the day number on the stone calendar face. Its art is one
-- sheet with the pressed state beside the normal one.
local function skinCalendar()
    local button = _G.GameTimeFrame
    if not button then return end
    rememberButtonArt(button, "calendar")
    for i, r in ipairs({ button:GetRegions() }) do remember(r, "calreg" .. i) end
    remember(button:GetFontString(), "calfs")
    pcall(button.SetNormalTexture, button, CALENDAR_ART)
    pcall(button.SetPushedTexture, button, CALENDAR_ART)
    pcall(button.SetHighlightTexture, button, ZOOM_HIGHLIGHT)
    local normal, pushed = button:GetNormalTexture(), button:GetPushedTexture()
    local hl = button:GetHighlightTexture()
    if normal then
        normal:SetTexCoord(0, 0.390625, 0, 0.78125)
        normal:ClearAllPoints(); normal:SetAllPoints(button); normal:SetDrawLayer("BACKGROUND")
    end
    if pushed then
        pushed:SetTexCoord(0.5, 0.890625, 0, 0.78125)
        pushed:ClearAllPoints(); pushed:SetAllPoints(button); pushed:SetDrawLayer("BACKGROUND")
    end
    if hl then
        hl:SetTexCoord(0, 1, 0, 1)
        hl:ClearAllPoints(); hl:SetAllPoints(button); hl:SetBlendMode("ADD")
    end
    for _, r in ipairs({ button:GetRegions() }) do
        if r:IsObjectType("Texture") and r ~= normal and r ~= pushed and r ~= hl then r:SetAlpha(0) end
    end
    local fs = button:GetFontString()
    if not fs then
        fs = button:CreateFontString(nil, "OVERLAY", "GameFontBlack")
        button:SetFontString(fs)
    end
    fs:SetFontObject("GameFontBlack")
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", button, "CENTER", -1, -1)
    fs:SetDrawLayer("OVERLAY")
    local t = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime
        and C_DateAndTime.GetCurrentCalendarTime()
    if t and t.monthDay then button:SetText(t.monthDay) end
end

-- The 1.x cluster: a 192px frame with the map sunk into it, the zone name
-- across the top and the buttons riding the rim. Every number here is the
-- original layout; the art is Blizzard's own, so a client that does not ship
-- it leaves the frame empty and the placement still holds.
local function applyClassic()
    local cluster, backdrop, map = MinimapCluster, MinimapBackdrop, Minimap
    if not (cluster and backdrop and map) then return end
    remember(cluster, "cluster", { keepPoints = true })
    remember(backdrop, "backdrop")
    remember(map, "map")
    remember(cluster.MinimapContainer, "container")
    remember(cluster.ZoneTextButton, "zonebtn")
    remember(cluster.Tracking, "tracking")
    remember(cluster.Tracking and cluster.Tracking.Button, "trackbtn")
    remember(cluster.IndicatorFrame, "mail")
    remember(cluster.DielFrame, "diel")
    remember(cluster.InstanceDifficulty, "difficulty")
    remember(backdrop.StaticOverlayTexture, "staticoverlay")
    remember(MinimapCompassTexture, "compass")
    remember(MinimapCompassTextureUnderlay, "underlay", { shown = true })
    remember(_G.QueueStatusButton, "queue")
    remember(_G.ExpansionLandingPageMinimapButton, "landing")
    remember(_G.AddonCompartmentFrame, "compartment", { shown = true })
    remember(_G.TimeManagerClockTicker, "clockticker")
    remember(_G.TimeManagerClockButton, "clock")
    if _G.TimeManagerClockButton then
        for i, r in ipairs({ _G.TimeManagerClockButton:GetRegions() }) do remember(r, "clockreg" .. i) end
    end

    cluster:SetSize(CLASSIC_CLUSTER, CLASSIC_CLUSTER)
    setShown(cluster.BorderTop, false)
    if cluster.MinimapContainer then
        cluster.MinimapContainer:SetScale(1)
        cluster.MinimapContainer:SetSize(CLASSIC_MAP, CLASSIC_MAP)
        cluster.MinimapContainer:ClearAllPoints()
        cluster.MinimapContainer:SetPoint("CENTER", cluster, "TOP", 9, -92)
    end
    map:SetSize(CLASSIC_MAP, CLASSIC_MAP)
    map:ClearAllPoints()
    map:SetPoint("CENTER", cluster.MinimapContainer or cluster, "CENTER", 0, 0)
    pcall(map.SetMaskTexture, map, CIRCLE_MASK)

    backdrop:SetSize(CLASSIC_CLUSTER, CLASSIC_CLUSTER)
    backdrop:ClearAllPoints()
    backdrop:SetPoint("CENTER", cluster, "CENTER", 0, -20)
    if backdrop.StaticOverlayTexture then backdrop.StaticOverlayTexture:SetAlpha(0) end

    -- the two pieces cut out of the one border sheet
    local top = region(cluster, "borderTop", "ARTWORK")
    top:SetTexture(CLASSIC_SHEET)
    top:SetTexCoord(unpack(SHEET_TOP))
    top:SetSize(CLASSIC_CLUSTER, 32)
    top:ClearAllPoints()
    top:SetPoint("TOPRIGHT", cluster, "TOPRIGHT", 0, 0)
    top:Show()

    local ring = region(backdrop, "ring", "ARTWORK")
    ring:SetTexture(CLASSIC_SHEET)
    -- GetTexture comes back nil when the file is not in the client. Said once,
    -- because an empty frame otherwise just looks like a bug in the layout.
    if not ring:GetTexture() and not mod._warnedArt then
        mod._warnedArt = true
        ns:Print(L["This client does not ship the classic minimap art, so the frame stays empty. The layout still applies."])
    end
    ring:SetTexCoord(unpack(SHEET_RING))
    ring:ClearAllPoints()
    ring:SetAllPoints(backdrop)
    ring:Show()

    -- The client's own round frame would sit on top of the classic one.
    setShown(MinimapCompassTexture, false)
    setShown(MinimapCompassTextureUnderlay, false)

    -- A rotating map gets the compass ring, a fixed one the little N.
    local rotate = C_CVar and C_CVar.GetCVarBool and C_CVar.GetCVarBool("rotateMinimap")
    local north = region(backdrop, "north", "OVERLAY")
    north:SetTexture(COMPASS_NORTH)
    north:SetSize(16, 16)
    north:ClearAllPoints()
    north:SetPoint("CENTER", map, "CENTER", 0, 67)
    north:SetShown(not rotate)
    if MinimapCompassTexture and rotate then
        MinimapCompassTexture:SetTexture(COMPASS_RING)
        MinimapCompassTexture:SetTexCoord(0, 1, 0, 1)
        MinimapCompassTexture:SetSize(256, 256)
        MinimapCompassTexture:ClearAllPoints()
        MinimapCompassTexture:SetPoint("CENTER", map, "CENTER", -2, 0)
        MinimapCompassTexture:SetDrawLayer("OVERLAY")
        MinimapCompassTexture:Show()
    end

    -- Zone name across the header bar.
    if cluster.ZoneTextButton then
        cluster.ZoneTextButton:SetScale(1)
        cluster.ZoneTextButton:SetSize(CLASSIC_MAP, 12)
        cluster.ZoneTextButton:ClearAllPoints()
        cluster.ZoneTextButton:SetPoint("CENTER", cluster, "TOP", 0, -12)
    end

    -- Anything sitting over the map edge must be above it to take a click.
    local above = map:GetFrameLevel() + 5
    for _, e in ipairs({ { "ZoomIn", 72, -25 }, { "ZoomOut", 50, -43 } }) do
        local button = map[e[1]]
        if button then
            remember(button, e[1]:lower())
            button:SetParent(backdrop)
            button:SetFrameLevel(above)
            button:SetSize(32, 32)
            button:ClearAllPoints()
            button:SetPoint("CENTER", backdrop, "CENTER", e[2], e[3])
            -- the 1.x button faces, one file per state
            rememberButtonArt(button, e[1])
            local base = ZOOM_ART[e[1]]
            for state, suffix in pairs({ Normal = "Up", Pushed = "Down", Disabled = "Disabled" }) do
                local setter = button["Set" .. state .. "Texture"]
                if setter then pcall(setter, button, base .. suffix) end
            end
            pcall(button.SetHighlightTexture, button, ZOOM_HIGHLIGHT)
            for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
                local tex = button["Get" .. state .. "Texture"](button)
                if tex then
                    tex:SetTexCoord(0, 1, 0, 1)
                    tex:ClearAllPoints()
                    tex:SetAllPoints(button)
                end
            end
            local hl = button:GetHighlightTexture()
            if hl then hl:SetBlendMode("ADD") end
            button:SetHitRectInsets(4, 4, 2, 6)
            button:Show()
        end
    end

    -- Tracking: the stone ring around it is a texture of its own, and the icon
    -- Blizzard draws as the button face is shrunk back to its 1.x size.
    local tracking = cluster.Tracking
    if tracking then
        tracking:SetParent(backdrop)
        tracking:SetFrameLevel(above)
        tracking:SetSize(32, 32)
        tracking:ClearAllPoints()
        tracking:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 9, -45)
        local ring = region(tracking, "ring", "BORDER")
        ring:SetTexture(TRACK_BORDER)
        ring:SetSize(54, 54)
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", tracking, "TOPLEFT", 0, 0)
        ring:Show()
        if tracking.Background then
            remember(tracking.Background, "trackbg")
            tracking.Background:SetTexture(MAP_BACKGROUND)
            tracking.Background:SetTexCoord(0, 1, 0, 1)
            tracking.Background:SetSize(25, 25)
            tracking.Background:ClearAllPoints()
            tracking.Background:SetPoint("TOPLEFT", tracking, "TOPLEFT", 2, -4)
            tracking.Background:SetAlpha(0.6)
        end
        local button = tracking.Button
        if button then
            rememberButtonArt(button, "track")
            button:SetSize(32, 32)
            button:SetFrameLevel(above + 1)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", tracking, "TOPLEFT", 0, 0)
            for _, state in ipairs({ "Normal", "Pushed" }) do
                local tex = button["Get" .. state .. "Texture"](button)
                if tex then
                    local o = state == "Pushed" and 8 or 6
                    tex:SetSize(20, 20)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", tracking, "TOPLEFT", o, -o)
                end
            end
        end
    end

    -- Mail gets the same stone ring, up on the right of the map.
    local indicator = cluster.IndicatorFrame
    if indicator then
        indicator:SetFrameLevel(above)
        indicator:SetSize(33, 33)
        indicator:ClearAllPoints()
        indicator:SetPoint("TOPRIGHT", map, "TOPRIGHT", 24, -37)
        local host = indicator.MailFrame or indicator
        local ring = region(host, "ring", "OVERLAY")
        ring:SetTexture(TRACK_BORDER)
        ring:SetSize(52, 52)
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
        ring:Show()
    end
    if cluster.DielFrame then
        cluster.DielFrame:ClearAllPoints()
        cluster.DielFrame:SetPoint("TOPRIGHT", map, "TOPRIGHT", 20, -2)
    end
    -- The clock sits on a stone plate under the map. Blizzard's own rounded
    -- backing is faded rather than hidden, because hiding its regions is what
    -- would take the time text with them.
    local clock = _G.TimeManagerClockButton
    if clock then
        clock:SetParent(map)
        clock:SetFrameLevel(above)
        clock:SetSize(60, 28)
        clock:ClearAllPoints()
        clock:SetPoint("CENTER", map, "CENTER", 0, -75)
        local plate = region(clock, "plate", "BORDER")
        for _, r in ipairs({ clock:GetRegions() }) do
            if r ~= plate and r:IsObjectType("Texture") then r:SetAlpha(0) end
        end
        plate:SetTexture(CLOCK_PLATE)
        plate:SetTexCoord(0.015625, 0.8125, 0.015625, 0.390625)
        plate:SetAllPoints(clock)
        plate:SetAlpha(1)
        plate:Show()
        if _G.TimeManagerClockTicker then
            _G.TimeManagerClockTicker:ClearAllPoints()
            _G.TimeManagerClockTicker:SetPoint("CENTER", clock, "CENTER", 3, 1)
        end
    end

    -- The queue eye on the lower left, wearing the same stone ring.
    if _G.QueueStatusButton then
        local q = _G.QueueStatusButton
        q:SetParent(backdrop)
        q:SetFrameLevel(above)
        q:SetSize(33, 33)
        -- in scale-1 offsets, converted for the scale the eye has right now
        local qs = q:GetScale() or 1
        engine(q, "ClearAllPoints")(q)
        engine(q, "SetPoint")(q, "TOPLEFT", backdrop, "TOPLEFT", 22 / qs, -100 / qs)
        local ring = region(q, "ring", "OVERLAY")
        ring:SetTexture(TRACK_BORDER)
        ring:SetSize(52, 52)
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", q, "TOPLEFT", 1, -1)
        ring:Show()
    end
    if cluster.InstanceDifficulty then
        cluster.InstanceDifficulty:ClearAllPoints()
        cluster.InstanceDifficulty:SetPoint("TOPLEFT", cluster, "TOPLEFT", 22, -17)
    end

    -- 1.x has no landing-page button; it stays reachable from the micro menu,
    -- so it is faded rather than hidden.
    if _G.ExpansionLandingPageMinimapButton then
        _G.ExpansionLandingPageMinimapButton:SetAlpha(0)
        _G.ExpansionLandingPageMinimapButton:EnableMouse(false)
    end

    if _G.AddonCompartmentFrame then _G.AddonCompartmentFrame:Hide() end
    skinCalendar()
    cluster:SetScale(mod.db.scale)
end

local function applyModern()
    local cluster, backdrop = MinimapCluster, MinimapBackdrop
    if not cluster then return end
    remember(cluster, "cluster", { keepPoints = true })
    remember(Minimap, "map")
    remember(backdrop, "backdrop")
    remember(cluster.ZoneTextButton, "zonebtn")
    hideOurs(backdrop)

    applyShape(mod.db.shape == "round")
    setShown(MinimapCompassTexture, false)
    if backdrop then backdrop:SetSize(1, 1) end

    -- A thin border of our own, drawn from four edges rather than a texture so
    -- it stays one physical pixel at any scale.
    local edges = ours[Minimap] and ours[Minimap].edges
    if not edges then
        edges = ns.MakeEdges(Minimap, "OVERLAY")
        ours[Minimap] = ours[Minimap] or {}
        ours[Minimap].edges = edges
    end
    local r, g, b, a = borderRGB()
    ns.LayoutEdges(edges, Minimap, mod.db.borderSize, r, g, b, a)

    if cluster.ZoneTextButton and mod.db.zoneMode ~= "none" then
        cluster.ZoneTextButton:ClearAllPoints()
        if mod.db.zoneMode == "top" then
            cluster.ZoneTextButton:SetPoint("BOTTOM", Minimap, "TOP", 0, 4)
        else
            cluster.ZoneTextButton:SetPoint(mod.db.zonePosition, Minimap, mod.db.zonePosition, 0, -4)
        end
    end
    cluster:SetScale(mod.db.scale)
end

-- ---------------------------------------------------------------------------
-- The queue eye
--
-- In this client the eye is an Edit Mode system (the group finder). Its
-- SetPoint, ClearAllPoints and SetScale are Lua overrides that write Edit Mode
-- state, so everything here goes through the engine methods the mixin kept
-- aside (SetPointBase and friends).
--
-- The size is a factor on top of the size the client's own editor gives it.
-- A scale also scales the anchor offsets, so they are converted from the old
-- scale to the new one -- what the client's override does -- and the eye
-- stays where it sits.
-- ---------------------------------------------------------------------------
local function clientQueueScale(q)
    local enum = Enum and Enum.EditModeGroupFinderSetting
    if not (enum and enum.Size and q.GetSettingValue and q.systemInfo) then return 1 end
    local ok, v = pcall(q.GetSettingValue, q, enum.Size)
    if ok and type(v) == "number" and v > 0 then return v / 100 end
    return 1
end

local function scaleQueue(factor)
    local q = _G.QueueStatusButton
    if not (q and q.GetNumPoints) then return end
    local old = q:GetScale() or 1
    local new = clientQueueScale(q) * (factor or 1)
    if old == 0 or new <= 0 or math.abs(old - new) < 0.001 then return end
    local pts = {}
    for i = 1, q:GetNumPoints() do
        local p, rel, rp, x, y = q:GetPoint(i)
        pts[i] = { p, rel, rp, (x or 0) * old / new, (y or 0) * old / new }
    end
    engine(q, "SetScale")(q, new)
    engine(q, "ClearAllPoints")(q)
    local setPoint = engine(q, "SetPoint")
    for _, pt in ipairs(pts) do setPoint(q, pt[1], pt[2], pt[3], pt[4], pt[5]) end
end

P.setShown      = setShown
P.applyClutter  = applyClutter
P.applyZoneSize = applyZoneSize
P.applyStandard = applyStandard
P.skinCalendar  = skinCalendar
P.applyClassic  = applyClassic
P.applyModern   = applyModern
P.scaleQueue    = scaleQueue
