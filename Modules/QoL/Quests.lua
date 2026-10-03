-- VuloForeverUI / Modules / QoL / Quests
--
-- Quest help without a quest database of our own:
--
--   available  a yellow ! on the minimap for every quest the client offers in
--              this zone -- the same list the world map draws its offers from
--              (C_QuestLine.GetAvailableQuestLines, filled after
--              RequestQuestLinesForMap and announced by QUESTLINE_UPDATE)
--   turn-in    a yellow ? where a finished quest is handed in: the quest's map
--              point (C_QuestLog.GetQuestsOnMap) is the quest giver once the
--              objectives are done
--   tooltip    on an item an open quest asks for, the quest and how many you
--              have; units carry their quest lines from the client already
--
-- WHERE A PIN GOES
--
-- Both the player and the pin are positions on the same zone map. The map's
-- corners in world yards (C_Map.GetWorldPosFromMapPos) turn the difference
-- into yards east and north, the minimap's view radius (C_Minimap.
-- GetViewRadius) turns yards into pixels, and with a rotating minimap the
-- offset turns with the player's facing. Outside the minimap a pin hides.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Q = QoL.RegisterPart("quests", {})
QoL.Quests = Q

local registered, hookedTooltip
local mapID, mapW, mapH
local offers, turnins = {}, {}
local pins, used = {}, 0
local holder
local itemObjectives = {}

local function db() return QoL.db().quest end

local function readable(v)
    if ns.CanRead(v) then return v end
    return nil
end

local function isTrue(v) return ns.CanRead(v) and v == true end

-- ----------------------------------------------------------------- map --

local function measure(id)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local _, tl = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(0, 0))
    local _, br = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(1, 1))
    if not (tl and br) then return nil end
    local top, left = tl:GetXY()
    local bottom, right = br:GetXY()
    if not (top and left and bottom and right) then return nil end
    local w, h = left - right, top - bottom
    if w <= 0 or h <= 0 then return nil end
    return w, h
end

local function currentMap()
    local id = readable(C_Map.GetBestMapForUnit("player"))
    if type(id) ~= "number" then return nil end
    return id
end

-- -------------------------------------------------------------- the data --

local function collectOffers()
    wipe(offers)
    if not (db().available and mapID and C_QuestLine and C_QuestLine.GetAvailableQuestLines) then return end
    local ok, list = pcall(C_QuestLine.GetAvailableQuestLines, mapID)
    if not (ok and type(list) == "table") then return end
    for _, info in ipairs(list) do
        local id, x, y = readable(info.questID), readable(info.x), readable(info.y)
        local trivial = isTrue(info.isHidden)
        if id and x and y and (db().trivial or not trivial)
            and not isTrue(C_QuestLog.IsOnQuest(id)) then
            offers[#offers + 1] = { id = id, x = x, y = y, trivial = trivial,
                name = readable(info.questName), daily = isTrue(info.isDaily) }
        end
    end
end

local function collectTurnins()
    wipe(turnins)
    if not (db().turnIn and mapID and C_QuestLog.GetQuestsOnMap) then return end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if not (ok and type(list) == "table") then return end
    for _, info in ipairs(list) do
        local id, x, y = readable(info.questID), readable(info.x), readable(info.y)
        if id and x and y and isTrue(C_QuestLog.IsComplete(id)) then
            turnins[#turnins + 1] = { id = id, x = x, y = y, turnin = true,
                name = readable(C_QuestLog.GetTitleForQuestID(id)) }
        end
    end
end

-- Which items the open quests ask for, by the objective text: "Egg: 3/15".
local function collectObjectives()
    wipe(itemObjectives)
    if not db().tooltip then return end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and readable(info.questID) then
            local objs = C_QuestLog.GetQuestObjectives(info.questID)
            for _, o in ipairs(objs or {}) do
                local text = readable(o.text)
                if o.type == "item" and type(text) == "string" then
                    itemObjectives[#itemObjectives + 1] = {
                        title = readable(info.title) or "?", text = text,
                        have = readable(o.numFulfilled), need = readable(o.numRequired),
                        done = isTrue(o.finished),
                    }
                end
            end
        end
    end
end

-- ----------------------------------------------------------------- pins --

