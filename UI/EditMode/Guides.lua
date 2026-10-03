-- VuloForeverUI / UI / EditMode / Guides: alignment guides, gap readout, connector lines, magnetism, overlap cycling.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent
local EM = ns._EM
local gridState = EM.gridState
local snapKinds = EM.snapKinds

local function snapVal(v, size)
    if not size or size <= 0 then return v end
    return math.floor(v / size + 0.5) * size
end

local guideFrame, guidePool = nil, {}
local function ensureGuideFrame()
    if guideFrame then return end
    guideFrame = CreateFrame("Frame", "VFUIEditGuides", UIParent)
    guideFrame:SetAllPoints(UIParent)
    guideFrame:SetFrameStrata("DIALOG")   -- above the mover boxes (HIGH)
    guideFrame:EnableMouse(false)
end
local measurePool = {}
local function hideMeasures()
    for _, t in ipairs(measurePool) do t:Hide() end
end
local function hideGuides()
    for _, t in ipairs(guidePool) do t:Hide() end
    hideMeasures()
end
ns._hideGuides = hideGuides
local function drawGuides(gx, gy, persist)
    ensureGuideFrame()
    hideGuides()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local i = 0
    local function gtex()
        i = i + 1
        local t = guidePool[i]
        if not t then t = guideFrame:CreateTexture(nil, "OVERLAY"); guidePool[i] = t end
        t:ClearAllPoints()
        t:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
        return t
    end
    if gx then
        local t = gtex(); t:SetWidth(2)
        local sx = w / 2 + gx
        t:SetPoint("TOP",    guideFrame, "TOPLEFT",    sx, 0)
        t:SetPoint("BOTTOM", guideFrame, "BOTTOMLEFT", sx, 0)
        t:Show()
    end
    if gy then
        local t = gtex(); t:SetHeight(2)
        local sy = h / 2 + gy
        t:SetPoint("LEFT",  guideFrame, "BOTTOMLEFT",  0, sy)
        t:SetPoint("RIGHT", guideFrame, "BOTTOMRIGHT", 0, sy)
        t:Show()
    end
    if not persist and (gx or gy) and C_Timer and C_Timer.After then
        C_Timer.After(0.5, hideGuides)
    end
end

-- frame centre + half-extents as offsets from the screen centre, in UIParent units
local function boxUI(frame)
    local cx, cy = ns:GetCenterOffsets(frame)
    if not cx then return nil end
    local r = ns.GetScaleRatio and ns:GetScaleRatio(frame) or 1
    return cx * r, cy * r,
           (frame:GetWidth()  or 0) / 2 * r,
           (frame:GetHeight() or 0) / 2 * r
end

-- Distance readout: for each active alignment guide, label the edge-to-edge gap
-- between the dragged frame and the partner frame it lined up with.
local function drawMeasures(mover, moverX, moverY)
    hideMeasures()
    if not (mover and mover.target) then return end
    if not (moverX or moverY) then return end
    ensureGuideFrame()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local acx, acy, ahw, ahh = boxUI(mover.target)
    if not acx then return end
    local n = 0
    local function mtex()
        n = n + 1
        local t = measurePool[n]
        if not t then
            t = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            UI.Font(t, 11)
            measurePool[n] = t
        end
        t:ClearAllPoints()
        t:SetTextColor(accent.r, accent.g, accent.b)
        return t
    end
    -- vertical guide (shared X) -> vertical gap to the partner
    if moverX and moverX.target then
        local bcx, bcy, _, bhh = boxUI(moverX.target)
        if bcx then
            local gap = math.abs(acy - bcy) - (ahh + bhh)
            local t = mtex()
            t:SetText(tostring(math.floor(gap + 0.5)))
            t:SetPoint("CENTER", guideFrame, "BOTTOMLEFT", w / 2 + acx + 14, h / 2 + (acy + bcy) / 2)
            t:Show()
        end
    end
    -- horizontal guide (shared Y) -> horizontal gap to the partner
    if moverY and moverY.target then
        local bcx, _, bhw = boxUI(moverY.target)
        if bcx then
            local gap = math.abs(acx - bcx) - (ahw + bhw)
            local t = mtex()
            t:SetText(tostring(math.floor(gap + 0.5)))
            t:SetPoint("CENTER", guideFrame, "BOTTOMLEFT", w / 2 + (acx + bcx) / 2, h / 2 + acy + 14)
            t:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Anchor connector lines: every window pinned to another draws a line to it,
