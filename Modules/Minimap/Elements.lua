-- VuloForeverUI / Modules / Minimap / Elements
--
-- The readouts that sit on or beside the map: coordinates, the zone name, the
-- clock, a framerate and latency line, and the instance difficulty.
--
-- All five are the same thing wearing different text, so they are built from
-- one description each and share a single ticker. Nothing here polls per frame:
-- C_Map.GetPlayerMapPosition allocates about 1.8 KB per call, and a framerate
-- that updates sixty times a second is unreadable anyway.
local _, ns = ...
local L = ns.L

local MM = ns.MM
local Elements = {}
MM.Elements = Elements

local db = function() return MM.mod.db end

-- ---------------------------------------------------------------------------
-- What each element says
--
-- A provider returns the finished string, or nil to stay empty. They run inside
-- the shared ticker, so a nil is cheaper than an error.
-- ---------------------------------------------------------------------------
local function coordsText()
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    if not x then return nil end
    local fmt = db().coordsPrecision > 0 and "%.1f, %.1f" or "%d, %d"
    return fmt:format(x * 100, y * 100)
end

local function zoneText()
    local d = db()
    local sub = d.zoneSubzone and GetMinimapZoneText()
    if sub and sub ~= "" then return sub end
    return GetZoneText()
end

-- The zone's own colour: sanctuary blue, friendly green, contested yellow,
-- hostile red. PVPTYPE colours are Blizzard's own table, so the wording stays
-- whatever the client calls it.
local function zoneColor()
    if not db().zoneReactiveColor then return nil end
    local pvpType = C_PvP.GetZonePVPInfo()
    if pvpType == "sanctuary" then return { r = .41, g = .8, b = .94 } end
    if pvpType == "friendly" then return { r = .1, g = 1, b = .1 } end
    if pvpType == "hostile" then return { r = 1, g = .1, b = .1 } end
    if pvpType == "contested" then return { r = 1, g = .7, b = 0 } end
    return nil
end

local function clockText()
    local hour, minute = GetGameTime()
    if db().clock24 then return ("%02d:%02d"):format(hour, minute) end
    local suffix = hour >= 12 and "pm" or "am"
    local h = hour % 12
    if h == 0 then h = 12 end
    return ("%d:%02d %s"):format(h, minute, suffix)
end

