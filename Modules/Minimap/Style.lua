-- VuloForeverUI / Modules / Minimap / Style
--
-- Three looks for the minimap, picked from one dropdown:
--
--   standard  the client's own. We touch nothing, and switching back to it
--             puts every piece we ever moved where we found it.
--   classic   the 1.x stone ring: a round map inside a heavy border, the zone
--             name across the top, zoom buttons at the lower right.
--   modern    flat. Square or round, a thin border, and the clutter around the
--             edge gone unless you ask for it.
--
-- Forever's own minimap is the retail MinimapCluster wearing a Camelot skin
-- (Blizzard_Minimap/Camelot/Skin.lua): a round frame from the atlas
-- UI-HUD-Minimap-Frame, sized from that atlas and masked round. That skin runs
-- on its own whenever `rotateMinimap` changes, so anything we do has to be
-- re-applied afterwards rather than set once.
--
-- Nothing here is secret-sensitive: the minimap carries no combat data. What it
-- does carry is Blizzard frames, so every write is guarded and reversible, and
-- the layout work waits for the end of a fight.
local _, ns = ...
local L = ns.L

-- Shared between the files in this folder; Elements.lua hangs off it.
ns.MM = ns.MM or {}
local MM = ns.MM

local mod = ns:RegisterModule("minimapstyle", {
    name        = "Minimap",
    group       = "HUD",
    description = "Three looks for the minimap: the game's own, the classic ring, or a flat modern one.",
    defaults = {
        enabled = true,
        style   = "standard",

        scale       = 1,
        shape       = "round",          -- modern only; classic is always round
        borderSize  = 1,
        borderColor = { r = .067, g = .067, b = .067 },
        borderClassColor = false,

        -- The five readouts. Each one has the same five settings, so they are
        -- named the same way and Elements.lua walks them by key.
        coordsMode = "never", coordsPosition = "BOTTOM", coordsSize = 11,
        coordsOffsetX = 0, coordsOffsetY = 0, coordsScale = 1, coordsPrecision = 0,

        zoneMode = "inside", zonePosition = "TOP", zoneSize = 12,
        zoneOffsetX = 0, zoneOffsetY = 0, zoneScale = 1,
        zoneSubzone = false, zoneReactiveColor = false,

        clockMode = "edge", clockPosition = "BOTTOM", clockSize = 11,
        clockOffsetX = 0, clockOffsetY = 0, clockScale = 1, clock24 = true,

        fpsMode = "none", fpsPosition = "BOTTOMLEFT", fpsSize = 11,
        fpsOffsetX = 0, fpsOffsetY = 0, fpsScale = 1, fpsShowMS = true,

        diffMode = "none", diffPosition = "TOPLEFT", diffSize = 11,
        diffOffsetX = 0, diffOffsetY = 0, diffScale = 1,

        -- behaviour
        scrollZoom   = true,
        zoomReset    = 0,               -- seconds of quiet before zooming back out; 0 = off
        middleClickMenu = false,
        visibility   = "always",        -- always | instances | never
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,

        hideZoom     = true,
        hideTracking = false,
        hideMail     = false,
        hideClock    = true,            -- the client's own clock; ours is an element
        hideDiel     = false,           -- Forever's day/night indicator
    },
})
MM.mod = mod

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
-- Remembering what we found
--
-- Every frame we move is written down the first time we touch it, so "standard"
-- is a real restore and not a second guess at Blizzard's layout.
-- ---------------------------------------------------------------------------
local saved = {}

-- One getter, answered or not: a refused call is simply not recorded.
local function ask(frame, method)
    local fn = frame[method]
    if type(fn) ~= "function" then return false end
    return pcall(fn, frame)
end

