-- VuloForeverUI / Modules / Nameplates / Extras
--
-- The three things a plate shows that are neither health, cast nor aura:
-- a marker on a quest mob, a glow when the target is low enough to finish, and
-- the combo points on the plate of whatever you are hitting.
--
-- Two of them look like they need a comparison and do not:
--
--   * the execute glow asks the CLIENT to turn health into a colour. A colour
--     curve is red below the threshold and black (nothing, under ADD) above it, and
--     UnitHealthPercent evaluates it for us -- so the decision "is this mob low
--     enough" is made in C on a number we never see.
--   * a combo point is one bar per pip, each scaled i-1 .. i and fed the secret
--     power. The third pip fills when the value passes 3. Geometry again.
--
-- The quest scan is the exception: tooltip lines really are read, so every
-- field is checked for readability first. Its answer is cached per unit; one
-- that could not be read is tried once per fight and again after it.
local _, ns = ...
local NP = ns.NP

local Extras = {}
NP.Extras = Extras

local QUEST_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
NP.QUEST_ICON = QUEST_ICON

-- ---------------------------------------------------------------------------
-- Quest mobs
--
-- The client puts the quest on the unit's tooltip; there is no "is this a quest
-- mob" API. Scanning a tooltip is not cheap, so the answer is remembered per
-- unit and thrown away when the quest log changes.
--
-- Not in a fight: the log changes with every kill that counts, and a fresh
-- scan has to wait for the fight's end -- thrown away there, the marker went
-- missing for the rest of the fight. So the scan remembers WHICH quests mark
-- the unit, and a change in a fight only asks the log whether those are done:
-- a finished quest takes its marker off at once, the rest stand until the
-- fight's end rescans everything.
--
-- NOT CACHED AS "NO" TOO EARLY. A plate comes up before the client has the
-- unit's quest lines: the first tooltip is often bare, and a "no" cached from
-- it held until the next quest log change. The client says when a tooltip's
-- data fills in (TOOLTIP_DATA_UPDATE, by its dataInstanceID), and that unit is
-- scanned again right then. A scan that met an unreadable line answers
-- "unknown" rather than "no", so it is not kept and the next look tries again;
-- that is also what lets a plate that comes up mid-fight try at once instead
-- of waiting for the fight's end.
-- ---------------------------------------------------------------------------
local questCache = {}   -- unit -> false, or { [questID] = true }; 0 = a quest we could not name
local questStale = false
local questData  = {}   -- unit -> the dataInstanceID its last scan read
local triedBlind = {}   -- unit -> true: an unreadable scan in this fight, no retry until data changes
local questText  = {}   -- unit -> "3/8" or "40%": the first open objective's progress, plain text

-- The progress of an objective line, or nil. The line carries it as numbers
-- (numFulfilled, numRequired); an area objective shown as a percentage has
-- 0/1 there and its real progress only in the text, so a percent in the text
-- wins.
local function progressOf(line)
    local text = line.leftText
    if ns.CanRead(text) and type(text) == "string" then
        local pct = text:match("(%d+)%s*%%")
        if pct then return pct .. "%" end
    end
    local have, need = line.numFulfilled, line.numRequired
    if ns.CanRead(have) and ns.CanRead(need) and type(have) == "number" and type(need) == "number" then
        return have .. "/" .. need
    end
    if ns.CanRead(text) and type(text) == "string" then
        local done, total = text:match("(%d+)%s*/%s*(%d+)")
        if done then return done .. "/" .. total end
    end
    return nil
end

local function onQuest(id)
    local on = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id)
    return ns.CanRead(on) and on == true
end

local function questDone(id)
    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
    return ns.CanRead(done) and done == true
end

-- A table of quest ids, false for "no quest", nil for "could not tell".
local function scanQuest(unit)
    local info = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit, true)
    if type(info) ~= "table" then return nil end
    local dataID = info.dataInstanceID
    questData[unit] = (ns.CanRead(dataID) and type(dataID) == "number") and dataID or nil
    local lines = info.lines
    if type(lines) ~= "table" then return nil end
    local types = Enum.TooltipDataLineType
    -- Only an OPEN objective marks the unit. A title alone does not: the
    -- client keeps a quest's title on the mob after its last kill or drop,
    -- and the marker stayed until the quest was handed in.
    local ids, current, skip, blind, progress = nil, nil, false, false, nil
    for _, line in ipairs(lines) do
        local kind = line.type
        if not ns.CanRead(kind) then
            blind = true
        else
            if kind == types.QuestTitle then
                -- our own quest, still open, not someone else's tooltip line;
                -- the objectives below a title belong to it
                local id = ns.Num(line.id, nil)
                current = id and onQuest(id) and not questDone(id) and id or nil
                -- a title we can read but that is not an open quest of ours:
                -- its objectives count for nothing
                skip = id ~= nil and current == nil
            elseif kind == types.QuestObjective and not skip then
                local done = line.completed
                if ns.CanRead(done) and done == false then
                    ids = ids or {}
                    ids[current or 0] = true
                    progress = progress or progressOf(line)
                end
            end
        end
    end
    if ids then questText[unit] = progress; return ids end
    if blind then return nil end
    questText[unit] = nil
    return false
