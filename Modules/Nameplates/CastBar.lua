-- VuloForeverUI / Modules / Nameplates / CastBar
--
-- The cast bar of one plate.
--
-- For a nameplate unit every interesting cast field is secret: name, icon,
-- times, spell id, and whether the cast can be interrupted. So:
--   * the fill is a timer the CLIENT runs (SetTimerDuration with the cast's
--     duration object); we never see a time;
--   * name and icon go straight into SetText / SetTexture;
--   * "can it be interrupted" and "is my interrupt ready" are secret booleans
--     that are folded into the bar colour and the shield's alpha by the client
--     (ns.FoldColor, ns.AlphaFromBool) -- there is no `if` on either;
--   * where the interrupt comes ready is GEOMETRY: two invisible status bars
--     laid end to end (elapsed cast time, then remaining cooldown) whose far
--     edge is that moment on the bar.
--
-- The cast events are registered per plate with RegisterUnitEvent and the
-- handler never reads the unit from the payload: the payload of these events is
-- documented as secret for restricted units. Only castBarID is never secret.
--
-- Stop handlers hide and never ask the client again: under restriction a cast
-- that has just ended can still come back from UnitCastingInfo as a non-nil
-- secret tuple, and would look like a running cast.
local _, ns = ...
local L = ns.L
local NP = ns.NP

local Cast = {}
NP.Cast = Cast

local WHITE = "Interface\\Buttons\\WHITE8X8"
local SPARK = "Interface\\AddOns\\VuloForeverUI\\Media\\Castbar\\CastingBarSpark"
local ELAPSED   = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime or 0
local REMAINING = Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
local IMMEDIATE = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
local FILL_STANDARD = Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Standard
local FILL_REVERSE  = Enum.StatusBarFillStyle and Enum.StatusBarFillStyle.Reverse

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}
Cast.EVENTS = CAST_EVENTS

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
local function invisibleBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(WHITE)
    bar:SetStatusBarColor(0, 0, 0, 0)
    return bar
end

-- A fill texture created by SetStatusBarTexture / SetFillStyle snaps to the
-- pixel grid again; on a thin mark that reads as jitter.
local function noSnap(bar)
    local tex = bar:GetStatusBarTexture()
    if tex and tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
end

function Cast.Build(plate)
    local cast = CreateFrame("StatusBar", nil, plate)
    cast:SetStatusBarTexture(WHITE)
    cast:Hide()
    plate.cast = cast

    plate.castBG = cast:CreateTexture(nil, "BACKGROUND")
    plate.castBG:SetAllPoints(cast)

    local borderHost = CreateFrame("Frame", nil, cast)
    borderHost:SetAllPoints(cast)
    borderHost:SetFrameLevel(cast:GetFrameLevel() + 4)
    plate.castBorder = ns.MakeEdges(borderHost, "OVERLAY")

    -- kick geometry, clipped to the bar
    local clip = CreateFrame("Frame", nil, cast)
    clip:SetAllPoints(cast)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(cast:GetFrameLevel() + 1)
    plate.kickClip = clip
    plate.kickPositioner = invisibleBar(clip)
    plate.kickPositioner:SetAllPoints(cast)
    plate.kickMarker = invisibleBar(clip)
    plate.kickReadyFill = clip:CreateTexture(nil, "ARTWORK")
    plate.kickTick = clip:CreateTexture(nil, "OVERLAY")

    local spark = cast:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(SPARK)
    spark:SetBlendMode("ADD")
    plate.castSpark = spark

    -- important-cast glow: the host takes the secret boolean as its alpha, the
    -- inner frame pulses. Two frames because both want to own "alpha".
    local glowHost = CreateFrame("Frame", nil, cast)
    glowHost:SetAllPoints(cast)
    glowHost:SetFrameLevel(cast:GetFrameLevel() + 5)
    glowHost:SetAlpha(0)
    local glowInner = CreateFrame("Frame", nil, glowHost)
    glowInner:SetAllPoints(glowHost)
    plate.castGlowHost = glowHost
    plate.castGlow = ns.MakeEdges(glowInner, "OVERLAY")
    for _, t in pairs(plate.castGlow) do t:SetBlendMode("ADD") end
    local pulse = glowInner:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.25); a:SetDuration(0.45)
    plate.castGlowPulse = pulse

    local iconFrame = CreateFrame("Frame", nil, cast)
    iconFrame:SetFrameLevel(cast:GetFrameLevel() + 2)
    plate.castIconFrame = iconFrame
    plate.castIcon = iconFrame:CreateTexture(nil, "ARTWORK")
    plate.castIcon:SetAllPoints(iconFrame)
    plate.castIconBorder = ns.MakeEdges(iconFrame, "OVERLAY")

    local top = CreateFrame("Frame", nil, cast)
    top:SetAllPoints(cast)
    top:SetFrameLevel(cast:GetFrameLevel() + 6)
    plate.castShield = top:CreateTexture(nil, "OVERLAY")
    plate.castShield:SetAtlas("nameplates-InterruptShield")
    plate.castShield:SetAlpha(0)
    local font = ns.ModuleFontPath("nameplates")
    for _, key in ipairs({ "castName", "castTarget", "castTimer" }) do
        local fs = top:CreateFontString(nil, "OVERLAY")
        fs:SetFont(font, 10, "OUTLINE")
        fs:SetWordWrap(false)
        plate[key] = fs
    end
