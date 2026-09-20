-- VuloForeverUI / Modules / QoL / Vendor
--
-- What happens when you walk up to a merchant: the greys go, the gear gets
-- repaired, and a warning appears long before either matters.
--
-- TWO THINGS THE SERVER DOES NOT TELL US
--
-- 1. SellAllJunkItems is fire and forget. Past its rate limit the server drops
--    sell requests without a word, and an item whose data has not cached yet
--    at MERCHANT_SHOW is not counted as junk at all. One call therefore leaves
--    greys behind on a regular basis -- so the sweep re-counts after every
--    pass and fires again while the count is still falling, backing off when
--    it stops.
--
-- 2. RepairAllItems(true) never fails for want of guild funds: the server pays
--    what the allowance covers and quietly charges the rest to the player, and
--    the call itself reports nothing. Who paid is therefore deduced from the
--    money that actually left the player after the debit has landed -- never
--    from the guild bank balance, which reads zero until a guild bank has been
--    opened this session.
--
-- Nothing here is secret: item quality, money and repair costs stay readable
-- on this client.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Vendor = QoL.RegisterPart("vendor", {})
QoL.Vendor = Vendor

local merchantOpen = false

-- --------------------------------------------------------------- money --

-- Coin icons or "12g 34s": the icons are the client's own textures, the short
-- form is built from translated suffixes.
local function moneyText(amount)
    if QoL.db().repairCoinIcons and C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    end
    local g = math.floor(amount / 10000)
    local s = math.floor((amount % 10000) / 100)
    local c = amount % 100
    local out = ""
    if g > 0 then out = g .. L["g"] end
    if s > 0 then out = out .. (out ~= "" and " " or "") .. s .. L["s"] end
    if c > 0 or out == "" then out = out .. (out ~= "" and " " or "") .. c .. L["c"] end
    return out
end

-- ---------------------------------------------------------- junk sweep --

local BASE_DELAY, MAX_DELAY = 0.4, 1.6
local MAX_PASSES, MAX_STALLS = 12, 3
local pending, passes, lastCount, stalls, warned, delay

local function carriedBags()
    if ns.Bags and ns.Bags.CarriedBags then return ns.Bags.CarriedBags() end
    local out = { 0 }
    for i = 1, (NUM_BAG_SLOTS or 4) do out[#out + 1] = i end
    return out
end

local function countJunk()
    local junk, unknown = 0, 0
    for _, bag in ipairs(carriedBags()) do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                -- A quality of nil is "not cached yet", not "not junk": the
                -- sweep waits for it rather than deciding without it.
                if info.quality == nil then
                    unknown = unknown + 1
                elseif info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                    junk = junk + 1
                end
            end
        end
    end
    return junk, unknown
end

local function stopSweep()
    if pending then pending:Cancel(); pending = nil end
end

local function report()
    pending = nil
    if not merchantOpen then return end
    local left = countJunk()
    if left > 0 and not warned then
        warned = true
        ns:Print(L["%d grey item(s) could not be sold."], left)
    end
end

local function pass()
    pending = nil
    if not merchantOpen or not QoL.db().sellJunk then return end

    local junk, unknown = countJunk()
    if junk == 0 and unknown == 0 then return end

    passes = passes + 1
    if junk > lastCount then
        -- The count ROSE: uncached slots resolved into junk that could not be
        -- seen a moment ago. That is discovery, not a stall -- and it is the
        -- whole reason this sweep exists.
        stalls, delay = 0, BASE_DELAY
    elseif junk == lastCount then
        -- Nothing moved. Either the item cannot be sold (a refundable purchase
        -- opens a confirmation instead) or the request was dropped; the two
        -- look identical from here, so back off before giving up.
        stalls = stalls + 1
        delay = math.min(delay * 2, MAX_DELAY)
        if stalls >= MAX_STALLS then
            if junk > 0 and not warned then
                warned = true
                ns:Print(L["%d grey item(s) could not be sold."], junk)
            end
            return
        end
    else
        stalls, delay = 0, BASE_DELAY
    end

    lastCount = junk
    -- Only round-trip when there is something to sell; a count of zero with
    -- unknowns left is just waiting on item data.
    if junk > 0 and C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
        C_MerchantFrame.SellAllJunkItems()
    end
    if passes >= MAX_PASSES then
        -- The cap was hit while things were still moving. Bailing silently is
        -- the exact failure this sweep fixes, so one verifying pass follows.
        pending = C_Timer.NewTimer(delay, report)
        return
    end
    pending = C_Timer.NewTimer(delay, pass)
end

local function sellJunk()
    if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems) then return end
    stopSweep()
    passes, lastCount, stalls, warned = 0, math.huge, 0, false
    delay = BASE_DELAY
    pass()
