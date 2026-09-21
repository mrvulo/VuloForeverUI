-- VuloForeverUI / Modules / CooldownManager / Preview
--
-- The live preview that sits at the top of the settings page.
--
-- It is not a drawing of a bar, and not a second implementation of one: it is
-- a frame that goes through CM.StyleFrame and CM.PaintFrame, the very same two
-- passes the real bars go through. Whatever a setting does on screen it does
-- here, including the parts we do not control -- the engine's swipe, the
-- engine's countdown, a glow's animation -- because they are the same widgets.
--
-- Two things it does differently, both on purpose:
--   * it borrows spells when the bar is empty, so a bar someone is still
--     filling still shows its size, its spacing and its border
--   * it scales itself down when the bar is wider than the page, so a 24 icon
--     row is visible rather than cut off, with the scale written out
--
-- It works while the module is switched OFF, which is the point: the module
-- ships off, and nobody should have to turn something on to see what it is.
--
-- It is also where a bar is EDITED. An icon is dragged to the place it should
-- have, and the plus button beside it opens the picker -- because the order on
-- screen is what somebody is actually deciding, and deciding it in a list of
-- names one panel further down is deciding it blind.
local _, ns = ...
local L  = ns.L
local CM = ns.CM

local PANEL_H    = 118
local PREVIEW_ROWS = 5      -- how many stand-ins an empty bar borrows

local panel       -- the card, created once and re-parented on every page build
local previewBar  -- the frame the two passes run on
local ghost       -- the icon that follows the cursor while one is dragged
local dragFrom    -- which row is being dragged, nil when none is
local marker      -- the line that says where it would land

-- Forward: the slow tick drives the drop marker, and the tick is defined
-- above the drag code that owns it.
local dragTick

-- The bar the panel falls back to when nothing was chosen yet. The module can
-- be OFF while this page is open, so the bars are ensured here rather than
-- assumed to exist.
local function firstBar()
    CM.EnsureBars()
    local db = CM.db()
    local key = db and db.barOrder and db.barOrder[1]
    return key and CM.Bar(key) or nil
end

-- The KEY of the bar the panel is showing. The panel itself only ever needed
-- the bar; everything that CHANGES one needs its key.
local function currentKey()
    CM.EnsureBars()
    local db = CM.db()
    if CM.previewKey and CM.Bar(CM.previewKey) then return CM.previewKey end
    return db and db.barOrder and db.barOrder[1] or nil
end

-- The preview shows LIVE cooldowns, and it has to do that while the module is
-- switched off, when no event of ours runs at all. So it keeps its own slow
-- tick: four times a second, the paint pass only, never the layout. A hidden
-- frame gets no OnUpdate, so a closed settings window costs nothing.
local function tick(self, elapsed)
    self.wait = (self.wait or 0) + elapsed
    if self.wait < 0.25 then return end
    self.wait = 0
    local bar = CM.Bar(CM.previewKey or "") or firstBar()
    if not (bar and previewBar) then return end
    local own = CM.Own(bar)
    CM.PaintFrame(previewBar, bar, CM.PreviewFill(own, PREVIEW_ROWS), #own)
end


-- ---------------------------------------------------------------- drag --
--
-- Reordering by dragging the icon itself. The preview's icons are OUR frames,
-- not secure buttons, so a drag here costs nothing and takes nothing away --
-- the tooltip script the bar put on them is hooked, never replaced.
--
-- Only the rows the bar OWNS can move. The stand-ins a short bar borrows are
-- drawn at half strength and belong to no list; dropping one would ask the
-- module to move a row that does not exist.

local function ensureGhost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(32, 32)
    ghost:Hide()
    local tex = ghost:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(ghost)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ghost.texture = tex
    ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale() or 1
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        -- The drop marker rides along here rather than on the panel's own
        -- tick: that one runs four times a second, and a marker that lags a
        -- quarter of a second behind the cursor points at the wrong gap.
        dragTick()
    end)
    return ghost
end

local function ensureMarker()
    if marker then return marker end
    marker = previewBar:CreateTexture(nil, "OVERLAY")
    marker:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    marker:Hide()
    return marker
end