end

-- ---------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------
local function placeText(fs, cast, side, size, col, x, y, width, wrap, font)
    fs:SetFont(font, size, "OUTLINE")
    fs:SetTextColor(col.r, col.g, col.b)
    fs:ClearAllPoints()
    fs:SetWidth(width)
    fs:SetWordWrap(wrap and true or false)
    fs:SetMaxLines(wrap and 2 or 1)
    if side == "none" then fs:Hide(); return end
    fs:Show()
    if side == "left" then
        fs:SetPoint("LEFT", cast, "LEFT", 3 + x, y); fs:SetJustifyH("LEFT")
    elseif side == "right" then
        fs:SetPoint("RIGHT", cast, "RIGHT", -3 + x, y); fs:SetJustifyH("RIGHT")
    else
        fs:SetPoint("CENTER", cast, "CENTER", x, y); fs:SetJustifyH("CENTER")
    end
end

function Cast.ApplyAppearance(plate)
    local db = NP.db()
    local cast, health = plate.cast, plate.health
    local barW, castH = db.healthBarWidth, db.castBarHeight
    if plate.isFocus then castH = castH * db.focusCastHeight / 100 end
    local gap = db.showBorder and NP.Pixel(plate, db.borderSize) or 0

    -- icon
    local iconSize = (db.castIconFullSize and (castH + db.healthBarHeight + gap) or castH) * db.castIconScale
    local showIcon = db.showCastIcon
    local inWidth = showIcon and db.castbarIconInWidth and not db.castIconFullSize
    local castW = inWidth and (barW - iconSize) or barW
    local onRight = db.castIconOnRight

    cast:ClearAllPoints()
    cast:SetSize(castW, castH)
    if inWidth and not onRight then
        cast:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, -gap + db.castBarOffsetY)
    else
        cast:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -gap + db.castBarOffsetY)
    end
    cast:SetStatusBarTexture(ns.MediaStatusbar(db.castBarTexture, WHITE))
    noSnap(cast)

    local bg = db.castBgColor
    plate.castBG:SetColorTexture(bg.r, bg.g, bg.b, db.castBgAlpha)
    local bc = db.castBorderColor
    ns.LayoutEdges(plate.castBorder, cast, db.castBorderSize, bc.r, bc.g, bc.b, 1)

    local iconFrame = plate.castIconFrame
    iconFrame:ClearAllPoints()
    iconFrame:SetSize(iconSize, iconSize)
    iconFrame:SetShown(showIcon)
    local ix, iy = db.castIconOffsetX, db.castIconOffsetY
    if db.castIconFullSize then
        if onRight then iconFrame:SetPoint("BOTTOMLEFT", cast, "BOTTOMRIGHT", gap + ix, iy)
        else iconFrame:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", -gap + ix, iy) end
    elseif onRight then
        iconFrame:SetPoint("LEFT", cast, "RIGHT", (inWidth and 0 or gap) + ix, iy)
    else
        iconFrame:SetPoint("RIGHT", cast, "LEFT", -(inWidth and 0 or gap) + ix, iy)
    end
    plate.castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ibc = db.castIconTargetBorder and db.targetBorderColor or db.borderColor
    ns.LayoutEdges(plate.castIconBorder, iconFrame, db.hideCastIconBorder and 0 or 1, ibc.r, ibc.g, ibc.b, 1)

    -- spark, shield, glow
    local spark = plate.castSpark
    spark:SetSize(castH * 0.6, castH * 2)
    spark:SetShown(db.castBarSparkEnabled)
    plate.castShield:ClearAllPoints()
    plate.castShield:SetSize(castH * 0.83, castH)
    plate.castShield:SetPoint("CENTER", cast, "LEFT", 0, 0)
    local gc = db.importantCastGlowColor
    ns.LayoutEdges(plate.castGlow, plate.castGlowHost, 2, gc.r, gc.g, gc.b, 1)

    -- kick geometry
    local marker = plate.kickMarker
    marker:SetSize(castW, castH)
    local tc = db.kickTickColor
    plate.kickTick:SetColorTexture(tc.r, tc.g, tc.b, 1)
    plate.kickTick:SetWidth(math.max(NP.Pixel(plate, 2), 1))
    local rc = db.interruptMidCastColor
    plate.kickReadyFill:SetColorTexture(rc.r, rc.g, rc.b, 0.55)

    -- texts. Name and target may not share a side; the options keep them
    -- apart, the combined mode hides the target line.
    local font = ns.ModuleFontPath("nameplates")
    placeText(plate.castName, cast, db.castNameSide, db.castNameSize, db.castNameColor,
        db.castNameOffsetX, db.castNameOffsetY, castW * db.castNameWidthPct / 100, db.castNameWrap, font)
    placeText(plate.castTarget, cast, db.castCombineNameTarget and "none" or db.castTargetSide,
        db.castTargetSize, db.castTargetColor, db.castTargetOffsetX, db.castTargetOffsetY,
        castW * db.castTargetWidthPct / 100, db.castTargetWrap, font)
    placeText(plate.castTimer, cast, db.showCastTimer and db.castTimerSide or "none",
        db.castTimerSize, db.castTimerColor, db.castTimerOffsetX, db.castTimerOffsetY, 0, false, font)
