-- VuloForeverUI / UI / Widgets / Inputs: labeled edit box and color swatch.
local _, ns = ...
local UI = ns.UI
local L = ns.L
local W = UI._W

local FONT_PATH, clean, attachTooltip = W.FONT_PATH, W.clean, W.attachTooltip

-- EditBox config: { label?, tooltip?, get, set, numeric?, width?, editWidth?, commitOnFocusLost?, onEnter? }
local function editboxSetup(container, config)
    container._vcConfig = config
    local label, eb = container._labelFS, container._editBox
    eb:ClearAllPoints(); label:ClearAllPoints()
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)

    if config.label and config.label ~= "" then
        label:SetText(clean(config.label))
        label:Show()
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        local editW = config.editWidth or 130
        eb:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        eb:SetWidth(editW)
        label:SetPoint("RIGHT", eb, "LEFT", -10, 0)
        local labelW = label:GetStringWidth() or 80
        container:SetWidth(config.width or (labelW + 14 + editW))
    else
        label:Hide()
        eb:SetPoint("LEFT", container, "LEFT", 0, 0)
        eb:SetWidth(config.width or 160)
        container:SetWidth(config.width or 160)
    end

    eb:ClearFocus()
    eb:SetText(tostring(config.get(eb) or ""))
end

function UI:CreateEditBox(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(26)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(ns.TC("label"))
    container._labelFS = label

    local eb = CreateFrame("EditBox", nil, container)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_PATH, 12, "")
    eb:SetTextInsets(8, 8, 0, 0)
    container._editBox = eb

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(eb)
    bg:SetColorTexture(ns.TC("input"))
    eb._bg = bg

    local borderColor = ns.COLORS.border or { r = 0.35, g = 0.25, b = 0.55, a = 1 }
    local borderFrame = CreateFrame("Frame", nil, eb,
        BackdropTemplateMixin and "BackdropTemplate")
    borderFrame:SetAllPoints(eb)
    if borderFrame.SetBackdrop then
        borderFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
    end
    eb._borderFrame = borderFrame

    eb:SetScript("OnEditFocusGained", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            local c = ns.COLORS.accent
            self._borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            self._borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
        end
        -- opt-in: an adjacent button steals focus before its OnClick, so commit here too
        local cfg = container._vcConfig
        if cfg and cfg.commitOnFocusLost then
            local v = self:GetText()
            if cfg.numeric then v = tonumber(v) end
            cfg.set(self, v)
        end
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local cfg = container._vcConfig
        if not cfg then self:ClearFocus(); return end
        local v = self:GetText()
        if cfg.numeric then v = tonumber(v) end
        cfg.set(self, v)
        self:ClearFocus()
        if cfg.onEnter then cfg.onEnter(v) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    attachTooltip(container)
    container._vcType  = "editbox"
    container._vcSetup = editboxSetup
    editboxSetup(container, config)
    return container
end

-- ColorSwatch config: { label, get() -> {r,g,b} or {r=,g=,b=}, set(r,g,b[,a]), width?, hasAlpha? }
-- hasAlpha: the picker shows an opacity bar and set receives the alpha too.
function UI:CreateColorSwatch(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12); label:SetTextColor(ns.TC("label"))
    label:SetPoint("LEFT", b, "LEFT", 0, 0)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    b._label = label

    local sw = CreateFrame("Button", nil, b)
    sw:SetSize(18, 18)
    sw:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 0.8)
    local fill = sw:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b._fill = fill
    label:SetPoint("RIGHT", sw, "LEFT", -8, 0)

    -- Optional per-row reset between label and swatch; exists only while the
    -- config carries onReset. Pooled reuse hides it again via _vcSetup.
    local rb = CreateFrame("Button", nil, b)
    rb:SetSize(16, 16)
    rb:SetPoint("RIGHT", sw, "LEFT", -6, 0)
    local rt = rb:CreateTexture(nil, "ARTWORK")
    rt:SetAllPoints()
    rt:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\reset.tga")
    rt:SetVertexColor(ns.TC("textSoft", 0.55))
    rb:Hide()

    local function curRGB()
        local cfg = b._vcConfig
        local c = cfg and cfg.get and cfg.get()
        if not c then return 1, 1, 1 end
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
    end
    local function refresh()
        local r, g, bl = curRGB(); fill:SetColorTexture(r, g, bl, 1)
        -- labelTint paints the label in the row's own color (class-color rows);
        -- pooled reuse without the flag gets the standard color back.
        local cfg = b._vcConfig
        if cfg and cfg.labelTint then
            label:SetTextColor(r, g, bl)
        else
            label:SetTextColor(ns.TC("label"))
        end
    end
    local function open()
        local r, g, bl = curRGB()
        local cfg = b._vcConfig
        local c = cfg and cfg.get and cfg.get()
        ns:ShowColorPicker({ r = r, g = g, b = bl, a = c and (c.a or c[4]) or 1,
            hasAlpha = cfg and cfg.hasAlpha,
            onChange = function(nr, ng, nb, na)
                local cur = b._vcConfig
                if cur and cur.set then cur.set(nr, ng, nb, na) end
                refresh()
            end })
    end
    b:SetScript("OnClick", open)
    sw:SetScript("OnClick", open)
    sw:SetScript("OnEnter", function() border:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end)
    sw:SetScript("OnLeave", function() border:SetColorTexture(0, 0, 0, 0.8) end)
    rb:SetScript("OnEnter", function() rt:SetVertexColor(ns.TC("textHi", 0.9)); UI:ShowTooltip(rb, L["Reset to default"]) end)
    rb:SetScript("OnLeave", function() rt:SetVertexColor(ns.TC("textSoft", 0.55)); UI:HideTooltip() end)
    rb:SetScript("OnClick", function()
        local cfg = b._vcConfig
        if cfg and cfg.onReset then cfg.onReset() end
        refresh()
    end)

    b._refresh = refresh
    b._vcType  = "color"
    b._vcSetup = function(self, cfg)
        self._vcConfig = cfg
        self._label:SetText(clean(cfg.label) or "")
        local hasReset = cfg.onReset ~= nil
        rb:SetShown(hasReset)
        -- Re-anchoring the same point replaces it; the label clamps against
        -- whatever sits leftmost on the control side.
        label:SetPoint("RIGHT", hasReset and rb or sw, "LEFT", -8, 0)
        local extra = hasReset and 22 or 0
        if cfg.width then
            self:SetSize(cfg.width, 22)
        else
            self:SetSize(math.max((self._label:GetStringWidth() or 0) + 12 + 18 + extra, 120), 22)
        end
        refresh()
    end
    b._vcSetup(b, config)
    return b
end
