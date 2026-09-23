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

local frames = {}

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

local function positionOf(def)
    local d = db()
    local point = d[def.pos] or "BOTTOM"
    local x, y = d[def.ox] or 0, d[def.oy] or 0
    -- "edge" hangs the text just outside the map, "inside" lays it on top
    if d[def.mode] == "edge" then
        if point:find("TOP") then y = y + 14 elseif point:find("BOTTOM") then y = y - 14 end
    else
        if point:find("TOP") then y = y - 4 elseif point:find("BOTTOM") then y = y + 4 end
    end
    return point, x, y
end

local function apply(def)
    local d = db()
    local fs = frames[def.key]
    if not want(def) then
        if fs then fs:Hide() end
        return
    end
    if not fs then
        fs = Minimap:CreateFontString(nil, "OVERLAY")
        frames[def.key] = fs
    end
    fs:SetFont(ns.ModuleFontPath("minimapstyle"), d[def.size] or 11, "OUTLINE")
    fs:SetScale(d[def.scale] or 1)
    fs:ClearAllPoints()
    local point, x, y = positionOf(def)
    fs:SetPoint(point, Minimap, point, x, y)
    local c = def.colour and def.colour()
    if c then fs:SetTextColor(c.r, c.g, c.b) else fs:SetTextColor(1, 1, 1) end
    fs:SetShown(d[def.mode] ~= "hover" or Elements.hovered)
end

local ticker, sinceLast = nil, {}

local function tick(_, elapsed)
    for _, def in ipairs(DEFS) do
        local fs = frames[def.key]
        if fs and fs:IsShown() then
            sinceLast[def.key] = (sinceLast[def.key] or 0) + 0.2
            if sinceLast[def.key] >= def.interval then
                sinceLast[def.key] = 0
                local ok, text = pcall(def.provider)
                fs:SetText((ok and text) or "")
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
        local fs = frames[def.key]
        if fs and d[def.mode] == "hover" then fs:SetShown(Elements.hovered) end
    end
    if Elements.hovered then tick() end
end

function Elements.HideAll()
    for _, fs in pairs(frames) do fs:Hide() end
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
