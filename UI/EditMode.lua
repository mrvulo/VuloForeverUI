-- Self-driven Edit Mode HUD: Blizzard's own is protected, so opening it from here would taint.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local accent = ns.COLORS.accent

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

-- Which of the two snap kinds the current mode allows.
local function snapKinds(g)
    local mode = g.snapTo or "both"
    return (mode == "both" or mode == "elements"),   -- elements
           (mode == "both" or mode == "grid")        -- grid
end

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

local dim, toolbar, built
-- Assigned further down, where the frames they read are in scope. Declared
-- here so the session refresh below can call them.
local layoutsShown, refreshCoordText
local gridPool = {}

local function refreshGrid()
    local g = gridState()
    for _, t in ipairs(gridPool) do t:Hide() end
    if not dim or not g.show then return end

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
            t = dim:CreateTexture(nil, "ARTWORK")
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
        t:SetPoint("TOP",    dim, "TOPLEFT",    px, 0)
        t:SetPoint("BOTTOM", dim, "BOTTOMLEFT", px, 0)
        t:Show()
    end
    local function hline(py, center)
        local t = lineTex()
        if center then t:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
        else           t:SetColorTexture(1, 1, 1, 0.07) end
        t:SetHeight(center and 2 or 1)
        t:SetPoint("LEFT",  dim, "BOTTOMLEFT",  0, py)
        t:SetPoint("RIGHT", dim, "BOTTOMRIGHT", 0, py)
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

-- ---------------------------------------------------------------------------
-- The three session looks: how dark the interface behind the boxes goes, the
-- light that follows the cursor, and whether the toolbar waits for the mouse.
-- All three are settings, so each one is a function the options page can call.

local function refreshDim()
    if not (dim and dim.fill) then return end
    -- The frame keeps its mouse either way: a click on empty space is what
    -- deselects, and that has to work with the darkening turned off.
    local g = gridState()
    dim.fill:SetColorTexture(0, 0, 0, g.dimBg and 0.35 or 0)
end

local cursorLight

local function refreshCursorLight()
    if not dim then return end
    local g = gridState()
    if not g.cursorLight then
        if cursorLight then cursorLight:Hide() end
        dim:SetScript("OnUpdate", nil)
        return
    end
    if not cursorLight then
        cursorLight = dim:CreateTexture(nil, "ARTWORK")
        cursorLight:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\textures\\soft-glow.tga")
        cursorLight:SetBlendMode("ADD")
        cursorLight:SetSize(420, 420)
    end
    local a = ns.COLORS.accent
    cursorLight:SetVertexColor(a.r, a.g, a.b, 0.16)
    cursorLight:Show()
    -- OnUpdate on `dim` and nowhere else: a hidden frame gets no OnUpdate, so
    -- this costs nothing once the session closes.
    dim:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if not s or s == 0 then return end
        cursorLight:ClearAllPoints()
        cursorLight:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
    end)
end

local HOVER_BAR_ALPHA = 0.12

local function refreshHoverBar()
    if not toolbar then return end
    local g = gridState()
    if not g.hoverBar then
        toolbar:SetScript("OnUpdate", nil)
        toolbar:SetAlpha(1)
        return
    end
    toolbar:SetScript("OnUpdate", function(self, elapsed)
        self._hoverT = (self._hoverT or 0) + elapsed
        if self._hoverT < 0.1 then return end
        self._hoverT = 0
        -- The layouts panel is opened FROM the toolbar and sits away from it;
        -- fading the bar out from under an open panel reads as a bug.
        local near = self:IsMouseOver(12, -12, -12, 12) or (layoutsShown and layoutsShown())
        self:SetAlpha(near and 1 or HOVER_BAR_ALPHA)
    end)
    toolbar:SetAlpha(toolbar:IsMouseOver(12, -12, -12, 12) and 1 or HOVER_BAR_ALPHA)
end

-- Everything a setting can change about a running session, in one call. The
-- toolbar switches read the same keys, so they are pushed back in step -- a
-- widget built once keeps showing the value it was built with otherwise.
function ns:RefreshEditMode()
    refreshGrid()
    refreshDim()
    refreshCursorLight()
    refreshHoverBar()
    if toolbar and toolbar._switches then
        for _, w in ipairs(toolbar._switches) do
            if w._refresh then w._refresh() end
        end
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

