-- Custom HSV colour picker singleton, replacing Blizzard's ColorPickerFrame; onChange fires live while dragging, Cancel/click-away restores via onChange.
local _, ns = ...
local L = ns.L

-- HSV <-> RGB (h in [0,360], s/v/r/g/b in [0,1])
local floor, abs, max, min = math.floor, math.abs, math.max, math.min

local function HSVtoRGB(h, s, v)
    local c  = v * s
    local hp = (h % 360) / 60
    local x  = c * (1 - abs(hp % 2 - 1))
    local r, g, b = 0, 0, 0
    if     hp < 1 then r, g, b = c, x, 0
    elseif hp < 2 then r, g, b = x, c, 0
    elseif hp < 3 then r, g, b = 0, c, x
    elseif hp < 4 then r, g, b = 0, x, c
    elseif hp < 5 then r, g, b = x, 0, c
    else               r, g, b = c, 0, x end
    local m = v - c
    return r + m, g + m, b + m
end

local function RGBtoHSV(r, g, b)
    local mx, mn = max(r, g, b), min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if     mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else                h = (r - g) / d + 4 end
        h = h * 60
        if h < 0 then h = h + 360 end
    end
    return h, (mx == 0) and 0 or (d / mx), mx
end

local SV      = 200    -- saturation/value square
local BARW    = 22     -- hue bar width
local RIGHTW  = 104    -- right column (swatches / hex / buttons)
local PAD     = 16
local TITLE_H = 30

local picker  -- singleton

local function addBorder(frame, r, g, b, a)
    local function edge()
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(r, g, b, a)
        return t
    end
    local top = edge(); top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); top:SetHeight(1)
    local bot = edge(); bot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); bot:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); bot:SetHeight(1)
    local lft = edge(); lft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0); lft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0); lft:SetWidth(1)
    local rgt = edge(); rgt:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0); rgt:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0); rgt:SetWidth(1)
end

local function font(fs, size, flags)
    if ns.UI and ns.UI.Font then ns.UI.Font(fs, size, flags) else fs:SetFont(STANDARD_TEXT_FONT, size, flags or "") end
    return fs
end

