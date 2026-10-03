-- VuloForeverUI / UI / MainFrame / Window: the window's size, scale and fit, close hooks and the style-switch rebuild.
-- Together the MainFrame files build the main options window (title bar, sidebar, tabs, content, footer).
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Shared between the MainFrame files: the bar sizes, fittedSize and the parts
-- of UI:CreateMainFrame that live in their own files.
UI._MF = UI._MF or {}
local MF = UI._MF

local FRAME_WIDTH   = 1050
local FRAME_HEIGHT  = 680
local SIDEBAR_WIDTH = 210
local TITLEBAR_H    = 32
local BOTTOMBAR_H   = 44
local TABBAR_H      = 32

-- 1050x680 is the design size, not a promise. On an interface scale that leaves
-- UIParent smaller than that, the window fills the screen edge to edge -- and
-- because it is clamped to the screen it then cannot be dragged at all: there
-- is nowhere for it to go. Reported as "the menu will not move down"
-- (01.08.2026), where the window stood at 99% of the screen height and had
-- about twenty units of travel left.
--
-- A margin is subtracted rather than fitting exactly, so there is always slack
-- in both directions and the window can still be moved off centre.
local MIN_WIDTH, MIN_HEIGHT, SCREEN_MARGIN = 820, 400, 60

-- This window's own scale, on top of whatever the game's interface scale is.
-- Read through a clamp rather than trusted: it comes out of a saved profile, and
-- a window at scale 0.05 cannot be found again to fix it.
local SCALE_MIN, SCALE_MAX = 0.70, 1.30
function UI:MainFrameScale()
    local ui = ns.db and ns.db.profile and ns.db.profile.ui
    local s = ui and ui.mainFrameScale
    if type(s) ~= "number" or s ~= s then return 1 end
    if s < SCALE_MIN then return SCALE_MIN end
    if s > SCALE_MAX then return SCALE_MAX end
    return s
end
UI.MainFrameScaleRange = { SCALE_MIN, SCALE_MAX }

local function fittedSize()
    local w, h = FRAME_WIDTH, FRAME_HEIGHT
    -- The room is measured in UIParent units, the window is measured in its own:
    -- at half scale the same screen holds twice the design size. Dividing here is
    -- what lets scaling DOWN actually buy the window its full 1050x680 on a
    -- screen that could not hold it before.
    local s = UI:MainFrameScale()
    if UIParent and UIParent.GetWidth then
        local aw, ah = UIParent:GetWidth(), UIParent:GetHeight()
        if aw and aw > 0 then w = math.min(w, math.max(MIN_WIDTH,  (aw - SCREEN_MARGIN) / s)) end
        if ah and ah > 0 then h = math.min(h, math.max(MIN_HEIGHT, (ah - SCREEN_MARGIN) / s)) end
    end
    return w, h
end

-- Live, because the slider that calls this sits IN the window: the effect is the
-- feedback. The row panel is closed rather than rescaled -- it hangs off a row
-- that just moved and changed size under it.
function UI:SetMainFrameScale(v)
    local ui = ns.db and ns.db.profile and ns.db.profile.ui
    if ui then ui.mainFrameScale = tonumber(v) or 1 end
    local f = UI.mainFrame
    if not f then return end
    if UI.CloseRowPopup then UI:CloseRowPopup() end
    f:SetScale(UI:MainFrameScale())
    -- A rebuild only when the window actually changed SIZE, which happens where
    -- the screen was cutting it off: the rows are laid out against that width.
    -- Next frame, not here: the rebuild reclaims the very slider whose drag is
    -- still running up the stack above this call.
    if UI:FitMainFrame() and UI.BuildOptionsPage and UI._currentBuildKey then
        ns.NextFrame(function()
            if UI.mainFrame and UI.mainFrame:IsShown() then
                UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
            end
        end)
    end
end