local function build()
    if built then return end
    built = true
    local accent = ns.COLORS.accent

    -- Strata stays below the movers (HIGH) so the boxes remain clickable.
    dim = CreateFrame("Frame", "VFUIEditDim", UIParent)
    dim:SetAllPoints(UIParent)
    dim:SetFrameStrata("MEDIUM")
    dim:EnableMouse(true)
    dim:SetScript("OnMouseDown", function()
        if ns.IsAnchorPicking and ns:IsAnchorPicking() then
            if ns.CancelAnchorPick then ns:CancelAnchorPick() end
            return
        end
        if ns.DeselectMover then ns:DeselectMover() end
    end)
    local fill = dim:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(dim)
    fill:SetColorTexture(0, 0, 0, 0.35)
    dim.fill = fill
    dim:Hide()

    -- DIALOG keeps the toolbar above the movers (HIGH) so its controls stay clickable.
    toolbar = CreateFrame("Frame", "VFUIEditToolbar", UIParent)
    toolbar:SetSize(1240, 64)
    toolbar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    toolbar:SetFrameStrata("DIALOG")
    toolbar:SetClampedToScreen(true)
    toolbar:EnableMouse(true)
    toolbar:SetMovable(true)
    toolbar:RegisterForDrag("LeftButton")
    toolbar:SetScript("OnDragStart", toolbar.StartMoving)
    toolbar:SetScript("OnDragStop",  toolbar.StopMovingOrSizing)
    UI:StyleBackdrop(toolbar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(toolbar)

    local strip = toolbar:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  toolbar, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 13, "")
    title:SetPoint("TOP", toolbar, "TOP", 0, -8)
    title:SetText(L["EDIT MODE"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local ROWY = -32

    -- Changes already live in the DB, so this is a checkpoint rather than a
    -- write: it re-bases the snapshot so Discard returns here, not to the state
    -- the session opened in, and lets you keep editing.
    local saveBtn = UI:CreateButton(toolbar, {
        label   = L["Save"],
        primary = true,
        width   = 96,
        tooltip = L["Keep the current arrangement and carry on editing. Discard then returns to this point instead of to how things looked when Edit Mode opened."],
        onClick = function()
            if ns.SnapshotEditState then
                ns:ClearEditSnapshot()
                ns:SnapshotEditState()
            end
            ns:Print(L["Window positions saved."])
        end,
    })
    saveBtn:SetPoint("TOPLEFT", toolbar, "TOPLEFT", 14, ROWY)

    local exitBtn = UI:CreateButton(toolbar, {
        label   = L["Exit"],
        width   = 90,
        tooltip = L["Close Edit Mode and lock all windows. Your changes stay applied."],
        onClick = function() ns:SetEditMode(false) end,
    })
    exitBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

    local discardBtn = UI:CreateButton(toolbar, {
        label   = L["Discard"],
        width   = 96,
        tooltip = L["Discard changes and revert every window to the last save point, or to how it was when Edit Mode opened."],
        onClick = function() StaticPopup_Show("VFUI_EDIT_DISCARD") end,
    })
    discardBtn:SetPoint("LEFT", exitBtn, "RIGHT", 8, 0)

    local gridTog = UI:CreateToggle(toolbar, {
        label   = L["Grid"],
        tooltip = L["Show an alignment grid."],
        get     = function() return gridState().show end,
        set     = function(_, v) gridState().show = v; refreshGrid() end,
    })
    gridTog:SetSize(108, 24)
    gridTog:SetPoint("LEFT", discardBtn, "RIGHT", 16, 0)

    -- This switch keeps the meaning it always had -- the GRID half of snapping
    -- -- and leaves the element half exactly as the global settings left it.
    -- Flipping it off and on again has to give the mode back unchanged.
    local GRID_OFF = { both = "elements", grid = "none" }
    local GRID_ON  = { elements = "both", none = "grid" }
    local snapTog = UI:CreateToggle(toolbar, {
        label   = L["Snap"],
        tooltip = L["Snap windows to the grid while dragging. Snapping to other windows is a separate setting, in the global settings."],
        get     = function() local _, useGrid = snapKinds(gridState()); return useGrid end,
        set     = function(_, v)
            local g = gridState()
            local mode = g.snapTo or "both"
            g.snapTo = (v and GRID_ON[mode] or GRID_OFF[mode]) or mode
        end,
    })
    snapTog:SetSize(140, 24)
    snapTog:SetPoint("LEFT", gridTog, "RIGHT", 14, 0)

    local cap = toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 11)
    cap:SetText(L["Size"])
    cap:SetTextColor(0.65, 0.65, 0.70)
    cap:SetPoint("LEFT", snapTog, "RIGHT", 16, 0)

    -- width is the TRACK only: the minus button, value and plus hang off its
    -- right edge for a further ~84px that no anchor accounts for, so the
    -- buttons on the right have to be placed clear of track width + 84.
    local sizeSlider = UI:CreateSlider(toolbar, {
        label = "",
        min   = 8, max = 128, step = 4,
        width = 70,
        get   = function() return gridState().size end,
        set   = function(_, v) gridState().size = v; refreshGrid() end,
    })
    sizeSlider:SetPoint("LEFT", cap, "RIGHT", 8, 0)


    local resetBtn = UI:CreateButton(toolbar, {
        label   = L["Reset"],
        width   = 120,
        tooltip = L["Reset all VuloUI window positions to the screen centre."],
        onClick = function() StaticPopup_Show("VFUI_EDIT_RESET") end,
    })
    resetBtn:SetPoint("TOPRIGHT", toolbar, "TOPRIGHT", -16, ROWY)

    local layoutsBtn = UI:CreateButton(toolbar, {
        label   = L["Layouts"],
        width   = 110,
        tooltip = L["Save, load, export and import named window layouts."],
        onClick = function() if ns.ToggleLayouts then ns:ToggleLayouts() end end,
    })
    layoutsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)

    -- Anchored RIGHT, off the button group: the left-hand chain ends at the
    -- size slider whose caption width varies by language — a left anchor put
    -- this switch on top of the Layouts button in German (user screenshot).
    local ghostTog = UI:CreateToggle(toolbar, {
        label   = L["See-through"],
        tooltip = L["Hide the box fill and labels while editing, so you can see the interface you are aligning. The thin borders stay."],
        get     = function() return gridState().ghost end,
        set     = function(_, v) gridState().ghost = v; ns:RefreshMoverStyles() end,
    })
    ghostTog:SetSize(140, 24)
    ghostTog:SetPoint("RIGHT", layoutsBtn, "LEFT", -18, 0)

    -- The same keys are editable in the global settings; RefreshEditMode
    -- pushes a change made there back into these switches. The size slider is
    -- not among them -- it has no refresh hook, so a grid size changed from
    -- the options page redraws the grid but leaves this slider on its old
    -- number until the session is reopened.
    toolbar._switches = { gridTog, snapTog, ghostTog }
end

function ns:IsEditModeActive()
    return ns._editActive and true or false
end

