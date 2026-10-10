-- VuloForeverUI / UI / OptionsBuilder / Page: the jump-chip strip above the page, the crumb and the page build (UI:BuildOptionsPage).
local _, ns = ...
local UI = ns.UI
local L = ns.L
local OB = UI._OB
local CONTENT_PADDING = OB.CONTENT_PADDING
local navChips = OB.navChips
local clearChildren = OB.clearChildren
local markChanged = OB.markChanged
local placeItemList = OB.placeItemList
local pageLabelColumn = OB.pageLabelColumn
local soloLabelColumn = OB.soloLabelColumn
local closeRowPopup = OB.closeRowPopup
local wrapRecent = OB.wrapRecent

-- ---------------------------------------------------------------------------
-- The strip above the page: one chip per heading (click scrolls there, the
-- heading under the top edge is lit), and at the right the changed-only
-- filter with its count. Shown only when it has something to say -- two or
-- more headings, or a row that differs from its default.
-- ---------------------------------------------------------------------------
local NAV_CHIP_H, NAV_GAP = 20, 6

local function stripCodes(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return s
end

local function styleChip(c, active, strong)
    if not c.SetBackdropColor then return end
    local a, b = ns.COLORS.accent, ns.COLORS.border
    if active then
        c:SetBackdropColor(a.r, a.g, a.b, strong and 0.32 or 0.18)
        c:SetBackdropBorderColor(a.r, a.g, a.b, 0.9)
        c.text:SetTextColor(ns.TC("textHi"))
    else
        c:SetBackdropColor(ns.TC("chip"))
        c:SetBackdropBorderColor(b.r, b.g, b.b, 0.6)
        c.text:SetTextColor(ns.TC("textSoft"))
    end
end

local function navChip(host, i)
    local c = navChips[i]
    if c then c:SetParent(host); return c end
    c = CreateFrame("Button", nil, host, BackdropTemplateMixin and "BackdropTemplate")
    c:SetHeight(NAV_CHIP_H)
    if c.SetBackdrop then
        c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                        edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    local hl = c:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(c)
    hl:SetColorTexture(ns.TC("textHi", 0.05))
    c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(c.text, 11)
    c.text:SetPoint("CENTER", c, "CENTER", 0, 0)
    c:SetScript("OnClick", function(self) if self._onClick then self._onClick() end end)
    c:SetScript("OnEnter", function(self)
        if self._tip then UI:ShowTooltip(self, { title = self._tip, wrap = true }) end
    end)
    c:SetScript("OnLeave", function() UI:HideTooltip() end)
    navChips[i] = c
    return c
end

local function ensurePageNav(f)
    if f.pageNav then return f.pageNav end
    local nav = CreateFrame("Frame", nil, f.content)
    nav:Hide()
    f.pageNav = nav
    f.scroll:HookScript("OnVerticalScroll", function() UI:UpdateNavActive() end)
    return nav
end

function UI:UpdateNavActive()
    local f = UI.mainFrame
    local chips = UI._navSectionChips
    if not (f and f.pageNav and f.pageNav:IsShown() and chips and #chips > 0) then return end
    local off = f.scroll:GetVerticalScroll() or 0
    local active = 1
    for i, c in ipairs(chips) do
        if c._section and c._section.y <= off + 12 then active = i end
    end
    -- At the very bottom the last heading is what the reader is looking at,
    -- whether or not it ever reached the top edge.
    local maxOff = (f.scrollChild:GetHeight() or 0) - (f.scroll:GetHeight() or 0)
    if maxOff > 0 and off >= maxOff - 1 then active = #chips end
    for i, c in ipairs(chips) do styleChip(c, i == active) end
end

local function layoutPageNav(f, changedN)
    local nav = ensurePageNav(f)
    for _, c in ipairs(navChips) do c:Hide() end
    UI._navSectionChips = nil
    local sections = UI._sectionList or {}
    local showFilter = changedN > 0 or UI.onlyChanged
    if #sections < 2 and not showFilter then nav:Hide(); return 0 end

    local width = (f.content:GetWidth() or 0) - 56
    if width < 200 then width = 600 end
    local n, filterW = 0, 0

    if showFilter then
        n = n + 1
        local c = navChip(nav, n)
        c.text:SetText(string.format("%s  %d", L["Changed"], changedN))
        c:SetWidth((c.text:GetStringWidth() or 40) + 20)
        c._section = nil
        c._tip = L["Show only settings that differ from their defaults"]
        c._onClick = function()
            UI.onlyChanged = not UI.onlyChanged
            UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
        end
        styleChip(c, UI.onlyChanged, true)
        c:ClearAllPoints()
        c:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, 0)
        c:Show()
        filterW = (c:GetWidth() or 60) + 12
    end

    local x, row, chips = 0, 0, {}
    if #sections >= 2 then
        for _, s in ipairs(sections) do
            n = n + 1
            local c = navChip(nav, n)
            c.text:SetText(stripCodes(s.title))
            local w = (c.text:GetStringWidth() or 40) + 18
            c:SetWidth(w)
            local limit = width - (row == 0 and filterW or 0)
            if x > 0 and x + w > limit then x = 0; row = row + 1 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", nav, "TOPLEFT", x, -row * (NAV_CHIP_H + NAV_GAP))
            c._section = s
            c._tip = nil
            local title = s.title
            c._onClick = function() UI:ScrollToSection(title); UI:UpdateNavActive() end
            styleChip(c, false)
            c:Show()
            chips[#chips + 1] = c
            x = x + w + NAV_GAP
        end
    end
    UI._navSectionChips = chips
    local h = (row + 1) * (NAV_CHIP_H + NAV_GAP) - NAV_GAP
    nav:SetHeight(h)
    nav:Show()
    return h
end

-- The content column from the top down: nav strip, pinned page header, scroll
-- area -- each one anchored under whichever of the two above it is shown.
-- The nav is inset to the rows' own left edge (scroll inset + CONTENT_PADDING)
-- so its chips line up with the cards below.
local function layoutTop(f, navH, hh)
    local nav, header, scroll = f.pageNav, f.pageHeader, f.scroll
    local top = f.content
    if nav then
        if navH > 0 then
            nav:ClearAllPoints()
            nav:SetPoint("TOPLEFT",  f.content, "TOPLEFT",  8 + CONTENT_PADDING, -10)
            nav:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -20 - CONTENT_PADDING, -10)
            nav:SetHeight(navH)
            nav:Show()
            top = nav
        else
            nav:Hide()
        end
    end
    if header then
        if hh > 0 then
            header:ClearAllPoints()
            if top == f.content then
                header:SetPoint("TOPLEFT",  f.content, "TOPLEFT",  8, -8)
                header:SetPoint("TOPRIGHT", f.content, "TOPRIGHT", -20, -8)
            else
                header:SetPoint("TOPLEFT",  top, "BOTTOMLEFT",  -CONTENT_PADDING, -8)
                header:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", CONTENT_PADDING, -8)
            end
            header:SetHeight(hh)
            header:Show()
            scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
            return
        end
        header:Hide()
    end
    if top == f.content then
        scroll:SetPoint("TOPLEFT", f.content, "TOPLEFT", 8, -8)
    else
        scroll:SetPoint("TOPLEFT", top, "BOTTOMLEFT", -CONTENT_PADDING, -8)
    end
end

-- "Group › Module › Tab" for the title bar. The group is left out where the
-- sidebar never shows it as a heading.
local function crumbText(mod, tabId)
    local parts = {}
    local g = mod.group
    if g and not (UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[g]) then
        parts[#parts + 1] = L[g]
    end
    parts[#parts + 1] = L[mod.name]
    if mod.tabs and (#mod.tabs > 1 or mod.tabsAlways) then
        for _, t in ipairs(mod.tabs) do
            if t.id == tabId then parts[#parts + 1] = L[t.label]; break end
        end
    end
    return table.concat(parts, "  \226\128\186  ")
end

-- Rebuild whatever page is open, without knowing which one that is. Used when
-- something outside the page changes how it must be drawn -- entering or leaving
-- the talent-override editing mode, for one.
function UI:RebuildCurrentPage()
    local key = UI.currentModule
    if not key or key == UI.DASHBOARD_KEY then return end
    UI:BuildOptionsPage(key, UI.currentTab)
end

function UI:BuildOptionsPage(key, tabId)
    local f = UI.mainFrame
    if not f then return end
    -- A rebuild pulls the row the panel hangs off out from under it, and the
    -- panel's own setters close over the OLD spec table. Closing first also
    -- hands its rows back to the pools before the page asks for them.
    closeRowPopup()
    -- The dropdown menu too, and for the same reason: it is parented to
    -- UIParent and anchored to a widget the rebuild is about to hand back to
    -- the pool, so an open one would be left hanging over the page pointing at
    -- nothing. A single-select menu closes itself on the first click and rarely
    -- outlived a rebuild; a multi-select one is meant to stay open, so this is
    -- now the ordinary case rather than the rare one.
    if UI.CloseDropdownPopup then UI.CloseDropdownPopup() end
    -- a sub-module redirects to its container + own tab, so rebuildPage("itskey") keeps working
    local m0 = ns.modules[key]
    if m0 and m0.parentTab then
        tabId = key
        key   = m0.parentTab
    end
    local mod = ns.modules[key]
    if not mod then return end

    local parent = f.scrollChild
    clearChildren(parent)
    parent:SetWidth((f.scroll:GetWidth() or 540) - 8)
    UI._currentBuildKey = key
    -- Section positions of THIS build, for ScrollToSection below.
    UI._sectionY = {}
    UI._sectionList = {}
    UI._rowFrames   = {}
    if UI.SetCrumb then UI:SetCrumb(crumbText(mod, tabId)) end

    -- Pinned page header: a module that defines BuildPageHeader(host) gets the
    -- strip above the scroll area, visible at every scroll position. For every
    -- other module the header hides and the scroll takes its old top anchor.
    local header = f.pageHeader
    local hh = 0
    if header then
        -- More than one module pins a frame into this ONE shared host now
        -- (cooldown manager strip, action-bar picker + preview). Each child
        -- belongs to its module; hiding them all here means only the current
        -- module's builder shows its own again -- without this, switching
        -- pages stacked one module's header over the other's.
        for _, child in ipairs({ header:GetChildren() }) do child:Hide() end
        if mod.BuildPageHeader then
            -- tabId rides along: a header may only belong to SOME tabs (the
            -- cooldown manager's preview has no business over the power bar)
            local ok, res = pcall(mod.BuildPageHeader, header, tabId)
            if ok then hh = tonumber(res) or 0
            else ns:Print(L["|cffff5555Options page '%s' failed to build:|r %s"], tostring(mod.key or mod.name), tostring(res)) end
        end
        -- Anchored below, in layoutTop, once the nav strip's height is known.
    end

    local y = -8

    -- mod.description is a raw English key, translated live
    if mod.description and mod.description ~= "" then
        local pw = parent:GetWidth()
        if not pw or pw < 100 then pw = 540 end
        local desc = OB.createWidget(parent, {
            type  = "desc",
            text  = L[mod.description],
            width = pw - 2 * CONTENT_PADDING,
        })
        desc:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        y = y - math.max(20, desc:GetDescHeight() + 8)
    end

    -- clearChildren() already ran, so an error here would leave a blank page with
    -- no height and no explanation. The other two GetOptions call sites (the tab
    -- container and the settings search index) have always guarded; this one is
    -- the path the user actually walks.
    local items
    if mod.GetOptions then
        local ok, result = ns.ModuleOptions(mod, tabId)
        if ok then
            items = result
        else
            ns:Print(L["|cffff5555Options page '%s' failed to build:|r %s"], tostring(mod.key or mod.name), tostring(result))
            items = { { type = "desc", text = L["|cffff5555This page could not be built. /reload, and report it if it persists.|r"] } }
        end
    end
    if type(items) ~= "table" then items = {} end

    -- One interception point for every widget type: the item table is what the
    -- widgets read `set` from, so wrapping it here covers checkbox, slider,
    -- dropdown and editbox at once. The items are freshly built by GetOptions on
    -- every page build, so the wrapper never stacks.
    -- The profile page is excluded outright: which profile is active, and the
    -- switch that starts the recording itself, must never become
    -- per-talent-group values. Without it the recording switch records itself
    -- the moment it is turned on, and the talent switch then replays it.
    --
    -- CORRECTED: the guard was `key ~= "profiles"` and never fired. That page is
    -- not reached under its own name -- the tab is "profile", the module is
    -- "profiles", and BuildOptionsPage gets the CONTAINER. Measured in game
    -- while the page was open: key: globalsettings, tab: profile. The same
    -- one-letter trap cost two wrong diagnoses on optionsGrid (6576bff); it is
    -- spelled out here rather than derived, because there is nothing to derive
    -- it from: ns.modules["profile"] does not exist.
    local isProfilePage = (key == "profiles") or (tabId == "profile")

    if ns.NoteOverrideWrite then
        local function wrap(list)
            for _, it in ipairs(list) do
                if type(it) == "table" then
                    if it.items then wrap(it.items) end
                    -- subOptions too: a row behind a gear is an ordinary
                    -- setting that happens to be folded away. Without this it
                    -- silently records nothing and never shows the accent bar --
                    -- which was already true for the six on the cooldown page
                    -- and the ones on the trinket page, long before the
                    -- nameplates were folded up.
                    if it.subOptions then wrap(it.subOptions) end
                    -- Colours used to be excluded here. They are three values
                    -- through a setter that takes no self, which is why they
                    -- were skipped -- but skipping meant changing one while
                    -- editing a group did nothing and said nothing. Both shapes
                    -- are handled now; ns:NoteOverrideWrite needs the type to
                    -- know it may keep the table (as a copy).
                    if type(it.set) == "function" and type(it.get) == "function"
                       and it.label
                       and not it.noOverride and not isProfilePage then
                        local id       = ns:OverrideId(key, tabId, it.label)
                        local setter   = it.set
                        local getter   = it.get
                        local itemType = it.type
                        it._vcOverrideId = id
                        it.set = function(...)
                            setter(...)
                            -- read back rather than read the arguments: what the
                            -- module chose to store is the value that matters
                            ns:NoteOverrideWrite(id, getter, itemType)
                        end
                    end
                end
            end
        end
        wrap(items)
    end

    -- Which rows differ from their defaults, and the change log every setter
    -- reports into. Neither on the profile page: which profile is active is
    -- not a setting with a default, and the switch that records overrides
    -- must not be listed as a change of the profile.
    local changedN = markChanged(items, isProfilePage)
    wrapRecent(items, key, tabId, isProfilePage)

    -- Grid pages decide their column count and their label column ONCE, here,
    -- so every row on the page lines up with every other. Cleared afterwards:
    -- other callers of the placement helpers (the edit-mode toolbar) must not
    -- inherit a page's grid.
    -- Read off the module whose GetOptions produced these items, which on a
    -- container page is NOT `mod`: `mod` is the container and the items came
    -- from the tab. The profile page is a tab of the global-settings container,
    -- so the flag was looked up on the container, found nothing, and the grid
    -- stayed off -- nine class rows in two columns with the ninth stretched
    -- across the page, and every dropdown box starting a few pixels off the one
    -- above it.
    -- optionsGrid is either `true` for the whole page, or a table keyed by tab
    -- id. The table exists because a tab is NOT always a module: the profile
    -- page is the "profile" tab of Modules/GlobalSettings, which owns the tab
    -- and only delegates the options -- there is no module of that name to hang
    -- a flag on. Looking the tab up in ns.modules therefore found nothing and
    -- silently fell back to the container, which is why the grid never switched
    -- on there however often the flag was moved.
    local gridMod  = (tabId and ns.modules and ns.modules[tabId]) or mod
    local wantGrid = gridMod.optionsGrid
    if type(wantGrid) == "table" then wantGrid = tabId and wantGrid[tabId] end
    -- The grid is the house rule for every page (the player's call,
    -- 2026-10-10): a setting alone on its line keeps its half, so every
    -- switch and box sits on the same line as the ones above and below.
    -- A page opts OUT with optionsGrid = false (or false for its tab).
    if wantGrid == nil then wantGrid = true end
    UI._grid = nil
    local pw = parent:GetWidth()
    if not pw or pw < 100 then pw = 540 end
    local availW = pw - 2 * CONTENT_PADDING
    if wantGrid then
        UI._grid = { cols = 2, labelCol = pageLabelColumn(items, availW) }
    end
    -- Measured on every page, grid or not: the ragged edge it fixes has nothing
    -- to do with the grid opt-in.
    UI._soloCol = soloLabelColumn(items, availW)

    UI._building = true
    UI._sectionDepth = 0
    local okPlace, res = pcall(placeItemList, parent, items, y)
    UI._building = false
    UI._grid = nil
    UI._soloCol = nil
    if okPlace then
        y = res
    else
        ns:Print(L["|cffff5555Options page '%s' failed to build:|r %s"], tostring(mod.key or mod.name), tostring(res))
    end

    if UI.onlyChanged and changedN == 0 then
        local note = OB.createWidget(parent, { type = "desc",
            text = L["Nothing on this page differs from its defaults."], width = availW })
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y - 4)
        y = y - math.max(24, note:GetDescHeight() + 10)
    end

    local totalHeight = math.max(400, math.abs(y) + 20)
    parent:SetHeight(totalHeight)

    layoutTop(f, layoutPageNav(f, changedN), hh)
    UI:UpdateNavActive()
end