local function pinEnter(self)
    local d = self.data
    if not d then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(d.name or L["Quest"], 1, 0.82, 0)
    if d.turnin then
        GameTooltip:AddLine(L["Ready to hand in"], 0.35, 0.85, 0.4)
    elseif d.trivial then
        GameTooltip:AddLine(L["Available quest (low level)"], 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(L["Available quest"], 1, 1, 1)
    end
    GameTooltip:Show()
end

local function pinLeave() GameTooltip:Hide() end

local function pin(i)
    local p = pins[i]
    if p then return p end
    p = CreateFrame("Button", nil, holder)
    p.icon = p:CreateTexture(nil, "OVERLAY")
    p.icon:SetAllPoints()
    p:SetScript("OnEnter", pinEnter)
    p:SetScript("OnLeave", pinLeave)
    pins[i] = p
    return p
end

local function assign()
    used = 0
    local size = db().pinSize
    local function add(d)
        used = used + 1
        local p = pin(used)
        p.data = d
        p:SetSize(size, size)
        p.icon:SetAtlas(d.turnin and "QuestTurnin" or (d.daily and "QuestDaily" or "QuestNormal"))
        p.icon:SetDesaturated(d.trivial and true or false)
        p.icon:SetAlpha(d.trivial and 0.6 or 1)
    end
    for _, d in ipairs(turnins) do add(d) end
    for _, d in ipairs(offers) do add(d) end
    for i = used + 1, #pins do pins[i]:Hide(); pins[i].data = nil end
end

local function round()
    local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
    return shape == "ROUND"
end

local function place()
    if used == 0 or not (mapID and mapW) then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    px, py = readable(px), readable(py)
    local radius = C_Minimap.GetViewRadius and readable(C_Minimap.GetViewRadius())
    if not (px and py and type(radius) == "number" and radius > 0) then
        for i = 1, used do pins[i]:Hide() end
        return
    end
    local half = Minimap:GetWidth() / 2
    local facing = (GetCVar("rotateMinimap") == "1") and readable(GetPlayerFacing())
    local cosF, sinF = 1, 0
    if type(facing) == "number" then cosF, sinF = math.cos(facing), math.sin(facing) end
    local isRound = round()
    local scale = half / radius
    for i = 1, used do
        local p = pins[i]
        local d = p.data
        local east = (d.x - px) * mapW
        local north = (py - d.y) * mapH
        local x = (east * cosF + north * sinF) * scale
        local y = (north * cosF - east * sinF) * scale
        local inside
        if isRound then inside = (x * x + y * y) <= half * half
        else inside = math.abs(x) <= half and math.abs(y) <= half end
        if inside then
            p:ClearAllPoints()
            p:SetPoint("CENTER", Minimap, "CENTER", x, y)
            p:Show()
        else
            p:Hide()
        end
    end
end

-- ------------------------------------------------------------- refresh --

local queued

local function refresh()
    queued = nil
    if not registered then return end
    local id = currentMap()
    if id ~= mapID then
        mapID = id
        mapW, mapH = nil, nil
        if id then
            mapW, mapH = measure(id)
            if db().available and C_QuestLine and C_QuestLine.RequestQuestLinesForMap then
                pcall(C_QuestLine.RequestQuestLinesForMap, id)
            end
        end
    end
    collectOffers()
    collectTurnins()
    collectObjectives()
    assign()
    place()
end

-- Quest log updates come in bursts; one refresh per burst is enough.
local function queue()
    if queued then return end
    queued = true
    C_Timer.After(0.3, refresh)
end

-- ------------------------------------------------------------- tooltip --

local function onItemTooltip(tooltip, data)
    if not (registered and db().tooltip) or #itemObjectives == 0 then return end
    if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
    local id = data and readable(data.id)
    if type(id) ~= "number" then return end
    local name = C_Item.GetItemNameByID(id)
    name = readable(name)
    if type(name) ~= "string" or name == "" then return end
    local added
    for _, o in ipairs(itemObjectives) do
        if o.text:find(name, 1, true) then
            if not added then tooltip:AddLine(" "); added = true end
            local progress = (o.have and o.need) and ("%d/%d"):format(o.have, o.need) or ""
            if o.done then
                tooltip:AddDoubleLine(o.title, progress, 0.35, 0.85, 0.4, 0.35, 0.85, 0.4)
            else
                tooltip:AddDoubleLine(o.title, progress, 1, 0.82, 0, 1, 1, 1)
            end
        end
    end
end

local function hookTooltip()
    if hookedTooltip or not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall) then return end
    hookedTooltip = true
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        local ok, err = pcall(onItemTooltip, tooltip, data)
        if not ok then ns:Debug("qol quest tooltip: %s", tostring(err)) end
    end)
end

-- --------------------------------------------------------------- switch --

local EVENTS = {
    PLAYER_ENTERING_WORLD = queue,
    ZONE_CHANGED_NEW_AREA = queue,
    ZONE_CHANGED = queue,
    ZONE_CHANGED_INDOORS = queue,
    QUEST_LOG_UPDATE = queue,
    QUESTLINE_UPDATE = queue,
    QUEST_ACCEPTED = queue,
    QUEST_TURNED_IN = queue,
    PLAYER_LEVEL_UP = queue,
}

local function wanted()
    local d = db()
    return QoL.mod.active and (d.available or d.turnIn or d.tooltip) and true or false
end

local function ensureHolder()
    if holder or not Minimap then return end
    holder = CreateFrame("Frame", nil, Minimap)
    holder:SetAllPoints(Minimap)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    local acc = 0
    holder:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.05 then return end
        acc = 0
        place()
    end)
end

function Q.Apply()
    local on = wanted()
    if on then
        ensureHolder()
        if db().tooltip then hookTooltip() end
    end
    if on ~= registered then
        registered = on
        for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    end
    if holder then holder:SetShown(on) end
    mapID = nil   -- a setting may have changed what is collected
    if on then refresh() end
end

function Q.Disable()
    if registered then
        for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    end
    registered = nil
    if holder then holder:Hide() end
end

-- For the options: how many offers the client gave for this zone, so a
-- player can tell "no quests here" from "this client gives no offers".
function Q.Counts()
    return #offers, #turnins
end