-- Re-measured on every open: the interface scale can change while the addon is
-- loaded, and the setting that changes it lives in this very window.
function UI:FitMainFrame()
    local f = UI.mainFrame
    if not f then return end
    -- Re-applied here too, not only in the setter: a profile switch brings its
    -- own scale along, and this runs on every open.
    local s = UI:MainFrameScale()
    if f:GetScale() ~= s then f:SetScale(s) end
    local w, h = fittedSize()
    -- Reports whether it RESIZED. Scaling alone needs no relayout -- everything
    -- inside is measured in the window's own units and comes along -- but a size
    -- change does, and only the caller knows whether a rebuild is safe from
    -- where it stands.
    if f:GetWidth() ~= w or f:GetHeight() ~= h then f:SetSize(w, h); return true end
    return false
end

-- for the MainFrame files loaded after this one
MF.SIDEBAR_WIDTH = SIDEBAR_WIDTH
MF.TITLEBAR_H    = TITLEBAR_H
MF.BOTTOMBAR_H   = BOTTOMBAR_H
MF.TABBAR_H      = TABBAR_H
MF.fittedSize    = fittedSize

-- What a module wants done when the window closes. Registered here rather than
-- hooked onto the frame: a style switch replaces the frame (UI:RebuildMainFrame),
-- and a hook laid on the old one would never fire again.
UI._mainHideHooks = UI._mainHideHooks or {}
function UI:OnMainFrameHide(fn)
    table.insert(UI._mainHideHooks, fn)
end

-- A style switch without /reload. Every texture of the window was painted once,
-- when it was built, so the window is built again -- same place, same page --
-- and the old one is hidden for good. Frames cannot be destroyed; one abandoned
-- window per switch is the price, and nothing references it afterwards. Every
-- cache below holds frames of the old window and must go with it.
-- Windows outside this one (Edit Mode panels, dialogs, color picker) keep
-- their look until the next /reload.
local OLD_WINDOW_CACHES = {
    "_dashRow", "_dashContainer", "_dashStats", "_dashChips", "_dashHints",
    "_dashChangeRows", "_dashGroupHdrs", "_changelogRow", "_pinRows",
    "_sidebarChildren", "_sidebarHeaders", "_sidebarFilterBox", "sidebarButtons",
}
function UI:RebuildMainFrame()
    local old = UI.mainFrame
    if not old then return end
    local wasShown = old:IsShown()
    local module, tab = UI.currentModule, UI.currentTab
    local filter = UI._sidebarFilterBox and UI._sidebarFilterBox:GetText() or ""

    if UI.CloseDropdownPopup then UI.CloseDropdownPopup() end
    old:Hide()
    UI.mainFrame = nil
    for _, k in ipairs(OLD_WINDOW_CACHES) do UI[k] = nil end
    -- tables the sidebar reads with pairs() before it refills them
    UI.sidebarButtons = {}
    UI._pinRows = {}
    UI._tabPool = {}
    if UI.ResetWidgetPools then UI.ResetWidgetPools() end
    if UI.ResetDropdownPopup then UI.ResetDropdownPopup() end

    local f = UI:CreateMainFrame()
    if not wasShown then return end
    f:Show()
    UI:PopulateSidebar()
    if filter ~= "" and UI._sidebarFilterBox then UI._sidebarFilterBox:SetText(filter) end
    -- The page waits one frame. A window built this very frame has no resolved
    -- size yet -- the scroll area reads 0 wide, the page is laid out into
    -- nothing and the tab rail hides every tab as overflow (seen in game: an
    -- empty window after the first switch).
    C_Timer.After(0, function()
        if UI.mainFrame ~= f or not f:IsShown() then return end
        if module and module ~= UI.DASHBOARD_KEY and ns.modules[module] then
            UI:ShowModulePage(module)
            if tab then UI:ShowTab(tab) end
        elseif UI.ShowDashboard then
            UI:ShowDashboard()
        end
    end)
end
