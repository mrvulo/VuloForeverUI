-- VuloForeverUI / UI / Widgets / Toggle: toggle switch, eye toggle and themed checkbox.
local _, ns = ...
local UI = ns.UI
local W = UI._W

local clean, attachTooltip = W.clean, W.attachTooltip

-- Toggle config: { label, tooltip?, get, set, width?, style = "eye"? }
local TOGGLE_W, TOGGLE_H = 36, 18
local EYE_ON  = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\eye.tga"
local EYE_OFF = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\eye_off.tga"

local function setTrackColor(container, r, g, b)
    for _, t in ipairs(container._trackParts) do t:SetColorTexture(r, g, b, 1) end
end

local function toggleRefresh(container)
    local cfg, btn = container._vcConfig, container._switch
    if not cfg then return end
    local state = cfg.get(btn) and true or false

    if container._eye then
        container._eye:SetTexture(state and EYE_ON or EYE_OFF)
        if state then
            container._eye:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            container._eye:SetVertexColor(ns.TC("textMuted"))
        end
        return
    end

    if container._check then
        container._check:SetShown(state)
        return
    end

    local knob = container._knob
    if state then
        setTrackColor(container, ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        knob:SetColorTexture(ns.TC("knob"))
        knob:ClearAllPoints()
        knob:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
    else
        setTrackColor(container, ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b)
        knob:SetColorTexture(ns.TC("knobOff"))
        knob:ClearAllPoints()
        knob:SetPoint("LEFT", btn, "LEFT", 3, 0)
    end
end

local function toggleFlip(container)
    local cfg = container._vcConfig
    if not cfg then return end
    local newState = not (cfg.get(container._switch) and true or false)
    cfg.set(container._switch, newState)
    toggleRefresh(container)
end

local function toggleSetup(container, config)
    container._vcConfig = config
    local label = container._label
    label:SetText(clean(config.label) or "")

    if config.width then
        container:SetSize(config.width, 22)
    else
        local labelW = label:GetStringWidth() or 0
        container:SetSize(math.max(labelW + 12 + TOGGLE_W, 90), 22)
    end
    toggleRefresh(container)
end

function UI:CreateToggle(parent, config)
    local container = CreateFrame("Frame", nil, parent)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(ns.TC("label"))

    local btn = CreateFrame("Button", nil, container)
    btn:SetSize(TOGGLE_W, TOGGLE_H)
    btn:SetPoint("RIGHT", container, "RIGHT", 0, 0)

    label:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)

    container._switch = btn
    container._label  = label

    if config.style == "eye" then
        btn:SetSize(22, 16)
        local eye = btn:CreateTexture(nil, "ARTWORK")
        eye:SetPoint("CENTER", btn, "CENTER", 0, 0)
        eye:SetSize(22, 16)
        container._eye = eye
    elseif ns.theme.art then
        -- a checkbox in place of the switch: UICheckButtonTemplate's art, or
        -- the minimal one of Blizzard's settings panel
        local box = btn:CreateTexture(nil, "ARTWORK")
        local check = btn:CreateTexture(nil, "OVERLAY")
        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        if ns.theme.art == "modern" then
            box:SetAtlas("checkbox-minimal")
            check:SetAtlas("checkmark-minimal")
            hl:SetAtlas("checkbox-minimal")
            box:SetSize(22, 22)
        else
            box:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
            check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            hl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
            box:SetSize(26, 26)
        end
        box:SetPoint("RIGHT", btn, "RIGHT", 2, 0)
        check:SetAllPoints(box)
        hl:SetBlendMode("ADD")
        hl:SetAllPoints(box)
        container._check = check
    else
        local track = btn:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints(btn)
        track:SetColorTexture(ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b, 1)
        container._trackParts = { track }

        local borderColor = ns.COLORS.borderDark or ns.COLORS.border
        for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local bd = btn:CreateTexture(nil, "BORDER")
            bd:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
            if s == "TOP" or s == "BOTTOM" then
                bd:SetPoint(s .. "LEFT"); bd:SetPoint(s .. "RIGHT"); bd:SetHeight(1)
            else
                bd:SetPoint("TOP" .. s); bd:SetPoint("BOTTOM" .. s); bd:SetWidth(1)
            end
        end

        local knobShadow = btn:CreateTexture(nil, "ARTWORK", nil, 1)
        knobShadow:SetSize(TOGGLE_H - 4, TOGGLE_H - 4)
        knobShadow:SetColorTexture(0, 0, 0, 0.30)

        local knob = btn:CreateTexture(nil, "ARTWORK", nil, 2)
        knob:SetSize(TOGGLE_H - 6, TOGGLE_H - 6)
        knob:SetColorTexture(ns.TC("knob"))
        knobShadow:SetPoint("CENTER", knob, "CENTER", 0, 0)

        container._knob = knob
    end

    btn:SetScript("OnClick", function(self) toggleFlip(self:GetParent()) end)

    container:EnableMouse(true)
    container:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then toggleFlip(self) end
    end)
    attachTooltip(container)

    -- Separate pool key per style: the eye variant is built at construction and
    -- cannot be turned back into a switch, so the two must never be interchanged.
    container._vcType   = (config.style == "eye") and "toggle_eye" or "toggle"
    container._vcSetup  = toggleSetup
    container._refresh  = function() toggleRefresh(container) end
    toggleSetup(container, config)
    return container
end