local function fpsText()
    local parts = { ("%d fps"):format(math.floor(GetFramerate() + 0.5)) }
    if db().fpsShowMS then
        local _, _, home, world = GetNetStats()
        parts[#parts + 1] = ("%d ms"):format(math.max(home or 0, world or 0))
    end
    return table.concat(parts, "  ")
end

-- "5M", "25H", "M+" -- the short form that fits next to the map.
local function difficultyText()
    local name, instanceType, _, difficultyName, maxPlayers = GetInstanceInfo()
    if not name or instanceType == "none" then return nil end
    if maxPlayers and maxPlayers > 0 then
        local short = (difficultyName or ""):sub(1, 1):upper()
        return ("%d%s"):format(maxPlayers, short ~= "" and short or "")
    end
    return difficultyName
end

-- ---------------------------------------------------------------------------
-- The elements themselves
--
-- `key` names the settings (coords -> coordsMode, coordsSize, ...), `provider`
-- writes the text, `interval` is how often it is worth asking.
-- ---------------------------------------------------------------------------
-- The settings each readout owns, written out rather than built with ".." --
-- a name that only exists at runtime is a name nothing can check.
local DEFS = {
    { key = "coords", provider = coordsText, interval = 0.2,
      mode = "coordsMode", pos = "coordsPosition", size = "coordsSize",
      ox = "coordsOffsetX", oy = "coordsOffsetY", scale = "coordsScale" },
    { key = "zone", provider = zoneText, interval = 1, colour = zoneColor,
      mode = "zoneMode", pos = "zonePosition", size = "zoneSize",
      ox = "zoneOffsetX", oy = "zoneOffsetY", scale = "zoneScale" },
    { key = "clock", provider = clockText, interval = 1,
      mode = "clockMode", pos = "clockPosition", size = "clockSize",
      ox = "clockOffsetX", oy = "clockOffsetY", scale = "clockScale" },
    { key = "fps", provider = fpsText, interval = 3,
      mode = "fpsMode", pos = "fpsPosition", size = "fpsSize",
      ox = "fpsOffsetX", oy = "fpsOffsetY", scale = "fpsScale" },
    { key = "diff", provider = difficultyText, interval = 2,
      mode = "diffMode", pos = "diffPosition", size = "diffSize",
      ox = "diffOffsetX", oy = "diffOffsetY", scale = "diffScale" },
}

local ticker, sinceLast = nil, {}

-- Per readout: a small frame of ours on the map (the thing our edit mode drags)
-- with the text inside it. frames[key] is that frame, frames[key].text the text.
local frames = {}

-- An example for our edit mode, for a readout that has nothing to say right now
-- (the difficulty outside an instance, the coordinates where there are none).
local SAMPLE = { coords = "45, 62", zone = "Zone", clock = "12:00", fps = "60 fps", diff = "5H" }

local editing = false

local function want(def)
    local d = db()
    -- The style decides who draws what; in standard we draw nothing at all.
    if not MM.Allows(def.key) then return false end
    local mode = d[def.mode]
    if mode == "never" or mode == "none" then return false end
    -- "hover" only shows while the mouse is on the map; the ticker still runs
    -- so the text is current the moment it appears.
    return true
end

-- The little nudge each mode adds on top of the offsets: "edge" hangs the text
-- just outside the map, "inside" lays it on top.
local function modeNudge(def)
    local d = db()
    local point = d[def.pos] or "BOTTOM"
    if d[def.mode] == "edge" then
        if point:find("TOP") then return 14 elseif point:find("BOTTOM") then return -14 end
    else
        if point:find("TOP") then return -4 elseif point:find("BOTTOM") then return 4 end
    end
    return 0
end

local function positionOf(def)
    local d = db()
    local point = d[def.pos] or "BOTTOM"
    return point, d[def.ox] or 0, (d[def.oy] or 0) + modeNudge(def)
end

-- ---------------------------------------------------------------------------
-- Moving them in our edit mode
--
-- One mover per readout: each already has its own corner, offset, size and
-- scale, and they are switched on one by one, so one box for a group would
-- have to carry readouts that are not even there.
--
-- THE POSITION MODEL. The saved truth stays what the options write: a corner
-- of the map (coordsPosition, ...) and an offset from it (coordsOffsetX/Y, in
-- the readout's own scaled units). So a readout keeps following the map
-- wherever the map goes, and the corner choice keeps its meaning: a drag only
-- changes the offset from the corner that is chosen, it never picks another.
--
-- The mover wants a centre offset from the middle of the screen instead. It
-- gets a table of its own that is never saved (POS[key]) holding the absolute
-- centre those settings work out to; a drop, a nudge, the edit panel's X/Y or
-- a discard write it, and it is turned back into the offset from the corner.
-- A reset puts the offset back to 0, 0 -- the chosen corner itself.
-- ---------------------------------------------------------------------------
local POS, SYNCED, OPEN = {}, {}, {}
for _, def in ipairs(DEFS) do POS[def.key] = {} end

-- x / y of a named point on a frame, in that frame's own units
local function pointX(frame, point)
    local l, w = frame:GetLeft(), frame:GetWidth()
    if not (l and w) then return nil end
    if point:find("LEFT") then return l elseif point:find("RIGHT") then return l + w end
    return l + w / 2
end

local function pointY(frame, point)
    local b, h = frame:GetBottom(), frame:GetHeight()
    if not (b and h) then return nil end
    if point:find("BOTTOM") then return b elseif point:find("TOP") then return b + h end
    return b + h / 2
end

-- The map's corner and UIParent's centre, both carried into the box's units,
-- and the step from the box's own corner to its centre. nil without rects.
local function geometry(def, box)
    local point = db()[def.pos] or "BOTTOM"
    local es = box:GetEffectiveScale() or 1
    if es == 0 then return nil end
    local ms = (Minimap:GetEffectiveScale() or 1) / es
    local us = (UIParent:GetEffectiveScale() or 1) / es
    local mx, my = pointX(Minimap, point), pointY(Minimap, point)
    local ux, uy = UIParent:GetCenter()
    if not (mx and my and ux and uy) then return nil end
    local w, h = box:GetWidth() or 0, box:GetHeight() or 0
    local cx = point:find("LEFT") and w / 2 or (point:find("RIGHT") and -w / 2 or 0)
    local cy = point:find("BOTTOM") and h / 2 or (point:find("TOP") and -h / 2 or 0)
    return mx * ms, my * ms, ux * us, uy * us, cx, cy
end

local function place(def)
    local box = frames[def.key]
    if not box then return end
    local point, x, y = positionOf(def)
    box:ClearAllPoints()
    box:SetPoint(point, Minimap, point, x, y)
    -- the mover's copy of where that is
    local mx, my, ux, uy, cx, cy = geometry(def, box)
    local pos = POS[def.key]
    if mx then
        pos.x, pos.y = mx + x + cx - ux, my + y + cy - uy
        SYNCED[def.key] = { pos.x, pos.y }
    else
        SYNCED[def.key] = nil
    end
end

-- the mover's centre -> the offset from the chosen corner
local function fromMover(def, x, y)
    local box = frames[def.key]
    if not box then return end
    local d, pos, o = db(), POS[def.key], OPEN[def.key]
    if ns._inMoverReset then
        d[def.ox], d[def.oy] = 0, 0
    elseif o and pos.x == o.x and pos.y == o.y then
        -- A discard handing back the pair read when the editor opened (the
        -- editor's snapshot is taken just before editPreview, from POS, which
        -- may be stale if the map moved since): the offsets from that moment,
        -- not a conversion against a map that may have moved.
        d[def.ox], d[def.oy] = o.ox, o.oy
    else
        local mx, my, ux, uy, cx, cy = geometry(def, box)
        if mx then
            d[def.ox] = (ux + x - cx) - mx
            d[def.oy] = (uy + y - cy) - my - modeNudge(def)
        end
    end
    place(def)
end

-- applyPos: ApplyMover, a nudge, a reset. A stored centre that still matches
-- what the offsets produced means nothing moved it; one that differs was
-- nudged and is read back. Never measured (no rect yet): the offsets win.
local function placeFromMover(def)
    local pos, sy = POS[def.key], SYNCED[def.key]
    if ns._inMoverReset then
        fromMover(def, 0, 0)
    elseif sy and pos.x and pos.y and (sy[1] ~= pos.x or sy[2] ~= pos.y) then
        fromMover(def, pos.x, pos.y)
    else
        place(def)
    end
end

local function moverLabel(key)
    local name
    if key == "coords" then name = L["Coordinates"]
    elseif key == "zone" then name = L["Zone Name"]
    elseif key == "clock" then name = L["Clock"]
    elseif key == "fps" then name = L["Framerate"]
    else name = L["Instance Difficulty"] end
    return L["Minimap: %s"]:format(name)
end

-- The box follows the text, so the edit box covers what it moves.
local function fitBox(box)
    local w, h = box.text:GetStringWidth() or 0, box.text:GetStringHeight() or 0
    box:SetSize(math.max(w, 16), math.max(h, 10))
end

local editPreview   -- below; the movers need it

local function create(def)
    local box = CreateFrame("Frame", nil, Minimap)
    box:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20)
    box:EnableMouse(false)
    box:SetSize(40, 14)
    box.text = box:CreateFontString(nil, "OVERLAY")
    frames[def.key] = box

    box.mover = ns:CreateMover(box, {
        key      = "minimap_" .. def.key,
        label    = moverLabel(def.key),
        db       = POS[def.key],
        module   = "minimapstyle",
        width    = 60,
        height   = 16,
        applyPos = function() placeFromMover(def) end,
        onMove   = function(x, y) fromMover(def, x, y) end,
        -- A mouseover readout is hidden most of the time, and the difficulty
        -- is empty outside an instance: while our edit mode is open every
        -- readout that is switched on shows, with an example if it is empty.
        editPreview = function(on) editPreview(on) end,
    })
    return box
end

local function apply(def)
    local d = db()
    local box = frames[def.key]
    if not want(def) then
        if box then box:Hide() end
        return
    end
    if not box then box = create(def) end
    local fs = box.text
    fs:SetFont(ns.ModuleFontPath("minimapstyle"), d[def.size] or 11, "OUTLINE")
    box:SetScale(d[def.scale] or 1)
    -- The text sits on the same corner of the box as the box on the map, so
    -- it lands exactly where it sat when it was anchored to the map itself.
    local point = d[def.pos] or "BOTTOM"
    fs:ClearAllPoints()
    fs:SetPoint(point, box, point, 0, 0)
    local text = fs:GetText()
    if editing and (type(text) ~= "string" or text == "") then fs:SetText(SAMPLE[def.key]) end
    fitBox(box)
    ns:ApplyMover(box.mover)
    local c = def.colour and def.colour()
    if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 1, 1) end
    box:SetShown(d[def.mode] ~= "hover" or Elements.hovered or editing)
