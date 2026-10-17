-- VuloForeverUI / Modules / QoL / StackSplit
--
-- Three additions to the client's own "split a stack" popup: a button that
-- takes the whole stack, our look instead of the money-frame art, and -- at a
-- merchant -- buying more than one stack at once.
--
-- WHY THE CLIENT'S FRAME AND NOT OUR OWN
--
-- `StackSplitFrame` is what every bag in the game opens -- ours, the client's,
-- the bank, the guild bank. Rebuilding it would mean replacing a frame that
-- four different windows hand their item to, and each of them expects the
-- original back. Adding to it reaches all four and breaks none.
--
-- The frame is plain FrameXML: a `Frame` with `StackSplitMixin`, created at
-- load, not secure and not protected. Its shape here is Forever's own
-- (Blizzard_FrameXML/Camelot/StackSplitFrame.xml), which is why the parts are
-- addressed by their parentKey -- `LeftButton`, `RightButton`, `OkayButton`,
-- `StackSplitText` -- rather than by a global name.
--
-- The state lives on the frame: `split` is the current amount, `maxStack` the
-- most it may be, `minSplit` the step for a multi-stack. MAX therefore sets
-- `split` and asks the frame's own `UpdateStackText` to redraw, which is the
-- same path the arrow buttons take. `typing` is deliberately NOT touched: the
-- mixin uses it to decide whether a digit starts a new number, and a MAX that
-- quietly changed that would make the next keystroke behave differently than it
-- does after an arrow click.
local _, ns = ...
local L  = ns.L
local UI = ns.UI

local QoL = ns.QoL
local Split = QoL.RegisterPart("stacksplit", {})
QoL.StackSplit = Split

local function db() return QoL.db().stackSplit end

local maxButton      -- our button, created once, kept for the session
local hooked         -- the frame's methods carry our hook already
local originalShown  -- the art we hid, so switching the skin off restores it

local function frame() return _G.StackSplitFrame end

-- ------------------------------------------------------- merchant --
--
-- Shift-click on a merchant item opens this same frame, capped by the client
-- at one purchase (GetMerchantItemMaxStack) and at what you can pay. With
-- `merchantBuy` on, the cap becomes what you can pay, what the merchant has
-- and what fits into your bags -- and Max fills that in.
--
-- The client's Okay hands the amount to the item button's own SplitStack,
-- which buys it in ONE call; past a single purchase that call is not ours to
-- trust. So each merchant item button gets its SplitStack wrapped, once: up to
-- one purchase it goes to the client's original untouched, above it we buy
-- purchase by purchase, a step apart, while the merchant stays open. Items
-- paid in other items or with a refund prompt keep the client's cap.
local BUY_STEP = 0.3
local originals = setmetatable({}, { __mode = "k" })   -- item button -> client's SplitStack
local merchantOwner                                     -- the button the frame was opened for
local buying

local function merchantIndex(owner)
    if not owner or owner:IsForbidden() then return nil end
    local parent = owner:GetParent()
    local name = parent and parent:GetName()
    if type(name) ~= "string" or not name:match("^MerchantItem%d+$") then return nil end
    local mf = _G.MerchantFrame
    if not (mf and mf:IsShown() and (mf.selectedTab or 1) == 1) then return nil end
    local id = owner:GetID()
    return type(id) == "number" and id > 0 and id or nil
end

-- Room for `itemID` in the bags that can hold it: free slots and what the
-- partial stacks of it still take.
local function roomFor(itemID, perStack)
    local family = C_Item.GetItemFamily(itemID) or 0
    local room = 0
    for _, bag in ipairs(ns.CarriedBags()) do
        local free, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
        if bagFamily == 0 or (family ~= 0 and bagFamily and bit.band(family, bagFamily) ~= 0) then
            room = room + (free or 0) * perStack
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID == itemID then
                    room = room + math.max(0, perStack - (info.stackCount or 0))
                end
            end
        end
    end
    return room
end

-- The most of merchant item `index` that can be bought now, in items; nil when
-- the client's own cap stands (extended cost, unknown item, nothing to gain).
local function merchantMost(index)
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info or info.hasExtendedCost or not (info.price and info.price > 0) then return nil end
    local lot = math.max(1, info.stackCount or 1)
    local itemID = GetMerchantItemID(index)
    local perStack = itemID and C_Item.GetItemMaxStackSizeByID(itemID)
    if type(perStack) ~= "number" or perStack < 1 then return nil end
    local most = math.floor(GetMoney() / (info.price / lot))
    most = math.min(most, roomFor(itemID, perStack))
    if type(info.numAvailable) == "number" and info.numAvailable >= 0 then
        most = math.min(most, info.numAvailable * lot)
    end
    most = math.floor(most / lot) * lot
    return most, lot
end

local function stopBuying()
    if buying then buying:Cancel(); buying = nil end
end

local function buyInSteps(index, total)
    stopBuying()
    local per = GetMerchantItemMaxStack(index) or 1
    local link = GetMerchantItemLink(index)
    local left = total
    local function step()
        buying = nil
        local mf = _G.MerchantFrame
        if left <= 0 or not (mf and mf:IsShown()) then return end
        local n = math.min(per, left)
        BuyMerchantItem(index, n)
        left = left - n
        if left > 0 then
            buying = C_Timer.NewTimer(BUY_STEP, step)
        elseif link then
            ns:Print(L["Bought %d x %s."], total, link)
        end
    end
    step()