end

-- ---------------------------------------------------------------------------
-- Colour: base -> "my interrupt is on cooldown" -> important -> uninterruptible
-- ---------------------------------------------------------------------------
local function kickReady()
    local cd = NP.Kick.Duration()
    if not cd then return nil end
    local ok, zero = pcall(cd.IsZero, cd)
    if ok then return zero, cd end
    return nil
end

function Cast.RefreshColor(plate)
    if not plate.isCasting then return end
    local db = NP.db()
    local c = db.castBar
    local r, g, b = c.r, c.g, c.b
    local ready = kickReady()
    if ns.Exists(ready) then
        local n = db.interruptReady
        r, g, b = ns.FoldColor(ready, r, g, b, n.r, n.g, n.b)
    end
    if db.importantCastColorEnabled and ns.Exists(plate.castImportant) then
        local i = db.castBarImportant
        r, g, b = ns.FoldColor(plate.castImportant, i.r, i.g, i.b, r, g, b)
    end
    if ns.Exists(plate.castNotInt) then
        local u = db.castBarUninterruptible
        r, g, b = ns.FoldColor(plate.castNotInt, u.r, u.g, u.b, r, g, b)
    end
    plate.cast:SetStatusBarColor(r, g, b)
end

local function refreshShield(plate)
    local shield = plate.castShield
    if NP.db().castBarShieldEnabled and ns.Exists(plate.castNotInt) then
        ns.AlphaFromBool(shield, plate.castNotInt)
    else
        shield:SetAlpha(0)
    end
