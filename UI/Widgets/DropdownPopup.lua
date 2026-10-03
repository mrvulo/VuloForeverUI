-- VuloForeverUI / UI / Widgets / DropdownPopup: the one shared dropdown menu: rows, scrolling, row buttons, drag reorder.
local _, ns = ...
local UI = ns.UI
local L = ns.L
local W = UI._W

local clean = W.clean

-- Dropdown config: { label?, tooltip?, values = { { text, value }, ... }, get, set, width? }
-- One popup frame is shared by all dropdowns; only one can be open at a time.
-- It lives on W.activePopup, because the closed box in Dropdown.lua reads it too.

-- Exported below as UI.CloseDropdownPopup: a panel that hands its widgets back
-- to the pool has to shut any menu still hanging off one of them first, or the
-- menu outlives the button it belongs to.
local function closeActivePopup()
    if W.activePopup and W.activePopup:IsShown() then
        W.activePopup:Hide()
        if W.activePopup._owner and W.activePopup._owner._setHovered then
            W.activePopup._owner._setHovered(false)
        end
        W.activePopup._owner = nil
    end
end
UI.CloseDropdownPopup = closeActivePopup

-- Forward-declared: the wheel handler below is written before the function
-- exists, and a plain reference there would resolve to a nil GLOBAL and scroll
-- nothing, silently.
local placePopupRows

-- A style switch without /reload (UI:RebuildMainFrame) drops the menu, so the
-- next open builds it in the new colors.
function UI.ResetDropdownPopup()
    if W.activePopup then W.activePopup:Hide() end
    W.activePopup = nil
end

local function ensurePopupFrame()
    if W.activePopup then return W.activePopup end
    local p = CreateFrame("Frame", "VCDropdownPopup", UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Above everything this UI can put on that strata. An open menu is the
    -- frontmost thing on screen by definition -- it is what the next click is
    -- for. At 200 it merely TIED with the options row panel, and a tie in the
    -- same strata is resolved by creation order: the menu drew behind the panel
    -- and its entries showed through as ghosts (user report, 02.08.2026).
    p:SetFrameLevel(600)
    p:EnableMouse(true)
    -- The wheel is caught on the popup, not on each row: a row is only 24 px
    -- tall, and hitting the gap between two of them would drop the tick.
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(self, delta)
        if (self._maxOffset or 0) <= 0 then return end
        local off = (self._offset or 0) - delta * 3
        if off < 0 then off = 0 elseif off > self._maxOffset then off = self._maxOffset end
        if off == self._offset then return end
        self._offset = off
        placePopupRows(self)
    end)
    p:Hide()

    UI:CreateShadow(p)
    local bg = p:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(p)
    bg:SetColorTexture(ns.TC("popup"))
    p._bg = bg

    local borders = {}
    for i = 1, 4 do
        local b = p:CreateTexture(nil, "BORDER")
        b:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        borders[i] = b
    end
    borders[1]:SetPoint("TOPLEFT", p, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", p, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", p, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", p, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    p._items = {}

    -- Scrollbar for long lists. The wheel has always scrolled this window, but
    -- nothing SHOWED that there was more below the edge -- reported from the
    -- Chinese client, where a texture list simply ended mid-way. The bar is the
    -- affordance and a second way to scroll; the wheel keeps working.
    local track = CreateFrame("Frame", nil, p)
    track:SetWidth(6)
    track:SetPoint("TOPRIGHT",    p, "TOPRIGHT", -1, -2)
    track:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -1, 2)
    local trackBG = track:CreateTexture(nil, "BACKGROUND")
    trackBG:SetAllPoints(track)
    trackBG:SetColorTexture(ns.TC("track"))
    track:EnableMouse(true)
    track:Hide()
    p._sbTrack = track

    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetSize(4, 36)
    thumb._tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb._tex:SetAllPoints(thumb)
    thumb._tex:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    p._sbThumb = thumb

    -- cursor -> row offset, thumb centre following the pointer
    local function offsetFromCursor()
        local scale = track:GetEffectiveScale()
        if not scale or scale == 0 then return p._offset or 0 end
        local _, cy = GetCursorPosition()
        cy = cy / scale
        local top, h = track:GetTop() or 0, track:GetHeight() or 1
        local th = thumb:GetHeight() or 20
        local frac = (top - cy - th / 2) / math.max(1, h - th)
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
        return math.floor(frac * (p._maxOffset or 0) + 0.5)
    end

    local function sbDragTick(self)
        if not IsMouseButtonDown("LeftButton") then
            self:SetScript("OnUpdate", nil)
            return
        end
        local off = offsetFromCursor()
        if off ~= self._offset then
            self._offset = off
            placePopupRows(self)
        end
    end

    -- grab the thumb or press anywhere on the track: both jump there and keep
    -- following the held mouse
    track:SetScript("OnMouseDown", function()
        local off = offsetFromCursor()
        if off ~= p._offset then p._offset = off; placePopupRows(p) end
        p:SetScript("OnUpdate", sbDragTick)
    end)

    p:SetScript("OnHide", function(self)
        if self._owner and self._owner._setHovered then
            self._owner._setHovered(false)
        end
        self._owner = nil
        -- a drag interrupted by ESC/click-through never reaches OnDragStop; the
        -- stale index would arm the next popup's first rejected drag
        self._dragFrom = nil
        self:SetScript("OnUpdate", nil)
    end)

    tinsert(UISpecialFrames, "VCDropdownPopup")  -- ESC closes

    W.activePopup = p
    return p
