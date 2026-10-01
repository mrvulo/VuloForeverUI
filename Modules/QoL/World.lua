-- VuloForeverUI / Modules / QoL / World
--
-- Two kinds of answer: one that saves a click at an NPC, and the ones that
-- decide who is allowed to interrupt you -- invites, trades, duels, friend
-- requests, shared quests -- plus the one invite you ask for by whisper.
--
-- THE ONE-OPTION RULE
--
-- Auto-picking a gossip option is only safe when there is exactly ONE thing to
-- pick and no quest anywhere on the frame. A quest giver with one option and a
-- quest underneath it would lose the quest to the click -- so available and
-- active quests both veto, and so does a second option. That leaves the case
-- the setting is actually for: the flight master, the innkeeper, the one-line
-- NPC that only ever had one answer.
--
-- WHAT COUNTS AS A STRANGER
--
-- Not on your friend list, not in your guild, not one of your Battle.net
-- friends' characters. The check runs on an invite or a trade, never on a
-- timer, so the Battle.net walk costs nothing in a fight.
--
-- Both blocks SAY what they did. A group invite that vanishes without a word
-- looks like a bug in the game, and the one thing worse than an unwanted invite
-- is a wanted one you never saw.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local World = QoL.RegisterPart("world", {})
QoL.World = World

local function db() return QoL.db().world end

local function suppressed()
    return IsShiftKeyDown and IsShiftKeyDown()
end

-- --------------------------------------------------------- one option --