end

-- ---------------------------------------------------------------------------
-- Kick mark. positioner = elapsed cast time, marker = remaining cooldown, both
-- on the cast's own time scale and laid end to end; the marker's far edge is
-- the moment the interrupt is back. Both are re-pinned together -- one without
-- the other and the mark wanders. A cast that ends before that moment pushes
-- the edge outside the clip frame, and the ready-fill's anchors cross: it
-- collapses to nothing without a single comparison.
-- ---------------------------------------------------------------------------
local function layoutKick(plate)
    local cast, pos, marker = plate.cast, plate.kickPositioner, plate.kickMarker
    local tick, fill = plate.kickTick, plate.kickReadyFill
    local reverse = plate.isChannel and FILL_REVERSE
    if pos.SetFillStyle and FILL_STANDARD then
        pos:SetFillStyle(reverse or FILL_STANDARD)
        marker:SetFillStyle(reverse or FILL_STANDARD)
    end
    noSnap(pos); noSnap(marker)
    local posTex, markTex = pos:GetStatusBarTexture(), marker:GetStatusBarTexture()
    marker:ClearAllPoints()
    tick:ClearAllPoints()
    fill:ClearAllPoints()
    if reverse then
        marker:SetPoint("RIGHT", posTex, "LEFT", 0, 0)
        tick:SetPoint("TOP", markTex, "TOPLEFT", 0, 0)
        tick:SetPoint("BOTTOM", markTex, "BOTTOMLEFT", 0, 0)
        fill:SetPoint("TOPRIGHT", markTex, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", cast, "BOTTOMLEFT", 0, 0)
    else
        marker:SetPoint("LEFT", posTex, "RIGHT", 0, 0)
        tick:SetPoint("TOP", markTex, "TOPRIGHT", 0, 0)
        tick:SetPoint("BOTTOM", markTex, "BOTTOMRIGHT", 0, 0)
        fill:SetPoint("TOPLEFT", markTex, "TOPRIGHT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", 0, 0)
    end
end

local function pinKick(plate)
    local db = NP.db()
    local dur = plate.castDur
    local tick, fill = plate.kickTick, plate.kickReadyFill
    local ready, cd = kickReady()
    if not (db.kickTickEnabled and ns.Exists(dur) and cd and ns.Exists(ready)) then
        tick:SetAlpha(0); fill:SetAlpha(0)
        return
    end
    local total = dur:GetTotalDuration()
    plate.kickPositioner:SetMinMaxValues(0, total)
    plate.kickPositioner:SetValue(dur:GetElapsedDuration())
    plate.kickMarker:SetMinMaxValues(0, total)
    plate.kickMarker:SetValue(cd:GetRemainingDuration())
    -- nothing to mark when the interrupt is ready now, or cannot land at all
    local alpha = ns.FoldValue(ready, 0, 1)
    if ns.Exists(plate.castNotInt) then alpha = ns.FoldValue(plate.castNotInt, 0, alpha) end
    tick:SetAlpha(alpha)
    if db.interruptMidCastEnabled then fill:SetAlpha(alpha) else fill:SetAlpha(0) end
end

-- ---------------------------------------------------------------------------
-- One ticker for all casting plates: timer text, kick mark, kick colour.
-- ---------------------------------------------------------------------------
local casting, count, ticker = {}, 0, nil

local function onError(err) geterrorhandler()(err) end

local function tickPlate(plate)
    local dur = plate.castDur
    if ns.Exists(dur) and plate.castTimer:IsShown() then
        plate.castTimer:SetFormattedText("%.1f", dur:GetRemainingDuration())
    end
    pinKick(plate)
    Cast.RefreshColor(plate)
end

local function tick()
    for plate in pairs(casting) do
        if plate.isCasting then xpcall(tickPlate, onError, plate) end
    end
end

local function track(plate, on)
    if on and not casting[plate] then
        casting[plate] = true
        count = count + 1
        if not ticker then ticker = ns:AddTicker(0.1, tick, nil, "nameplates") end
    elseif not on and casting[plate] then
        casting[plate] = nil
        count = count - 1
        if count <= 0 and ticker then
            ns:CancelTicker(ticker)
            ticker, count = nil, 0
        end
    end
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
local function wrapBorder(plate, on)
    local db = NP.db()
    if not (db.showBorder and db.wrapBorderCastbar) then return end
    local host = plate.borderHost
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", plate.health, "TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", on and plate.cast or plate.health, "BOTTOMRIGHT", 0, 0)
end

local function hide(plate)
    plate.isCasting = false
    plate.castDur, plate.castNotInt, plate.castImportant, plate.castBarID = nil, nil, nil, nil
    track(plate, false)
    plate.cast:Hide()
    plate.castGlowPulse:Stop()
    wrapBorder(plate, false)
    plate.texts.Top:SetAlpha(1)
    if NP.Target then NP.Target.SetCastScale(plate, false) end
end

-- isChannel: true/false from the event that started it, nil to find out (a
-- plate that appears mid-cast).
function Cast.Start(plate, isChannel)
    local unit = plate.unit
    if not unit then return end
    local db = NP.db()
    plate.flashToken = (plate.flashToken or 0) + 1

    local name, _, texture, notInt, spellID, barID
    if isChannel ~= true then
        name, _, texture, _, _, _, _, notInt, spellID, barID = UnitCastingInfo(unit)
        if ns.Exists(name) then isChannel = false end
    end
    if not ns.Exists(name) and isChannel ~= false then
        name, _, texture, _, _, _, notInt, spellID = UnitChannelInfo(unit)
        if ns.Exists(name) then isChannel = true end
    end
    if not ns.Exists(name) then
        if plate.isCasting then hide(plate) end
        return
    end

    plate.isCasting, plate.isChannel = true, isChannel
    plate.castNotInt = notInt
    plate.castBarID = ns.Num(barID, nil)

    local cast = plate.cast
    local dur
    if isChannel then dur = UnitChannelDuration(unit) else dur = UnitCastingDuration(unit) end
    plate.castDur = dur
    if ns.Exists(dur) then
        cast:SetTimerDuration(dur, IMMEDIATE, isChannel and REMAINING or ELAPSED)
    else
        cast:SetMinMaxValues(0, 1)
        cast:SetValue(1)
    end

    local spark = plate.castSpark
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)

    plate.castName:SetText(name)
    plate.castIcon:SetTexture(texture)
    plate.castTimer:SetText("")

    -- important cast: a secret boolean, straight into an alpha
    plate.castImportant = nil
    if C_Spell.IsSpellImportant and ns.Exists(spellID) then
        local ok, important = pcall(C_Spell.IsSpellImportant, spellID)
        if ok then plate.castImportant = important end
    end
    if db.importantCastGlow and ns.Exists(plate.castImportant) then
        ns.AlphaFromBool(plate.castGlowHost, plate.castImportant)
        plate.castGlowPulse:Play()
    else
        plate.castGlowHost:SetAlpha(0)
    end

    Cast.UpdateTarget(plate, name)
    refreshShield(plate)
    layoutKick(plate)
    cast:Show()
    wrapBorder(plate, true)
    if db.hideEnemyNameWhileCasting then plate.texts.Top:SetAlpha(0) end
    if NP.Target then NP.Target.SetCastScale(plate, true) end
    track(plate, true)
    xpcall(tickPlate, onError, plate)