local function build()
    if picker then return picker end
    local accent = ns.COLORS.accent
    local W = PAD + SV + 12 + BARW + 22 + RIGHTW + PAD
    local H = TITLE_H + SV + 42

    local f = CreateFrame("Frame", "VFUIColorPicker", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(500)
    f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
    f:Hide()
    if ns.UI and ns.UI.CreateShadow then ns.UI:CreateShadow(f) end

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.05, 0.06, 0.09, 0.98)
    addBorder(f, accent.r, accent.g, accent.b, 0.5)

    -- Full-screen click catcher (cancel on click outside)
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(490)
    catcher:Hide()
    f._catcher = catcher

    local title = CreateFrame("Frame", nil, f)
    title:SetHeight(TITLE_H)
    title:SetPoint("TOPLEFT"); title:SetPoint("TOPRIGHT")
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() f:StartMoving() end)
    title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    local titleTx = font(title:CreateFontString(nil, "OVERLAY"), 13)
    titleTx:SetPoint("CENTER", title, "CENTER", 0, 0)
    titleTx:SetTextColor(0.95, 0.95, 0.97)
    titleTx:SetText(L["Color Picker"])

    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 10)
    local cx = font(closeBtn:CreateFontString(nil, "OVERLAY"), 16)
    cx:SetPoint("CENTER"); cx:SetText("\195\151"); cx:SetTextColor(0.7, 0.7, 0.75)
    closeBtn:SetScript("OnEnter", function() cx:SetTextColor(1, 1, 1) end)
    closeBtn:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
    closeBtn:SetScript("OnClick", function() f._cancel() end)

    f._h, f._s, f._v = 0, 1, 1
    f._suppress = false

    local svPad = CreateFrame("Frame", nil, f)
    svPad:SetSize(SV, SV)
    svPad:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TITLE_H)
    svPad:EnableMouse(true)

    local svHue = svPad:CreateTexture(nil, "BACKGROUND"); svHue:SetAllPoints(); svHue:SetColorTexture(1, 0, 0, 1)
    local svWhite = svPad:CreateTexture(nil, "BORDER"); svWhite:SetAllPoints()
    ns.UI.SetGradient(svWhite, "HORIZONTAL", 1, 1, 1, 1, 1, 1, 1, 0)   -- left white -> right clear
    local svBlack = svPad:CreateTexture(nil, "ARTWORK"); svBlack:SetAllPoints()
    ns.UI.SetGradient(svBlack, "VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0)     -- bottom black -> top clear
    addBorder(svPad, 1, 1, 1, 0.10)

    local ARM = 5
    local chT = svPad:CreateTexture(nil, "OVERLAY"); chT:SetSize(1, ARM); chT:SetColorTexture(1, 1, 1, 0.9)
    local chB = svPad:CreateTexture(nil, "OVERLAY"); chB:SetSize(1, ARM); chB:SetColorTexture(1, 1, 1, 0.9)
    local chL = svPad:CreateTexture(nil, "OVERLAY"); chL:SetSize(ARM, 1); chL:SetColorTexture(1, 1, 1, 0.9)
    local chR = svPad:CreateTexture(nil, "OVERLAY"); chR:SetSize(ARM, 1); chR:SetColorTexture(1, 1, 1, 0.9)
    f._svHue = svHue
    f._setCrosshair = function(s, v)
        local x, y = s * SV, -(1 - v) * SV
        chT:ClearAllPoints(); chT:SetPoint("BOTTOM", svPad, "TOPLEFT", x, y + 2)
        chB:ClearAllPoints(); chB:SetPoint("TOP",    svPad, "TOPLEFT", x, y - 2)
        chL:ClearAllPoints(); chL:SetPoint("RIGHT",  svPad, "TOPLEFT", x - 2, y)
        chR:ClearAllPoints(); chR:SetPoint("LEFT",   svPad, "TOPLEFT", x + 2, y)
    end

    local function svFromCursor()
        local cxp, cyp = GetCursorPosition()
        local scale = svPad:GetEffectiveScale()
        cxp, cyp = cxp / scale, cyp / scale
        local s = max(0, min(1, (cxp - svPad:GetLeft()) / SV))
        local v = max(0, min(1, (cyp - svPad:GetBottom()) / SV))
        return s, v
    end
    svPad:SetScript("OnMouseDown", function(self)
        f._s, f._v = svFromCursor(); f._updateAll()
        self:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
            f._s, f._v = svFromCursor(); f._updateAll()
        end)
    end)
    svPad:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    local hueBar = CreateFrame("Frame", nil, f)
    hueBar:SetSize(BARW, SV)
    hueBar:SetPoint("TOPLEFT", svPad, "TOPRIGHT", 12, 0)
    hueBar:EnableMouse(true)
    local stops = { {1,0,0}, {1,1,0}, {0,1,0}, {0,1,1}, {0,0,1}, {1,0,1}, {1,0,0} }  -- hue 0..360
    local segH = SV / 6
    for i = 1, 6 do
        local seg = hueBar:CreateTexture(nil, "BACKGROUND")
        seg:SetSize(BARW, segH + 0.5)
        seg:SetPoint("TOPLEFT", hueBar, "TOPLEFT", 0, -(i - 1) * segH)
        local c1, c2 = stops[i], stops[i + 1]   -- top=c1 (lower hue), bottom=c2
        ns.UI.SetGradient(seg, "VERTICAL", c2[1], c2[2], c2[3], 1, c1[1], c1[2], c1[3], 1)
    end
    addBorder(hueBar, 1, 1, 1, 0.10)
    local hueInd = hueBar:CreateTexture(nil, "OVERLAY"); hueInd:SetSize(BARW + 6, 2); hueInd:SetColorTexture(1, 1, 1, 0.95)
    f._setHueInd = function(h) hueInd:ClearAllPoints(); hueInd:SetPoint("CENTER", hueBar, "TOP", 0, -(h / 360) * SV) end

    local function hueFromCursor()
        local _, cyp = GetCursorPosition()
        cyp = cyp / hueBar:GetEffectiveScale()
        return max(0, min(360, (hueBar:GetTop() - cyp) / SV * 360))
    end
    hueBar:SetScript("OnMouseDown", function(self)
        f._h = hueFromCursor(); f._updateAll()
        self:SetScript("OnUpdate", function()
            if not IsMouseButtonDown("LeftButton") then self:SetScript("OnUpdate", nil); return end
            f._h = hueFromCursor(); f._updateAll()
        end)
    end)
    hueBar:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)

    local rx = -PAD  -- anchored from TOPRIGHT
    local newLbl = font(f:CreateFontString(nil, "OVERLAY"), 12)
    newLbl:SetPoint("TOPRIGHT", f, "TOPRIGHT", rx - RIGHTW + 2, -(TITLE_H + 2))
    newLbl:SetText(L["New"]); newLbl:SetTextColor(0.8, 0.8, 0.85); newLbl:SetJustifyH("LEFT")

    local function swatch(yTop, h)
        local s = CreateFrame("Button", nil, f)
        s:SetSize(RIGHTW, h)
        s:SetPoint("TOPRIGHT", f, "TOPRIGHT", rx, yTop)
        local t = s:CreateTexture(nil, "ARTWORK"); t:SetPoint("TOPLEFT", 1, -1); t:SetPoint("BOTTOMRIGHT", -1, 1)
        addBorder(s, 0, 0, 0, 0.6)
        s._tex = t
        return s
    end
    local newSw = swatch(-(TITLE_H + 18), 36); f._newTex = newSw._tex
    local prevSw = swatch(-(TITLE_H + 58), 36); f._prevTex = prevSw._tex
    prevSw:SetScript("OnClick", function() f._setFromRGB(f._prev[1], f._prev[2], f._prev[3]) end)

    local prevLbl = font(f:CreateFontString(nil, "OVERLAY"), 12)
    prevLbl:SetPoint("TOPRIGHT", prevSw, "BOTTOMRIGHT", 0, -3)
    prevLbl:SetText(L["Prev"]); prevLbl:SetTextColor(0.8, 0.8, 0.85); prevLbl:SetJustifyH("LEFT")
    prevLbl:SetPoint("TOPLEFT", prevSw, "BOTTOMLEFT", 0, -3)

    local hexLbl = font(f:CreateFontString(nil, "OVERLAY"), 12)
    hexLbl:SetPoint("TOPLEFT", prevSw, "BOTTOMLEFT", 0, -22)
    hexLbl:SetText(L["Hex#"]); hexLbl:SetTextColor(0.8, 0.8, 0.85)

    local hexBox = CreateFrame("EditBox", nil, f)
    hexBox:SetSize(RIGHTW, 24)
    hexBox:SetPoint("TOPLEFT", hexLbl, "BOTTOMLEFT", 0, -4)
    hexBox:SetAutoFocus(false); hexBox:SetMaxLetters(6)
    font(hexBox, 12); hexBox:SetTextColor(0.95, 0.95, 0.97)
    hexBox:SetTextInsets(6, 6, 0, 0)
    local hb = hexBox:CreateTexture(nil, "BACKGROUND"); hb:SetAllPoints(); hb:SetColorTexture(0.10, 0.11, 0.14, 1)
    addBorder(hexBox, accent.r, accent.g, accent.b, 0.4)
    f._hexBox = hexBox
    local function parseHex()
        local s = (hexBox:GetText() or ""):gsub("#", ""):gsub("%s", "")
        if #s == 6 then
            local r = tonumber(s:sub(1, 2), 16)
            local g = tonumber(s:sub(3, 4), 16)
            local b = tonumber(s:sub(5, 6), 16)
            if r and g and b then f._setFromRGB(r / 255, g / 255, b / 255) end
        end
    end
    hexBox:SetScript("OnEnterPressed", function(self) parseHex(); self:ClearFocus() end)
    hexBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local okBtn = ns.UI:CreateButton(f, {
        label = L["OK"], width = RIGHTW, height = 24, primary = true,
        onClick = function() f._accept() end,
    })
    okBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", rx, PAD - 4)

    local cancelBtn = ns.UI:CreateButton(f, {
        label = L["Cancel"], width = RIGHTW, height = 22,
        onClick = function() f._cancel() end,
    })
    cancelBtn:SetPoint("BOTTOMRIGHT", okBtn, "TOPRIGHT", 0, 6)

    f._updateAll = function()
        local r, g, b = HSVtoRGB(f._h, f._s, f._v)
        f._r, f._g, f._b = r, g, b
        local hr, hg, hb = HSVtoRGB(f._h, 1, 1)
        svHue:SetColorTexture(hr, hg, hb, 1)
        f._setCrosshair(f._s, f._v)
        f._setHueInd(f._h)
        f._newTex:SetColorTexture(r, g, b, 1)
        if not hexBox:HasFocus() then
            hexBox:SetText(string.format("%02X%02X%02X", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5)))
        end
        -- _suppress means "draw, but do not notify". It has to gate only this
        -- call: seeding the picker with the current colour is not the user
        -- picking one, but the notification runs straight into the option's
        -- setter. Gating the whole function instead would leave the picker
        -- showing nothing.
        if f._onChange and not f._suppress then f._onChange(r, g, b) end
    end

    f._setFromRGB = function(r, g, b)
        f._h, f._s, f._v = RGBtoHSV(r, g, b)
        f._updateAll()
    end

    f._cancel = function()
        f._catcher:Hide(); f:Hide()
        -- Put the old colour back only if something actually moved. Firing the
        -- setter with an unchanged value made a plain Cancel look like an edit,
        -- reload prompt and all.
        if f._onChange and f._prev then
            local changed = math.abs((f._r or 0) - f._prev[1]) > 0.001
                         or math.abs((f._g or 0) - f._prev[2]) > 0.001
                         or math.abs((f._b or 0) - f._prev[3]) > 0.001
            if changed then f._onChange(f._prev[1], f._prev[2], f._prev[3]) end
        end
        if f._onCancel then f._onCancel() end
    end
    f._accept = function()
        f._catcher:Hide(); f:Hide()
    end
    catcher:SetScript("OnClick", function() f._cancel() end)

    picker = f
    return f
end

function ns:ShowColorPicker(opts)
    opts = opts or {}
    local f = build()
    f._onChange = opts.onChange
    f._onCancel = opts.onCancel
    f._prev = { opts.r or 1, opts.g or 1, opts.b or 1 }
    f._prevTex:SetColorTexture(f._prev[1], f._prev[2], f._prev[3], 1)

    f._suppress = true
    f._setFromRGB(f._prev[1], f._prev[2], f._prev[3])
    f._suppress = false

    f._catcher:Show()
    f:Show()
    f:Raise()
    return f
end
