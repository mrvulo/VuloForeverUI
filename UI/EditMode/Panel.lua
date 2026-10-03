-- VuloForeverUI / UI / EditMode / Panel: the side panel for the selected window, and selecting/deselecting movers.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent
local EM = ns._EM
local gridState = EM.gridState
local selIndex  = EM.selIndex

local function cleanLabel(s)
    s = tostring(s or "Frame")
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local panel

-- Shared dropdown column, so every labelled dropdown starts at the same x and
-- ends flush with the 264-wide buttons (18 + 264 = 282 = DROP_X + DROP_W).
local DROP_X, DROP_W = 118, 164

local ANCHOR_POINTS = {
    { value = "CENTER",      text = "Center" },
    { value = "TOP",         text = "Top" },
    { value = "BOTTOM",      text = "Bottom" },
    { value = "LEFT",        text = "Left" },
    { value = "RIGHT",       text = "Right" },
    { value = "TOPLEFT",     text = "Top-Left" },
    { value = "TOPRIGHT",    text = "Top-Right" },
    { value = "BOTTOMLEFT",  text = "Bottom-Left" },
    { value = "BOTTOMRIGHT", text = "Bottom-Right" },
}

-- Which side of the target window this one attaches to; the offset is kept
-- edge-to-edge so it survives either frame being resized.
local SIDE_POINTS
ns.OnLocaleReady(function()
SIDE_POINTS = {
    { value = "CENTER", text = L["Centered"] },
    { value = "LEFT",   text = L["Left of"] },
    { value = "RIGHT",  text = L["Right of"] },
    { value = "TOP",    text = L["Top of"] },
    { value = "BOTTOM", text = L["Bottom of"] },
}
end)

-- Reads the live target, not the stored db (which only updates on drop), so X/Y track a drag.
local function moverXY(m)
    local x, y = ns:GetCenterOffsets(m and m.target)
    if x and y then return x, y end
    if m and m.opts and m.opts.db then return m.opts.db.x or 0, m.opts.db.y or 0 end
    return 0, 0
end

-- The X/Y readout on a box. The mover already draws one during a drag and
-- keeps it live frame by frame (Core/Mover/Drag.lua); the setting only decides
-- whether it stays on the box for the whole session instead of retiring on the
-- drop. A second font string of our own would just disagree with that one.
EM.refreshCoordText = function(m)
    if not m then return end
    local g = gridState()
    local editing = ns._moverEditGlobal
        or (m.opts and m.opts.scope and ns._moverEditScopes and ns._moverEditScopes[m.opts.scope])
        or false
    if g.coords and editing and m:IsShown() then
        if ns.UpdateMoverCoord then ns.UpdateMoverCoord(m) end
    elseif m.coord and not m._drag then
        m.coord:Hide()
    end
end

local function refreshPanel()
    if not panel or not panel:IsShown() then return end
    local m = ns._selectedMover
    if not m or not m.opts then return end
    local name = cleanLabel(m.opts.label)
    local n = #ns._selection
    if n > 1 then
        name = name .. string.format("  %s+%d|r", (ns.C and ns.C.accent) or "|cff9b6cff", n - 1)
    end
    panel.title:SetText(name)
    if panel.optBtn then
        local key = ns.ModuleForMover and ns:ModuleForMover(m) or nil
        panel.optBtn._key = key
        panel.optBtn:SetShown(key ~= nil)
    end
    local x, y = moverXY(m)
    if not panel.xBox._editBox:HasFocus() then
        panel.xBox._editBox:SetText(tostring(math.floor(x + 0.5)))
    end
    if not panel.yBox._editBox:HasFocus() then
        panel.yBox._editBox:SetText(tostring(math.floor(y + 0.5)))
    end
end

