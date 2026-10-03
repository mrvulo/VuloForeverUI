-- VuloForeverUI / UI / EditMode / State: session settings, snap modes, grid, session looks, selection list and box styles.
-- Self-driven Edit Mode HUD: Blizzard's own is protected, so opening it from here would taint.
local _, ns = ...
local accent = ns.COLORS.accent

-- Private to UI/EditMode/: helpers and state the files of this folder share.
ns._EM = ns._EM or {}
local EM = ns._EM

-- Everything the editing session remembers, grid included. The db path still
-- says `grid` because that is where the first four keys were written and a
-- rename would drop every saved preference; `ghost` has lived here since long
-- before the rest joined it.
--
-- Falls back to a local table when called before the DB exists.
local EDIT_DEFAULTS = {
    show        = false,     -- draw the alignment grid
    snap        = true,      -- legacy grid-snap flag, now seeds snapTo
    size        = 32,        -- grid spacing
    ghost       = false,     -- see-through boxes
    snapTo      = "both",    -- both | elements | grid | none
    coords      = false,     -- X/Y readout on every box
    cursorLight = false,     -- a soft light following the cursor
    dimBg       = true,      -- darken the interface behind the boxes
    hoverBar    = false,     -- the toolbar fades until the mouse reaches it
}

local function fillEditDefaults(g)
    for k, v in pairs(EDIT_DEFAULTS) do
        if g[k] == nil then g[k] = v end
    end
    -- A profile written before the snap modes existed carries `snap` alone,
    -- and `snap` only ever gated the GRID: windows snapped to each other
    -- whatever it said. So its off state migrates to "elements", not to
    -- "none" -- mapping it to "none" would take away edge alignment that the
    -- player never switched off.
    if g._snapToSeeded == nil then
        g._snapToSeeded = true
        if g.snap == false then g.snapTo = "elements" end
    end
    return g
end

local function gridState()
    local p = ns.db and ns.db.profile
    if p then
        p.editmode      = p.editmode      or {}
        p.editmode.grid = p.editmode.grid or {}
        return fillEditDefaults(p.editmode.grid)
    end
    ns._editGridFallback = fillEditDefaults(ns._editGridFallback or {})
    return ns._editGridFallback
end
ns.EditState = gridState
EM.gridState = gridState

-- Which of the two snap kinds the current mode allows.
local function snapKinds(g)
    local mode = g.snapTo or "both"
    return (mode == "both" or mode == "elements"),   -- elements
           (mode == "both" or mode == "grid")        -- grid
end
EM.snapKinds = snapKinds

function ns:EditSnapXY(x, y, ratio)
    local g = gridState()
    local _, useGrid = snapKinds(g)
    if not useGrid then return x, y end
    local s = g.size or 32
    if s <= 0 then return x, y end
    -- Snap in UIParent units (where the grid is drawn), then convert back to frame-local units.
    ratio = ratio or 1
    if ratio == 0 then ratio = 1 end
    local function snap(v) return (math.floor((v * ratio) / s + 0.5) * s) / ratio end
    return snap(x), snap(y)
end

-- EM.dim and EM.toolbar are built in Toolbar.lua.
-- Assigned in later files, where the frames they read are in scope, and read
-- by the session refresh below: EM.layoutsShown (Layouts.lua) and
-- EM.refreshCoordText (Panel.lua).
local gridPool = {}

