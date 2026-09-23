-- VuloForeverUI / Modules / QoL / Loot
--
-- Looting a corpse in one click, opening what can be opened, and typing the
-- delete word for you.
--
-- WHY AUTO-OPEN IS THE LONGEST PIECE OF CODE IN THIS MODULE
--
-- UseContainerItem is the same call the client uses for everything else you do
-- with an item, and it has three properties that make a naive loop lose items:
--
--   * the slot is locked optimistically, and only unlocked once the server
--     answers. A second use on a still-resolving slot strands it until relog.
--   * with a merchant open the same call SELLS the item instead of opening it
--   * while a cast is running it silently CANCELS the cast -- no error, no
--     message, just a lost mount or hearthstone
--
-- So there is exactly one open cycle at a time, every step re-checks the gates
-- rather than trusting the ones checked when the cycle began, and a container
-- that changes nothing after an open is written off for the session instead of
-- being retried forever.
--
-- Whether an item can be opened is read once per item id from its tooltip and
-- cached. A negative is only cached once the item data has actually arrived:
-- a brand new item has an empty tooltip for a moment, and that is not a "no".
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Loot = QoL.RegisterPart("loot", {})
QoL.Loot = Loot

local function carriedBags()
    if ns.Bags and ns.Bags.CarriedBags then return ns.Bags.CarriedBags() end
    local out = { 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) do out[#out + 1] = i end
    return out
end

-- ---------------------------------------------------------- quick loot --

-- Slots are taken one after another rather than in one burst: the server
-- answers each LootSlot separately, and a burst past its limit drops the tail.
-- Holding shift opens the window as usual, which is how you skip something.
local function onLootReady()
    if not QoL.db().quickLoot then return end
    if IsShiftKeyDown() then return end
    local step = QoL.db().quickLootDelay
    for i = 1, GetNumLootItems() do
        local index = i
        C_Timer.After(step * index, function() LootSlot(index) end)
    end
end

-- ------------------------------------------------------ auto containers --

local openable = {}       -- itemID -> true/false, "can this be opened"
local failed = {}         -- itemID -> true, written off for this session
local inProgress = {}     -- bag*1000+slot -> true while an open is resolving
local cacheBuilt = false
local busy = false        -- exactly one cycle at a time
local scanScheduled = false
local missedScan = false  -- a scan was asked for while busy, or while casting
local lootOpen = false
local cycleGen = 0
local pendingOpen, lootSource
local lastChurn = 0

local CHURN_WINDOW, CHURN_DELAY = 0.35, 0.4
local SLOTS_PER_FRAME = 3

local scanAndOpen, requestScan

local function slotKey(bag, slot) return bag * 1000 + slot end

local function openEnabled()
    return QoL.db().autoOpen == true
end

-- A merchant turns the open into a SELL, so nothing is opened while one is up.
local function merchantOpen()
    return (MerchantFrame and MerchantFrame:IsShown()) and true or false
end

-- Interaction state, not frame visibility: the mailbox and the bank hand out
-- items of their own, and that is what races us into a stranded slot.
local function interactingWith(kind)
    local M = C_PlayerInteractionManager
    if not (M and M.IsInteractingWithNpcOfType and Enum.PlayerInteractionType) then return false end
    local t = Enum.PlayerInteractionType[kind]
    return (t and M.IsInteractingWithNpcOfType(t)) and true or false
end

local function mailOpen() return interactingWith("MailInfo") end

local function bankOpen()
    return interactingWith("Banker") or interactingWith("AccountBanker")
end

local function playerIsCasting()
    -- type(), not ~= nil: the cast name can be secret
    return (UnitCastingInfo and type(UnitCastingInfo("player")) ~= "nil")
        or (UnitChannelInfo and type(UnitChannelInfo("player")) ~= "nil")
end

local function isOpenable(itemID, bag, slot)
    local cached = openable[itemID]
    if cached ~= nil then return cached end

    local tip = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    if tip and tip.lines then
        for _, line in ipairs(tip.lines) do
            if line and line.leftText == ITEM_OPENABLE then
                openable[itemID] = true
                return true
            end
        end
    end
    -- An empty tooltip can simply mean the item data has not arrived yet, so a
    -- negative is only written down once the data is actually in. Otherwise the
    -- first sighting of a new container would mark it unopenable for good.
    if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
        return false
    end
    openable[itemID] = false
    return false
end

-- Warming the cache walks every slot, which is why it happens a few slots per
-- frame and then hides itself: a hidden frame runs no OnUpdate at all.
local scanBagIndex, scanSlot = 1, 1
local scanFrame = CreateFrame("Frame")
scanFrame:Hide()
scanFrame:SetScript("OnUpdate", function(self)
    if not openEnabled() then self:Hide(); return end
    local bags = carriedBags()
    local checked = 0
    while checked < SLOTS_PER_FRAME do
        local bag = bags[scanBagIndex]
        if not bag then
            cacheBuilt = true
            self:Hide()
            if scanAndOpen then scanAndOpen() end
            return
        end
        if scanSlot > (C_Container.GetContainerNumSlots(bag) or 0) then
            scanBagIndex, scanSlot = scanBagIndex + 1, 1
        else
            local info = C_Container.GetContainerItemInfo(bag, scanSlot)
            if info and info.itemID then
                -- Warmed here so the open cycle never scans a tooltip on its
                -- own hot path.
                isOpenable(info.itemID, bag, scanSlot)
            end
            scanSlot = scanSlot + 1
            checked = checked + 1
        end
    end
end)

scanAndOpen = function(skipMerchantGate)
    if not (cacheBuilt and openEnabled()) then return end
    if InCombatLockdown() then return end
    if not skipMerchantGate and merchantOpen() then return end
    if mailOpen() or bankOpen() then return end
    -- A cast is transient, so this defers rather than gives up; the spellcast
    -- events below bring the cycle back.
    if playerIsCasting() then missedScan = true; return end
    if lootOpen then return end
    -- A running cycle picks this trigger up in its own finish().
    if busy then missedScan = true; return end

    local toOpen = {}
    for _, bag in ipairs(carriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if openable[info.itemID] == nil then isOpenable(info.itemID, bag, slot) end
                if openable[info.itemID] and not failed[info.itemID] then
                    toOpen[#toOpen + 1] = { bag = bag, slot = slot }
                end
            end
        end
    end
    if #toOpen == 0 then return end

    busy = true
    cycleGen = cycleGen + 1
    local myGen = cycleGen
    local progressed = false

    -- The only place busy is cleared, and every exit routes through it: a leak
    -- here would freeze auto-open until the next reload. A cycle that has been
    -- replaced must NOT clear it -- the flag belongs to its successor.
    local function finish()
        if myGen ~= cycleGen then return end
        busy = false
        if (progressed or missedScan) and openEnabled() and not InCombatLockdown()
            and not merchantOpen() and not mailOpen() and not bankOpen() and not lootOpen then
            missedScan = false
            -- Containers hold containers, so the cycle re-scans itself once
            -- anything actually moved.
            C_Timer.After(0.3, function() scanAndOpen() end)
        end
    end

    local step, paceNext

    step = function(idx)
        if myGen ~= cycleGen then return end
        if idx > #toOpen then return finish() end
        if not openEnabled() or InCombatLockdown() or merchantOpen()
            or mailOpen() or bankOpen() or lootOpen then
            return finish()
        end
        -- Re-checked per step: a cycle paces itself across seconds, so a cast
        -- can start long after the gate at the top was passed.
        if playerIsCasting() then missedScan = true; return finish() end

        local item = toOpen[idx]
        local key = slotKey(item.bag, item.slot)
        local info = C_Container.GetContainerItemInfo(item.bag, item.slot)
        -- Never act on a slot that is mid-action, ours or the client's:
        -- re-using a still-resolving container is what strands it.
        if info and info.itemID and not info.isLocked and not inProgress[key]
            and openable[info.itemID] and not failed[info.itemID] then
            local prevID = info.itemID
            local prevCount = info.stackCount or 1
            inProgress[key] = true
            pendingOpen = { bag = item.bag, slot = item.slot, itemID = prevID, count = prevCount }
            C_Container.UseContainerItem(item.bag, item.slot)
            C_Timer.After(0.5, function()
                -- The slot flag is always released; a superseded cycle stops
                -- here, since its verdict would race its successor.
                inProgress[key] = nil
                if pendingOpen and pendingOpen.bag == item.bag and pendingOpen.slot == item.slot then
                    pendingOpen = nil
                end
                if myGen ~= cycleGen then return end
                local after = C_Container.GetContainerItemInfo(item.bag, item.slot)
                local moved = (not after) or after.itemID ~= prevID
                    or (after.stackCount or 1) < prevCount
                if moved then
                    progressed = true
                elseif after and not after.isLocked and not lootOpen then
                    -- Unchanged, unlocked, no loot window: a genuine refusal. A
                    -- still-locked slot is only slow, so it keeps its chance.
                    failed[prevID] = true
                end
                paceNext(idx + 1)
            end)
            return
        end
        C_Timer.After(0.1, function() step(idx + 1) end)
    end

    -- Paces the step AFTER a real open resolved: when something else has just
    -- touched the bags, let it settle first rather than racing it.
    paceNext = function(idx)
        if myGen ~= cycleGen then return end
        if GetTime() - lastChurn < CHURN_WINDOW then
            C_Timer.After(CHURN_DELAY, function() step(idx) end)
        else
            step(idx)
        end
    end

    C_Timer.After(0.15, function() step(1) end)
end

-- One open fires several bag updates; they collapse into a single next-frame
-- scan rather than a scan each.
requestScan = function()
    if busy then missedScan = true; return end
    if scanScheduled then return end
    scanScheduled = true
    ns.NextFrame(function()
        scanScheduled = false
        scanAndOpen()
    end)
end

local function onBagUpdate()
    -- The raw per-slot event is used for nothing but the timestamp the pacing
    -- above reads; the coalesced one is far too coarse for that.
    lastChurn = GetTime()
end

local function onBagUpdateDelayed() requestScan() end

local function onLootOpened()
    lootOpen = true
    -- Claim the window for the container just used, so its verdict can be
    -- taken when the window closes again.
    lootSource = pendingOpen
    pendingOpen = nil
end

local function onLootClosed()
    lootOpen = false
    C_Timer.After(0.5, function()
        local src = lootSource
        lootSource = nil
        if src then
            local now = C_Container.GetContainerItemInfo(src.bag, src.slot)
            -- Still there with the same count: it could not be looted (full
            -- bags, a unique cap). Written off BEFORE the re-scan, or the
            -- cycle would try it forever.
            if now and now.itemID == src.itemID and not now.isLocked
                and (now.stackCount or 1) >= src.count then
                failed[src.itemID] = true
            end
        end
        scanAndOpen()
    end)
end

local function onMerchantClosed()
    -- The interaction is over, but the frame may not have hidden yet -- so the
    -- entry gate is skipped for this one run rather than waiting on a timer.
    scanAndOpen(true)
end

local function onInteractionEnded()
    C_Timer.After(0.5, function() scanAndOpen() end)
end

local function onCastEnded()
    -- Only resume when the casting gate actually deferred something: these
    -- fire on every instant cast too, and walking the bags each time would be
    -- constant work for nothing.
    if missedScan and not busy then
        missedScan = false
        C_Timer.After(0.1, function() scanAndOpen() end)
    end
end

local OPEN_EVENTS = {
    BAG_UPDATE = onBagUpdate,
    BAG_UPDATE_DELAYED = onBagUpdateDelayed,
    LOOT_OPENED = onLootOpened,
    LOOT_CLOSED = onLootClosed,
    MERCHANT_CLOSED = onMerchantClosed,
    PLAYER_INTERACTION_MANAGER_FRAME_HIDE = onInteractionEnded,
    UNIT_SPELLCAST_SUCCEEDED = onCastEnded,
    UNIT_SPELLCAST_STOP = onCastEnded,
    UNIT_SPELLCAST_CHANNEL_STOP = onCastEnded,
}

-- ------------------------------------------------------- delete dialog --

-- The confirmation is the client's own popup; only its edit box is filled, and
-- the button is still yours to press.
local deleteHooked = false
local function hookDeletePopups()
    if deleteHooked then return end
    deleteHooked = true
    for i = 1, 4 do
        local popup = _G["StaticPopup" .. i]
        if popup then
            hooksecurefunc(popup, "Show", function(self)
                if not QoL.db().autoFillDelete then return end
                if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then return end
                local edit = self.editBox or (self.GetEditBox and self:GetEditBox())
                if not edit then return end
                edit:SetText(DELETE_ITEM_CONFIRM_STRING)
                edit:SetFocus()
            end)
        end
    end
end

-- ----------------------------------------------------------- lifecycle --

function Loot.Apply()
    local db = QoL.db()

    QoL.SyncEvent(db.quickLoot and true or false, "LOOT_READY", onLootReady)

    local openOn = openEnabled()
    for ev, handler in pairs(OPEN_EVENTS) do
        QoL.SyncEvent(openOn, ev, handler)
    end
    if openOn then
        if not cacheBuilt then
            scanBagIndex, scanSlot = 1, 1
            scanFrame:Show()
        else
            requestScan()
        end
    else
        scanFrame:Hide()
        -- A cycle cut off mid-flight would otherwise leave busy set for good;
        -- the generation bump kills its timers, so a quick re-enable cannot
        -- resurrect the old chain beside the new one.
        busy, scanScheduled, missedScan = false, false, false
        lootOpen, pendingOpen, lootSource = false, nil, nil
        cycleGen = cycleGen + 1
    end

    -- hooksecurefunc cannot be undone, so the hook is installed on first use
    -- and its body reads the setting live.
    if db.autoFillDelete then hookDeletePopups() end
end

function Loot.Disable()
    ns:UnregisterEvent("LOOT_READY", onLootReady)
    for ev, handler in pairs(OPEN_EVENTS) do
        ns:UnregisterEvent(ev, handler)
    end
    scanFrame:Hide()
    busy, scanScheduled, missedScan = false, false, false
    lootOpen, pendingOpen, lootSource = false, nil, nil
    cycleGen = cycleGen + 1
end

-- Debug aid: what the tooltip scan believes about the bags right now.
function Loot.CacheStatus()
    local yes, no = 0, 0
    for _, v in pairs(openable) do
        if v then yes = yes + 1 else no = no + 1 end
    end
    return cacheBuilt, yes, no
end
