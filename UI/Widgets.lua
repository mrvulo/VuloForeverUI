-- VuloForeverUI / UI / Widgets: toggle switches, sliders, dropdowns, headers, buttons, editboxes.
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

local FONT_PATH = "Interface\\AddOns\\VuloForeverUI\\Media\\Fonts\\Expressway.TTF"
UI.FONT_PATH  = FONT_PATH
-- Default outline flags for text that names none. The global-font settings
-- overwrite BOTH fields early at ADDON_LOADED; UI.Font must therefore read the
-- exported fields, not the local above -- the local exists only as the shipped
-- default and for code that wants Expressway regardless of the setting.
UI.FONT_FLAGS = ""

local MASK_ROUNDED = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\csquare_mask.tga"
local MASK_CIRCLE  = "Interface\\AddOns\\VuloForeverUI\\Media\\Masks\\circle_mask.tga"

-- Strips "(...)" hints from labels and dropdown values; the full text stays in the tooltip.
function UI.StripParens(s)
    if type(s) ~= "string" then return s end
    return (s:gsub("%s*%b()", ""):gsub("%s+$", ""))
end
local clean = UI.StripParens

function UI.Font(fs, size, flags)
    fs:SetFont(UI.FONT_PATH, size or 12, flags or UI.FONT_FLAGS)
    return fs
end

-- Like UI.Font, but a module's own font override (Global Settings -> Fonts)
-- wins over the global face. Explicit flags stay explicit -- text that chose
-- its outline keeps it; only unflagged text follows the module outline.
function UI.FontFor(modKey, fs, size, flags)
    local path = ns.ModuleFontPath and ns.ModuleFontPath(modKey) or UI.FONT_PATH
    local fl = flags
    if fl == nil then
        fl = ns.ModuleFontFlags and ns.ModuleFontFlags(modKey) or UI.FONT_FLAGS
    end
    fs:SetFont(path, size or 12, fl)
    return fs
end

-- SetGradient(tex, orient, ...): first color is bottom/left, second is top/right.
function UI.SetGradient(tex, orient, r1, g1, b1, a1, r2, g2, b2, a2)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    if tex.SetGradient and CreateColor then
        tex:SetGradient(orient, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha(orient, r1, g1, b1, a1, r2, g2, b2, a2)
    else
        tex:SetColorTexture((r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, ((a1 or 1) + (a2 or 1)) / 2)
    end
end

-- The dark "x" close button in a window's top-right corner (bags, bank, guild bank).
function UI:CreateCloseX(f, onClick)
    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
    local cx = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(cx, 20)
    cx:SetPoint("CENTER"); cx:SetText("x"); cx:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cx:SetTextColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b) end)
    close:SetScript("OnLeave", function() cx:SetTextColor(0.7, 0.7, 0.75) end)
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
    sb:SetTextColor(0.9, 0.9, 0.95)
    local bg = sb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(sb); bg:SetColorTexture(0.04, 0.04, 0.055, 0.95)
    local icon = sb:CreateTexture(nil, "OVERLAY")
    icon:SetSize(11, 11)
    icon:SetPoint("LEFT", sb, "LEFT", 6, 0)
    icon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\modules\\fixinspect.tga")
    icon:SetVertexColor(0.55, 0.55, 0.62)
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
    sb:SetScript("OnTextChanged", opts.onText)
    sb:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    return sb
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
    n:SetTextColor(0.9, 0.9, 0.95)
    h:SetTextColor(ac.r, ac.g, ac.b)
    d:SetTextColor(0.45, 0.45, 0.5)
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
    bg:SetColorTexture(0.13, 0.13, 0.16, 1)
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
        bg:SetColorTexture(0.19, 0.19, 0.23, 1)
        for _, t in ipairs(edges) do t:SetColorTexture(ac.r, ac.g, ac.b, 0.9) end
    end)
    b:HookScript("OnLeave", function()
        bg:SetColorTexture(0.13, 0.13, 0.16, 1)
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
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8 + (i - 1))
        t:SetPoint("TOPLEFT",     frame, "TOPLEFT",     -l[1],  l[1])
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT",  l[1], -l[1])
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
        track:SetColorTexture(0.10, 0.10, 0.13, 1)
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

-- Pooled widgets are reused with a new _vcConfig, so the tooltip text has to be
-- read at hover time. Every widget below builds its spec through this.
-- A row label lives in a measured column and is cut when the translation runs
-- long -- German option names do that regularly. When it has been cut, the full
-- name leads the tooltip and the explanation follows it; a row whose label
-- fits is left exactly as it was.
--
-- GetStringWidth reports what the text NEEDS, GetWidth what the column gave it,
-- so the comparison is the truncation test without having to reproduce the
-- client's ellipsis logic. One pixel of slack, because the two disagree by
-- about that much on a string that only just fits.
local function labelClipped(fs)
    if not fs or not fs:IsShown() then return nil end
    local text = fs:GetText()
    if not text or text == "" then return nil end
    local room = fs:GetWidth() or 0
    if room <= 0 then return nil end
    if (fs:GetStringWidth() or 0) <= room + 1 then return nil end
    return text
end

local function configTip(self)
    local cfg = self._vcConfig
    local text = cfg and cfg.tooltip
    local full = labelClipped(self._label or self._labelFS)
    if not text then
        return full and { title = full, wrap = true } or nil
    end
    if not full then return { title = text, wrap = true } end
    return { title = full, wrap = true, lines = { { text, nil, nil, nil, true } } }
end

local function tooltipShow(self) UI:ShowTooltip(self, configTip(self)) end
local function tooltipHide() UI:HideTooltip() end

-- Installed once and reading the live _vcConfig: pooled widgets would otherwise stack hooks.
local function attachTooltip(frame)
    frame:SetScript("OnEnter", tooltipShow)
    frame:SetScript("OnLeave", tooltipHide)
end