-- Lets modules with their own positioner (not a CreateMover box) follow the same toggle.
ns._editHooks = ns._editHooks or {}
function ns:RegisterEditModeHook(fn)
    if type(fn) == "function" then ns._editHooks[#ns._editHooks + 1] = fn end
end

-- opts.keepSnapshot: a combat auto-suspend closes edit mode but must NOT clear the
-- discard snapshot, so a later Discard still reverts to the original session layout.
function ns:SetEditMode(state, opts)
    state = state and true or false
    if state and ns:InCombat() then
        ns:Print(L["Not possible in combat."])
        return
    end
    build()
    ns._editActive = state
    if state then
        -- a drag left over from a session that ended abnormally must not resume
        if ns.AbortMoverDrag then ns:AbortMoverDrag() end
        if not ns._editSnapshot and ns.SnapshotEditState then ns:SnapshotEditState() end
        if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
        -- The options window sits exactly on top of the boxes it just
        -- unlocked; entering the editor closes it, the same way the client's
        -- own editor closes the settings panel (user report with screenshot,
        -- 09.08.2026). Not reopened on exit: whoever finishes editing is
        -- looking at their interface, not at the options.
        local main = ns.UI and ns.UI.mainFrame
        if main and main.IsShown and main:IsShown() then main:Hide() end
        dim:Show()
        toolbar:Show()
        ns:RefreshEditMode()
    else
        -- Abort an in-flight drag (combat auto-exit can fire mid-drag) or the frame sticks to the cursor.
        if ns.AbortMoverDrag then ns:AbortMoverDrag() end
        if ns.CancelAnchorPick then ns:CancelAnchorPick() end
        if ns.DeselectMover then ns:DeselectMover() end
        if ns.HideLayouts then ns:HideLayouts() end
        ns._draggingMover = nil
        if ns._hideGuides then ns._hideGuides() end
        if ns._hideLinks  then ns._hideLinks()  end
        dim:Hide()
        dim:SetScript("OnUpdate", nil)
        toolbar:Hide()
        -- A faded toolbar must not come back faded next session before the
        -- first OnUpdate tick, and the script has nothing to do while hidden.
        toolbar:SetScript("OnUpdate", nil)
        toolbar:SetAlpha(1)
        if not (opts and opts.keepSnapshot) and ns.ClearEditSnapshot then ns:ClearEditSnapshot() end
    end
    ns:SetMoversEditMode(state)
    -- Restyle on both edges: leaving must drop free-move boxes back to their quiet look.
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    for _, fn in ipairs(ns._editHooks) do pcall(fn, state) end
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_EDIT_RESET"] = {
    text         = L["Reset all VuloUI window positions to the screen centre?"],
    button1      = YES,
    button2      = NO,
    OnAccept     = function() if ns.ResetAllMovers then ns:ResetAllMovers() end end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["VFUI_EDIT_DISCARD"] = {
    text         = L["Discard all changes made since the last save?"],
    button1      = YES,
    button2      = NO,
    OnAccept     = function()
        if ns.RestoreEditState then ns:RestoreEditState() end
        ns:SetEditMode(false)
    end,
    timeout      = 0,
    whileDead    = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
end)

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED")
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if ns:IsEditModeActive() then
            ns._editResume = true
            ns:SetEditMode(false, { keepSnapshot = true })
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns._editResume then
            ns._editResume = false
            ns:SetEditMode(true)
        end
    end
end)

local disp = CreateFrame("Frame")
disp:RegisterEvent("DISPLAY_SIZE_CHANGED")
disp:RegisterEvent("UI_SCALE_CHANGED")
disp:SetScript("OnEvent", function()
    if ns:IsEditModeActive() then refreshGrid() end
end)

ns:RegisterSlash({ key = "EDITMODE", commands = { "/vedit" },
    desc = "Open Edit Mode and move frames around.",
})
ns.Slash.EDITMODE = function()
    ns:SetEditMode(not ns:IsEditModeActive())
end

local function snapVal(v, size)
    if not size or size <= 0 then return v end
    return math.floor(v / size + 0.5) * size
end

local function cleanLabel(s)
    s = tostring(s or "Frame")
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- ns._selection holds all selected movers; ns._selectedMover is the primary one the panel edits.
ns._selection = ns._selection or {}

local function selIndex(m)
    for i, x in ipairs(ns._selection) do if x == m then return i end end
end
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
        if refreshCoordText then refreshCoordText(m) end
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
-- keeps it live frame by frame (Core/Mover.lua); the setting only decides
-- whether it stays on the box for the whole session instead of retiring on the
-- drop. A second font string of our own would just disagree with that one.
refreshCoordText = function(m)
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
    cfs:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(0.7, 0.7, 0.75) end)
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
    optIcon:SetVertexColor(0.7, 0.7, 0.75)
    opt:SetScript("OnEnter", function(self)
        optIcon:SetVertexColor(accent.r, accent.g, accent.b)
        UI:ShowTooltip(self, { title = L["Open this element's settings"] })
    end)
    opt:SetScript("OnLeave", function()
        optIcon:SetVertexColor(0.7, 0.7, 0.75)
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
    sep:SetColorTexture(1, 1, 1, 0.07)

    local cap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -46)
    cap:SetText(L["POSITION"])
    cap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.scaleCap:SetTextColor(0.55, 0.55, 0.62)
    panel.scaleSlider = UI:CreateSlider(panel, {
        label = "", min = 0.5, max = 2.0, step = 0.05, width = 150,
        get = function() local m = ns._selectedMover; return (m and m.opts.db.scale) or 1 end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:MoverSetScale(m, v) end end,
    })

    panel.anchorCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.anchorCap, 10)
    panel.anchorCap:SetText(L["ANCHOR"])
    panel.anchorCap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.linkCap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.sideCap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.gapCap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.widthCap:SetTextColor(0.55, 0.55, 0.62)

    panel.heightCap = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(panel.heightCap, 10)
    panel.heightCap:SetText(L["HEIGHT LIKE"])
    panel.heightCap:SetTextColor(0.55, 0.55, 0.62)

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
    panel.freeCap:SetTextColor(0.55, 0.55, 0.62)

    panel.freeToggle = UI:CreateToggle(panel, {
        label   = "",
        tooltip = L["Leave this window unlocked so you can still drag it after closing Edit Mode. Stays unlocked through /reload."],
        get = function() local m = ns._selectedMover; return m and ns:IsMoverFreeMove(m) end,
        set = function(_, v) local m = ns._selectedMover; if m then ns:SetMoverFreeMove(m, v) end end,
    })
    panel.freeToggle:SetSize(44, 22)

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
    hint:SetTextColor(0.55, 0.55, 0.62)
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

-- Click-to-pick anchoring: BeginAnchorPick arms it from the panel, then the next
-- mover the user clicks becomes this frame's anchor target (see Core/Mover.lua handlers).
local pickHint
function ns:IsAnchorPicking() return ns._anchorPick ~= nil end

