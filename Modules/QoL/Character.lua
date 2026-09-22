-- VuloForeverUI / Modules / QoL / Character
--
-- The five answers you would otherwise click yourself: taking a quest, handing
-- it in, accepting a resurrection or a summon, and releasing in a battleground.
--
-- WHAT THE CLIENT ALLOWS, AND HOW THAT WAS ESTABLISHED
--
-- Every call here exists in 1.60.1 (checked against the generated GlobalAPI and
-- Events lists for this build, not from memory), and every one of them is what
-- Blizzard's own, non-secure UI calls from an ordinary button: the quest frame's
-- accept button, the resurrect popup, the summon popup, the death popup. That is
-- why they are plain APIs rather than protected ones.
--
-- The residual risk is a different one. This client refuses some calls made
-- WITHOUT user input -- from a timer or an event handler -- and a refused
-- protected call raises no Lua error at all, so pcall reports success either way
-- (docs/forever-client-research.md). Everything below runs from an event
-- handler, which is exactly that shape. So each action is written to be harmless
-- when it silently does nothing: the frame the player would have clicked stays
-- open, and they click it. Nothing here retries, and nothing here assumes it
-- worked.
--
-- TWO THINGS IT DELIBERATELY DOES NOT DO
--
--   * it never picks a quest reward. With a choice on the table the turn-in
--     stops and the window stays open -- picking for you is the one mistake
--     that cannot be undone
--   * it never accepts a resurrection or a summon while you are in combat: a
--     resurrection taken mid-fight puts you back on the floor, and a summon
--     accepted mid-fight is a wipe someone has to explain
--
-- Holding SHIFT suppresses the quest half for as long as it is held, the same
-- escape hatch the one-click looting has.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Char = QoL.RegisterPart("character", {})
QoL.Character = Char

local function db() return QoL.db().character end

-- Shift is the "not this one" key. Read once per event, never cached.
local function suppressed()
    return IsShiftKeyDown and IsShiftKeyDown()
end

-- InCombatLockdown, not UnitAffectingCombat: the unit query can come back as a
-- secret in restricted content, and a boolean test on a secret throws rather
-- than answering. The lockdown flag is the client's own state and always reads.
local function inCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- ------------------------------------------------------------- quests --

-- A quest the client accepted for us (a popup from an item) arrives already
-- accepted; acknowledging it is what closes it, accepting it again is not a
-- thing. Blizzard's own frame makes the same distinction.
local function onQuestDetail()
    if not db().acceptQuests or suppressed() then return end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        if AcknowledgeAutoAcceptQuest then AcknowledgeAutoAcceptQuest() end
        if CloseQuest then CloseQuest() end
        return
    end
    if AcceptQuest then AcceptQuest() end
end

local function onQuestProgress()
    if not db().turnInQuests or suppressed() then return end
    -- "Completable" is the client's own verdict on whether the items and the
    -- count are there. Without it this would click through a quest you cannot
    -- hand in yet and close the window on you.
    if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

local function onQuestComplete()
    if not db().turnInQuests or suppressed() then return end
    local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
    -- More than one reward: your decision, not ours. The window stays open.
    if choices > 1 then return end
    if GetQuestReward then GetQuestReward(choices == 1 and 1 or 0) end
end

-- --------------------------------------------------- rez and summons --

local function onResurrectRequest()
    if not db().acceptResurrect or inCombat() then return end
    if AcceptResurrect then AcceptResurrect() end
end

local function onConfirmSummon()
    if not db().acceptSummon or inCombat() then return end
    local S = _G.C_SummonInfo
    if not (S and S.ConfirmSummon) then return end
    -- The offer expires; a summon with no time left is not one to confirm.
    local left = S.GetSummonConfirmTimeLeft and S.GetSummonConfirmTimeLeft()
    if type(left) == "number" and left <= 0 then return end
    S.ConfirmSummon()
    local hide = _G.StaticPopup_Hide
    if hide then hide("CONFIRM_SUMMON") end
end

-- ------------------------------------------------------------ dying --

-- Only where dying costs nothing but the walk back: a battleground or an arena.
-- In the world, releasing is a decision (a healer may be on the way), and out
-- there the corpse run is the price.
local function onPlayerDead()
    if not db().releasePvP then return end
    local _, kind = IsInInstance()
    if kind ~= "pvp" and kind ~= "arena" then return end
    -- In an arena the client itself refuses the release until the round is
    -- decided; calling it then is simply ignored, which is why this does not
    -- retry.
    if RepopMe then RepopMe() end
end

-- ------------------------------------------------------------ apply --

function Char.Apply()
    local d = db()
    QoL.SyncEvent(d.acceptQuests,  "QUEST_DETAIL",      onQuestDetail)
    QoL.SyncEvent(d.turnInQuests,  "QUEST_PROGRESS",    onQuestProgress)
    QoL.SyncEvent(d.turnInQuests,  "QUEST_COMPLETE",    onQuestComplete)
    QoL.SyncEvent(d.acceptResurrect, "RESURRECT_REQUEST", onResurrectRequest)
    QoL.SyncEvent(d.acceptSummon,  "CONFIRM_SUMMON",    onConfirmSummon)
    QoL.SyncEvent(d.releasePvP,    "PLAYER_DEAD",       onPlayerDead)
end

function Char.Disable()
    QoL.SyncEvent(false, "QUEST_DETAIL",      onQuestDetail)
    QoL.SyncEvent(false, "QUEST_PROGRESS",    onQuestProgress)
    QoL.SyncEvent(false, "QUEST_COMPLETE",    onQuestComplete)
    QoL.SyncEvent(false, "RESURRECT_REQUEST", onResurrectRequest)
    QoL.SyncEvent(false, "CONFIRM_SUMMON",    onConfirmSummon)
    QoL.SyncEvent(false, "PLAYER_DEAD",       onPlayerDead)
end