local function refreshGrid()
    local g = gridState()
    for _, t in ipairs(gridPool) do t:Hide() end
    if not EM.dim or not g.show then return end

    local accent = ns.COLORS.accent
    local w, h   = UIParent:GetWidth(), UIParent:GetHeight()
    if not w or not h or w <= 0 then return end
    local cx, cy = w / 2, h / 2
    local size   = g.size or 32
    if size < 4 then size = 4 end

    local idx = 0
    local function lineTex()
        idx = idx + 1
        local t = gridPool[idx]
        if not t then
            t = EM.dim:CreateTexture(nil, "ARTWORK")
            gridPool[idx] = t
        end
        t:ClearAllPoints()
        return t
    end
    local function vline(px, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetWidth(center and 2 or 1)
        t:SetPoint("TOP",    EM.dim, "TOPLEFT",    px, 0)
        t:SetPoint("BOTTOM", EM.dim, "BOTTOMLEFT", px, 0)
        t:Show()
    end
    local function hline(py, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetHeight(center and 2 or 1)
        t:SetPoint("LEFT",  EM.dim, "BOTTOMLEFT",  0, py)
        t:SetPoint("RIGHT", EM.dim, "BOTTOMRIGHT", 0, py)
        t:Show()
    end

    vline(cx, true)
    local x = cx + size; while x < w do vline(x, false); x = x + size end
    x = cx - size;       while x > 0 do vline(x, false); x = x - size end

    hline(cy, true)
    local y = cy + size; while y < h do hline(y, false); y = y + size end
    y = cy - size;       while y > 0 do hline(y, false); y = y - size end
end
ns.RefreshEditGrid = refreshGrid
EM.refreshGrid = refreshGrid

-- ---------------------------------------------------------------------------
-- The three session looks: how dark the interface behind the boxes goes, the
-- light that follows the cursor, and whether the toolbar waits for the mouse.
-- All three are settings, so each one is a function the options page can call.

local function refreshDim()
    if not (EM.dim and EM.dim.fill) then return end
    -- The frame keeps its mouse either way: a click on empty space is what
    -- deselects, and that has to work with the darkening turned off.
    local g = gridState()
    EM.dim.fill:SetColorTexture(0, 0, 0, g.dimBg and 0.35 or 0)
end
EM.refreshDim = refreshDim

local cursorLight

local function refreshCursorLight()
    if not EM.dim then return end
    local g = gridState()
    if not g.cursorLight then
        if cursorLight then cursorLight:Hide() end
        EM.dim:SetScript("OnUpdate", nil)
        return
    end
    if not cursorLight then
        cursorLight = EM.dim:CreateTexture(nil, "ARTWORK")
        cursorLight:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\textures\\soft-glow.tga")
        cursorLight:SetBlendMode("ADD")
        cursorLight:SetSize(420, 420)
    end
    local a = ns.COLORS.accent
    cursorLight:SetVertexColor(a.r, a.g, a.b, 0.16)
    cursorLight:Show()
    -- OnUpdate on `dim` and nowhere else: a hidden frame gets no OnUpdate, so
    -- this costs nothing once the session closes.
    EM.dim:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if not s or s == 0 then return end
        cursorLight:ClearAllPoints()
        cursorLight:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
end

local HOVER_BAR_ALPHA = 0.12

local function refreshHoverBar()
    if not EM.toolbar then return end
    local g = gridState()
    if not g.hoverBar then
        EM.toolbar:SetScript("OnUpdate", nil)
        EM.toolbar:SetAlpha(1)
        return
    end
    EM.toolbar:SetScript("OnUpdate", function(self, elapsed)
        self._hoverT = (self._hoverT or 0) + elapsed
        if self._hoverT < 0.1 then return end
        self._hoverT = 0
        -- The layouts panel is opened FROM the toolbar and sits away from it;
        -- fading the bar out from under an open panel reads as a bug.
        local near = self:IsMouseOver(12, -12, -12, 12) or (EM.layoutsShown and EM.layoutsShown())
        self:SetAlpha(near and 1 or HOVER_BAR_ALPHA)
    end)
    EM.toolbar:SetAlpha(EM.toolbar:IsMouseOver(12, -12, -12, 12) and 1 or HOVER_BAR_ALPHA)
end

-- Everything a setting can change about a running session, in one call. The
-- toolbar switches read the same keys, so they are pushed back in step -- a
-- widget built once keeps showing the value it was built with otherwise.
function ns:RefreshEditMode()
    refreshGrid()
    refreshDim()
    refreshCursorLight()
    refreshHoverBar()
    if EM.toolbar and EM.toolbar._switches then
        for _, w in ipairs(EM.toolbar._switches) do
            if w._refresh then w._refresh() end
        end
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

-- ns._selection holds all selected movers; ns._selectedMover is the primary one the panel edits.
ns._selection = ns._selection or {}

local function selIndex(m)
    for i, x in ipairs(ns._selection) do if x == m then return i end end
end
EM.selIndex = selIndex
function ns:IsSelected(m) return selIndex(m) ~= nil end

function ns:RefreshMoverStyles()
    -- See-through editing: the filled box plus its caption covers exactly the
    -- interface piece being aligned. Ghost drops the fill and the captions and
    -- keeps only the thin borders, so the boxes stay findable and grabbable.
    local ghost = gridState().ghost
    for _, m in ipairs(ns._movers) do
        local sel     = ns:IsSelected(m)
        local primary = (m == ns._selectedMover)
        local sc      = m.opts and m.opts.scope
        local editing = ns._moverEditGlobal or (sc and ns._moverEditScopes and ns._moverEditScopes[sc]) or false
        -- Free-move boxes outside edit mode stay grabbable but go quiet, else they read as a stuck overlay.
        local quiet = m:IsShown() and not editing
            and not (m.opts and m.opts.db and m.opts.db.unlocked)
        -- Ghost applies only WHILE EDITING: a box kept visible by a module's
        -- own unlock button outside edit mode keeps its normal look (the flag
        -- lives in the profile and would otherwise leak past the session).
        local ghosted = ghost and editing
        -- the cover-vs-handle decision depends on the editing state, so it is
        -- re-taken on the same edges that restyle the boxes
        if ns.RefreshMoverGeometry then ns:RefreshMoverGeometry(m) end
        if m.bg then
            if quiet then
                m.bg:SetColorTexture(0.05, 0.07, 0.10, 0.30)
            elseif ghosted then
                m.bg:SetColorTexture(accent.r, accent.g, accent.b, sel and 0.10 or 0)
            elseif sel then
                -- dark base with an accent wash: selection reads at a glance
                -- without giving up the solid cover look
                local lift = primary and 0.22 or 0.14
                m.bg:SetColorTexture(
                    0.05 + accent.r * lift,
                    0.07 + accent.g * lift,
                    0.10 + accent.b * lift, 0.95)
            else
                -- solid only in edit mode; an unlocked box outside it is a
                -- handle over live content (test previews, drop targets) and
                -- must stay see-through
                m.bg:SetColorTexture(0.05, 0.07, 0.10, editing and 0.92 or 0.45)
            end
        end
        if EM.refreshCoordText then EM.refreshCoordText(m) end
        if m.label then
            m.label:SetShown(not quiet and not ghosted)
            -- orange marks a docked window, the same signal the link overlay uses
            if m.key and ns.GetMoverLink and ns:GetMoverLink(m.key) then
                m.label:SetTextColor(1, 0.72, 0.35, 0.9)
            else
                m.label:SetTextColor(1, 1, 1, 0.85)
            end
        end
        if m.border and m.border.SetBackdropBorderColor then
            if m._rejectUntil and m._rejectUntil > GetTime() then
                -- the reject flash owns this border until it expires
            elseif quiet then
                m.border:SetBackdropBorderColor(accent.r * 0.6, accent.g * 0.6, accent.b * 0.6, 0.35)
            elseif primary then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 1)
            elseif sel then
                m.border:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.85)
            else
                m.border:SetBackdropBorderColor(accent.r * 0.7, accent.g * 0.7, accent.b * 0.7, 0.8)
            end
        end
    end
end