-- with a pulse travelling child -> parent so the direction of the link is
-- obvious. Only drawn for windows you are touching, or the screen turns into a
-- spider web the moment more than a couple of links exist.

local linkFrame, linePool, dotPool = nil, {}, {}
local LINK_CYCLE = 2.0    -- seconds per pulse
local LINK_SWEEP = 0.6    -- share of the cycle the pulse is actually moving

local function ensureLinkFrame()
    if linkFrame then return end
    linkFrame = CreateFrame("Frame", "VFUIEditLinks", UIParent)
    linkFrame:SetAllPoints(UIParent)
    linkFrame:SetFrameStrata("MEDIUM")   -- above the dim, below the mover boxes
    linkFrame:SetFrameLevel(20)
    linkFrame:EnableMouse(false)
end

-- frame centre in UIParent units, measured from the screen's bottom-left
local function uiCenter(f)
    if not (f and f.GetCenter) then return nil end
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then return nil end
    local s = (f:GetEffectiveScale() or 1) / us
    return cx * s, cy * s
end

local function hideLinks()
    for _, l in ipairs(linePool) do l:Hide() end
    for _, d in ipairs(dotPool) do d:Hide() end
end

local function drawLinks()
    ensureLinkFrame()
    hideLinks()
    if not ns:IsEditModeActive() then return end
    local now  = GetTime()
    local used = 0
    for _, child in ipairs(ns._movers) do
        local link = child.key and ns:GetMoverLink(child.key)
        if link and child:IsShown() then
            local parent = ns:GetMoverByKey(link.to)
            if parent and parent.target and parent:IsShown() then
                local touched = child == ns._activeMover or parent == ns._activeMover
                    or child == ns._draggingMover or parent == ns._draggingMover
                    or ns:IsSelected(child) or ns:IsSelected(parent)
                local cx, cy = uiCenter(child.target)
                local px, py = uiCenter(parent.target)
                if touched and cx and px then
                    used = used + 1
                    local line = linePool[used]
                    if not line then
                        line = linkFrame:CreateLine(nil, "ARTWORK")
                        line:SetThickness(2)
                        linePool[used] = line
                    end
                    line:ClearAllPoints()
                    line:SetStartPoint("CENTER", child.target)
                    line:SetEndPoint("CENTER", parent.target)
                    line:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
                    line:Show()

                    local dot = dotPool[used]
                    if not dot then
                        dot = linkFrame:CreateTexture(nil, "OVERLAY")
                        dot:SetSize(7, 7)
                        dot:SetBlendMode("ADD")
                        dotPool[used] = dot
                    end
                    -- ease the pulse across the line, then rest for the remainder
                    local phase = (now % LINK_CYCLE) / LINK_CYCLE
                    if phase <= LINK_SWEEP then
                        local t = phase / LINK_SWEEP
                        t = t * t * (3 - 2 * t)          -- smoothstep
                        local a = math.min(1, math.min(t, 1 - t) * 6)
                        dot:SetColorTexture(accent.r, accent.g, accent.b, 0.9 * a)
                        dot:ClearAllPoints()
                        dot:SetPoint("CENTER", linkFrame, "BOTTOMLEFT",
                            cx + (px - cx) * t, cy + (py - cy) * t)
                        dot:Show()
                    end
                end
            end
        end
    end
end
ns._hideLinks = hideLinks

local MAG_THRESH = 12

-- Math runs in UIParent units (where guides are drawn); returned dx/dy convert back to frame-local, lineX/lineY stay UI-space.
-- Scratch buffers, reused across calls. This runs EVERY FRAME for as long as a
-- window is being dragged, and it used to build six fresh tables per other
-- mover plus two feature tables and a closure -- roughly 300 short-lived tables
-- per frame at 50 windows, in a Lua that collects incrementally, precisely
-- while the user is judging whether the drag feels smooth. Values and lines are
-- kept in two parallel flat arrays with an explicit count, so nothing is
-- allocated after the first drag warms them up.
local _xv, _xm, _yv, _ym = {}, {}, {}, {}
local _feat = {}

