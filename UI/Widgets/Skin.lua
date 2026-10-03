-- VuloForeverUI / UI / Widgets / Skin: close X, search box, panel-button skin, shadow, scrollbar, backdrop and Blizzard window/button art.
local _, ns = ...
local UI = ns.UI
local W = UI._W

local FONT_PATH = W.FONT_PATH

-- The dark "x" close button in a window's top-right corner (bags, bank, guild bank).
-- style "box": the client's red cross on a dark square with a thin frame.
function UI:CreateCloseX(f, onClick, style)
    local close = CreateFrame("Button", nil, f)
    if style == "box" then
        close:SetSize(18, 18)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -7, -7)
        local bg = close:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(close); bg:SetColorTexture(0.06, 0.06, 0.07, 0.95)
        local border = CreateFrame("Frame", nil, close, BackdropTemplateMixin and "BackdropTemplate")
        border:SetAllPoints(close)
        local function edge(r, g, b)
            if border.SetBackdropBorderColor then border:SetBackdropBorderColor(r, g, b, 1) end
        end
        if border.SetBackdrop then
            border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
        edge(0.32, 0.32, 0.36)
        local x = close:CreateTexture(nil, "ARTWORK")
        x:SetPoint("TOPLEFT", close, "TOPLEFT", 3, -3)
        x:SetPoint("BOTTOMRIGHT", close, "BOTTOMRIGHT", -3, 3)
        x:SetAtlas("communities-icon-redx")
        close:SetScript("OnEnter", function()
            edge(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
            x:SetVertexColor(1, 0.6, 0.6)
        end)
        close:SetScript("OnLeave", function() edge(0.32, 0.32, 0.36); x:SetVertexColor(1, 1, 1) end)
        close:SetScript("OnClick", onClick)
        return close
    end
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(cx, 20)
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(ns.TC("textDim"))
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(ns.TC("textDim")) end)
    close:SetScript("OnClick", onClick)
    return close
end

-- Dark search box with magnifier icon and accent border while focused.
-- opts: width (default 120), onText(self). Caller anchors the box.
function UI:CreateSearchBox(parent, opts)
    opts = opts or {}
    local sb = CreateFrame("EditBox", nil, parent)
    sb:SetAutoFocus(false)
    sb:SetSize(opts.width or 120, 18)
    sb:SetFont(FONT_PATH, 11, "")
    sb:SetMaxLetters(40)
    sb:SetTextInsets(22, 8, 0, 0)
    sb:SetTextColor(ns.TC("label"))
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb); bg:SetColorTexture(ns.TC("input"))
    local icon = sb:CreateTexture(nil, "OVERLAY")
    icon:SetSize(11, 11)
    icon:SetPoint("LEFT", sb, "LEFT", 6, 0)
    icon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\modules\\fixinspect.tga")
    icon:SetVertexColor(ns.TC("textMuted"))
    local border = CreateFrame("Frame", nil, sb, BackdropTemplateMixin and "BackdropTemplate")
    border:SetAllPoints(sb)
    if border.SetBackdrop then
        border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        border:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end
    sb:SetScript("OnEditFocusGained", function()
        if border.SetBackdropBorderColor then border:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end
    end)
    sb:SetScript("OnEditFocusLost", function()
        if border.SetBackdropBorderColor then border:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1) end
    end)
    if ns.theme.art then UI.ApplySearchArt(sb, bg, border) end
    sb:SetScript("OnTextChanged", opts.onText)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    return sb
end

-- Blizzard's search-box border (InputBoxVisualTemplate's three atlas pieces,
-- rounded ends) around one of our edit boxes. The flat fill is pulled in off
-- the rounded ends -- left square, it showed as two black corners outside the
-- curve -- and the flat one-pixel border steps aside.
function UI.ApplySearchArt(box, bg, border)
    if box._searchArt then return end
    box._searchArt = true
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -3)
    bg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -4, 3)
    bg:SetColorTexture(0, 0, 0, 0.5)
    if border then border:Hide() end
    local h = box:GetHeight()
    if not h or h < 1 then h = 20 end
    local left = box:CreateTexture(nil, "BORDER")
    left:SetAtlas("common-search-border-left")
    left:SetSize(8, h)
    left:SetPoint("LEFT", box, "LEFT", -5, 0)
    local right = box:CreateTexture(nil, "BORDER")
    right:SetAtlas("common-search-border-right")
    right:SetSize(8, h)
    right:SetPoint("RIGHT", box, "RIGHT", 0, 0)
    local mid = box:CreateTexture(nil, "BORDER")
    mid:SetAtlas("common-search-border-middle")
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
end

