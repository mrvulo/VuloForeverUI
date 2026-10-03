-- VuloForeverUI / UI / MainFrame / Create: UI:CreateMainFrame, the window itself (title bar, sidebar, tabs, content).
local _, ns = ...
local L = ns.L
local UI = ns.UI
local MF = UI._MF
local SIDEBAR_WIDTH = MF.SIDEBAR_WIDTH
local TITLEBAR_H    = MF.TITLEBAR_H
local BOTTOMBAR_H   = MF.BOTTOMBAR_H
local TABBAR_H      = MF.TABBAR_H
local fittedSize    = MF.fittedSize

function UI:CreateMainFrame()
    if UI.mainFrame then return UI.mainFrame end

    local f = CreateFrame("Frame", "VuloForeverUIMainFrame", UIParent)
    f:SetScale(UI:MainFrameScale())   -- before the fit: the fit is measured against it
    f:SetSize(fittedSize())
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:Hide()

    UI:StyleBackdrop(f, { bg = ns.COLORS.bg, border = ns.COLORS.borderDark or ns.COLORS.border,
                          edge = ns.theme.edge, window = true })
    UI:CreateShadow(f)

    local brand = f:CreateTexture(nil, "BORDER", nil, 1)
    brand:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    brand:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    brand:SetHeight(2)
    UI.SetGradient(brand, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1.0,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.10)
    -- a Blizzard window frame has its own top edge; the accent line would sit on it
    if ns.theme.window then brand:Hide() end

    local pos = (ns.db and ns.db.profile and ns.db.profile.ui and ns.db.profile.ui.mainFramePos)
              or { point = "CENTER", relPoint = "CENTER", x = 0, y = 0 }
    f:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)

    tinsert(UISpecialFrames, "VuloForeverUIMainFrame")  -- ESC closes

    f:SetScript("OnMouseDown", function()
        if _G.VCDropdownPopup and _G.VCDropdownPopup:IsShown() then
            _G.VCDropdownPopup:Hide()
        end
    end)

    -- A theme with Blizzard's window frame lays a metal band across the top
    -- 22 pixels. The title then goes INTO that band, centred the way Blizzard
    -- places its own, and search, version and timings move to a header row
    -- under it -- 58 pixels in all instead of one 32-pixel bar. The bar is
    -- raised above the frame art (UI.ApplyWindowArt draws at +30), or the band
    -- would cover the title.
    local framed = (ns.theme.window and ns.theme.window.layout) and true or false
    local titleH = framed and 58 or TITLEBAR_H

    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:SetHeight(titleH)
    if framed then titleBar:SetFrameLevel(f:GetFrameLevel() + 35) end
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, x, y = f:GetPoint(1)
        if ns.db and ns.db.profile and ns.db.profile.ui then
            ns.db.profile.ui.mainFramePos = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)

    local tbBG = UI.SetColorBG(titleBar, ns.TC("barBottom"))
    local top, bot = ns.COLORS.barTop, ns.COLORS.barBottom
    UI.SetGradient(tbBG, "VERTICAL",
        bot.r, bot.g, bot.b, bot.a or 1,
        top.r, top.g, top.b, top.a or 1)
    if framed then tbBG:Hide() end   -- the metal band and the window background show instead

    -- the icon supplies the leading "V", the text starts at "uloForeverUI"
    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(title, 15)
    if ns.theme.titleFont then title:SetFont(ns.theme.titleFont, 15, "") end
    title:SetText((ns.C and ns.C.accent or "|cff9b6cff") .. "uloForeverUI|r")
    local _, titleFontSize = title:GetFont()
    local iconSize = (titleFontSize or 14) + 4

    local titleIcon = titleBar:CreateTexture(nil, "OVERLAY")
    titleIcon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\vui4")
    titleIcon:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    titleIcon:SetSize(iconSize, iconSize)

    title:SetPoint("LEFT", titleIcon, "RIGHT", 1, 0)

    local version = titleBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.Font(version, 10)
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText("v" .. ns.VERSION)
    version:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)

    if framed then
        title:SetFont(ns.theme.titleFont or UI.FONT_PATH, 13, "")
        iconSize = 17
        titleIcon:SetSize(iconSize, iconSize)
        title:ClearAllPoints()
        title:SetPoint("TOP", titleBar, "TOP", iconSize / 2, -5)
        titleIcon:ClearAllPoints()
        titleIcon:SetPoint("RIGHT", title, "LEFT", -1, 0)
        version:ClearAllPoints()
        version:SetPoint("LEFT", titleBar, "BOTTOMLEFT", 16, 17)
    end

    -- the frame-time readout and its OnShow/OnHide hooks: MainFrame/Bars.lua
    local cpuText = MF.BuildFrameTimeReadout(f, titleBar, version)

    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(38, TITLEBAR_H - 3)
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -1, -3)

    local closeBG = closeBtn:CreateTexture(nil, "BACKGROUND")
    closeBG:SetAllPoints(closeBtn)
    closeBG:SetColorTexture(0.78, 0.16, 0.16, 1)
    closeBG:Hide()

    local searchBox = CreateFrame("EditBox", nil, titleBar)
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(UI.FONT_PATH, 11, "")
    searchBox:SetMaxLetters(60)
    searchBox:SetTextInsets(24, 8, 0, 0)

    local sbBg = searchBox:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints(searchBox)
    sbBg:SetColorTexture(ns.TC("input"))

    local sbIcon = searchBox:CreateTexture(nil, "OVERLAY")
    sbIcon:SetSize(12, 12)
    sbIcon:SetPoint("LEFT", searchBox, "LEFT", 7, 0)
    sbIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    sbIcon:SetVertexColor(ns.TC("textMuted"))

    local sbBorder = CreateFrame("Frame", nil, searchBox, BackdropTemplateMixin and "BackdropTemplate")
    sbBorder:SetAllPoints(searchBox)
    if sbBorder.SetBackdrop then
        sbBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    end

    searchBox:HookScript("OnEditFocusGained", function()
        if sbBorder.SetBackdropBorderColor then
            sbBorder:SetBackdropBorderColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
        end
        sbIcon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
    end)
    searchBox:HookScript("OnEditFocusLost", function()
        if sbBorder.SetBackdropBorderColor then
            sbBorder:SetBackdropBorderColor(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
        end
        sbIcon:SetVertexColor(ns.TC("textMuted"))
    end)

    local placeholder = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    UI.Font(placeholder, 11)
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 24, 0)
    placeholder:SetText(L["Search settings..."])
    placeholder:SetTextColor(ns.TC("textMuted"))

    -- Framed: the header row under the band, Blizzard's own search-box border
    -- and its close button.
    if framed then
        searchBox:ClearAllPoints()
        searchBox:SetPoint("RIGHT", titleBar, "BOTTOMRIGHT", -18, 17)
        searchBox:SetSize(230, 20)
        UI.ApplySearchArt(searchBox, sbBg, sbBorder)

        closeBtn:Hide()
        local blizzClose = CreateFrame("Button", nil, titleBar, "UIPanelCloseButtonNoScripts")
        blizzClose:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, 1)
        blizzClose:SetScript("OnClick", function() f:Hide() end)
    end

    -- the result list, the search itself and its keys: MainFrame/Search.lua
    MF.BuildSearchResults(f, searchBox, placeholder)

    local closeText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(closeText, 20)
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(ns.TC("textDim"))
    local font, _, flags = closeText:GetFont()
    if font then closeText:SetFont(font, 20, flags or "") end
    closeBtn:SetScript("OnEnter", function()
        closeBG:Show()
        closeText:SetTextColor(ns.TC("textHi"))
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBG:Hide()
        closeText:SetTextColor(ns.TC("textDim"))
    end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sep:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    sep:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    sep:SetHeight(1)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT",    sep, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", f,   "BOTTOMLEFT", 0, BOTTOMBAR_H)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    UI.SetColorBG(sidebar, ns.TC("bgLight"))

    local sidebarSep = f:CreateTexture(nil, "ARTWORK")
    sidebarSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    sidebarSep:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT", 0, 0)
    sidebarSep:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarSep:SetWidth(1)

    local sidebarScroll = CreateFrame("ScrollFrame", nil, sidebar, "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT",     sidebar, "TOPLEFT",     6, -6)
    sidebarScroll:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", -14, 6)
    local sidebarContent = CreateFrame("Frame", nil, sidebarScroll)
    sidebarContent:SetSize(SIDEBAR_WIDTH - 22, 10)
    sidebarScroll:SetScrollChild(sidebarContent)
    UI.StyleScrollbar(sidebarScroll)
    UI.EnableScrollWheel(sidebarScroll, sidebarContent)

    -- The dashboard's search prompt hands focus here rather than matching on its
    -- own, so there is only ever one search implementation.
    f.searchBox       = searchBox

    -- Where you are: "Group › Module › Tab", in the title bar's idle stretch
    -- between the frame-time readout and the search box. The sidebar shows the
    -- module, the tab row shows the tab; this is the one line that shows both
    -- and the group above them.
    local crumb = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(crumb, 11)
    crumb:SetPoint("LEFT", cpuText, "RIGHT", 16, 0)
    crumb:SetPoint("RIGHT", searchBox, "LEFT", -40, 0)
    crumb:SetJustifyH("LEFT")
    crumb:SetWordWrap(false)
    crumb:SetTextColor(ns.COLORS.textDim.r, ns.COLORS.textDim.g, ns.COLORS.textDim.b)
    f.crumb = crumb
    function UI:SetCrumb(text)
        if UI.mainFrame and UI.mainFrame.crumb then UI.mainFrame.crumb:SetText(text or "") end
    end

    -- Override-group picker, left of the search box. It only appears where the
    -- talent API exists, so a client without it shows no dead control.
    if ns.HasTalentGroups and ns:HasTalentGroups() then
        local ovBtn = CreateFrame("Button", nil, titleBar)
        ovBtn:SetSize(22, 20)
        ovBtn:SetPoint("RIGHT", searchBox, "LEFT", -6, 0)

        -- The player's own class icon: the overrides hang on this character's
        -- talents, so the control that opens them should look like them. Comes
        -- from Blizzard's class sheet, so nothing ships and no restart is needed.
        local glyph = ovBtn:CreateTexture(nil, "ARTWORK")
        glyph:SetSize(15, 15)
        glyph:SetPoint("CENTER")
        local classToken = select(2, UnitClass("player"))
        local tex, coords = ns:GetVuloClassIcon(classToken)
        if tex and coords then
            glyph:SetTexture(tex)
            glyph:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        else
            glyph:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
        ovBtn._glyph = glyph

        local hl = ovBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(ovBtn)
        hl:SetColorTexture(ns.TC("textHi", 0.08))

        ovBtn:SetScript("OnClick", function(self)
            if ns.ShowOverrideMenu then ns:ShowOverrideMenu(self) end
        end)
        ovBtn:SetScript("OnEnter", function(self)
            self._glyph:SetAlpha(1)   -- 90 % idle, full on hover
            local id = ns.EditingOverrideGroup and ns:EditingOverrideGroup()
            local g  = id and ns:OverrideGroup(id)
            -- The group icon rides HERE and not on the button: the button keeps
            -- one identity on purpose (see RefreshOverrideButton below), and the
            -- tooltip is where the group is named anyway.
            local name = g and ((ns.OverrideIconMarkup and ns:OverrideIconMarkup(g.icon) or "") .. g.name)
            -- Same wording as the menu's default entry, from one helper.
            UI:ShowTooltip(self, {
                anchor = "ANCHOR_BOTTOM",
                title  = L["Editing as"],
                lines  = { name and { name, 0.7, 0.7, 0.8 }
                                or { ns:OverrideSelfLabel(), 1, 1, 1 } },
            })
        end)
        ovBtn:SetScript("OnLeave", function(self)
            self._glyph:SetAlpha(0.9)
            UI:HideTooltip()
        end)

        f.overrideBtn = ovBtn

        -- Accent while a group is being recorded into: the whole suite behaves
        -- differently then, and that has to be visible from anywhere in it.
        function UI:RefreshOverrideButton()
            local b = UI.mainFrame and UI.mainFrame.overrideBtn
            if not b then return end
            -- ONE identity: the class icon in its natural colours, whatever the
            -- state. A control that changes its look depending on a mode makes
            -- the reader decode the icon before they can use it -- and the state
            -- is already told twice over, by the tick in the menu and by the
            -- accent bars on the overridden rows.
            b._glyph:SetDesaturated(false)
            b._glyph:SetVertexColor(ns.TC("textHi"))
            b._glyph:SetAlpha(0.9)
        end
        UI:RefreshOverrideButton()
    end

    f.sidebar         = sidebar
    f.sidebarContent  = sidebarContent
    f.sidebarScroll   = sidebarScroll

    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT",  sidebar,  "TOPRIGHT", 1, 0)
    tabBar:SetPoint("TOPRIGHT", f,        "TOPRIGHT", 0, -titleH - 1)
    tabBar:SetHeight(TABBAR_H)
    UI.SetColorBG(tabBar, ns.TC("bgContent"))

    local tabSep = f:CreateTexture(nil, "ARTWORK")
    tabSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    tabSep:SetPoint("TOPLEFT",  tabBar, "BOTTOMLEFT",  0, 0)
    tabSep:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, 0)
    tabSep:SetHeight(1)

    f.tabBar = tabBar
    f.tabSep = tabSep
    f.tabs   = {}

    -- Single-row tab strip. Tabs sit on a rail inside a clipping window; when
    -- they outgrow the bar, two arrow buttons page the rail left and right --
    -- the bar never wraps to a second row.
    local tabStrip = CreateFrame("Frame", nil, tabBar)
    tabStrip:SetClipsChildren(true)
    tabStrip:SetPoint("TOPLEFT",     tabBar, "TOPLEFT",     4, 0)
    tabStrip:SetPoint("BOTTOMRIGHT", tabBar, "BOTTOMRIGHT", -4, 0)
    local tabRail = CreateFrame("Frame", nil, tabStrip)
    tabRail:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", 0, -2)
    tabRail:SetSize(10, TABBAR_H - 4)
    f.tabStrip, f.tabRail = tabStrip, tabRail

    local function makeTabArrow(dir)
        local b = CreateFrame("Button", nil, tabBar)
        b:SetSize(18, TABBAR_H - 4)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        icon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\arrow_"
            .. (dir < 0 and "left" or "right") .. ".tga")
        icon:SetVertexColor(ns.TC("textDim"))
        b._icon = icon
        b:SetScript("OnEnter", function(self) self._icon:SetVertexColor(ns.TC("textHi")) end)
        b:SetScript("OnLeave", function(self) self._icon:SetVertexColor(ns.TC("textDim")) end)
        b:SetScript("OnClick", function() UI:ScrollTabs(dir) end)
        b:Hide()
        return b
    end
    f.tabPrev = makeTabArrow(-1)
    f.tabPrev:SetPoint("TOPLEFT", tabBar, "TOPLEFT", 2, -2)
    f.tabNext = makeTabArrow(1)
    f.tabNext:SetPoint("TOPRIGHT", tabBar, "TOPRIGHT", -2, -2)

    -- Beside the arrows, only while they are needed: a menu of every tab,
    -- the current one ticked. Paging a rail of fourteen tabs two at a time to
    -- reach the last one is the case this exists for.
    local tabMenu = CreateFrame("Button", nil, tabBar)
    tabMenu:SetSize(18, TABBAR_H - 4)
    tabMenu:SetPoint("RIGHT", f.tabNext, "LEFT", -2, 0)
    local tmIcon = tabMenu:CreateTexture(nil, "ARTWORK")
    tmIcon:SetSize(12, 12)
    tmIcon:SetPoint("CENTER", tabMenu, "CENTER", 0, 0)
    tmIcon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\arrow_down.tga")
    tmIcon:SetVertexColor(ns.TC("textDim"))
    tabMenu:SetScript("OnEnter", function(self)
        tmIcon:SetVertexColor(ns.TC("textHi"))
        UI:ShowTooltip(self, { title = L["All tabs"] })
    end)
    tabMenu:SetScript("OnLeave", function()
        tmIcon:SetVertexColor(ns.TC("textDim"))
        UI:HideTooltip()
    end)
    tabMenu:SetScript("OnClick", function(self)
        if not ns.ShowPopupMenu then return end
        local entries = {}
        for _, tab in ipairs(f.tabs or {}) do
            local id = tab._tabId
            entries[#entries + 1] = {
                text    = tab._text:GetText() or "",
                checked = function() return UI.currentTab == id end,
                func    = function() UI:ShowTab(id) end,
            }
        end
        ns:ShowPopupMenu(entries, self)
    end)
    tabMenu:Hide()
    f.tabMenu = tabMenu

    local TABCOL_W = 170
    local tabColumn = CreateFrame("Frame", nil, f)
    tabColumn:SetPoint("TOPLEFT",     sidebar, "TOPRIGHT",    1, 0)
    tabColumn:SetPoint("BOTTOMRIGHT", sidebar, "BOTTOMRIGHT", 1 + TABCOL_W, 0)
    UI.SetColorBG(tabColumn, ns.TC("bgLight"))
    tabColumn:Hide()

    local tabColSep = tabColumn:CreateTexture(nil, "ARTWORK")
    tabColSep:SetColorTexture(ns.COLORS.border.r, ns.COLORS.border.g, ns.COLORS.border.b, 1)
    tabColSep:SetPoint("TOPLEFT",    tabColumn, "TOPRIGHT", 0, 0)
    tabColSep:SetPoint("BOTTOMLEFT", tabColumn, "BOTTOMRIGHT", 0, 0)
    tabColSep:SetWidth(1)

    local tabColScroll = CreateFrame("ScrollFrame", nil, tabColumn, "UIPanelScrollFrameTemplate")
    tabColScroll:SetPoint("TOPLEFT",     tabColumn, "TOPLEFT",     6, -6)
    tabColScroll:SetPoint("BOTTOMRIGHT", tabColumn, "BOTTOMRIGHT", -14, 6)
    local tabColContent = CreateFrame("Frame", nil, tabColScroll)
    tabColContent:SetSize(TABCOL_W - 22, 10)
    tabColScroll:SetScrollChild(tabColContent)
    if UI.StyleScrollbar then UI.StyleScrollbar(tabColScroll) end
    UI.EnableScrollWheel(tabColScroll, tabColContent)

    f.tabColumn     = tabColumn
    f.tabColWidth   = TABCOL_W
    f.tabColContent = tabColContent
    f.tabColScroll  = tabColScroll

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     tabBar,  "BOTTOMLEFT",  0, -1)
    content:SetPoint("BOTTOMRIGHT", f,       "BOTTOMRIGHT", 0, BOTTOMBAR_H)
    UI.SetColorBG(content, ns.TC("bgContent"))

    f.content = content

    -- A module may pin a header here (mod.BuildPageHeader): it sits ABOVE the
    -- scroll area and stays put while the page under it scrolls. Hidden and
    -- zero-cost for every module that does not claim it; the scroll frame's
    -- top anchor switches between the two in BuildOptionsPage.
    local pageHeader = CreateFrame("Frame", nil, content)
    pageHeader:SetPoint("TOPLEFT",  content, "TOPLEFT",  8, -8)
    pageHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -20, -8)
    pageHeader:SetHeight(10)
    pageHeader:Hide()
    f.pageHeader = pageHeader

    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     content, "TOPLEFT",     8,  -8)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 8)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    UI.StyleScrollbar(scroll)
    UI.EnableScrollWheel(scroll, scrollChild)
    f.scroll      = scroll
    f.scrollChild = scrollChild

    -- the bottom bar, its buttons and the copy-link popup: MainFrame/Bars.lua
    MF.BuildBottomBar(f)

    UI.mainFrame = f
    return f
end
