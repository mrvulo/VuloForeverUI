-- VuloForeverUI / UI / MainFrame / Tabs: the tab bar and tab column -- pooled tabs, scrolling rail, switching tabs -- and the window toggle.
local _, ns = ...
local L = ns.L
local UI = ns.UI
local MF = UI._MF
local BOTTOMBAR_H = MF.BOTTOMBAR_H
local TABBAR_H    = MF.TABBAR_H

-- Optional per-module spec: mod.tabs = { { id = "general", label = "General" }, ... }.
-- Tab buttons are pooled: frames are never garbage-collected.
UI._tabPool = UI._tabPool or {}

function UI:ReleaseTabs()
    local f = UI.mainFrame
    if not f or not f.tabs then return end
    for _, tab in ipairs(f.tabs) do
        tab:Hide()
        tab:ClearAllPoints()
        if tab._icon      then tab._icon:Hide()      end
        if tab._leftbar   then tab._leftbar:Hide()   end
        if tab._underline then tab._underline:Hide() end
        -- the permanent handle, not _activeBG: the top-bar rendering nils that
        if tab._activeBGTex then tab._activeBGTex:Hide() end
        table.insert(UI._tabPool, tab)
    end
    f.tabs = {}
end

local function acquireTab(parentBar)
    local tab = table.remove(UI._tabPool)
    if tab then
        tab:SetParent(parentBar)
        return tab
    end

    tab = CreateFrame("Button", nil, parentBar)
    tab:SetHeight(28)

    local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    UI.Font(text, 12)
    text:SetPoint("CENTER", tab, "CENTER", 0, 0)
    tab._text = text

    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", tab, "LEFT", 8, 0)
    icon:Hide()
    tab._icon = icon

    local leftbar = tab:CreateTexture(nil, "OVERLAY")
    leftbar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    leftbar:SetWidth(3)
    leftbar:SetPoint("TOPLEFT",    tab, "TOPLEFT",    0, 0)
    leftbar:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 0, 0)
    leftbar:Hide()
    tab._leftbar = leftbar

    local activeBG = tab:CreateTexture(nil, "BACKGROUND")
    activeBG:SetAllPoints(tab)
    activeBG:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.08)
    activeBG:Hide()
    tab._activeBG = activeBG
    -- permanent handle: the top-bar rendering nils _activeBG (no fill behind a
    -- text tab), and a pooled frame must not lose the texture over it
    tab._activeBGTex = activeBG

    local underline = tab:CreateTexture(nil, "OVERLAY")
    underline:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT",  tab, "BOTTOMLEFT", 6, 0)
    underline:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 0)
    underline:Hide()
    tab._underline = underline

    -- scripts installed once on the pooled frame; they read the live self._tabId
    tab:SetScript("OnEnter", function(self)
        if UI.currentTab ~= self._tabId then
            self._text:SetTextColor(ns.TC("textHi"))
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if UI.currentTab ~= self._tabId then
            local c = ns.COLORS.textDim
            self._text:SetTextColor(c.r, c.g, c.b)
        end
    end)
    tab:SetScript("OnClick", function(self)
        UI:ShowTab(self._tabId)
    end)

    return tab
end

function UI:BuildTabsForModule(key)
    local f = UI.mainFrame
    if not f then return end
    local mod = ns.modules[key]

    UI:ReleaseTabs()

    local tabs = (mod and mod.tabs) or { { id = "default", label = L["Settings"] } }
    local hasRealTabs = mod and mod.tabs and #mod.tabs > 1

    if not hasRealTabs then
        f.tabBar:Hide()
        if f.tabSep then f.tabSep:Hide() end
        if f.tabColumn then f.tabColumn:Hide() end
        f.content:ClearAllPoints()
        f.content:SetPoint("TOPLEFT",     f.sidebar, "TOPRIGHT",  1, 0)
        f.content:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", 0, BOTTOMBAR_H)
        UI.currentTab = "default"
        UI:BuildOptionsPage(key, "default")
        return
    end

    -- Horizontal tab row along the top of the content area: text tabs with an
    -- accent underline under the active one. This replaced the left tab column
    -- on 30.07.2026 at the user's request. ONE row, always: tabs sit on the
    -- rail at their text width, and when they outgrow the bar (the arena
    -- module), the arrow buttons page the rail -- no second row.
    if f.tabColumn then f.tabColumn:Hide() end
    f.tabBar:Show()
    if f.tabSep then f.tabSep:Show() end

    local rail = f.tabRail
    local ROW_H, PADX, GAPX = TABBAR_H - 4, 14, 2
    local x = 0
    for _, tabDef in ipairs(tabs) do
        local tab = acquireTab(rail)
        tab:SetParent(rail)
        tab._tabId = tabDef.id
        tab:SetHeight(ROW_H)

        if tab._icon then tab._icon:Hide() end
        tab._text:ClearAllPoints()
        tab._text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab._text:SetJustifyH("CENTER")
        tab._text:SetText(L[tabDef.label])  -- tabDef.label is a raw English key

        local w = math.max(44, math.ceil(tab._text:GetStringWidth() or 40) + PADX * 2)
        tab:SetWidth(w)
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", rail, "TOPLEFT", x, 0)
        x = x + w + GAPX

        -- underline is the active mark up here; the left bar belongs to the
        -- retired column rendering and must not linger on a pooled frame
        tab._activeMark = tab._underline
        tab._leftbar:Hide()
        if tab._activeBGTex then tab._activeBGTex:Hide() end
        tab._activeBG = nil

        tab:Show()
        table.insert(f.tabs, tab)
    end
    f.tabBar:SetHeight(TABBAR_H)
    rail:SetSize(math.max(x, 10), ROW_H)
    f._tabTotalW = x
    UI._tabOffset = 0
    UI:UpdateTabScroll()

    f.content:ClearAllPoints()
    f.content:SetPoint("TOPLEFT",     f.tabBar, "BOTTOMLEFT",  0, -1)
    f.content:SetPoint("BOTTOMRIGHT", f,        "BOTTOMRIGHT", 0, BOTTOMBAR_H)

    if tabs[1] then UI:ShowTab(tabs[1].id) end