-- Everything any look changes on a frame or a texture, so restore can put all
-- of it back: a piece that was moved but not written down is a piece that
-- stays classic after switching back. `opts.shown` records visibility too;
-- `opts.keepPoints` leaves the anchors
-- alone -- the cluster's belong to Edit Mode, and a snapshot of them taken at
-- login would undo every move made there since.
local function remember(frame, key, opts)
    if not frame or saved[key] then return end
    local entry = { points = {}, keepPoints = opts and opts.keepPoints }
    local ok, a, b, c, d
    ok, a = ask(frame, "GetParent");      if ok then entry.parent = a or false end
    ok, a, b = ask(frame, "GetSize");     if ok then entry.w, entry.h = a, b end
    ok, a = ask(frame, "GetScale");       if ok then entry.scale = a end
    ok, a = ask(frame, "GetAlpha");       if ok then entry.alpha = a end
    -- shown only on request: most of these are shown and hidden by the
    -- clutter switches and the visibility rules, which run after a restore
    if opts and opts.shown then
        ok, a = ask(frame, "IsShown"); if ok then entry.shown = a and true or false end
    end
    ok, a = ask(frame, "GetFrameLevel");  if ok then entry.level = a end
    ok, a = ask(frame, "IsMouseEnabled"); if ok then entry.mouse = a and true or false end
    ok, a, b, c, d = ask(frame, "GetHitRectInsets")
    if ok and a then entry.insets = { a, b, c, d } end
    -- Textures remember their art too: the classic look overwrites the zoom
    -- and tracking faces. An atlas wins over the file, because SetAtlas also
    -- brings its own coordinates back. A nil path is a real answer (the
    -- region had none) and is kept as `false`.
    ok, a = ask(frame, "GetAtlas")
    if ok and type(a) == "string" and a ~= "" then entry.atlas = a end
    ok, a = ask(frame, "GetTexture");     if ok then entry.tex = a or false end
    if frame.GetTexCoord then entry.coords = { pcall(frame.GetTexCoord, frame) } end
    ok, a, b = ask(frame, "GetDrawLayer"); if ok and a then entry.layer = { a, b or 0 } end
    ok, a = ask(frame, "GetBlendMode");   if ok and a then entry.blend = a end
    ok, a = ask(frame, "GetFontObject");  if ok and a then entry.font = a end
    if not entry.keepPoints then
        local okN, n = ask(frame, "GetNumPoints")
        for i = 1, (okN and n or 0) do
            entry.points[i] = { frame:GetPoint(i) }
        end
    end
    saved[key] = entry
end

local function restore(frame, key)
    local entry = saved[key]
    if not (frame and entry) then return end
    saved[key] = nil
    local function set(method, ...)
        if frame[method] then pcall(frame[method], frame, ...) end
    end
    -- the parent first: a new parent resets the frame level
    if entry.parent ~= nil and frame.SetParent then set("SetParent", entry.parent or nil) end
    if not entry.keepPoints then
        frame:ClearAllPoints()
        for _, pt in ipairs(entry.points) do set("SetPoint", unpack(pt)) end
    end
    if entry.w and entry.w > 0 then set("SetSize", entry.w, entry.h) end
    if entry.scale and frame.SetScale then set("SetScale", entry.scale) end
    if entry.alpha then set("SetAlpha", entry.alpha) end
    if entry.level and frame.SetFrameLevel then set("SetFrameLevel", entry.level) end
    if entry.mouse ~= nil and frame.EnableMouse then set("EnableMouse", entry.mouse) end
    if entry.insets then set("SetHitRectInsets", unpack(entry.insets)) end
    if entry.atlas and frame.SetAtlas then
        set("SetAtlas", entry.atlas)
    elseif entry.tex ~= nil and frame.SetTexture then
        set("SetTexture", entry.tex or nil)
        if entry.coords and entry.coords[1] and #entry.coords >= 9 then
            set("SetTexCoord", select(2, unpack(entry.coords)))
        end
    end
    if entry.layer then set("SetDrawLayer", entry.layer[1], entry.layer[2]) end
    if entry.blend then set("SetBlendMode", entry.blend) end
    if entry.font then set("SetFontObject", entry.font) end
    if entry.shown ~= nil then set("SetShown", entry.shown) end
end

-- The button faces the classic look replaces, remembered per state so the
-- client's own art comes back when the style does.
local function rememberButtonArt(button, key)
    if not button then return end
    for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
        local getter = button["Get" .. state .. "Texture"]
        local tex = getter and getter(button)
        if tex then remember(tex, key .. state) end
    end
end

local function restoreButtonArt(button, key)
    if not button then return end
    for _, state in ipairs({ "Normal", "Pushed", "Disabled", "Highlight" }) do
        local getter = button["Get" .. state .. "Texture"]
        local tex = getter and getter(button)
        if tex then restore(tex, key .. state) end
    end
end

-- Our own regions on Blizzard frames, kept in a weak table rather than as a
-- field on the frame -- the house rule for anything the client owns.
local ours = setmetatable({}, { __mode = "k" })

local function region(parent, key, layer)
    local set = ours[parent]
    if not set then set = {}; ours[parent] = set end
    if not set[key] then set[key] = parent:CreateTexture(nil, layer or "OVERLAY") end
    return set[key]
end