function UI:StyleBackdrop(frame, opts)
    opts = opts or {}
    local bgColor    = opts.bg     or ns.COLORS.bg
    local borderRGB  = opts.border or ns.COLORS.border

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
        t:SetHeight(1)
        b:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        b:SetHeight(1)
        l:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        l:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        l:SetWidth(1)
        r:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        r:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        r:SetWidth(1)
    end
    for _, b in ipairs(frame._vcBorders) do
        b:SetColorTexture(borderRGB.r, borderRGB.g, borderRGB.b, borderRGB.a or 1)
    end
end

-- Header item: { text, subtitle? }
local function headerSetup(f, item)
    f._label:SetText(string.upper(clean(item.text) or ""))
    if item.subtitle and item.subtitle ~= "" then
        f._sub:SetText(item.subtitle)
        f._sub:Show()
    else
        f._sub:SetText("")
        f._sub:Hide()
    end
end

function UI:CreateHeader(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(480, 22)

    -- Same look as the section heading (CreateCollapsibleHeader without a
    -- click): uppercase, bright, the fading rule underneath -- and no accent
    -- tick. Two heading styles on the same pages read as two different
    -- mechanisms where there is only one (user request, 31.07.2026).
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 5)
    UI.Font(fs, 13)
    fs:SetTextColor(0.92, 0.90, 0.96)
    fs:SetJustifyH("LEFT")
    f._label = fs

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    UI.Font(sub, 10)
    sub:SetTextColor(0.40, 0.40, 0.48)
    sub:Hide()
    f._sub = sub

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    UI.SetGradient(line, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.40,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.0)

    f._vcType  = "header"
    f._vcSetup = headerSetup
    headerSetup(f, { text = text })
    return f
end

-- Desc item: { text }. Wrapped in a frame because bare regions cannot be pooled across parents.
local function descSetup(f, item)
    f._fs:SetText(item.text or "")
end

function UI:CreateDescription(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(480, 20)

    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(fs, 11)
    fs:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    local c = ns.COLORS.textDim
    fs:SetTextColor(c.r, c.g, c.b)
    fs:SetJustifyH("LEFT")
    f._fs = fs

    -- width drives the wrap; the frame then adopts the wrapped text height
    function f:SetDescWidth(w)
        self._fs:SetWidth(w)
        local _, h = self._fs:GetSize()
        self:SetSize(w, math.max(18, (h or 18)))
    end
    function f:GetDescHeight()
        local _, h = self._fs:GetSize()
        return h or 18
    end

    f._vcType  = "desc"
    f._vcSetup = descSetup
    descSetup(f, { text = text })
    return f
end

-- Section header: CreateCollapsibleHeader(parent, text, expanded, onClick)
--
-- The name is historical. Pass an onClick and it still folds -- the sidebar
-- has no use for that any more either, so almost nothing passes one today.
-- Without one it is a plain heading: no glyph, no hover, not even a mouse
-- target, because a heading that lights up under the cursor promises a click
-- that does nothing.
local function collapsibleSetup(b, title, expanded, onClick, count)
    b._label:SetText(string.upper(title or ""))
    b._label:SetTextColor(0.92, 0.90, 0.96)

    -- How many settings the heading groups, in the muted tone beside it. A
    -- pooled header carries the last page's number otherwise, so it is set on
    -- every setup -- to nothing when the caller has no count.
    if b._count then
        if count and count > 0 then
            b._count:SetText(tostring(count))
            b._count:Show()
        else
            b._count:SetText("")
            b._count:Hide()
        end
    end

    b._vcOnClick = onClick
    b:EnableMouse(onClick ~= nil)

    if not onClick then
        b._chevron:Hide()
        b._label:ClearAllPoints()
        b._label:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 5)
        return
    end

    b._chevron:Show()
    b._label:ClearAllPoints()
    b._label:SetPoint("BOTTOMLEFT", b._chevron, "BOTTOMRIGHT", 7, 1)
    -- The window's ONE expander glyph is the gear -- the same one the rows
    -- carry (user rule, 31.07.2026; Blizzard's plus/minus box was a second
    -- vocabulary for the same thing). Open tints it accent, closed stays dim,
    -- which is the signal the plus/minus pair used to carry.
    b._chevron:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\gear.tga")
    local c = expanded and ns.COLORS.accent or nil
    if c then
        b._chevron:SetVertexColor(c.r, c.g, c.b)
    else
        b._chevron:SetVertexColor(0.65, 0.65, 0.72)
    end
end

function UI:CreateCollapsibleHeader(parent, text, expanded, onClick, count)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(480, 24)

    local box = b:CreateTexture(nil, "ARTWORK")
    box:SetSize(14, 14)
    box:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 4)
    -- texture is set per state in collapsibleSetup
    box:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    b._chevron = box

    -- A heading has to outweigh what it groups. At 12 it was the same size as
    -- the setting labels below it and lighter in weight than the card borders,
    -- so the strongest thing on the page was the outline of a row.
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 7, 1)
    UI.Font(fs, 13)
    b._label = fs

    local cnt = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cnt:SetPoint("BOTTOMLEFT", fs, "BOTTOMRIGHT", 8, 1)
    UI.Font(cnt, 11)
    cnt:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)
    cnt:Hide()
    b._count = cnt

    local line = b:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -10, 0)
    line:SetHeight(1)
    UI.SetGradient(line, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.40,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.0)

    b:SetScript("OnClick", function(self) if self._vcOnClick then self._vcOnClick() end end)
    b:SetScript("OnEnter", function(self) self._label:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self._label:SetTextColor(0.92, 0.90, 0.96) end)

    b._vcType  = "collapsible"
    b._vcSetup = collapsibleSetup
    collapsibleSetup(b, text, expanded, onClick, count)
    return b
end

