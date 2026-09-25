-- VuloForeverUI / Modules / QoL / Trinkets
--
-- Two trinket slots on screen, with their cooldowns, a pick-list on right
-- click, and an auto-queue per slot that puts the next trinket on as soon as
-- the one in the slot is spent.
--
-- WHAT A CLICK IS
--
-- Using a trinket is a protected action, so each slot is a SECURE button that
-- runs "/use 13" or "/use 14" -- that is what works in a fight.
-- The button draws nothing. What you see is a plain frame of ours under it:
-- icon, cooldown swipe, queue mark. Cooldown:SetCooldown is protected on this
-- client for protected frames, and a swipe on the secure button itself would
-- freeze for the whole fight; on our own frame it keeps running.
--
-- Right click and alt-click are no secure action at all (their types point at
-- nothing), and a hook on the button handles them: the pick-list, and the
-- queue switch for that slot.
--
-- WHAT IS NOT POSSIBLE IN A FIGHT
--
-- Equipping an item is refused in combat. The pick-list says so instead of
-- pretending, and the queue simply waits: it runs once a second out of
-- combat, and once more the moment a fight ends.
--
-- THE QUEUE, per slot, as the list in the options orders it
--
-- "Ready" is a cooldown that is over or has at most 30 seconds left -- the
-- equip cooldown a freshly put-on trinket gets. When the trinket in the slot
-- is ready and has a use, it stays. When it is spent (or passive), the first
-- ready trinket above the stop marker that is in the bags goes on. A trinket
-- that was used in the last 20 seconds is left alone so its effect is not cut
-- short, and nothing is swapped while casting or while the slot is locked.
--
-- The lists are per CHARACTER (VuloForeverUICharDB): they name items that one
-- character carries. The window's look is in the profile.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Trinkets = QoL.RegisterPart("trinkets", {})
QoL.Trinkets = Trinkets

local SLOTS = { { key = "top", inv = 13 }, { key = "bottom", inv = 14 } }
local STOP = 0              -- the stop marker's id in a queue list
local READY_LEFT = 30       -- seconds of cooldown that still count as ready
local USE_GRACE = 20        -- seconds after a use in which the slot is left alone
local SIZE = 36

local holder, buttons, ticker, pending

local function db() return QoL.db().trinkets end

-- ---------------------------------------------------------------- queue data --

