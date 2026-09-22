-- VuloForeverUI / Modules / QoL / World
--
-- Two kinds of answer: one that saves a click at an NPC, and two that decide
-- who is allowed to interrupt you.
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

-- ------------------------------------------------------------ apply --

function World.Apply()
    local d = db()
    QoL.SyncEvent(d.gossipSingle, "GOSSIP_SHOW",          onGossipShow)
    QoL.SyncEvent(d.blockInvites, "PARTY_INVITE_REQUEST", onPartyInvite)
    QoL.SyncEvent(d.blockTrades,  "TRADE_SHOW",           onTradeShow)
end

function World.Disable()
    QoL.SyncEvent(false, "GOSSIP_SHOW",          onGossipShow)
    QoL.SyncEvent(false, "PARTY_INVITE_REQUEST", onPartyInvite)
    QoL.SyncEvent(false, "TRADE_SHOW",           onTradeShow)
end
