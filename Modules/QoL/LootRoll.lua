-- VuloForeverUI / Modules / QoL / LootRoll
--
-- The group loot rolls as one compact list (F-81). This file is the data:
-- which rolls are open, what the player chose, and what the loot history
-- says about everybody else. The rows themselves are LootRollList.lua.
--
-- TAKING THE CLIENT'S POPUPS OUT WITHOUT TOUCHING A FRAME
--
-- The client opens its roll windows from one internal handler: START_LOOT_ROLL
-- goes through GameEvent (EventRouting.lua) to GameEvent.HandleStartLootRoll,
-- which calls GroupLootContainer_AddRoll. The part takes that ONE handler out
-- with GameEvent.UnregisterInternalEvent. No client frame is hidden, moved or
-- re-parented: Hide on a client frame runs its OnHide in our taint
-- (concepts.md, engine rules).
--
-- It is NEVER put back from here. A handler registered by addon code -- or a
-- direct GroupLootContainer_AddRoll -- runs the client's container and with it
-- the bottom managed frame container's Layout in our taint, and in combat that
-- is ADDON_ACTION_BLOCKED (the extra action button lives there). So switching
-- the part off after it took the handler keeps the list working until a
-- reload and offers one; only a reload gives the client its windows back.
-- With the gamepad UI on, the client's gamepad roll frame takes the event
-- itself; the part then stays out of the way entirely.
--
-- Known gap: on PLAYER_ENTERING_WORLD the client re-reads every active roll
-- into its own windows (GroupLootContainer_RefreshRolls). A roll that is still
-- open across a loading screen then shows in both places.
--
-- COUNTS, PLAYERS, WINNER
--
-- The roll API says nothing about the others. C_LootHistory does: every drop
-- with its rolls, found by item link. A drop is matched to a roll once and the
-- pair (encounterID, lootListKey) kept on the roll -- only while exactly ONE
-- row has that item link: with the same item twice nothing tells the drops
-- apart, so such rows stay without counts, players and winner. Rolling never
-- depends on that match; the buttons work all the same.
--
-- CANCEL_LOOT_ROLL can come right after the player's own click, long before
-- the others are done. A matched row therefore stays (buttons off, counts
-- live) until the drop has a winner or everyone passed, then shows the result
-- for LINGER seconds; an unmatched row lingers from the CANCEL on.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local LR = QoL.RegisterPart("lootRoll", {})
QoL.LootRoll = LR

-- Roll types as RollOnLoot takes them.
LR.PASS, LR.NEED, LR.GREED, LR.DISENCHANT, LR.TRANSMOG = 0, 1, 2, 3, 4

-- The rows, in the order the rolls came. Never reassigned: the list file
-- reads it through LR.
LR.rolls = {}
local rolls = LR.rolls

local LINGER    = 8     -- seconds a finished roll stays with its result

local CAP       = 10    -- seconds past the roll's end a closed row waits for the result
local ZERO_WAIT = 3     -- seconds at 0:00 without a CANCEL before a row is closed

local active, suppressed, confirmHooked = false, false, false
local wanted = false    -- the switch is on (and the gamepad UI is not)

local function db() return QoL.db().lootRoll end
LR.db = db

function LR.IsActive() return active end

-- A flag from the client, false when it cannot be read.
local function flag(v)
    return (ns.CanRead(v) and v) and true or false
end

-- EncounterLootDropRollState -> the button it belongs to. Greed and transmog
-- share one place: only one of the two buttons is ever shown.
--   0 NeedMainSpec, 1 NeedOffSpec, 2 Transmog, 3 Greed, 4 NoRoll, 5 Pass
local SLOT = { [0] = 1, [1] = 1, [2] = 2, [3] = 2, [5] = 0 }
-- ... and the roll type it means, for the player's own choice.
local STATE_TYPE = { [0] = 1, [1] = 1, [2] = 4, [3] = 2, [5] = 0 }

function LR.SlotOfState(state)
    local s = ns.Num(state)
    return s and SLOT[s] or nil
end