function Trinkets.Queue(key)
    local c = _G.VuloForeverUICharDB
    if type(c) ~= "table" then return { enabled = false, list = { STOP } } end
    c.trinketQueue = type(c.trinketQueue) == "table" and c.trinketQueue or {}
    local q = c.trinketQueue[key]
    if type(q) ~= "table" then q = { enabled = false, list = { STOP } }; c.trinketQueue[key] = q end
    if type(q.list) ~= "table" then q.list = { STOP } end
    local hasStop = false
    for _, id in ipairs(q.list) do if id == STOP then hasStop = true end end
    if not hasStop then q.list[#q.list + 1] = STOP end
    return q
end

-- ---------------------------------------------------------------- items --

local function isTrinket(id)
    local t = C_Item.GetItemInventoryTypeByID(id)
    local want = Enum.InventoryType and Enum.InventoryType.IndexTrinketType or 12
    return t == want
end

function Trinkets.ItemName(id)
    if id == STOP then return L["-- no swapping from here on --"] end
    local name = C_Item.GetItemNameByID(id)
    if not name then
        C_Item.RequestLoadItemDataByID(id)
        return "#" .. id
    end
    return name
end

function Trinkets.ItemIcon(id)
    if id == STOP then return "Interface\\Buttons\\UI-GroupLoot-Pass-Up" end
    return C_Item.GetItemIconByID(id)
end

-- Every trinket the character has: the two worn ones and the bags.
function Trinkets.Owned()
    local out, seen = {}, {}
    local function add(id)
        if id and not seen[id] and isTrinket(id) then seen[id] = true; out[#out + 1] = id end
    end
    add(GetInventoryItemID("player", 13))
    add(GetInventoryItemID("player", 14))
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            add(C_Container.GetContainerItemID(bag, slot))
        end
    end
    return out
end

local function inBags(id)
    return (C_Item.GetItemCount(id) or 0) > 0 and not C_Item.IsEquippedItem(id)
end

local function num(v) return ns.CanRead(v) and type(v) == "number" and v or nil end

-- Seconds of cooldown left on an item, from the plain (out-of-combat) numbers.
local function itemLeft(id)
    local start, dur = C_Container.GetItemCooldown(id)
    start, dur = num(start), num(dur)
    if not (start and dur) or start == 0 then return 0 end
    return math.max(0, dur - (GetTime() - start))
end

local function equip(id, inv)
    if InCombatLockdown() then
        ns:Print(L["Trinkets can only be changed out of combat."])
        return
    end
    C_Item.EquipItemByName(id, inv)
end

-- ---------------------------------------------------------------- the queue --

local function busy()
    if InCombatLockdown() or UnitIsDeadOrGhost("player") or CursorHasItem() then return true end
    local cast = UnitCastingInfo("player")
    local chan = UnitChannelInfo("player")
    return (ns.CanRead(cast) and cast ~= nil) or (ns.CanRead(chan) and chan ~= nil)
end

local function runQueue(key, inv)
    local q = Trinkets.Queue(key)
    if not q.enabled then return end
    if IsInventoryItemLocked(inv) then return end
    local current = GetInventoryItemID("player", inv)
    if not current then return end

    local start, dur = GetInventoryItemCooldown("player", inv)
    start, dur = num(start), num(dur)
    if not (start and dur) then return end
    local left = (start > 0) and math.max(0, dur - (GetTime() - start)) or 0
    -- just used: its effect may still be running
    if start > 0 and dur > READY_LEFT and (GetTime() - start) < USE_GRACE then return end

    local ready = left <= READY_LEFT
    -- "has a use" is the item's own spell: the enable flag may come as a
    -- number or a boolean, and a passive trinket answers nil here
    local usable = C_Item.GetItemSpell(current) ~= nil

    -- how far down the list may look: to the stop marker, or -- when the
    -- worn trinket is ready and listed -- to the worn trinket itself
    local list, rank = q.list, nil
    for i, id in ipairs(list) do
        if id == STOP then rank = i; break end
        if ready and id == current then rank = i; break end
    end
    if not rank then return end
    if ready and usable then return end            -- a usable one that is ready stays

    for i = 1, rank do
        local id = list[i]
        if id ~= STOP and id ~= current and inBags(id) and itemLeft(id) <= READY_LEFT then
            equip(id, inv)
            return true
        end
    end
end

-- One swap per tick. The server confirms a swap a moment later; until then
-- the item still counts as "in the bags", and both slots wanting the same
-- trinket in one pass sent it to two slots at once.
local function tickQueue()
    if busy() then return end
    for _, s in ipairs(SLOTS) do
        if runQueue(s.key, s.inv) then return end
    end
end

local function anyQueue()
    for _, s in ipairs(SLOTS) do
        if Trinkets.Queue(s.key).enabled then return true end
    end
    return false
end

local function syncTicker()
    local want = QoL.mod.active and db().enabled and anyQueue()
    if want and not ticker then
        ticker = ns:AddTicker(1, tickQueue, nil, "qol.trinkets")
    elseif not want and ticker then
        ns:CancelTicker(ticker)
        ticker = nil
    end
end

-- ---------------------------------------------------------------- display --

local function paintSlot(b)
    local inv = b.inv
    local tex = GetInventoryItemTexture("player", inv)
    b.icon:SetTexture(tex or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket")
    b.icon:SetDesaturated(tex == nil)
    local start, dur = GetInventoryItemCooldown("player", inv)
    -- handed on as they come: in a fight they may be secret, so nil is tested
    -- by TYPE -- `start or 0` would be a boolean test on a secret, which throws
    if type(start) == "nil" then start = 0 end
    if type(dur) == "nil" then dur = 0 end
    pcall(b.cd.SetCooldown, b.cd, start, dur)
    b.mark:SetShown(Trinkets.Queue(b.key).enabled)
end

function Trinkets.Refresh()
    if not buttons then return end
    for _, b in ipairs(buttons) do paintSlot(b) end
end

local function layout()
    local d = db()
    for i, b in ipairs(buttons) do
        b.view:ClearAllPoints()
        if d.vertical then
            b.view:SetPoint("TOP", holder, "TOP", 0, -(i - 1) * (SIZE + 4))
        else
            b.view:SetPoint("LEFT", holder, "LEFT", (i - 1) * (SIZE + 4), 0)
        end
    end
    local w, h = SIZE * 2 + 4, SIZE
    if d.vertical then w, h = SIZE, SIZE * 2 + 4 end
    holder:SetSize(w, h)
    -- the scale is the mover's: it applies db.scale with the position
    if holder.mover then
        holder.mover.opts.width, holder.mover.opts.height = w, h
        ns:RefreshMoverGeometry(holder.mover)
        ns:ApplyMover(holder.mover)
    end
end

local function pickList(b)
    local entries = { { text = L["Trinkets"], title = true } }
    if InCombatLockdown() then
        entries[#entries + 1] = { text = L["Trinkets can only be changed out of combat."], title = true }
        return entries
    end
    local any = false
    for _, id in ipairs(Trinkets.Owned()) do
        if inBags(id) then
            any = true
            entries[#entries + 1] = { text = Trinkets.ItemName(id), icon = Trinkets.ItemIcon(id),
                func = function() equip(id, b.inv) end }
        end
    end
    if not any then entries[#entries + 1] = { text = L["No other trinket in your bags."], title = true } end
    return entries
end

local function onClick(self, button, down)
    if down then return end
    if button == "RightButton" then
        ns:ShowPopupMenu(pickList(self), self, self)
    elseif button == "LeftButton" and IsAltKeyDown() then
        local q = Trinkets.Queue(self.key)
        q.enabled = not q.enabled
        ns:Print(q.enabled and L["Trinkets: auto-queue for this slot is on."]
            or L["Trinkets: auto-queue for this slot is off."])
        paintSlot(self)
        syncTicker()
    end
end

local function onEnter(self)
    if not db().tooltips then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not GameTooltip:SetInventoryItem("player", self.inv) then
        GameTooltip:SetText(L["Trinkets"], 1, 1, 1)
    end
    GameTooltip:AddLine(L["Right click: pick a trinket. Alt-click: auto-queue on or off."], 0.6, 0.6, 0.65, true)
    GameTooltip:Show()
end

-- Built out of combat only: a secure button made in a fight cannot be used.
local function build()
    if holder then return true end
    if InCombatLockdown() then return false end
    holder = CreateFrame("Frame", "VuloForeverUITrinkets", UIParent)
    holder:SetSize(SIZE * 2 + 4, SIZE)
    holder:SetFrameStrata("MEDIUM")
    holder:Hide()
    buttons = {}
    for _, s in ipairs(SLOTS) do
        local view = CreateFrame("Frame", nil, holder)
        view:SetSize(SIZE, SIZE)
        local bg = view:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(view)
        bg:SetColorTexture(0, 0, 0, 0.6)
        local icon = view:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", -1, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local cd = CreateFrame("Cooldown", nil, view, "CooldownFrameTemplate")
        cd:SetAllPoints(icon)
        local mark = view:CreateTexture(nil, "OVERLAY")
        mark:SetAtlas("bags-greenarrow")
        mark:SetSize(12, 12)
        mark:SetPoint("TOPLEFT", view, "TOPLEFT", 1, -1)
        ns.LayoutEdges(ns.MakeEdges(view, "OVERLAY"), view, 1, 0, 0, 0, 1)

        local b = CreateFrame("Button", nil, holder, "SecureActionButtonTemplate")
        b:SetAllPoints(view)
        b:RegisterForClicks("AnyUp", "AnyDown")
        -- "/use 13" as macro text, NOT type "item" with item "13": on this
        -- client the item action parses a slot number into no name and then
        -- calls C_Item.IsEquippableItem(nil), which throws before anything is
        -- used. The /use command takes the slot path and never asks that.
        b:SetAttribute("*type1", "macro")
        b:SetAttribute("*macrotext1", "/use " .. s.inv)
        -- right click and alt-click: no secure action, the hook handles them
        -- (the exact "alt-type1" wins over the "*type1" wildcard)
        b:SetAttribute("type2", "vfnone")
        b:SetAttribute("alt-type1", "vfnone")
        b:HookScript("OnClick", onClick)
        b:SetScript("OnEnter", onEnter)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b.key, b.inv, b.view, b.icon, b.cd, b.mark = s.key, s.inv, view, icon, cd, mark
        buttons[#buttons + 1] = b
    end
    holder.mover = ns:CreateMover(holder, {
        key = "qol_trinkets", label = L["Trinkets"], db = db(), module = "qol",
        width = SIZE * 2 + 4, height = SIZE, scalable = true,
    })
    ns:ApplyMover(holder.mover)
    if db().freeMove then ns:SetMoverFreeMove(holder.mover, true) end
    return true
end

-- Moving without Edit Mode: the mover's own free-move, switched from the
-- options. It is refused in a fight by the mover itself -- the window holds
-- secure buttons.
function Trinkets.SetUnlocked(on)
    on = on and true or false
    db().freeMove = on
    if holder and holder.mover then ns:SetMoverFreeMove(holder.mover, on) end
end

-- ---------------------------------------------------------------- apply --

local function onEquip() Trinkets.Refresh() end
local function onCooldown() Trinkets.Refresh() end
local function onRegen()
    if pending then Trinkets.Apply() end
    if QoL.mod.active and db().enabled then tickQueue() end
end

function Trinkets.Apply()
    local on = QoL.mod.active and db().enabled
    QoL.SyncEvent(on, "PLAYER_EQUIPMENT_CHANGED", onEquip)
    QoL.SyncEvent(on, "BAG_UPDATE_COOLDOWN", onCooldown)
    QoL.SyncEvent(on, "SPELL_UPDATE_COOLDOWN", onCooldown)
    ns:RegisterEvent("PLAYER_REGEN_ENABLED", onRegen)

    -- Showing, hiding and building touch a frame with secure children: out
    -- of combat only, and a change asked for in a fight lands when it ends.
    if InCombatLockdown() then pending = true; return end
    pending = false
    if on then
        if not build() then pending = true; return end
        layout()
        Trinkets.Refresh()
        holder:Show()
    elseif holder then
        holder:Hide()
    end
    syncTicker()
end

function Trinkets.Disable()
    QoL.SyncEvent(false, "PLAYER_EQUIPMENT_CHANGED", onEquip)
    QoL.SyncEvent(false, "BAG_UPDATE_COOLDOWN", onCooldown)
    QoL.SyncEvent(false, "SPELL_UPDATE_COOLDOWN", onCooldown)
    if ticker then ns:CancelTicker(ticker); ticker = nil end
    if holder then
        if InCombatLockdown() then pending = true else holder:Hide() end
    end
end

-- The queue page changed a list or a switch.
function Trinkets.QueueChanged()
    Trinkets.Refresh()
    syncTicker()
end