end

-- -------------------------------------------------------------- repair --

local repairGen = 0

local function reportRepair(guildPart, ownPart)
    if not QoL.db().repairReport then return end
    local line = string.format(L["Repaired everything for %s"], moneyText(guildPart + ownPart))
    if guildPart > 0 then
        line = line .. " " .. L["(guild bank)"]
        if ownPart > 0 then line = line .. " " .. moneyText(guildPart) end
    end
    ns:Print(line)
end

-- Who paid is only knowable once the debit has landed, so the verdict waits
-- half a second rather than reading the guild bank -- which reports zero until
-- a guild bank has been opened this session, exactly the case where the guild
-- pays nothing. The generation counter makes a second merchant cancel the
-- first one's pending verdict instead of reporting it twice.
local function watchRepair(cost, moneyBefore)
    repairGen = repairGen + 1
    local gen = repairGen
    C_Timer.After(0.5, function()
        if gen ~= repairGen then return end
        local remain, stillNeed = GetRepairAllCost()
        if not (stillNeed and remain > 0) then remain = 0 end
        local paid = cost - remain
        if paid <= 0 then return end
        local own = moneyBefore - GetMoney()
        if own < 0 then own = 0 end
        if own > paid then own = paid end
        reportRepair(paid - own, own)
    end)
end

local function doRepair()
    if not (QoL.db().repairAll and CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, canRepair = GetRepairAllCost()
    if not (canRepair and cost and cost > 0) then return end

    local useGuild = QoL.db().repairGuild and IsInGuild()
        and CanGuildBankRepair and CanGuildBankRepair()
    if not useGuild and GetMoney() < cost then
        -- Nothing was spent, so there is nothing to watch.
        ns:Print(L["Not enough gold to repair."])
        return
    end
    -- No affordability test on the guild path on purpose: the client's own
    -- button also just asks for the repair and lets the server split the bill.
    -- Gating on "the guild covers all of it" would hand the player the lot.
    local before = GetMoney()
    RepairAllItems(useGuild and true or false)
    watchRepair(cost, before)
end

-- -------------------------------------------------- durability warning --

local durFrame

local function durabilitySettings()
    if not durFrame then return end
    local db = QoL.db().durability
    local c = db.color
    durFrame.text:SetFont(QoL.Font(), db.fontSize, QoL.Outline())
    durFrame.text:SetTextColor(c.r, c.g, c.b, 1)
    durFrame:SetSize(db.fontSize * 12, db.fontSize + 12)
    if durFrame.mover then
        durFrame.mover.opts.width  = durFrame:GetWidth()
        durFrame.mover.opts.height = durFrame:GetHeight()
        ns:RefreshMoverGeometry(durFrame.mover)
        ns:ApplyMover(durFrame.mover)
    end
end
Vendor.RefreshDurability = durabilitySettings

local function createDurability()
    if durFrame then return durFrame end

    durFrame = CreateFrame("Frame", "VuloForeverUIDurabilityWarning", UIParent)
    durFrame:SetSize(240, 40)
    durFrame:SetFrameStrata("HIGH")
    durFrame:EnableMouse(false)

    local fs = durFrame:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    durFrame.text = fs

    -- A slow pulse, so the line is noticed without covering anything.
    local ag = fs:CreateAnimationGroup()
    local out = ag:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0.3); out:SetDuration(0.5); out:SetOrder(1)
    local back = ag:CreateAnimation("Alpha")
    back:SetFromAlpha(0.3); back:SetToAlpha(1); back:SetDuration(0.5); back:SetOrder(2)
    ag:SetLooping("REPEAT")
    durFrame.pulse = ag
    durFrame:SetScript("OnHide", function() ag:Stop() end)

    durFrame.mover = ns:CreateMover(durFrame, {
        key      = "qol_durability",
        label    = L["Durability warning"],
        db       = QoL.db().durability,
        module   = "qol",
        width    = 240,
        height   = 40,
        scalable = true,
        -- Invisible nearly all the time, so the mover box has to stand in for
        -- it or there is nothing to grab in Edit Mode.
        fill     = true,
    })
    durabilitySettings()
    ns:ApplyMover(durFrame.mover)
    durFrame:Hide()
    return durFrame