-- Which icon the cursor is over, and on which side of it. The side is what
-- turns "over the third icon" into "before it" or "after it", which is the
-- difference between dropping at 3 and dropping at 4.
local function dropTarget(owned)
    for i = 1, math.min(owned, #previewBar.icons) do
        local b = previewBar.icons[i].button
        if b:IsShown() and b:IsMouseOver() then
            -- The cursor comes back in raw screen pixels and the button's own
            -- left edge in the BUTTON's coordinates. The preview is scaled
            -- down whenever a bar is wider than the page, so dividing by
            -- UIParent's scale compared two different rulers and every drop
            -- on a scaled preview landed on the wrong side of the icon.
            local scale = b:GetEffectiveScale() or 1
            local left, width = b:GetLeft(), b:GetWidth() or 1
            local x = GetCursorPosition() / scale
            local after = left and (x > left + width / 2)
            return i, after and true or false
        end
    end
    return nil
end

local function showMarker(index, after)
    local m = ensureMarker()
    local b = previewBar.icons[index] and previewBar.icons[index].button
    if not b then m:Hide(); return end
    m:ClearAllPoints()
    m:SetWidth(2)
    m:SetPoint("TOP", b, after and "TOPRIGHT" or "TOPLEFT", 0, 2)
    m:SetPoint("BOTTOM", b, after and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -2)
    m:Show()
end

local function stopDrag()
    dragFrom = nil
    if ghost then ghost:Hide() end
    if marker then marker:Hide() end
end

-- The index the row ends up at. Moving something DOWN the list shifts the rows
-- it passes, so the naive "the index I dropped on" is one too far -- the old
-- draft dropped icon 1 onto icon 3 and it landed at 2.
local function landingIndex(from, over, after)
    local to = after and (over + 1) or over
    if from < to then to = to - 1 end
    return math.max(1, to)
end

local function wireDrag(index, icon)
    local b = icon.button
    if b.vfDragWired then b.vfIndex = index; return end
    b.vfDragWired = true
    b.vfIndex = index
    b:RegisterForDrag("LeftButton")

    b:SetScript("OnDragStart", function(self)
        local owned = previewBar.ownedCount or 0
        if (self.vfIndex or 0) > owned then return end
        dragFrom = self.vfIndex
        local g = ensureGhost()
        g.texture:SetTexture(icon.texture:GetTexture())
        g:Show()
    end)

    b:SetScript("OnDragStop", function()
        if not dragFrom then stopDrag(); return end
        local owned = previewBar.ownedCount or 0
        local over, after = dropTarget(owned)
        local from = dragFrom
        stopDrag()
        if not over then return end
        local to = landingIndex(from, over, after)
        if to == from then return end
        local key = currentKey()
        if not key then return end
        CM.MoveSpell(key, from, to)
        CM.RefreshPreview()
        if CM.RebuildOptions then CM.RebuildOptions("spells") end
    end)

    -- Hooked, not set: the bar gave these buttons their tooltip scripts, and a
    -- drag hint is an addition to that tooltip, not a replacement for it.
    b:HookScript("OnEnter", function(self)
        if not dragFrom then return end
        local owned = previewBar.ownedCount or 0
        if (self.vfIndex or 0) > owned then return end
        local over, after = dropTarget(owned)
        if over then showMarker(over, after) end
    end)
    b:HookScript("OnLeave", function()
        if marker and not dragFrom then marker:Hide() end
    end)
end

-- The marker has to follow the cursor WHILE a drag is on, not only when it
-- crosses into a new icon: an icon the cursor never leaves still has two sides.
dragTick = function()
    if not dragFrom then return end
    local owned = previewBar.ownedCount or 0
    local over, after = dropTarget(owned)
    if over then showMarker(over, after) elseif marker then marker:Hide() end
end

-- ---------------------------------------------------------------- plus --

local function ensurePlus()
    if panel.plus then return panel.plus end
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(22, 22)
    b:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, -4)
    local text = b:CreateFontString(nil, "OVERLAY")
    ns.UI.FontFor("cooldownmanager", text, 16, nil)
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    text:SetText("+")
    text:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    b.edges = ns.MakeEdges(b, "OVERLAY")
    ns.LayoutEdges(b.edges, b, 1, 1, 1, 1, 0.15, 0)
    b:SetScript("OnEnter", function(self)
        ns.UI:ShowTooltip(self, { title = L["Add to this bar"], accent = true,
            lines = { L["Spells, items, equipment slots and your own ids."] } })
    end)
    b:SetScript("OnLeave", function() ns.UI:HideTooltip() end)
    b:SetScript("OnClick", function(self)
        local key = currentKey()
        if key then ns:ShowPopupMenu(CM.Picker.Menu(key), self, self) end
    end)
    panel.plus = b
    return b
