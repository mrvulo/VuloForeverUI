-- VuloForeverUI / Modules / ResourceBars / Experience
--
-- The experience bar: the same bar as the others in this module, plus what an
-- experience bar has and they do not -- the rested stretch after the fill, the
-- experience of finished quests before it, a level on the left, a percent on
-- the right, and an info line underneath with the rate, the time to level and
-- the time played.
--
-- WHAT MAY BE READ HERE
--
-- Experience is not combat data, and the client's own bar does its arithmetic
-- on it openly. Every number is still gated through ns.Num: should one ever
-- arrive secret, the fill still gets it (SetValue takes secrets as they are),
-- and everything that needs arithmetic -- overlays, texts, the rate -- simply
-- stays empty rather than guessing.
local _, ns = ...
local L  = ns.L
local RB = ns.RB
local UI = ns.UI

local XP = {}
RB.XP = XP

local KEY = "xp"

-- The client's own rest states: 1 rested, 2 normal.
local REST_RESTED = 1

-- ---------------------------------------------------------------- session --

-- Per character, so a /reload keeps the rate it has gathered. A fresh login
-- starts a new session.
local function session()
    local char = VuloForeverUICharDB
    if type(char) ~= "table" then return nil end
    if type(char.xpSession) ~= "table" then char.xpSession = {} end
    return char.xpSession
end

local function resetSession(cur, max)
    local s = session()
    if not s then return end
    s.start  = time()
    s.gained = 0
    s.last   = cur
    s.lastMax = max
end

-- What PLAYER_XP_UPDATE brought, added to the session. A level-up wraps the
-- value around, so the rest of the old level counts as well.
-- The pace is measured over the last quarter of an hour, not the whole
-- session: a session with a long break in it would otherwise promise a level
-- far later than the player is actually getting there. Kept in memory only;
-- after a /reload the session average stands in until new gains arrive.
local WINDOW = 15 * 60
local recent = {}        -- { t = GetTime(), xp = gained }, oldest first
local windowStart = GetTime()

local function prune(now)
    while recent[1] and now - recent[1].t > WINDOW do table.remove(recent, 1) end
end