-- A slot holds either one texture or a set of them (the modern border is four
-- edges). Missing the second case is what left a square outline around the map
-- after switching from modern to classic.
local function hideOurs(parent)
    local set = ours[parent]
    if not set then return end
    for _, item in pairs(set) do
        if item.Hide then
            item:Hide()
        else
            for _, tex in pairs(item) do
                if tex.Hide then tex:Hide() end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
local function borderRGB()
    local db = mod.db
    if db.borderClassColor then
        local _, class = UnitClass("player")
        local c = class and ((ns.CLASS_COLORS and ns.CLASS_COLORS[class]) or RAID_CLASS_COLORS[class])
        if c then return c.r, c.g, c.b end
    end
    local c = db.borderColor
    return c.r, c.g, c.b
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
        q:SetScale(1)
        q:SetSize(33, 33)
        q:ClearAllPoints()
        q:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 22, -100)
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
    local r, g, b = borderRGB()
    ns.LayoutEdges(edges, Minimap, mod.db.borderSize, r, g, b, 1)

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
-- Applying, and doing it again when the client redoes its own skin
-- ---------------------------------------------------------------------------
local applying

function mod:Apply()
    if not self.active or applying then return end
    if InCombatLockdown() then
        ns:RunOutOfCombatOnce("minimapstyle", function() mod:Apply() end)
        return
    end
    applying = true
    local ok, err = pcall(function()
        local style = self.db.style
        if style ~= "standard" then applyStandard() end   -- from a clean slate
        if style == "classic" then applyClassic()
        elseif style == "modern" then applyModern()
        else applyStandard() end
        applyClutter()
        if style ~= "standard" then applyZoneSize() end
        MM.Elements.Apply()
        MM.Elements.ApplyVisibility()
    end)
    applying = false
    -- The rim buttons measure the map when they place themselves, and they
    -- load before this file: after a look changes its size they sit wrong.
    for _, key in ipairs({ "minimap", "minimapcollector" }) do
        local m = ns.modules[key]
        if m and m.active and m.UpdatePosition then pcall(m.UpdatePosition) end
    end
    if not ok then ns:Print(L["|cffff5555Minimap style failed:|r %s"], tostring(err)) end
end

-- Script hooks cannot be taken off again: each one asks the module first.
local function onEnter()
    if not mod.active then return end
    MM.Elements.SetHovered(true)
    -- the client shows its zoom buttons on every hover
    if mod.db.hideZoom then
        setShown(Minimap.ZoomIn, false)
        setShown(Minimap.ZoomOut, false)
    end
end
local function onLeave() if mod.active then MM.Elements.SetHovered(false) end end
local mouseHooked = false
local blizzWheel      -- the map's own zoom handler, put back on disable

-- Zoom back out after a while, so a map left zoomed in does not stay that way.
local zoomTimer

local function scheduleZoomReset()
    local seconds = mod.db.zoomReset
    if seconds <= 0 then return end
    if zoomTimer then ns:CancelTicker(zoomTimer); zoomTimer = nil end
    local waited = 0
    zoomTimer = ns:AddTicker(1, function()
        waited = waited + 1
        if waited < seconds then return end
        ns:CancelTicker(zoomTimer); zoomTimer = nil
        for _ = 1, Minimap:GetZoom() do Minimap:SetZoom(Minimap:GetZoom() - 1) end
    end, nil, "minimapstyle")
end

