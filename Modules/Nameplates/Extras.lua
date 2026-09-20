-- VuloForeverUI / Modules / Nameplates / Extras
--
-- The three things a plate shows that are neither health, cast nor aura:
-- a marker on a quest mob, a glow when the target is low enough to finish, and
-- the combo points on the plate of whatever you are hitting.
--
-- Two of them look like they need a comparison and do not:
--
--   * the execute glow asks the CLIENT to turn health into a colour. A colour
--     curve is red below the threshold and transparent above it, and
--     UnitHealthPercent evaluates it for us -- so the decision "is this mob low
--     enough" is made in C on a number we never see.
--   * a combo point is one bar per pip, each scaled i-1 .. i and fed the secret
--     power. The third pip fills when the value passes 3. Geometry again.
--
-- The quest scan is the exception: tooltip lines really are read, so every
-- field is checked for readability first and an unreadable one simply ends the
-- scan. It runs out of combat only and is cached per unit.
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
-- ---------------------------------------------------------------------------
local questCache = {}

local function scanQuest(unit)
    local info = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit, true)
    local lines = info and info.lines
    if not lines then return false end
    local types = Enum.TooltipDataLineType
    for _, line in ipairs(lines) do
        local kind = line.type
        if ns.CanRead(kind) then
            if kind == types.QuestTitle then
                local id = ns.Num(line.id, nil)
                -- our own quest, not someone else's tooltip line
                if id and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id) then return true end
            elseif kind == types.QuestObjective then
                local done = line.completed
                if ns.CanRead(done) and done == false then return true end
            end
        end
    end
    return false
end

function Extras.IsQuestMob(unit)
    if not NP.db().questMobEnabled then return false end
    local cached = questCache[unit]
    if cached ~= nil then return cached end
    if InCombatLockdown() then return false end     -- tooltip scans wait
    local ok, res = pcall(scanQuest, unit)
    res = ok and res or false
    questCache[unit] = res
    return res
end

function Extras.ForgetQuest(unit)
    if unit then questCache[unit] = nil else wipe(questCache) end
end

-- ---------------------------------------------------------------------------
-- Execute glow
--
-- The curve is the whole trick: two points, one just below the threshold and
-- one just above, so the client returns a lit colour for a mob in range and a
-- transparent one for everything else. We hand the result straight to
-- SetVertexColor without ever looking at it.
-- ---------------------------------------------------------------------------
local curve, curveKey

local function executeCurve()
    local db = NP.db()
    local c = db.executeColor
    local key = ("%f/%f/%f/%f"):format(db.executeThreshold, c.r, c.g, c.b)
    if curve and curveKey == key then return curve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, new = pcall(C_CurveUtil.CreateColorCurve)
    if not ok or not new then return nil end
    -- UnitHealthPercent hands the curve a FRACTION, so the threshold is /100
    local t = db.executeThreshold / 100
    new:AddPoint(0, CreateColor(c.r, c.g, c.b, 1))
    new:AddPoint(t, CreateColor(c.r, c.g, c.b, 1))
    new:AddPoint(math.min(t + 0.001, 1), CreateColor(c.r, c.g, c.b, 0))
    new:AddPoint(1, CreateColor(c.r, c.g, c.b, 0))
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
    local ok, col = pcall(UnitHealthPercent, plate.unit, true, c)
    if not ok or not ns.Exists(col) then glow:Hide(); return end
    local r, g, b, a = col:GetRGBA()
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