-- Toggle config: { label, tooltip?, get, set, width?, style = "eye"? }
local TOGGLE_W, TOGGLE_H = 36, 18
local EYE_ON  = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\eye.tga"
local EYE_OFF = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\eye_off.tga"

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
            container._eye:SetVertexColor(0.45, 0.45, 0.50, 1)
        end
        return
    end

    local knob = container._knob
    if state then
        setTrackColor(container, ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        knob:SetColorTexture(1, 1, 1, 1)
        knob:ClearAllPoints()
        knob:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
    else
        setTrackColor(container, ns.COLORS.toggleOff.r, ns.COLORS.toggleOff.g, ns.COLORS.toggleOff.b)
        knob:SetColorTexture(0.72, 0.72, 0.78, 1)
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
    label:SetTextColor(0.95, 0.95, 0.97)

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
        knob:SetColorTexture(1, 1, 1, 1)
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

-- Slider config: { label, tooltip?, min, max, step, get, set, width? }
-- Rounds a flat colour texture with one of the bundled masks. Turning texel
-- snapping off matters as much as the mask: with it on, small rounded art is
-- snapped hard onto the pixel grid and the curve comes out visibly stepped.
local function roundTexture(owner, tex, maskFile)
    if not (owner and tex and owner.CreateMaskTexture and tex.AddMaskTexture) then return end
    local m = owner:CreateMaskTexture()
    m:SetTexture(maskFile, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(tex)          -- tracks the fill as it grows
    tex:AddMaskTexture(m)
    if tex.SetSnapToPixelGrid   then tex:SetSnapToPixelGrid(false) end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    return m
end

local function sliderUpdateFill(s, v)
    local sMin, sMax = s._min or 0, s._max or 100
    local frac = 0
    if sMax > sMin then frac = (v - sMin) / (sMax - sMin) end
    frac = math.max(0, math.min(1, frac))
    local w = (s._trackBg:GetWidth() or s:GetWidth() or 200) * frac
    s._trackFill:SetWidth(math.max(0.001, w))
end

-- ONE place decides what a slider value looks like. It used to be decided
-- twice: OnValueChanged rounded to the step, the setup path did not -- so a
-- value written by something other than the slider (a frame dragged in edit
-- mode, say) came back as 7.6293945 on a slider whose step is 1, and then got
-- clipped to "7.629..." by a 36px box.
local function snapSliderValue(step, v)
    v = tonumber(v) or 0
    step = tonumber(step) or 1
    if step >= 1 then return math.floor(v / step + 0.5) * step end
    -- Sub-integer steps: round to the step's own precision, so 0.05 gives 1.35
    -- and never 1.3500000000000001.
    local inv = 1 / step
    return math.floor(v * inv + 0.5) / inv
end

local function formatSliderValue(step, v)
    return string.format("%g", snapSliderValue(step, v))
end

-- Wide enough for the widest value the range can produce, instead of a fixed
-- 36 which "-800" never fitted into.
local function sliderValueWidth(min, max, step)
    local widest = math.max(#formatSliderValue(step, min or 0), #formatSliderValue(step, max or 0))
    return math.max(36, 8 + widest * 7)
end

-- What the -/value/+ block occupies at the right end of a slider row: the gap
-- to the track, the two 16px buttons, the value box and the gaps between them.
-- The options page asks this before it builds anything, because how many
-- columns a run may use depends on whether a track still fits beside it.
function UI.SliderEndWidth(min, max, step)
    return 8 + 16 + 4 + sliderValueWidth(min, max, step) + 4 + 16 + 4
end

-- Row metrics. They are the same numbers the toggle and dropdown rows use, so
-- the three line up without anyone tuning gaps by eye.
local SLIDER_ROW_H  = 24
local SLIDER_LABEL_W = 120   -- default until the page measures the real column
local LABEL_GAP      = 12
local DEFAULT_TRACK_W = 160  -- when the caller names no track width
-- Exported because the options page has to reproduce this row's arithmetic to
-- decide a column count. Two copies of the number would drift the moment one
-- of them was tuned, and the drift would show up as a clipped label.
UI.SLIDER_LABEL_GAP = LABEL_GAP

-- The track is what is left after the label column and the -/value/+ block.
-- A local, declared before CreateSlider because both the setup and the size
-- hook close over it.
local function layoutSliderRow(row)
    local s = row and row._slider
    if not s then return end

    -- No label, no column and no gap. The edit-mode toolbar builds sliders with
    -- label = "" and its own caption beside them; reserving a column there would
    -- shove a 70px track out of the toolbar entirely.
    local hasLabel = (row.label:GetText() or "") ~= ""
    local w = row:GetWidth() or 260
    local labelW = 0
    if hasLabel then
        labelW = math.min(row._labelW or SLIDER_LABEL_W, math.max(40, w * 0.5))
    end
    row.label:SetWidth(math.max(1, labelW))
    row.label:SetShown(hasLabel)

    local left = hasLabel and (labelW + LABEL_GAP) or 0
    s:ClearAllPoints()
    s:SetPoint("LEFT", row, "LEFT", left, 0)
    -- A floor, not a licence to overflow. The -/value/+ block is anchored to the
    -- ROW, so a cell too narrow for the track costs track width and stops there.
    -- While the block hung off the track it moved with it, and every pixel the
    -- floor invented was a pixel drawn on top of the next column.
    s:SetWidth(math.max(24, w - left - (row._endW or 90)))
end

local function sliderSetup(row, config)
    local s = row._slider
    s._vcConfig = config
    -- Also on the row: callers outside the options builder hold the row and read
    -- _vcConfig off it to rebuild themselves (UI/EditMode.lua does).
    row._vcConfig = config
    s._min  = config.min or 0
    s._max  = config.max or 100
    s._step = config.step or 1

    -- SetMinMaxValues/SetValue fire OnValueChanged; a reconfigure must not call config.set()
    s._configuring = true
    s:SetMinMaxValues(s._min, s._max)
    s:SetValueStep(s._step)
    row.label:SetText(clean(config.label) or "")

    local valW = sliderValueWidth(s._min, s._max, s._step)
    s._valueText:SetWidth(valW)
    -- gap + minus + gap + value + gap + plus, matching the anchors below. The
    -- options page needs the same number BEFORE the row exists, to decide how
    -- many columns fit -- so the formula lives in UI.SliderEndWidth and both
    -- read it there rather than each keeping its own copy.
    row._endW = UI.SliderEndWidth(s._min, s._max, s._step)

    -- config.width has always meant the TRACK width, not the row width. Callers
    -- that pass it (the edit-mode toolbar) size themselves around the track, so
    -- the row takes the track plus whatever the label and value block need.
    --
    -- Sized in BOTH cases now, not only when a width was given. The options page
    -- reads a control's width back when it lays out a row of them, and an unsized
    -- row handed it whatever the pooled widget carried over from the last page
    -- that used it.
    local labelPart = (clean(config.label) or "") ~= "" and (row._labelW + LABEL_GAP) or 0
    row:SetWidth(labelPart + (config.width or DEFAULT_TRACK_W) + row._endW)

    local v = config.get(s) or s._min
    s:SetValue(v)
    s._valueText:SetText(formatSliderValue(s._step, v))
    layoutSliderRow(row)
    sliderUpdateFill(s, v)
    s._configuring = false

    -- re-fill next frame, once the track has its real width
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if s:IsShown() then sliderUpdateFill(s, s:GetValue() or s._min) end
        end)
    end
end

function UI:CreateSlider(parent, config)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetObeyStepOnDrag(true)

    if s.Low  then s.Low:SetText("") end
    if s.High then s.High:SetText("") end
    if s.Text then
        UI.Font(s.Text, 12)
        s.Text:SetTextColor(0.95, 0.95, 0.97)
        -- The template centres its label over the track. Every other label on
        -- the page starts at the left edge, so a centred one broke the single
        -- reading edge that lets you scan a column of settings by their names
        -- instead of reading each row.
        s.Text:ClearAllPoints()
        s.Text:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 1)
        s.Text:SetJustifyH("LEFT")
    end

    local accent = ns.COLORS.accent
    local thumb  = s:GetThumbTexture()

    -- The template ships its own groove art, which sits under our flat track and
    -- reads as a second, misaligned bar. Drop it before we draw anything.
    for _, r in ipairs({ s:GetRegions() }) do
        if r ~= thumb and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end

    -- A 6px bar is only the drawing; the frame stays the grab target, and a few
    -- px of slack on top of that is the difference between precise and fiddly.
    s:SetHitRectInsets(0, 0, -3, -3)

    -- White at low alpha rather than a fixed grey: it stays hue-neutral, so the
    -- track keeps the same relationship to any panel colour behind it.
    local TRACK_IDLE, TRACK_HOVER = 0.16, 0.24
    local trackBg = s:CreateTexture(nil, "ARTWORK", nil, 1)
    trackBg:SetHeight(6)
    trackBg:SetPoint("LEFT", s, "LEFT", 2, 0)
    trackBg:SetPoint("RIGHT", s, "RIGHT", -2, 0)
    trackBg:SetColorTexture(1, 1, 1, TRACK_IDLE)
    roundTexture(s, trackBg, MASK_ROUNDED)

    -- Inner shadow along the top lip: reads as carved into the panel instead of
    -- laid on top of it. Two pixels is enough; more looks like a smudge.
    local trackShade = s:CreateTexture(nil, "ARTWORK", nil, 2)
    trackShade:SetPoint("TOPLEFT",  trackBg, "TOPLEFT",  0, 0)
    trackShade:SetPoint("TOPRIGHT", trackBg, "TOPRIGHT", 0, 0)
    trackShade:SetHeight(2)
    UI.SetGradient(trackShade, "VERTICAL", 0, 0, 0, 0, 0, 0, 0, 0.45)
    roundTexture(s, trackShade, MASK_ROUNDED)

    local trackFill = s:CreateTexture(nil, "ARTWORK", nil, 3)
    trackFill:SetHeight(6)
    trackFill:SetPoint("LEFT", trackBg, "LEFT", 0, 0)
    trackFill:SetColorTexture(accent.r, accent.g, accent.b, 0.95)
    roundTexture(s, trackFill, MASK_ROUNDED)

    -- One-pixel gloss on the fill's top edge; the classic glass cue. Inset by a
    -- pixel so it cannot poke out of the fill's rounded corners.
    local fillGloss = s:CreateTexture(nil, "ARTWORK", nil, 4)
    fillGloss:SetPoint("TOPLEFT",  trackFill, "TOPLEFT",   1, 0)
    fillGloss:SetPoint("TOPRIGHT", trackFill, "TOPRIGHT", -1, 0)
    fillGloss:SetHeight(1)
    fillGloss:SetColorTexture(1, 1, 1, 0.12)

    s._trackBg, s._trackFill = trackBg, trackFill
    s._updateFill = function(v) sliderUpdateFill(s, v) end

    -- Accent halo behind the knob, so it reads as a control rather than a blob.
    -- ~1.3x the knob; at 2x it stops looking deliberate and starts looking broken.
    local thumbGlow = s:CreateTexture(nil, "ARTWORK", nil, 5)
    thumbGlow:SetSize(20, 20)
    thumbGlow:SetColorTexture(accent.r, accent.g, accent.b, 0.5)
    roundTexture(s, thumbGlow, MASK_CIRCLE)
    thumbGlow:Hide()

    if thumb then
        -- Desaturated knob over a saturated fill separates on two channels at
        -- once, which holds up far better than brightness alone.
        thumb:SetColorTexture(0.97, 0.97, 1.0, 1)
        thumb:SetSize(15, 15)
        thumb:SetDrawLayer("OVERLAY")     -- keep it above the halo
        roundTexture(s, thumb, MASK_CIRCLE)
        thumbGlow:SetPoint("CENTER", thumb, "CENTER", 0, 0)
        thumbGlow:Show()
    end

    -- Eased hover, instant press. Current values live in upvalues so an
    -- interrupted fade continues from where it actually is rather than snapping
    -- back to a base value first.
    local GLOW_IDLE, GLOW_HOVER, GLOW_PRESS = 0.55, 0.9, 1.0
    local glowNow,  glowGoal  = GLOW_IDLE, GLOW_IDLE
    local trackNow, trackGoal = TRACK_IDLE, TRACK_IDLE
    local function paintState()
        thumbGlow:SetAlpha(glowNow)
        trackBg:SetColorTexture(1, 1, 1, trackNow)
    end
    local function fadeTick(self, elapsed)
        local k = math.min(1, (elapsed or 0) / 0.18 * 3)
        local settled = true
        if math.abs(glowGoal - glowNow) > 0.004 then
            glowNow = glowNow + (glowGoal - glowNow) * k; settled = false
        else glowNow = glowGoal end
        if math.abs(trackGoal - trackNow) > 0.003 then
            trackNow = trackNow + (trackGoal - trackNow) * k; settled = false
        else trackNow = trackGoal end
        paintState()
        if settled then self:SetScript("OnUpdate", nil) end
    end
    s._setSliderState = function(hovered, pressed)
        glowGoal  = pressed and GLOW_PRESS or (hovered and GLOW_HOVER or GLOW_IDLE)
        trackGoal = (hovered or pressed) and TRACK_HOVER or TRACK_IDLE
        if pressed then
            -- ease OUT of a press, never into it: a fading press feels laggy
            glowNow, trackNow = glowGoal, trackGoal
            s:SetScript("OnUpdate", nil)
            paintState()
        else
            s:SetScript("OnUpdate", fadeTick)
        end
    end
    paintState()
    s._thumbGlow = thumbGlow

    local function makeStepButton(label, dir)
        local b = CreateFrame("Button", nil, s)
        b:SetSize(16, 16)
        local border = b:CreateTexture(nil, "BACKGROUND")
        border:SetAllPoints(b)
        border:SetColorTexture(0.3, 0.3, 0.35, 1)
        roundTexture(b, border, MASK_ROUNDED)
        local fill = b:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
        fill:SetColorTexture(0.14, 0.14, 0.16, 1)
        roundTexture(b, fill, MASK_ROUNDED)
        local txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(txt, 12)
        txt:SetPoint("CENTER", b, "CENTER", 0, 1)
        txt:SetText(label)
        b:SetScript("OnEnter", function() border:SetColorTexture(accent.r, accent.g, accent.b, 1) end)
        b:SetScript("OnLeave", function() border:SetColorTexture(0.3, 0.3, 0.35, 1) end)
        b:RegisterForClicks("LeftButtonUp")
        b:SetScript("OnClick", function()
            local mult = IsShiftKeyDown() and 5 or 1
            s:SetValue(s:GetValue() + dir * (s._step or 1) * mult)
        end)
        return b
    end

    local minusBtn = makeStepButton("-", -1)
    minusBtn:SetPoint("LEFT", s, "RIGHT", 8, 0)

    -- An EDIT BOX, not a label: going from 8 to 190 used to mean holding "+".
    -- Click the number, type it, press Enter. It still reads like plain text
    -- until you touch it, so nothing shouts for attention.
    local valueText = CreateFrame("EditBox", nil, s)
    valueText:SetPoint("LEFT", minusBtn, "RIGHT", 4, 0)
    valueText:SetSize(36, 18)
    valueText:SetAutoFocus(false)
    valueText:SetJustifyH("CENTER")
    valueText:SetFontObject("GameFontHighlightSmall")
    UI.Font(valueText, 11)
    valueText:SetTextInsets(2, 2, 0, 0)

    local vbg = valueText:CreateTexture(nil, "BACKGROUND")
    vbg:SetAllPoints(valueText)
    vbg:SetColorTexture(1, 1, 1, 0.05)
    vbg:Hide()
    valueText:SetScript("OnEnter", function(self) vbg:Show() end)
    valueText:SetScript("OnLeave", function(self) if not self:HasFocus() then vbg:Hide() end end)
    valueText:SetScript("OnEditFocusGained", function(self) vbg:Show(); self:HighlightText() end)

    local function restoreFromSlider(self)
        self:HighlightText(0, 0)
        self:SetText(formatSliderValue(s._step, s:GetValue() or s._min))
        self:ClearFocus()
        if not self:IsMouseOver() then vbg:Hide() end
    end

    valueText:SetScript("OnEnterPressed", function(self)
        local typed = tonumber(self:GetText())
        if typed then
            -- Clamp before snapping: typing 9999 into a 0..100 slider should
            -- land on 100, not be refused without a word.
            typed = math.max(s._min, math.min(s._max, typed))
            s:SetValue(snapSliderValue(s._step, typed))
        end
        restoreFromSlider(self)
    end)
    valueText:SetScript("OnEscapePressed", restoreFromSlider)
    valueText:SetScript("OnEditFocusLost", restoreFromSlider)

    s._valueText = valueText

    local plusBtn = makeStepButton("+", 1)
    plusBtn:SetPoint("LEFT", valueText, "RIGHT", 4, 0)

    s:SetScript("OnValueChanged", function(self, v)
        local cfg = self._vcConfig
        if not cfg then return end
        v = snapSliderValue(cfg.step, v)
        -- Never fight the user's cursor: if they are typing in the box, the
        -- slider must not overwrite what is half-entered.
        if not self._valueText:HasFocus() then
            self._valueText:SetText(formatSliderValue(cfg.step, v))
        end
        sliderUpdateFill(self, v)
        if self._configuring then return end
        cfg.set(self, v)
    end)

    attachTooltip(s)
    -- hooked after attachTooltip so its own handlers can't displace these
    s:HookScript("OnEnter", function(self)
        if self._setSliderState then self._setSliderState(true, self._pressed) end
    end)
    s:HookScript("OnLeave", function(self)
        if self._setSliderState then self._setSliderState(false, self._pressed) end
    end)
    s:HookScript("OnMouseDown", function(self)
        self._pressed = true
        if self._setSliderState then self._setSliderState(true, true) end
    end)
    -- IsMouseOver decides the target, or letting go off-frame strands it bright
    s:HookScript("OnMouseUp", function(self)
        self._pressed = nil
        if self._setSliderState then self._setSliderState(self:IsMouseOver(), false) end
    end)

    -- ---- one-line row --------------------------------------------------
    -- The slider keeps every bit of its own drawing; it simply stops being the
    -- thing the page places. The row is [label][track][- value +] -- the same
    -- shape a toggle and a dropdown row have, which is what lets a page of
    -- mixed controls line up on one edge instead of on three.
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(SLIDER_ROW_H)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(row.label, 12)
    row.label:SetTextColor(0.95, 0.95, 0.97)
    row.label:SetJustifyH("LEFT")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWordWrap(false)

    s:SetParent(row)
    s:ClearAllPoints()
    -- The template's own label is retired: the row owns the text now. Leaving
    -- it alive would draw a second, centred copy over the track.
    if s.Text then s.Text:SetText(""); s.Text:Hide() end

    row._slider = s
    row._labelW = SLIDER_LABEL_W
    row._endW   = 90

    -- Re-anchored now that the row exists: the block hangs off the ROW's right
    -- edge, not the track's. Chained to the track it inherited every pixel the
    -- track's minimum width invented, and in a narrow cell that put the value
    -- box and the + button on top of the neighbouring column. Anchored here the
    -- row is a closed box -- nothing it contains can leave it, whatever width
    -- the page hands it.
    plusBtn:ClearAllPoints()
    plusBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    valueText:ClearAllPoints()
    valueText:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
    minusBtn:ClearAllPoints()
    minusBtn:SetPoint("RIGHT", valueText, "LEFT", -4, 0)

    row.SetLabelWidth = function(self, w)
        self._labelW = math.max(20, w or SLIDER_LABEL_W)
        layoutSliderRow(self)
    end
    row:SetScript("OnSizeChanged", function(self) layoutSliderRow(self) end)

    row._vcType  = "slider"
    row._vcSetup = sliderSetup
    sliderSetup(row, config)
    return row
end

-- Dropdown config: { label?, tooltip?, values = { { text, value }, ... }, get, set, width? }
-- One popup frame is shared by all dropdowns; only one can be open at a time.
local activePopup

-- Exported below as UI.CloseDropdownPopup: a panel that hands its widgets back
-- to the pool has to shut any menu still hanging off one of them first, or the
-- menu outlives the button it belongs to.
local function closeActivePopup()
    if activePopup and activePopup:IsShown() then
        activePopup:Hide()
        if activePopup._owner and activePopup._owner._setHovered then
            activePopup._owner._setHovered(false)
        end
        activePopup._owner = nil
    end
end
UI.CloseDropdownPopup = closeActivePopup

-- Forward-declared: the wheel handler below is written before the function
-- exists, and a plain reference there would resolve to a nil GLOBAL and scroll
-- nothing, silently.
local placePopupRows

local function ensurePopupFrame()
    if activePopup then return activePopup end
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
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.99)
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
    trackBG:SetColorTexture(0.10, 0.10, 0.13, 1)
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

    activePopup = p
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
    b._icon:SetVertexColor(0.72, 0.72, 0.78)

    b._glyph = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(b._glyph, 13)
    b._glyph:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._glyph:SetTextColor(0.72, 0.72, 0.78)

    b:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1)
        self._glyph:SetTextColor(1, 1, 1)
        if self._tooltip then
            UI:ShowTooltip(self, { title = self._tooltip, wrap = true, anchor = "ANCHOR_RIGHT" })
        end
    end)
    b:SetScript("OnLeave", function(self)
        self._icon:SetVertexColor(0.72, 0.72, 0.78)
        self._glyph:SetTextColor(0.72, 0.72, 0.78)
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
            item._text:SetTextColor(0.45, 0.45, 0.50)
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
                    item._text:SetTextColor(0.88, 0.88, 0.90)
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
                item._text:SetTextColor(0.88, 0.88, 0.90)
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
            b._text:SetTextColor(1, 1, 1)
        else
            b._text:SetTextColor(0.72, 0.72, 0.78)
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
    label:SetTextColor(0.95, 0.95, 0.97)
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

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(0.95, 0.95, 0.97)
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
    UI:StyleBackdrop(btn, { bg = { r = 0.06, g = 0.06, b = 0.08, a = 1 } })
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
    arrow:SetVertexColor(0.7, 0.7, 0.75)

    local function setHovered(state)
        local c = state and ns.COLORS.accent or ns.COLORS.border
        for _, b in ipairs(borders) do
            b:SetColorTexture(c.r, c.g, c.b, 1)
        end
        if state then
            arrow:SetVertexColor(1, 1, 1)
        else
            arrow:SetVertexColor(0.7, 0.7, 0.75)
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
        if not (activePopup and activePopup:IsShown() and activePopup._owner == btn) then
            setHovered(false)
        end
    end)

    btn:SetScript("OnClick", function(self)
        if activePopup and activePopup:IsShown() and activePopup._owner == self then
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

-- EditBox config: { label?, tooltip?, get, set, numeric?, width?, editWidth?, commitOnFocusLost?, onEnter? }
local function editboxSetup(container, config)
    container._vcConfig = config
    local label, eb = container._labelFS, container._editBox
    eb:ClearAllPoints(); label:ClearAllPoints()
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)

    if config.label and config.label ~= "" then
        label:SetText(clean(config.label))
        label:Show()
        label:SetPoint("LEFT", container, "LEFT", 0, 0)
        local editW = config.editWidth or 130
        eb:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        eb:SetWidth(editW)
        label:SetPoint("RIGHT", eb, "LEFT", -10, 0)
        local labelW = label:GetStringWidth() or 80
        container:SetWidth(config.width or (labelW + 14 + editW))
    else
        label:Hide()
        eb:SetPoint("LEFT", container, "LEFT", 0, 0)
        eb:SetWidth(config.width or 160)
        container:SetWidth(config.width or 160)
    end

    eb:ClearFocus()
    eb:SetText(tostring(config.get(eb) or ""))
