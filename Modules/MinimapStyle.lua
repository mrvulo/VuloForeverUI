-- VuloForeverUI / Modules / MinimapStyle
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

        coordsMode      = "never",      -- never | hover | always
        coordsPosition  = "BOTTOM",
        coordsPrecision = 0,
        coordsSize      = 11,

        zoneMode     = "inside",        -- none | inside | top
        zonePosition = "TOP",
        zoneSize     = 12,
        showClock    = true,

        scrollZoom   = true,
        hideZoom     = true,
        hideTracking = false,
        hideMail     = false,
        hideDiel     = false,           -- Forever's day/night indicator
    },
})

local CLASSIC_CLUSTER, CLASSIC_MAP = 192, 140
local SQUARE_MASK  = "Interface\\Buttons\\WHITE8X8"
local ROUND_MASK   = "ui-hud-minimap-frame-generic-mask"
local CLASSIC_RING = "Interface\\Minimap\\UI-Minimap-Border"

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
    pcall(Minimap.SetMaskTexture, Minimap, round and ROUND_MASK or SQUARE_MASK)
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
        if cluster.ZoneTextButton then
            setShown(cluster.ZoneTextButton, db.zoneMode ~= "none" or db.style == "standard")
        end
    end
    if _G.TimeManagerClockButton then setShown(_G.TimeManagerClockButton, db.showClock) end
end

-- ---------------------------------------------------------------------------
-- Coordinates
--
-- C_Map.GetPlayerMapPosition allocates about 1.8 KB per call, so this never
-- runs per frame -- a ticker at 5 Hz is far more than the eye needs.
-- ---------------------------------------------------------------------------
local coordsText, coordsTicker

local function updateCoords()
    if not coordsText or not coordsText:IsShown() then return end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then coordsText:SetText("") return end
    local x, y = pos:GetXY()
    if not x then coordsText:SetText("") return end
    local fmt = mod.db.coordsPrecision > 0 and "%.1f, %.1f" or "%d, %d"
    coordsText:SetFormattedText(fmt, x * 100, y * 100)
end

local function applyCoords()
    local db = mod.db
    if db.coordsMode == "never" then
        if coordsText then coordsText:Hide() end
        if coordsTicker then ns:CancelTicker(coordsTicker); coordsTicker = nil end
        return
    end
    if not coordsText then
        coordsText = Minimap:CreateFontString(nil, "OVERLAY")
    end
    coordsText:SetFont(ns.ModuleFontPath("minimapstyle"), db.coordsSize, "OUTLINE")
    coordsText:ClearAllPoints()
    local inset = db.coordsPosition:find("TOP") and -4 or 4
    coordsText:SetPoint(db.coordsPosition, Minimap, db.coordsPosition, 0, inset)
    coordsText:SetShown(db.coordsMode == "always")
    if not coordsTicker then
        coordsTicker = ns:AddTicker(0.2, updateCoords, nil, "minimapstyle")
    end
    updateCoords()
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
    setShown(MinimapCompassTexture, true)
    if cluster then cluster:SetScale(mod.db.scale) end
    -- the client's own skin puts the frame and the mask back
    if _G.MinimapCluster_UpdateMinimapConfig then
        pcall(_G.MinimapCluster_UpdateMinimapConfig)
    end
end

