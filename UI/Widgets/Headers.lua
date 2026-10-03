-- VuloForeverUI / UI / Widgets / Headers: page header, description text and section heading.
local _, ns = ...
local UI = ns.UI
local W = UI._W

local clean = W.clean

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
    fs:SetTextColor(ns.TC("heading"))
    fs:SetJustifyH("LEFT")
    f._label = fs

    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("LEFT", fs, "RIGHT", 6, 0)
    UI.Font(sub, 10)
    sub:SetTextColor(ns.TC("textMuted"))
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
    b._label:SetTextColor(ns.TC("heading"))

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
    b._chevron:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\gear.tga")
    local c = expanded and ns.COLORS.accent or nil
    if c then
        b._chevron:SetVertexColor(c.r, c.g, c.b)
    else
        b._chevron:SetVertexColor(ns.TC("textDim"))
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
    b:SetScript("OnEnter", function(self) self._label:SetTextColor(ns.TC("textHi")) end)
    b:SetScript("OnLeave", function(self) self._label:SetTextColor(ns.TC("heading")) end)

    b._vcType  = "collapsible"
    b._vcSetup = collapsibleSetup
    collapsibleSetup(b, text, expanded, onClick, count)
    return b
end