local function bestLine(nFeat, vals, owners, n)
    local bd, bl, bm
    for i = 1, nFeat do
        local f = _feat[i]
        for j = 1, n do
            local d = vals[j] - f
            if math.abs(d) <= MAG_THRESH and (not bd or math.abs(d) < math.abs(bd)) then
                bd, bl, bm = d, vals[j], owners[j]
            end
        end
    end
    return bd, bl, bm
end

local function computeSnap(mover, x, y)
    local target = mover.target
    if not target then return end
    local r = ns.GetScaleRatio and ns:GetScaleRatio(target) or 1
    local xu, yu = x * r, y * r
    local hw = (target:GetWidth()  or 0) / 2 * r
    local hh = (target:GetHeight() or 0) / 2 * r

    -- each candidate line carries its owning mover (nil = the screen-centre line)
    _xv[1], _xm[1] = 0, nil
    _yv[1], _ym[1] = 0, nil
    local nx, ny = 1, 1
    for _, o in ipairs(ns._movers) do
        if o ~= mover and o.target and o:IsShown() then
            local ox, oy = ns:GetCenterOffsets(o.target)
            if ox and oy then
                local orr = ns.GetScaleRatio and ns:GetScaleRatio(o.target) or 1
                local ocx, ocy = ox * orr, oy * orr
                local ohw = (o.target:GetWidth()  or 0) / 2 * orr
                local ohh = (o.target:GetHeight() or 0) / 2 * orr
                _xv[nx + 1], _xm[nx + 1] = ocx,       o
                _xv[nx + 2], _xm[nx + 2] = ocx - ohw, o
                _xv[nx + 3], _xm[nx + 3] = ocx + ohw, o
                nx = nx + 3
                _yv[ny + 1], _ym[ny + 1] = ocy,       o
                _yv[ny + 2], _ym[ny + 2] = ocy - ohh, o
                _yv[ny + 3], _ym[ny + 3] = ocy + ohh, o
                ny = ny + 3
            end
        end
    end

    _feat[1], _feat[2], _feat[3] = xu - hw, xu, xu + hw
    local dx, lineX, moverX = bestLine(3, _xv, _xm, nx)
    _feat[1], _feat[2], _feat[3] = yu - hh, yu, yu + hh
    local dy, lineY, moverY = bestLine(3, _yv, _ym, ny)
    if dx then dx = dx / r end
    if dy then dy = dy / r end
    return dx, lineX, dy, lineY, moverX, moverY
end

function ns:EditResolveDrop(mover, x, y)
    local g = gridState()
    local useElements, useGrid = snapKinds(g)
    local t = mover.target
    local r = (ns.GetScaleRatio and t) and ns:GetScaleRatio(t) or 1
    local dx, lineX, dy, lineY
    if useElements then dx, lineX, dy, lineY = computeSnap(mover, x, y) end
    if dx then x = x + dx elseif useGrid then x = snapVal(x * r, g.size) / r end
    if dy then y = y + dy elseif useGrid then y = snapVal(y * r, g.size) / r end
    -- Pixel grid is the last resort only: an edge snap already sits exactly on
    -- the neighbour's edge and a grid snap on its line, so re-rounding either
    -- would nudge it a pixel off the thing it was just aligned to.
    if t then
        if not dx and not useGrid then x = ns:PixelSnapCenter(x, t:GetWidth() or 0, t) end
        if not dy and not useGrid then y = ns:PixelSnapCenter(y, t:GetHeight() or 0, t) end
    end
    drawGuides(dx and lineX or nil, dy and lineY or nil)
    return x, y
end

-- The box being snapped AGAINST lights up with a white pulse, so the guide
-- line reads as "aligned to THAT window" instead of a free-floating stripe.
-- RefreshMoverStyles restores whatever border this painted over, both when the
-- partner changes mid-drag and when the drag ends.
local lastPartnerX, lastPartnerY

local function tintPartner(p, a)
    if p and p.border and p.border.SetBackdropBorderColor
       and not (p._rejectUntil and p._rejectUntil > GetTime()) then
        p.border:SetBackdropBorderColor(1, 1, 1, a)
    end
