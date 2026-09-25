-- VuloForeverUI / Modules / DamageMeter / Threat
--
-- The threat meter: the threat on your target for everyone in the group, one
-- bar each, sorted, with an optional "pull aggro" bar and a warning sound.
--
-- This client hands the threat API over readable. A value that does come back
-- secret skips that unit rather than erroring -- and a unit comparison that
-- comes back secret counts as "not you", never as a thrown test.
--
-- The mob whose table is shown is your target when you can attack it, or else
-- what your friendly target is fighting, so a healer on the tank sees the tank's
-- mob. That second case has no event of its own (UNIT_THREAT_LIST_UPDATE names
-- real tokens, never targettarget), so it is re-read on a short interval, and
-- only in combat.
local _, ns = ...
local L  = ns.L
local DM = ns.DM

local Threat = {}
DM.Threat = Threat

local UPDATE_DELAY, FOLLOW_INTERVAL, PREVIEW_SECONDS, TEXT_PAD = 0.2, 0.5, 10, 4
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PET_COLOR = { r = 0.45, g = 0.6, b = 0.45 }
local FALLBACK_COLOR = { r = 0.6, g = 0.6, b = 0.6 }

local frame, events, pendingUpdate, previewUntil, followTicker, mover
local rows, entries, list = {}, {}, {}
local mobUnit, warned
local editing = false

local function tdb() return DM.db().threat end

-- Readable first, THEN compared: a secret must never meet an operator.
local function readable(v)
    if not ns.CanRead(v) then return false end
    return v ~= nil
end

-- Forever returns threat in display units already, not the x100 scale of the
-- old API, so it is shown as is.
local function shortThreat(v)
    if v >= 1000000 then return string.format("%.1fm", v / 1000000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v + 0.5))
end

local function threatMob()
    if UnitExists("target") and UnitCanAttack("player", "target") then return "target" end
    if UnitExists("targettarget") and UnitCanAttack("player", "targettarget") then
        return "targettarget"
    end
end

-- A tank is not warned about holding aggro: the tank role, Bear or Dire Bear
-- Form, or Defensive Stance.
local function playerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then return true end
    local form = GetShapeshiftFormID()
    return form == 5 or form == 8 or form == 18
end

local function visibleNow()
    local v = tdb().visibility or "always"
    if v == "combat" then return InCombatLockdown() or UnitAffectingCombat("player") end
    if v == "noncombat" then return not (InCombatLockdown() or UnitAffectingCombat("player")) end
    return true
end

-- ---------------------------------------------------------------- look --

local function outlineFlag()
    local o = tdb().outline or "INHERIT"
    if o == "INHERIT" then return nil end
    if o == "NONE" then return "" end
    return o
end

local function headerHeight()
    local t = tdb()
    return t.showHeader and t.barHeight or 0
end

local function styleRow(row, texture)
    local t = tdb()
    row:SetStatusBarTexture(texture)
    DM.Font(row.name, t.textSize, outlineFlag())
    DM.Font(row.value, t.textSize, outlineFlag())
end

local function barTexture()
    return ns.MediaStatusbar(tdb().texture, WHITE)
end

