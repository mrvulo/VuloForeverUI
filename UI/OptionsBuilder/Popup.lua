-- VuloForeverUI / UI / OptionsBuilder / Popup: the row popup panel, inline row icons and the gear sub-column.
local _, ns = ...
local UI = ns.UI
local OB = UI._OB
local CONTENT_PADDING = OB.CONTENT_PADDING
local acquire = OB.acquire
local clearChildren = OB.clearChildren
local ICON_GEAR = OB.ICON_GEAR
local ICON_EXPAND = OB.ICON_EXPAND
local ICON_EYE = OB.ICON_EYE
local ICON_EYE_OFF = OB.ICON_EYE_OFF
local ROW_ICON_SLOT = OB.ROW_ICON_SLOT
local makeRowIcon = OB.makeRowIcon
local setRowIcon = OB.setRowIcon
local runLabelColumn = OB.runLabelColumn
local collectCompact = OB.collectCompact
local makeSubColumn = OB.makeSubColumn

-- ---------------------------------------------------------------------------
-- Row popup: one row's fine tuning, in a floating panel.
--
-- WHY NOT THE GEAR. The gear unfolds a sub-column INSIDE the row's cell, which
-- needs a cell wide enough to hold a second, indented run. Half a cell in a
-- strict two-column grid is not -- and the nameplate slot rows are exactly that
-- shape (user request, 02.08.2026). This is not the second collapse mechanism
-- the section note further down forbids: it makes the SAME promise the gear
-- makes -- "what is in here belongs to this row" -- drawn where the width is.
--
-- The rows inside are built by placeItemList, so they are the same widgets with
-- the same look and the same settings-search reach as any page row. Pooling
-- stays safe only because clearChildren releases per PARENT: a page rebuild
-- reclaims the page's widgets and cannot reach into the panel, and the panel's
-- own widgets are out of the pool while it is open, so no page can be handed
-- one that is still on screen.

local function closeRowPopup()
    if OB.rowPopup and OB.rowPopup:IsShown() then OB.rowPopup:Hide() end
end
UI.CloseRowPopup = closeRowPopup

local function ensureRowPopup()
    if OB.rowPopup then return OB.rowPopup end
    -- Named on purpose: UISpecialFrames closes it on Escape, which is what the
    -- key does to every other panel in this UI.
    local f = CreateFrame("Frame", "VuloOptionsRowPopup", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)          -- eats its own clicks, so the catcher below cannot see them
    f:Hide()
    UI:StyleBackdrop(f)
    if UI.CreateShadow then UI:CreateShadow(f) end

    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT",  f, "TOPLEFT",   1, -1)
    accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    f._accent = accent

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(title, 12)
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetTextColor(ns.TC("label"))
    f._title = title

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    f._body = body

    -- A click anywhere else closes it. A full-screen catcher BEHIND the panel,
    -- not a mouse test on OnUpdate: the test would have to run every frame for
    -- a panel that is open for a second.
    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(100)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", closeRowPopup)
    f._catcher = catcher

    f:SetScript("OnShow", function(self) self._catcher:Show() end)
    f:SetScript("OnHide", function(self)
        self._catcher:Hide()
        self._owner = nil
        -- A menu opened from one of these rows would otherwise outlive the
        -- button it belongs to -- that button is about to go back to the pool.
        if UI.CloseDropdownPopup then UI.CloseDropdownPopup() end
        -- back to the pools, or the next open would stack a second set of rows
        -- on top of these
        clearChildren(self._body)
    end)
    if _G.UISpecialFrames then
        tinsert(_G.UISpecialFrames, "VuloOptionsRowPopup")
    end
    OB.rowPopup = f
    return f
end

