-- VuloForeverUI / Modules / QoL / StackSplit
--
-- Two additions to the client's own "split a stack" popup: a button that takes
-- the whole stack, and our look instead of the money-frame art.
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
            lines = { L["Take the whole stack."] } })
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
    local on = db().maxButton and (tonumber(f.maxStack) or 0) > 1
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
    hooksecurefunc(f, "OpenStackSplitFrame", function()
        if not QoL.mod.active then return end
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
    if maxButton then maxButton:Hide() end
    applySkin(false)
end