local function onGossipShow()
    if not db().gossipSingle or suppressed() then return end
    local G = _G.C_GossipInfo
    if not G then return end

    local avail  = G.GetAvailableQuests and G.GetAvailableQuests()
    local active = G.GetActiveQuests and G.GetActiveQuests()
    if (avail and #avail > 0) or (active and #active > 0) then return end

    local opts = G.GetOptions and G.GetOptions()
    if not opts or #opts ~= 1 then return end

    -- By index where the client offers it: the option table's field names have
    -- moved between builds, the index has not.
    if G.SelectOptionByIndex then
        G.SelectOptionByIndex(1)
    elseif G.SelectOption and opts[1] and opts[1].gossipOptionID then
        G.SelectOption(opts[1].gossipOptionID)
    end
end

-- ---------------------------------------------------------- strangers --

-- "Name-Realm" and "Name" have to compare equal: an invite carries the realm,
-- the friend list mostly does not.
local function shortName(name)
    if type(name) ~= "string" then return nil end
    local base = name:match("^([^-]+)")
    return base or name
end

local function isFriend(name, guid)
    local F = _G.C_FriendList
    if not F then return false end
    if guid and F.IsFriend and F.IsFriend(guid) then return true end
    if F.GetFriendInfo then
        if F.GetFriendInfo(name) then return true end
        local short = shortName(name)
        if short and short ~= name and F.GetFriendInfo(short) then return true end
    end
    return false
end

local function isGuildMate(name)
    local G = _G.C_GuildInfo
    if not (G and G.MemberExistsByName) then return false end
    if G.MemberExistsByName(name) then return true end
    local short = shortName(name)
    return (short and short ~= name and G.MemberExistsByName(short)) or false
end

-- A Battle.net friend playing a character you have never seen is still not a
-- stranger. Checked by character name, because that is all an invite carries.
local function isBattleNetFriend(name)
    local num = _G.BNGetNumFriends and _G.BNGetNumFriends() or 0
    if num == 0 then return false end
    local BN = _G.C_BattleNet
    if not (BN and BN.GetFriendAccountInfo) then return false end
    local want = shortName(name)
    for i = 1, num do
        local info = BN.GetFriendAccountInfo(i)
        local game = info and info.gameAccountInfo
        if game and game.characterName and shortName(game.characterName) == want then
            return true
        end
    end
    return false
end

local function isStranger(name, guid)
    if type(name) ~= "string" or name == "" then return false end
    if isFriend(name, guid) then return false end
    if isGuildMate(name) then return false end
    if isBattleNetFriend(name) then return false end
    return true
end

-- The payload of PARTY_INVITE_REQUEST has gained and lost arguments between
-- builds; the inviter's name has always been the first. The GUID is picked out
-- by shape rather than by position, so a reordered payload costs nothing.
local function guidFrom(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" and v:find("^Player%-") then return v end
    end
    return nil
end

local function onPartyInvite(_, name, ...)
    if not db().blockInvites then return end
    if not isStranger(name, guidFrom(...)) then return end
    if _G.DeclineGroup then _G.DeclineGroup() end
    local hide = _G.StaticPopup_Hide
    if hide then hide("PARTY_INVITE") end
    ns:Print(L["Group invite from %s declined: not a friend, guild member or Battle.net friend."], name)
end

local function onTradeShow()
    if not db().blockTrades then return end
    -- The trade partner is the "npc" unit while the window is open; that is
    -- where the name comes from, the event carries none.
    local name = UnitName and UnitName("npc")
    local guid = UnitGUID and UnitGUID("npc")
    if not isStranger(name, guid) then return end
    if _G.CancelTrade then _G.CancelTrade() end
    ns:Print(L["Trade with %s cancelled: not a friend, guild member or Battle.net friend."], name)
end

-- -------------------------------------------------------------- duels --

local function hideDuelPopup()
    local hide = _G.StaticPopup_Hide
    if hide then hide("DUEL_REQUESTED") end
end

local function onDuelRequested(_, name)
    if not db().blockDuels then return end
    if _G.CancelDuel then _G.CancelDuel() end
    -- The client opens its popup from the same event. Whichever handler runs
    -- first, the popup is gone again by the next frame.
    hideDuelPopup()
    C_Timer.After(0, hideDuelPopup)
    if type(name) ~= "string" or not ns.CanRead(name) then name = "?" end
    ns:Print(L["Duel from %s declined."], name)
end

-- ---------------------------------------------------- invite by whisper --

-- The whole whisper has to be the keyword, case aside: "inv" invites, "can
-- you inv me later" does not. A whisper the client hands out as a secret is
-- never read at all.
local function keywordMatches(text)
    if type(text) ~= "string" or not ns.CanRead(text) then return false end
    local want = db().inviteKeyword
    if type(want) ~= "string" then return false end
    want = want:match("^%s*(.-)%s*$"):lower()
    if want == "" then return false end
    return text:match("^%s*(.-)%s*$"):lower() == want
end

-- Alone you can always invite; in a group only the leader, or an assistant in
-- a raid. Anybody else would be refused by the server.
local function canInvite()
    if not IsInGroup() then return true end
    if UnitIsGroupLeader("player") then return true end
    return IsInRaid() and UnitIsGroupAssistant("player") or false
end

local function onWhisper(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    local d = db()
    if not d.inviteWhisper or not keywordMatches(text) then return end
    if type(sender) ~= "string" or not ns.CanRead(sender) then return end
    if not ns.CanRead(guid) then guid = nil end
    if d.inviteFriendsOnly and isStranger(sender, guid) then return end
    if not canInvite() then return end
    C_PartyInfo.InviteUnit(sender)
end

-- A Battle.net whisper carries the account, not the character: the invite goes
-- to the game account, and only when it is in this same game.
local function onBNWhisper(_, text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    if not db().inviteWhisper or not keywordMatches(text) then return end
    if type(bnSenderID) ~= "number" or not ns.CanRead(bnSenderID) then return end
    if not canInvite() then return end
    local info = C_BattleNet.GetAccountInfoByID(bnSenderID)
    local game = info and info.gameAccountInfo
    if not (game and game.isOnline and game.gameAccountID) then return end
    if game.clientProgram ~= BNET_CLIENT_WOW or game.wowProjectID ~= WOW_PROJECT_ID then return end
    C_BattleNet.InviteFriend(game.gameAccountID)
end

-- ----------------------------------------------------- friend requests --

-- Every pending request goes, the ones waiting from before the login too: the
-- list is only complete once BN_FRIEND_INVITE_LIST_INITIALIZED has fired.
local function declineFriendRequests()
    if not db().blockFriendRequests then return end
    for i = BNGetNumFriendInvites(), 1, -1 do
        local info = C_BattleNet.GetFriendInviteInfo(i)
        if info and info.inviteID then
            BNDeclineFriendInvite(info.inviteID)
            ns:Print(L["Battle.net friend request from %s declined."], info.accountName or "?")
        end
    end
end

-- ------------------------------------------------------- shared quests --

-- A quest shared by a player opens the same detail window a quest giver does;
-- the "questnpc" unit is then that player. The same stranger rule as above.
function World.BlocksSharedQuest()
    if not db().blockSharedQuests then return false end
    if not UnitIsPlayer("questnpc") then return false end
    local name, guid = UnitName("questnpc"), UnitGUID("questnpc")
    if type(name) ~= "string" or not ns.CanRead(name) then return false end
    if not ns.CanRead(guid) then guid = nil end
    return isStranger(name, guid)
end

local function onQuestDetail()
    if not World.BlocksSharedQuest() then return end
    local name = UnitName("questnpc")
    DeclineQuest()
    ns:Print(L["Quest shared by %s declined: not a friend, guild member or Battle.net friend."], name)
end

-- ------------------------------------------------------------ apply --

function World.Apply()
    local d = db()
    QoL.SyncEvent(d.gossipSingle, "GOSSIP_SHOW",          onGossipShow)
    QoL.SyncEvent(d.blockInvites, "PARTY_INVITE_REQUEST", onPartyInvite)
    QoL.SyncEvent(d.blockTrades,  "TRADE_SHOW",           onTradeShow)
    QoL.SyncEvent(d.blockDuels,   "DUEL_REQUESTED",       onDuelRequested)
    QoL.SyncEvent(d.inviteWhisper, "CHAT_MSG_WHISPER",    onWhisper)
    QoL.SyncEvent(d.inviteWhisper, "CHAT_MSG_BN_WHISPER", onBNWhisper)
    QoL.SyncEvent(d.blockFriendRequests, "BN_FRIEND_INVITE_ADDED",            declineFriendRequests)
    QoL.SyncEvent(d.blockFriendRequests, "BN_FRIEND_INVITE_LIST_INITIALIZED", declineFriendRequests)
    QoL.SyncEvent(d.blockSharedQuests, "QUEST_DETAIL",    onQuestDetail)
    -- switched on with requests already waiting: those go now, not on the next one
    if d.blockFriendRequests then declineFriendRequests() end
end

function World.Disable()
    QoL.SyncEvent(false, "GOSSIP_SHOW",          onGossipShow)
    QoL.SyncEvent(false, "PARTY_INVITE_REQUEST", onPartyInvite)
    QoL.SyncEvent(false, "TRADE_SHOW",           onTradeShow)
    QoL.SyncEvent(false, "DUEL_REQUESTED",       onDuelRequested)
    QoL.SyncEvent(false, "CHAT_MSG_WHISPER",     onWhisper)
    QoL.SyncEvent(false, "CHAT_MSG_BN_WHISPER",  onBNWhisper)
    QoL.SyncEvent(false, "BN_FRIEND_INVITE_ADDED",            declineFriendRequests)
    QoL.SyncEvent(false, "BN_FRIEND_INVITE_LIST_INITIALIZED", declineFriendRequests)
    QoL.SyncEvent(false, "QUEST_DETAIL",         onQuestDetail)
end