local function trackGain(cur, max)
    local s = session()
    if not (s and cur and max) then return end
    if not (s.start and s.last and s.lastMax) then resetSession(cur, max); return end
    local gained = cur - s.last
    if gained < 0 then gained = (s.lastMax - s.last) + cur end
    if gained > 0 then
        s.gained = (s.gained or 0) + gained
        recent[#recent + 1] = { t = GetTime(), xp = gained }
    end
    s.last, s.lastMax = cur, max
end

-- Experience per hour over the window, or nil with nothing gained in it.
local function recentRate()
    local now = GetTime()
    prune(now)
    if not recent[1] then return nil end
    local sum = 0
    for _, e in ipairs(recent) do sum = sum + e.xp end
    -- the span the window really covers: never more than the window, never
    -- less than a minute (one kill right after a reload is not an hourly rate)
    local span = math.max(60, math.min(WINDOW, now - windowStart))
    return math.ceil(sum / span * 3600)
end

-- ---------------------------------------------------------------- played --

-- The client answers RequestTimePlayed with TIME_PLAYED_MSG, and every chat
-- frame registered for it prints two lines. For our own request those frames
-- are taken off the event until the answer is in, so the player never sees a
-- message they did not ask for.
local played = { level = nil, total = nil, stamp = nil }
local muted = {}
local requestPending = false

local function unmuteChat()
    for frame in pairs(muted) do
        frame:RegisterEvent("TIME_PLAYED_MSG")
        muted[frame] = nil
    end
    requestPending = false
end

local function requestPlayed()
    if requestPending or type(RequestTimePlayed) ~= "function" then return end
    requestPending = true
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            muted[frame] = true
        end
    end
    RequestTimePlayed()
    -- No answer in time: give the chat its event back regardless.
    C_Timer.After(10, function() if requestPending then unmuteChat() end end)
end

local function onPlayed(total, level)
    total, level = ns.Num(total), ns.Num(level)
    if total and level then
        played.total, played.level, played.stamp = total, level, GetTime()
    end
    -- One frame later: the frames that were muted must not receive this very
    -- event on its way through.
    if requestPending then ns.NextFrame(unmuteChat) end
end

-- ---------------------------------------------------------------- quests --

local quest = { complete = 0, incomplete = 0 }

local function scanQuests()
    local complete, incomplete = 0, 0
    local QL = C_QuestLog
    if QL and QL.GetNumQuestLogEntries and type(GetQuestLogRewardXP) == "function" then
        for i = 1, QL.GetNumQuestLogEntries() or 0 do
            local info = QL.GetInfo(i)
            local id = info and not info.isHeader and info.questID
            if id and id > 0 then
                local reward = ns.Num(GetQuestLogRewardXP(id), 0)
                if reward > 0 then
                    if QL.IsComplete(id) or (QL.ReadyForTurnIn and QL.ReadyForTurnIn(id)) then
                        complete = complete + reward
                    else
                        incomplete = incomplete + reward
                    end
                end
            end
        end
    end
    quest.complete, quest.incomplete = complete, incomplete
end

-- ---------------------------------------------------------------- format --

local function short(n)
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 10000 then return string.format("%.1fK", n / 1000) end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function duration(sec)
    sec = math.floor(sec or 0)
    if sec < 60 then return "< 1m" end
    local d = math.floor(sec / 86400)
    local h = math.floor(sec % 86400 / 3600)
    local m = math.floor(sec % 3600 / 60)
    if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

local function pct(n) return string.format("%.1f%%", n) end

-- ---------------------------------------------------------------- data --

local function atMaxLevel()
    local util = GameRulesUtil
    if util and util.IsPlayerAtEffectiveMaxLevel then
        return util.IsPlayerAtEffectiveMaxLevel() and true or false
    end
    return false
end

-- Everything the bar draws, as one table: the real one from the client, the
-- preview's from Preview.lua. nil fields mean "not readable".
function XP.Read()
    local d = {
        level   = ns.Num(UnitLevel("player")),
        rawCur  = UnitXP("player"),
        rawMax  = UnitXPMax("player"),
        rested  = ns.Num(GetXPExhaustion(), 0),
        isRested = ns.Num(GetRestState()) == REST_RESTED,
        maxLevel = atMaxLevel(),
        disabled = type(IsXPUserDisabled) == "function" and IsXPUserDisabled() and true or false,
        questComplete   = quest.complete,
        questIncomplete = quest.incomplete,
    }
    d.cur, d.max = ns.Num(d.rawCur), ns.Num(d.rawMax)

    local s = session()
    -- Switched on mid-session: the session starts now, not at the first gain.
    if s and not s.start and d.cur and d.max then resetSession(d.cur, d.max) end
    if s and s.start and d.cur and d.max then
        local secs = time() - s.start
        local gained = s.gained or 0
        d.sessionTime = secs
        local rate = recentRate()
        if not rate and secs > 0 and gained > 0 then
            rate = math.ceil(gained / (secs / 3600))
        end
        if rate and rate > 0 then
            d.perHour = rate
            d.toLevel = math.ceil((d.max - d.cur) / rate * 3600)
        end
    end
    if played.stamp then
        local since = GetTime() - played.stamp
        d.levelTime = played.level + since
        d.totalTime = played.total + since
    end
    return d
end

-- ---------------------------------------------------------------- regions --

-- The client's own bar texture, for the stretches laid over the client's bar.
local CLIENT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local function isClientStyle(bar)
    return (bar.xpStyle or "client") == "client"
end
XP.IsClientStyle = isClientStyle

-- The parts only this bar has. On our own bar (built by RB.BuildRegions) they
-- join the fill and the text holder that are already there; on the frame laid
-- over the client's bar, which has neither, the frame itself carries them.
-- Lazy, so the preview's pooled frames get them the first time they show it.
local function ensureRegions(frame)
    if frame.xpQuest then return end
    local under = frame.fill or frame
    -- Under the fill's texture on our own bar: they start where the fill ends,
    -- so the order only matters where a rounding pixel overlaps.
    frame.xpQuest      = under:CreateTexture(nil, "BORDER", nil, 1)
    frame.xpIncomplete = under:CreateTexture(nil, "BORDER", nil, 2)
    frame.xpRested     = under:CreateTexture(nil, "BORDER", nil, 3)

    local holder = frame.textHolder
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        frame.textHolder = holder
    end
    if not frame.left then
        frame.left = holder:CreateFontString(nil, "OVERLAY")
        frame.left:SetPoint("LEFT", frame, "LEFT", 4, 0)
        frame.left:SetJustifyH("LEFT")
        frame.right = holder:CreateFontString(nil, "OVERLAY")
        frame.right:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        frame.right:SetJustifyH("RIGHT")
    end

    local center = holder:CreateFontString(nil, "OVERLAY")
    center:SetPoint("CENTER", frame, "CENTER", 0, 0)
    center:SetJustifyH("CENTER")
    frame.center = center

    local info = holder:CreateFontString(nil, "OVERLAY")
    info:SetJustifyH("CENTER")
    frame.xpInfo = info
end
XP.EnsureRegions = ensureRegions

-- A stretch of the bar that starts `from` and is `width` long, both in
-- experience; clipped to the end of the bar.
local function stretch(tex, frame, from, width, max, color, alpha, texture)
    if not (max and max > 0 and width and width > 0 and from < max) then tex:Hide(); return end
    local barW = frame:GetWidth() or 0
    local x1 = barW * from / max
    local x2 = barW * math.min(max, from + width) / max
    if x2 - x1 < 0.5 then tex:Hide(); return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, 0)
    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x1, 0)
    tex:SetWidth(x2 - x1)
    tex:SetTexture(texture or RB.WHITE)
    tex:SetVertexColor(color.r, color.g, color.b, alpha)
    tex:Show()
