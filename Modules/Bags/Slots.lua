-- VuloForeverUI / Modules / Bags / Slots
--
-- The item buttons: a pool of them, and what one looks like once it has an
-- item in it.
--
-- THE POOL IS THE WHOLE POINT
--
-- These are secure buttons from the client's own container template, which is
-- what makes a left click use the item and a drag pick it up. A button made
-- while a fight is on is tainted for the rest of the session, and the failure
-- shows up as "action blocked" the first time somebody drinks a potion in a
-- dungeon. So: the pool is grown out of combat, generously, and a window that
-- runs out of slots mid-fight draws what it has and waits.
--
-- Each button also gets a PARENT of its own, because that is where the bag
-- number lives: the client's secure click reads the bag from the parent's id
-- and the slot from the button's. That is also why our own state lives in
-- Bags.State(button) instead of on the button -- a custom field there taints
-- the same click.
local _, ns = ...
local Bags = ns.Bags

local Slots = {}
Bags.Slots = Slots

-- ONE POOL PER WINDOW, not one for the module.
--
-- The bags and the bank are open at the same time whenever anyone visits a
-- banker, and a single shared pool means the second window to lay itself out
-- takes the buttons the first one is already using -- the bank would draw
-- itself out of the bags' slots and the bags would go blank. Each window keeps
-- its own list and its own cursor into it.
local pools, host = {}, nil
local WARM_TARGET = 160     -- a full set of bags plus room to grow

local function poolFor(owner)
    local p = pools[owner]
    if not p then p = { slots = {}, used = 0 }; pools[owner] = p end
    return p
end

local function ensureHost()
    if host then return host end
    host = CreateFrame("Frame", nil, UIParent)
    host:Hide()
    return host
end

-- ---------------------------------------------------------------- pool --

