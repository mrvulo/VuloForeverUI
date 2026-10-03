-- VuloForeverUI / UI / EditMode / Interact: click-to-pick anchoring, group drag/nudge and the reject flash.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent
local EM = ns._EM
local refreshDim = EM.refreshDim

-- Click-to-pick anchoring: BeginAnchorPick arms it from the panel, then the next
-- mover the user clicks becomes this frame's anchor target (see Core/Mover/Drag.lua handlers).
local pickHint
function ns:IsAnchorPicking() return ns._anchorPick ~= nil end

-- The screen visibly darkens while picking, so it reads as a distinct mode.
-- Picking an anchor target dims harder, so the box you are about to click
-- stands out. Letting go returns to whatever the DARKENING SETTING says --
-- restoring a fixed 0.35 would switch the darkening back on behind the back of
-- a player who turned it off.
local function setPickDim(on)
    if not (EM.dim and EM.dim.fill) then return end
    if on then
        EM.dim.fill:SetColorTexture(0, 0, 0, 0.6)
    else
        refreshDim()
    end
end

function ns:BeginAnchorPick(child)
    if not (child and child.key and ns:IsEditModeActive()) then return end
    ns._anchorPick = child
    setPickDim(true)
    if not pickHint and EM.dim then
        pickHint = EM.dim:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pickHint:SetPoint("TOP", UIParent, "TOP", 0, -230)
        pickHint:SetTextColor(accent.r, accent.g, accent.b)
    end
    if pickHint then
        pickHint:SetText(L["Click a window to anchor it (right-click to cancel)."])
        pickHint:Show()
    end
end

function ns:CancelAnchorPick()
    ns._anchorPick = nil
    setPickDim(false)
    if pickHint then pickHint:Hide() end
end

function ns:AnchorPickPick(targetMover)
    local child = ns._anchorPick
    ns:CancelAnchorPick()
    if not (child and targetMover) then return end
    if targetMover == child or not targetMover.key then return end
    if ns:SetMoverLink(child, targetMover.key) then
        ns:OnMoverRepositioned(targetMover)   -- settle the child onto its new anchor
    else
        ns:FlashMoverReject(targetMover, L["Not possible - that would create a loop."])
    end
    if ns._selectedMover == child then ns:RelayoutEditPanel() end
end

-- Only the leader snaps; followers keep their relative offset so the group stays rigid.
function ns:BeginGroupDrag(leader)
    ns._groupDrag = nil
    if #ns._selection <= 1 or not (leader and ns:IsSelected(leader) and leader.target) then return end
    -- Captures are in each owning frame's local space, or a scaled follower teleports on the first tick.
    local followers = {}
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.target then
            local x, y = ns:GetCenterOffsets(m.target)
            if x and y then
                followers[#followers + 1] = { mover = m, x = x, y = y }
            end
        end
    end
    if #followers == 0 then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    ns._groupDrag = { lx = lx, ly = ly, followers = followers }
end

function ns:UpdateGroupDrag()
    local gd = ns._groupDrag
    local leader = ns._draggingMover
    if not (gd and leader and leader.target) then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    local dx, dy = lx - gd.lx, ly - gd.ly
    local lscale = leader.target:GetEffectiveScale() or 1
    for _, f in ipairs(gd.followers) do
        local t = f.mover.target
        -- Convert the delta into this follower's space so a scaled frame tracks the leader 1:1 on screen.
        local conv = lscale / (t:GetEffectiveScale() or 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "CENTER", f.x + dx * conv, f.y + dy * conv)
    end
end

-- sdx/sdy is the snap correction the leader took, reapplied so the group keeps its arrangement.
function ns:EndGroupDrag(sdx, sdy)
    local gd = ns._groupDrag
    ns._groupDrag = nil
    if not gd then return end
    sdx, sdy = sdx or 0, sdy or 0
    for _, f in ipairs(gd.followers) do
        local x, y = ns:GetCenterOffsets(f.mover.target)
        if x and y then
            ns:MoverSetCenter(f.mover, x + sdx, y + sdy)
        end
    end
end

function ns:NudgeGroupFollowers(leader, dx, dy)
    if #ns._selection <= 1 or not ns:IsSelected(leader) then return end
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.opts and m.opts.db then
            m.opts.db.x = (m.opts.db.x or 0) + dx
            m.opts.db.y = (m.opts.db.y or 0) + dy
            ns:ApplyMover(m)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Rejection feedback: a refused action (loop, self-anchor) flashes the offending
-- box red and floats the reason at the cursor. A chat line is too easy to miss
-- while you are looking at the window you just clicked.

local rejectDriver, rejectHint

local function ensureReject()
    if rejectDriver then return end
    rejectDriver = CreateFrame("Frame", nil, UIParent)
    rejectDriver:Hide()
    rejectHint = rejectDriver:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(rejectHint, 12)
    rejectHint:SetTextColor(1, 0.35, 0.3)
    rejectDriver:SetFrameStrata("TOOLTIP")
    rejectDriver:SetAllPoints(UIParent)
end

function ns:FlashMoverReject(mover, text)
    ensureReject()
    local until_ = GetTime() + 2.0
    if mover and mover.border and mover.border.SetBackdropBorderColor then
        mover._rejectUntil = until_
    end
    rejectHint:SetText(text or "")
    rejectDriver:Show()
    rejectDriver:SetScript("OnUpdate", function(self)
        local left = until_ - GetTime()
        if left <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if mover then mover._rejectUntil = nil end
            if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
            return
        end
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if cx and s and s > 0 then
            rejectHint:ClearAllPoints()
            rejectHint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                cx / s + 18, cy / s + 18)
        end
        rejectHint:SetAlpha(math.min(1, left / 0.6))
        if mover and mover.border and mover.border.SetBackdropBorderColor then
            local p = 0.5 + 0.5 * math.abs(math.sin(GetTime() * 10))
            mover.border:SetBackdropBorderColor(1, 0.2, 0.15, p)
        end
    end)
end