end

function UI:CreateEditBox(parent, config)
    local container = CreateFrame("Frame", nil, parent)
    container:SetHeight(26)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(label, 12)
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetTextColor(0.95, 0.95, 0.97)
    container._labelFS = label

    local eb = CreateFrame("EditBox", nil, container)
    eb:SetHeight(22)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT_PATH, 12, "")
    eb:SetTextInsets(8, 8, 0, 0)
    container._editBox = eb

    local bg = eb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(eb)
    bg:SetColorTexture(0.06, 0.05, 0.10, 0.85)
    eb._bg = bg

    local borderColor = ns.COLORS.border or { r = 0.35, g = 0.25, b = 0.55, a = 1 }
    local borderFrame = CreateFrame("Frame", nil, eb,
        BackdropTemplateMixin and "BackdropTemplate")
    borderFrame:SetAllPoints(eb)
    if borderFrame.SetBackdrop then
        borderFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
    end
    eb._borderFrame = borderFrame

    eb:SetScript("OnEditFocusGained", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            local c = ns.COLORS.accent
            self._borderFrame:SetBackdropBorderColor(c.r, c.g, c.b, 1)
        end
    end)
    eb:SetScript("OnEditFocusLost", function(self)
        if self._borderFrame and self._borderFrame.SetBackdropBorderColor then
            self._borderFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a or 1)
        end
        -- opt-in: an adjacent button steals focus before its OnClick, so commit here too
        local cfg = container._vcConfig
        if cfg and cfg.commitOnFocusLost then
            local v = self:GetText()
            if cfg.numeric then v = tonumber(v) end
            cfg.set(self, v)
        end
    end)

    eb:SetScript("OnEnterPressed", function(self)
        local cfg = container._vcConfig
        if not cfg then self:ClearFocus(); return end
        local v = self:GetText()
        if cfg.numeric then v = tonumber(v) end
        cfg.set(self, v)
        self:ClearFocus()
        if cfg.onEnter then cfg.onEnter(v) end
    end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    attachTooltip(container)
    container._vcType  = "editbox"
    container._vcSetup = editboxSetup
    editboxSetup(container, config)
    return container
end

-- Button config: { label, tooltip?, onClick, width?, height?, primary?, danger? }
-- danger wins over primary: a destructive action keeps its warning color even
-- when it is also the centred main action of its row.
local BTN_DANGER = { r = 0.85, g = 0.28, b = 0.28 }

local function buttonApplyIdle(b)
    local cfg = b._vcConfig
    if cfg and cfg.danger then
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(BTN_DANGER, 0.70)
        b._textFS:SetTextColor(0.92, 0.40, 0.40, 0.95)
    elseif cfg and cfg.primary then
        local a = ns.COLORS.accent
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(a, 0.70)
        b._textFS:SetTextColor(a.r, a.g, a.b, 0.95)
    else
        b._bg:SetColorTexture(0.13, 0.13, 0.16, 1)
        b._setBorder(ns.COLORS.border)
        b._textFS:SetTextColor(0.95, 0.95, 0.97)
    end
end

local function buttonSetup(b, config)
    b._vcConfig = config
    b._textFS:SetText(clean(config.label) or "")
    local w = config.width or 120
    local tw = (b._textFS:GetStringWidth() or 0) + 36
    b:SetSize(math.max(w, tw), config.height or 26)
    buttonApplyIdle(b)
end

function UI:CreateButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b._bg = bg

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    b._setBorder = function(c, a)
        for _, bt in ipairs(borders) do bt:SetColorTexture(c.r, c.g, c.b, a or 1) end
    end

    local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._textFS = text

    b:SetScript("OnEnter", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.danger then
            local d = BTN_DANGER
            bg:SetColorTexture(d.r * 0.20, d.g * 0.20, d.b * 0.20, 1)
            self._setBorder(d, 1)
            self._textFS:SetTextColor(1, 0.45, 0.45, 1)
        elseif cfg and cfg.primary then
            local a = ns.COLORS.accent
            bg:SetColorTexture(a.r * 0.16, a.g * 0.16, a.b * 0.16, 1)
            self._setBorder(a, 1)
            self._textFS:SetTextColor(a.r, a.g, a.b, 1)
        else
            bg:SetColorTexture(0.19, 0.19, 0.23, 1)
            self._setBorder(ns.COLORS.accent, 0.8)
        end
        UI:ShowTooltip(self, configTip(self))
    end)
    b:SetScript("OnLeave", function(self)
        buttonApplyIdle(self)
        UI:HideTooltip()
    end)

    b:SetScript("OnMouseDown", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, -1)
    end)
    b:SetScript("OnMouseUp", function(self)
        self._textFS:SetPoint("CENTER", self, "CENTER", 0, 0)
    end)

    b:SetScript("OnClick", function(self)
        -- Commit the neighbouring edit box FIRST. A WoW edit box keeps its
        -- keyboard focus through a button click (nothing steals it), so an
        -- "Add" clicked right after typing ran against the EMPTY committed
        -- value and silently did nothing -- the field only ever committed via
        -- Enter. Clearing focus here fires OnEditFocusLost synchronously,
        -- which is where commitOnFocusLost hands the text over, and only then
        -- does the click handler run.
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.ClearFocus then focus:ClearFocus() end
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    b._vcType  = "button"
    b._vcSetup = buttonSetup
    buttonSetup(b, config)
    return b
end

-- IconButton config: { icon = "up"/"down"/"left"/"right" or a texture path, tooltip?, onClick, width?, height?, iconInset? }
local ARROW_DIR = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\"
local BUILTIN_ICONS = {
    up    = { tex = ARROW_DIR .. "arrow_up.tga",    tc = {0, 1, 0, 1} },
    down  = { tex = ARROW_DIR .. "arrow_down.tga",  tc = {0, 1, 0, 1} },
    left  = { tex = ARROW_DIR .. "arrow_left.tga",  tc = {0, 1, 0, 1} },
    right = { tex = ARROW_DIR .. "arrow_right.tga", tc = {0, 1, 0, 1} },
}

local function iconButtonSetup(b, config)
    b._vcConfig = config
    b:SetSize(config.width or 24, config.height or 24)
    local icon = b._icon
    local inset = config.iconInset or 10
    icon:SetSize((config.width or 24) - inset, (config.height or 24) - inset)
    icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)

    local iconKey = config.icon
    local builtin = iconKey and BUILTIN_ICONS[iconKey]
    if builtin then
        icon:SetTexture(builtin.tex)
        icon:SetTexCoord(unpack(builtin.tc))
    else
        icon:SetTexCoord(0, 1, 0, 1)
        if iconKey then icon:SetTexture(iconKey) end
    end