-- The normal/highlight/disabled font trio every panel-button skin needs. Four
-- modules carried a verbatim eleven-line copy of this, differing only in the
-- global name prefix. Font objects are shared on purpose: the buttons swap
-- FontObject on hover and disable, so setting the font per FontString would not
-- stick. Idempotent -- the globals are reused across calls.
function UI:PanelButtonFonts(prefix)
    local n = _G[prefix .. "Normal"]    or CreateFont(prefix .. "Normal")
    local h = _G[prefix .. "Highlight"] or CreateFont(prefix .. "Highlight")
    local d = _G[prefix .. "Disabled"]  or CreateFont(prefix .. "Disabled")
    if UI.FONT_PATH then
        n:SetFont(UI.FONT_PATH, 12, "")
        h:SetFont(UI.FONT_PATH, 12, "")
        d:SetFont(UI.FONT_PATH, 12, "")
    end
    local ac = ns.COLORS.accent
    n:SetTextColor(ns.TC("label"))
    h:SetTextColor(ac.r, ac.g, ac.b)
    d:SetTextColor(ns.TC("textMuted"))
    return n, h, d
end

-- Dark rectangular skin for a Blizzard panel button: strips the stock art,
-- draws a flat background plus four one-pixel edges, applies the caller's
-- font trio and recolours to accent on hover. Four modules carried copies.
-- opts: fonts = { normal, highlight, disabled }, border = colour table.
-- REVERSIBLE since 02.08.2026. This used to call r:SetTexture(nil) on every
-- region, which DESTROYS Blizzard's artwork: a button skinned once could never
-- wear its Blizzard look again without being rebuilt. The loadouts sidebar
-- needs exactly that switch -- Classic+ shows Blizzard's buttons, the modern
-- style the flat ones -- so the artwork is now only faded out and remembered.
--
-- Alpha rather than Hide() on purpose, and that is unchanged from before:
-- Blizzard's own button-state code calls Show/Hide on these regions when a
-- button is pressed or disabled, and would undo a Hide. It never touches alpha.
--
-- Calling it twice is now "switch back on" instead of a no-op, so a caller can
-- toggle without knowing which state it is in.
function UI:SkinPanelButton(b, opts)
    if not b then return end
    local ac = ns.COLORS.accent
    local bc = (opts and opts.border) or ns.COLORS.border or { r = 0.22, g = 0.22, b = 0.27 }

    if b._vfuiSkin then
        for _, r in ipairs(b._vfuiBlizzRegions or {}) do r:SetAlpha(0) end
        if b._vfuiBG then b._vfuiBG:Show() end
        for _, t in ipairs(b._vfuiEdges or {}) do t:Show() end
        return
    end
    b._vfuiSkin = true

    -- Only regions that carried artwork at skin time, with the alpha they had:
    -- a region Blizzard keeps invisible must stay invisible when we hand it back.
    local blizz = {}
    for _, r in ipairs({ b:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then
            blizz[#blizz + 1] = r
            r._vfuiAlpha = r:GetAlpha()
            r:SetAlpha(0)
        end
    end
    b._vfuiBlizzRegions = blizz

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(ns.TC("control"))
    local edges = {}
    for i = 1, 4 do
        local t = b:CreateTexture(nil, "BORDER")
        t:SetColorTexture(bc.r, bc.g, bc.b, 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    b._vfuiBG, b._vfuiEdges = bg, edges
    local fonts = opts and opts.fonts
    if fonts then
        if b.SetNormalFontObject then b:SetNormalFontObject(fonts[1]) end
        if b.SetHighlightFontObject then b:SetHighlightFontObject(fonts[2]) end
        if b.SetDisabledFontObject then b:SetDisabledFontObject(fonts[3]) end
    end
    b:HookScript("OnEnter", function()
        bg:SetColorTexture(ns.TC("controlHover"))
        for _, t in ipairs(edges) do t:SetColorTexture(ac.r, ac.g, ac.b, 0.9) end
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(ns.TC("control"))
        for _, t in ipairs(edges) do t:SetColorTexture(bc.r, bc.g, bc.b, 1) end
    end)
end

-- Hands the button back its Blizzard look: our flat background and border step
-- aside, the original artwork fades back to the alpha it had before we touched
-- it. The hover hooks stay installed and keep recolouring textures nobody can
-- see -- cheap, and it means SkinPanelButton can switch the look back on
-- without rebuilding anything.
--
-- Safe on a button that was never skinned: there is nothing to restore.
function UI:UnskinPanelButton(b)
    if not b or not b._vfuiSkin then return end
    if b._vfuiBG then b._vfuiBG:Hide() end
    for _, t in ipairs(b._vfuiEdges or {}) do t:Hide() end
    for _, r in ipairs(b._vfuiBlizzRegions or {}) do
        r:SetAlpha(r._vfuiAlpha or 1)
    end
end

function UI:CreateShadow(frame)
    if frame._vcShadow then return end
    frame._vcShadow = {}
    local layers = { { 1, 0.45 }, { 3, 0.28 }, { 5, 0.15 }, { 7, 0.07 } }
    for i, l in ipairs(layers) do
        local d = l[1]
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + (i - 1))
        t:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -d,  d)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  d, -d)
        t:SetColorTexture(0, 0, 0, l[2])
        frame._vcShadow[i] = t
    end
end

local function setColorBG(frame, r, g, b, a, drawLayer)
    local tex = frame:CreateTexture(nil, drawLayer or "BACKGROUND")
    tex:SetAllPoints(frame)
    tex:SetColorTexture(r, g, b, a or 1)
    return tex
end

UI.SetColorBG = setColorBG

-- Restyles a ScrollFrame built from UIPanelScrollFrameTemplate.
function UI.StyleScrollbar(scrollFrame)
    if not scrollFrame then return end

    -- API compat: the scrollbar is a property, a global by name, or an unnamed child
    local sb = scrollFrame.ScrollBar
    if not sb then
        local sfName = scrollFrame.GetName and scrollFrame:GetName()
        if sfName then sb = _G[sfName .. "ScrollBar"] end
    end
    if not sb then
        for _, child in ipairs({ scrollFrame:GetChildren() }) do
            if child.SetThumbTexture then sb = child; break end
        end
    end
    if not sb then return end

    -- The client's own scroll handlers fall back to _G[self:GetName().."ScrollBar"]
    -- when the .ScrollBar key is missing, and every scroll frame here is created
    -- unnamed -- so that lookup concatenates a nil name and throws. It throws
    -- inside OnVerticalScroll and OnScrollRangeChanged, which is why a thumb
    -- refuses to move and a scrollbar keeps showing on a page with nothing to
    -- scroll. Publishing the bar we just resolved makes those handlers take the
    -- key path and never reach for the name.
    if not scrollFrame.ScrollBar then scrollFrame.ScrollBar = sb end

    local function findChild(parent, suffix)
        local pName = parent.GetName and parent:GetName()
        if pName then
            local g = _G[pName .. suffix]
            if g then return g end
        end
        return nil
    end
    local upBtn   = sb.ScrollUpButton   or findChild(sb, "ScrollUpButton")
    local downBtn = sb.ScrollDownButton or findChild(sb, "ScrollDownButton")
    if upBtn   then upBtn:Hide();   upBtn:SetHeight(0.001)   end
    if downBtn then downBtn:Hide(); downBtn:SetHeight(0.001) end

    for _, region in ipairs({ sb:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" then
            region:SetTexture(nil)
        end
    end

    if not sb._vcTrack then
        local track = sb:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("TOP",    sb, "TOP",    0, 0)
        track:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        track:SetWidth(4)
        track:SetColorTexture(ns.TC("track"))
        sb._vcTrack = track
    end

    local thumb = sb:GetThumbTexture()
    if thumb then
        thumb:SetTexture(nil)
        thumb:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        thumb:SetSize(6, 36)
    end

    sb:SetWidth(8)
end

-- The scroll template declares an OnMouseWheel handler but leaves the wheel
-- itself switched off, so the handler has never fired -- the same shape the
-- sliders in the trinket options had. The scroll is driven from the child's
-- height rather than the scrollbar's range, because the range is only correct
-- once the client has processed the child's new size.
function UI.EnableScrollWheel(scrollFrame, child, step)
    if not scrollFrame or not scrollFrame.SetVerticalScroll then return end
    step = step or 28
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local range = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
        if range <= 0 then return end
        local v = self:GetVerticalScroll() - delta * step
        if v < 0 then v = 0 elseif v > range then v = range end
        self:SetVerticalScroll(v)
    end)
end

function UI:StyleBackdrop(frame, opts)
    opts = opts or {}
    local bgColor    = opts.bg     or ns.COLORS.bg
    local borderRGB  = opts.border or ns.COLORS.border
    local edge       = opts.edge or 1

    if not frame._vcBG then
        frame._vcBG = frame:CreateTexture(nil, "BACKGROUND")
        frame._vcBG:SetAllPoints(frame)
    end
    frame._vcBG:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)

    if not frame._vcBorders then
        frame._vcBorders = {}
        for i = 1, 4 do
            local b = frame:CreateTexture(nil, "BORDER")
            b:SetColorTexture(borderRGB.r, borderRGB.g, borderRGB.b, borderRGB.a or 1)
            frame._vcBorders[i] = b
        end
        local t, b, l, r = unpack(frame._vcBorders)
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end
    -- opts.edge: border width, 1 unless the theme draws a heavier frame
    local t, b, l, r = unpack(frame._vcBorders)
    t:SetHeight(edge); b:SetHeight(edge); l:SetWidth(edge); r:SetWidth(edge)
    for _, b in ipairs(frame._vcBorders) do
        b:SetColorTexture(borderRGB.r, borderRGB.g, borderRGB.b, borderRGB.a or 1)
    end
    -- opts.window: the settings window, which a theme with window art frames
    -- the way Blizzard frames its own.
    if opts.window then UI.ApplyWindowArt(frame) end
end

-- Blizzard's window frame over one of ours: the NineSlice layout named by the
-- theme, and the theme's background in place of the flat color. The frame
-- sits ABOVE the window's children on purpose -- the bottom bar is a child and
-- would otherwise paint over the bottom edge -- and takes no mouse, so
-- everything under it still clicks. The title bar raises itself above it
-- (UI/MainFrame/).
function UI.ApplyWindowArt(frame)
    local w = ns.theme.window
    if not w or frame._vfWindowArt then return end
    frame._vfWindowArt = true
    if w.layout and NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        local art = CreateFrame("Frame", nil, frame)
        -- Forever's metal corners sit their left edge INSIDE the container,
        -- which put the left metal on top of the sidebar (measured in game
        -- twice). The frame reaches out on the left and nowhere else, and the
        -- window background reaches out under it, so no gap opens between the
        -- metal and the window.
        local reach = 11
        art:SetPoint("TOPLEFT", frame, "TOPLEFT", -reach, 0)
        art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        art:SetFrameLevel(frame:GetFrameLevel() + 30)
        art:EnableMouse(false)
        NineSliceUtil.ApplyLayoutByName(art, w.layout)
        frame._vfWindowArt = art
        for _, e in ipairs(frame._vcBorders or {}) do e:Hide() end
        if frame._vcBG then
            frame._vcBG:ClearAllPoints()
            frame._vcBG:SetPoint("TOPLEFT", frame, "TOPLEFT", -(reach - 3), 0)
            frame._vcBG:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end
    end

    local bg = frame._vcBG
    if bg and w.bgFile then
        bg:SetTexture(w.bgFile, "REPEAT", "REPEAT")
        bg:SetHorizTile(true); bg:SetVertTile(true)
        bg:SetVertexColor(1, 1, 1, 1)
    end
end

-- The settings panel's list-row art on a sidebar row: its selected and hover
-- atlases in place of the accent gradient, wash and bar.
function UI.ApplyListArt(row, hover)
    if not ns.theme.listArt then return end
    row.bg:SetAtlas("Options_List_Active")
    row.bg:SetVertexColor(1, 1, 1, 1)
    row.accentBar:SetAlpha(0)
    hover:SetAtlas("Options_List_Hover")
    hover:SetVertexColor(1, 1, 1, 1)
end

-- UIPanelButtonTemplate's art: one texture file cut into left cap, middle and
-- right cap, swapped for its -Down twin while pressed.
local PANEL_BTN = {
    up        = "Interface\\Buttons\\UI-Panel-Button-Up",
    down      = "Interface\\Buttons\\UI-Panel-Button-Down",
    highlight = "Interface\\Buttons\\UI-Panel-Button-Highlight",
    coords    = { { 0, 0.09375 }, { 0.09375, 0.53125 }, { 0.53125, 0.625 } },
}

function UI.ApplyButtonArt(b)
    if b._artParts then return end
    b._bg:Hide()
    for _, e in ipairs(b._borders) do e:Hide() end
    local parts = {}
    for i, c in ipairs(PANEL_BTN.coords) do
        local t = b:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetTexture(PANEL_BTN.up)
        t:SetTexCoord(c[1], c[2], 0, 0.6875)
        parts[i] = t
    end
    local left, mid, right = parts[1], parts[2], parts[3]
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(12)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(12)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(PANEL_BTN.highlight)
    hl:SetTexCoord(0, 0.625, 0, 0.6875)
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(b)
    b._artParts = parts
end

function UI.SetButtonArtPressed(b, down)
    if not b._artParts then return end
    for _, t in ipairs(b._artParts) do t:SetTexture(down and PANEL_BTN.down or PANEL_BTN.up) end
end