end

-- Who the cast is aimed at. All three values may be secret; the class colour
-- is looked up by the client and only its numbers are handed on.
function Cast.UpdateTarget(plate, spellName)
    local unit, db = plate.unit, NP.db()
    local fs = plate.castTarget
    local show = UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(unit)
    local target = UnitSpellTargetName and UnitSpellTargetName(unit)
    if not (ns.CanRead(show) and show and ns.Exists(target)) then
        fs:SetText("")
        return
    end
    local r, g, b = db.castTargetColor.r, db.castTargetColor.g, db.castTargetColor.b
    if db.castTargetClassColor and UnitSpellTargetClass and C_ClassColor then
        local class = UnitSpellTargetClass(unit)
        if ns.Exists(class) then
            local ok, color = pcall(C_ClassColor.GetClassColor, class)
            if ok and color then r, g, b = color:GetRGB() end
        end
    end
    if db.castCombineNameTarget then
        plate.castName:SetFormattedText("%s - %s", spellName, target)
    else
        fs:SetTextColor(r, g, b)
        fs:SetText(target)
    end
end

-- The bar stays for a second in the flash colour, saying who did it.
local function flash(plate, interruptedBy)
    local db = NP.db()
    local cast = plate.cast
    local token = (plate.flashToken or 0) + 1
    plate.flashToken = token
    plate.isCasting = false
    track(plate, false)
    plate.castGlowPulse:Stop()
    plate.castGlowHost:SetAlpha(0)
    plate.castShield:SetAlpha(0)
    plate.kickTick:SetAlpha(0); plate.kickReadyFill:SetAlpha(0)
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(1)
    local c = db.interruptedFlashColor
    cast:SetStatusBarColor(c.r, c.g, c.b)
    plate.castTimer:SetText("")
    plate.castTarget:SetText("")

    -- GUID -> unit token -> name; the GUID may be secret and is only handed on.
    local who
    if ns.Exists(interruptedBy) and UnitTokenFromGUID then
        local ok, token = pcall(UnitTokenFromGUID, interruptedBy)
        if ok and ns.Exists(token) then
            local okName, name = pcall(UnitName, token)
            if okName and ns.Exists(name) then who = name end
        end
    end
    if who then
        plate.castName:SetFormattedText("%s (%s)", L["Interrupted"], who)
    else
        plate.castName:SetText(L["Interrupted"])
    end
    C_Timer.After(1, function()
        if plate.flashToken == token and not plate.isCasting then hide(plate) end
    end)