end

function UI:CreateIconButton(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.15, 0.15, 0.18, 1)

    local borderColor = ns.COLORS.border
    local borders = {}
    for i = 1, 4 do
        local bt = b:CreateTexture(nil, "BORDER")
        bt:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, 1)
        borders[i] = bt
    end
    borders[1]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[1]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", b, "TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", b, "TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT"); borders[4]:SetWidth(1)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b._icon = icon

    b:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.22, 0.22, 0.26, 1)
        icon:SetVertexColor(1, 1, 1)
        UI:ShowTooltip(self, configTip(self))
    end)
    b:SetScript("OnLeave", function()
        bg:SetColorTexture(0.15, 0.15, 0.18, 1)
        icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        local cfg = self._vcConfig
        if cfg and cfg.onClick then cfg.onClick(self) end
    end)

    b._vcType  = "iconbutton"
    b._vcSetup = iconButtonSetup
    iconButtonSetup(b, config)
    return b
end

-- PowerButton config: { size?, tooltip?, get() -> bool, set(bool) }
function UI:CreatePowerButton(parent, config)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(config.size or 14, config.size or 14)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    icon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\power")
    b._icon = icon

    local function refresh()
        local on = config.get() and true or false
        if on then
            icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        else
            icon:SetVertexColor(0.4, 0.4, 0.4, 0.6)
        end
    end

    b:SetScript("OnClick", function()
        local newState = not (config.get() and true or false)
        config.set(newState)
        refresh()
    end)

    b:SetScript("OnEnter", function()
        icon:SetVertexColor(1, 1, 1, 1)
        if config.tooltip then
            UI:ShowTooltip(b, { title = config.tooltip, wrap = true })
        end
    end)
    b:SetScript("OnLeave", function()
        refresh()
        UI:HideTooltip()
    end)

    refresh()
    b._refresh = refresh
    return b