function mod:OnEnable()
    -- MinimapCluster lays itself out again on its own -- an Edit Mode change, a
    -- size setting, a zone with a different header. Without this hook our
    -- placement survives exactly until the next time it does.
    if not self._layoutHooked then
        self._layoutHooked = true
        local function relayout()
            if mod.active and mod.db.style ~= "standard" then
                ns.NextFrame(function() mod:Apply() end)
            end
        end
        -- Everything that lays the cluster out again behind our back.
        local cluster = MinimapCluster
        if cluster then
            if cluster.Layout then hooksecurefunc(cluster, "Layout", relayout) end
            if cluster.SetRotateMinimap then hooksecurefunc(cluster, "SetRotateMinimap", relayout) end
            if cluster.IndicatorFrame and cluster.IndicatorFrame.Layout then
                hooksecurefunc(cluster.IndicatorFrame, "Layout", relayout)
            end
        end
        if _G.QueueStatusButton and _G.QueueStatusButton.UpdatePosition then
            hooksecurefunc(_G.QueueStatusButton, "UpdatePosition", relayout)
        end
        -- The calendar redraws its own face whenever the date is set.
        if _G.GameTimeFrame_SetDate then
            hooksecurefunc("GameTimeFrame_SetDate", function()
                if mod.active and mod.db.style == "classic" then skinCalendar() end
            end)
        end
        -- Two frames that put themselves back: 1.x has neither.
        if _G.AddonCompartmentFrame and _G.AddonCompartmentFrame.UpdateDisplay then
            hooksecurefunc(_G.AddonCompartmentFrame, "UpdateDisplay", function(self)
                if mod.active and mod.db.style == "classic" then self:Hide() end
            end)
        end
        if _G.ExpansionLandingPageMinimapButton and _G.ExpansionLandingPageMinimapButton.UpdateIcon then
            hooksecurefunc(_G.ExpansionLandingPageMinimapButton, "UpdateIcon", function(self)
                if mod.active and mod.db.style == "classic" then
                    self:SetAlpha(0); self:EnableMouse(false)
                end
            end)
        end
        -- The client hides the zoom buttons when the mouse leaves the map; in
        -- the classic look they are part of the frame and stay put.
        Minimap:HookScript("OnLeave", function()
            if mod.active and mod.db.style == "classic" and not mod.db.hideZoom then
                setShown(Minimap.ZoomIn, true)
                setShown(Minimap.ZoomOut, true)
            end
        end)
    end
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Apply() end)
    -- the Camelot skin rebuilds itself when this CVar flips, undoing our work
    self:RegisterEvent("CVAR_UPDATE", function(_, name)
        if name == "rotateMinimap" then ns.NextFrame(function() self:Apply() end) end
    end)
    if not mouseHooked then
        mouseHooked = true
        blizzWheel = Minimap:GetScript("OnMouseWheel")
        Minimap:HookScript("OnEnter", onEnter)
        Minimap:HookScript("OnLeave", onLeave)
        Minimap:HookScript("OnMouseUp", function(_, button)
            if mod.active and button == "MiddleButton" and mod.db.middleClickMenu then
                if _G.MainMenuMicroButton and _G.ToggleFrame then
                    pcall(_G.ToggleFrame, _G.MicroMenuContainer)
                end
            end
        end)
    end
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if not mod.db.scrollZoom then return end
        if delta > 0 then Minimap.ZoomIn:Click() else Minimap.ZoomOut:Click() end
        scheduleZoomReset()
    end)
    -- what the map is allowed to be seen for
    for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED",
                             "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED" }) do
        self:RegisterEvent(event, function() MM.Elements.ApplyVisibility() end)
    end
    self:Apply()
end

function mod:OnDisable()
    MM.Elements.HideAll()
    if MinimapCluster then MinimapCluster:Show() end
    Minimap:SetScript("OnMouseWheel", blizzWheel)
    applyStandard()
    applyClutter()
end

-- ---------------------------------------------------------------------------
-- Which classic textures this client actually ships
--
-- The classic look is built from Blizzard's own 1.x art. Whether Forever still
-- carries those files is not something the UI source can answer -- only the
-- running client can, and SetTexture returning false is how it says no.
-- ---------------------------------------------------------------------------
local CLASSIC_ART = {
    "Interface\\Minimap\\UI-Minimap-Border",
    "Interface\\Minimap\\UI-Minimap-Background",
    "Interface\\Minimap\\CompassRing",
    "Interface\\Minimap\\CompassNorthTag",
    "Interface\\Minimap\\MiniMap-TrackingBorder",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Down",
    "Interface\\Minimap\\UI-Minimap-ZoomInButton-Disabled",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Up",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Down",
    "Interface\\Minimap\\UI-Minimap-ZoomOutButton-Disabled",
    "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
    "Interface\\CharacterFrame\\TempPortraitAlphaMask",
    "Interface\\TimeManager\\ClockBackground",
    "Interface\\Calendar\\UI-Calendar-Button",
}

ns:RegisterSlash({ key = "MMTEX", commands = { "/vfmmtex" },
    desc = "Report which classic minimap textures this client ships.",
})

local probeTex