end

function Cast.Stop(plate, reason, interruptedBy)
    if reason == "interrupted" and plate.isCasting and NP.db().interruptedFlashEnabled then
        flash(plate, interruptedBy)
        return
    end
    -- the STOP that follows an interrupt must not cut the flash short
    if reason == "stop" and not plate.isCasting then return end
    plate.flashToken = (plate.flashToken or 0) + 1
    hide(plate)
end

-- A plate put on a unit that is already casting.
function Cast.Resume(plate)
    if not plate.isCasting then Cast.Start(plate, nil) end
end

-- ---------------------------------------------------------------------------
-- Events (called from the plate's OnEvent; `...` is the payload AFTER the unit)
-- ---------------------------------------------------------------------------
-- A stop that belongs to another cast of the same unit must not take this bar
-- down. castBarID is the one payload field that is never secret.
local function sameBar(plate, barID)
    local mine = plate.castBarID
    barID = ns.Num(barID, nil)
    return not (mine and barID) or mine == barID
end

function Cast.OnEvent(plate, event, _, _, _, p4, p5)
    if event == "UNIT_SPELLCAST_START" then
        Cast.Start(plate, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        Cast.Start(plate, true)
    elseif event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        if plate.isCasting then Cast.Start(plate, plate.isChannel) end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if sameBar(plate, p5) then Cast.Stop(plate, "interrupted", p4) end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        if sameBar(plate, p5) then Cast.Stop(plate, "stop") end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" then
        if sameBar(plate, p4) then Cast.Stop(plate, "stop") end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        if plate.isCasting then
            -- the event says it in the clear; no need to ask for the secret flag
            plate.castNotInt = (event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
            refreshShield(plate)
            Cast.RefreshColor(plate)
        end
    end
end