end

local function leftText(bar, d)
    if (bar.leftText or "level") == "level" and d.level then
        return string.format(L["Level %d"], d.level)
    end
    return ""
end

local function centerText(bar, d)
    local mode = bar.centerText or "valuemax"
    if mode == "none" then return "" end
    if d.maxLevel then return L["Max level"] end
    if not (d.cur and d.max) then return "" end
    local rest = d.max - d.cur
    if mode == "value" then return short(d.cur) end
    if mode == "remaining" then return short(rest) end
    if mode == "valuemaxrest" then
        return string.format("%s / %s (%s)", short(d.cur), short(d.max), short(rest))
    end
    return short(d.cur) .. " / " .. short(d.max)
end

local function rightText(bar, d)
    local mode = bar.rightText or "percentquest"
    if mode == "none" or d.maxLevel or not (d.cur and d.max and d.max > 0) then return "" end
    local p = d.cur / d.max * 100
    if mode == "percentquest" and (d.questComplete or 0) > 0 then
        return string.format("%s (%s)", pct(p), pct(math.min(100, (d.cur + d.questComplete) / d.max * 100)))
    end
    return pct(p)
end

-- The info line's pieces, by the side of the bar they belong to when the line
-- is folded into the bar itself: the pace next to the level on the left, the
-- shares and the times next to the percent on the right.
local function infoParts(bar, d)
    local left, right = {}, {}
    if not d.maxLevel and d.max and d.max > 0 then
        if bar.showRate then
            left[#left + 1] = string.format(L["Level in %s  ·  %s XP/h"],
                d.toLevel and duration(d.toLevel) or "--", d.perHour and short(d.perHour) or "0")
        end
        if bar.showQuestRested then
            right[#right + 1] = string.format(L["Quests: |cffffab07%s|r  ·  Rested: |cff4f90ff%s|r"],
                pct((d.questComplete or 0) / d.max * 100), pct((d.rested or 0) / d.max * 100))
        end
    end
    if bar.showLevelTime and d.levelTime then
        if d.maxLevel then
            right[#right + 1] = string.format(L["Played: %s"], duration(d.totalTime))
        else
            right[#right + 1] = string.format(L["This level: %s"], duration(d.levelTime))
        end
    end
    if bar.showSessionTime and d.sessionTime then
        right[#right + 1] = string.format(L["This session: %s"], duration(d.sessionTime))
    end
    return left, right
end

local SEP = "   ·   "

local function join(...)
    local out = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "table" then
            for _, p in ipairs(v) do out[#out + 1] = p end
        elseif v and v ~= "" then
            out[#out + 1] = v
        end
    end
    return table.concat(out, SEP)
end

-- Where the three texts sit: their home on the bar (4 px in from each end,
-- the middle in the middle) plus the player's sideways shift.
local function placeTexts(frame, bar)
    local lx, cx, rx = bar.leftX or 0, bar.centerX or 0, bar.rightX or 0
    frame.left:ClearAllPoints()
    frame.left:SetPoint("LEFT", frame, "LEFT", 4 + lx, 0)
    frame.center:ClearAllPoints()
    frame.center:SetPoint("CENTER", frame, "CENTER", cx, 0)
    frame.right:ClearAllPoints()
    frame.right:SetPoint("RIGHT", frame, "RIGHT", -4 + rx, 0)
end

-- The two sides may only use what the middle text leaves free on their side;
-- whatever does not fit is cut with an ellipsis rather than written over the
-- middle. With the middle empty, each side may run to the bar's centre line
-- (shifted with the middle text), so the two still never meet.
local GAP = 10

local function fitSides(frame, bar)
    local total = frame:GetWidth() or 0
    local lx, cx, rx = bar.leftX or 0, bar.centerX or 0, bar.rightX or 0
    local mid = (frame.center:GetText() or "") ~= "" and frame.center:GetStringWidth() or 0
    local midLeft  = total / 2 + cx - mid / 2
    local midRight = total / 2 + cx + mid / 2
    local rooms = {
        [frame.left]  = midLeft - (4 + lx) - GAP,
        [frame.right] = (total - 4 + rx) - midRight - GAP,
    }
    for fs, room in pairs(rooms) do
        fs:SetWordWrap(false)
        fs:SetWidth(0)
        local w = fs:GetStringWidth() or 0
        fs:SetWidth(math.max(20, math.min(w + 2, room)))
    end
end

-- Overlays, texts and the info line, on our own bar or on the frame over the
-- client's. `texture` is what the stretches are drawn with.
function XP.PaintExtras(frame, bar, d, texture)
    ensureRegions(frame)

    -- After the fill, in this order: finished quests, unfinished quests, rest.
    local cur, max = d.cur, d.max
    local alpha = bar.overlayOpacity or 0.45
    if cur and max and not d.maxLevel then
        local at = cur
        local qc = bar.showQuest and (d.questComplete or 0) or 0
        stretch(frame.xpQuest, frame, at, qc, max, bar.questColor, alpha, texture)
        at = at + qc
        local qi = (bar.showQuest and bar.showIncomplete) and (d.questIncomplete or 0) or 0
        stretch(frame.xpIncomplete, frame, at, qi, max, bar.incompleteColor, alpha, texture)
        at = at + qi
        stretch(frame.xpRested, frame, at, bar.showRested and d.rested or 0, max, bar.restedFillColor, alpha, texture)
    else
        frame.xpQuest:Hide(); frame.xpIncomplete:Hide(); frame.xpRested:Hide()
    end

    local size, c = bar.fontSize or 11, bar.textColor
    for _, fs in ipairs({ frame.left, frame.center, frame.right }) do
        UI.FontFor("resourcebars", fs, size, "OUTLINE")
        fs:SetTextColor(c.r, c.g, c.b)
    end
    UI.FontFor("resourcebars", frame.xpInfo, bar.infoSize or 11, "OUTLINE")
    frame.xpInfo:SetTextColor(c.r, c.g, c.b)

    -- In the bar, above or below it. "auto" is in the bar on the client's,
    -- which has the action bars right above and below it, and below our own.
    local where = bar.infoAnchor or "auto"
    if where == "auto" then where = isClientStyle(bar) and "inside" or "below" end
    local infoLeft, infoRight = infoParts(bar, d)

    if where == "inside" then
        frame.left:SetText(join(leftText(bar, d), infoLeft))
        frame.right:SetText(join(infoRight, rightText(bar, d)))
        frame.xpInfo:SetText("")
        frame.xpInfo:Hide()
    else
        frame.left:SetText(leftText(bar, d))
        frame.right:SetText(rightText(bar, d))
        frame.xpInfo:ClearAllPoints()
        if where == "above" then
            frame.xpInfo:SetPoint("BOTTOM", frame, "TOP", 0, 3)
        else
            frame.xpInfo:SetPoint("TOP", frame, "BOTTOM", 0, -3)
        end
        frame.xpInfo:SetText(join(infoLeft, infoRight))
        frame.xpInfo:Show()
    end
    frame.center:SetText(centerText(bar, d))
    frame.center:Show()
    placeTexts(frame, bar)
    fitSides(frame, bar)
end

-- Our own bar, built by RB.BuildRegions and dressed by RB.PaintLook: the real
-- one and the settings page's preview alike.
function XP.Paint(frame, bar, d)
    local color = (bar.useRestColor ~= false and d.isRested) and bar.restedFillColor or bar.fillColor
    frame.fill:SetStatusBarColor(color.r, color.g, color.b)

    if d.maxLevel then
        frame.fill:SetMinMaxValues(0, 1)
        frame.fill:SetValue(1)
    else
        -- The raw values: should they ever be secret, the widget still takes them.
        frame.fill:SetMinMaxValues(0, d.rawMax or d.max or 1)
        frame.fill:SetValue(d.rawCur or d.cur or 0)
    end
    local tex = frame.fill:GetStatusBarTexture()
    XP.PaintExtras(frame, bar, d, tex and tex:GetTexture() or RB.WHITE)
end

-- ---------------------------------------------------------------- client bar --

-- The client's experience bar, in whichever of its two containers shows it.
local function clientExpBar()
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local index = enum and enum.Experience
    if not index then return nil end
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local container = _G[name]
        local expBar = container and container.bars and container.bars[index]
        if expBar and expBar:IsShown() then return expBar end
    end
    return nil
end

-- The width of the client's bar, for the settings preview: the texts are cut
-- to the room they have, so the preview has to have the same room.
function XP.ClientBarWidth()
    local expBar = clientExpBar()
    local w = expBar and expBar.StatusBar and expBar.StatusBar:GetWidth()
    if type(w) == "number" and w > 50 then return w end
    return nil
end

-- Everything of the client's we made transparent, and how to give it back.
local touched = {}

local function setClientAlpha(region, alpha)
    if not region then return end
    if alpha < 1 then
        region:SetAlpha(alpha)
        touched[region] = true
    elseif touched[region] then
        region:SetAlpha(1)
        touched[region] = nil
    end
end

local function releaseClient()
    for region in pairs(touched) do region:SetAlpha(1) end
    wipe(touched)
end

-- The frame over the client's bar. A child of the client's StatusBar, so it
-- moves, scales, fades and hides with it -- wherever the action bars put that
-- bar, this goes along. It never takes the mouse: the client's tooltip on its
-- own bar keeps working underneath.
local over

local function updateClientBar(bar, d, want)
    local expBar = want and clientExpBar() or nil
    if not (expBar and expBar.StatusBar) then
        if over then over:Hide() end
        releaseClient()
        return
    end
    if not over then
        over = CreateFrame("Frame", nil, expBar.StatusBar)
        over:EnableMouse(false)
        -- The texts over the client's own, which sit on MEDIUM.
        over.textHolder = CreateFrame("Frame", nil, over)
        over.textHolder:SetAllPoints(over)
        over.textHolder:SetFrameStrata("MEDIUM")
        over.textHolder:EnableMouse(false)
    end
    if over:GetParent() ~= expBar.StatusBar then over:SetParent(expBar.StatusBar) end
    over:ClearAllPoints()
    over:SetAllPoints(expBar.StatusBar)
    over:SetFrameLevel(expBar.StatusBar:GetFrameLevel() + 2)
    over.textHolder:SetFrameLevel((expBar.OverlayFrame and expBar.OverlayFrame:GetFrameLevel() or over:GetFrameLevel()) + 5)
    over:Show()

    XP.PaintExtras(over, bar, d, CLIENT_TEXTURE)

    -- The client draws its own rest from the fill onward; ours starts after
    -- the quests, so only one of the two may show.
    local ours = bar.showRested and 0 or 1
    setClientAlpha(expBar.ExhaustionLevelFillBar, ours)
    setClientAlpha(expBar.ExhaustionTick, ours)
    -- Its "7511 / 8800" would sit right under our middle text.
    local text = expBar.OverlayFrame and expBar.OverlayFrame.Text
    local anyText = (bar.leftText or "level") ~= "none" or (bar.centerText or "valuemax") ~= "none"
        or (bar.rightText or "percentquest") ~= "none"
    setClientAlpha(text, anyText and 0 or 1)
end

-- Our own style's switch to hide the client's bar. The CONTAINER is left
-- alone: its alpha is what the client's own fade logic reads to decide what
-- to show next. Only the experience bar inside it goes transparent.
local hiddenBars = {}

function XP.ApplyBlizzard(release)
    local bar = RB.Bar(KEY)
    local hide = not release and RB.mod.active and bar and bar.enabled
        and bar.hideBlizzard and not isClientStyle(bar)
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local index = enum and enum.Experience
    if not index then return end
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local container = _G[name]
        local expBar = container and container.bars and container.bars[index]
        if expBar then
            if hide then
                expBar:SetAlpha(0)
                hiddenBars[expBar] = true
            elseif hiddenBars[expBar] then
                expBar:SetAlpha(1)
                hiddenBars[expBar] = nil
            end
        end
    end
end

-- ---------------------------------------------------------------- live --

local ticker

local function wantsClock(bar)
    return bar.showRate or bar.showLevelTime or bar.showSessionTime
end

function XP.Update()
    local frame, bar = RB.frames[KEY], RB.Bar(KEY)
    if not (frame and bar) then return end
    local d = XP.Read()
    local client = isClientStyle(bar)
    local on = RB.mod.active and bar.enabled and true or false

    -- Our own bar under the client style is not hidden, it does not exist --
    -- Edit Mode must not offer it either (RB.UpdateVisibility).
    local suppressed = d.disabled or (d.maxLevel and not bar.showAtMaxLevel)
    if frame.disabledByStyle ~= client or frame.suppressed ~= suppressed then
        frame.disabledByStyle = client
        frame.suppressed = suppressed
        RB.UpdateVisibility(KEY)
    end
    if not client then
        XP.Paint(frame, bar, d)
        frame.maxValue = d.max
    end
    updateClientBar(bar, d, on and client and not d.disabled)

    -- The clock texts move by the second; nothing else does, so the ticker
    -- only runs while one of them is on.
    local want = on and wantsClock(bar)
    if want and not ticker then
        ticker = C_Timer.NewTicker(1, XP.Update)
    elseif not want and ticker then
        ticker:Cancel(); ticker = nil
    end
    if want and bar.showLevelTime and not played.stamp then requestPlayed() end

    XP.ApplyBlizzard()
end

function XP.Stop()
    if ticker then ticker:Cancel(); ticker = nil end
    if over then over:Hide() end
    releaseClient()
    XP.ApplyBlizzard(true)
end

-- The client swaps the bar a container shows (experience, reputation, ...)
-- on its own; the frame over it follows at once rather than a second later.
local hookedClient = false

function XP.HookClient()
    if hookedClient then return end
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    if not enum then return end
    hookedClient = true
    for _, name in ipairs({ "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
        local container = _G[name]
        if container and type(container.ApplyPendingBarToShow) == "function" then
            hooksecurefunc(container, "ApplyPendingBarToShow", function()
                if RB.mod.active then XP.Update() end
            end)
        end
    end
end

-- ---------------------------------------------------------------- events --

function XP.RegisterEvents(mod)
    XP.HookClient()
    mod:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin)
        if isLogin then
            resetSession(ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player")))
            played.stamp = nil
        end
        scanQuests()
        XP.Update()
    end)
    mod:RegisterEvent("PLAYER_XP_UPDATE", function(_, unit)
        if unit and unit ~= "player" then return end
        trackGain(ns.Num(UnitXP("player")), ns.Num(UnitXPMax("player")))
        XP.Update()
    end)
    mod:RegisterEvent("PLAYER_LEVEL_UP", function()
        -- A new level starts its own clock from nothing.
        if played.stamp then
            played.total = played.total + (GetTime() - played.stamp)
            played.level, played.stamp = 0, GetTime()
        end
        XP.Update()
    end)
    mod:RegisterEvent("UPDATE_EXHAUSTION", XP.Update)
    mod:RegisterEvent("ENABLE_XP_GAIN", XP.Update)
    mod:RegisterEvent("DISABLE_XP_GAIN", XP.Update)
    mod:RegisterEvent("QUEST_LOG_UPDATE", function() scanQuests(); XP.Update() end)
    mod:RegisterEvent("TIME_PLAYED_MSG", function(_, total, level) onPlayed(total, level); XP.Update() end)
end
