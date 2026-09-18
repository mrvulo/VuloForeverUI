-- VuloForeverUI / Modules / UnitFramesClassicCastBar
--
-- The target and focus cast bar in the Classic style: a port of the second
-- reference's cast bar skin (its boss bars are not part of this round).
--
-- Checked against Forever's source:
--   Blizzard_UnitFrame/Mainline/TargetFrame.lua  :697 CreateSpellbar sets
--     frame.spellbar, :822 TargetSpellBarMixin:AdjustPosition (one TOPLEFT
--     anchor, to the frame or to its aura container)
--   Blizzard_UIPanels_Game/Mainline/CastingBarFrame.xml  :399
--     SmallCastingBarFrameTemplate -- :403 TextBorder, :409 Background,
--     :415 BorderShield, :423 Icon, :431 Border, :437 Spark, :443 Flash,
--     :449 Text; FadeOutAnim from Shared/CastingBarFrameTemplates.xml:5
--   Blizzard_UIPanels_Game/Shared/CastingBarFrame.lua  :294 UpdateShownState,
--     :541 HandleInterruptOrSpellFailed, :640 UpdateBarFillTexture,
--     :721 PlayInterruptAnims, :774 PlayFinishAnim. In HandleCastStart the
--     spark's atlas is set (:392) BEFORE UpdateShownState (:435), so the
--     reference's hook point does see the last word. SetLook (:1022) is never
--     called again for a target bar, so the look is set once.
--
-- Differences from the reference:
--   * its UpdateShownState hook creates a new Alpha animation on FadeOutAnim
--     on EVERY call -- a leak, and a fade that gets faster all evening. Here
--     the animation is created once per bar;
--   * its finish flash is created inside the PlayFinishAnim hook, which can
--     fire in combat; here it is created once, up front;
--   * its position offset is AdjustPointsOffset from two hooks (AdjustPosition
--     and OnShow), which adds up when both fire for one anchor. Here the
--     wanted anchor is absolute and remembered, so it is applied once;
--   * the spark is switched with alpha instead of Hide(), and its anchor is
--     left alone: CastingBarMixin:OnUpdate re-anchors it every frame anyway;
--   * the focus bar gets the position offset too (the reference only hooks
--     the target's bar, the two frames share their geometry).
local _, ns = ...
local UF = ns.UF
local Classic = UF.Classic

local BAR = Classic.BAR

local COLOR = {
    Standard        = CreateColor(1, 0.7, 0, 1),
    Channel         = CreateColor(0, 1, 0, 1),
    Uninterruptable = CreateColor(0.7, 0.7, 0.7, 1),
    Interrupted     = CreateColor(1, 0, 0, 1),
}

------------------------------------------------------------------------------
-- Position
------------------------------------------------------------------------------

-- GetPoint on a Blizzard region can answer with secrets on this client; an
-- anchor we cannot read is left where Blizzard put it.
local function adjustPosition(bar)
    local parent = bar:GetParent()
    local point, rel, relPoint, x, y = bar:GetPoint()
    if not (ns.CanRead(point) and ns.CanRead(rel) and ns.CanRead(relPoint)
        and ns.CanRead(x) and ns.CanRead(y)) then
        return
    end
    if not point then return end
    local s = Classic.State(bar)
    if s.rel == rel and s.x == x and s.y == y then return end   -- already ours

    local dy
    if rel == parent then
        if parent.haveToT then
            dy = 22
        elseif Classic.HaveElite and Classic.HaveElite(parent) then
            dy = -14
        else
            dy = -2
        end
    else
        dy = -5
    end
    local wantX, wantY = x + 2, y + dy
    Classic.Layout("castbar.position." .. tostring(bar.unit), function()
        bar:ClearAllPoints()
        bar:SetPoint(point, rel, relPoint, wantX, wantY)
        s.rel, s.x, s.y = rel, wantX, wantY
    end)
end

------------------------------------------------------------------------------
-- Look (reference: its SetLook), and what it creates inside hooks
------------------------------------------------------------------------------

local function paintSpark(bar)
    local spark = bar.Spark
    if not spark then return end
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetBlendMode("ADD")
    spark:SetAlpha(bar.channeling and 0 or 1)
end

local function setup(bar)
    local s = Classic.State(bar)
    if s.isSetUp then return end
    s.isSetUp = true

    Classic.Guard("castbar.paint", function()
        bar.Background:SetColorTexture(0, 0, 0, 0.5)
        bar.Border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
        bar.BorderShield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
        if bar.TextBorder then bar.TextBorder:SetAlpha(0) end
        paintSpark(bar)
    end)

    Classic.Guard("castbar.fade", function()
        local anim = bar.FadeOutAnim:CreateAnimation("Alpha")
        anim:SetDuration(0.2)
        anim:SetFromAlpha(1)
        anim:SetToAlpha(0)
    end)

    Classic.Guard("castbar.flash", function()
        local flash = bar:CreateTexture(nil, "OVERLAY")
        flash:SetSize(0, 49)
        flash:SetTexture("Interface\\CastingBar\\UI-CastingBar-Flash-Small")
        flash:SetPoint("TOPLEFT", -23, 20)
        flash:SetPoint("TOPRIGHT", 23, 20)
        flash:SetBlendMode("ADD")
        flash:SetAlpha(0)
        local group = flash:CreateAnimationGroup()
        group:SetToFinalAlpha(true)
        local anim = group:CreateAnimation("Alpha")
        anim:SetDuration(0.2)
        anim:SetFromAlpha(1)
        anim:SetToAlpha(0)
        s.flash, s.flashAnim = flash, group
    end)

    Classic.Layout("castbar.layout." .. tostring(bar.unit), function()
        bar.Border:SetWidth(0)
        bar.Border:SetHeight(49)
        bar.Border:ClearAllPoints()
        bar.Border:SetPoint("TOPLEFT", -23, 20)
        bar.Border:SetPoint("TOPRIGHT", 23, 20)

        bar.BorderShield:SetWidth(0)
        bar.BorderShield:SetHeight(49)
        bar.BorderShield:ClearAllPoints()
        bar.BorderShield:SetPoint("TOPLEFT", -28, 20)
        bar.BorderShield:SetPoint("TOPRIGHT", 18, 20)

        bar.Text:SetWidth(0)
        bar.Text:SetHeight(16)
        bar.Text:ClearAllPoints()
        bar.Text:SetPoint("TOPLEFT", 0, 4)
        bar.Text:SetPoint("TOPRIGHT", 0, 4)

        bar.Icon:ClearAllPoints()
        bar.Icon:SetPoint("RIGHT", bar, "LEFT", -5, 0)
        bar.Icon:SetSize(16, 16)

        if bar.Spark then bar.Spark:SetSize(32, 32) end
    end)
end

------------------------------------------------------------------------------
-- Fill colour. SetVertexColorFromBoolean takes the (possibly secret)
-- notInterruptible flag as it comes; only the spell NAME is tested, to tell a
-- cast from a channel, and only when it is readable. A name the client keeps
-- secret still says which of the two is running: an idle unit answers nil,
-- which is readable.
------------------------------------------------------------------------------

local function paintFill(bar, isFull)
    bar:SetStatusBarTexture(BAR)
    local tex = bar:GetStatusBarTexture()
    if not tex then return end
    local unit = bar.unit
    if unit and tex.SetVertexColorFromBoolean then
        local name, _, _, _, _, _, _, castLocked = UnitCastingInfo(unit)
        local channel, _, _, _, _, _, channelLocked = UnitChannelInfo(unit)
        local nameOpen, channelOpen = ns.CanRead(name), ns.CanRead(channel)
        if nameOpen and name then
            tex:SetVertexColorFromBoolean(castLocked, COLOR.Uninterruptable, COLOR.Standard)
        elseif channelOpen and channel then
            tex:SetVertexColorFromBoolean(channelLocked, COLOR.Uninterruptable, COLOR.Channel)
        elseif not nameOpen then
            tex:SetVertexColorFromBoolean(castLocked, COLOR.Uninterruptable, COLOR.Standard)
        elseif not channelOpen then
            tex:SetVertexColorFromBoolean(channelLocked, COLOR.Uninterruptable, COLOR.Channel)
        end
    end
    if isFull then tex:SetVertexColor(COLOR.Channel:GetRGBA()) end
end

------------------------------------------------------------------------------
-- Part
------------------------------------------------------------------------------

local bars = setmetatable({}, { __mode = "k" })

local function hookBar(bar, method, key, fn)
    if type(bar[method]) ~= "function" then return end
    hooksecurefunc(bar, method, function(self, ...)
        if not Classic.IsActive() or not bars[self] then return end
        Classic.Guard(key, fn, self, ...)
    end)
end

local function installBar(bar)
    if not bar then return end

    hookBar(bar, "AdjustPosition", "castbar.position", adjustPosition)
    bar:HookScript("OnShow", function(self)
        if not Classic.IsActive() or not bars[self] then return end
        Classic.Guard("castbar.position", adjustPosition, self)
    end)

    hookBar(bar, "HandleInterruptOrSpellFailed", "castbar.text", function(self, _, event)
        if not self.Text then return end
        if event == "UNIT_SPELLCAST_FAILED" then
            self.Text:SetText(FAILED)
        else
            self.Text:SetText(INTERRUPTED)
        end
    end)

    hookBar(bar, "UpdateShownState", "castbar.spark", paintSpark)

    hookBar(bar, "PlayInterruptAnims", "castbar.interrupt", function(self)
        local tex = self:GetStatusBarTexture()
        if tex then tex:SetVertexColor(COLOR.Interrupted:GetRGBA()) end
        self:SetValue(self.maxValue)
        if self.Spark then self.Spark:SetAlpha(0) end
    end)

    hookBar(bar, "PlayFinishAnim", "castbar.finish", function(self)
        local s = Classic.State(self)
        if not s.flash then return end
        s.flashAnim:Play()
        s.flash:SetVertexColor(self:GetStatusBarColor())
    end)

    hookBar(bar, "UpdateBarFillTexture", "castbar.fill", paintFill)
end

local function spellbars()
    return { _G.TargetFrame and _G.TargetFrame.spellbar, _G.FocusFrame and _G.FocusFrame.spellbar }
end

Classic.RegisterPart({
    name = "castbar",

    install = function()
        local list = spellbars()
        for i = 1, 2 do installBar(list[i]) end
    end,

    enable = function()
        local list = spellbars()
        for i = 1, 2 do
            local bar = list[i]
            if bar then
                bars[bar] = true
                setup(bar)
                Classic.Guard("castbar.position", adjustPosition, bar)
            end
        end
    end,
})