end

-- Off-screen ruler for the entries. A FontString that is anchored on both sides
-- reports the width it WOULD need, but only reliably while it is shown and
-- laid out -- a free-standing one with no anchors is the honest measuring tape,
-- and it costs one FontString for the whole addon.
local popupRuler
local function measureItem(text)
    if not popupRuler then
        popupRuler = UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(popupRuler, 12)
        popupRuler:Hide()
    end
    popupRuler:SetText(text or "")
    return (popupRuler:GetStringWidth() or 0)
end

-- The menu is as wide as its longest entry, not as wide as the button that
-- opened it. A closed dropdown has to fit a page column; the open list does
-- not, and clipping "Seal of Righteousness" to "Seal of R..." in the one place
-- where the whole point is to compare the choices is the wrong trade.
--
-- ITEM_PAD is the 18px check column plus the 8px right inset plus a little
-- slack: GetStringWidth and the drawn glyph run disagree by a pixel or two, and
-- being short by one drops the last letter.
local ITEM_PAD    = 34
local POPUP_MAX_W = 460

-- Room on the right for the per-row buttons, so a name never runs under them.
local ROW_BTN_SIZE = 16
local ROW_BTN_GAP  = 2

local function rowButtonRoom(opt)
    local n = opt.buttons and #opt.buttons or 0
    if n == 0 then return 0 end
    return n * (ROW_BTN_SIZE + ROW_BTN_GAP) + ROW_BTN_GAP
end

local function popupWidth(button, values)
    local w = button:GetWidth() or 0
    for _, opt in ipairs(values) do
        local need = measureItem(clean(L[opt.text])) + ITEM_PAD + rowButtonRoom(opt)
        if need > w then w = need end
    end
    local room = (UIParent:GetWidth() or 1024) - 40
    return math.min(w, math.min(POPUP_MAX_W, room))
end

-- Shows exactly the rows inside the window and hides the rest. Called on open
-- and on every wheel tick; the rows themselves never move between pools, only
-- their anchors change.
placePopupRows = function(p)
    local n, ih, off = p._visible or 0, p._itemHeight or 24, p._offset or 0
    for i, item in ipairs(p._items) do
        local slot = i - off
        if slot >= 1 and slot <= n and p._values and p._values[i] then
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT",  p, "TOPLEFT",   2, -((slot - 1) * ih + 2))
            item:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -((slot - 1) * ih + 2))
            item:Show()
        else
            item:Hide()
        end
    end

    -- the scrollbar mirrors the window: thumb length = visible share, position
    -- = scrolled share; without overflow the whole bar stays hidden
    local track, thumb = p._sbTrack, p._sbThumb
    if track and thumb then
        local maxOff = p._maxOffset or 0
        local total  = p._values and #p._values or 0
        if maxOff > 0 and total > 0 then
            track:Show()
            -- from the popup's explicit size, not track:GetHeight(): the track
            -- is anchor-sized and this runs before the first Show()
            local h  = math.max(1, (p:GetHeight() or 24) - 4)
            local th = math.max(20, math.floor(h * n / total))
            thumb:SetHeight(th)
            local frac = off / maxOff
            thumb:ClearAllPoints()
            thumb:SetPoint("TOP", track, "TOP", 0, -math.floor(frac * (h - th) + 0.5))
        else
            track:Hide()
        end
    end