-- The 1.x cluster: a heavy ring with the map sunk into it. The ring art is
-- Blizzard's own classic texture; if this client does not ship it the ring
-- simply stays empty and the rest of the layout still holds.
local function applyClassic()
    local cluster, backdrop = MinimapCluster, MinimapBackdrop
    if not (cluster and backdrop) then return end
    remember(cluster, "cluster")
    remember(cluster.MinimapContainer, "container")
    remember(Minimap, "map")
    remember(backdrop, "backdrop")
    remember(cluster.ZoneTextButton, "zonebtn")

    cluster:SetSize(CLASSIC_CLUSTER, CLASSIC_CLUSTER)
    if cluster.MinimapContainer then
        cluster.MinimapContainer:SetSize(CLASSIC_MAP, CLASSIC_MAP)
        cluster.MinimapContainer:ClearAllPoints()
        cluster.MinimapContainer:SetPoint("CENTER", cluster, "CENTER", 0, -6)
    end
    Minimap:SetSize(CLASSIC_MAP, CLASSIC_MAP)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", cluster.MinimapContainer or cluster, "CENTER", 0, 0)
    applyShape(true)

    backdrop:SetSize(CLASSIC_CLUSTER, CLASSIC_CLUSTER)
    backdrop:ClearAllPoints()
    backdrop:SetPoint("CENTER", Minimap, "CENTER", 0, 0)

    local ring = region(backdrop, "ring", "ARTWORK")
    ring:SetTexture(CLASSIC_RING)
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", Minimap, "CENTER", 10, -12)
    ring:SetSize(CLASSIC_MAP * 1.55, CLASSIC_MAP * 1.55)
    ring:Show()
    -- the Camelot frame would sit on top of the classic ring
    setShown(MinimapCompassTexture, false)

    if cluster.ZoneTextButton then
        cluster.ZoneTextButton:ClearAllPoints()
        cluster.ZoneTextButton:SetPoint("BOTTOM", Minimap, "TOP", 0, 14)
        cluster.ZoneTextButton:SetSize(CLASSIC_MAP, 14)
    end

    -- Zoom buttons ride the lower right of the ring and must sit above the map
    -- to take a click at all.
    local above = Minimap:GetFrameLevel() + 5
    for _, e in ipairs({ { Minimap.ZoomIn, "zoomin", 62, -50 }, { Minimap.ZoomOut, "zoomout", 44, -66 } }) do
        local button = e[1]
        if button then
            remember(button, e[2])
            button:SetParent(Minimap)
            button:SetFrameLevel(above)
            button:ClearAllPoints()
            button:SetPoint("CENTER", Minimap, "CENTER", e[3], e[4])
        end
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
        applyCoords()
        if style ~= "standard" then applyZoneSize() end
    end)
    applying = false
    if not ok then ns:Print(L["|cffff5555Minimap style failed:|r %s"], tostring(err)) end
end

local function onEnter()
    if mod.db.coordsMode == "hover" and coordsText then coordsText:Show(); updateCoords() end
end

local function onLeave()
    if mod.db.coordsMode == "hover" and coordsText then coordsText:Hide() end
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
    end)
    self:Apply()
end

function mod:OnDisable()
    if coordsTicker then ns:CancelTicker(coordsTicker); coordsTicker = nil end
    if coordsText then coordsText:Hide() end
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

    return {
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

        { type = "section", title = L["Text"], items = {
            { type = "dropdown", label = L["Coordinates"],
              values = {
                  { value = "never",  text = L["Never"] },
                  { value = "hover",  text = L["On mouseover"] },
                  { value = "always", text = L["Always"] },
              },
              get = function() return d.coordsMode end, set = set("coordsMode") },
            { type = "dropdown", label = L["Coordinate Position"], values = positions,
              disabled = function() return d.coordsMode == "never" end,
              get = function() return d.coordsPosition end, set = set("coordsPosition") },
            { type = "slider", label = L["Decimals"], min = 0, max = 1, step = 1,
              disabled = function() return d.coordsMode == "never" end,
              get = function() return d.coordsPrecision end, set = set("coordsPrecision") },
            { type = "slider", label = L["Coordinate Size"], min = 6, max = 20, step = 1,
              disabled = function() return d.coordsMode == "never" end,
              get = function() return d.coordsSize end, set = set("coordsSize") },
            { type = "dropdown", label = L["Zone Name"],
              values = {
                  { value = "none",   text = L["Hidden"] },
                  { value = "inside", text = L["On the map"] },
                  { value = "top",    text = L["Above the map"] },
              },
              get = function() return d.zoneMode end, set = set("zoneMode") },
            { type = "slider", label = L["Zone Name Size"], min = 6, max = 24, step = 1,
              disabled = function() return d.zoneMode == "none" end,
              get = function() return d.zoneSize end, set = set("zoneSize") },
            { type = "dropdown", label = L["Zone Name Position"], values = positions,
              disabled = function() return d.zoneMode ~= "inside" end,
              get = function() return d.zonePosition end, set = set("zonePosition") },
        } },

        { type = "section", title = L["Around the Map"], items = {
            { type = "toggle", label = L["Show Clock"],
              get = function() return d.showClock end, set = set("showClock") },
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
        } },
    }
end