end

function editPreview(on)
    on = (on and MM.mod.active) and true or false
    if on and not editing then
        local d = db()
        for _, def in ipairs(DEFS) do
            local pos = POS[def.key]
            OPEN[def.key] = { x = pos.x, y = pos.y, ox = d[def.ox], oy = d[def.oy] }
        end
    elseif not on then
        wipe(OPEN)
    end
    editing = on
    if not MM.mod.active then return end
    for _, def in ipairs(DEFS) do
        apply(def)
        -- the example goes again: the real text straight away, not on the
        -- next tick, which for some readouts is seconds off
        local box = frames[def.key]
        if not on and box and box:IsShown() then
            local ok, text = pcall(def.provider)
            box.text:SetText((ok and text) or "")
            fitBox(box)
        end
    end
end


local function tick(_, elapsed)
    for _, def in ipairs(DEFS) do
        local box = frames[def.key]
        if box and box:IsShown() then
            sinceLast[def.key] = (sinceLast[def.key] or 0) + 0.2
            if sinceLast[def.key] >= def.interval then
                sinceLast[def.key] = 0
                local fs = box.text
                local ok, text = pcall(def.provider)
                text = (ok and text) or ""
                if editing and text == "" then text = SAMPLE[def.key] end
                fs:SetText(text)
                fitBox(box)
                local c = def.colour and def.colour()
                if c then fs:SetTextColor(c.r, c.g, c.b) end
            end
        end
    end