-- The screen visibly darkens while picking, so it reads as a distinct mode.
-- Picking an anchor target dims harder, so the box you are about to click
-- stands out. Letting go returns to whatever the DARKENING SETTING says --
-- restoring a fixed 0.35 would switch the darkening back on behind the back of
-- a player who turned it off.
local function setPickDim(on)
    if not (dim and dim.fill) then return end
    if on then
        dim.fill:SetColorTexture(0, 0, 0, 0.6)
    else
        refreshDim()
    end
end

function ns:BeginAnchorPick(child)
    if not (child and child.key and ns:IsEditModeActive()) then return end
    ns._anchorPick = child
    setPickDim(true)
    if not pickHint and dim then
        pickHint = dim:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        pickHint:SetPoint("TOP", UIParent, "TOP", 0, -230)
        pickHint:SetTextColor(accent.r, accent.g, accent.b)
    end
    if pickHint then
        pickHint:SetText(L["Click a window to anchor it (right-click to cancel)."])
        pickHint:Show()
    end
end

function ns:CancelAnchorPick()
    ns._anchorPick = nil
    setPickDim(false)
    if pickHint then pickHint:Hide() end
end

function ns:AnchorPickPick(targetMover)
    local child = ns._anchorPick
    ns:CancelAnchorPick()
    if not (child and targetMover) then return end
    if targetMover == child or not targetMover.key then return end
    if ns:SetMoverLink(child, targetMover.key) then
        ns:OnMoverRepositioned(targetMover)   -- settle the child onto its new anchor
    else
        ns:FlashMoverReject(targetMover, L["Not possible - that would create a loop."])
    end
    if ns._selectedMover == child then ns:RelayoutEditPanel() end
end