end

local function wrapSplit(owner)
    if originals[owner] or type(owner.SplitStack) ~= "function" then return end
    local original = owner.SplitStack
    originals[owner] = original
    owner.SplitStack = function(button, split)
        local index = merchantIndex(button)
        local per = index and GetMerchantItemMaxStack(index)
        if index and per and type(split) == "number" and split > per and db().merchantBuy then
            buyInSteps(index, split)
        else
            original(button, split)
        end
    end
end

-- After the client opened the frame: raise its cap for a merchant item.
local function raiseForMerchant(f)
    merchantOwner = nil
    if not db().merchantBuy then return end
    local index = merchantIndex(f.owner)
    if not index then return end
    local most = merchantMost(index)
    if not most or most <= (tonumber(f.maxStack) or 0) then return end
    wrapSplit(f.owner)
    merchantOwner = f.owner
    f.maxStack = most
    if f.RightButton and (tonumber(f.split) or 0) < most then f.RightButton:Enable() end
end

-- ------------------------------------------------------------- MAX --

local function applyMax()
    local f = frame()
    if not f then return end
    local most = tonumber(f.maxStack)
    if not most or most < 1 then return end

    f.split = most
    if f.UpdateStackText then f:UpdateStackText() end
    -- The arrows answer for their own ends; at the top there is nothing to the
    -- right and always something to the left.
    if f.RightButton then f.RightButton:Disable() end
    if f.LeftButton and most > (tonumber(f.minSplit) or 1) then f.LeftButton:Enable() end
end

local function ensureMaxButton()
    if maxButton then return maxButton end
    local f = frame()
    if not f then return nil end

    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(38, 16)
    -- Upper right, the only free corner: the number sits right of centre, the
    -- arrows flank it, and the bottom row is Okay and Cancel edge to edge.
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    if b.SetText then b:SetText(L["Max"]) end
    if b.SetFrameLevel then b:SetFrameLevel((f:GetFrameLevel() or 1) + 5) end
    b:SetScript("OnClick", applyMax)
    b:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self, { title = L["Max"], accent = true,
            lines = { merchantOwner and L["As many as you can pay for and your bags can hold."]
                or L["Take the whole stack."] } })
    end)
    b:SetScript("OnLeave", function() UI:HideTooltip() end)
    maxButton = b
    return b
end

-- The button only makes sense while there is more than one to take, and the
-- frame is reused for every split, so this rides along with the frame's own
-- two entry points rather than an OnShow that fires before the numbers are set.
local function syncMaxButton()
    local f = frame()
    if not f then return end
    local on = (db().maxButton or (merchantOwner and merchantOwner == f.owner))
        and (tonumber(f.maxStack) or 0) > 1
    if not on then
        if maxButton then maxButton:Hide() end
        return
    end
    local b = ensureMaxButton()
    if b then b:Show() end
end

-- ------------------------------------------------------------ skin --

local function applySkin(on)
    local f = frame()
    if not f then return end

    local art = { f.SingleItemSplitBackground, f.MultiItemSplitBackground }
    if on then
        if originalShown == nil then
            originalShown = {}
            for i, t in ipairs(art) do originalShown[i] = t and t:IsShown() end
        end
        for _, t in ipairs(art) do if t then t:Hide() end end
        UI:StyleBackdrop(f)
        if f._vcBG then f._vcBG:Show() end
        if f._vcBorders then for _, t in ipairs(f._vcBorders) do t:Show() end end
    else
        if f._vcBG then f._vcBG:Hide() end
        if f._vcBorders then for _, t in ipairs(f._vcBorders) do t:Hide() end end
        -- Only what we hid comes back, and only to the state it was in: the
        -- multi-stack art is hidden by the frame itself most of the time.
        if originalShown then
            for i, t in ipairs(art) do
                if t and originalShown[i] then t:Show() end
            end
        end
    end
end

-- ----------------------------------------------------------- hooks --

-- hooksecurefunc on the frame's own methods: the mixin functions are what every
-- caller goes through, and hooking them leaves the originals untouched.
local function ensureHooks()
    if hooked then return end
    local f = frame()
    if not (f and f.OpenStackSplitFrame) then return end
    hooksecurefunc(f, "OpenStackSplitFrame", function(self)
        merchantOwner = nil
        if not QoL.mod.active then return end
        raiseForMerchant(self)
        syncMaxButton()
        applySkin(db().skin)
    end)
    if f.UpdateStackSplitFrame then
        hooksecurefunc(f, "UpdateStackSplitFrame", function()
            if QoL.mod.active then syncMaxButton() end
        end)
    end
    hooked = true
end

-- ----------------------------------------------------------- apply --

function Split.Apply()
    if not frame() then return end
    ensureHooks()
    syncMaxButton()
    applySkin(db().skin)
end

function Split.Disable()
    stopBuying()
    merchantOwner = nil
    if maxButton then maxButton:Hide() end
    applySkin(false)
end
