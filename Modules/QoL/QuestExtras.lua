-- VuloForeverUI / Modules / QoL / QuestExtras
--
-- Additions to the client's own quest windows rather than a quest UI of ours:
--
--   levels     the quest level in front of every quest a quest giver offers or
--              takes back, in both of the client's dialogs (the gossip list and
--              the plain quest greeting). The quest log already shows it, and
--              the tracker has a client switch for it (showQuestLevel), which
--              the options page offers next to this one.
--   sounds     a short sound when an objective moves on, when one is done, and
--              when the whole quest is ready to hand in
--   group      the same moments told to the party
--
-- WHERE THE MOMENTS COME FROM
--
-- There is no event per objective. The quest log is read after every log
-- update and compared with the read before: a count that went up is progress,
-- an objective that turned finished is done, a quest that turned complete is
-- ready. A quest seen for the first time -- just accepted, or the first read
-- after login -- is only remembered, so neither makes a sound.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local X = QoL.RegisterPart("questextras", {})
QoL.QuestExtras = X

local function db() return QoL.db().quest end
local function active() return QoL.mod.active and true or false end

-- ---------------------------------------------------------------- levels --

local function prefix(level, questID)
    if not ns.CanRead(level) or type(level) ~= "number" or level <= 0 then return nil end
    local elite = ""
    if questID and C_QuestLog.IsEliteQuest then
        local ok, e = pcall(C_QuestLog.IsEliteQuest, questID)
        if ok and ns.CanRead(e) and e == true then elite = "+" end
    end
    return "[" .. level .. elite .. "] "
end

-- The gossip list: its buttons are set up from the quest's own info, which
-- carries the level. The button writes its title once more with the level in
-- front, through its own method, so the colour and the resize stay its own.
local function gossipSetup(button, info)
    if not (active() and db().levelsDialog) or type(info) ~= "table" then return end
    local p = prefix(info.questLevel, info.questID)
    if not (p and type(info.title) == "string") then return end
    -- The shared base method: text, colour and resize, without the quest-data
    -- callback the button's own override would store on it.
    local base = GossipSharedQuestButtonMixin and GossipSharedQuestButtonMixin.UpdateTitleForQuest
    if type(base) ~= "function" then return end
    base(button, info.questID, p .. info.title, info.isIgnored, info.isTrivial)
end

-- The plain greeting: the client lays its buttons out on show and ends with a
-- bare SetText of the title, so the level goes on after that.
local function greetingShow()
    if not (active() and db().levelsDialog) then return end
    local pool = QuestFrameGreetingPanel and QuestFrameGreetingPanel.titleButtonPool
    if not pool then return end
    for button in pool:EnumerateActive() do
        local id = button:GetID()
        local level, title, questID
        if button.isActive == 1 then
            level, title, questID = GetActiveLevel(id), GetActiveTitle(id), GetActiveQuestID(id)
        else
            level, title = GetAvailableLevel(id), GetAvailableTitle(id)
            questID = select(5, GetAvailableQuestInfo(id))
        end
        local p = prefix(level, questID)
        if p and type(title) == "string" then
            button:SetText(p .. title)
            local icon = button.Icon
            button:SetHeight(math.max(button:GetTextHeight() + 2, icon and icon:GetHeight() or 0))
        end
    end
end

-- Hooked once and for good; the setting is read inside. The mixin tables are
-- hooked before the client builds its first gossip button, which copies the
-- hooked Setup into every button made from them.
local hookedDialogs
local function hookDialogs()
    if hookedDialogs then return end
    hookedDialogs = true
    for _, mixin in ipairs({ GossipAvailableQuestButtonMixin, GossipActiveQuestButtonMixin }) do
        if type(mixin) == "table" and type(mixin.Setup) == "function" then
            hooksecurefunc(mixin, "Setup", gossipSetup)
        end
    end
    if QuestFrameGreetingPanel then
        QuestFrameGreetingPanel:HookScript("OnShow", greetingShow)
    end
end

-- The tracker's level is the client's own switch.
function X.TrackerLevels()
    return C_CVar.GetCVarBool("showQuestLevel") and true or false
end

function X.SetTrackerLevels(on)
    if InCombatLockdown() then return end
    pcall(SetCVar, "showQuestLevel", on and "1" or "0")
end

-- ---------------------------------------------------------------- sounds --