end

function Elements.Apply()
    for _, def in ipairs(DEFS) do apply(def) end
    wipe(sinceLast)
    local any = false
    for _, def in ipairs(DEFS) do
        if want(def) then any = true break end
    end
    if any and not ticker then
        ticker = ns:AddTicker(0.2, tick, nil, "minimapstyle")
        tick()
    elseif not any and ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
end

-- Mouseover elements come and go with the cursor.
function Elements.SetHovered(on)
    Elements.hovered = on and true or false
    local d = db()
    for _, def in ipairs(DEFS) do
        local box = frames[def.key]
        if box and d[def.mode] == "hover" then box:SetShown(Elements.hovered or editing) end
    end
    if Elements.hovered then tick() end
end

function Elements.HideAll()
    for _, box in pairs(frames) do box:Hide() end
    if ticker then ns:CancelTicker(ticker); ticker = nil end
end

-- ---------------------------------------------------------------------------
-- Visibility: when the whole map should be out of the way
-- ---------------------------------------------------------------------------
function Elements.ApplyVisibility()
    local d = db()
    local show = true
    if d.visibility == "instances" then
        local _, kind = IsInInstance()
        show = kind ~= nil and kind ~= "none"
    elseif d.visibility == "never" then
        show = false
    end
    if show and d.visHideMounted and IsMounted and IsMounted() then show = false end
    if show and d.visHideNoTarget and not UnitExists("target") then show = false end
    if show and d.visHideNoEnemy and not (UnitExists("target") and UnitCanAttack("player", "target")) then
        show = false
    end
    if MinimapCluster then MinimapCluster:SetShown(show) end
