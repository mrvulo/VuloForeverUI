-- VuloForeverUI / Modules / QoL / StackSplit
--
-- Four additions to the client's own "split a stack" popup: a button that
-- takes the whole stack, a field to type the amount into, our look instead of
-- the money-frame art, and -- at a merchant -- buying more than one stack at
-- once.
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
local typeBox        -- the amount field over the number, and its click catcher
local typeCatcher
local merchantStack  -- one full stack of the merchant item, in items
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
    local most, lot = merchantMost(index)
    if not most or most <= (tonumber(f.maxStack) or 0) then return end
    local itemID = GetMerchantItemID(index)
    local perStack = itemID and C_Item.GetItemMaxStackSizeByID(itemID) or lot
    merchantStack = math.max(lot, math.floor(perStack / lot) * lot)
    wrapSplit(f.owner)
    merchantOwner = f.owner
    f.maxStack = most
    if f.RightButton and (tonumber(f.split) or 0) < most then f.RightButton:Enable() end
end

-- ------------------------------------------------------------- MAX --

-- Set the amount the way the arrows do: the frame's own fields, its own
-- redraw, and each arrow answering for its own end.
local function setSplit(f, n)
    local most = tonumber(f.maxStack) or 1
    local step = math.max(1, tonumber(f.minSplit) or 1)
    n = math.floor((tonumber(n) or step) / step) * step
    n = math.max(step, math.min(n, most))
    f.split = n
    if f.UpdateStackText then f:UpdateStackText() end
    if f.RightButton then
        if n >= most then f.RightButton:Disable() else f.RightButton:Enable() end
    end
    if f.LeftButton then
        if n <= step then f.LeftButton:Disable() else f.LeftButton:Enable() end
    end
    return n
end

-- At a merchant Max is ONE full stack -- what a shopping trip usually means --
-- and Shift-click takes everything you can pay for and carry. Elsewhere it is
-- the whole stack being split.
local function applyMax()
    local f = frame()
    if not f then return end
    local most = tonumber(f.maxStack)
    if not most or most < 1 then return end
    if merchantOwner and merchantOwner == f.owner and merchantStack and not IsShiftKeyDown() then
        most = math.min(most, merchantStack)
    end
    setSplit(f, most)
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
        local f = frame()
        UI:ShowTooltip(self, { title = L["Max"], accent = true,
            lines = { (merchantOwner and f and merchantOwner == f.owner)
                and L["One full stack. Shift-click: as many as you can pay for and your bags can hold."]
                or L["Take the whole stack."] } })
    end)
    b:SetScript("OnLeave", function() UI:HideTooltip() end)
    maxButton = b
    return b
end

-- ------------------------------------------------------------ type --
--
-- The client already takes digits typed while the window is open, but shows no
-- field, and a digit that would go past the limit is silently dropped -- so
-- "40" with a limit of 20 ends at 4. Here the number is a field: a click on it
-- opens a box with the amount selected, what is typed is held to the limit as
-- it is typed, and Enter confirms like Okay. The box never takes the focus on
-- its own: an open split window must not swallow the movement keys.

local function closeBox()
    if typeBox and typeBox:IsShown() then
        typeBox:ClearFocus()
        typeBox:Hide()
    end
end

local function ensureTypeBox()
    if typeBox then return typeBox end
    local f = frame()
    if not (f and f.StackSplitText) then return nil end

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetSize(64, 20)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(6)
    eb:SetFontObject(ChatFontNormal)
    eb:SetJustifyH("CENTER")
    eb:SetFrameLevel((f:GetFrameLevel() or 1) + 6)
    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(eb)
    bg:SetColorTexture(0.05, 0.05, 0.06, 0.95)
    eb.edges = ns.MakeEdges(eb, "OVERLAY")
    ns.LayoutEdges(eb.edges, eb, 1, ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1, 0)
    eb:Hide()

    -- Held to the limit while typing: past it, the field shows the limit.
    eb:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local n = tonumber(self:GetText())
        local most = tonumber(f.maxStack) or 1
        if n and n > most then
            self:SetText(tostring(most))
            self:SetCursorPosition(#tostring(most))
        end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        local n = tonumber(self:GetText())
        closeBox()
        if n and n > 0 then
            setSplit(f, n)
            if StackSplitOkayButton_OnClick then StackSplitOkayButton_OnClick() end
        end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self.discard = true
        closeBox()
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        -- Clicking elsewhere keeps what was typed, without confirming it;
        -- Escape throws it away.
        local n = tonumber(self:GetText())
        if n and n > 0 and not self.discard then setSplit(f, n) end
        self.discard = nil
        self:Hide()
    end)

    local catcher = CreateFrame("Button", nil, f)
    catcher:SetFrameLevel((f:GetFrameLevel() or 1) + 5)
    catcher:SetScript("OnClick", function()
        eb:ClearAllPoints()
        eb:SetPoint("CENTER", f.StackSplitText, "CENTER", 0, 0)
        eb:SetText(tostring(tonumber(f.split) or 1))
        eb:Show()
        eb:SetFocus()
        eb:HighlightText()
    end)
    catcher:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self, { title = L["Type the amount"], accent = true,
            lines = { L["Click the number and type how many you want. Enter confirms."] } })
    end)
    catcher:SetScript("OnLeave", function() UI:HideTooltip() end)
    f:HookScript("OnHide", closeBox)

    typeBox, typeCatcher = eb, catcher
    return eb
end

-- The catcher follows the number, which the frame moves between its single
-- and multi-stack layouts.
local function syncTypeBox()
    local f = frame()
    if not f then return end
    closeBox()
    local on = db().typeAmount ~= false and (tonumber(f.maxStack) or 0) > 1
    if not on then
        if typeCatcher then typeCatcher:Hide() end
        return
    end
    if not ensureTypeBox() then return end
    -- Hugging the number's own bounds, which grow with it: a fixed box wide
    -- enough for "1000" would lie over the arrows beside a "1".
    typeCatcher:ClearAllPoints()
    typeCatcher:SetPoint("TOPLEFT", f.StackSplitText, "TOPLEFT", -6, 4)
    typeCatcher:SetPoint("BOTTOMRIGHT", f.StackSplitText, "BOTTOMRIGHT", 6, -4)
    typeCatcher:Show()
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
        merchantOwner, merchantStack = nil, nil
        if not QoL.mod.active then return end
        raiseForMerchant(self)
        syncMaxButton()
        syncTypeBox()
        applySkin(db().skin)
    end)
    if f.UpdateStackSplitFrame then
        hooksecurefunc(f, "UpdateStackSplitFrame", function()
            if QoL.mod.active then syncMaxButton(); syncTypeBox() end
        end)
    end
    hooked = true
end

-- ----------------------------------------------------------- apply --

function Split.Apply()
    if not frame() then return end
    ensureHooks()
    syncMaxButton()
    syncTypeBox()
    applySkin(db().skin)
end

function Split.Disable()
    stopBuying()
    merchantOwner, merchantStack = nil, nil
    if maxButton then maxButton:Hide() end
    closeBox()
    if typeCatcher then typeCatcher:Hide() end
    applySkin(false)
end
