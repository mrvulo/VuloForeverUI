-- VuloForeverUI / UI / Widgets / Slider: slider row with track, -/value/+ block and typed value.
local _, ns = ...
local UI = ns.UI
local W = UI._W

local clean, attachTooltip = W.clean, W.attachTooltip

local MASK_ROUNDED = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\circle_mask.tga"

-- Slider config: { label, tooltip?, min, max, step, get, set, width? }
-- Rounds a flat colour texture with one of the bundled masks. Turning texel
-- snapping off matters as much as the mask: with it on, small rounded art is
-- snapped hard onto the pixel grid and the curve comes out visibly stepped.
local function roundTexture(owner, tex, maskFile)
    if not (owner and tex and owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    local m = owner:CreateMaskTexture()
    m:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)          -- tracks the fill as it grows
    tex:AddMaskTexture(m)
    if tex.SetSnapToPixelGrid   then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return m
end

local function sliderUpdateFill(s, v)
    local sMin, sMax = s._min or 0, s._max or 100
    local frac = 0
    if sMax > sMin then frac = (v - sMin) / (sMax - sMin) end
    frac = math.max(0, math.min(1, frac))
    local w = (s._trackBg:GetWidth() or s:GetWidth() or 200) * frac
    s._trackFill:SetWidth(math.max(0.001, w))
end

-- ONE place decides what a slider value looks like. It used to be decided
-- twice: OnValueChanged rounded to the step, the setup path did not -- so a
-- value written by something other than the slider (a frame dragged in edit
-- mode, say) came back as 7.6293945 on a slider whose step is 1, and then got
-- clipped to "7.629..." by a 36px box.
local function snapSliderValue(step, v)
    v = tonumber(v) or 0
    step = tonumber(step) or 1
    if step >= 1 then return math.floor(v / step + 0.5) * step end
    -- Sub-integer steps: round to the step's own precision, so 0.05 gives 1.35
    -- and never 1.3500000000000001.
    local inv = 1 / step
    return math.floor(v * inv + 0.5) / inv
end

-- suffix: a unit shown after the number ("%" on an opacity slider).
local function formatSliderValue(step, v, suffix)
    return string.format("%g", snapSliderValue(step, v)) .. (suffix or "")
end