end

-- The option rows for everything in this file. Kept here so the settings sit
-- next to the code that reads them.
function Elements.Options(set, positions)
    local d = db()
    local byKey = {}
    for _, def in ipairs(DEFS) do byKey[def.key] = def end

    local function textRows(key, label, modeValues, extra)
        local def = byKey[key]
        local off = function() local m = d[def.mode]; return m == "never" or m == "none" end
        local rows = {
            { type = "dropdown", label = label, values = modeValues,
              get = function() return d[def.mode] end, set = set(def.mode) },
            { type = "dropdown", label = L["Position"], values = positions, disabled = off,
              get = function() return d[def.pos] end, set = set(def.pos) },
            { type = "slider", label = L["Size"], min = 6, max = 24, step = 1, disabled = off,
              get = function() return d[def.size] end, set = set(def.size) },
            { type = "slider", label = L["Scale"], min = 0.5, max = 2, step = 0.05, disabled = off,
              get = function() return d[def.scale] end, set = set(def.scale) },
            { type = "slider", label = L["X Offset"], min = -200, max = 200, step = 1, disabled = off,
              get = function() return d[def.ox] end, set = set(def.ox) },
            { type = "slider", label = L["Y Offset"], min = -200, max = 200, step = 1, disabled = off,
              get = function() return d[def.oy] end, set = set(def.oy) },
        }
        for _, row in ipairs(extra or {}) do rows[#rows + 1] = row end
        return { type = "section", title = label, items = rows }
    end

    local showHide = {
        { value = "none", text = L["Hidden"] },
        { value = "inside", text = L["On the map"] },
        { value = "edge", text = L["At the edge"] },
    }
    local never = {
        { value = "never", text = L["Never"] },
        { value = "hover", text = L["On mouseover"] },
        { value = "always", text = L["Always"] },
    }

    return {
        textRows("coords", L["Coordinates"], never, {
            { type = "slider", label = L["Decimals"], min = 0, max = 1, step = 1,
              get = function() return d.coordsPrecision end, set = set("coordsPrecision") },
        }),
        textRows("zone", L["Zone Name"], showHide, {
            { type = "toggle", label = L["Prefer the subzone"],
              get = function() return d.zoneSubzone end, set = set("zoneSubzone") },
            { type = "toggle", label = L["Colour by zone type"],
              tooltip = L["Sanctuary, friendly, contested or hostile."],
              get = function() return d.zoneReactiveColor end, set = set("zoneReactiveColor") },
        }),
        textRows("clock", L["Clock"], showHide, {
            { type = "toggle", label = L["24-hour time"],
              get = function() return d.clock24 end, set = set("clock24") },
        }),
        textRows("fps", L["Framerate"], showHide, {
            { type = "toggle", label = L["Show latency too"],
              get = function() return d.fpsShowMS end, set = set("fpsShowMS") },
        }),
        textRows("diff", L["Instance Difficulty"], showHide),
    }
end