-- spec = { title = <string>, width = <number>, items = { <option items> } }
local function openRowPopup(anchor, spec)
    local f = ensureRowPopup()
    -- the same icon twice is "close", the way every expander in this UI behaves
    if f:IsShown() and f._owner == anchor then closeRowPopup(); return end
    f:Hide()                     -- releases the previous panel's rows via OnHide
    f._owner = anchor
    f._spec  = spec              -- kept for RefreshRowPopup
    -- A child of UIParent, not of the window it belongs to, so it does not
    -- inherit the window's scale. Taken here rather than at creation: the panel
    -- outlives any number of scale changes.
    if UI.MainFrameScale then f:SetScale(UI:MainFrameScale()) end
    f._title:SetText(spec.title or "")
    local a = ns.COLORS.accent   -- read at paint time: the theme colour is live-mutated
    f._accent:SetColorTexture(a.r, a.g, a.b, 0.9)

    -- Width BEFORE the rows: placeItemList measures its columns against the
    -- parent's width, and a body still at its default would lay the rows out
    -- for a width the panel never has. Below MIN_CELL on purpose -- one column
    -- is what a fine-tuning list should be.
    local w = spec.width or 240
    f:SetWidth(w)
    f._body:SetSize(w, 10)

    -- ONE column, with a label column measured for THESE rows at THIS width --
    -- the same recipe placeSubColumn uses, and for the same reason.
    --
    -- Clearing the grid instead of setting it was the first attempt and it drew
    -- the panel in two columns anyway (user report, 02.08.2026): with no grid,
    -- placeColumns falls through to fitColumns, which pairs any run that fits --
    -- and at half of 320px every label came out as "Ver-t...". The grid is not
    -- only what forces pairing, it is also what can forbid it.
    local savedGrid, savedSolo = UI._grid, UI._soloCol
    local col = runLabelColumn(collectCompact(spec.items or {}, {}),
        w - 2 * CONTENT_PADDING - 20 - ROW_ICON_SLOT, true)
    UI._grid    = { cols = 1, labelCol = col, iconStrip = ROW_ICON_SLOT }
    UI._soloCol = col
    local ok, bottom = pcall(OB.placeItemList, f._body, spec.items or {}, 0)
    UI._grid, UI._soloCol = savedGrid, savedSolo
    if not ok then
        ns:Debug("row popup: %s", tostring(bottom))
        f:Hide()
        return
    end
    local bodyH = math.max(10, -bottom)
    f._body:SetHeight(bodyH)
    f:SetHeight(30 + bodyH + 10)

    f:ClearAllPoints()
    -- UPWARDS by default (user request, 02.08.2026). Opening downwards put the
    -- panel over the rows below it and, on a row near the bottom of the page,
    -- half of it off the screen -- where SetClampedToScreen shoved it back over
    -- its own anchor. Above the row it covers what you have already read.
    --
    -- Flipped back down only when the panel would not fit above: measured
    -- against the anchor's own top, so a row near the top of the screen still
    -- gets a panel you can read rather than one pinned to the edge.
    local top = anchor:GetTop()
    local screenH = UIParent:GetHeight() or 768
    if top and (top + f:GetHeight() + 10) > screenH then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -10, -6)
    else
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -10, 6)
    end
    f:Show()
end
UI.OpenRowPopup = openRowPopup

-- Redraw the open panel in place. A setter inside it that decides whether OTHER
-- rows in the same panel can do anything needs this: refreshing the PAGE leaves
-- the panel exactly as it was, and its rows would go on looking available until
-- it was closed and opened again. The owner is cleared first, or openRowPopup
-- would read the call as clicking the same gear twice and close the panel.
function UI:RefreshRowPopup()
    local f = OB.rowPopup
    if not (f and f:IsShown() and f._owner and f._spec) then return end
    local anchor, spec = f._owner, f._spec
    f._owner = nil
    openRowPopup(anchor, spec)
end

-- Where a row's inline icons chain leftward from. A dropdown hands back its
-- box, which is what the eye follows; anything else falls back to its own right
-- edge. Inline icons sit LEFT of the control on purpose -- the right-hand strip
-- is spoken for by the info dot and the gear, and widening it would move every
-- control on every page.
-- Where a row's inline icons chain leftward from: the point at which the
-- CONTROL begins. A dropdown hands back its box, a slider its track, a
-- checkbox or toggle its switch.
--
-- The fallback to the widget itself is a LAST resort and it looks wrong when it
-- fires -- the widget starts at the label, so the icons land in front of the
-- text. That is exactly what the toggle rows did before `_switch` was listed
-- here (user report, 02.08.2026): "Zaubersymbol" drew its arrows left of its
-- own name. Any widget type given inline icons needs a handle in this list.
local function inlineAnchor(widget)
    return widget._button or widget._slider or widget._switch or widget
end

-- Small square colour button for an inline swatch. Pooled like the row icons,
-- so a page rebuild reclaims it through clearChildren.
local function makeInlineColor(parent)
    local b = acquire("inlinecolor", parent)
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b._vcType  = "inlinecolor"
    b._vcSetup = function() end
    b:SetSize(18, 18)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(b)
    border:SetColorTexture(0, 0, 0, 0.8)
    b._border = border
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b._fill = fill
    b:SetScript("OnEnter", function(self)
        local a = ns.COLORS.accent
        self._border:SetColorTexture(a.r, a.g, a.b, 1)
        if self._tip then UI:ShowTooltip(self, { title = self._tip, wrap = true }) end
    end)
    b:SetScript("OnLeave", function(self)
        self._border:SetColorTexture(0, 0, 0, 0.8)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        local cfg = self._cfg
        if not (cfg and cfg.get) then return end
        local c = cfg.get() or {}
        ns:ShowColorPicker({ r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1,
            hasAlpha = cfg.hasAlpha,
            onChange = function(r, g, bl, a)
                if cfg.set then cfg.set(r, g, bl, a) end
                local nc = cfg.get() or {}
                self._fill:SetColorTexture(nc.r or 1, nc.g or 1, nc.b or 1, 1)
            end })
    end)
    return b