-- The count slot a button shows.
function LR.SlotOfType(t)
    if t == LR.NEED then return 1 end
    if t == LR.GREED or t == LR.TRANSMOG then return 2 end
    if t == LR.PASS then return 0 end
    return nil
end

local function find(id)
    for i, r in ipairs(rolls) do
        if r.id == id then return r, i end
    end
    return nil
end

-- ------------------------------------------------------------- item --

local function readItem(r)
    if type(GetLootRollItemInfo) ~= "function" then return false end
    local texture, name, count, quality, bop, canNeed, canGreed, canDE,
          reasonNeed, reasonGreed, _, _, canTransmog = GetLootRollItemInfo(r.id)
    if type(name) ~= "string" then return false end
    r.texture, r.name = texture, name
    r.count   = ns.Num(count, 1)
    r.quality = ns.Num(quality, 1)
    r.bop     = flag(bop)
    r.canNeed, r.canGreed, r.canDE = flag(canNeed), flag(canGreed), flag(canDE)
    r.canTransmog = flag(canTransmog)
    r.reasonNeed, r.reasonGreed = ns.Num(reasonNeed), ns.Num(reasonGreed)
    local link = GetLootRollItemLink and GetLootRollItemLink(r.id)
    if type(link) == "string" and ns.CanRead(link) then r.link = link end
    return true
end

-- "BoE": binds when equipped. The item may not be in the cache yet; then it
-- is read again when the client says it arrived.
local waitingInfo = false
local onItemInfo

local function readBind(r)
    if r.boe ~= nil then return true end
    if r.bop or not r.link then r.boe = false; return true end
    local bindType = select(14, C_Item.GetItemInfo(r.link))
    if type(bindType) ~= "number" then return false end
    r.boe = (ns.CanRead(bindType) and bindType == 2) and true or false
    return true
end

local function readBinds()
    local missing = false
    for _, r in ipairs(rolls) do
        if not r.test and not readBind(r) then missing = true end
    end
    if missing ~= waitingInfo then
        waitingInfo = missing
        QoL.SyncEvent(missing, "GET_ITEM_INFO_RECEIVED", onItemInfo)
    end
end

function onItemInfo()
    readBinds()
    LR.Layout()
end

function LR.QualityColor(q)
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q or 1)
        if type(r) == "number" then return r, g, b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 1]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Milliseconds left on a running roll. A closed roll (the player is done)
-- runs on our own clock: the client no longer answers for it.
function LR.TimeLeft(r)
    if r.test then return math.max(0, (r.endsAt - GetTime()) * 1000) end
    if r.closed then
        return math.max(0, (r.startedAt + r.duration / 1000 - GetTime()) * 1000)
    end
    return ns.Num(GetLootRollTimeLeft and GetLootRollTimeLeft(r.id), 0)
end

-- Another real row with the same item: then no drop of the history can be
-- told apart, and the row shows nothing from it.
local function duplicate(r)
    if not r.link then return false end
    for _, o in ipairs(rolls) do
        if o ~= r and not o.test and o.link == r.link then return true end
    end
    return false
end

local function finishedDrop(info)
    return type(info) == "table" and (flag(info.allPassed) or type(info.winner) == "table")
end

-- The history entry of a row, nil when there is none or it cannot be trusted.
function LR.Info(r)
    if r.test then return r.info end
    if type(r.info) ~= "table" or duplicate(r) then return nil end
    return r.info
end

-- ---------------------------------------------------------- history --

local function claimedBy(e, k)
    for _, r in ipairs(rolls) do
        if r.encounterID == e and r.lootListKey == k then return r end
    end
    return nil
end

