-- EditMode: the settings page for the editing session, as its own sidebar row
-- under Global Settings.
--
-- There is no module here in the usual sense -- no lifecycle, nothing to
-- switch off. Edit Mode is a session the whole suite shares (UI/EditMode.lua
-- owns it, Core/Mover.lua owns the boxes); this file is the page that drives
-- it, and it exists as a module only because that is what puts a row in the
-- sidebar. Every switch writes ns.db.profile.editmode.grid, the one table the
-- session reads, and then asks a running session to pick the change up.
local _, ns = ...
local L = ns.L

local mod = ns:RegisterModule("editmode", {
    name        = "Edit Mode",
    group       = "Global",
    description = "Unlock every window in the suite and place it: the grid, what a window snaps to, and how the session looks while you work.",
    noToggle    = true,      -- nothing to switch off
    optionsGrid = true,
    -- Global Settings carries no order of its own (0), so 1 puts this row
    -- directly beneath it instead of alphabetically anywhere in the group.
    sidebarOrder = 1,
    defaults    = { enabled = true },
})

-- No lifecycle of its own; the session is built on demand by UI/EditMode.lua.
function mod:OnEnable() end

local function editState()
    return ns.EditState and ns.EditState() or {}
end

local function editRefresh()
    if ns.IsEditModeActive and ns:IsEditModeActive() and ns.RefreshEditMode then
        ns:RefreshEditMode()
    end
end

local function editToggle(key, label, tooltip)
    return { type = "toggle", label = label, tooltip = tooltip,
        get = function() return editState()[key] end,
        set = function(_, v) editState()[key] = v; editRefresh() end }
end

function mod:GetOptions()
    local snapModes = {
        { value = "both",     text = L["Other windows and the grid"] },
        { value = "elements", text = L["Only other windows"] },
        { value = "grid",     text = L["Only the grid"] },
        { value = "none",     text = L["Nothing"] },
    }

    return {
        { type = "group", layout = "row", gap = 10, align = "center", items = {
            { type = "button", label = L["Open Edit Mode"], width = 200, primary = true,
              onClick = function() ns:SetEditMode(true) end },
            { type = "button", label = L["Reset All Positions"], width = 200,
              tooltip = L["Reset all VuloUI window positions to the screen centre."],
              onClick = function() StaticPopup_Show("VFUI_EDIT_RESET") end },
        } },
        { type = "desc", text = L["|cffaaaaaaEdit Mode unlocks every window in the suite so you can drag it. /vedit opens it too. Not possible in combat.|r"] },

        { type = "section", title = L["Alignment"], items = {
            editToggle("show", L["Show the grid"],
                L["Draws an alignment grid over the screen while editing."]),
            { type = "slider", label = L["Grid size"], min = 8, max = 128, step = 4,
              get = function() return editState().size end,
              set = function(_, v) editState().size = v; editRefresh() end },
            { type = "dropdown", label = L["Snap to"], values = snapModes, width = 220,
              tooltip = L["What a window snaps to while you drag it. Other windows snap edge to edge and centre to centre; the grid snaps to its lines."],
              get = function() return editState().snapTo end,
              set = function(_, v) editState().snapTo = v; editRefresh() end },
        } },

        { type = "section", title = L["While editing"], items = {
            editToggle("dimBg", L["Darken the interface"],
                L["Dims everything behind the boxes so the boxes read clearly. Off keeps your interface at full brightness while you place things against it."]),
            editToggle("ghost", L["See-through boxes"],
                L["Hide the box fill and labels while editing, so you can see the interface you are aligning. The thin borders stay."]),
            editToggle("coords", L["Show coordinates"],
                L["Prints each window's X and Y position on its box, and keeps it up to date while you drag."]),
            editToggle("cursorLight", L["Light around the cursor"],
                L["A soft light follows the mouse, so the darkened interface stays readable where you are working."]),
            editToggle("hoverBar", L["Toolbar only on mouseover"],
                L["The Edit Mode toolbar fades out until the mouse reaches it, so it stops covering what is behind it."]),
        } },
    }
end