end

-- Draws item.inline (right to left) starting at the control's left edge, and
-- returns how much width they took so the caller can shrink the control by it.
local INLINE_SLOT = 24
local function placeInlineIcons(parent, item, widget, level)
    if not widget then return 0 end
    local defs = item.inline
    local n = (defs and #defs) or 0

    -- A toggle's label spans from the row's left edge to its switch, so icons
    -- placed between the two would draw over the end of the text. Move the
    -- label's right edge out of their way -- and move it BACK when a pooled
    -- toggle lands on a row with no icons, or the gap travels to a page that
    -- never asked for it.
    if widget._switch and widget._label then
        widget._label:ClearAllPoints()
        widget._label:SetPoint("LEFT", widget, "LEFT", 0, 0)
        widget._label:SetPoint("RIGHT", widget._switch, "LEFT", -8 - n * INLINE_SLOT, 0)
    end

    if n == 0 then return 0 end
    local anchor = inlineAnchor(widget)
    local used = 0
    for _, def in ipairs(defs) do
        local b
        if def.kind == "color" then
            b = makeInlineColor(parent)
            b._cfg = def
            b._tip = def.tooltip
            local c = (def.get and def.get()) or {}
            b._fill:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
            -- A swatch that cannot do anything says so rather than lying
            local off = def.disabled and def.disabled()
            b:SetAlpha(off and 0.15 or 1)
            b:EnableMouse(not off)
            b:SetFrameLevel(level)
            b:Show()
        else
            local tex = ICON_EXPAND
            local onClick
            if def.kind == "eye" then
                local on = not (def.get and def.get() == false)
                tex = on and ICON_EYE or ICON_EYE_OFF
                onClick = function()
                    if def.set then def.set(not on) end
                    UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
                end
            else
                -- Two icons, one mechanism, and the difference is what the rows
                -- behind it ARE. The gear means "more of this setting" -- the
                -- same promise the right-hand gear makes on every other page.
                -- The two arrows mean "this thing has a place and a size", which
                -- is what a position slot opens.
                if def.kind == "gear" then tex = ICON_GEAR end
                onClick = function() openRowPopup(widget, def.popup or def) end
            end
            b = setRowIcon(makeRowIcon(parent), tex, def.tooltip, onClick, level)
            -- same rule as the swatch: an icon that cannot do anything says so
            local off = def.disabled and def.disabled()
            b:SetAlpha(off and 0.15 or 1)
            b:EnableMouse(not off)
        end
        b:ClearAllPoints()
        b:SetPoint("RIGHT", anchor, "LEFT", -6 - used, 0)
        used = used + INLINE_SLOT
    end
    return used
end

local function placeSubColumn(parent, item, cellX, subY, cellW)
    local sub = makeSubColumn(parent)
    sub:ClearAllPoints()
    sub:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX - CONTENT_PADDING, subY)
    sub:SetWidth(cellW + 2 * CONTENT_PADDING)
    sub:SetFrameLevel(parent:GetFrameLevel())
    sub:Show()

    -- One column, with a label column measured for THESE rows at THIS width.
    -- The page grid must not leak in here: its cells are half the page, its
    -- label column is measured against that, and fitColumns never answers
    -- below two -- each of the three would cram two ~220px cells into the
    -- half. iconStrip reserves ONE slot, not the full-width strip of two:
    -- the cell above reserved exactly the gear slot (gearLead), and the
    -- sub-rows' controls should end on that same edge.
    local savedGrid, savedSolo = UI._grid, UI._soloCol
    local col = runLabelColumn(collectCompact(item.subOptions, {}),
        cellW - 20 - ROW_ICON_SLOT, true)
    UI._grid    = { cols = 1, labelCol = col, iconStrip = ROW_ICON_SLOT }
    UI._soloCol = col
    local yEnd = OB.placeItemList(sub, item.subOptions, 0)
    UI._grid, UI._soloCol = savedGrid, savedSolo

    local h = -yEnd
    sub:SetHeight(math.max(1, h))
    return h
end

-- for the OptionsBuilder files loaded after this one
OB.closeRowPopup = closeRowPopup
OB.INLINE_SLOT = INLINE_SLOT
OB.placeInlineIcons = placeInlineIcons
OB.placeSubColumn = placeSubColumn