-- One drop of the loot history onto the roll it belongs to. fresh: the
-- client just reported this drop changing, so a finished drop may still be
-- ours (the result arrives after the roll closed). A scan only takes open
-- drops: an old drop of the same item is long finished.
local function useDrop(e, info, fresh)
    if type(info) ~= "table" then return nil end
    local k = ns.Num(info.lootListKey)
    if not k then return nil end
    local r = claimedBy(e, k)
    if not r then
        local link = info.itemHyperlink
        if type(link) ~= "string" or not ns.CanRead(link) then return nil end
        if finishedDrop(info) and not fresh then return nil end
        -- exactly one row with this item, or none is matched at all
        local n = 0
        for _, cand in ipairs(rolls) do
            if not cand.test and cand.link == link then
                n = n + 1
                if not cand.encounterID and (fresh or not cand.doneAt) then r = cand end
            end
        end
        if n ~= 1 or not r then return nil end
        r.encounterID, r.lootListKey = e, k
    end
    r.info = info
    if duplicate(r) then return r end
    -- closed and waiting for the result: it is there now
    if r.closed and not r.doneAt and finishedDrop(info) then r.doneAt = GetTime() end
    if r.choice == nil then
        local s = ns.Num(info.playerRollState)
        local t = s and STATE_TYPE[s]
        if t then r.choice, r.pending = t, nil end
    end
    return r
end

local function history() return C_LootHistory end

local function scanEncounter(e, fresh)
    local H = history()
    if not (H and H.GetSortedDropsForEncounter) then return end
    local ok, drops = pcall(H.GetSortedDropsForEncounter, e)
    if not ok or type(drops) ~= "table" then return end
    for _, info in ipairs(drops) do useDrop(e, info, fresh) end
end

-- Every roll against the whole history: at a new roll and at its end.
local function scanAll()
    local H = history()
    if not (H and H.GetAllEncounterInfos) then return end
    local any = false
    for _, r in ipairs(rolls) do
        if not r.test then any = true; break end
    end
    if not any then return end
    local ok, encounters = pcall(H.GetAllEncounterInfos)
    if not ok or type(encounters) ~= "table" then return end
    for _, enc in ipairs(encounters) do
        local e = type(enc) == "table" and ns.Num(enc.encounterID)
        if e then scanEncounter(e, false) end
    end
end

-- The players of a roll: EncounterLootDropRollInfo, as the history has them.
function LR.Players(r)
    local info = LR.Info(r)
    if not info or type(info.rollInfos) ~= "table" then return nil end
    return info.rollInfos
end

-- How many picked each button: [0] pass, [1] need, [2] greed/transmog.
function LR.Counts(r)
    local players = LR.Players(r)
    if not players then return nil end
    local c = { [0] = 0, [1] = 0, [2] = 0 }
    for _, p in ipairs(players) do
        local s = LR.SlotOfState(p.state)
        if s then c[s] = c[s] + 1 end
    end
    return c
end

-- A name we may show, without the realm of somebody from ours.
function LR.Name(name)
    if type(name) ~= "string" or not ns.CanRead(name) then return "?" end
    if Ambiguate then return Ambiguate(name, "short") end
    return name
end

-- The text in a finished roll's bar, and whether somebody won.
function LR.ResultText(r)
    local info = LR.Info(r)
    if info then
        local w = info.winner
        if type(w) == "table" then
            local roll = ns.Num(w.roll)
            local mark = CreateAtlasMarkup and CreateAtlasMarkup("lootroll-icon-checkmark", 0, 0) or ""
            local text = mark .. " " .. LR.Name(w.playerName)
            if roll then text = text .. " " .. roll end
            return text, true
        end
        if flag(info.allPassed) then return L["Everyone passed"], false end
    end
    return L["Roll ended"], false
end

-- ------------------------------------------------------------ rolls --

local addRoll

local function retry(id, rollTime, tries)
    if tries >= 3 then return end
    C_Timer.After(0.5, function()
        if active and not find(id) then addRoll(id, rollTime, tries + 1) end
    end)
end