local function buildPanel()
    if panel then return end
    panel = CreateFrame("Frame", "VFUIEditPanel", UIParent)
    panel:SetSize(300, 184)
    panel:SetPoint("RIGHT", UIParent, "RIGHT", -48, 60)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
    UI:StyleBackdrop(panel, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(panel)

    local strip = panel:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(panel.title, 14)
    panel.title:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, -13)
    panel.title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -56, -13)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)
    panel.title:SetTextColor(accent.r, accent.g, accent.b)

    local close = CreateFrame("Button", nil, panel)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -8)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(cfs, 20)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x")
    cfs:SetTextColor(ns.TC("textDim"))
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(ns.TC("textDim")) end)
    close:SetScript("OnClick", function() if ns.DeselectMover then ns:DeselectMover() end end)

    -- The gear: straight from the box to its module's settings page. The
    -- editor closes first, the way it does whenever the options open over it;
    -- the module is read off the mover's position table (ns:ModuleForMover),
    -- and the gear stays hidden for a box no module claims.
    local opt = CreateFrame("Button", nil, panel)
    opt:SetSize(18, 18)
    opt:SetPoint("RIGHT", close, "LEFT", -4, 0)
    local optIcon = opt:CreateTexture(nil, "ARTWORK")
    optIcon:SetSize(14, 14)
    optIcon:SetPoint("CENTER", opt, "CENTER", 0, 0)
    optIcon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\gear.tga")
    optIcon:SetVertexColor(ns.TC("textDim"))
    opt:SetScript("OnEnter", function(self)
        optIcon:SetVertexColor(accent.r, accent.g, accent.b)
        UI:ShowTooltip(self, { title = L["Open this element's settings"] })
    end)
    opt:SetScript("OnLeave", function()
        optIcon:SetVertexColor(ns.TC("textDim"))
        UI:HideTooltip()
    end)
    opt:SetScript("OnClick", function(self)
        local key = self._key
        if not key then return end
        ns:SetEditMode(false)
        if not UI.ShowModulePage then return end
        local main = UI.mainFrame
        if not (main and main:IsShown()) and UI.ToggleMainFrame then UI:ToggleMainFrame() end
        UI:ShowModulePage(key)
    end)
    opt:Hide()
    panel.optBtn = opt

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  panel, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -38)
    sep:SetHeight(1)
    sep:SetColorTexture(ns.TC("textHi", 0.07))

    local cap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
    cap:SetText(L["POSITION"])
    cap:SetTextColor(ns.TC("textMuted"))

    panel.xBox = UI:CreateEditBox(panel, {
        label = "X", numeric = true, commitOnFocusLost = true, width = 124, editWidth = 100,
        get = function() local x = moverXY(ns._selectedMover); return math.floor(x + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if not (m and v) then return end
            -- The box displays whole units; committing an unchanged value would
            -- round a pixel-snapped position back onto the integer grid.
            local cur = moverXY(m)
            if math.floor(cur + 0.5) == v then return end
            ns:MoverSetCenter(m, v, m.opts.db.y or 0); refreshPanel()
        end,
    })
    panel.xBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -62)

    panel.yBox = UI:CreateEditBox(panel, {
        label = "Y", numeric = true, commitOnFocusLost = true, width = 124, editWidth = 100,
        get = function() local _, y = moverXY(ns._selectedMover); return math.floor(y + 0.5) end,
        set = function(_, v)
            local m = ns._selectedMover
            if not (m and v) then return end
            local _, cur = moverXY(m)
            if math.floor(cur + 0.5) == v then return end
            ns:MoverSetCenter(m, m.opts.db.x or 0, v); refreshPanel()
        end,
    })
    panel.yBox:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -18, -62)

    panel.scaleCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.scaleCap, 10)
    panel.scaleCap:SetText(L["SCALE"])
    panel.scaleCap:SetTextColor(ns.TC("textMuted"))
    panel.scaleSlider = UI:CreateSlider(panel, {
        label = "", min = 0.5, max = 2.0, step = 0.05, width = 150,
        get = function() local m = ns._selectedMover; return (m and m.opts.db.scale) or 1 end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetScale(m, v) end end,
    })

    panel.anchorCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.anchorCap, 10)
    panel.anchorCap:SetText(L["ANCHOR"])
    panel.anchorCap:SetTextColor(ns.TC("textMuted"))

    panel.anchorToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["Pin this frame to a screen edge/corner so it stays put across resolution changes. Off keeps it centred."],
        get = function() local m = ns._selectedMover; return m and ns:IsMoverAnchorEnabled(m) end,
        set = function(_, v)
            local m = ns._selectedMover
            if m then ns:MoverSetAnchorEnabled(m, v); if ns.OnAnchorToggled then ns:OnAnchorToggled() end end
        end,
    })
    panel.anchorToggle:SetSize(44, 22)

    panel.anchorDrop = UI:CreateDropdown(panel, {
        label = "", width = DROP_W, values = ANCHOR_POINTS,
        tooltip = L["Which screen point the frame is pinned to (keeps it put across resolution changes)."],
        get = function() local m = ns._selectedMover; return (m and m.opts.db.anchor) or "CENTER" end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetAnchor(m, v) end end,
    })

    panel.linkCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.linkCap, 10)
    panel.linkCap:SetText(L["FOLLOW WINDOW"])
    panel.linkCap:SetTextColor(ns.TC("textMuted"))

    panel.linkDrop = UI:CreateDropdown(panel, {
        label = "", width = DROP_W, values = {},
        tooltip = L["Pins this window to another one - it then moves along whenever that window is moved. Dragging this window keeps the pin and just updates the distance."],
        get = function()
            local m = ns._selectedMover
            local l = m and m.key and ns:GetMoverLink(m.key)
            return (l and l.to) or ""
        end,
        set = function(_, v)
            local m = ns._selectedMover
            if not m then return end
            if not ns:SetMoverLink(m, v ~= "" and v or nil) then
                ns:FlashMoverReject(m, L["Not possible - that would create a loop."])
            end
            if panel.linkDrop._button and panel.linkDrop._button._refresh then
                panel.linkDrop._button._refresh()
            end
            if ns.RelayoutEditPanel then ns:RelayoutEditPanel() end
        end,
    })

    panel.pickBtn = UI:CreateButton(panel, {
        label   = L["Anchor to window..."],
        width   = 264,
        tooltip = L["Then click any window to anchor this one to it."],
        onClick = function()
            local m = ns._selectedMover
            if m and ns.BeginAnchorPick then ns:BeginAnchorPick(m) end
        end,
    })

    panel.sideCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.sideCap, 10)
    panel.sideCap:SetText(L["ANCHOR SIDE"])
    panel.sideCap:SetTextColor(ns.TC("textMuted"))

    panel.sideDrop = UI:CreateDropdown(panel, {
        label = "", width = DROP_W, values = SIDE_POINTS,
        tooltip = L["Docks this window to that side of the target and centres it there. 'Centered' does not move it - it only travels along. The gap is kept edge-to-edge, so it survives either window being resized."],
        get = function()
            local m = ns._selectedMover
            return (m and m.key and ns:GetMoverLinkSide(m.key)) or "CENTER"
        end,
        set = function(_, v)
            local m = ns._selectedMover
            if not (m and ns:SetMoverLinkSide(m, v)) then return end
            -- Order matters: move this window onto its edge FIRST, then carry
            -- its own followers. OnMoverRepositioned re-measures the link of the
            -- mover it is given, so doing it the other way round would put the
            -- old offsets straight back. See ns:ApplyMoverLink.
            ns:ApplyMoverLink(m)
            ns:OnMoverRepositioned(m)
            ns:RelayoutEditPanel()
        end,
    })

    panel.gapCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.gapCap, 10)
    panel.gapCap:SetText(L["GAP"])
    panel.gapCap:SetTextColor(ns.TC("textMuted"))

    panel.gapSlider = UI:CreateSlider(panel, {
        label = "", width = 150, min = 0, max = 60, step = 1,
        tooltip = L["Distance from that edge, in pixels. 0 is flush."],
        get = function()
            local m = ns._selectedMover
            return (m and m.key and ns:GetMoverLinkGap(m.key)) or 0
        end,
        set = function(_, v)
            local m = ns._selectedMover
            if not (m and m.key) then return end
            local side = ns:GetMoverLinkSide(m.key)
            if side == "CENTER" then return end   -- no edge, no gap
            if ns:SetMoverLinkSide(m, side, v) then
                ns:ApplyMoverLink(m)
                ns:OnMoverRepositioned(m)
            end
        end,
    })

    -- Own labelled row each: side by side they overflow the panel and give no
    -- clue which box is width and which is height.
    panel.widthCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.widthCap, 10)
    panel.widthCap:SetText(L["WIDTH LIKE"])
    panel.widthCap:SetTextColor(ns.TC("textMuted"))

    panel.heightCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.heightCap, 10)
    panel.heightCap:SetText(L["HEIGHT LIKE"])
    panel.heightCap:SetTextColor(ns.TC("textMuted"))

    local function sizeSetter(axis)
        return function(_, v)
            local m = ns._selectedMover
            if not m then return end
            if not ns:SetMoverSizeLink(m, v ~= "" and v or nil, axis) then
                ns:FlashMoverReject(m, L["Not possible - that would create a loop."])
                return
            end
            if v ~= "" and not ns:MoverSizeMatchSticks(m, axis) then
                ns:Print(L["This window sets its own size - the match will not stick."])
            end
            ns:RelayoutEditPanel()
        end
    end

    panel.widthDrop = UI:CreateDropdown(panel, {
        label = "", width = DROP_W, values = {},
        tooltip = L["Takes its width from another window and keeps it."],
        get = function()
            local m = ns._selectedMover
            local e = m and m.key and ns:GetMoverSizeLink(m.key)
            return (e and e.w) or ""
        end,
        set = sizeSetter("w"),
    })

    panel.heightDrop = UI:CreateDropdown(panel, {
        label = "", width = DROP_W, values = {},
        tooltip = L["Takes its height from another window and keeps it."],
        get = function()
            local m = ns._selectedMover
            local e = m and m.key and ns:GetMoverSizeLink(m.key)
            return (e and e.h) or ""
        end,
        set = sizeSetter("h"),
    })

    panel.freeCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.freeCap, 10)
    panel.freeCap:SetText(L["FREE MOVE"])
    panel.freeCap:SetTextColor(ns.TC("textMuted"))

    panel.freeToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["Leave this window unlocked so you can still drag it after closing Edit Mode. Stays unlocked through /reload."],
        get = function() local m = ns._selectedMover; return m and ns:IsMoverFreeMove(m) end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:SetMoverFreeMove(m, v) end end,
    })
    panel.freeToggle:SetSize(44, 22)

    -- Opacity by situation. Percent on the slider, 0..1 in the db. The frame
    -- stays at full strength while the editor is open (its box would fade
    -- with it), so the change shows once Edit Mode is closed.
    panel.fadeCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.fadeCap, 10)
    panel.fadeCap:SetText(L["OPACITY"])
    panel.fadeCap:SetTextColor(ns.TC("textMuted"))

    local function fadeSlider(state, label)
        return UI:CreateSlider(panel, {
            label = label, min = 0, max = 100, step = 5, width = 264,
            tooltip = L["Shows once Edit Mode is closed; while it is open every window is at full strength."],
            get = function()
                local m = ns._selectedMover
                return math.floor(ns:GetMoverFade(m, state) * 100 + 0.5)
            end,
            set = function(_, v)
                local m = ns._selectedMover
                if m then ns:SetMoverFade(m, state, v / 100) end
            end,
        })
    end
    panel.fadeOoc    = fadeSlider("ooc", L["Out of combat"])
    panel.fadeCombat = fadeSlider("combat", L["In combat"])

    panel.hoverCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.hoverCap, 10)
    panel.hoverCap:SetText(L["FULL ON MOUSEOVER"])
    panel.hoverCap:SetTextColor(ns.TC("textMuted"))
    panel.hoverToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["A faded window comes back to full strength while the mouse is over it."],
        get = function() local m = ns._selectedMover; return m and ns:GetMoverFade(m, "mouseover") end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:SetMoverFade(m, "mouseover", v and true or false) end end,
    })
    panel.hoverToggle:SetSize(44, 22)

    panel.reset = UI:CreateButton(panel, {
        label   = L["Reset this frame"],
        width   = 264,
        onClick = function()
            local m = ns._selectedMover
            if m then
                ns._inMoverReset = true          -- flags an explicit reset, not a 0,0 drop
                ns:MoverSetCenter(m, 0, 0)
                ns._inMoverReset = false
                refreshPanel()
            end
        end,
    })

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(hint, 11)
    hint:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  16, 14)
    hint:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("LEFT")
    hint:SetSpacing(2)
    hint:SetTextColor(ns.TC("textMuted"))
    hint:SetText(L["Drag a box, or hover it and use the arrow keys (Shift = 5px). Hold Shift while dragging to lock one axis. Shift+right-click hides a box that is in the way."])

    panel._acc = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        self._acc = self._acc + elapsed
        if self._acc < 0.05 then return end
        self._acc = 0
        refreshPanel()
    end)