local function makeSlot(owner)
    if InCombatLockdown() then return nil end
    local parent = CreateFrame("Frame", nil, ensureHost())
    parent:SetSize(Bags.SLOT_SIZE, Bags.SLOT_SIZE)

    local ok, button = pcall(CreateFrame, "ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
    if not ok or not button then return nil end
    button:SetAllPoints(parent)
    -- Shown explicitly. A button from this template does not necessarily come
    -- up shown -- the client's own container shows its buttons itself as it
    -- fills them -- and showing only the frame around it gave a window with
    -- the right shape, the right counts and no icons at all.
    button:Show()

    local slot = { frame = parent, button = button }

    -- One font string, and nothing else: the quality border comes from the
    -- client's own setter further down, and the four edge textures an earlier
    -- draft made here were laid out at zero width -- a thousand hidden
    -- textures for a border that could never be seen.
    local level = button:CreateFontString(nil, "OVERLAY")
    level:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    slot.level = level

    local p = poolFor(owner)
    p.slots[#p.slots + 1] = slot
    return slot
end

-- Grow the pool up to what a full set of bags needs. Called at login and every
-- time a fight ends.
-- Grown for both windows, because the bank window has to be ready before the
-- player reaches a banker: at the banker the fight is over, but the bags may
-- already be full and the pool is cheaper to have than to need.
function Slots.Warm()
    if InCombatLockdown() then return end
    for _, owner in ipairs({ "bags", "bank" }) do
        local p = poolFor(owner)
        local want = (owner == "bags") and math.min(WARM_TARGET, math.max(#p.slots + 24, 64)) or 40
        while #p.slots < want do
            if not makeSlot(owner) then break end
        end
    end
end

-- Hand out the next free slot, or nothing at all. "Nothing at all" is a real
-- answer here: in combat the pool cannot grow, and a missing slot is better
-- than a tainted one.
function Slots.Begin(owner)
    poolFor(owner).used = 0
end

-- Second return value: WHY there is no slot. "in combat" is a wait that
-- passes; anything else means the client would not give us a button at all,
-- and the two must not reach the player as the same sentence.
function Slots.Next(owner)
    local p = poolFor(owner)
    p.used = p.used + 1
    local slot = p.slots[p.used]
    if slot then return slot end
    if InCombatLockdown() then return nil, "combat" end
    local made = makeSlot(owner)
    if made then return made end
    return nil, "refused"
end

function Slots.HideRest(owner)
    local p = poolFor(owner)
    for i = p.used + 1, #p.slots do
        p.slots[i].frame:Hide()
    end
end

function Slots.PoolSize(owner) return #poolFor(owner).slots end

-- ---------------------------------------------------------------- paint --

local POOR = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

-- THE SETTERS EXIST IN TWO SHAPES, and which one a client has is not ours to
-- assume: newer builds carry them as methods on the button, older ones only as
-- global functions. Both are tried, and a failure is SAID ONCE rather than
-- swallowed -- the first draft wrapped each call in a bare pcall, and when the
-- method was not there the window came up with headings and no items and no
-- word about why.
local reported = {}

local function callSetter(button, name, ...)
    local method = button[name]
    if type(method) == "function" then
        local ok = pcall(method, button, ...)
        if ok then return true end
    end
    local global = _G[name]
    if type(global) == "function" then
        local ok = pcall(global, button, ...)
        if ok then return true end
    end
    if not reported[name] then
        reported[name] = true
        ns:Print(ns.L["The client has no %s; bag icons may stay empty."], name)
    end
    return false
end

-- One slot, bound to one place in one bag. The two ids are what the client's
-- secure click reads, and they are set with the frame's own setter -- which is
-- not a custom field and is therefore allowed.
function Slots.Paint(slot, bagID, slotID, info)
    local db = Bags.db()
    local button, frame = slot.button, slot.frame

    frame:SetID(bagID)
    button:SetID(slotID)
    frame:SetSize(db.slotSize or 37, db.slotSize or 37)

    button:Show()

    -- The icon, from whichever field this client's container info carries it
    -- in. If none of them has it, the item's own link is asked instead -- and
    -- the first time that happens the fields we DID get are printed, because
    -- guessing twice about the same table is how an empty bag stays empty.
    local icon = info and (info.iconFileID or info.icon or info.texture)
    if info and not icon then
        if info.hyperlink and C_Item.GetItemIconByID then
            icon = C_Item.GetItemIconByID(info.hyperlink)
        end
        if not reported.info then
            reported.info = true
            local keys = {}
            for k in pairs(info) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            ns:Print(ns.L["The bag data has no icon field. What it does have: %s"], table.concat(keys, ", "))
        end
    end
    if not callSetter(button, "SetItemButtonTexture", icon) then
        -- Last resort: the icon region itself. Not as good as the setter --
        -- it knows about the slot's empty art and the overlays -- but an icon
        -- drawn by hand beats a bag full of nothing.
        local tex = button.icon or button.Icon
        if tex then tex:SetTexture(icon) end
    end
    callSetter(button, "SetItemButtonCount",
        (db.showCount ~= false and info) and info.stackCount or 0)

    -- The quality border: the client's own setter knows every item type there
    -- is, including the ones a guess would miss.
    if db.qualityBorder ~= false and info then
        callSetter(button, "SetItemButtonQuality", info.quality, info.hyperlink, false, false)
    else
        callSetter(button, "SetItemButtonQuality", nil)
    end

    -- Grey items go quiet so the rest of the bag can be read.
    local dim = db.dimJunk and info and type(info.quality) == "number" and info.quality == POOR
    callSetter(button, "SetItemButtonDesaturated", dim and true or false)

    -- The cooldown swirl, driven by the client's own numbers.
    local cd = button.Cooldown or button.cooldown
    if cd then
        local start, duration, enable = C_Container.GetContainerItemCooldown(bagID, slotID)
        if type(start) == "number" and type(duration) == "number" then
            pcall(cd.SetCooldown, cd, start, duration)
            cd:SetShown((enable or 0) ~= 0 and duration > 0)
        else
            pcall(cd.Clear, cd)
        end
    end

    -- The item level, on gear only.
    if db.showItemLevel and info and Bags.Categories.IsGear(info) then
        local level
        local loc = ItemLocation and ItemLocation.CreateFromBagAndSlot
            and ItemLocation:CreateFromBagAndSlot(bagID, slotID)
        if loc and C_Item.GetCurrentItemLevel then
            local ok, value = pcall(C_Item.GetCurrentItemLevel, loc)
            if ok and type(value) == "number" then level = value end
        end
        if level then
            ns.UI.FontFor("bags", slot.level, db.itemLevelSize or 11, "OUTLINE")
            slot.level:SetTextColor(db.itemLevelColor.r, db.itemLevelColor.g, db.itemLevelColor.b)
            slot.level:SetText(tostring(level))
            slot.level:Show()
        else
            slot.level:Hide()
        end
    else
        slot.level:Hide()
    end

    -- A locked item -- one that is on the cursor or being moved -- is drawn
    -- faded, the way the client draws it in its own bags.
    local locked = info and info.isLocked
    local shade = locked and 0.5 or 1
    if type(button.SetItemButtonTextureVertexColor) == "function" then
        pcall(button.SetItemButtonTextureVertexColor, button, shade, shade, shade)
    else
        local tex = button.icon or button.Icon
        if tex then tex:SetVertexColor(shade, shade, shade) end
    end

    frame:Show()
end

-- A slot the search has filtered out: still there, still clickable, just faded
-- so the eye goes to what was searched for.
function Slots.SetFiltered(slot, filtered)
    slot.frame:SetAlpha(filtered and 0.25 or 1)
end