-- Wide enough for the widest value the range can produce, instead of a fixed
-- 36 which "-800" never fitted into.
local function sliderValueWidth(min, max, step, suffix)
    local widest = math.max(#formatSliderValue(step, min or 0, suffix), #formatSliderValue(step, max or 0, suffix))
    return math.max(36, 8 + widest * 7)
end

-- What the -/value/+ block occupies at the right end of a slider row: the gap
-- to the track, the two 16px buttons, the value box and the gaps between them.
-- The options page asks this before it builds anything, because how many
-- columns a run may use depends on whether a track still fits beside it.
function UI.SliderEndWidth(min, max, step, suffix)
    return 8 + 16 + 4 + sliderValueWidth(min, max, step, suffix) + 4 + 16 + 4
end

-- Row metrics. They are the same numbers the toggle and dropdown rows use, so
-- the three line up without anyone tuning gaps by eye.
local SLIDER_ROW_H  = 24
local SLIDER_LABEL_W = 120   -- default until the page measures the real column
local LABEL_GAP      = 12
local DEFAULT_TRACK_W = 160  -- when the caller names no track width
-- Exported because the options page has to reproduce this row's arithmetic to
-- decide a column count. Two copies of the number would drift the moment one
-- of them was tuned, and the drift would show up as a clipped label.
UI.SLIDER_LABEL_GAP = LABEL_GAP

-- The track is what is left after the label column and the -/value/+ block.
-- A local, declared before CreateSlider because both the setup and the size
-- hook close over it.
local function layoutSliderRow(row)
    local s = row and row._slider
    if not s then return end

    -- No label, no column and no gap. The edit-mode toolbar builds sliders with
    -- label = "" and its own caption beside them; reserving a column there would
    -- shove a 70px track out of the toolbar entirely.
    local hasLabel = (row.label:GetText() or "") ~= ""
    local w = row:GetWidth() or 260
    local labelW = 0
    if hasLabel then
        labelW = math.min(row._labelW or SLIDER_LABEL_W, math.max(40, w * 0.5))
    end
    row.label:SetWidth(math.max(1, labelW))
    row.label:SetShown(hasLabel)

    local left = hasLabel and (labelW + LABEL_GAP) or 0
    s:ClearAllPoints()
    s:SetPoint("LEFT", row, "LEFT", left, 0)
    -- A floor, not a licence to overflow. The -/value/+ block is anchored to the
    -- ROW, so a cell too narrow for the track costs track width and stops there.
    -- While the block hung off the track it moved with it, and every pixel the
    -- floor invented was a pixel drawn on top of the next column.
    s:SetWidth(math.max(24, w - left - (row._endW or 90)))
end

local function sliderSetup(row, config)
    local s = row._slider
    s._vcConfig = config
    -- Also on the row: callers outside the options builder hold the row and read
    -- _vcConfig off it to rebuild themselves (UI/EditMode/ does).
    row._vcConfig = config
    s._min  = config.min or 0
    s._max  = config.max or 100
    s._step = config.step or 1
    s._suffix = config.suffix

    -- SetMinMaxValues/SetValue fire OnValueChanged; a reconfigure must not call config.set()
    s._configuring = true
    s:SetMinMaxValues(s._min, s._max)
    s:SetValueStep(s._step)
    row.label:SetText(clean(config.label) or "")

    local valW = sliderValueWidth(s._min, s._max, s._step, s._suffix)
    s._valueText:SetWidth(valW)
    -- gap + minus + gap + value + gap + plus, matching the anchors below. The
    -- options page needs the same number BEFORE the row exists, to decide how
    -- many columns fit -- so the formula lives in UI.SliderEndWidth and both
    -- read it there rather than each keeping its own copy.
    row._endW = UI.SliderEndWidth(s._min, s._max, s._step, s._suffix)

    -- config.width has always meant the TRACK width, not the row width. Callers
    -- that pass it (the edit-mode toolbar) size themselves around the track, so
    -- the row takes the track plus whatever the label and value block need.
    --
    -- Sized in BOTH cases now, not only when a width was given. The options page
    -- reads a control's width back when it lays out a row of them, and an unsized
    -- row handed it whatever the pooled widget carried over from the last page
    -- that used it.
    local labelPart = (clean(config.label) or "") ~= "" and (row._labelW + LABEL_GAP) or 0
    row:SetWidth(labelPart + (config.width or DEFAULT_TRACK_W) + row._endW)

    local v = config.get(s) or s._min
    s:SetValue(v)
    s._valueText:SetText(formatSliderValue(s._step, v, s._suffix))
    layoutSliderRow(row)
    sliderUpdateFill(s, v)
    s._configuring = false

    -- re-fill next frame, once the track has its real width
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if s:IsShown() then sliderUpdateFill(s, s:GetValue() or s._min) end
        end)
    end
end

