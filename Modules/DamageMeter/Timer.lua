-- VuloForeverUI / Modules / DamageMeter / Timer
--
-- The standalone combat timer: the fight's length on its own, away from the
-- window headers. It reads the same duration the headers do, so the two can
-- never disagree.
--
-- The tenths are display smoothing only. The client reports whole seconds, so
-- a GetTime() anchor is re-set whenever the reported second changes and the
-- fraction is clamped below one; it cannot run ahead of the real value.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local Timer = {}
DM.Timer = Timer

local frame, text
local decimalTicker
local lastWhole, anchor = nil, 0
local previewing = false

local function tdb() return DM.db().timer end

local function build()
    if frame then return frame end
    frame = CreateFrame("Frame", "VuloForeverUIMeterCombatTimer", UIParent)
    frame:SetSize(90, 30)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:SetDontSavePosition(true)
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text = text
    Timer.frame = frame

    -- Shift and drag moves it, which also puts the anchor back to free.
    frame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not IsShiftKeyDown() or tdb().locked then return end
        self:StartMoving()
        self.moving = true
    end)
    frame:SetScript("OnMouseUp", function(self)
        if not self.moving then return end
        self.moving = false
        self:StopMovingOrSizing()
        local t = tdb()
        t.anchor = "free"
        t.pos = { x = self:GetLeft(), y = self:GetTop() }
        Timer.Apply()
    end)
    frame:SetScript("OnEnter", function(self)
        if tdb().locked then return end
        UI:ShowTooltip(self, { title = L["Combat timer"], lines = { L["Hold Shift and drag to move it."] } })
    end)
    frame:SetScript("OnLeave", function() UI:HideTooltip() end)
    return frame
end

-- Free, or pinned to a corner of the topmost or bottommost visible window.
local function applyPosition()
    local t = tdb()
    frame:ClearAllPoints()
    local mode = t.anchor or "free"
    if mode == "free" then
        local p = t.pos
        if type(p) == "table" and p.x and p.y then
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
        else
            local W = DM.windows[1]
            if W and W.frame:GetTop() then
                frame:SetPoint("BOTTOMRIGHT", W.frame, "TOPRIGHT", 0, 5)
            else
                frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        end
        return
    end
    local top, bottom
    for _, W in ipairs(DM.windows) do
        if W.frame:IsShown() and W.frame:GetTop() then
            if not top or W.frame:GetTop() > top.frame:GetTop() then top = W end
            if not bottom or W.frame:GetBottom() < bottom.frame:GetBottom() then bottom = W end
        end
    end
    local target = (mode == "topleft" or mode == "topright") and top or bottom
    if not target then
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        return
    end
    if mode == "topleft" then
        frame:SetPoint("BOTTOMLEFT", target.frame, "TOPLEFT", 0, 4)
    elseif mode == "topright" then
        frame:SetPoint("BOTTOMRIGHT", target.frame, "TOPRIGHT", 0, 4)
    elseif mode == "bottomleft" then
        frame:SetPoint("TOPLEFT", target.frame, "BOTTOMLEFT", 0, -4)
    else
        frame:SetPoint("TOPRIGHT", target.frame, "BOTTOMRIGHT", 0, -4)
    end
end

-- Grey while idle: the configured colour's own luminance, so any colour keeps
-- its brightness.
local function idleColor(r, g, b)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    return lum, lum, lum
end

function Timer.Update()
    if not frame or not frame:IsShown() then return end
    local t = tdb()
    local W = DM.windows[1]
    local d = W and DM.ViewDuration(W) or DM.frozenDur
    if type(d) ~= "number" then d = 0 end

    if t.decimal and (DM.inCombat or DM.needsFinal) then
        local whole = math.floor(d)
        if whole ~= lastWhole then
            lastWhole = whole
            anchor = GetTime()
        end
        local frac = math.min(0.9, GetTime() - anchor)
        text:SetText(DM.FormatTimerDecimal(whole + frac))
    else
        text:SetText(t.decimal and DM.FormatTimerDecimal(d) or DM.FormatTimer(d))
    end

    local r, g, b
    if t.useAccent then r, g, b = DM.Accent() else r, g, b = t.color.r, t.color.g, t.color.b end
    if not (DM.inCombat or DM.needsFinal) and t.desatOOC then r, g, b = idleColor(r, g, b) end
    text:SetTextColor(r, g, b)
end

local function startDecimalTicker()
    if decimalTicker or not tdb().decimal then return end
    decimalTicker = ns:AddTicker(0.1, Timer.Update, nil, "meter timer tenths")
end

local function stopDecimalTicker()
    if decimalTicker then ns:CancelTicker(decimalTicker); decimalTicker = nil end
end

function Timer.UpdateVisibility()
    if not frame then return end
    local t = tdb()
    if not t.enabled then frame:Hide(); stopDecimalTicker(); return end
    if previewing or DM.optionsOpen or ns:IsEditModeActive() then
        frame:Show(); Timer.Update(); return
    end
    if DM.toggleHidden and DM.db().toggleIncludeTimer then
        frame:Hide(); stopDecimalTicker(); return
    end
    local show = DM.inCombat or DM.needsFinal or t.showOOC
    frame:SetShown(show)
    if show then
        Timer.Update()
        if DM.inCombat or DM.needsFinal then startDecimalTicker() else stopDecimalTicker() end
    else
        stopDecimalTicker()
    end
end

function Timer.Apply()
    local t = tdb()
    if not t.enabled and not frame then return end
    build()
    local flags = t.outline
    if flags == "INHERIT" then flags = nil end
    DM.Font(text, t.size or 26, flags)
    text:SetJustifyH(t.alignLeft and "LEFT" or "CENTER")
    frame:SetFrameStrata(t.strata or "HIGH")
    -- Sized for the longest string it can show, so a corner anchor does not
    -- jump when the text grows.
    local probe = t.decimal and "99:99.9" or "99:99"
    text:SetText(probe)
    frame:SetSize(math.max(40, (text:GetStringWidth() or 60) + 10), (t.size or 26) + 6)
    frame:EnableMouse(not t.locked)
    applyPosition()
    Timer.UpdateVisibility()
end

function Timer.Hide()
    if frame then frame:Hide() end
    stopDecimalTicker()
end

-- The options page shows it while the page is open, with a stand-in time.
function Timer.ShowPreview()
    build()
    previewing = true
    Timer.Apply()
    frame:Show()
    text:SetText(tdb().decimal and "11:37.0" or "11:37")
end

function Timer.HidePreview()
    previewing = false
    Timer.UpdateVisibility()
end
