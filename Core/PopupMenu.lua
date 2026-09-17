-- Shared popup-menu helper; EasyMenu is often nil on Anniversary.
--
-- Two levels: a root menu and one flyout. An entry with `submenu` (a table of
-- entries, or a function returning one) grows an arrow and opens the flyout on
-- hover, anchored to its right edge. Long flyouts (sound lists) window
-- themselves to MAX_VISIBLE rows and scroll on the mouse wheel. Clicking
-- anywhere outside closes the whole thing -- GLOBAL_MOUSE_DOWN, which
-- Blizzard's own 2.5.x talent UI listens to as well.
local _, ns = ...

local MAX_VISIBLE = 18

-- _levels[1] = root, _levels[2] = flyout; each { frame, buttons }
local _levels = {}

local function menuColors()
    local ac = (ns.COLORS and ns.COLORS.accent) or { r = 0.608, g = 0.424, b = 1 }
    local bd = (ns.COLORS and ns.COLORS.borderDark) or { r = 0.02, g = 0.02, b = 0.03 }
    return ac, bd
end

local renderLevel -- forward: the wheel handler re-renders its own level

local function hideFrom(levelIndex)
    for i = #_levels, levelIndex, -1 do
        local lv = _levels[i]
        if lv then lv.frame:Hide() end
    end
end

local function createLevel(i)
    local lv = _levels[i]
    if lv then return lv end
    -- the root gets the global name for ESC; the flyout is PARENTED to the
    -- root, so hiding or escaping the root takes the flyout with it
    local name   = (i == 1) and "VFUI_SharedPopupMenu" or nil
    local parent = (i == 1) and UIParent or createLevel(1).frame
    local f = CreateFrame("Frame", name, parent,
        BackdropTemplateMixin and "BackdropTemplate")
    f:SetFrameStrata("DIALOG")
    -- the flyout must beat the root wherever they overlap
    f:SetFrameLevel(20 * i)
    f:SetWidth(200)
    f:SetHeight(30)
    f:Hide()
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        local _, bd = menuColors()
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.98)
        f:SetBackdropBorderColor(bd.r, bd.g, bd.b, 1)
    end
    if ns.UI and ns.UI.CreateShadow then ns.UI:CreateShadow(f) end

    if i == 1 then
        tinsert(UISpecialFrames, name)
        -- Click-elsewhere closes. Registered only while shown; the down event
        -- fires BEFORE any OnClick, so clicks on the open anchor are left to
        -- the anchor's own toggle (hiding here would make its click reopen).
        f:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        f:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            hideFrom(2)
        end)
        f:SetScript("OnEvent", function(self)
            if self:IsMouseOver() then return end
            local fly = _levels[2] and _levels[2].frame
            if fly and fly:IsShown() and fly:IsMouseOver() then return end
            local a = self._openAnchor
            if type(a) == "table" and a.IsMouseOver and a:IsMouseOver() then return end
            self:Hide()
        end)
    end

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local me = _levels[i]
        if not (me.entries and #me.entries > MAX_VISIBLE) then return end
        local maxOff = #me.entries - MAX_VISIBLE
        local off = math.min(math.max((me.offset or 0) - delta, 0), maxOff)
        if off ~= me.offset then
            me.offset = off
            renderLevel(i, me.entries, nil)
            -- the rows just re-mapped to different entries; a flyout still
            -- anchored to one of them would be lying about its parent
            if i == 1 then hideFrom(2) end
        end
    end)

    lv = { frame = f, buttons = {} }
    _levels[i] = lv
    return lv
end

