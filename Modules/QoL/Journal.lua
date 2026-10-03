-- VuloForeverUI / Modules / QoL / Journal
--
-- A quest journal per character: every quest accepted, handed in or
-- abandoned and every level gained, with the date, the level and the zone.
-- Kept in the character's saved variables (questJournal), the newest at the
-- bottom, shown in a window of its own (/vfjournal or the Quest tab).
--
-- HAND-IN OR ABANDON
--
-- The client says QUEST_REMOVED for both. A hand-in also says QUEST_TURNED_IN
-- and flags the quest completed, so a removal is called an abandon only when,
-- a moment later, neither of the two happened.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local J = QoL.RegisterPart("journal", {})
QoL.Journal = J

local MAX_ENTRIES = 3000

local registered
local turnedIn = {}   -- questID -> true, for the abandon test above
local window

local readable = ns.Readable

local function db() return QoL.db().quest end
local function isTrue(v) return ns.CanRead(v) and v == true end

local function store()
    local c = ns.db and ns.db.char
    if not c then return nil end
    if type(c.questJournal) ~= "table" then c.questJournal = {} end
    return c.questJournal
end

local function add(kind, id, title, extra)
    local list = store()
    if not list then return end
    local e = { t = time(), k = kind, lvl = readable(UnitLevel("player")),
                zone = readable(GetRealZoneText()) }
    if id then
        e.id = id
        e.title = title or readable(C_QuestLog.GetTitleForQuestID(id))
    end
    for k, v in pairs(extra or {}) do e[k] = v end
    list[#list + 1] = e
    while #list > MAX_ENTRIES do table.remove(list, 1) end
    if window and window:IsShown() then J.Render() end
end

-- ---------------------------------------------------------------- events --

local function onAccepted(_, id)
    id = readable(id)
    if type(id) == "number" then add("accept", id) end
end

local function onTurnedIn(_, id, xp, money)
    id = readable(id)
    if type(id) ~= "number" then return end
    turnedIn[id] = true
    xp, money = readable(xp), readable(money)
    add("turnin", id, nil, { xp = type(xp) == "number" and xp > 0 and xp or nil,
                             money = type(money) == "number" and money > 0 and money or nil })
end

local function onRemoved(_, id)
    id = readable(id)
    if type(id) ~= "number" then return end
    local title = readable(C_QuestLog.GetTitleForQuestID(id))
    C_Timer.After(1, function()
        if turnedIn[id] then turnedIn[id] = nil; return end
        if isTrue(C_QuestLog.IsQuestFlaggedCompleted(id)) then return end
        add("abandon", id, title)
    end)
end

local function onLevel(_, level)
    level = readable(level)
    if type(level) == "number" then add("level", nil, nil, { lvl = level }) end
end

local EVENTS = {
    QUEST_ACCEPTED = onAccepted,
    QUEST_TURNED_IN = onTurnedIn,
    QUEST_REMOVED = onRemoved,
    PLAYER_LEVEL_UP = onLevel,
}

-- ---------------------------------------------------------------- window --

local function line(e)
    local stamp = "|cff808080" .. date("%Y-%m-%d %H:%M", e.t or 0) .. "|r  "
    local lvl = e.lvl and ("|cffaaaaaa[" .. e.lvl .. "]|r ") or ""
    local name = e.title or (L["Quest"] .. " #" .. tostring(e.id))
    local where = e.zone and e.zone ~= "" and ("  |cff808080" .. e.zone .. "|r") or ""
    if e.k == "accept" then
        return stamp .. lvl .. L["Accepted: %s"]:format(name) .. where
    elseif e.k == "turnin" then
        local xp = e.xp and ("  |cffb0b0ff" .. L["+%s XP"]:format(BreakUpLargeNumbers(e.xp)) .. "|r") or ""
        return stamp .. lvl .. "|cff59d966" .. L["Handed in: %s"]:format(name) .. "|r" .. xp .. where
    elseif e.k == "abandon" then
        return stamp .. lvl .. "|cffff6666" .. L["Abandoned: %s"]:format(name) .. "|r" .. where
    elseif e.k == "level" then
        return stamp .. "|cffffd100" .. L["Reached level %d"]:format(e.lvl or 0) .. "|r" .. where
    end
    return stamp .. tostring(e.k)
end

local function ensureWindow()
    if window then return end
    local UI = ns.UI
    window = CreateFrame("Frame", "VFUI_QuestJournal", UIParent)
    window:SetSize(520, 440)
    window:SetPoint("CENTER")
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    UI:StyleBackdrop(window, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    if UI.CreateShadow then UI:CreateShadow(window) end
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    table.insert(_G.UISpecialFrames, "VFUI_QuestJournal")

    window.strip = window:CreateTexture(nil, "ARTWORK")
    window.strip:SetPoint("TOPLEFT")
    window.strip:SetPoint("TOPRIGHT")
    window.strip:SetHeight(2)

    window.title = window:CreateFontString(nil, "OVERLAY")
    UI.Font(window.title, 13)
    window.title:SetPoint("TOPLEFT", 14, -12)
    window.title:SetText(L["Quest journal"])
    UI:CreateCloseX(window, function() window:Hide() end)

    window.summary = window:CreateFontString(nil, "OVERLAY")
    UI.Font(window.summary, 11)
    window.summary:SetPoint("TOPLEFT", 14, -34)
    window.summary:SetTextColor(0.75, 0.75, 0.75)

    local log = CreateFrame("ScrollingMessageFrame", nil, window)
    log:SetPoint("TOPLEFT", 14, -56)
    log:SetPoint("BOTTOMRIGHT", -14, 14)
    UI.Font(log, 11)
    log:SetJustifyH("LEFT")
    log:SetFading(false)
    log:SetMaxLines(MAX_ENTRIES)
    log:SetHyperlinksEnabled(false)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, delta)
        for _ = 1, 3 do
            if delta > 0 then self:ScrollUp() else self:ScrollDown() end
        end
    end)
    window.log = log
end

function J.Render()
    if not window then return end
    local ac = ns.COLORS.accent
    ns.UI.SetGradient(window.strip, "HORIZONTAL", ac.r, ac.g, ac.b, 0.1, ac.r, ac.g, ac.b, 0.9)
    window.title:SetTextColor(ac.r, ac.g, ac.b)
    local log = window.log
    log:Clear()
    local list = store() or {}
    local done, dropped, xp = 0, 0, 0
    for _, e in ipairs(list) do
        if e.k == "turnin" then done = done + 1; xp = xp + (e.xp or 0) end
        if e.k == "abandon" then dropped = dropped + 1 end
        log:AddMessage(line(e))
    end
    if #list == 0 then
        log:AddMessage(L["No entries yet. Quests you accept from now on are written here."])
    end
    window.summary:SetText(L["%d quests handed in, %d abandoned, %s experience from quests"]:format(
        done, dropped, BreakUpLargeNumbers(xp)))
    log:ScrollToBottom()
end

function J.Open()
    ensureWindow()
    window:Show()
    J.Render()
end

ns:RegisterSlash({ key = "JOURNAL", commands = { "/vfjournal" },
    desc = "Open the quest journal: every quest accepted, handed in and abandoned.",
    module = "qol",
})
ns.Slash.JOURNAL = function()
    if window and window:IsShown() then window:Hide() else J.Open() end
end

-- --------------------------------------------------------------- switch --

function J.Apply()
    local on = QoL.mod.active and db().journal and true or false
    if on ~= registered then
        registered = on
        for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
    end
end

function J.Disable()
    if registered then
        for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    end
    registered = nil
end