end

-- Which entry the cursor is over right now. Used by the drag: OnDragStop fires
-- on the row the drag STARTED on, so the drop target has to be worked out from
-- the pointer rather than from the event.
local function popupRowUnderCursor(p)
    local scale = p:GetEffectiveScale()
    if not scale or scale == 0 then return nil end
    local _, cy = GetCursorPosition()
    cy = cy / scale
    for i, item in ipairs(p._items) do
        if item:IsShown() then
            local top, bottom = item:GetTop(), item:GetBottom()
            if top and bottom and cy <= top and cy >= bottom then return i end
        end
    end
    return nil
end

-- A row button: the small pencil/delete controls on the right of an entry.
-- Its own frame, so the click lands here and not on the row underneath it.
local function ensureRowButton(item, n)
    item._btns = item._btns or {}
    local b = item._btns[n]
    if b then return b end
    b = CreateFrame("Button", nil, item)
    b:SetSize(ROW_BTN_SIZE, ROW_BTN_SIZE)
    b:SetFrameLevel(item:GetFrameLevel() + 2)

    b._icon = b:CreateTexture(nil, "ARTWORK")
    b._icon:SetAllPoints(b)
    b._icon:SetVertexColor(ns.TC("textDim"))

    b._glyph = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(b._glyph, 13)
    b._glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._glyph:SetTextColor(ns.TC("textDim"))

    b:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(ns.TC("textHi"))
        self._glyph:SetTextColor(ns.TC("textHi"))
        if self._tooltip then
            UI:ShowTooltip(self, { title = self._tooltip, wrap = true, anchor = "ANCHOR_RIGHT" })
        end
    end)
    b:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(ns.TC("textDim"))
        self._glyph:SetTextColor(ns.TC("textDim"))
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        if self._onClick then self._onClick() end
    end)

    item._btns[n] = b
    return b
end

