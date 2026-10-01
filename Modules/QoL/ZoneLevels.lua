-- VuloForeverUI / Modules / QoL / ZoneLevels
--
-- The level range of a zone on the world map, in its top left corner,
-- coloured the way the client colours quests: grey when you have outgrown it,
-- red while it is still above you. On a zone's own map that zone; on a
-- continent the zone under the cursor.
--
-- WHERE THE NUMBERS COME FROM
--
-- The client's own C_Map.GetMapLevels first -- but on this server it answers
-- 0 for every zone (seen in game), so the original ranges of the 1.x world
-- stand in, from a table below. That table carries two map numberings, the
-- 14xx one of the 1.x clients and the low one of the modern client, because
-- this client's numbering is not documented anywhere. Which one applies is
-- decided once, by asking the client what its Kalimdor is called; the other
-- set is never looked at, so a number that means another map in the other
-- system can never pick up a wrong range.
local _, ns = ...

local QoL = ns.QoL
local ZoneLevels = QoL.RegisterPart("zonelevels", {})
QoL.ZoneLevels = ZoneLevels

local function db() return QoL.db().world end

local label

-- { min, max, 1.x map ID, modern map ID }. Cities and Moonglade have no range
-- and are left out.
local ZONES = {
    -- Kalimdor
    { 1, 10,  1411, 1 },   -- Durotar
    { 1, 10,  1412, 7 },   -- Mulgore
    { 10, 25, 1413, 10 },  -- The Barrens
    { 1, 10,  1438, 57 },  -- Teldrassil
    { 10, 20, 1439, 62 },  -- Darkshore
    { 18, 30, 1440, 63 },  -- Ashenvale
    { 25, 35, 1441, 64 },  -- Thousand Needles
    { 15, 27, 1442, 65 },  -- Stonetalon Mountains
    { 30, 40, 1443, 66 },  -- Desolace
    { 40, 50, 1444, 69 },  -- Feralas
    { 35, 45, 1445, 70 },  -- Dustwallow Marsh
    { 40, 50, 1446, 71 },  -- Tanaris
    { 45, 55, 1447, 76 },  -- Azshara
    { 48, 55, 1448, 77 },  -- Felwood
    { 48, 55, 1449, 78 },  -- Un'Goro Crater
    { 55, 60, 1451, 81 },  -- Silithus
    { 55, 60, 1452, 83 },  -- Winterspring
    -- Eastern Kingdoms
    { 30, 40, 1416, nil }, -- Alterac Mountains
    { 30, 40, 1417, 14 },  -- Arathi Highlands
    { 35, 45, 1418, 15 },  -- Badlands
    { 45, 55, 1419, 17 },  -- Blasted Lands
    { 1, 10,  1420, 18 },  -- Tirisfal Glades
    { 10, 20, 1421, 21 },  -- Silverpine Forest
    { 51, 58, 1422, 22 },  -- Western Plaguelands
    { 53, 60, 1423, 23 },  -- Eastern Plaguelands
    { 20, 30, 1424, 25 },  -- Hillsbrad Foothills
    { 40, 50, 1425, 26 },  -- The Hinterlands
    { 1, 10,  1426, 27 },  -- Dun Morogh
    { 43, 50, 1427, 32 },  -- Searing Gorge
    { 50, 58, 1428, 36 },  -- Burning Steppes
    { 1, 10,  1429, 37 },  -- Elwynn Forest
    { 55, 60, 1430, 42 },  -- Deadwind Pass
    { 18, 30, 1431, 47 },  -- Duskwood
    { 10, 20, 1432, 48 },  -- Loch Modan
    { 15, 25, 1433, 49 },  -- Redridge Mountains
    { 30, 45, 1434, 50 },  -- Stranglethorn Vale
    { 30, 45, nil,  210 }, -- (modern only: its southern half)
    { 35, 45, 1435, 51 },  -- Swamp of Sorrows
    { 10, 20, 1436, 52 },  -- Westfall
    { 20, 30, 1437, 56 },  -- Wetlands
    -- New on this client, in its own numbering. Riverglades as announced;
    -- Hyjal has no announced range, only "the endgame levelling zone".
    -- Shen'dralas and Zephras Isle stay out until their ranges are known.
    { 35, 45, 2548, nil }, -- Riverglades
    { 55, 60, 2482, nil }, -- Mount Hyjal
}

-- Which numbering this client uses: the one whose Kalimdor is a continent.
-- nil until asked, false when neither fits.
local byID