end

-- ---------------------------------------------------------------- build --

local function build(parent)
    if not panel then
        panel = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
        panel:SetHeight(PANEL_H)

        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(panel)
        bg:SetColorTexture(0, 0, 0, 0.25)
        panel.bg = bg

        panel.edges = ns.MakeEdges(panel, "BORDER")
        ns.LayoutEdges(panel.edges, panel, 1, 1, 1, 1, 0.08, 0)

        local caption = panel:CreateFontString(nil, "OVERLAY")
        ns.UI.FontFor("cooldownmanager", caption, 11, nil)
        caption:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
        caption:SetTextColor(0.6, 0.6, 0.6)
        panel.caption = caption

        -- The preview bar is a plain frame with no mover, no anchor and no
        -- visibility rules -- everything that makes a bar a bar lives in the
        -- two passes, not in the frame.
        previewBar = CreateFrame("Frame", nil, panel)
        previewBar:SetPoint("CENTER", panel, "CENTER", 0, -6)
        previewBar.icons = {}
        previewBar.barKey = "__preview"
        panel.bar = previewBar
        panel:SetScript("OnUpdate", tick)
        ensurePlus()
    end
    -- A page rebuild orphans anything the builder does not recognise, so the
    -- panel re-adopts itself every time it is asked for.
    panel:SetParent(parent)
    -- And it takes its width from the page: a custom widget is anchored by one
    -- corner and nothing else, so a panel that never set a width is zero wide,
    -- and the fit maths below would shrink the bar to nothing.
    panel:SetWidth(math.max(120, (parent:GetWidth() or 540) - 28))
    panel:Show()
    CM.RefreshPreview()
    return panel
end

-- The options item. Height is fixed, so the page can lay itself out before the
-- bar inside is measured.
function CM.PreviewItem()
    return { type = "custom", height = PANEL_H, build = build }
end

-- ---------------------------------------------------------------- draw --

-- Which bar the preview shows. Set by the options page when the bar selector
-- changes; falls back to the first bar so the panel is never empty.
function CM.SetPreviewBar(key)
    CM.previewKey = key
    CM.RefreshPreview()
end

function CM.RefreshPreview()
    if not (panel and panel:IsShown()) then return end
    local bar = CM.Bar(CM.previewKey or "") or firstBar()
    if not bar then return end

    -- The rows the bar owns, topped up with borrowed ones so an empty or
    -- nearly empty bar still shows its layout. The borrowed ones are drawn at
    -- half strength by the paint pass, exactly as they are on screen.
    local own = CM.Own(bar)
    local list = CM.PreviewFill(own, PREVIEW_ROWS)

    previewBar:SetScale(1)
    CM.StyleFrame(previewBar, bar, list, #own)

    -- Wired after the style pass, because that is what creates the icons. The
    -- index travels with the button: the pool hands the same button out for a
    -- different row on the next draw.
    for i = 1, #previewBar.icons do
        wireDrag(i, previewBar.icons[i])
    end

    -- Fit. The page is narrower than a wide bar, and a preview that runs off
    -- the card shows the left half of a setting instead of the setting.
    local room = math.max(80, (panel:GetWidth() or 480) - 24)
    local tall = PANEL_H - 30
    local w, h = previewBar:GetWidth() or 1, previewBar:GetHeight() or 1
    local scale = math.min(1, room / math.max(w, 1), tall / math.max(h, 1))
    if scale < 1 then previewBar:SetScale(math.max(0.25, scale)) end

    local shown = math.floor(math.min(scale, 1) * 100 + 0.5)
    if shown < 100 then
        panel.caption:SetFormattedText("%s  |cff777777(%d%%)|r", L["Live preview"], shown)
    else
        panel.caption:SetText(L["Live preview"])
    end
end