local function createRow(i)
    local row = CreateFrame("StatusBar", nil, frame)
    row:SetMinMaxValues(0, 1)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetPoint("LEFT", row, "LEFT", TEXT_PAD, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.value = row:CreateFontString(nil, "OVERLAY")
    row.value:SetPoint("RIGHT", row, "RIGHT", -TEXT_PAD, 0)
    row.value:SetJustifyH("RIGHT")
    row.name:SetPoint("RIGHT", row.value, "LEFT", -TEXT_PAD, 0)
    rows[i] = row
    styleRow(row, barTexture())
    return row
end

-- The inputs of the last layout; a redraw that matches them moves nothing.
local laid = {}

local function layoutRows(count)
    local t = tdb()
    local bh, gap, w, up, header = t.barHeight, t.spacing, t.width, t.growUp, t.showHeader
    if laid.count == count and laid.bh == bh and laid.gap == gap and laid.w == w
        and laid.up == up and laid.header == header then return end
    laid.count, laid.bh, laid.gap, laid.w, laid.up, laid.header = count, bh, gap, w, up, header
    local top = headerHeight()
    frame:SetSize(w, math.max(top + count * (bh + gap) - (count > 0 and gap or 0), top, 1))
    for i = 1, count do
        local row = rows[i] or createRow(i)
        row:ClearAllPoints()
        local off = top + (i - 1) * (bh + gap)
        if up then
            row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, off)
        else
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -off)
        end
        row:SetSize(w, bh)
        row:Show()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
    frame.header:ClearAllPoints()
    frame.header:SetPoint(up and "BOTTOMLEFT" or "TOPLEFT")
    frame.header:SetSize(w, math.max(top, 1))
    frame.header:SetShown(top > 0)
end

local function applyStyle()
    if not frame then return end
    local t = tdb()
    laid.count = nil
    frame.bg:SetColorTexture(0, 0, 0, t.bgAlpha)
    frame.header.bg:SetColorTexture(0, 0, 0, math.min(1, t.bgAlpha + 0.2))
    DM.Font(frame.header.text, t.textSize, outlineFlag())
    local texture = barTexture()
    for i = 1, #rows do styleRow(rows[i], texture) end
    local c = t.borderColor
    ns.LayoutEdges(frame.edges, frame, t.borderSize or 0, c.r, c.g, c.b, 1, 0)
end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VuloForeverUIThreatMeter", UIParent)
    frame:SetSize(tdb().width, 1)
    frame:SetFrameStrata("MEDIUM")
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.header = CreateFrame("Frame", nil, frame)
    frame.header.bg = frame.header:CreateTexture(nil, "BACKGROUND")
    frame.header.bg:SetAllPoints()
    frame.header.text = frame.header:CreateFontString(nil, "OVERLAY")
    frame.header.text:SetPoint("LEFT", TEXT_PAD, 0)
    frame.header.text:SetPoint("RIGHT", -TEXT_PAD, 0)
    frame.header.text:SetJustifyH("LEFT")
    frame.header.text:SetWordWrap(false)
    -- The border on a frame above the rows: the rows are child frames, and a
    -- child draws over every layer of its parent.
    local top = CreateFrame("Frame", nil, frame)
    top:SetAllPoints(frame)
    top:SetFrameLevel(frame:GetFrameLevel() + 5)
    frame.edges = ns.MakeEdges(top, "OVERLAY")
    frame:Hide()

    -- The box in our edit mode. Its db is the meter's own position, a centre
    -- offset from the screen's centre; the example rows stand in while it is
    -- open, so there is something the size of the meter to drag.
    local t = tdb()
    if type(t.mover) ~= "table" then t.mover = { x = 400, y = -100 } end
    mover = ns:CreateMover(frame, {
        key    = "dm_threat",
        label  = L["Threat Meter"],
        db     = t.mover,
        module = "damagemeter",
        width  = t.width, height = 60,
        editPreview = function(on)
            editing = on and true or false
            Threat.Update()
        end,
    })
    ns:ApplyMover(mover)
    applyStyle()
    return frame
end

-- ---------------------------------------------------------------- data --

local function colorOf(unit)
    local isPlayer = unit and UnitIsPlayer(unit)
    if not (readable(isPlayer) and isPlayer) then return PET_COLOR end
    local _, classFile = UnitClass(unit)
    if not ns.CanRead(classFile) then return FALLBACK_COLOR end
    return DM.ClassColorTable(classFile) or FALLBACK_COLOR
end

-- Every group token the meter reads, built once.
local RAID_UNITS, RAID_PETS, PARTY_UNITS, PARTY_PETS = {}, {}, {}, {}
local MEMBER_UNITS, PET_UNITS = { player = true }, { pet = true }
for i = 1, 40 do
    local u, p = "raid" .. i, "raidpet" .. i
    RAID_UNITS[i], RAID_PETS[i], MEMBER_UNITS[u], PET_UNITS[p] = u, p, true, true
