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

-- ---------------------------------------------------------------------------
-- Remembering what we found
--
-- Every frame we move is written down the first time we touch it, so "standard"
-- is a real restore and not a second guess at Blizzard's layout.
-- ---------------------------------------------------------------------------
local saved = {}

local function remember(frame, key)
    if not frame or saved[key] then return end
    local entry = { parent = frame:GetParent(), points = {} }
    local ok, w, h = pcall(frame.GetSize, frame)
    if ok then entry.w, entry.h = w, h end
    for i = 1, (frame.GetNumPoints and frame:GetNumPoints() or 0) do
        local p, rel, relP, x, y = frame:GetPoint(i)
        entry.points[i] = { p, rel, relP, x, y }
    end
    saved[key] = entry
end

local function restore(frame, key)
    local entry = saved[key]
    if not (frame and entry) then return end
    frame:ClearAllPoints()
    for _, pt in ipairs(entry.points) do
        pcall(frame.SetPoint, frame, pt[1], pt[2], pt[3], pt[4], pt[5])
    end
    if entry.w and entry.w > 0 then pcall(frame.SetSize, frame, entry.w, entry.h) end
    saved[key] = nil
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

local function hideOurs(parent)
    local set = ours[parent]
    if not set then return end
    for _, tex in pairs(set) do tex:Hide() end
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

-- What sits around the edge. Every one of these is optional and every one is
-- a Blizzard frame, so nothing here is more than a Show or a Hide.
local function applyClutter()
    local db = mod.db
    local cluster = MinimapCluster
    setShown(Minimap.ZoomIn, not db.hideZoom)
    setShown(Minimap.ZoomOut, not db.hideZoom)
    if cluster then
        setShown(cluster.Tracking, not db.hideTracking)
        setShown(cluster.IndicatorFrame, not db.hideMail)
        setShown(cluster.DielFrame, not db.hideDiel)
        setShown(cluster.BorderTop, db.style == "standard")
        -- Blizzard's zone text steps aside for our own readout unless we are
        -- hands-off in standard.
        if cluster.ZoneTextButton then
            setShown(cluster.ZoneTextButton, db.style == "standard")
        end
    end
    if _G.TimeManagerClockButton then
        setShown(_G.TimeManagerClockButton, db.style == "standard" or not db.hideClock)
    end
end

-- ---------------------------------------------------------------------------
-- The three looks
-- ---------------------------------------------------------------------------
local function applyStandard()
    local cluster = MinimapCluster
    hideOurs(cluster)
    hideOurs(MinimapBackdrop)
    restore(cluster and cluster.MinimapContainer, "container")
    restore(Minimap, "map")
    restore(MinimapBackdrop, "backdrop")
    restore(cluster and cluster.ZoneTextButton, "zonebtn")
    restore(Minimap.ZoomIn, "zoomin")
    restore(Minimap.ZoomOut, "zoomout")
    restore(cluster, "cluster")
    restore(cluster and cluster.Tracking, "tracking")
    restore(cluster and cluster.IndicatorFrame, "mail")
    restore(_G.TimeManagerClockButton, "clock")
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

-- The 1.x cluster: a 192px frame with the map sunk into it, the zone name
-- across the top and the buttons riding the rim. Every number here is the
-- original layout; the art is Blizzard's own, so a client that does not ship
-- it leaves the frame empty and the placement still holds.
local function applyClassic()
    local cluster, backdrop, map = MinimapCluster, MinimapBackdrop, Minimap
    if not (cluster and backdrop and map) then return end
    for frame, key in pairs({ [cluster] = "cluster", [backdrop] = "backdrop", [map] = "map" }) do
        remember(frame, key)
    end
    remember(cluster.MinimapContainer, "container")
    remember(cluster.ZoneTextButton, "zonebtn")
    remember(cluster.Tracking, "tracking")
    remember(cluster.IndicatorFrame, "mail")
    remember(_G.TimeManagerClockButton, "clock")

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
    for _, e in ipairs({ { map.ZoomIn, 72, -25 }, { map.ZoomOut, 50, -43 } }) do
        local button = e[1]
        if button then
            button:SetParent(backdrop)
            button:SetFrameLevel(above)
            button:SetSize(32, 32)
            button:ClearAllPoints()
            button:SetPoint("CENTER", backdrop, "CENTER", e[2], e[3])
        end
    end
    if cluster.Tracking then
        cluster.Tracking:SetParent(backdrop)
        cluster.Tracking:SetFrameLevel(above)
        cluster.Tracking:SetSize(32, 32)
        cluster.Tracking:ClearAllPoints()
        cluster.Tracking:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 9, -45)
    end
    if cluster.IndicatorFrame then
        cluster.IndicatorFrame:SetFrameLevel(above)
        cluster.IndicatorFrame:SetSize(33, 33)
        cluster.IndicatorFrame:ClearAllPoints()
        cluster.IndicatorFrame:SetPoint("TOPRIGHT", map, "TOPRIGHT", 24, -37)
    end
    if cluster.DielFrame then
        cluster.DielFrame:ClearAllPoints()
        cluster.DielFrame:SetPoint("TOPRIGHT", map, "TOPRIGHT", 20, -2)
    end
    if _G.TimeManagerClockButton then
        local clock = _G.TimeManagerClockButton
        clock:SetParent(map)
        clock:SetFrameLevel(above)
        clock:ClearAllPoints()
        clock:SetPoint("CENTER", map, "CENTER", 0, -75)
    end
    cluster:SetScale(mod.db.scale)
end

local function applyModern()
    local cluster, backdrop = MinimapCluster, MinimapBackdrop
    if not cluster then return end
    remember(cluster, "cluster")
    remember(Minimap, "map")
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
    if not ok then ns:Print(L["|cffff5555Minimap style failed:|r %s"], tostring(err)) end
end

local function onEnter() MM.Elements.SetHovered(true) end
local function onLeave() MM.Elements.SetHovered(false) end

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
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:Apply() end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", updateCoords)
    -- the Camelot skin rebuilds itself when this CVar flips, undoing our work
    self:RegisterEvent("CVAR_UPDATE", function(_, name)
        if name == "rotateMinimap" then ns.NextFrame(function() self:Apply() end) end
    end)
    Minimap:HookScript("OnEnter", onEnter)
    Minimap:HookScript("OnLeave", onLeave)
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if not mod.db.scrollZoom then return end
        if delta > 0 then Minimap.ZoomIn:Click() else Minimap.ZoomOut:Click() end
        scheduleZoomReset()
    end)
    Minimap:HookScript("OnMouseUp", function(_, button)
        if button == "MiddleButton" and mod.db.middleClickMenu then
            if _G.MainMenuMicroButton and _G.ToggleFrame then
                pcall(_G.ToggleFrame, _G.MicroMenuContainer)
            end
        end
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
    Minimap:SetScript("OnMouseWheel", nil)
    applyStandard()
    applyClutter()
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
              tooltip = L["Our own clock readout replaces it; see the Clock section."],
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
