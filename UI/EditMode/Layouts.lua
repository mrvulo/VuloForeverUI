-- VuloForeverUI / UI / EditMode / Layouts: named layouts panel (save, load, delete, export, import).
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent
local EM = ns._EM

-- Layouts live in ns.db.global so they are shared across profiles; capture/apply lives in Core/Mover/Layout.lua.
local layoutsPanel
local selectedLayout
local layoutValues = {}

local function layoutStore()
    local g = ns.db and ns.db.global
    if g then
        g.editLayouts = g.editLayouts or {}
        return g.editLayouts
    end
    ns._layoutFallback = ns._layoutFallback or {}
    return ns._layoutFallback
end

local function rebuildLayoutList(preferred)
    wipe(layoutValues)
    local store = layoutStore()
    local names = {}
    for name in pairs(store) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        layoutValues[#layoutValues + 1] = { value = name, text = name }
    end
    if preferred and store[preferred] then
        selectedLayout = preferred
    elseif not (selectedLayout and store[selectedLayout]) then
        selectedLayout = names[1]
    end
    if layoutsPanel and layoutsPanel.dropdown and layoutsPanel.dropdown._button then
        layoutsPanel.dropdown._button._refresh()
        if not selectedLayout then
            layoutsPanel.dropdown._button._setText(L["No layouts saved"])
        end
    end
end

local function saveLayout(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    layoutStore()[name] = ns:CaptureLayout()
    rebuildLayoutList(name)
    ns:Print(string.format(L["Layout '%s' saved."], name))
end

local function loadSelected()
    local store = layoutStore()
    if not (selectedLayout and store[selectedLayout]) then
        ns:Print(L["No layout selected."]); return
    end
    local n = ns:ApplyLayout(store[selectedLayout])
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    ns:Print(string.format(L["Applied layout '%s' (%d frames)."], selectedLayout, n))
end

local function importLayout(str)
    local name, snap = ns:DeserializeLayout(str)
    if not name then
        ns:Print(string.format(L["Import failed (%s)."], tostring(snap)))
        return
    end
    if name == "" then name = L["Imported"] end
    -- De-dupe without parentheses; the dropdown strips "(...)" from display.
    local store = layoutStore()
    local base, i, final = name, 2, name
    while store[final] do final = base .. " " .. i; i = i + 1 end
    store[final] = snap
    rebuildLayoutList(final)
    ns:Print(string.format(L["Layout '%s' imported."], final))
end

-- Newer clients expose the popup box as .EditBox, older ones as .editBox.
local function popupBox(self)
    return ns.PopupEditBox(self)
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_LAYOUT_SAVE"] = {
    text = L["Name for this layout:"],
    button1 = SAVE or L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 48,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then saveLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) saveLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_IMPORT"] = {
    text = L["Paste a layout string and confirm:"],
    button1 = L["Import"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 0,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then importLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) importLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_EXPORT"] = {
    text = L["Copy this string (Ctrl+A, Ctrl+C):"],
    button1 = OKAY or L["Close"],
    hasEditBox = true, maxLetters = 0,
    OnShow = function(self, data)
        local b = popupBox(self)
        if b then b:SetText(data or ""); b:HighlightText(); b:SetFocus() end
    end,
    EditBoxOnEnterPressed  = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_DELETE"] = {
    text = L["Delete layout '%s'?"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        if selectedLayout then layoutStore()[selectedLayout] = nil; rebuildLayoutList() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
end)

local function buildLayoutsPanel()
    if layoutsPanel then return end
    local p = CreateFrame("Frame", "VFUILayoutsPanel", UIParent)
    layoutsPanel = p
    p:SetSize(260, 252)
    p:SetPoint("LEFT", UIParent, "LEFT", 48, 40)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    UI:StyleBackdrop(p, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(p)

    local strip = p:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 14)
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -13)
    title:SetText(L["LAYOUTS"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local close = CreateFrame("Button", nil, p)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -8)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(cfs, 20)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x"); cfs:SetTextColor(ns.TC("textDim"))
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(ns.TC("textDim")) end)
    close:SetScript("OnClick", function() p:Hide() end)

    local sep = p:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -38)
    sep:SetHeight(1); sep:SetColorTexture(ns.TC("textHi", 0.07))

    local cap = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -46)
    cap:SetText(L["SAVED"]); cap:SetTextColor(ns.TC("textMuted"))

    p.dropdown = UI:CreateDropdown(p, {
        label = "", width = 228, values = layoutValues,
        tooltip = L["Pick a saved layout to load, delete or export."],
        get = function() return selectedLayout end,
        set = function(_, v) selectedLayout = v end,
    })
    p.dropdown:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -60)

    local loadBtn = UI:CreateButton(p, {
        label = L["Load"], width = 110, primary = true,
        onClick = function() loadSelected() end,
    })
    loadBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -92)

    local delBtn = UI:CreateButton(p, {
        label = L["Delete"], width = 110,
        onClick = function()
            if selectedLayout then StaticPopup_Show("VFUI_LAYOUT_DELETE", selectedLayout)
            else ns:Print(L["No layout selected."]) end
        end,
    })
    delBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -92)

    local saveBtn = UI:CreateButton(p, {
        label = L["Save current as..."], width = 228,
        onClick = function() StaticPopup_Show("VFUI_LAYOUT_SAVE") end,
    })
    saveBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -124)

    local sep2 = p:CreateTexture(nil, "ARTWORK")
    sep2:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -158)
    sep2:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -158)
    sep2:SetHeight(1); sep2:SetColorTexture(ns.TC("textHi", 0.07))

    local expBtn = UI:CreateButton(p, {
        label = L["Export"], width = 110,
        onClick = function()
            local store = layoutStore()
            if selectedLayout and store[selectedLayout] then
                StaticPopup_Show("VFUI_LAYOUT_EXPORT", nil, nil,
                    ns:SerializeLayout(selectedLayout, store[selectedLayout]))
            else ns:Print(L["No layout selected."]) end
        end,
    })
    expBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -168)

    local impBtn = UI:CreateButton(p, {
        label = L["Import"], width = 110,
        onClick = function() StaticPopup_Show("VFUI_LAYOUT_IMPORT") end,
    })
    impBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -168)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(hint, 11)
    hint:SetPoint("BOTTOMLEFT",  p, "BOTTOMLEFT",  16, 14)
    hint:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("LEFT"); hint:SetSpacing(2); hint:SetTextColor(ns.TC("textMuted"))
    hint:SetText(L["Save your window arrangement, then load or share it any time."])
end

function ns:ToggleLayouts()
    buildLayoutsPanel()
    if layoutsPanel:IsShown() then
        layoutsPanel:Hide()
    else
        rebuildLayoutList()
        layoutsPanel:Show()
    end
end

function ns:HideLayouts()
    if layoutsPanel then layoutsPanel:Hide() end
end

-- Read by the fading toolbar, which must not fade out from under an open panel.
EM.layoutsShown = function()
    return layoutsPanel ~= nil and layoutsPanel:IsShown()
end