end
for i = 1, 4 do
    local u, p = "party" .. i, "partypet" .. i
    PARTY_UNITS[i], PARTY_PETS[i], MEMBER_UNITS[u], PET_UNITS[p] = u, p, true, true
end

local count = 0

local function entry()
    count = count + 1
    local e = entries[count]
    if not e then e = {}; entries[count] = e end
    list[#list + 1] = e
    return e
end

local function add(unit, mob)
    if not UnitExists(unit) then return end
    local tanking, _, scaled, _, raw = UnitDetailedThreatSituation(unit, mob)
    if not (readable(raw) and readable(scaled) and readable(tanking)) or raw <= 0 then return end
    local me = UnitIsUnit(unit, "player")
    local e = entry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = unit, UnitName(unit), raw, scaled, tanking
    e.isPlayer, e.pull = readable(me) and me == true or false, nil
end

local function collect(mob)
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
    local pets = not tdb().ignorePets
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            add(RAID_UNITS[i], mob)
            if pets then add(RAID_PETS[i], mob) end
        end
    else
        add("player", mob)
        if pets then add("pet", mob) end
        for i = 1, GetNumSubgroupMembers() do
            add(PARTY_UNITS[i], mob)
            if pets then add(PARTY_PETS[i], mob) end
        end
    end
end

local function byThreat(a, b) return a.raw > b.raw end

-- Where you pull aggro: the scaled percent is threat against your own pull
-- line (100 = you take it), so the line is your threat scaled up to 100.
local function addPullEntry(me)
    if not (me and not me.tanking and me.scaled > 0) then return end
    local e = entry()
    e.unit, e.name, e.raw, e.scaled, e.tanking = nil, L["Pull Aggro"], me.raw * 100 / me.scaled, 100, false
    e.isPlayer, e.pull = false, true
end

-- ---------------------------------------------------------------- draw --

local function rowColor(e)
    local t = tdb()
    if e.pull then return t.pullColor.r, t.pullColor.g, t.pullColor.b end
    if e.isPlayer and t.playerColorOn then return t.playerColor.r, t.playerColor.g, t.playerColor.b end
    if e.tanking and t.tankColorOn then return t.tankColor.r, t.tankColor.g, t.tankColor.b end
    local c = colorOf(e.unit)
    return c.r, c.g, c.b
end

local function valueText(e)
    local t = tdb()
    local v, p = t.showValue, t.showPercent and not e.pull
    if v and p then return string.format("%s  %d%%", shortThreat(e.raw), e.scaled) end
    if v then return shortThreat(e.raw) end
    if p then return string.format("%d%%", e.scaled) end
    return ""
end

local function render(shown, top, title)
    layoutRows(shown)
    -- Names go straight to SetText: a name can come back secret, and a secret
    -- cannot be tested for nil.
    frame.header.text:SetText(title)
    local alpha = tdb().barOpacity / 100
    for i = 1, shown do
        local e, row = list[i], rows[i]
        local r, g, b = rowColor(e)
        row:SetStatusBarColor(r, g, b, alpha)
        row.bg:SetColorTexture(r * 0.25, g * 0.25, b * 0.25, alpha * 0.6)
        row:SetValue(top > 0 and e.raw / top or 0)
        row.name:SetText(e.name)
        row.value:SetText(valueText(e))
    end
end

local function playWarning()
    local key = tdb().warnSoundKey
    local path = ns.LSM and key and ns.LSM:Fetch("sound", key, true)
    if type(path) == "number" then
        PlaySound(path, "Master")
    elseif path then
        PlaySoundFile(path, "Master")
    end
end

local function checkWarning(me)
    local t = tdb()
    if not t.warnSound then return end
    local over = me and not me.tanking and me.scaled >= t.warnAt
        and not (t.warnSkipTank and playerIsTank())
    if over and not warned then playWarning() end
    warned = over
end

local function samplePreview()
    count = 0
    for i = #list, 1, -1 do list[i] = nil end
    local samples = { { 10000, 100, true }, { 8200, 82 }, { 6100, 61 }, { 3400, 34 } }
    for i, s in ipairs(samples) do
        local e = entry()
        e.unit = "player"
        e.name = i == 1 and L["Tank"] or UnitName("player")
        e.raw, e.scaled, e.tanking = s[1], s[2], s[3] == true
        e.isPlayer, e.pull = i == 2, false
    end
    addPullEntry(list[2])
    table.sort(list, byThreat)
    render(math.min(#list, tdb().maxBars), list[1].raw, L["Threat Meter"])
end

local function setFollow(on)
    if on and not followTicker then
        followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, function() Threat.Update() end)
    elseif not on and followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

function Threat.Update()
    pendingUpdate = false
    mobUnit = nil
    if not frame then return end
    local t = tdb()
    if not (t.enabled and DM.mod.active) then
        setFollow(false)
        frame:Hide()
        return
    end
    -- The example: while our edit mode or the settings page asks for it.
    if editing or (previewUntil and GetTime() < previewUntil) then
        setFollow(false)
        samplePreview()
        frame:Show()
        return
    end
    previewUntil = nil
    local mob = visibleNow() and threatMob()
    mobUnit = mob or nil
    setFollow(mob == "targettarget" and InCombatLockdown())
    if mob then collect(mob) end
    if not mob or #list == 0 then
        warned = false
        frame:Hide()
        return
    end
    local me
    for i = 1, #list do
        if list[i].isPlayer then me = list[i] break end
    end
    checkWarning(me)
    if t.pullBar then addPullEntry(me) end
    table.sort(list, byThreat)
    render(math.min(#list, t.maxBars), list[1].raw, UnitName(mob))
    frame:Show()
end

-- Threat updates arrive per unit, so a raid pull is a burst; one redraw per
-- short window covers the whole burst.
local function requestUpdate()
    if pendingUpdate then return end
    pendingUpdate = true
    C_Timer.After(UPDATE_DELAY, Threat.Update)
end

-- A threat-list change counts only for the mob shown (a secret comparison
-- counts as a match; with none shown, only your target's), a threat-situation
-- change only for a unit the meter lists. Every other event redraws.
local function onEvent(_, event, unit)
    if pendingUpdate then return end
    if event == "UNIT_THREAT_LIST_UPDATE" then
        if not mobUnit then
            if unit ~= "target" then return end
        elseif unit ~= mobUnit then
            local same = UnitIsUnit(unit, mobUnit)
            if readable(same) and not same then return end
        end
    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if not (MEMBER_UNITS[unit] or (PET_UNITS[unit] and not tdb().ignorePets)) then return end
    end
    requestUpdate()
end

-- ---------------------------------------------------------------- apply --

function Threat.Apply()
    local t = tdb()
    if t.enabled and DM.mod.active then
        build()
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", onEvent)
        end
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterUnitEvent("UNIT_TARGET", "target")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        if mover then
            mover.opts.db = t.mover
            mover.opts.width = t.width
            if ns.RefreshMoverGeometry then ns:RefreshMoverGeometry(mover) end
            ns:ApplyMover(mover)
        end
        applyStyle()
        requestUpdate()
    else
        Threat.Disable()
    end
end

function Threat.Disable()
    if events then events:UnregisterAllEvents() end
    setFollow(false)
    warned = false
    if frame then frame:Hide() end
end

function Threat.ApplyStyle()
    applyStyle()
    if frame then Threat.Update() end
end

-- The settings page's example: ten seconds of sample rows.
function Threat.Preview()
    if not (tdb().enabled and DM.mod.active) then return end
    build()
    previewUntil = GetTime() + PREVIEW_SECONDS
    Threat.Update()
    C_Timer.After(PREVIEW_SECONDS, Threat.Update)
end

function Threat.PlayWarning() playWarning() end