ns.Slash.MMTEX = function()
    if not probeTex then probeTex = UIParent:CreateTexture(nil, "BACKGROUND"); probeTex:Hide() end
    local A, R = ns.C.accent, ns.C.r
    ns:Print("%sClassic minimap art%s", A, R)
    local missing = 0
    for _, path in ipairs(CLASSIC_ART) do
        local ok = probeTex:SetTexture(path) ~= false and probeTex:GetTexture() ~= nil
        if not ok then missing = missing + 1 end
        ns:Print("  %s%-52s%s", ok and (ns.C.pos .. "yes  " .. R) or (ns.C.neg .. "NO   " .. R),
            path:gsub("Interface\\", ""), "")
    end
    ns:Print("  %d of %d missing", missing, #CLASSIC_ART)
end

-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------
local function set(key, after)
    return function(_, v)
        mod.db[key] = v
        if after then after() else mod:Apply() end
    end
end

function mod:GetOptions()
    local d = self.db
    local modern = function() return d.style ~= "modern" end
    local positions = ns.AnchorPointValues()

    local rows = {
        { type = "dropdown", label = L["Minimap Style"],
          tooltip = L["Standard leaves the game's own minimap alone. Classic rebuilds the old ring. Modern is a flat map with a thin border."],
          values = {
              { value = "standard", text = L["Standard (as the game ships it)"] },
              { value = "classic",  text = L["Classic (the old ring)"] },
              { value = "modern",   text = L["Modern (flat)"] },
          },
          get = function() return d.style end, set = set("style") },

        { type = "section", title = L["Shape and Size"], items = {
            { type = "dropdown", label = L["Shape"], disabled = modern,
              values = { { value = "round", text = L["Round"] }, { value = "square", text = L["Square"] } },
              get = function() return d.shape end, set = set("shape") },
            { type = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05,
              get = function() return d.scale end, set = set("scale") },
            { type = "slider", label = L["Border Size"], min = 0, max = 4, step = 1, disabled = modern,
              inline = { { kind = "color", tooltip = L["Border color"],
                           disabled = function() return d.borderClassColor end,
                           get = function() return d.borderColor end,
                           set = function(r, g, b)
                               d.borderColor.r, d.borderColor.g, d.borderColor.b = r, g, b
                               mod:Apply()
                           end } },
              get = function() return d.borderSize end, set = set("borderSize") },
            { type = "toggle", label = L["Use my class color"], disabled = modern,
              get = function() return d.borderClassColor end, set = set("borderClassColor") },
        } },

        { type = "section", title = L["Around the Map"], items = {
            { type = "toggle", label = L["Zoom with the mouse wheel"],
              get = function() return d.scrollZoom end, set = set("scrollZoom") },
            { type = "toggle", label = L["Hide Zoom Buttons"],
              get = function() return d.hideZoom end, set = set("hideZoom") },
            { type = "toggle", label = L["Hide Tracking Button"],
              get = function() return d.hideTracking end, set = set("hideTracking") },
            { type = "toggle", label = L["Hide Mail Icon"],
              get = function() return d.hideMail end, set = set("hideMail") },
            { type = "toggle", label = L["Hide Day/Night Indicator"],
              tooltip = L["The sun and moon dial this client shows next to the map."],
              get = function() return d.hideDiel end, set = set("hideDiel") },
            { type = "toggle", label = L["Hide the game's own clock"],
              tooltip = L["Only in the classic look. Modern draws its own clock instead, and standard leaves the game's alone."],
              disabled = function() return d.style ~= "classic" end,
              get = function() return d.hideClock end, set = set("hideClock") },
            { type = "slider", label = L["Zoom back out after"], min = 0, max = 60, step = 5,
              tooltip = L["Seconds of quiet before the map returns to its widest zoom. 0 leaves it alone."],
              get = function() return d.zoomReset end, set = set("zoomReset") },
            { type = "toggle", label = L["Middle click opens the menu"],
              get = function() return d.middleClickMenu end, set = set("middleClickMenu") },
        } },

        { type = "section", title = L["When to show the map"], items = {
            { type = "dropdown", label = L["Show the minimap"],
              values = {
                  { value = "always",    text = L["Always"] },
                  { value = "instances", text = L["Only in instances"] },
                  { value = "never",     text = L["Never"] },
              },
              get = function() return d.visibility end,
              set = set("visibility", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide while mounted"],
              get = function() return d.visHideMounted end,
              set = set("visHideMounted", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide without a target"],
              get = function() return d.visHideNoTarget end,
              set = set("visHideNoTarget", function() MM.Elements.ApplyVisibility() end) },
            { type = "toggle", label = L["Hide without an enemy target"],
              get = function() return d.visHideNoEnemy end,
              set = set("visHideNoEnemy", function() MM.Elements.ApplyVisibility() end) },
        } },
    }

    for _, section in ipairs(MM.Elements.Options(set, positions)) do
        rows[#rows + 1] = section
    end
    return rows
end
