-- VuloForeverUI / UI / Widgets / Dropdown: segmented control and the closed dropdown box that opens the shared menu.
local _, ns = ...
local UI = ns.UI
local L = ns.L
local W = UI._W

local clean, labelClipped, configTip = W.clean, W.labelClipped, W.configTip
local closeActivePopup, measureItem, openPopup = W.closeActivePopup, W.measureItem, W.openPopup

-- Segmented control: CreateSegmented(parent, config)
--
-- Same contract as a dropdown -- { label, values = {{value, text}, ...}, get,
-- set } -- drawn as a row of buttons instead of a menu. For two to four fixed
-- choices it is one click where the menu costs two, and the alternatives are
-- readable without opening anything. Beyond four the buttons get too narrow for
-- a translated label; use a dropdown there.
local SEG_H = 22

local function segRelayout(container)
    local strip = container._strip
    local n     = container._segCount or 0
    if n == 0 then return end
    local w = strip:GetWidth() or 0
    if w <= 1 then return end   -- not laid out yet; OnSizeChanged brings us back

    -- Integer widths, and the remainder handed out one pixel at a time rather
    -- than all of it to the last button: a rounded-down width times four leaves
    -- a visible notch at the right edge otherwise.
    local base, extra = math.floor((w - (n - 1)) / n), (w - (n - 1)) % n
    local x = 0
    for i = 1, n do
        local b  = container._segs[i]
        local bw = base + (i <= extra and 1 or 0)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", strip, "TOPLEFT", x, 0)
        b:SetSize(bw, SEG_H)
        x = x + bw + 1
    end
end

local function segRefresh(container)
    local cfg = container._vcConfig
    if not cfg then return end
    local cur = cfg.get and cfg.get()
    for i = 1, (container._segCount or 0) do
        local b  = container._segs[i]
        local on = (b._value == cur)
        local c  = on and ns.COLORS.accent or ns.COLORS.border
        b._bg:SetColorTexture(c.r, c.g, c.b, on and 0.85 or 0.18)
        if on then
            b._text:SetTextColor(ns.TC("textHi"))
        else
            b._text:SetTextColor(ns.TC("textDim"))
        end
        b._on = on
    end
end

local function makeSegButton(container)
    local b = CreateFrame("Button", nil, container._strip)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b._bg = bg

    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(t, 11)
    t:SetPoint("LEFT",  b, "LEFT",   4, 0)
    t:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    t:SetJustifyH("CENTER")
    t:SetWordWrap(false)
    b._text = t

    b:SetScript("OnEnter", function(self)
        if not self._on then
            local a = ns.COLORS.accent
            self._bg:SetColorTexture(a.r, a.g, a.b, 0.35)
        end
    end)
    b:SetScript("OnLeave", function() segRefresh(container) end)
    b:SetScript("OnClick", function(self)
        local cfg = container._vcConfig
        if cfg and cfg.set then cfg.set(nil, self._value) end
        segRefresh(container)
    end)
    return b
end

local function segmentedSetup(container, config)
    container._vcConfig = config
    container._labelW   = nil   -- pooled: a column from the last page must not stick

    local label = container._label
    if config.label and config.label ~= "" then
        label:SetText(clean(config.label))
        label:Show()
        label:SetWidth(0)
        container._strip:SetPoint("LEFT", label, "RIGHT", 10, 0)
    else
        label:Hide()
        container._strip:SetPoint("LEFT", container, "LEFT", 0, 0)
    end

    local values = config.values or {}
    for i = 1, #values do
        local b = container._segs[i]
        if not b then
            b = makeSegButton(container)
            container._segs[i] = b
        end
        b._value = values[i].value
        b._text:SetText(tostring(values[i].text or values[i].value))
        b:Show()
    end
    for i = #values + 1, #container._segs do container._segs[i]:Hide() end
    container._segCount = #values

    container:SetHeight(26)
    segRelayout(container)
    segRefresh(container)