local function isContinent(id)
    local info = C_Map.GetMapInfo(id)
    return info and info.mapType == Enum.UIMapType.Continent or false
end

local function zoneTable()
    if byID ~= nil then return byID end
    local col = (isContinent(1414) and 3) or (isContinent(12) and 4) or nil
    byID = false
    if col then
        byID = {}
        for _, z in ipairs(ZONES) do
            if z[col] then byID[z[col]] = z end
        end
    end
    return byID
end

local function levelsFor(mapID)
    local minL, maxL = C_Map.GetMapLevels(mapID)
    if minL and maxL and minL > 0 and maxL > 0 then return minL, maxL end
    local t = zoneTable()
    local z = t and t[mapID]
    if z then return z[1], z[2] end
    return nil
end

-- Blizzard's own rule from the continent tooltip: a zone entirely below you
-- turns grey two levels early, so it never reads yellow.
local function rangeColor(minL, maxL)
    local level = ns.Num(UnitLevel("player"), 1)
    if level < minL then return GetQuestDifficultyColor(minL) end
    if level > maxL then return GetQuestDifficultyColor(maxL - 2) end
    return QuestDifficultyColors["difficult"]
end

-- The map shown, or on a map without a range of its own (a continent) the
-- zone under the cursor.
local function targetMap()
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return nil end
    if levelsFor(mapID) then return mapID end
    if not WorldMapFrame.ScrollContainer:IsMouseOver() then return nil end
    local x, y = WorldMapFrame:GetNormalizedCursorPosition()
    if not (x and y) then return nil end
    local info = C_Map.GetMapInfoAtPosition(mapID, x, y)
    return info and info.mapID ~= mapID and info.mapID or nil
end

local shown

local function update()
    if not label then return end
    if not (QoL.mod.active and db().zoneLevels and WorldMapFrame:IsShown()) then
        label:Hide(); shown = nil
        return
    end
    local mapID = targetMap()
    local minL, maxL
    if mapID then minL, maxL = levelsFor(mapID) end
    local info = minL and C_Map.GetMapInfo(mapID)
    if not (info and info.name) then label:Hide(); shown = nil; return end
    -- the cursor moves far more often than it changes zone
    local level = ns.Num(UnitLevel("player"), 1)
    local key = mapID * 1000 + level
    if shown == key and label:IsShown() then return end
    shown = key
    local c = rangeColor(minL, maxL)
    local range = (minL == maxL) and tostring(maxL) or (minL .. "-" .. maxL)
    label:SetFont(QoL.Font(), 14, QoL.Outline())
    label:SetFormattedText("%s |cff%02x%02x%02x(%s)|r", info.name,
        math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5), range)
    label:Show()
end

local function create()
    if label then return end
    if not (WorldMapFrame and WorldMapFrame.ScrollContainer) then return end
    local holder = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
    holder:SetFrameStrata("HIGH")
    holder:SetAllPoints()
    label = holder:CreateFontString(nil, "OVERLAY")
    -- clear of the round button the client puts in that corner
    label:SetPoint("TOPLEFT", holder, "TOPLEFT", 44, -10)
    label:SetJustifyH("LEFT")
    label:SetTextColor(1, 0.82, 0)
    -- Left corner, not the top centre: that is where the client writes the
    -- name of the zone under the cursor.
    EventRegistry:RegisterCallback("MapCanvas.MapSet", update, ZoneLevels)
    WorldMapFrame:HookScript("OnShow", update)
    -- for the cursor on a continent; the holder lives inside the map, so this
    -- only runs while the map is open
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.1 then return end
        acc = 0
        update()
    end)
end

local function apply()
    if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then return end
    if db().zoneLevels then create() end
    shown = nil   -- the font may have changed
    update()
end

local function onAddOnLoaded(_, name)
    -- The world map is loaded on demand, so the label waits for it.
    if name == "Blizzard_WorldMap" then apply() end
end

function ZoneLevels.Apply()
    local on = db().zoneLevels and true or false
    QoL.SyncEvent(on, "ADDON_LOADED",    onAddOnLoaded)
    QoL.SyncEvent(on, "PLAYER_LEVEL_UP", update)
    apply()
end

function ZoneLevels.Disable()
    QoL.SyncEvent(false, "ADDON_LOADED",    onAddOnLoaded)
    QoL.SyncEvent(false, "PLAYER_LEVEL_UP", update)
    if label then label:Hide() end
end