function addRoll(id, rollTime, tries)
    if type(id) ~= "number" or not ns.CanRead(id) or find(id) then return end
    local r = { id = id }
    -- The item can be a moment late at the very start; the client's own
    -- window gives up on it, we ask again a few times.
    if not readItem(r) then retry(id, rollTime, tries or 0); return end
    LR.DropTests()
    local dur = C_Loot and C_Loot.GetLootRollDuration and ns.Num(C_Loot.GetLootRollDuration(id))
    if not dur or dur <= 0 then dur = ns.Num(rollTime) end
    if not dur or dur <= 0 then dur = math.max(LR.TimeLeft(r), 1) end
    r.duration = dur
    r.startedAt = GetTime() - math.max(0, dur - LR.TimeLeft(r)) / 1000
    rolls[#rolls + 1] = r
    readBinds()
    scanAll()
    LR.Layout()
end

-- A roll the client's own windows already show stays there: switching on
-- mid-roll leaves it.
local function clientShows(id)
    for i = 1, 4 do
        local f = _G["GroupLootFrame" .. i]
        if f and f:IsShown() and f.rollID == id then return true end
    end
    local c = _G.GroupLootContainer
    local waiting = c and c.waitingRolls
    if type(waiting) == "table" then
        for _, w in ipairs(waiting) do
            if type(w) == "table" and w.rollID == id then return true end
        end
    end
    return false
end

local function activeIDs()
    if type(GetActiveLootRollIDs) ~= "function" then return {} end
    local ids = GetActiveLootRollIDs()
    return type(ids) == "table" and ids or {}
end

-- The player is done with a roll: no more buttons. A matched row waits for
-- the history's result; any other shows its end at once. now: show the end
-- right away (the roll is gone from the client).
local function close(r, now)
    if r.doneAt then return end
    r.closed = true
    if now or not r.encounterID or duplicate(r) or finishedDrop(r.info) then
        r.doneAt = GetTime()
    end
end

local function rehydrate()
    local ids = activeIDs()
    local open = {}
    for _, id in ipairs(ids) do open[id] = true end
    -- rows the client no longer knows (a loading screen ate the CANCEL)
    for _, r in ipairs(rolls) do
        if not r.test and not r.closed and not open[r.id] then close(r, true) end
    end
    for _, id in ipairs(ids) do
        if not clientShows(id) then addRoll(id) end
    end
end

-- A closed row whose result never came: past the end of the drop (history
-- clock) or of the roll (ours), plus CAP seconds.
local function overdue(r, now)
    if now > r.startedAt + r.duration / 1000 + CAP then return true end
    local info, H = r.info, C_LootHistory
    if type(info) == "table" and H and H.GetLootHistoryTime then
        local start, dur = ns.Num(info.startTime), ns.Num(info.duration)
        local t = ns.Num(H.GetLootHistoryTime())
        if start and dur and t and t > start + dur + CAP then return true end
    end
    return false
end

-- Finished rows that have shown their result long enough. Called from the
-- list's ticker; true when a row went.
function LR.Expire()
    local now, changed = GetTime(), false
    for i = #rolls, 1, -1 do
        local r = rolls[i]
        if not r.test and not r.closed then
            -- at 0:00 and no CANCEL: closed after a moment
            if LR.TimeLeft(r) <= 0 then
                r.zeroSince = r.zeroSince or now
                if now - r.zeroSince > ZERO_WAIT then close(r); changed = true end
            else
                r.zeroSince = nil
            end
        elseif not r.test and not r.doneAt and overdue(r, now) then
            r.doneAt = now
            changed = true
        end
        if r.doneAt and not r.test and now - r.doneAt > LINGER then
            table.remove(rolls, i)
            changed = true
        end
    end
    if changed then readBinds() end
    return changed
end

-- A click on a button. A bind-on-pickup item asks first (the client's
-- CONFIRM_LOOT_ROLL popup); the choice counts once it is confirmed.
function LR.Roll(r, rollType)
    if r.test or r.closed or r.doneAt or r.choice ~= nil or type(r.id) ~= "number" then return end
    if type(RollOnLoot) ~= "function" then return end
    if r.bop and rollType ~= LR.PASS then
        r.pending = rollType
    else
        r.choice = rollType
    end
    RollOnLoot(r.id, rollType)
    LR.Layout()
end

-- ----------------------------------------------------------- events --

local function onStart(_, id, rollTime)
    addRoll(id, rollTime)
end

local function onCancel(_, id)
    local r = find(id)
    if not r or r.closed then return end
    scanAll()
    close(r)
    LR.Layout()
end

local function onCancelAll()
    for i = #rolls, 1, -1 do
        if not rolls[i].test then table.remove(rolls, i) end
    end
    readBinds()
    LR.Layout()
end

local function onDrop(_, e, k)
    local H = history()
    e, k = ns.Num(e), ns.Num(k)
    if not (H and H.GetSortedInfoForDrop and e and k) then return end
    local ok, info = pcall(H.GetSortedInfoForDrop, e, k)
    if ok and useDrop(e, info, true) then LR.Layout() end
end

local function onEncounter(_, e)
    e = ns.Num(e)
    if not e then return end
    scanEncounter(e, false)
    LR.Layout()
end

local function onNeedRoll()
    scanAll()
    LR.Layout()
end

local function onWorld()
    rehydrate()
end

local EVENTS = {
    START_LOOT_ROLL               = onStart,
    CANCEL_LOOT_ROLL              = onCancel,
    CANCEL_ALL_LOOT_ROLLS         = onCancelAll,
    MAIN_SPEC_NEED_ROLL           = onNeedRoll,
    LOOT_HISTORY_UPDATE_DROP      = onDrop,
    LOOT_HISTORY_UPDATE_ENCOUNTER = onEncounter,
    PLAYER_ENTERING_WORLD         = onWorld,
}

local function syncEvents(on)
    for event, fn in pairs(EVENTS) do QoL.SyncEvent(on, event, fn) end
end

-- The confirmed bind-on-pickup roll: the client's popup calls ConfirmLootRoll.
local function hookConfirm()
    if confirmHooked or type(ConfirmLootRoll) ~= "function" then return end
    confirmHooked = true
    hooksecurefunc("ConfirmLootRoll", function(id, rollType)
        if not active then return end
        local r = find(id)
        if r and r.choice == nil then
            r.choice, r.pending = ns.Num(rollType, r.pending), nil
            LR.Layout()
        end
    end)
end

-- ---------------------------------------------- the client's popups --

local function gameEvent()
    local g = _G.GameEvent
    return type(g) == "table" and g or nil
end

local function suppress()
    if suppressed then return end
    local g = gameEvent()
    if g and type(g.UnregisterInternalEvent) == "function" then
        g.UnregisterInternalEvent("START_LOOT_ROLL")
        suppressed = true
    end
end

-- The gamepad UI has its own roll frame, which takes START_LOOT_ROLL itself.
local function gamepadUI()
    local iu = _G.InputUtil
    if type(iu) ~= "table" or type(iu.IsGamepadUIEnabled) ~= "function" then return false end
    return iu.IsGamepadUIEnabled() and true or false
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_LOOTROLL_RELOAD"] = {
    text = L["The game's roll windows come back after a reload. Reload now?"],
    button1 = L["Reload now"],
    button2 = L["Later"],
    OnAccept = function() ReloadUI() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
end)

-- ------------------------------------------------------------ apply --

function LR.Apply()
    -- the gamepad UI is the client's alone, unless we already took the handler
    if not db().enabled or (gamepadUI() and not suppressed) then LR.Disable(); return end
    wanted = true
    if not active then
        active = true
        syncEvents(true)
        hookConfirm()
        suppress()
        rehydrate()
    end
    LR.Style()
end

-- Off. Once the client's handler is out, nothing of ours may put it back
-- (see the top of the file): the list keeps answering rolls until a reload,
-- and the switch-off offers that reload.
function LR.Disable()
    if suppressed then
        if wanted then
            wanted = false
            if StaticPopup_Show then StaticPopup_Show("VFUI_LOOTROLL_RELOAD") end
        end
        return
    end
    wanted = false
    if active then
        active = false
        syncEvents(false)
    end
    wipe(rolls)
    LR.DropTests()
    if waitingInfo then
        waitingInfo = false
        QoL.SyncEvent(false, "GET_ITEM_INFO_RECEIVED", onItemInfo)
    end
    if LR.HideList then LR.HideList() end
end