end

local function refreshAnchorEnabled(m)
    if not (panel and panel.anchorDrop) then return end
    local on = m and ns:IsMoverAnchorEnabled(m)
    local a = on and 1 or 0.4
    panel.anchorDrop:SetAlpha(a)
    if panel.anchorDrop.EnableMouse then panel.anchorDrop:EnableMouse(on and true or false) end
    if panel.anchorDrop._button and panel.anchorDrop._button.EnableMouse then
        panel.anchorDrop._button:EnableMouse(on and true or false)
    end
end

local function layoutPanel(m)
    if not panel then return end
    local scalable   = m and m.opts and m.opts.scalable
    local anchorable = m and m.opts and m.opts.anchorable
    local y = -100

    if scalable then
        panel.scaleCap:Show(); panel.scaleSlider:Show()
        panel.scaleCap:ClearAllPoints()
        panel.scaleCap:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y)
        panel.scaleSlider:ClearAllPoints()
        panel.scaleSlider:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 20)
        y = y - 48
    else
        panel.scaleCap:Hide(); panel.scaleSlider:Hide()
    end

    if anchorable then
        panel.anchorCap:Show(); panel.anchorToggle:Show(); panel.anchorDrop:Show()
        panel.anchorCap:ClearAllPoints()
        panel.anchorCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
        panel.anchorToggle:ClearAllPoints()
        panel.anchorToggle:SetPoint("LEFT", panel.anchorCap, "RIGHT", 10, 0)
        panel.anchorDrop:ClearAllPoints()
        panel.anchorDrop:SetPoint("LEFT", panel, "TOPLEFT", DROP_X, y - 13)
        refreshAnchorEnabled(m)
        y = y - 36
    else
        panel.anchorCap:Hide(); panel.anchorToggle:Hide(); panel.anchorDrop:Hide()
    end

    if m and m.key then
        -- Every dropdown starts in the same column and ends flush with the
        -- full-width buttons; anchoring each one to its own caption instead made
        -- them start at three different x positions.
        local function dropRow(cap, drop)
            cap:Show(); drop:Show()
            cap:ClearAllPoints()
            cap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
            drop:ClearAllPoints()
            drop:SetPoint("LEFT", panel, "TOPLEFT", DROP_X, y - 13)
            y = y - 32
        end

        panel.pickBtn:Show()
        dropRow(panel.linkCap, panel.linkDrop)
        panel.pickBtn:ClearAllPoints()
        panel.pickBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y - 6)
        y = y - 36
        if ns:GetMoverLink(m.key) then
            dropRow(panel.sideCap, panel.sideDrop)
            -- Only an EDGE has a gap. On CENTER the row would be a slider that
            -- changes nothing, which reads as a broken control.
            if ns:GetMoverLinkSide(m.key) ~= "CENTER" then
                dropRow(panel.gapCap, panel.gapSlider)
            else
                panel.gapCap:Hide(); panel.gapSlider:Hide()
            end
        else
            panel.sideCap:Hide(); panel.sideDrop:Hide()
            panel.gapCap:Hide(); panel.gapSlider:Hide()
        end
        dropRow(panel.widthCap, panel.widthDrop)
        dropRow(panel.heightCap, panel.heightDrop)
        y = y - 6
    else
        panel.linkCap:Hide(); panel.linkDrop:Hide(); panel.pickBtn:Hide()
        panel.sideCap:Hide(); panel.sideDrop:Hide()
        panel.gapCap:Hide(); panel.gapSlider:Hide()
        panel.widthCap:Hide(); panel.widthDrop:Hide()
        panel.heightCap:Hide(); panel.heightDrop:Hide()
    end

    panel.freeCap:Show(); panel.freeToggle:Show()
    panel.freeCap:ClearAllPoints()
    panel.freeCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
    panel.freeToggle:ClearAllPoints()
    panel.freeToggle:SetPoint("RIGHT", panel, "TOPRIGHT", -18, y - 13)
    y = y - 34

    if m and ns:MoverCanFade(m) then
        panel.fadeCap:Show(); panel.fadeOoc:Show(); panel.fadeCombat:Show()
        panel.hoverCap:Show(); panel.hoverToggle:Show()
        panel.fadeCap:ClearAllPoints()
        panel.fadeCap:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y - 4)
        panel.fadeOoc:ClearAllPoints()
        panel.fadeOoc:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 22)
        panel.fadeCombat:ClearAllPoints()
        panel.fadeCombat:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y - 66)
        y = y - 110
        panel.hoverCap:ClearAllPoints()
        panel.hoverCap:SetPoint("LEFT", panel, "TOPLEFT", 18, y - 13)
        panel.hoverToggle:ClearAllPoints()
        panel.hoverToggle:SetPoint("RIGHT", panel, "TOPRIGHT", -18, y - 13)
        y = y - 34
    else
        panel.fadeCap:Hide(); panel.fadeOoc:Hide(); panel.fadeCombat:Hide()
        panel.hoverCap:Hide(); panel.hoverToggle:Hide()
    end

    panel.reset:ClearAllPoints()
    panel.reset:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, y - 8)
    panel:SetHeight(-(y - 8) + 92)