local function openPopup(button, config)
    local p = ensurePopupFrame()
    p._owner = button

    local values = config.values or {}
    local itemHeight = 24
    local width  = popupWidth(button, values)

    -- LONG LISTS SCROLL INSTEAD OF RUNNING OFF THE SCREEN.
    --
    -- The height used to be "one row per entry", full stop. A media list can
    -- hold two hundred sounds, and the menu then reached several thousand
    -- pixels down with no way to get at the bottom of it.
    --
    -- A window of rows plus an offset, not a ScrollFrame: the rows are already
    -- pooled and placed by hand here, so moving the window is one number, while
    -- a scroll frame would mean re-parenting all of them.
    local maxRows = math.max(6, math.floor(((UIParent:GetHeight() or 768) - 160) / itemHeight))

    -- The window used to be sized from the SCREEN height while always opening
    -- downwards from the button: a dropdown on the lower half of the page
    -- parked its tail below the screen edge, where no amount of scrolling
    -- could reach it -- the wheel clamp was correct, the rows were off-screen
    -- (reported with a 100+ entry shared-media texture list). So: size the
    -- window from the room the chosen direction really has, and open upwards
    -- when there is more room above than the list needs below.
    local uiH = UIParent:GetHeight() or 768
    local us  = UIParent:GetEffectiveScale()
    local k   = (us and us > 0) and (button:GetEffectiveScale() / us) or 1
    local roomBelow = math.floor((((button:GetBottom() or 0) * k) - 10) / itemHeight)
    local roomAbove = math.floor(((uiH - ((button:GetTop() or uiH) * k)) - 10) / itemHeight)
    local want    = math.min(#values, maxRows)
    local openUp  = roomBelow < want and roomAbove > roomBelow
    local room    = math.max(4, openUp and roomAbove or roomBelow)
    local visible = math.min(want, room)
    local height  = visible * itemHeight + 4
    p._values, p._config, p._button = values, config, button
    p._itemHeight, p._visible = itemHeight, visible
    p._maxOffset = math.max(0, #values - visible)
    p._width = width

    -- Grown to the right by default. When that would run off the screen, the
    -- menu hangs from the button's right edge instead and grows to the left --
    -- a dropdown near the window's right edge is the normal case on this page,
    -- not an exception. Vertically the same idea, decided above.
    p:ClearAllPoints()
    local left = button:GetLeft() or 0
    local rightEdge = left + width > (UIParent:GetWidth() or 1024) - 8
    if openUp then
        p:SetPoint(rightEdge and "BOTTOMRIGHT" or "BOTTOMLEFT", button,
                   rightEdge and "TOPRIGHT"    or "TOPLEFT", 0, 2)
    else
        p:SetPoint(rightEdge and "TOPRIGHT" or "TOPLEFT", button,
                   rightEdge and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
    end
    p:SetSize(width, height)

    for _, item in ipairs(p._items) do item:Hide() end

    -- Open ON the current choice when the list is longer than the window:
    -- landing at the top of two hundred entries hides the very thing the menu is
    -- there to show.
    local offset = 0
    -- A multi-select box has no single current value to open on, and no `get`
    -- to ask for one, so it simply opens at the top.
    if p._maxOffset > 0 and config.get then
        local cur = config.get(button)
        for i, opt in ipairs(values) do
            -- a caption row carries no value; with cur nil it would match one
            if opt.value ~= nil and opt.value == cur then
                offset = math.min(p._maxOffset, math.max(0, i - math.floor(visible / 2)))
                break
            end
        end
    end
    p._offset = offset

    for i, opt in ipairs(values) do
        local item = p._items[i]
        if not item then
            item = CreateFrame("Button", nil, p)
            item:SetHeight(itemHeight)

            local hover = item:CreateTexture(nil, "BACKGROUND")
            hover:SetAllPoints(item)
            hover:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.25)
            hover:Hide()
            item._hover = hover

            -- Reorder by dragging. OnDragStop fires on the row the drag STARTED
            -- on, so the target is read off the cursor instead. Handlers are
            -- wired once and take their state from the popup, because the row
            -- pool is shared by every dropdown in the addon; RegisterForDrag is
            -- per-row per-open, further down, because a registered drag eats the
            -- click when the mouse drifts a pixel -- ordinary dropdowns must
            -- never pay that.
            item:SetScript("OnDragStart", function(self)
                local pp = self:GetParent()
                if not (pp._config and pp._config.reorder and self._draggable) then return end
                pp._dragFrom = self._idx
                self._hover:Show()
            end)
            item:SetScript("OnDragStop", function(self)
                local pp = self:GetParent()
                local from = pp._dragFrom
                pp._dragFrom = nil
                self._hover:Hide()
                if not (from and pp._config and pp._config.reorder) then return end
                local to = popupRowUnderCursor(pp)
                local target = to and pp._values and pp._values[to]
                if not to or to == from or not (target and target.draggable) then return end
                -- Closed, not reopened: reorder() usually rebuilds the page that
                -- owns this dropdown, which swaps the config and values under
                -- us. Reopening from the captured table would show the OLD
                -- order, and its row buttons would act on the wrong entries.
                closeActivePopup()
                pp._config.reorder(from, to)
            end)

            local check = item:CreateTexture(nil, "OVERLAY")
            check:SetSize(6, 6)
            check:SetPoint("LEFT", item, "LEFT", 6, 0)
            check:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            check:Hide()
            item._check = check

            local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            UI.Font(fs, 12)
            fs:SetPoint("LEFT", item, "LEFT", 18, 0)
            fs:SetPoint("RIGHT", item, "RIGHT", -8, 0)
            fs:SetJustifyH("LEFT")
            -- Anchored on both sides, so the string has a fixed width and wraps
            -- by default -- while the row stays 24px. A long entry then printed
            -- three lines into its neighbours. Every other label in this file
            -- turns wrapping off; this one had been missed.
            fs:SetWordWrap(false)
            item._text = fs

            -- The widening handles the normal case; a name longer than the
            -- screen allows still gets cut, and then hovering is the way to
            -- read it. Only then -- a tooltip repeating what is already legible
            -- in front of it is noise.
            item:SetScript("OnEnter", function(self)
                self._hover:Show()
                if self._clipped then
                    UI:ShowTooltip(self, { title = self._full, wrap = true, anchor = "ANCHOR_RIGHT" })
                end
            end)
            item:SetScript("OnLeave", function(self)
                self._hover:Hide()
                UI:HideTooltip()
            end)
            p._items[i] = item
        end

        local full = clean(L[opt.text])
        item._text:SetText(full)
        item._full = full
        item._idx  = i
        item._draggable = opt.draggable and true or false
        -- Drag only where ordered: a registered drag swallows the click whenever
        -- the mouse drifts during the press, so every ordinary dropdown row must
        -- stay unregistered. No-argument call clears the registration.
        if config.reorder and opt.draggable then
            item:RegisterForDrag("LeftButton")
        else
            item:RegisterForDrag()
        end

        -- Buttons first: they decide how much room the label has left.
        local btnRoom = 0
        if item._btns then
            for _, b in ipairs(item._btns) do b:Hide(); b._onClick = nil end
        end
        if opt.buttons then
            local total = #opt.buttons
            for n, spec in ipairs(opt.buttons) do
                local b = ensureRowButton(item, n)
                b:ClearAllPoints()
                -- declaration order runs left to right, so the LAST button sits
                -- on the right edge -- { pencil, delete } reads pencil, delete
                b:SetPoint("RIGHT", item, "RIGHT", -(ROW_BTN_GAP + (total - n) * (ROW_BTN_SIZE + ROW_BTN_GAP)), 0)
                if spec.icon then
                    b._icon:SetTexture(spec.icon)
                    b._icon:Show()
                    b._glyph:SetText("")
                else
                    b._icon:SetTexture(nil)
                    b._icon:Hide()
                    b._glyph:SetText(spec.glyph or "")
                end
                b._tooltip = spec.tooltip
                b._onClick = function()
                    closeActivePopup()
                    if spec.onClick then spec.onClick(opt.value, opt) end
                end
                b:Show()
            end
            btnRoom = rowButtonRoom(opt)
        end
        item._text:SetPoint("RIGHT", item, "RIGHT", -(8 + btnRoom), 0)
        item._clipped = (measureItem(full) + ITEM_PAD + btnRoom) > width

        if opt.separator then
            -- A caption, not a choice: no mark, no hover, nothing to click.
            item._check:Hide()
            item._text:SetTextColor(ns.TC("textMuted"))
            item:EnableMouse(false)
            item._hover:Hide()
            item:SetScript("OnClick", nil)
        elseif opt.action then
            -- "add a new one" rows sit at the bottom and carry their own handler
            item._check:Hide()
            item._text:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
            item:EnableMouse(true)
            item:SetScript("OnClick", function()
                closeActivePopup()
                if opt.onClick then opt.onClick(opt.value, opt) end
            end)
        elseif config.multi then
            -- Several at once, and the menu STAYS OPEN: ticking five boxes
            -- should be five clicks, not five clicks and five reopenings. The
            -- row repaints itself and tells the closed box to re-read its
            -- summary, rather than rebuilding the menu -- a rebuild would
            -- throw away the scroll position on every tick.
            item:EnableMouse(true)
            local function paint()
                local on = config.isChecked and config.isChecked(opt.value) and true or false
                item._check:SetShown(on)
                if on then
                    item._text:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
                else
                    item._text:SetTextColor(ns.TC("label"))
                end
            end
            paint()
            item:SetScript("OnClick", function()
                if config.toggle then config.toggle(opt.value) end
                paint()
                if button._refresh then button._refresh() end
            end)
        else
            item:EnableMouse(true)
            if opt.value == config.get(button) then
                item._check:Show()
                item._text:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
            else
                item._check:Hide()
                item._text:SetTextColor(ns.TC("label"))
            end
            item:SetScript("OnClick", function()
                config.set(button, opt.value)
                if button._setText then button._setText(L[opt.text]) end
                closeActivePopup()
            end)
        end
    end

    placePopupRows(p)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:Show()
end

W.closeActivePopup = closeActivePopup
W.measureItem      = measureItem
W.openPopup        = openPopup
