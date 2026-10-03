-- VuloForeverUI / Modules / Minimap / Style: module registration and the remember/restore bookkeeping
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
        queueScale   = 1,               -- the queue eye, in every look: a factor on the client's size
        queuePos     = nil,             -- its own place from our edit mode; nil = where the look puts it
    },
})
MM.mod = mod

-- Private to the Style files (Style, StyleLooks, StyleApply); filled as the
-- pieces below are defined.
mod._style = {}
local P = mod._style

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
    -- The scale BEFORE the points: on an Edit Mode system (the queue eye)
    -- SetScale rescales whatever points the frame has, and run after the
    -- restore it scaled the saved ones -- a little further on every pass.
    if entry.scale and frame.SetScale then set("SetScale", entry.scale) end
    if not entry.keepPoints then
        frame:ClearAllPoints()
        for _, pt in ipairs(entry.points) do set("SetPoint", unpack(pt)) end
    end
    if entry.w and entry.w > 0 then set("SetSize", entry.w, entry.h) end
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

P.remember          = remember
-- The snapshot taken of a frame before any look changed it, or nil.
P.savedOf           = function(key) return saved[key] end
P.restore           = restore
P.rememberButtonArt = rememberButtonArt
P.restoreButtonArt  = restoreButtonArt
P.ours              = ours
P.region            = region
P.hideOurs          = hideOurs