-- Sound kits that exist in this client's data; 0 is silence.
X.SOUNDS = {
    { value = 0,     text = "Off" },
    { value = 877,   text = "Click" },
    { value = 120,   text = "Coins" },
    { value = 3175,  text = "Map ping" },
    { value = 878,   text = "Quest done" },
    { value = 880,   text = "Invite" },
    { value = 8960,  text = "Ready check" },
    { value = 12867, text = "Alarm" },
}

function X.Play(kit)
    if type(kit) == "number" and kit > 0 then pcall(PlaySound, kit, "Master") end
end

-- ----------------------------------------------------------------- group --

local function tell(msg)
    if not (IsInGroup() and not IsInRaid()) then return end
    local lock = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if lock then
        local ok, locked = pcall(lock)
        if not ok or locked ~= false then return end
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, msg, "PARTY") end
end

-- ------------------------------------------------------------- the reads --

local known, primed = {}, false

-- One quest as it stands: count and finished flag per objective, and the
-- quest's own complete flag. nil when any of it cannot be read -- the last
-- good read is kept then, so nothing fires on a gap.
local function read(questID)
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if type(objs) ~= "table" then return nil end
    local s = { count = {}, done = {}, text = {} }
    for i, o in ipairs(objs) do
        local n, fin, text = o.numFulfilled, o.finished, o.text
        if not (ns.CanRead(n) and ns.CanRead(fin)) then return nil end
        s.count[i] = type(n) == "number" and n or 0
        s.done[i] = fin == true
        s.text[i] = ns.CanRead(text) and type(text) == "string" and text or nil
    end
    local complete = C_QuestLog.IsComplete(questID)
    if not ns.CanRead(complete) then return nil end
    s.complete = complete == true
    return s
end

-- What changed between two reads of the same quest: 3 ready, 2 an objective
-- done, 1 progress, 0 nothing -- and the lines for the group.
local function compare(title, old, new, lines)
    local d = db()
    local what = d.announceWhat or "objectives"
    if new.complete and not old.complete then
        lines[#lines + 1] = L["%s: ready to hand in"]:format(title)
        return 3
    end
    local level = 0
    for i, n in ipairs(new.count) do
        local text = new.text[i]
        if new.done[i] and not old.done[i] then
            level = math.max(level, 2)
            if text and what ~= "complete" then lines[#lines + 1] = ("%s: %s"):format(title, text) end
        elseif n > (old.count[i] or 0) then
            level = math.max(level, 1)
            if text and what == "progress" then lines[#lines + 1] = ("%s: %s"):format(title, text) end
        end
    end
    return level
end

local function scan()
    local d = db()
    local seen, loudest, lines = {}, 0, {}
    local numEntries = C_QuestLog.GetNumQuestLogEntries()
    for i = 1, (type(numEntries) == "number" and numEntries or 0) do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if type(id) == "number" and id > 0 then
            seen[id] = true
            local new = read(id)
            if new then
                local old = known[id]
                if old and primed then
                    loudest = math.max(loudest, compare(info.title or "?", old, new, lines))
                end
                known[id] = new
            end
        end
    end
    for id in pairs(known) do
        if not seen[id] then known[id] = nil end
    end
    primed = true

    if loudest == 3 then X.Play(d.soundComplete)
    elseif loudest == 2 then X.Play(d.soundObjective)
    elseif loudest == 1 then X.Play(d.soundProgress) end
    if d.announce then
        for _, line in ipairs(lines) do tell(line) end
    end
end

-- The log fires its update in bursts; one read per burst.
local pending
local function queue()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = nil
        if active() and X.Watching() then
            local ok, err = pcall(scan)
            if not ok then ns:Debug("qol quest extras: %s", tostring(err)) end
        end
    end)
end

local function onUnitLog(_, unit)
    if unit == "player" then queue() end
end

-- --------------------------------------------------------------- switch --

local EVENTS = {
    QUEST_LOG_UPDATE = queue,
    UNIT_QUEST_LOG_CHANGED = onUnitLog,
    QUEST_ACCEPTED = queue,
    QUEST_REMOVED = queue,
}

function X.Watching()
    local d = db()
    return d.announce or (d.soundProgress or 0) > 0 or (d.soundObjective or 0) > 0
        or (d.soundComplete or 0) > 0
end

local registered
function X.Apply()
    if db().levelsDialog then hookDialogs() end
    local on = X.Watching()
    if on ~= registered then
        registered = on
        for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
        -- a fresh start remembers first and speaks after
        wipe(known)
        primed = false
        if on then queue() end
    end
end

function X.Disable()
    if registered then
        for event, fn in pairs(EVENTS) do ns:UnregisterEvent(event, fn) end
    end
    registered = nil
    wipe(known)
    primed = false
end