end

-- The lowest percentage across the worn slots, or nil while nothing is worn.
local function lowestDurability()
    local lowest
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    return lowest
end

local function checkDurability()
    local db = QoL.db().durability
    if not db.enabled then
        if durFrame then durFrame:Hide() end
        return
    end
    -- The warning is something you act on, and there is nothing to be done
    -- about it in the middle of a fight.
    if ns:InCombat() then
        if durFrame then durFrame:Hide() end
        return
    end

    local lowest = lowestDurability()
    if lowest and lowest < db.threshold then
        createDurability()
        durabilitySettings()
        durFrame.text:SetFormattedText(L["Low durability (%d%%)"], math.floor(lowest))
        durFrame:Show()
        durFrame.pulse:Play()
    elseif durFrame then
        durFrame:Hide()
    end
end
Vendor.CheckDurability = checkDurability

-- The durability and alert events arrive one per damaged slot, so the check is
-- coalesced into a single pass on the next frame.
local durPending = false
local function flushDurability()
    durPending = false
    checkDurability()
end

local function onDurabilityEvent()
    if durPending then return end
    durPending = true
    ns.NextFrame(flushDurability)
end

-- Shows the warning at a made-up value, so its place on the screen can be
-- judged without ruining a set of gear first.
function Vendor.PreviewDurability()
    createDurability()
    durabilitySettings()
    durFrame.text:SetFormattedText(L["Low durability (%d%%)"], QoL.db().durability.threshold)
    durFrame:Show()
    durFrame.pulse:Play()
    C_Timer.After(4, checkDurability)
end

-- -------------------------------------------------------------- events --

local function onMerchantShow()
    merchantOpen = true
    doRepair()
    if QoL.db().sellJunk then
        -- After the repair verdict: a sale landing in the same money event as
        -- the repair debit would net against it, and the whole bill would be
        -- credited to the guild bank.
        C_Timer.After(0.6, function()
            if merchantOpen then sellJunk() end
        end)
    end
end

local function onMerchantClosed()
    merchantOpen = false
    stopSweep()
end

local DUR_EVENTS = {
    "UPDATE_INVENTORY_DURABILITY", "UPDATE_INVENTORY_ALERTS",
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
}

function Vendor.Apply()
    local db = QoL.db()

    local vendorOn = (db.sellJunk or db.repairAll) and true or false
    QoL.SyncEvent(vendorOn, "MERCHANT_SHOW", onMerchantShow)
    QoL.SyncEvent(vendorOn, "MERCHANT_CLOSED", onMerchantClosed)
    if not vendorOn then
        merchantOpen = false
        stopSweep()
    end

    local durOn = db.durability.enabled and true or false
    for _, ev in ipairs(DUR_EVENTS) do
        QoL.SyncEvent(durOn, ev, onDurabilityEvent)
    end
    if durOn then
        createDurability()
        durabilitySettings()
        checkDurability()
    elseif durFrame then
        durFrame:Hide()
    end
end

function Vendor.Disable()
    stopSweep()
    merchantOpen = false
    if durFrame then durFrame:Hide() end
    ns:UnregisterEvent("MERCHANT_SHOW", onMerchantShow)
    ns:UnregisterEvent("MERCHANT_CLOSED", onMerchantClosed)
    for _, ev in ipairs(DUR_EVENTS) do
        ns:UnregisterEvent(ev, onDurabilityEvent)
    end
end