end

-- ColorSwatch config: { label, get() -> {r,g,b} or {r=,g=,b=}, set(r,g,b), width? }
function UI:CreateColorSwatch(parent, config)
    local b = CreateFrame("Button", nil, parent)

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(label, 12); label:SetTextColor(0.95, 0.95, 0.97)
    label:SetPoint("LEFT", b, "LEFT", 0, 0)
    label:SetJustifyH("LEFT"); label:SetWordWrap(false)
    b._label = label

    local sw = CreateFrame("Button", nil, b)
    sw:SetSize(18, 18)
    sw:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    local border = sw:CreateTexture(nil, "BACKGROUND"); border:SetAllPoints(); border:SetColorTexture(0, 0, 0, 0.8)
    local fill = sw:CreateTexture(nil, "ARTWORK"); fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b._fill = fill
    label:SetPoint("RIGHT", sw, "LEFT", -8, 0)

    -- Optional per-row reset between label and swatch; exists only while the
    -- config carries onReset. Pooled reuse hides it again via _vcSetup.
    local rb = CreateFrame("Button", nil, b)
    rb:SetSize(16, 16)
    rb:SetPoint("RIGHT", sw, "LEFT", -6, 0)
    local rt = rb:CreateTexture(nil, "ARTWORK")
    rt:SetAllPoints()
    rt:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\reset.tga")
    rt:SetVertexColor(0.75, 0.75, 0.80, 0.55)
    rb:Hide()

    local function curRGB()
        local cfg = b._vcConfig
        local c = cfg and cfg.get and cfg.get()
        if not c then return 1, 1, 1 end
        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1
    end
    local function refresh()
        local r, g, bl = curRGB(); fill:SetColorTexture(r, g, bl, 1)
        -- labelTint paints the label in the row's own color (class-color rows);
        -- pooled reuse without the flag gets the standard color back.
        local cfg = b._vcConfig
        if cfg and cfg.labelTint then
            label:SetTextColor(r, g, bl)
        else
            label:SetTextColor(0.95, 0.95, 0.97)
        end
    end
    local function open()
        local r, g, bl = curRGB()
        ns:ShowColorPicker({ r = r, g = g, b = bl, onChange = function(nr, ng, nb)
            local cfg = b._vcConfig
            if cfg and cfg.set then cfg.set(nr, ng, nb) end
            refresh()
        end })
    end
    b:SetScript("OnClick", open)
    sw:SetScript("OnClick", open)
    sw:SetScript("OnEnter", function() border:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1) end)
    sw:SetScript("OnLeave", function() border:SetColorTexture(0, 0, 0, 0.8) end)
    rb:SetScript("OnEnter", function() rt:SetVertexColor(1, 1, 1, 0.9); UI:ShowTooltip(rb, L["Reset to default"]) end)
    rb:SetScript("OnLeave", function() rt:SetVertexColor(0.75, 0.75, 0.80, 0.55); UI:HideTooltip() end)
    rb:SetScript("OnClick", function()
        local cfg = b._vcConfig
        if cfg and cfg.onReset then cfg.onReset() end
        refresh()
    end)

    b._refresh = refresh
    b._vcType  = "color"
    b._vcSetup = function(self, cfg)
        self._vcConfig = cfg
        self._label:SetText(clean(cfg.label) or "")
        local hasReset = cfg.onReset ~= nil
        rb:SetShown(hasReset)
        -- Re-anchoring the same point replaces it; the label clamps against
        -- whatever sits leftmost on the control side.
        label:SetPoint("RIGHT", hasReset and rb or sw, "LEFT", -8, 0)
        local extra = hasReset and 22 or 0
        if cfg.width then
            self:SetSize(cfg.width, 22)
        else
            self:SetSize(math.max((self._label:GetStringWidth() or 0) + 12 + 18 + extra, 120), 22)
        end
        refresh()
    end
    b._vcSetup(b, config)
    return b
end