end

-- the candidate list depends on the selected mover (no self, no loops), so it
-- is rebuilt into the live config each time — the popup reads values at click
local function rebuildLinkValues(m)
    if not (panel and panel.linkDrop and panel.linkDrop._vcConfig) then return end
    local vals = { { value = "", text = L["- none -"] } }
    if m and m.key then
        local sorted = {}
        for _, other in ipairs(ns._movers) do
            if other ~= m and other.key
                and not ns:MoverLinkWouldCycle(m.key, other.key) then
                sorted[#sorted + 1] = {
                    value = other.key,
                    text  = (other.opts and other.opts.label) or other.key,
                }
            end
        end
        table.sort(sorted, function(a, b) return tostring(a.text) < tostring(b.text) end)
        for _, v in ipairs(sorted) do vals[#vals + 1] = v end
    end
    panel.linkDrop._vcConfig.values = vals
end

-- Same idea for the size dropdowns, but the loop test is per axis.
local function rebuildSizeValues(m)
    if not (panel and panel.widthDrop and panel.widthDrop._vcConfig) then return end
    local function build(axis)
        local vals = { { value = "", text = L["- none -"] } }
        if m and m.key then
            local sorted = {}
            for _, other in ipairs(ns._movers) do
                if other ~= m and other.key
                    and not ns:MoverSizeWouldCycle(m.key, other.key, axis) then
                    sorted[#sorted + 1] = {
                        value = other.key,
                        text  = (other.opts and other.opts.label) or other.key,
                    }
                end
            end
            table.sort(sorted, function(a, b) return tostring(a.text) < tostring(b.text) end)
            for _, v in ipairs(sorted) do vals[#vals + 1] = v end
        end
        return vals
    end
    panel.widthDrop._vcConfig.values  = build("w")
    panel.heightDrop._vcConfig.values = build("h")
end

local function refreshCaps(m)
    if m and m.opts and m.opts.scalable and panel.scaleSlider._vcSetup then
        panel.scaleSlider._vcSetup(panel.scaleSlider, panel.scaleSlider._vcConfig)
    end
    if m and m.opts and m.opts.anchorable then
        if panel.anchorDrop._button then panel.anchorDrop._button._refresh() end
        if panel.anchorToggle._refresh then panel.anchorToggle._refresh() end
        refreshAnchorEnabled(m)
    end
    rebuildLinkValues(m)
    if panel.linkDrop and panel.linkDrop._button and panel.linkDrop._button._refresh then
        panel.linkDrop._button._refresh()
    end
    if panel.sideDrop and panel.sideDrop._button and panel.sideDrop._button._refresh then
        panel.sideDrop._button._refresh()
    end
    rebuildSizeValues(m)
    for _, dd in ipairs({ panel.widthDrop, panel.heightDrop }) do
        if dd and dd._button and dd._button._refresh then dd._button._refresh() end
    end
    if panel.freeToggle._refresh then panel.freeToggle._refresh() end
    if m and ns:MoverCanFade(m) then
        for _, s in ipairs({ panel.fadeOoc, panel.fadeCombat }) do
            if s._vcSetup then s._vcSetup(s, s._vcConfig) end
        end
        if panel.hoverToggle._refresh then panel.hoverToggle._refresh() end
    end
end

function ns:OnAnchorToggled()
    refreshAnchorEnabled(ns._selectedMover)
end

-- A plain click on a member of a multi-selection keeps the group and only retargets the primary.
function ns:SelectMover(mover, additive)
    if not mover then return end
    -- Selecting outside edit mode would strand the panel with no dim to deselect against; dragging still works.
    if not ns:IsEditModeActive() then return end

    if additive then
        local i = selIndex(mover)
        if i then
            local wasPrimary = (mover == ns._selectedMover)
            table.remove(ns._selection, i)
            if wasPrimary then ns._selectedMover = ns._selection[#ns._selection] end
        else
            ns._selection[#ns._selection + 1] = mover
            ns._selectedMover = mover
        end
    elseif selIndex(mover) and #ns._selection > 1 then
        ns._selectedMover = mover
    else
        wipe(ns._selection)
        ns._selection[1]  = mover
        ns._selectedMover = mover
    end

    if not ns._selectedMover then
        if panel then panel:Hide() end
        ns:RefreshMoverStyles()
        return
    end

    buildPanel()
    layoutPanel(ns._selectedMover)
    refreshCaps(ns._selectedMover)
    panel:Show()
    ns:RefreshMoverStyles()
    refreshPanel()
end

function ns:DeselectMover()
    if ns.CancelAnchorPick then ns:CancelAnchorPick() end
    wipe(ns._selection)
    ns._selectedMover = nil
    ns._groupDrag = nil
    if panel then panel:Hide() end
    ns:RefreshMoverStyles()
end

-- Re-run the panel layout for the current selection (rows appear/vanish as links change).
function ns:RelayoutEditPanel()
    local m = ns._selectedMover
    if not (panel and panel:IsShown() and m) then return end
    layoutPanel(m)
    refreshCaps(m)
    refreshPanel()
end

function ns:OnMoverMoved(mover)
    if mover == ns._selectedMover then refreshPanel() end
    if EM.refreshCoordText then EM.refreshCoordText(mover) end
end