end

function UI:CreateSegmented(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container._segs = {}

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(ns.TC("label"))
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    container._label = label

    local strip = CreateFrame("Frame", nil, container)
    strip:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    strip:SetHeight(SEG_H)
    container._strip = strip

    -- The builder sets the row's width AFTER the widget exists, so the buttons
    -- cannot be sized at construction. Relayout when the strip actually gets its
    -- size -- the same reason the reference build hooks OnSizeChanged rather
    -- than measuring once.
    strip:SetScript("OnSizeChanged", function() segRelayout(container) end)
    container.Relayout = function(self) segRelayout(self) end

    container.SetLabelWidth = function(self, w)
        self._labelW = w and math.max(20, w) or nil
        if self._label and self._label:IsShown() then
            self._label:SetWidth(self._labelW or 0)
        end
    end
    container.Refresh = segRefresh

    container._vcType  = "segmented"
    container._vcSetup = segmentedSetup
    segmentedSetup(container, config)
    return container
end

-- The box width a labeled dropdown row aims for; bounded by the row so a
-- narrow group cell still leaves the label 70px. Recomputed on every resize
-- because the builder widens rows AFTER setup.
local function dropdownRelayout(container)
    local cfg = container._vcConfig
    if not (cfg and cfg.label) then return end
    local want = cfg.boxWidth or 220
    local w = container:GetWidth() or 240
    container._button:SetWidth(math.max(100, math.min(want, w - 70)))
end

-- The container is the row: SetWidth() on it reflows label and button.
local function dropdownSetup(container, config)
    container._vcConfig = config
    local btn, label = container._button, container._label
    btn:ClearAllPoints(); label:ClearAllPoints()
    -- Cleared on every setup: these come from a pool, and a label column left
    -- over from the last page that used this frame would silently apply here.
    container._labelW = nil
    if config.label then
        label:SetText(clean(config.label))
        label:Show()
        label:SetWidth(0)
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        btn:SetHeight(24)
        -- The box hangs on the ROW'S right edge at a bounded width instead of
        -- growing out of its label's end: boxes used to begin wherever the
        -- label happened to stop -- one x per row (user report, 31.07.2026).
        -- Right edge plus equal width puts every box on the same two lines;
        -- clipped labels and values already restore in the hover tooltip.
        btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        label:SetPoint("RIGHT", btn, "LEFT", -10, 0)
        container:SetSize(config.width or 240, 28)
        dropdownRelayout(container)
    else
        label:Hide()
        btn:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        btn:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
        container:SetSize(config.width or 160, 26)
    end
    btn._refresh()
end

function UI:CreateDropdown(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetScript("OnSizeChanged", dropdownRelayout)
    -- And on demand. OnSizeChanged is the client's, which means it fires when
    -- the client gets round to it and NOT AT ALL when a set width happens to
    -- equal the width the frame already had. These come from a pool: a
    -- container handed back at exactly the width its next row asks for keeps
    -- the box of its previous row, and one class row in nine is then half a
    -- cell wider than its neighbours (user report, 22.09.2026). The builder
    -- calls this straight after it sizes a row, so the box follows the cell
    -- it is actually in rather than an event that may never come.
    container.Relayout = dropdownRelayout

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(ns.TC("label"))
    container._label = label

    local btn = CreateFrame("Button", nil, container)
    btn:SetHeight(24)
    container._button = btn

    -- Same contract the slider row has. The button is anchored to the label's
    -- right edge, so a label at its natural width starts every dropdown on a
    -- page at a different x -- nine class rows above one another, each box a few
    -- pixels off the last. Given a column, they all start on one line.
    container.SetLabelWidth = function(self, w)
        self._labelW = w and math.max(20, w) or nil
        if self._label and self._label:IsShown() then
            self._label:SetWidth(self._labelW or 0)
        end
    end

    -- same geometry StyleBackdrop draws; it keeps the four edges on the frame as
    -- _vcBorders, which is what the hover recolour below uses
    UI:StyleBackdrop(btn, { bg = ns.COLORS.popup })
    local borders = btn._vcBorders

    local valueText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(valueText, 12)
    valueText:SetPoint("LEFT",  btn, "LEFT",   8, 0)
    valueText:SetPoint("RIGHT", btn, "RIGHT", -22, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetWordWrap(false)

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    arrow:SetTexCoord(0.25, 0.75, 0.30, 0.80)
    arrow:SetVertexColor(ns.TC("textDim"))

    local function setHovered(state)
        local c = state and ns.COLORS.accent or ns.COLORS.border
        for _, b in ipairs(borders) do
            b:SetColorTexture(c.r, c.g, c.b, 1)
        end
        if state then
            arrow:SetVertexColor(ns.TC("textHi"))
        else
            arrow:SetVertexColor(ns.TC("textDim"))
        end
    end
    btn._setHovered = setHovered

    local function setText(text) valueText:SetText(clean(text) or "") end
    btn._setText = setText

    local function refresh()
        local cfg = container._vcConfig
        if not cfg then return end
        -- A multi-select box has no single value to name, so it names the ones
        -- that ARE on. The closed box clips what does not fit and the hover
        -- tooltip restores it, which is the behaviour a long single value
        -- already has here.
        if cfg.multi then
            local parts = {}
            for _, opt in ipairs(cfg.values or {}) do
                if opt.value ~= nil and cfg.isChecked and cfg.isChecked(opt.value) then
                    parts[#parts + 1] = clean(L[opt.text])
                end
            end
            setText(#parts > 0 and table.concat(parts, ", ") or (cfg.emptyText or L["None"]))
            return
        end
        local current = cfg.get(btn)
        for _, opt in ipairs(cfg.values or {}) do
            if opt.value == current then
                setText(L[opt.text])
                return
            end
        end
        setText(tostring(current or ""))
    end
    btn._refresh = refresh

    btn:SetScript("OnEnter", function(self)
        setHovered(true)
        -- The closed box clips its value more often than the open menu does: it
        -- lives in a page column, and 8px of inset plus the 22px arrow leave
        -- little for a translated seal name. Whatever got cut -- the label, the
        -- value, or both -- leads the tooltip, and the configured explanation
        -- follows it rather than replacing it, so hovering never costs anything.
        local cfg = container._vcConfig
        local labelFull = labelClipped(container._label)
        local shown = valueText:GetText()
        local room  = (self:GetWidth() or 0) - 30
        local valueFull
        if shown and shown ~= "" and room > 0 and measureItem(shown) > room then
            valueFull = shown
        end
        local title = labelFull or valueFull
        if not title then
            UI:ShowTooltip(self, configTip(container))
            return
        end
        local lines = {}
        if labelFull and valueFull then
            lines[#lines + 1] = { valueFull, 0.90, 0.90, 0.95, true }
        end
        if cfg and cfg.tooltip then
            lines[#lines + 1] = { cfg.tooltip, nil, nil, nil, true }
        end
        UI:ShowTooltip(self, { title = title, wrap = true, lines = (#lines > 0) and lines or nil })
    end)
    btn:SetScript("OnLeave", function()
        UI:HideTooltip()
        if not (W.activePopup and W.activePopup:IsShown() and W.activePopup._owner == btn) then
            setHovered(false)
        end
    end)

    btn:SetScript("OnClick", function(self)
        if W.activePopup and W.activePopup:IsShown() and W.activePopup._owner == self then
            closeActivePopup()
        else
            closeActivePopup()
            openPopup(self, container._vcConfig or {})
            setHovered(true)
        end
    end)

    container._vcType  = "dropdown"
    container._vcSetup = dropdownSetup
    dropdownSetup(container, config)
    return container
end