end

-- The progress to show in place of the marker, when the unit is a quest mob
-- and its objective line carried one.
function Extras.QuestProgress(unit)
    return Extras.IsQuestMob(unit) and questText[unit] or nil
end

function Extras.IsQuestMob(unit)
    if not NP.db().questMobEnabled then return false end
    local cached = questCache[unit]
    if cached == nil then
        -- in a fight one try per unit; its data changing allows the next
        if triedBlind[unit] then return false end
        local ok, res = pcall(scanQuest, unit)
        if not ok then res = false end
        if res == nil then
            -- In a fight: once, then wait for the unit's data or the fight's
            -- end. Out of one: a "no" like any other, which the unit's data
            -- filling in still asks again -- not a scan on every redraw.
            if InCombatLockdown() then triedBlind[unit] = true; return false end
            res = false
        end
        cached = res
        questCache[unit] = cached
    end
    return cached ~= false
end

-- The client filled in a tooltip's data: the unit it belongs to is asked
-- again. nil means every tooltip changed. Only a "no" is asked again, and a
-- marked unit whose progress is still missing: a unit already marked loses its marker through
-- the quest log. And at most twice a second per unit, in case the scan itself
-- is what makes the client send the event.
local rescanAt = {}

function Extras.OnTooltipData(dataID)
    if not NP.db().questMobEnabled then return end
    local now = GetTime()
    for unit, id in pairs(questData) do
        -- a quest mob read before the client had its counts is asked again
        -- too, while its progress is missing
        local open = questCache[unit] == false or triedBlind[unit]
            or (questCache[unit] and not questText[unit] and NP.db().questObjectiveText)
        if open and (dataID == nil or id == dataID) and now - (rescanAt[unit] or 0) >= 0.5 then
            rescanAt[unit] = now
            questCache[unit], triedBlind[unit] = nil, nil
            local plate = NP.plates[unit]
            if plate then
                plate:UpdateClassification()
                NP.Colors.Apply(plate)       -- the quest mob colour asks the same question
            end
        end
    end
end

-- In a fight: drop the quests the log now calls finished (or no longer has).
-- A unit still marked is read again, so its progress counts up with every
-- kill; a read that comes back unreadable keeps what the unit had.
local function pruneFinished()
    for unit, ids in pairs(questCache) do
        if ids then
            for id in pairs(ids) do
                if id ~= 0 and (questDone(id) or not onQuest(id)) then ids[id] = nil end
            end
            if next(ids) == nil then
                questCache[unit], questText[unit] = false, nil
            else
                local ok, res = pcall(scanQuest, unit)
                if ok and type(res) ~= "nil" then questCache[unit] = res end
            end
        end
    end
end

function Extras.ForgetQuest(unit)
    if unit then
        questCache[unit], questData[unit], triedBlind[unit], rescanAt[unit] = nil, nil, nil, nil
        questText[unit] = nil
        return
    end
    if InCombatLockdown() then
        questStale = true
        pruneFinished()
        return
    end
    questStale = false
    wipe(questCache)
    wipe(triedBlind)
    wipe(questText)
end

-- The fight is over: what the log changed in it, and the plates that came up
-- in it unscanned, get their answer now.
function Extras.QuestAfterCombat()
    -- the units the fight could not read get their scan now, stale log or not
    wipe(triedBlind)
    if questStale then Extras.ForgetQuest() end
end

-- ---------------------------------------------------------------------------
-- Execute glow
--
-- The curve is the whole trick: two points, one just below the threshold and
-- one just above, so the client returns a lit colour for a mob in range and
-- BLACK for everything else. Only the colour changes, never the alpha: what
-- the curve does with alpha between its points is not to be relied on, and
-- black adds nothing under the edges' ADD blend, so it is invisible. We hand
-- the result straight to SetVertexColor without ever looking at it.
-- ---------------------------------------------------------------------------
local curve, curveKey

-- Always red: the glow says one thing, and a second colour setting for it
-- only made the row harder to read.
local EXECUTE_RED = { r = 1, g = 0, b = 0 }

local function executeCurve()
    local db = NP.db()
    local c = EXECUTE_RED
    local key = db.executeThreshold
    if curve and curveKey == key then return curve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, new = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not new then return nil end
    -- UnitHealthPercent hands the curve a FRACTION, so the threshold is /100
    local t = db.executeThreshold / 100
    new:AddPoint(0, CreateColor(c.r, c.g, c.b, 1))
    new:AddPoint(t, CreateColor(c.r, c.g, c.b, 1))
    new:AddPoint(math.min(t + 0.0001, 1), CreateColor(0, 0, 0, 1))
    new:AddPoint(1, CreateColor(0, 0, 0, 1))
    curve, curveKey = new, key
    return curve