end

-- Purely visual preview; the actual snap still happens on drop.
local liveGuideDriver = CreateFrame("Frame")
liveGuideDriver:SetScript("OnUpdate", function()
    local m = ns._draggingMover
    if not (m and m.target and ns:IsEditModeActive()) then
        if lastPartnerX or lastPartnerY then
            lastPartnerX, lastPartnerY = nil, nil
            ns:RefreshMoverStyles()
        end
        return
    end
    if ns._groupDrag then ns:UpdateGroupDrag() end
    local lx, ly = ns:GetCenterOffsets(m.target)
    if not lx then return end
    local dx, lineX, dy, lineY, moverX, moverY = computeSnap(m, lx, ly)
    drawGuides(dx and lineX or nil, dy and lineY or nil, true)
    drawMeasures(m, dx and moverX or nil, dy and moverY or nil)

    local px = dx and moverX or nil
    local py = dy and moverY or nil
    if px ~= lastPartnerX or py ~= lastPartnerY then
        lastPartnerX, lastPartnerY = px, py
        ns:RefreshMoverStyles()
    end
    if px or py then
        local a = 0.55 + 0.45 * math.abs(math.sin(GetTime() * 5))
        tintPartner(px, a)
        if py ~= px then tintPartner(py, a) end
    end
end)

local cycleHint, altWasDown
local function ensureCycleHint()
    ensureGuideFrame()
    if cycleHint then return end
    cycleHint = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(cycleHint, 12)
    cycleHint:SetTextColor(accent.r, accent.g, accent.b)
    cycleHint:Hide()
end
local function updateCycle()
    if not ns:IsEditModeActive() then
        if cycleHint then cycleHint:Hide() end
        altWasDown = false
        return
    end
    local list = {}
    for _, m in ipairs(ns._movers) do
        if m:IsShown() and m:IsMouseOver() then list[#list + 1] = m end
    end
    local altDown = IsAltKeyDown() and true or false
    if #list > 1 then
        ensureCycleHint()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if cx and s and s > 0 then
            cycleHint:ClearAllPoints()
            cycleHint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 16, cy / s + 16)
            cycleHint:SetText(string.format(L["%d frames here - hold Alt to cycle"], #list))
            cycleHint:Show()
        end
        if altDown and not altWasDown then
            table.sort(list, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)
            list[1]:Raise()
        end
    elseif cycleHint then
        cycleHint:Hide()
    end
    altWasDown = altDown
end

local cycleDriver = CreateFrame("Frame")
local cycleAcc = 0
cycleDriver:SetScript("OnUpdate", function(_, elapsed)
    cycleAcc = cycleAcc + elapsed
    if cycleAcc < 0.15 then return end
    cycleAcc = 0
    updateCycle()
end)

-- Connector lines need their own, faster clock: the pulse has to look smooth.
local linkDriver = CreateFrame("Frame")
local linkAcc = 0
linkDriver:SetScript("OnUpdate", function(_, elapsed)
    if not ns:IsEditModeActive() then return end
    linkAcc = linkAcc + elapsed
    if linkAcc < 0.03 then return end
    linkAcc = 0
    drawLinks()
end)

-- All three drivers only ever have work while the editor is open -- each one's
-- body starts by checking exactly that -- yet they were installed at file load
-- and paid the per-frame call for the whole session regardless. A hidden frame
-- runs no OnUpdate at all (Blizzard parks its own state-driver manager the same
-- way), so the editor toggle now parks them and the idle cost drops to zero.
local DRIVERS = { liveGuideDriver, cycleDriver, linkDriver }
for _, d in ipairs(DRIVERS) do d:Hide() end
ns:RegisterEditModeHook(function(state)
    for _, d in ipairs(DRIVERS) do
        if state then d:Show() else d:Hide() end
    end
    -- Start each session on a full interval instead of whatever was left over.
    cycleAcc, linkAcc = 0, 0
    if not state then
        -- updateCycle was the only thing that ever hid this, and it no longer
        -- runs once the driver is parked -- the hint would stay on screen at
        -- DIALOG strata until edit mode was reopened and the cursor moved.
        if cycleHint then cycleHint:Hide() end
        altWasDown = false
    end
end)