function UI:CreateSlider(parent, config)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetObeyStepOnDrag(true)

    if s.Low  then s.Low:SetText("") end
    if s.High then s.High:SetText("") end
    if s.Text then
        UI.Font(s.Text, 12)
        s.Text:SetTextColor(ns.TC("label"))
        -- The template centres its label over the track. Every other label on
        -- the page starts at the left edge, so a centred one broke the single
        -- reading edge that lets you scan a column of settings by their names
        -- instead of reading each row.
        s.Text:ClearAllPoints()
        s.Text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 1)
        s.Text:SetJustifyH("LEFT")
    end

    local accent = ns.COLORS.accent
    local thumb  = s:GetThumbTexture()

    -- The template ships its own groove art, which sits under our flat track and
    -- reads as a second, misaligned bar. Drop it before we draw anything.
    for _, r in ipairs({ s:GetRegions() }) do
        if r ~= thumb and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end

    -- A 6px bar is only the drawing; the frame stays the grab target, and a few
    -- px of slack on top of that is the difference between precise and fiddly.
    s:SetHitRectInsets(0, 0, -3, -3)

    -- White at low alpha rather than a fixed grey: it stays hue-neutral, so the
    -- track keeps the same relationship to any panel colour behind it.
    local TRACK_IDLE, TRACK_HOVER = 0.16, 0.24
    local trackBg = s:CreateTexture(nil, "ARTWORK", nil, 1)
    trackBg:SetHeight(6)
    trackBg:SetPoint("LEFT", s, "LEFT", 2, 0)
    trackBg:SetPoint("RIGHT", s, "RIGHT", -2, 0)
    trackBg:SetColorTexture(ns.TC("textHi", TRACK_IDLE))
    roundTexture(s, trackBg, MASK_ROUNDED)

    -- Inner shadow along the top lip: reads as carved into the panel instead of
    -- laid on top of it. Two pixels is enough; more looks like a smudge.
    local trackShade = s:CreateTexture(nil, "ARTWORK", nil, 2)
    trackShade:SetPoint("TOPLEFT",  trackBg, "TOPLEFT",  0, 0)
    trackShade:SetPoint("TOPRIGHT", trackBg, "TOPRIGHT", 0, 0)
    trackShade:SetHeight(2)
    UI.SetGradient(trackShade, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.45)
    roundTexture(s, trackShade, MASK_ROUNDED)

    local trackFill = s:CreateTexture(nil, "ARTWORK", nil, 3)
    trackFill:SetHeight(6)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(accent.r, accent.g, accent.b, 0.95)
    roundTexture(s, trackFill, MASK_ROUNDED)

    -- One-pixel gloss on the fill's top edge; the classic glass cue. Inset by a
    -- pixel so it cannot poke out of the fill's rounded corners.
    local fillGloss = s:CreateTexture(nil, "ARTWORK", nil, 4)
    fillGloss:SetPoint("TOPLEFT",  trackFill, "TOPLEFT",   1, 0)
    fillGloss:SetPoint("TOPRIGHT", trackFill, "TOPRIGHT", -1, 0)
    fillGloss:SetHeight(1)
    fillGloss:SetColorTexture(1, 1, 1, 0.12)

    s._trackBg, s._trackFill = trackBg, trackFill
    s._updateFill = function(v) sliderUpdateFill(s, v) end

    -- Accent halo behind the knob, so it reads as a control rather than a blob.
    -- ~1.3x the knob; at 2x it stops looking deliberate and starts looking broken.
    local thumbGlow = s:CreateTexture(nil, "ARTWORK", nil, 5)
    thumbGlow:SetSize(20, 20)
    thumbGlow:SetColorTexture(accent.r, accent.g, accent.b, 0.5)
    roundTexture(s, thumbGlow, MASK_CIRCLE)
    thumbGlow:Hide()

    if thumb and ns.theme.art then
        -- Blizzard's knob (UISliderTemplate, or MinimalSliderTemplate for the
        -- modern art); it carries its own shading, so no halo
        if ns.theme.art == "modern" then
            thumb:SetAtlas("Minimal_SliderBar_Button")
            thumb:SetSize(20, 19)
        else
            thumb:SetTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
            thumb:SetSize(32, 32)
        end
        thumb:SetDrawLayer("OVERLAY")
    elseif thumb then
        -- Desaturated knob over a saturated fill separates on two channels at
        -- once, which holds up far better than brightness alone.
        thumb:SetColorTexture(ns.TC("thumb"))
        thumb:SetSize(15, 15)
        thumb:SetDrawLayer("OVERLAY")     -- keep it above the halo
        roundTexture(s, thumb, MASK_CIRCLE)
        thumbGlow:SetPoint("CENTER", thumb, "CENTER", 0, 0)
        thumbGlow:Show()
    end

    -- Eased hover, instant press. Current values live in upvalues so an
    -- interrupted fade continues from where it actually is rather than snapping
    -- back to a base value first.
    local GLOW_IDLE, GLOW_HOVER, GLOW_PRESS = 0.55, 0.9, 1.0
    local glowNow,  glowGoal  = GLOW_IDLE, GLOW_IDLE
    local trackNow, trackGoal = TRACK_IDLE, TRACK_IDLE
    local function paintState()
        thumbGlow:SetAlpha(glowNow)
        trackBg:SetColorTexture(ns.TC("textHi", trackNow))
    end
    local function fadeTick(self, elapsed)
        local k = math.min(1, (elapsed or 0) / 0.18 * 3)
        local settled = true
        if math.abs(glowGoal - glowNow) > 0.004 then
            glowNow = glowNow + (glowGoal - glowNow) * k; settled = false
        else glowNow = glowGoal end
        if math.abs(trackGoal - trackNow) > 0.003 then
            trackNow = trackNow + (trackGoal - trackNow) * k; settled = false
        else trackNow = trackGoal end
        paintState()
        if settled then self:SetScript("OnUpdate", nil) end
    end
    s._setSliderState = function(hovered, pressed)
        glowGoal  = pressed and GLOW_PRESS or (hovered and GLOW_HOVER or GLOW_IDLE)
        trackGoal = (hovered or pressed) and TRACK_HOVER or TRACK_IDLE
        if pressed then
            -- ease OUT of a press, never into it: a fading press feels laggy
            glowNow, trackNow = glowGoal, trackGoal
            s:SetScript("OnUpdate", nil)
            paintState()
        else
            s:SetScript("OnUpdate", fadeTick)
        end
    end
    paintState()
    s._thumbGlow = thumbGlow

    local function makeStepButton(label, dir)
        local b = CreateFrame("Button", nil, s)
        b:SetSize(16, 16)
        local border = b:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(b)
        border:SetColorTexture(ns.TC("border"))
        roundTexture(b, border, MASK_ROUNDED)
        local fill = b:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(ns.TC("control"))
        roundTexture(b, fill, MASK_ROUNDED)
        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(txt, 12)
        txt:SetPoint("CENTER", b, "CENTER", 0, 1)
        txt:SetText(label)
        b:SetScript("OnEnter", function() border:SetColorTexture(accent.r, accent.g, accent.b, 1) end)
        b:SetScript("OnLeave", function() border:SetColorTexture(ns.TC("border")) end)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function()
            local mult = IsShiftKeyDown() and 5 or 1
            s:SetValue(s:GetValue() + dir * (s._step or 1) * mult)
        end)
        return b
    end

    local minusBtn = makeStepButton("-", -1)
    minusBtn:SetPoint("LEFT", s, "RIGHT", 8, 0)

    -- An EDIT BOX, not a label: going from 8 to 190 used to mean holding "+".
    -- Click the number, type it, press Enter. It still reads like plain text
    -- until you touch it, so nothing shouts for attention.
    local valueText = CreateFrame("EditBox", nil, s)
    valueText:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
    valueText:SetSize(36, 18)
    valueText:SetAutoFocus(false)
    valueText:SetJustifyH("CENTER")
    valueText:SetFontObject("GameFontHighlightSmall")
    UI.Font(valueText, 11)
    valueText:SetTextInsets(2, 2, 0, 0)

    local vbg = valueText:CreateTexture(nil, "BACKGROUND")
    vbg:SetAllPoints(valueText)
    vbg:SetColorTexture(ns.TC("textHi", 0.05))
    vbg:Hide()
    valueText:SetScript("OnEnter", function(self) vbg:Show() end)
    valueText:SetScript("OnLeave", function(self) if not self:HasFocus() then vbg:Hide() end end)
    valueText:SetScript("OnEditFocusGained", function(self) vbg:Show(); self:HighlightText() end)

    local function restoreFromSlider(self)
        self:HighlightText(0, 0)
        self:SetText(formatSliderValue(s._step, s:GetValue() or s._min, s._suffix))
        self:ClearFocus()
        if not self:IsMouseOver() then vbg:Hide() end
    end

    valueText:SetScript("OnEnterPressed", function(self)
        -- The unit may be typed along ("50%"); only the number counts.
        -- A decimal comma counts as a point ("1,5" is 1.5 on a German keyboard).
        local typed = tonumber(((self:GetText() or ""):gsub(",", ".")):match("^%s*(-?[%d%.]+)"))
        if typed then
            -- Clamp before snapping: typing 9999 into a 0..100 slider should
            -- land on 100, not be refused without a word.
            typed = math.max(s._min, math.min(s._max, typed))
            s:SetValue(snapSliderValue(s._step, typed))
        end
        restoreFromSlider(self)
    end)
    valueText:SetScript("OnEscapePressed", restoreFromSlider)
    valueText:SetScript("OnEditFocusLost", restoreFromSlider)

    s._valueText = valueText

    local plusBtn = makeStepButton("+", 1)
    plusBtn:SetPoint("LEFT", valueText, "RIGHT", 4, 0)

    s:SetScript("OnValueChanged", function(self, v)
        local cfg = self._vcConfig
        if not cfg then return end
        v = snapSliderValue(cfg.step, v)
        -- Never fight the user's cursor: if they are typing in the box, the
        -- slider must not overwrite what is half-entered.
        if not self._valueText:HasFocus() then
            self._valueText:SetText(formatSliderValue(cfg.step, v, cfg.suffix))
        end
        sliderUpdateFill(self, v)
        if self._configuring then return end
        cfg.set(self, v)
    end)

    attachTooltip(s)
    -- hooked after attachTooltip so its own handlers can't displace these
    s:HookScript("OnEnter", function(self)
        if self._setSliderState then self._setSliderState(true, self._pressed) end
    end)
    s:HookScript("OnLeave", function(self)
        if self._setSliderState then self._setSliderState(false, self._pressed) end
    end)
    s:HookScript("OnMouseDown", function(self)
        self._pressed = true
        if self._setSliderState then self._setSliderState(true, true) end
    end)
    -- IsMouseOver decides the target, or letting go off-frame strands it bright
    s:HookScript("OnMouseUp", function(self)
        self._pressed = nil
        if self._setSliderState then self._setSliderState(self:IsMouseOver(), false) end
    end)

    -- ---- one-line row --------------------------------------------------
    -- The slider keeps every bit of its own drawing; it simply stops being the
    -- thing the page places. The row is [label][track][- value +] -- the same
    -- shape a toggle and a dropdown row have, which is what lets a page of
    -- mixed controls line up on one edge instead of on three.
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SLIDER_ROW_H)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(row.label, 12)
    row.label:SetTextColor(ns.TC("label"))
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWordWrap(false)

    s:SetParent(row)
    s:ClearAllPoints()
    -- The template's own label is retired: the row owns the text now. Leaving
    -- it alive would draw a second, centred copy over the track.
    if s.Text then s.Text:SetText(""); s.Text:Hide() end

    row._slider = s
    row._labelW = SLIDER_LABEL_W
    row._endW   = 90

    -- Re-anchored now that the row exists: the block hangs off the ROW's right
    -- edge, not the track's. Chained to the track it inherited every pixel the
    -- track's minimum width invented, and in a narrow cell that put the value
    -- box and the + button on top of the neighbouring column. Anchored here the
    -- row is a closed box -- nothing it contains can leave it, whatever width
    -- the page hands it.
    plusBtn:ClearAllPoints()
    plusBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueText:ClearAllPoints()
    valueText:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
    minusBtn:ClearAllPoints()
    minusBtn:SetPoint("RIGHT", valueText, "LEFT", -4, 0)

    row.SetLabelWidth = function(self, w)
        self._labelW = math.max(20, w or SLIDER_LABEL_W)
        layoutSliderRow(self)
    end
    row:SetScript("OnSizeChanged", function(self) layoutSliderRow(self) end)
    row.Relayout = function(self) layoutSliderRow(self) end

    row._vcType  = "slider"
    row._vcSetup = sliderSetup
    sliderSetup(row, config)
    return row
end