end

function Extras.UpdateExecute(plate)
    local glow = plate.executeGlow
    if not glow then return end
    local db = NP.db()
    if not (db.executeEnabled and plate.unit) or plate.friendly then
        glow:Hide()
        return
    end
    local c = executeCurve()
    if not c then glow:Hide(); return end
    -- GetRGBA has to be inside the pcall: the colour comes out of a secret
    -- evaluation, and a throw here would fire once per plate per frame.
    local unit = plate.unit
    local ok, r, g, b, a = pcall(function()
        return UnitHealthPercent(unit, true, c):GetRGBA()
    end)
    if not ok then glow:Hide(); return end
    for _, tex in pairs(plate.executeEdges) do tex:SetVertexColor(r, g, b, a) end
    glow:Show()
end

-- ---------------------------------------------------------------------------
-- Combo points
--
-- Forever has exactly one secondary resource, and the player's own power is
-- secret even out of combat -- so a pip is a bar with the range i-1 .. i, and
-- the client decides how full it is.
-- ---------------------------------------------------------------------------
local MAX_PIPS = 10

local function comboMax()
    local max = ns.Num(UnitPowerMax("player", Enum.PowerType.ComboPoints), 0)
    if max <= 0 or max > MAX_PIPS then return 0 end
    return max
end

function Extras.UpdateCombo(plate)
    local bar = plate.comboBar
    if not bar then return end
    local db = NP.db()
    if not (db.comboEnabled and plate.isTarget and plate.unit) then
        bar:Hide()
        return
    end
    local max = comboMax()
    if max == 0 then bar:Hide(); return end

    local width = db.healthBarWidth
    local gap = db.comboGap
    local pipW = (width - gap * (max - 1)) / max
    local value = UnitPower("player", Enum.PowerType.ComboPoints)   -- secret
    local c = db.comboColor
    for i = 1, MAX_PIPS do
        local pip = plate.comboPips[i]
        if i <= max then
            pip:ClearAllPoints()
            pip:SetSize(pipW, db.comboHeight)
            pip:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", (i - 1) * (pipW + gap), 0)
            pip:SetStatusBarColor(c.r, c.g, c.b)
            pip:SetMinMaxValues(i - 1, i)
            pip:SetValue(value)
            pip:Show()
        else
            pip:Hide()
        end
    end
    bar:SetSize(width, db.comboHeight)
    bar:Show()
end

-- ---------------------------------------------------------------------------
-- Build and layout
-- ---------------------------------------------------------------------------
local WHITE = "Interface\\Buttons\\WHITE8X8"

function Extras.Build(plate)
    local glow = CreateFrame("Frame", nil, plate)
    glow:SetFrameLevel(math.max(plate.health:GetFrameLevel() - 1, 0))
    glow:Hide()
    plate.executeGlow = glow
    plate.executeEdges = ns.MakeEdges(glow, "BACKGROUND")
    for _, tex in pairs(plate.executeEdges) do tex:SetBlendMode("ADD") end
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.6)
    plate.executePulse = pulse
    glow:SetScript("OnShow", function() pulse:Play() end)
    glow:SetScript("OnHide", function() pulse:Stop() end)

    local bar = CreateFrame("Frame", nil, plate)
    bar:Hide()
    plate.comboBar = bar
    plate.comboPips = {}
    for i = 1, MAX_PIPS do
        local pip = CreateFrame("StatusBar", nil, bar)
        pip:SetStatusBarTexture(WHITE)
        local bg = pip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(pip)
        bg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
        plate.comboPips[i] = pip
    end
end

function Extras.ApplyAppearance(plate)
    local db = NP.db()
    local size = db.executeGlowSize
    plate.executeGlow:ClearAllPoints()
    plate.executeGlow:SetPoint("TOPLEFT", plate.health, "TOPLEFT", -size, size)
    plate.executeGlow:SetPoint("BOTTOMRIGHT", plate.health, "BOTTOMRIGHT", size, -size)
    ns.LayoutEdges(plate.executeEdges, plate.health, size, 1, 1, 1, 1)

    plate.comboBar:ClearAllPoints()
    plate.comboBar:SetPoint("TOP", plate.cast, "BOTTOM", 0, -db.comboOffset)
end

function Extras.Update(plate)
    Extras.UpdateExecute(plate)
    Extras.UpdateCombo(plate)
end

-- Every plate at once: the player's combo points changed, or the quest log did.
function Extras.UpdateAll(what)
    for _, plate in pairs(NP.plates) do
        if what == "combo" then
            Extras.UpdateCombo(plate)
        else
            Extras.UpdateExecute(plate)
        end
    end
end