local function getMenuButton(lv, idx)
    local btn = lv.buttons[idx]
    if btn then return btn end
    btn = CreateFrame("Button", nil, lv.frame)
    btn:SetHeight(20)

    local ac = menuColors()

    btn.check = btn:CreateTexture(nil, "OVERLAY")
    btn.check:SetSize(6, 6)
    btn.check:SetPoint("LEFT", btn, "LEFT", 8, 0)
    btn.check:SetColorTexture(ac.r, ac.g, ac.b, 1)
    btn.check:Hide()

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(btn.text, 11) end
    btn.text:SetPoint("LEFT", btn, "LEFT", 22, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.text:SetJustifyH("LEFT")

    -- flyout marker; plain ">" because the bundled font has no triangle glyph
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if ns.UI and ns.UI.Font then ns.UI.Font(btn.arrow, 11) end
    btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    btn.arrow:SetText(">")
    btn.arrow:Hide()

    btn.hl = btn:CreateTexture(nil, "BACKGROUND")
    btn.hl:SetAllPoints(btn)
    btn.hl:SetColorTexture(ac.r, ac.g, ac.b, 0.22)
    btn.hl:Hide()

    btn:SetScript("OnEnter", function(self)
        if self._clickable then self.hl:Show() end
        if self._level == 1 then
            if self._submenu then
                ns._OpenPopupSubmenu(self)
            else
                hideFrom(2)
            end
        end
    end)
    btn:SetScript("OnLeave", function(self) self.hl:Hide() end)
    lv.buttons[idx] = btn
    return btn
end

-- level i of the shared menu from `entries`; anchorFn places the frame (nil on
-- a wheel re-render keeps the current position)
renderLevel = function(i, entries, anchorFn)
    local lv = createLevel(i)
    local menu = lv.frame
    lv.entries = entries
    if anchorFn then lv.offset = 0 end

    for _, b in ipairs(lv.buttons) do b:Hide() end

    local first = 1 + (lv.offset or 0)
    local last  = math.min(#entries, first + MAX_VISIBLE - 1)

    local y, maxTextWidth, shown = -6, 0, 0

    for ei = first, last do
        local entry = entries[ei]
        shown = shown + 1
        local btn = getMenuButton(lv, shown)
        btn:Show()
        btn.check:Hide()
        btn.arrow:Hide()
        btn._clickable = false
        btn._level = i
        btn._submenu = nil

        if entry.separator then
            btn:SetHeight(6)
            btn.text:SetText("")
            btn:EnableMouse(false)
            btn:SetScript("OnClick", nil)
        elseif entry.title then
            btn:SetHeight(20)
            btn.text:SetText(entry.text or "")
            local ac = menuColors()
            btn.text:SetTextColor(ac.r, ac.g, ac.b)
            btn:EnableMouse(false)
            btn:SetScript("OnClick", nil)
        else
            btn:SetHeight(20)
            btn.text:SetText(entry.text or "")
            if entry.disabled then
                btn.text:SetTextColor(0.5, 0.5, 0.5)
                -- mouse stays ON: hovering a dead flyout parent must still
                -- close an open flyout, and a tooltipless dead row is inert
                btn:EnableMouse(true)
                btn._clickable = false
                btn:SetScript("OnClick", nil)
            else
                btn.text:SetTextColor(1, 1, 1)
                btn:EnableMouse(true)
                btn._clickable = true
                btn:RegisterForClicks("LeftButtonUp")
                local fn        = entry.func
                local keepOpen  = entry.keepOpen
                local checkedFn = entry.checked
                local hasSub    = entry.submenu ~= nil
                btn._submenu = entry.submenu
                btn:SetScript("OnClick", function(self)
                    if hasSub then
                        -- a flyout parent only opens its flyout; hover
                        -- already did, so a click is a no-op there
                        if i == 1 then ns._OpenPopupSubmenu(self) end
                        return
                    end
                    if not keepOpen then hideFrom(1) end
                    if fn then fn() end
                    -- keepOpen items must re-evaluate their checkmark in place
                    if keepOpen and checkedFn then
                        local ok, isChecked = pcall(checkedFn)
                        self.check:SetShown(ok and isChecked)
                    end
                    -- a keepOpen radio set (one dot among siblings) needs the
                    -- WHOLE level repainted, not just the clicked row
                    if keepOpen and entry.radio then
                        renderLevel(i, _levels[i].entries, nil)
                    end
                end)
                if hasSub then btn.arrow:Show() end
            end
            if entry.checked then
                local ok, isChecked = pcall(entry.checked)
                if ok and isChecked then btn.check:Show() end
            end
        end

        local stringWidth = btn.text:GetStringWidth() or 0
        if stringWidth > maxTextWidth then maxTextWidth = stringWidth end

        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, y)
        btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
        y = y - btn:GetHeight() - 1
    end

    -- more rows than the window shows: say so, instead of a list that just ends
    if #entries > MAX_VISIBLE then
        shown = shown + 1
        local btn = getMenuButton(lv, shown)
        btn:Show()
        btn.check:Hide()
        btn.arrow:Hide()
        btn._clickable = false
        btn._level = i
        btn._submenu = nil
        btn:SetHeight(16)
        btn:EnableMouse(false)
        btn:SetScript("OnClick", nil)
        btn.text:SetText(string.format("%d/%d", last, #entries))
        btn.text:SetTextColor(0.45, 0.45, 0.45)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  menu, "TOPLEFT",  4, y)
        btn:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, y)
        y = y - btn:GetHeight() - 1
    end

    -- keep the width over a wheel re-render: only the rows change, and a menu
    -- that breathes sideways under the cursor drops the hover
    local desiredWidth = math.min(360, math.max(180, maxTextWidth + 52))
    if anchorFn or not lv.keptWidth then
        lv.keptWidth = desiredWidth
    end
    menu:SetWidth(math.max(desiredWidth, lv.keptWidth))
    menu:SetHeight(-y + 6)

    if anchorFn then anchorFn(menu) end
    menu:Show()
end

-- flyout for a hovered root button (module-internal, wired in OnEnter above)
function ns._OpenPopupSubmenu(btn)
    local sub = btn._submenu
    if type(sub) == "function" then sub = sub() end
    if type(sub) ~= "table" or #sub == 0 then hideFrom(2); return end
    local fly = createLevel(2).frame
    -- re-hovering the same parent must not reset an open, scrolled flyout
    if fly:IsShown() and fly._openFor == btn then return end
    fly._openFor = btn
    renderLevel(2, sub, function(menu)
        menu:ClearAllPoints()
        -- slight overlap so the cursor can cross without a gap dropping it
        menu:SetPoint("TOPLEFT", btn, "TOPRIGHT", -2, 6)
    end)
end

-- owner (optional): the FRAME whose click opened a cursor-anchored menu. The
-- outside-click close exempts whatever _openAnchor points at, and a string
-- "cursor" cannot be mouse-over-tested -- without the owner, the mouse-DOWN
-- closes the menu and the same click's OnClick reopens it, so the opening
-- button could never toggle its menu shut.
function ns:ShowPopupMenu(entries, anchor, owner)
    if type(entries) ~= "table" then return end
    local menu = createLevel(1).frame

    hideFrom(2)

    -- Toggle: clicking the SAME anchor again closes; a different anchor moves it
    local ident = owner or anchor
    if menu:IsShown() and menu._openAnchor == ident then
        menu:Hide()
        menu._openAnchor = nil
        return
    end
    menu._openAnchor = ident

    renderLevel(1, entries, function(m)
        m:ClearAllPoints()
        if anchor and type(anchor) == "table" and anchor.GetLeft then
            m:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", -2, 0)
        elseif anchor == "cursor" then
            local cx, cy = GetCursorPosition()
            local scale  = UIParent:GetEffectiveScale() or 1
            m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
        else
            m:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end)
end
