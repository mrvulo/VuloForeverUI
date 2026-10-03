-- VuloForeverUI / UI / Widgets / Buttons: text button, icon button and power button.
local _, ns = ...
local UI = ns.UI
local W = UI._W

local clean, configTip = W.clean, W.configTip

-- Button config: { label, tooltip?, onClick, width?, height?, primary?, danger? }
-- danger wins over primary: a destructive action keeps its warning color even
-- when it is also the centred main action of its row.
local BTN_DANGER = { r = 0.85, g = 0.28, b = 0.28 }

local function buttonApplyIdle(b)
    local cfg = b._vcConfig
    if b._artParts then
        -- Blizzard's buttons tell danger and primary apart by label only
        b._textFS:SetTextColor(1, 0.82, 0)
        UI.SetButtonArtPressed(b, false)
    elseif cfg and cfg.danger then
        b._bg:SetColorTexture(ns.TC("control"))
        b._setBorder(BTN_DANGER, 0.70)
        b._textFS:SetTextColor(ns.TC("danger", 0.95))
    elseif cfg and cfg.primary then
        local a = ns.COLORS.accent
        b._bg:SetColorTexture(ns.TC("control"))
        b._setBorder(a, 0.70)
        b._textFS:SetTextColor(a.r, a.g, a.b, 0.95)
    else
        b._bg:SetColorTexture(ns.TC("control"))
        b._setBorder(ns.COLORS.border)
        b._textFS:SetTextColor(ns.TC("label"))
    end
end

local function buttonSetup(b, config)
    b._vcConfig = config
    b._textFS:SetText(clean(config.label) or "")
    local w = config.width or 120
    local tw = (b._textFS:GetStringWidth() or 0) + 36
    b:SetSize(math.max(w, tw), config.height or 26)
    buttonApplyIdle(b)
end

function UI:CreateButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b._bg = bg

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    b._setBorder = function(c, a)
        for _, bt in ipairs(borders) do bt:SetColorTexture(c.r, c.g, c.b, a or 1) end
    end
    b._borders = borders

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._textFS = text

    b:SetScript("OnEnter", function(self)
        local cfg = self._vcConfig
        if self._artParts then
            self._textFS:SetTextColor(1, 1, 1)
        elseif cfg and cfg.danger then
            local d = BTN_DANGER
            bg:SetColorTexture(d.r * 0.20, d.g * 0.20, d.b * 0.20, 1)
            self._setBorder(d, 1)
            self._textFS:SetTextColor(1, 0.45, 0.45, 1)
        elseif cfg and cfg.primary then
            local a = ns.COLORS.accent
            bg:SetColorTexture(a.r * 0.16, a.g * 0.16, a.b * 0.16, 1)
            self._setBorder(a, 1)
            self._textFS:SetTextColor(a.r, a.g, a.b, 1)
        else
            bg:SetColorTexture(ns.TC("controlHover"))
            self._setBorder(ns.COLORS.accent, 0.8)
        end
        UI:ShowTooltip(self, configTip(self))
    end)
    b:SetScript("OnLeave", function(self)
        buttonApplyIdle(self)
        UI:HideTooltip()
    end)

    b:SetScript("OnMouseDown", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, -1)
        UI.SetButtonArtPressed(self, true)
    end)
    b:SetScript("OnMouseUp", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, 0)
        UI.SetButtonArtPressed(self, false)
    end)

    b:SetScript("OnClick", function(self)
        -- Commit the neighbouring edit box FIRST. A WoW edit box keeps its
        -- keyboard focus through a button click (nothing steals it), so an
        -- "Add" clicked right after typing ran against the EMPTY committed
        -- value and silently did nothing -- the field only ever committed via
        -- Enter. Clearing focus here fires OnEditFocusLost synchronously,
        -- which is where commitOnFocusLost hands the text over, and only then
        -- does the click handler run.
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.ClearFocus then focus:ClearFocus() end
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    if ns.theme.art then UI.ApplyButtonArt(b) end

    b._vcType  = "button"
    b._vcSetup = buttonSetup
    buttonSetup(b, config)
    return b
end

-- IconButton config: { icon = "up"/"down"/"left"/"right" or a texture path, tooltip?, onClick, width?, height?, iconInset? }
local ARROW_DIR = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\"
local BUILTIN_ICONS = {
    up    = { tex = ARROW_DIR .. "arrow_up.tga",    tc = {0, 1, 0, 1} },
    down  = { tex = ARROW_DIR .. "arrow_down.tga",  tc = {0, 1, 0, 1} },
    left  = { tex = ARROW_DIR .. "arrow_left.tga",  tc = {0, 1, 0, 1} },
    right = { tex = ARROW_DIR .. "arrow_right.tga", tc = {0, 1, 0, 1} },
}

local function iconButtonSetup(b, config)
    b._vcConfig = config
    b:SetSize(config.width or 24, config.height or 24)
    local icon = b._icon
    local inset = config.iconInset or 10
    icon:SetSize((config.width or 24) - inset, (config.height or 24) - inset)
    icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)

    local iconKey = config.icon
    local builtin = iconKey and BUILTIN_ICONS[iconKey]
    if builtin then
        icon:SetTexture(builtin.tex)
        icon:SetTexCoord(unpack(builtin.tc))
    else
        icon:SetTexCoord(0, 1, 0, 1)
        if iconKey then icon:SetTexture(iconKey) end
    end
end

function UI:CreateIconButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(ns.TC("control"))

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._icon = icon

    b:SetScript("OnEnter", function(self)
        bg:SetColorTexture(ns.TC("controlHover"))
        icon:SetVertexColor(ns.TC("textHi"))
        UI:ShowTooltip(self, configTip(self))
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(ns.TC("control"))
        icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    b._vcType  = "iconbutton"
    b._vcSetup = iconButtonSetup
    iconButtonSetup(b, config)
    return b
end

-- PowerButton config: { size?, tooltip?, get() -> bool, set(bool) }
function UI:CreatePowerButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.size or 14, config.size or 14)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\power")
    b._icon = icon

    local function refresh()
        local on = config.get() and true or false
        if on then
            icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            icon:SetVertexColor(ns.TC("textMuted", 0.6))
        end
    end

    b:SetScript("OnClick", function()
        local newState = not (config.get() and true or false)
        config.set(newState)
        refresh()
    end)

    b:SetScript("OnEnter", function()
        icon:SetVertexColor(ns.TC("textHi"))
        if config.tooltip then
            UI:ShowTooltip(b, { title = config.tooltip, wrap = true })
        end
    end)
    b:SetScript("OnLeave", function()
        refresh()
        UI:HideTooltip()
    end)

    refresh()
    b._refresh = refresh
    return b
end