-- Only the leader snaps; followers keep their relative offset so the group stays rigid.
function ns:BeginGroupDrag(leader)
    ns._groupDrag = nil
    if #ns._selection <= 1 or not (leader and ns:IsSelected(leader) and leader.target) then return end
    -- Captures are in each owning frame's local space, or a scaled follower teleports on the first tick.
    local followers = {}
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.target then
            local x, y = ns:GetCenterOffsets(m.target)
            if x and y then
                followers[#followers + 1] = { mover = m, x = x, y = y }
            end
        end
    end
    if #followers == 0 then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    ns._groupDrag = { lx = lx, ly = ly, followers = followers }
end

function ns:UpdateGroupDrag()
    local gd = ns._groupDrag
    local leader = ns._draggingMover
    if not (gd and leader and leader.target) then return end
    local lx, ly = ns:GetCenterOffsets(leader.target)
    if not lx then return end
    local dx, dy = lx - gd.lx, ly - gd.ly
    local lscale = leader.target:GetEffectiveScale() or 1
    for _, f in ipairs(gd.followers) do
        local t = f.mover.target
        -- Convert the delta into this follower's space so a scaled frame tracks the leader 1:1 on screen.
        local conv = lscale / (t:GetEffectiveScale() or 1)
        t:ClearAllPoints()
        t:SetPoint("CENTER", UIParent, "CENTER", f.x + dx * conv, f.y + dy * conv)
    end
end

-- sdx/sdy is the snap correction the leader took, reapplied so the group keeps its arrangement.
function ns:EndGroupDrag(sdx, sdy)
    local gd = ns._groupDrag
    ns._groupDrag = nil
    if not gd then return end
    sdx, sdy = sdx or 0, sdy or 0
    for _, f in ipairs(gd.followers) do
        local x, y = ns:GetCenterOffsets(f.mover.target)
        if x and y then
            ns:MoverSetCenter(f.mover, x + sdx, y + sdy)
        end
    end
end

function ns:NudgeGroupFollowers(leader, dx, dy)
    if #ns._selection <= 1 or not ns:IsSelected(leader) then return end
    for _, m in ipairs(ns._selection) do
        if m ~= leader and m.opts and m.opts.db then
            m.opts.db.x = (m.opts.db.x or 0) + dx
            m.opts.db.y = (m.opts.db.y or 0) + dy
            ns:ApplyMover(m)
        end
    end
end

function ns:OnMoverMoved(mover)
    if mover == ns._selectedMover then refreshPanel() end
    if refreshCoordText then refreshCoordText(mover) end
end

local guideFrame, guidePool = nil, {}
local function ensureGuideFrame()
    if guideFrame then return end
    guideFrame = CreateFrame("Frame", "VFUIEditGuides", UIParent)
    guideFrame:SetAllPoints(UIParent)
    guideFrame:SetFrameStrata("DIALOG")   -- above the mover boxes (HIGH)
    guideFrame:EnableMouse(false)
end
local measurePool = {}
local function hideMeasures()
    for _, t in ipairs(measurePool) do t:Hide() end
end
local function hideGuides()
    for _, t in ipairs(guidePool) do t:Hide() end
    hideMeasures()
end
ns._hideGuides = hideGuides
local function drawGuides(gx, gy, persist)
    ensureGuideFrame()
    hideGuides()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local i = 0
    local function gtex()
        i = i + 1
        local t = guidePool[i]
        if not t then t = guideFrame:CreateTexture(nil, "OVERLAY"); guidePool[i] = t end
        t:ClearAllPoints()
        t:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
        return t
    end
    if gx then
        local t = gtex(); t:SetWidth(2)
        local sx = w / 2 + gx
        t:SetPoint("TOP",    guideFrame, "TOPLEFT",    sx, 0)
        t:SetPoint("BOTTOM", guideFrame, "BOTTOMLEFT", sx, 0)
        t:Show()
    end
    if gy then
        local t = gtex(); t:SetHeight(2)
        local sy = h / 2 + gy
        t:SetPoint("LEFT",  guideFrame, "BOTTOMLEFT",  0, sy)
        t:SetPoint("RIGHT", guideFrame, "BOTTOMRIGHT", 0, sy)
        t:Show()
    end
    if not persist and (gx or gy) and C_Timer and C_Timer.After then
        C_Timer.After(0.5, hideGuides)
    end
end

-- frame centre + half-extents as offsets from the screen centre, in UIParent units
local function boxUI(frame)
    local cx, cy = ns:GetCenterOffsets(frame)
    if not cx then return nil end
    local r = ns.GetScaleRatio and ns:GetScaleRatio(frame) or 1
    return cx * r, cy * r,
           (frame:GetWidth()  or 0) / 2 * r,
           (frame:GetHeight() or 0) / 2 * r
end

-- Distance readout: for each active alignment guide, label the edge-to-edge gap
-- between the dragged frame and the partner frame it lined up with.
local function drawMeasures(mover, moverX, moverY)
    hideMeasures()
    if not (mover and mover.target) then return end
    if not (moverX or moverY) then return end
    ensureGuideFrame()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local acx, acy, ahw, ahh = boxUI(mover.target)
    if not acx then return end
    local n = 0
    local function mtex()
        n = n + 1
        local t = measurePool[n]
        if not t then
            t = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            UI.Font(t, 11)
            measurePool[n] = t
        end
        t:ClearAllPoints()
        t:SetTextColor(accent.r, accent.g, accent.b)
        return t
    end
    -- vertical guide (shared X) -> vertical gap to the partner
    if moverX and moverX.target then
        local bcx, bcy, _, bhh = boxUI(moverX.target)
        if bcx then
            local gap = math.abs(acy - bcy) - (ahh + bhh)
            local t = mtex()
            t:SetText(tostring(math.floor(gap + 0.5)))
            t:SetPoint("CENTER", guideFrame, "BOTTOMLEFT", w / 2 + acx + 14, h / 2 + (acy + bcy) / 2)
            t:Show()
        end
    end
    -- horizontal guide (shared Y) -> horizontal gap to the partner
    if moverY and moverY.target then
        local bcx, _, bhw = boxUI(moverY.target)
        if bcx then
            local gap = math.abs(acx - bcx) - (ahw + bhw)
            local t = mtex()
            t:SetText(tostring(math.floor(gap + 0.5)))
            t:SetPoint("CENTER", guideFrame, "BOTTOMLEFT", w / 2 + (acx + bcx) / 2, h / 2 + acy + 14)
            t:Show()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Rejection feedback: a refused action (loop, self-anchor) flashes the offending
-- box red and floats the reason at the cursor. A chat line is too easy to miss
-- while you are looking at the window you just clicked.

local rejectDriver, rejectHint

local function ensureReject()
    if rejectDriver then return end
    rejectDriver = CreateFrame("Frame", nil, UIParent)
    rejectDriver:Hide()
    rejectHint = rejectDriver:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(rejectHint, 12)
    rejectHint:SetTextColor(1, 0.35, 0.3)
    rejectDriver:SetFrameStrata("TOOLTIP")
    rejectDriver:SetAllPoints(UIParent)
end

function ns:FlashMoverReject(mover, text)
    ensureReject()
    local until_ = GetTime() + 2.0
    if mover and mover.border and mover.border.SetBackdropBorderColor then
        mover._rejectUntil = until_
    end
    rejectHint:SetText(text or "")
    rejectDriver:Show()
    rejectDriver:SetScript("OnUpdate", function(self)
        local left = until_ - GetTime()
        if left <= 0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if mover then mover._rejectUntil = nil end
            if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
            return
        end
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if cx and s and s > 0 then
            rejectHint:ClearAllPoints()
            rejectHint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT",
                cx / s + 18, cy / s + 18)
        end
        rejectHint:SetAlpha(math.min(1, left / 0.6))
        if mover and mover.border and mover.border.SetBackdropBorderColor then
            local p = 0.5 + 0.5 * math.abs(math.sin(GetTime() * 10))
            mover.border:SetBackdropBorderColor(1, 0.2, 0.15, p)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Anchor connector lines: every window pinned to another draws a line to it,
-- with a pulse travelling child -> parent so the direction of the link is
-- obvious. Only drawn for windows you are touching, or the screen turns into a
-- spider web the moment more than a couple of links exist.

local linkFrame, linePool, dotPool = nil, {}, {}
local LINK_CYCLE = 2.0    -- seconds per pulse
local LINK_SWEEP = 0.6    -- share of the cycle the pulse is actually moving

local function ensureLinkFrame()
    if linkFrame then return end
    linkFrame = CreateFrame("Frame", "VFUIEditLinks", UIParent)
    linkFrame:SetAllPoints(UIParent)
    linkFrame:SetFrameStrata("MEDIUM")   -- above the dim, below the mover boxes
    linkFrame:SetFrameLevel(20)
    linkFrame:EnableMouse(false)
end

-- frame centre in UIParent units, measured from the screen's bottom-left
local function uiCenter(f)
    if not (f and f.GetCenter) then return nil end
    local cx, cy = f:GetCenter()
    if not cx then return nil end
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then return nil end
    local s = (f:GetEffectiveScale() or 1) / us
    return cx * s, cy * s
end

local function hideLinks()
    for _, l in ipairs(linePool) do l:Hide() end
    for _, d in ipairs(dotPool) do d:Hide() end
end

local function drawLinks()
    ensureLinkFrame()
    hideLinks()
    if not ns:IsEditModeActive() then return end
    local now  = GetTime()
    local used = 0
    for _, child in ipairs(ns._movers) do
        local link = child.key and ns:GetMoverLink(child.key)
        if link and child:IsShown() then
            local parent = ns:GetMoverByKey(link.to)
            if parent and parent.target and parent:IsShown() then
                local touched = child == ns._activeMover or parent == ns._activeMover
                    or child == ns._draggingMover or parent == ns._draggingMover
                    or ns:IsSelected(child) or ns:IsSelected(parent)
                local cx, cy = uiCenter(child.target)
                local px, py = uiCenter(parent.target)
                if touched and cx and px then
                    used = used + 1
                    local line = linePool[used]
                    if not line then
                        line = linkFrame:CreateLine(nil, "ARTWORK")
                        line:SetThickness(2)
                        linePool[used] = line
                    end
                    line:ClearAllPoints()
                    line:SetStartPoint("CENTER", child.target)
                    line:SetEndPoint("CENTER", parent.target)
                    line:SetColorTexture(accent.r, accent.g, accent.b, 0.55)
                    line:Show()

                    local dot = dotPool[used]
                    if not dot then
                        dot = linkFrame:CreateTexture(nil, "OVERLAY")
                        dot:SetSize(7, 7)
                        dot:SetBlendMode("ADD")
                        dotPool[used] = dot
                    end
                    -- ease the pulse across the line, then rest for the remainder
                    local phase = (now % LINK_CYCLE) / LINK_CYCLE
                    if phase <= LINK_SWEEP then
                        local t = phase / LINK_SWEEP
                        t = t * t * (3 - 2 * t)          -- smoothstep
                        local a = math.min(1, math.min(t, 1 - t) * 6)
                        dot:SetColorTexture(accent.r, accent.g, accent.b, 0.9 * a)
                        dot:ClearAllPoints()
                        dot:SetPoint("CENTER", linkFrame, "BOTTOMLEFT",
                            cx + (px - cx) * t, cy + (py - cy) * t)
                        dot:Show()
                    end
                end
            end
        end
    end
end
ns._hideLinks = hideLinks

local MAG_THRESH = 12

-- Math runs in UIParent units (where guides are drawn); returned dx/dy convert back to frame-local, lineX/lineY stay UI-space.
-- Scratch buffers, reused across calls. This runs EVERY FRAME for as long as a
-- window is being dragged, and it used to build six fresh tables per other
-- mover plus two feature tables and a closure -- roughly 300 short-lived tables
-- per frame at 50 windows, in a Lua that collects incrementally, precisely
-- while the user is judging whether the drag feels smooth. Values and lines are
-- kept in two parallel flat arrays with an explicit count, so nothing is
-- allocated after the first drag warms them up.
local _xv, _xm, _yv, _ym = {}, {}, {}, {}
local _feat = {}

local function bestLine(nFeat, vals, owners, n)
    local bd, bl, bm
    for i = 1, nFeat do
        local f = _feat[i]
        for j = 1, n do
            local d = vals[j] - f
            if math.abs(d) <= MAG_THRESH and (not bd or math.abs(d) < math.abs(bd)) then
                bd, bl, bm = d, vals[j], owners[j]
            end
        end
    end
    return bd, bl, bm
end

local function computeSnap(mover, x, y)
    local target = mover.target
    if not target then return end
    local r = ns.GetScaleRatio and ns:GetScaleRatio(target) or 1
    local xu, yu = x * r, y * r
    local hw = (target:GetWidth()  or 0) / 2 * r
    local hh = (target:GetHeight() or 0) / 2 * r

    -- each candidate line carries its owning mover (nil = the screen-centre line)
    _xv[1], _xm[1] = 0, nil
    _yv[1], _ym[1] = 0, nil
    local nx, ny = 1, 1
    for _, o in ipairs(ns._movers) do
        if o ~= mover and o.target and o:IsShown() then
            local ox, oy = ns:GetCenterOffsets(o.target)
            if ox and oy then
                local orr = ns.GetScaleRatio and ns:GetScaleRatio(o.target) or 1
                local ocx, ocy = ox * orr, oy * orr
                local ohw = (o.target:GetWidth()  or 0) / 2 * orr
                local ohh = (o.target:GetHeight() or 0) / 2 * orr
                _xv[nx + 1], _xm[nx + 1] = ocx,       o
                _xv[nx + 2], _xm[nx + 2] = ocx - ohw, o
                _xv[nx + 3], _xm[nx + 3] = ocx + ohw, o
                nx = nx + 3
                _yv[ny + 1], _ym[ny + 1] = ocy,       o
                _yv[ny + 2], _ym[ny + 2] = ocy - ohh, o
                _yv[ny + 3], _ym[ny + 3] = ocy + ohh, o
                ny = ny + 3
            end
        end
    end

    _feat[1], _feat[2], _feat[3] = xu - hw, xu, xu + hw
    local dx, lineX, moverX = bestLine(3, _xv, _xm, nx)
    _feat[1], _feat[2], _feat[3] = yu - hh, yu, yu + hh
    local dy, lineY, moverY = bestLine(3, _yv, _ym, ny)
    if dx then dx = dx / r end
    if dy then dy = dy / r end
    return dx, lineX, dy, lineY, moverX, moverY
end

function ns:EditResolveDrop(mover, x, y)
    local g = gridState()
    local useElements, useGrid = snapKinds(g)
    local t = mover.target
    local r = (ns.GetScaleRatio and t) and ns:GetScaleRatio(t) or 1
    local dx, lineX, dy, lineY
    if useElements then dx, lineX, dy, lineY = computeSnap(mover, x, y) end
    if dx then x = x + dx elseif useGrid then x = snapVal(x * r, g.size) / r end
    if dy then y = y + dy elseif useGrid then y = snapVal(y * r, g.size) / r end
    -- Pixel grid is the last resort only: an edge snap already sits exactly on
    -- the neighbour's edge and a grid snap on its line, so re-rounding either
    -- would nudge it a pixel off the thing it was just aligned to.
    if t then
        if not dx and not useGrid then x = ns:PixelSnapCenter(x, t:GetWidth() or 0, t) end
        if not dy and not useGrid then y = ns:PixelSnapCenter(y, t:GetHeight() or 0, t) end
    end
    drawGuides(dx and lineX or nil, dy and lineY or nil)
    return x, y
end

-- The box being snapped AGAINST lights up with a white pulse, so the guide
-- line reads as "aligned to THAT window" instead of a free-floating stripe.
-- RefreshMoverStyles restores whatever border this painted over, both when the
-- partner changes mid-drag and when the drag ends.
local lastPartnerX, lastPartnerY

local function tintPartner(p, a)
    if p and p.border and p.border.SetBackdropBorderColor
       and not (p._rejectUntil and p._rejectUntil > GetTime()) then
        p.border:SetBackdropBorderColor(1, 1, 1, a)
    end
end

-- Purely visual preview; the actual snap still happens on drop.
local liveGuideDriver = CreateFrame("Frame")
liveGuideDriver:SetScript("OnUpdate", function()
    local m = ns._draggingMover
    if not (m and m.target and ns:IsEditModeActive()) then
        if lastPartnerX or lastPartnerY then
            lastPartnerX, lastPartnerY = nil, nil
            ns:RefreshMoverStyles()
        end
        return
    end
    if ns._groupDrag then ns:UpdateGroupDrag() end
    local lx, ly = ns:GetCenterOffsets(m.target)
    if not lx then return end
    local dx, lineX, dy, lineY, moverX, moverY = computeSnap(m, lx, ly)
    drawGuides(dx and lineX or nil, dy and lineY or nil, true)
    drawMeasures(m, dx and moverX or nil, dy and moverY or nil)

    local px = dx and moverX or nil
    local py = dy and moverY or nil
    if px ~= lastPartnerX or py ~= lastPartnerY then
        lastPartnerX, lastPartnerY = px, py
        ns:RefreshMoverStyles()
    end
    if px or py then
        local a = 0.55 + 0.45 * math.abs(math.sin(GetTime() * 5))
        tintPartner(px, a)
        if py ~= px then tintPartner(py, a) end
    end
end)

local cycleHint, altWasDown
local function ensureCycleHint()
    ensureGuideFrame()
    if cycleHint then return end
    cycleHint = guideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(cycleHint, 12)
    cycleHint:SetTextColor(accent.r, accent.g, accent.b)
    cycleHint:Hide()
end
local function updateCycle()
    if not ns:IsEditModeActive() then
        if cycleHint then cycleHint:Hide() end
        altWasDown = false
        return
    end
    local list = {}
    for _, m in ipairs(ns._movers) do
        if m:IsShown() and m:IsMouseOver() then list[#list + 1] = m end
    end
    local altDown = IsAltKeyDown() and true or false
    if #list > 1 then
        ensureCycleHint()
        local cx, cy = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        if cx and s and s > 0 then
            cycleHint:ClearAllPoints()
            cycleHint:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 16, cy / s + 16)
            cycleHint:SetText(string.format(L["%d frames here - hold Alt to cycle"], #list))
            cycleHint:Show()
        end
        if altDown and not altWasDown then
            table.sort(list, function(a, b) return a:GetFrameLevel() < b:GetFrameLevel() end)
            list[1]:Raise()
        end
    elseif cycleHint then
        cycleHint:Hide()
    end
    altWasDown = altDown
end

local cycleDriver = CreateFrame("Frame")
local cycleAcc = 0
cycleDriver:SetScript("OnUpdate", function(_, elapsed)
    cycleAcc = cycleAcc + elapsed
    if cycleAcc < 0.15 then return end
    cycleAcc = 0
    updateCycle()
end)

-- Connector lines need their own, faster clock: the pulse has to look smooth.
local linkDriver = CreateFrame("Frame")
local linkAcc = 0
linkDriver:SetScript("OnUpdate", function(_, elapsed)
    if not ns:IsEditModeActive() then return end
    linkAcc = linkAcc + elapsed
    if linkAcc < 0.03 then return end
    linkAcc = 0
    drawLinks()
end)

-- All three drivers only ever have work while the editor is open -- each one's
-- body starts by checking exactly that -- yet they were installed at file load
-- and paid the per-frame call for the whole session regardless. A hidden frame
-- runs no OnUpdate at all (Blizzard parks its own state-driver manager the same
-- way), so the editor toggle now parks them and the idle cost drops to zero.
local DRIVERS = { liveGuideDriver, cycleDriver, linkDriver }
for _, d in ipairs(DRIVERS) do d:Hide() end
ns:RegisterEditModeHook(function(state)
    for _, d in ipairs(DRIVERS) do
        if state then d:Show() else d:Hide() end
    end
    -- Start each session on a full interval instead of whatever was left over.
    cycleAcc, linkAcc = 0, 0
    if not state then
        -- updateCycle was the only thing that ever hid this, and it no longer
        -- runs once the driver is parked -- the hint would stay on screen at
        -- DIALOG strata until edit mode was reopened and the cursor moved.
        if cycleHint then cycleHint:Hide() end
        altWasDown = false
    end
end)

-- Layouts live in ns.db.global so they are shared across profiles; capture/apply lives in Core/Mover.lua.
local layoutsPanel
local selectedLayout
local layoutValues = {}

local function layoutStore()
    local g = ns.db and ns.db.global
    if g then
        g.editLayouts = g.editLayouts or {}
        return g.editLayouts
    end
    ns._layoutFallback = ns._layoutFallback or {}
    return ns._layoutFallback
end

local function rebuildLayoutList(preferred)
    wipe(layoutValues)
    local store = layoutStore()
    local names = {}
    for name in pairs(store) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        layoutValues[#layoutValues + 1] = { value = name, text = name }
    end
    if preferred and store[preferred] then
        selectedLayout = preferred
    elseif not (selectedLayout and store[selectedLayout]) then
        selectedLayout = names[1]
    end
    if layoutsPanel and layoutsPanel.dropdown and layoutsPanel.dropdown._button then
        layoutsPanel.dropdown._button._refresh()
        if not selectedLayout then
            layoutsPanel.dropdown._button._setText(L["No layouts saved"])
        end
    end
end

local function saveLayout(name)
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "")
    if not name or name == "" then return end
    layoutStore()[name] = ns:CaptureLayout()
    rebuildLayoutList(name)
    ns:Print(string.format(L["Layout '%s' saved."], name))
end

local function loadSelected()
    local store = layoutStore()
    if not (selectedLayout and store[selectedLayout]) then
        ns:Print(L["No layout selected."]); return
    end
    local n = ns:ApplyLayout(store[selectedLayout])
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    ns:Print(string.format(L["Applied layout '%s' (%d frames)."], selectedLayout, n))
end

local function importLayout(str)
    local name, snap = ns:DeserializeLayout(str)
    if not name then
        ns:Print(string.format(L["Import failed (%s)."], tostring(snap)))
        return
    end
    if name == "" then name = L["Imported"] end
    -- De-dupe without parentheses; the dropdown strips "(...)" from display.
    local store = layoutStore()
    local base, i, final = name, 2, name
    while store[final] do final = base .. " " .. i; i = i + 1 end
    store[final] = snap
    rebuildLayoutList(final)
    ns:Print(string.format(L["Layout '%s' imported."], final))
end

-- Newer clients expose the popup box as .EditBox, older ones as .editBox.
local function popupBox(self)
    return ns.PopupEditBox(self)
end

ns.OnLocaleReady(function()
StaticPopupDialogs["VFUI_LAYOUT_SAVE"] = {
    text = L["Name for this layout:"],
    button1 = SAVE or L["Save"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 48,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then saveLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) saveLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_IMPORT"] = {
    text = L["Paste a layout string and confirm:"],
    button1 = L["Import"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 0,
    OnShow   = function(self) local b = popupBox(self); if b then b:SetText(""); b:SetFocus() end end,
    OnAccept = function(self) local b = popupBox(self); if b then importLayout(b:GetText()) end end,
    EditBoxOnEnterPressed  = function(self) importLayout(self:GetText()); self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_EXPORT"] = {
    text = L["Copy this string (Ctrl+A, Ctrl+C):"],
    button1 = OKAY or L["Close"],
    hasEditBox = true, maxLetters = 0,
    OnShow = function(self, data)
        local b = popupBox(self)
        if b then b:SetText(data or ""); b:HighlightText(); b:SetFocus() end
    end,
    EditBoxOnEnterPressed  = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["VFUI_LAYOUT_DELETE"] = {
    text = L["Delete layout '%s'?"],
    button1 = YES, button2 = NO,
    OnAccept = function()
        if selectedLayout then layoutStore()[selectedLayout] = nil; rebuildLayoutList() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
end)

local function buildLayoutsPanel()
    if layoutsPanel then return end
    local p = CreateFrame("Frame", "VFUILayoutsPanel", UIParent)
    layoutsPanel = p
    p:SetSize(260, 252)
    p:SetPoint("LEFT", UIParent, "LEFT", 48, 40)
    p:SetFrameStrata("DIALOG")
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    p:SetMovable(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    UI:StyleBackdrop(p, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(p)

    local strip = p:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  p, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 14)
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -13)
    title:SetText(L["LAYOUTS"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local close = CreateFrame("Button", nil, p)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", p, "TOPRIGHT", -6, -8)
    local cfs = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(cfs, 20)
    cfs:SetPoint("CENTER", close, "CENTER", 0, 0)
    cfs:SetText("x"); cfs:SetTextColor(0.7, 0.7, 0.75)
    close:SetScript("OnEnter", function() cfs:SetTextColor(accent.r, accent.g, accent.b) end)
    close:SetScript("OnLeave", function() cfs:SetTextColor(0.7, 0.7, 0.75) end)
    close:SetScript("OnClick", function() p:Hide() end)

    local sep = p:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -38)
    sep:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -38)
    sep:SetHeight(1); sep:SetColorTexture(1, 1, 1, 0.07)

    local cap = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 10)
    cap:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -46)
    cap:SetText(L["SAVED"]); cap:SetTextColor(0.55, 0.55, 0.62)

    p.dropdown = UI:CreateDropdown(p, {
        label = "", width = 228, values = layoutValues,
        tooltip = L["Pick a saved layout to load, delete or export."],
        get = function() return selectedLayout end,
        set = function(_, v) selectedLayout = v end,
    })
    p.dropdown:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -60)

    local loadBtn = UI:CreateButton(p, {
        label = L["Load"], width = 110, primary = true,
        onClick = function() loadSelected() end,
    })
    loadBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -92)

    local delBtn = UI:CreateButton(p, {
        label = L["Delete"], width = 110,
        onClick = function()
            if selectedLayout then StaticPopup_Show("VFUI_LAYOUT_DELETE", selectedLayout)
            else ns:Print(L["No layout selected."]) end
        end,
    })
    delBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -92)

    local saveBtn = UI:CreateButton(p, {
        label = L["Save current as..."], width = 228,
        onClick = function() StaticPopup_Show("VFUI_LAYOUT_SAVE") end,
    })
    saveBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -124)

    local sep2 = p:CreateTexture(nil, "ARTWORK")
    sep2:SetPoint("TOPLEFT",  p, "TOPLEFT",  14, -158)
    sep2:SetPoint("TOPRIGHT", p, "TOPRIGHT", -14, -158)
    sep2:SetHeight(1); sep2:SetColorTexture(1, 1, 1, 0.07)

    local expBtn = UI:CreateButton(p, {
        label = L["Export"], width = 110,
        onClick = function()
            local store = layoutStore()
            if selectedLayout and store[selectedLayout] then
                StaticPopup_Show("VFUI_LAYOUT_EXPORT", nil, nil,
                    ns:SerializeLayout(selectedLayout, store[selectedLayout]))
            else ns:Print(L["No layout selected."]) end
        end,
    })
    expBtn:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -168)

    local impBtn = UI:CreateButton(p, {
        label = L["Import"], width = 110,
        onClick = function() StaticPopup_Show("VFUI_LAYOUT_IMPORT") end,
    })
    impBtn:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -168)

    local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(hint, 11)
    hint:SetPoint("BOTTOMLEFT",  p, "BOTTOMLEFT",  16, 14)
    hint:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 14)
    hint:SetJustifyH("LEFT"); hint:SetSpacing(2); hint:SetTextColor(0.55, 0.55, 0.62)
    hint:SetText(L["Save your window arrangement, then load or share it any time."])
end

function ns:ToggleLayouts()
    buildLayoutsPanel()
    if layoutsPanel:IsShown() then
        layoutsPanel:Hide()
    else
        rebuildLayoutList()
        layoutsPanel:Show()
    end
end

function ns:HideLayouts()
    if layoutsPanel then layoutsPanel:Hide() end
end

-- Read by the fading toolbar, which must not fade out from under an open panel.
layoutsShown = function()
    return layoutsPanel ~= nil and layoutsPanel:IsShown()
end
