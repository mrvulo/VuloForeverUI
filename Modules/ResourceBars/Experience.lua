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
local function trackGain(cur, max)
    local s = session()
    if not (s and cur and max) then return end
    if not (s.start and s.last and s.lastMax) then resetSession(cur, max); return end
    local gained = cur - s.last
    if gained < 0 then gained = (s.lastMax - s.last) + cur end
    if gained > 0 then s.gained = (s.gained or 0) + gained end
    s.last, s.lastMax = cur, max
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
        if secs > 0 and gained > 0 then
            d.perHour = math.ceil(gained / (secs / 3600))
            d.toLevel = math.ceil((d.max - d.cur) / d.perHour * 3600)
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

-- The parts only this bar has, added to a frame RB.BuildRegions made. Lazy, so
-- the preview's pooled frames get them the first time they show this bar.
local function ensureRegions(frame)
    if frame.xpQuest then return end
    local fill = frame.fill
    -- On the fill's own frame, under its texture: they start where the fill
    -- ends, so the order only matters where a rounding pixel overlaps.
    frame.xpQuest      = fill:CreateTexture(nil, "BORDER", nil, 1)
    frame.xpIncomplete = fill:CreateTexture(nil, "BORDER", nil, 2)
    frame.xpRested     = fill:CreateTexture(nil, "BORDER", nil, 3)

    local center = frame.textHolder:CreateFontString(nil, "OVERLAY")
    center:SetPoint("CENTER", frame, "CENTER", 0, 0)
    center:SetJustifyH("CENTER")
    frame.center = center

    local info = frame.textHolder:CreateFontString(nil, "OVERLAY")
    info:SetJustifyH("CENTER")
    frame.xpInfo = info
end
XP.EnsureRegions = ensureRegions

-- A stretch of the bar that starts `from` and is `width` long, both in
-- experience; clipped to the end of the bar.
local function stretch(tex, frame, from, width, max, color, alpha)
    if not (max and max > 0 and width and width > 0 and from < max) then tex:Hide(); return end
    local barW = frame:GetWidth() or 0
    local x1 = barW * from / max
    local x2 = barW * math.min(max, from + width) / max
    if x2 - x1 < 0.5 then tex:Hide(); return end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, 0)
    tex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x1, 0)
    tex:SetWidth(x2 - x1)
    tex:SetTexture(frame.fill:GetStatusBarTexture():GetTexture() or RB.WHITE)
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

local function infoText(bar, d)
    local parts = {}
    if not d.maxLevel and d.max and d.max > 0 then
        if bar.showRate then
            parts[#parts + 1] = string.format(L["Level in %s  ·  %s XP/h"],
                d.toLevel and duration(d.toLevel) or "--", d.perHour and short(d.perHour) or "0")
        end
        if bar.showQuestRested then
            parts[#parts + 1] = string.format(L["Quests: |cffffab07%s|r  ·  Rested: |cff4f90ff%s|r"],
                pct((d.questComplete or 0) / d.max * 100), pct((d.rested or 0) / d.max * 100))
        end
    end
    if bar.showLevelTime and d.levelTime then
        if d.maxLevel then
            parts[#parts + 1] = string.format(L["Played: %s"], duration(d.totalTime))
        else
            parts[#parts + 1] = string.format(L["This level: %s"], duration(d.levelTime))
        end
    end
    if bar.showSessionTime and d.sessionTime then
        parts[#parts + 1] = string.format(L["This session: %s"], duration(d.sessionTime))
    end
    return table.concat(parts, "     ")
end

-- Draws `d` onto any frame built by RB.BuildRegions and dressed by
-- RB.PaintLook: the real bar and the settings page's preview alike.
function XP.Paint(frame, bar, d)
    ensureRegions(frame)

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

    -- After the fill, in this order: finished quests, unfinished quests, rest.
    local cur, max = d.cur, d.max
    local alpha = bar.overlayOpacity or 0.45
    if cur and max and not d.maxLevel then
        local at = cur
        local qc = bar.showQuest and (d.questComplete or 0) or 0
        stretch(frame.xpQuest, frame, at, qc, max, bar.questColor, alpha)
        at = at + qc
        local qi = (bar.showQuest and bar.showIncomplete) and (d.questIncomplete or 0) or 0
        stretch(frame.xpIncomplete, frame, at, qi, max, bar.incompleteColor, alpha)
        at = at + qi
        stretch(frame.xpRested, frame, at, bar.showRested and d.rested or 0, max, bar.restedFillColor, alpha)
    else
        frame.xpQuest:Hide(); frame.xpIncomplete:Hide(); frame.xpRested:Hide()
    end

    local size = bar.fontSize or 11
    UI.FontFor("resourcebars", frame.center, size, "OUTLINE")
    frame.center:SetTextColor(bar.textColor.r, bar.textColor.g, bar.textColor.b)
    UI.FontFor("resourcebars", frame.xpInfo, bar.infoSize or 11, "OUTLINE")
    frame.xpInfo:SetTextColor(bar.textColor.r, bar.textColor.g, bar.textColor.b)
    frame.xpInfo:ClearAllPoints()
    frame.xpInfo:SetPoint("TOP", frame, "BOTTOM", 0, -3)

    frame.left:SetText(leftText(bar, d))
    frame.center:SetText(centerText(bar, d))
    frame.right:SetText(rightText(bar, d))
    frame.xpInfo:SetText(infoText(bar, d))
    frame.center:Show()
    frame.xpInfo:Show()
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
    XP.Paint(frame, bar, d)
    frame.maxValue = d.max

    -- Nothing to show at the top, or with experience switched off -- unless the
    -- player wants the bar there anyway.
    local suppressed = d.disabled or (d.maxLevel and not bar.showAtMaxLevel)
    if frame.suppressed ~= suppressed then
        frame.suppressed = suppressed
        RB.UpdateVisibility(KEY)
    end

    -- The clock texts move by the second; nothing else does, so the ticker
    -- only runs while one of them is on.
    local want = RB.mod.active and bar.enabled and wantsClock(bar)
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
    XP.ApplyBlizzard(true)
end

-- ---------------------------------------------------------------- client bar --

-- Hiding the client's own experience bar. The CONTAINER is left alone: its
-- alpha is what the client's own fade logic reads to decide what to show next.
-- Only the experience bar inside it goes transparent, and it comes back the
-- moment the setting or the module is switched off.
local hiddenBars = {}

function XP.ApplyBlizzard(release)
    local bar = RB.Bar(KEY)
    local hide = not release and RB.mod.active and bar and bar.enabled and bar.hideBlizzard
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

-- ---------------------------------------------------------------- events --

function XP.RegisterEvents(mod)
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
