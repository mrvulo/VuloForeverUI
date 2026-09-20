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
local _, ns = ...
local L  = ns.L
local CM = ns.CM

local PANEL_H    = 118
local PREVIEW_ROWS = 5      -- how many stand-ins an empty bar borrows

local panel       -- the card, created once and re-parented on every page build
local previewBar  -- the frame the two passes run on

-- The bar the panel falls back to when nothing was chosen yet. The module can
-- be OFF while this page is open, so the bars are ensured here rather than
-- assumed to exist.
local function firstBar()
    CM.EnsureBars()
    local db = CM.db()
    local key = db and db.barOrder and db.barOrder[1]
    return key and CM.Bar(key) or nil
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

