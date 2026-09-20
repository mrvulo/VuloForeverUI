-- VuloForeverUI / Modules / Nameplates / Target
--
-- Everything a plate shows because of what the PLAYER is doing with it: target,
-- focus, mouseover. Glow, border, highlight wash, bar overlay, arrows, the hash
-- line, the focus letter, scale and the fading of everything that is not the
-- target.
--
-- "Is this plate my target" is UnitIsUnit(plate unit, "target") -- a plate
-- token against a plain token, which the client answers in the clear. The
-- answer is kept on the plate (isTarget / isFocus / isHover) and every branch
-- below hangs on those, never on a fresh unit read.
local _, ns = ...
local NP = ns.NP

local Target = {}
NP.Target = Target

local WHITE = "Interface\\Buttons\\WHITE8X8"
local ARROW_LEFT  = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\arrow_right"   -- left of the bar, pointing at it
local ARROW_RIGHT = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\arrow_left"
local GLOW_SIZE = 7

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function gradientEdge(parent, orient, flip)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(WHITE)
    t:SetBlendMode("ADD")
    t.orient, t.flip = orient, flip
    return t
end

function Target.Build(plate)
    local health = plate.health

    -- glow: four soft edges behind the bar, fading outward
    local glow = CreateFrame("Frame", nil, plate)
    glow:SetFrameLevel(math.max(health:GetFrameLevel() - 1, 0))
    glow:SetPoint("TOPLEFT", health, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    glow:Hide()
    local e = {
        top = gradientEdge(glow, "VERTICAL", false), bot = gradientEdge(glow, "VERTICAL", true),
        lft = gradientEdge(glow, "HORIZONTAL", true), rgt = gradientEdge(glow, "HORIZONTAL", false),
    }
    e.top:SetPoint("BOTTOMLEFT", health, "TOPLEFT"); e.top:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT"); e.top:SetHeight(GLOW_SIZE)
    e.bot:SetPoint("TOPLEFT", health, "BOTTOMLEFT"); e.bot:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT"); e.bot:SetHeight(GLOW_SIZE)
    e.lft:SetPoint("TOPRIGHT", health, "TOPLEFT"); e.lft:SetPoint("BOTTOMRIGHT", health, "BOTTOMLEFT"); e.lft:SetWidth(GLOW_SIZE)
    e.rgt:SetPoint("TOPLEFT", health, "TOPRIGHT"); e.rgt:SetPoint("BOTTOMLEFT", health, "BOTTOMRIGHT"); e.rgt:SetWidth(GLOW_SIZE)
    plate.glow, plate.glowEdges = glow, e

    -- on top of the fill: overlay texture (filled and empty part) and the wash
    local over = CreateFrame("Frame", nil, health)
    over:SetAllPoints(health)
    over:SetFrameLevel(health:GetFrameLevel() + 2)
    local fillTex = health:GetStatusBarTexture()
    plate.overlayFill = over:CreateTexture(nil, "ARTWORK")
    plate.overlayFill:SetAllPoints(fillTex)
    plate.overlayEmpty = over:CreateTexture(nil, "ARTWORK")
    plate.overlayEmpty:SetPoint("TOPLEFT", fillTex, "TOPRIGHT")
    plate.overlayEmpty:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
    plate.highlight = over:CreateTexture(nil, "OVERLAY")
    plate.highlight:SetAllPoints(health)
    plate.highlight:SetTexture(WHITE)
    plate.highlight:SetBlendMode("ADD")
    plate.overlayFill:Hide(); plate.overlayEmpty:Hide(); plate.highlight:Hide()

    plate.arrowLeft = plate.iconFrame:CreateTexture(nil, "OVERLAY")
    plate.arrowLeft:SetTexture(ARROW_LEFT)
    plate.arrowRight = plate.iconFrame:CreateTexture(nil, "OVERLAY")
    plate.arrowRight:SetTexture(ARROW_RIGHT)
    plate.arrowLeft:Hide(); plate.arrowRight:Hide()

    plate.focusLetter = plate.textFrame:CreateFontString(nil, "OVERLAY")
    plate.focusLetter:SetFont(ns.ModuleFontPath("nameplates"), 18, "OUTLINE")
    plate.focusLetter:SetText("F")
    plate.focusLetter:Hide()

    plate.scaleCur, plate.scaleGoal = 1, 1
end

function Target.ApplyAppearance(plate)
    local db = NP.db()
    local size = 16 * db.targetArrowScale
    plate.arrowLeft:ClearAllPoints()
    plate.arrowLeft:SetSize(size, size)
    plate.arrowLeft:SetPoint("RIGHT", plate.health, "LEFT", -4, 0)
    plate.arrowRight:ClearAllPoints()
    plate.arrowRight:SetSize(size, size)
    plate.arrowRight:SetPoint("LEFT", plate.health, "RIGHT", 4, 0)

    local letter = plate.focusLetter
    letter:SetFont(ns.ModuleFontPath("nameplates"), db.focusLetterSize, "OUTLINE")
    letter:ClearAllPoints()
    letter:SetPoint(db.focusLetterAnchor, plate.health, db.focusLetterAnchor, db.focusLetterX, db.focusLetterY)
    local fc = db.focus
    letter:SetTextColor(fc.r, fc.g, fc.b)
end

-- ---------------------------------------------------------------------------
-- Pieces
-- ---------------------------------------------------------------------------
local function setGlow(plate, on, c, alpha)
    if not on then plate.glow:Hide(); return end
    for _, t in pairs(plate.glowEdges) do
        local a1, a2 = alpha, 0
        if t.flip then a1, a2 = 0, alpha end
        -- first colour is bottom/left, second is top/right
        t:SetGradient(t.orient, CreateColor(c.r, c.g, c.b, a1), CreateColor(c.r, c.g, c.b, a2))
    end
    plate.glow:Show()
end

local function setOverlay(plate, texture, color, alpha, fullEmpty, noTint)
    local fill, empty = plate.overlayFill, plate.overlayEmpty
    if not texture or texture == "none" then fill:Hide(); empty:Hide(); return end
    local path = ns.MediaStatusbar(texture, WHITE)
    local r, g, b = 1, 1, 1
    if not noTint then r, g, b = color.r, color.g, color.b end
    fill:SetTexture(path);  fill:SetVertexColor(r, g, b, alpha);  fill:Show()
    empty:SetTexture(path); empty:SetVertexColor(r, g, b, fullEmpty and alpha or alpha * 0.35); empty:Show()
end

local function playerClassColor()
    local _, class = UnitClass("player")
    local c = class and (ns.CLASS_COLORS and ns.CLASS_COLORS[class] or RAID_CLASS_COLORS[class])
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Scale, eased. One driver for all plates, hidden while nothing moves.
-- ---------------------------------------------------------------------------
local moving = {}
local easer = CreateFrame("Frame")
easer:Hide()
easer:SetScript("OnUpdate", function(self, elapsed)
    local any = false
    for plate in pairs(moving) do
        local cur, goal = plate.scaleCur, plate.scaleGoal
        local step = (goal - cur) * math.min(elapsed * 14, 1)
        if math.abs(goal - cur) < 0.004 or not plate.unit then
            cur = goal
            moving[plate] = nil
        else
            cur = cur + step
            any = true
        end
        plate.scaleCur = cur
        plate:SetScale(cur)
    end
    if not any then self:Hide() end
end)

local function updateScale(plate)
    local db = NP.db()
    local goal = 1
    if plate.isTarget then goal = goal * db.targetScale / 100 end
    if plate.castScaleOn then goal = goal * db.castScale / 100 end
    if goal == plate.scaleGoal then return end
    plate.scaleGoal = goal
    moving[plate] = true
    easer:Show()
end

function Target.SetCastScale(plate, on)
    plate.castScaleOn = on and true or false
    updateScale(plate)
end

-- ---------------------------------------------------------------------------
-- Alpha. Set on the plate's root: the client's own occlusion fade sits on the
-- base plate above it and still multiplies in.
-- ---------------------------------------------------------------------------
local hasTarget = false

-- Which plate currently holds each role. Kept up to date by Apply itself, not
-- only by the change events: a plate that shows up AFTER the target was picked
-- (walk up to a targeted mob, /reload in a pack) has to be known here, or the
-- next target change cannot take its glow away again.
local curTarget, curFocus, curHover, hoverTicker

function Target.ApplyAlpha(plate)
    local db = NP.db()
    local a = 1
    if hasTarget and not plate.isTarget and db.nonTargetAlpha < 100
        and not (plate.isFocus and db.nonTargetKeepFocus) then
        a = db.nonTargetAlpha / 100
    end
    plate:SetAlpha(a)
end

-- ---------------------------------------------------------------------------
-- Apply: target wins over focus wins over hover, channel by channel.
-- ---------------------------------------------------------------------------
function Target.Apply(plate)
    local unit = plate.unit
    if not unit then return end
    local db = NP.db()
    local isT = UnitIsUnit(unit, "target")
    local isF = UnitIsUnit(unit, "focus")
    local wasFocus = plate.isFocus
    plate.isTarget = ns.CanRead(isT) and isT == true
    plate.isFocus  = ns.CanRead(isF) and isF == true
    if plate.isTarget then curTarget = plate elseif curTarget == plate then curTarget = nil end
    if plate.isFocus then curFocus = plate elseif curFocus == plate then curFocus = nil end
    local T, F, H = plate.isTarget, plate.isFocus, plate.isHover and not plate.isTarget

    -- glow
    if T and db.targetGlow then setGlow(plate, true, db.targetGlowColor, db.targetGlowAlpha)
    elseif H and db.hoverGlow then setGlow(plate, true, db.hoverGlowColor, db.hoverGlowAlpha)
    else setGlow(plate, false) end

    -- border colour and size
    local bc, bs = db.borderColor, db.showBorder and db.borderSize or 0
    if T then
        if db.targetGlowBorderColor then bc = db.targetBorderColor end
        if db.targetGlowBorderSize then bs = db.targetBorderSizeValue end
    elseif H then
        if db.hoverGlowBorderColor then bc = db.hoverBorderColor end
        if db.hoverGlowBorderSize then bs = db.hoverBorderSizeValue end
    end
    ns.LayoutEdges(plate.border, plate.borderHost, bs, bc.r, bc.g, bc.b, 1)

    -- highlight wash
    local hl = plate.highlight
    if T and db.targetGlowHighlight then
        local c = db.targetHighlightColor
        hl:SetVertexColor(c.r, c.g, c.b, db.targetHighlightAlpha); hl:Show()
    elseif H and db.hoverGlowHighlight then
        local c = db.hoverColor
        hl:SetVertexColor(c.r, c.g, c.b, db.hoverAlpha); hl:Show()
    else
        hl:Hide()
    end

    -- bar overlay
    if T and db.targetOverlayTexture ~= "none" then
        setOverlay(plate, db.targetOverlayTexture, db.targetOverlayColor, db.targetOverlayAlpha,
            db.targetOverlayFullBgAlpha, db.targetOverlayNoTint)
    elseif F and db.focusOverlayTexture ~= "none" then
        setOverlay(plate, db.focusOverlayTexture, db.focusOverlayColor, db.focusOverlayAlpha,
            db.focusOverlayFullBgAlpha, db.focusOverlayNoTint)
    elseif H and db.hoverOverlayTexture ~= "none" then
        setOverlay(plate, db.hoverOverlayTexture, db.hoverColor, db.hoverAlpha, db.hoverOverlayFullBgAlpha, false)
    else
        setOverlay(plate, nil)
    end

    -- arrows
    local showArrows = T and db.showTargetArrows
    if showArrows then
        local r, g, b = db.targetArrowColor.r, db.targetArrowColor.g, db.targetArrowColor.b
        if db.targetArrowClassColor then r, g, b = playerClassColor() end
        plate.arrowLeft:SetVertexColor(r, g, b); plate.arrowRight:SetVertexColor(r, g, b)
    end
    plate.arrowLeft:SetShown(showArrows); plate.arrowRight:SetShown(showArrows)

    plate.hashLine:SetShown(T and db.hashLineEnabled)
    plate.focusLetter:SetShown(F and db.focusLetterEnabled)

    -- the focus cast bar has its own height
    if F ~= wasFocus and db.focusCastHeight ~= 100 then NP.Cast.ApplyAppearance(plate) end

    updateScale(plate)
    Target.ApplyAlpha(plate)
    NP.Extras.UpdateCombo(plate)
end

function Target.SetHover(plate, on)
    on = on and true or false
    if plate.isHover == on then return end
    plate.isHover = on
    Target.Apply(plate)
end

function Target.Reset(plate)
    Target.Forget(plate)
    moving[plate] = nil
    plate.scaleCur, plate.scaleGoal, plate.castScaleOn = 1, 1, false
    plate.isHover = false
    if plate.glow then plate.glow:Hide() end
end

-- ---------------------------------------------------------------------------
-- Who is target, focus, mouseover. Only the plates that change are restyled;
-- alpha is the exception, because gaining a target fades everyone else.
-- ---------------------------------------------------------------------------
local function plateOf(token)
    local nameplate = C_NamePlate.GetNamePlateForUnit(token)
    return nameplate and NP.byNameplate[nameplate]
end

-- A plate that goes away takes its role with it.
function Target.Forget(plate)
    if curTarget == plate then curTarget = nil end
    if curFocus == plate then curFocus = nil end
    if curHover == plate then curHover = nil end
end

local function restyle(plate)
    if plate and plate.unit then
        Target.Apply(plate)
        NP.Colors.Apply(plate)
    end
end

function Target.OnTargetChanged()
    local old = curTarget
    curTarget = plateOf("target") or nil
    hasTarget = UnitExists("target") and true or false
    if old ~= curTarget then restyle(old) end
    restyle(curTarget)
    for _, plate in pairs(NP.plates) do Target.ApplyAlpha(plate) end
end

function Target.OnFocusChanged()
    local old = curFocus
    curFocus = plateOf("focus") or nil
    if old ~= curFocus then restyle(old) end
    restyle(curFocus)
end

-- The client says when the mouse ARRIVES on a unit, never when it leaves; a
-- short ticker watches for that, and only while something is hovered.
local function checkHover()
    local plate = UnitExists("mouseover") and plateOf("mouseover") or nil
    if plate ~= curHover then
        if curHover and curHover.unit then Target.SetHover(curHover, false) end
        curHover = plate
        if plate then Target.SetHover(plate, true) end
    end
    if not plate and hoverTicker then
        ns:CancelTicker(hoverTicker)
        hoverTicker = nil
    end
end

function Target.OnMouseover()
    checkHover()
    if curHover and not hoverTicker then
        hoverTicker = ns:AddTicker(0.1, checkHover, nil, "nameplates")
    end
end
