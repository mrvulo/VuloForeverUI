-- VuloForeverUI / UI / EditMode / Toolbar: the toolbar, ns:SetEditMode, confirm popups, combat suspend and /vedit.
local _, ns = ...
local L  = ns.L
local UI = ns.UI
local EM = ns._EM
local gridState   = EM.gridState
local snapKinds   = EM.snapKinds
local refreshGrid = EM.refreshGrid

local built

local function build()
    if built then return end
    built = true
    local accent = ns.COLORS.accent

    -- Strata stays below the movers (HIGH) so the boxes remain clickable.
    EM.dim = CreateFrame("Frame", "VFUIEditDim", UIParent)
    EM.dim:SetAllPoints(UIParent)
    EM.dim:SetFrameStrata("MEDIUM")
    EM.dim:EnableMouse(true)
    EM.dim:SetScript("OnMouseDown", function()
        if ns.IsAnchorPicking and ns:IsAnchorPicking() then
            if ns.CancelAnchorPick then ns:CancelAnchorPick() end
            return
        end
        if ns.DeselectMover then ns:DeselectMover() end
    end)
    local fill = EM.dim:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(EM.dim)
    fill:SetColorTexture(0, 0, 0, 0.35)
    EM.dim.fill = fill
    EM.dim:Hide()

    -- DIALOG keeps the toolbar above the movers (HIGH) so its controls stay clickable.
    EM.toolbar = CreateFrame("Frame", "VFUIEditToolbar", UIParent)
    EM.toolbar:SetSize(1240, 64)
    EM.toolbar:SetPoint("TOP", UIParent, "TOP", 0, -140)
    EM.toolbar:SetFrameStrata("DIALOG")
    EM.toolbar:SetClampedToScreen(true)
    EM.toolbar:EnableMouse(true)
    EM.toolbar:SetMovable(true)
    EM.toolbar:RegisterForDrag("LeftButton")
    EM.toolbar:SetScript("OnDragStart", EM.toolbar.StartMoving)
    EM.toolbar:SetScript("OnDragStop",  EM.toolbar.StopMovingOrSizing)
    UI:StyleBackdrop(EM.toolbar, { bg = ns.COLORS.bg, border = ns.COLORS.accentDim })
    UI:CreateShadow(EM.toolbar)

    local strip = EM.toolbar:CreateTexture(nil, "ARTWORK")
    strip:SetPoint("TOPLEFT",  EM.toolbar, "TOPLEFT",  0, 0)
    strip:SetPoint("TOPRIGHT", EM.toolbar, "TOPRIGHT", 0, 0)
    strip:SetHeight(2)
    UI.SetGradient(strip, "HORIZONTAL", accent.r, accent.g, accent.b, 0.0, accent.r, accent.g, accent.b, 0.9)

    local title = EM.toolbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(title, 13, "")
    title:SetPoint("TOP", EM.toolbar, "TOP", 0, -8)
    title:SetText(L["EDIT MODE"])
    title:SetTextColor(accent.r, accent.g, accent.b)

    local ROWY = -32

    -- Changes already live in the DB, so this is a checkpoint rather than a
    -- write: it re-bases the snapshot so Discard returns here, not to the state
    -- the session opened in, and lets you keep editing.
    local saveBtn = UI:CreateButton(EM.toolbar, {
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
    saveBtn:SetPoint("TOPLEFT", EM.toolbar, "TOPLEFT", 14, ROWY)

    local exitBtn = UI:CreateButton(EM.toolbar, {
        label   = L["Exit"],
        width   = 90,
        tooltip = L["Close Edit Mode and lock all windows. Your changes stay applied."],
        onClick = function() ns:SetEditMode(false) end,
    })
    exitBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)

    local discardBtn = UI:CreateButton(EM.toolbar, {
        label   = L["Discard"],
        width   = 96,
        tooltip = L["Discard changes and revert every window to the last save point, or to how it was when Edit Mode opened."],
        onClick = function() StaticPopup_Show("VFUI_EDIT_DISCARD") end,
    })
    discardBtn:SetPoint("LEFT", exitBtn, "RIGHT", 8, 0)

    local gridTog = UI:CreateToggle(EM.toolbar, {
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
    local snapTog = UI:CreateToggle(EM.toolbar, {
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

    local cap = EM.toolbar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(cap, 11)
    cap:SetText(L["Size"])
    cap:SetTextColor(ns.TC("textDim"))
    cap:SetPoint("LEFT", snapTog, "RIGHT", 16, 0)

    -- width is the TRACK only: the minus button, value and plus hang off its
    -- right edge for a further ~84px that no anchor accounts for, so the
    -- buttons on the right have to be placed clear of track width + 84.
    local sizeSlider = UI:CreateSlider(EM.toolbar, {
        label = "",
        min   = 8, max = 128, step = 4,
        width = 70,
        get   = function() return gridState().size end,
        set   = function(_, v) gridState().size = v; refreshGrid() end,
    })
    sizeSlider:SetPoint("LEFT", cap, "RIGHT", 8, 0)


    local resetBtn = UI:CreateButton(EM.toolbar, {
        label   = L["Reset"],
        width   = 120,
        tooltip = L["Reset all VuloUI window positions to the screen centre."],
        onClick = function() StaticPopup_Show("VFUI_EDIT_RESET") end,
    })
    resetBtn:SetPoint("TOPRIGHT", EM.toolbar, "TOPRIGHT", -16, ROWY)

    local layoutsBtn = UI:CreateButton(EM.toolbar, {
        label   = L["Layouts"],
        width   = 110,
        tooltip = L["Save, load, export and import named window layouts."],
        onClick = function() if ns.ToggleLayouts then ns:ToggleLayouts() end end,
    })
    layoutsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -10, 0)

    -- Anchored RIGHT, off the button group: the left-hand chain ends at the
    -- size slider whose caption width varies by language — a left anchor put
    -- this switch on top of the Layouts button in German (user screenshot).
    local ghostTog = UI:CreateToggle(EM.toolbar, {
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
    EM.toolbar._switches = { gridTog, snapTog, ghostTog }
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
        -- The options window sits exactly on top of the boxes it just
        -- unlocked; entering the editor closes it, the same way the client's
        -- own editor closes the settings panel (user report with screenshot,
        -- 09.08.2026). Not reopened on exit: whoever finishes editing is
        -- looking at their interface, not at the options.
        local main = ns.UI and ns.UI.mainFrame
        if main and main.IsShown and main:IsShown() then main:Hide() end
        EM.dim:Show()
        EM.toolbar:Show()
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
        EM.dim:Hide()
        EM.dim:SetScript("OnUpdate", nil)
        EM.toolbar:Hide()
        -- A faded toolbar must not come back faded next session before the
        -- first OnUpdate tick, and the script has nothing to do while hidden.
        EM.toolbar:SetScript("OnUpdate", nil)
        EM.toolbar:SetAlpha(1)
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