end

-- Applies the clamped rail offset and decides whether the arrows are needed.
function UI:UpdateTabScroll()
    local f = UI.mainFrame
    if not (f and f.tabStrip) then return end
    local barW  = f.tabBar:GetWidth() or 800
    local total = f._tabTotalW or 0
    -- two-pass width: the arrows themselves take room away from the strip,
    -- and the tab menu beside the right arrow takes its own
    local overflow = total > barW - 8
    local insetL   = overflow and 22 or 4
    local insetR   = overflow and 42 or 4
    f.tabStrip:SetPoint("TOPLEFT",     f.tabBar, "TOPLEFT",     insetL, 0)
    f.tabStrip:SetPoint("BOTTOMRIGHT", f.tabBar, "BOTTOMRIGHT", -insetR, 0)
    local visible = barW - insetL - insetR
    f._tabVisibleW = visible
    local maxOff  = math.max(0, total - visible)
    local off     = math.min(math.max(UI._tabOffset or 0, 0), maxOff)
    UI._tabOffset = off
    f.tabRail:ClearAllPoints()
    f.tabRail:SetPoint("TOPLEFT", f.tabStrip, "TOPLEFT", -off, -2)
    f.tabPrev:SetShown(overflow)
    f.tabNext:SetShown(overflow)
    if f.tabMenu then f.tabMenu:SetShown(overflow) end
    -- an arrow with nothing left in its direction dims instead of vanishing,
    -- so the pair keeps its place
    if overflow then
        f.tabPrev:SetAlpha(off > 0      and 1 or 0.35)
        f.tabNext:SetAlpha(off < maxOff and 1 or 0.35)
    end
end

function UI:ScrollTabs(dir)
    UI._tabOffset = (UI._tabOffset or 0) + dir * 160
    UI:UpdateTabScroll()
end

-- Pages the rail just far enough that the tab is in the window. A tab chosen
-- from the menu or reached by a search hit may sit past the right arrow.
function UI:EnsureTabVisible(tabId)
    local f = UI.mainFrame
    if not (f and f.tabs and f.tabPrev:IsShown()) then return end
    local vis = f._tabVisibleW or 0
    if vis <= 0 then return end
    local x = 0
    for _, tab in ipairs(f.tabs) do
        local w = tab:GetWidth() or 40
        if tab._tabId == tabId then
            local off = UI._tabOffset or 0
            if x < off then off = x
            elseif x + w > off + vis then off = x + w - vis end
            UI._tabOffset = off
            UI:UpdateTabScroll()
            return
        end
        x = x + w + 2
    end
end

function UI:ShowTab(tabId)
    UI.currentTab = tabId
    local f = UI.mainFrame
    UI:EnsureTabVisible(tabId)
    for _, tab in ipairs(f.tabs) do
        local mark = tab._activeMark or tab._underline
        if tab._tabId == tabId then
            if mark then mark:Show() end
            if tab._activeBG then tab._activeBG:Show() end
            tab._text:SetTextColor(ns.TC("textHi"))
        else
            if mark then mark:Hide() end
            if tab._activeBG then tab._activeBG:Hide() end
            local c = ns.COLORS.textDim
            tab._text:SetTextColor(c.r, c.g, c.b)
        end
    end
    if UI.currentModule then
        UI:BuildOptionsPage(UI.currentModule, tabId)
    end
end

function UI:ToggleMainFrame()
    local f = UI:CreateMainFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        UI:PopulateSidebar()
        if UI.ShowDashboard then
            UI:ShowDashboard()
        elseif not UI.currentModule and ns.moduleOrder[1] then
            UI:ShowModulePage(ns.moduleOrder[1])
        end
    end
end
