-- VuloForeverUI / UI / Dashboard
--
-- The overview used to be a card per module, grouped exactly like the sidebar:
-- a second sidebar that answered "which modules exist" -- a question the sidebar
-- had already answered -- and nothing about the state of anything.
--
-- It answers "how does my interface stand right now" instead. Everything on it
-- is measured, never decorative: frame time and peak from the client's own addon
-- profiler, memory from the addon list API, the mover registry for windows, the
-- module registry for what is running. A number we cannot obtain is left out
-- rather than faked.
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local PAD        = 14
local STAT_H     = 62
local STAT_GAP   = 10
local SEARCH_H   = 34
local RECENT_MAX = 6

UI.DASHBOARD_KEY = "__dashboard__"

local HIDDEN_GROUPS = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }

local function clearDashboard(parent)
    -- must clear via OptionsBuilder: module pages leave POOLED widgets here that
    -- have to be released back into their pools, not just detached
    if UI.ClearOptionsChildren then
        UI.ClearOptionsChildren(parent)
        return
    end
    for _, child in ipairs({ parent:GetChildren() }) do
        if child ~= UI._dashContainer then
            child:Hide()
            child:SetParent(nil)
            child:ClearAllPoints()
        end
    end
    for _, r in ipairs({ parent:GetRegions() }) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
end

-- =========================================================================
-- Measurements. Each returns a display string, or nil when this client cannot
-- provide the number -- the caller then hides that line instead of printing a
-- zero that would read as "free".
-- =========================================================================

local function statFrameTime()
    local P, E = _G.C_AddOnProfiler, (_G.Enum and _G.Enum.AddOnProfilerMetric)
    if not (P and E and P.GetAddOnMetric) then return nil end
    local ok, own = pcall(P.GetAddOnMetric, ns.NAME, E.RecentAverageTime)
    if not ok or type(own) ~= "number" then return nil end
    local peak = select(2, pcall(P.GetAddOnMetric, ns.NAME, E.PeakTime))
    local sub
    if type(peak) == "number" and peak > 0 then
        sub = string.format(L["peak %.1f ms"], peak)
    end
    return string.format(L["%.2f ms"], own), sub
end

local function statMemory()
    local upd, get = UpdateAddOnMemoryUsage, GetAddOnMemoryUsage
    pcall(upd)
    local ok, kb = pcall(get, ns.NAME)
    if not ok or type(kb) ~= "number" or kb <= 0 then return nil end
    if kb >= 1024 then return string.format(L["%.1f MB"], kb / 1024) end
    return string.format(L["%d KB"], math.floor(kb + 0.5))
end

-- "moved" = the mover carries a stored offset, i.e. the frame is not where the
-- addon put it. Movers without a db of their own cannot be counted and are not.
local function statWindows()
    local movers = ns._movers
    if not movers or #movers == 0 then return nil end
    local moved = 0
    for i = 1, #movers do
        local db = movers[i] and movers[i].db
        if db and ((tonumber(db.x) or 0) ~= 0 or (tonumber(db.y) or 0) ~= 0) then
            moved = moved + 1
        end
    end
    return string.format(L["%d of %d"], moved, #movers), L["moved"]
end

local function countModules()
    local total, active = 0, 0
    for _, key in ipairs(ns.moduleOrder) do
        local m = ns.modules[key]
        if m and not HIDDEN_GROUPS[m.group or "Core"] and not m.noToggle and not m.parentTab then
            total = total + 1
            local on
            if m.toggleGet then on = m.toggleGet() else on = ns:IsModuleEnabled(key) end
            if on then active = active + 1 end
        end
    end
    return active, total
end

-- Only things the reader can act on, and only when they are actually true.
local function collectHints()
    local out = {}
    local active, total = countModules()
    if total - active > 0 then
        out[#out + 1] = string.format(L["%d modules are switched off."], total - active)
    end
    local em = ns.db and ns.db.profile and ns.db.profile.editmode
    if em and em.grid and em.grid.show then
        out[#out + 1] = L["The edit mode grid is switched on."]
    end
    if ns.db and ns.db.global and ns.db.global.patchNotesSeen ~= ns.VERSION then
        out[#out + 1] = L["There are patch notes you have not read yet."]
    end
    return out
end

-- =========================================================================
-- Recently visited. Written by UI:ShowModulePage; account-wide, because which
-- pages you work on is a habit, not a per-character setting.
-- =========================================================================

function UI:NoteVisitedPage(key)
    if not key or key == UI.DASHBOARD_KEY then return end
    local g = ns.db and ns.db.global
    if not g then return end
    local list = g.recentPages
    if not list then list = {}; g.recentPages = list end
    for i = #list, 1, -1 do
        if list[i] == key then table.remove(list, i) end
    end
    table.insert(list, 1, key)
    for i = #list, RECENT_MAX + 1, -1 do table.remove(list, i) end
end

-- =========================================================================
-- Widgets
-- =========================================================================

local function createStatCard(parent)
    local card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetHeight(STAT_H)

    if card.SetBackdrop then
        card:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        card:SetBackdropColor(0.09, 0.09, 0.115, 0.95)
        local b = ns.COLORS.borderDark
        card:SetBackdropBorderColor(b.r, b.g, b.b, 1)
    end

    local edge = card:CreateTexture(nil, "ARTWORK")
    edge:SetPoint("TOPLEFT", card, "TOPLEFT", 1, -1)
    edge:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 1, 1)
    edge:SetWidth(2)
    local a = ns.COLORS.accent
    edge:SetColorTexture(a.r, a.g, a.b, 0.9)

    card.label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    UI.Font(card.label, 10)
    card.label:SetPoint("TOPLEFT", card, "TOPLEFT", 11, -9)
    local s = ns.COLORS.sectionHdr
    card.label:SetTextColor(s.r, s.g, s.b)

    card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    UI.Font(card.value, 17)
    card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -4)
    card.value:SetTextColor(0.94, 0.92, 0.98)

    card.sub = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(card.sub, 10)
    card.sub:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 9)
    local d = ns.COLORS.textMuted
    card.sub:SetTextColor(d.r, d.g, d.b)

    return card
end

local function createChip(parent)
    local chip = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    chip:SetHeight(24)
    if chip.SetBackdrop then
        chip:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        chip:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
        local b = ns.COLORS.border
        chip:SetBackdropBorderColor(b.r, b.g, b.b, 0.5)
    end
    local hl = chip:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(chip)
    hl:SetColorTexture(1, 1, 1, 0.05)

    chip.icon = chip:CreateTexture(nil, "ARTWORK")
    chip.icon:SetSize(13, 13)
    chip.icon:SetPoint("LEFT", chip, "LEFT", 7, 0)
    chip.icon:SetDesaturated(true)
    chip.icon:SetVertexColor(0.76, 0.76, 0.84)

    chip.text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(chip.text, 11)
    chip.text:SetPoint("LEFT", chip.icon, "RIGHT", 6, 0)
    chip.text:SetTextColor(0.85, 0.85, 0.9)

    chip:SetScript("OnClick", function(self)
        if self._key and UI.ShowModulePage then UI:ShowModulePage(self._key) end
    end)
    return chip
end

-- One line of the "recently changed" list: the path to the setting on the
-- left, how long ago on the right. A click reveals the row (UI:RevealRow).
local function createChangeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(20)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.05)

    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    UI.Font(row.when, 10)
    row.when:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.when:SetJustifyH("RIGHT")
    local d = ns.COLORS.textMuted
    row.when:SetTextColor(d.r, d.g, d.b)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.Font(row.text, 11)
    row.text:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.text:SetPoint("RIGHT", row.when, "LEFT", -10, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)

    row:SetScript("OnClick", function(self)
        local e = self._entry
        if not (e and UI.RevealRow) then return end
        -- Entries hold English keys; the page's row keys are the translated
        -- labels, so everything is put through L on the way to the row.
        local parents
        if type(e.parents) == "table" then
            parents = {}
            for i, v in ipairs(e.parents) do parents[i] = L[tostring(v)] end
        end
        UI:RevealRow({
            mod = e.mod, tab = e.tab, subKey = e.subKey,
            label = e.label and L[tostring(e.label)] or nil,
            section = e.section and L[tostring(e.section)] or nil,
            parents = parents,
        })
    end)
    return row
end

local function timeAgo(t)
    local d = (time() or 0) - (tonumber(t) or 0)
    if d < 60 then return L["just now"] end
    if d < 3600 then return string.format(L["%d min ago"], math.floor(d / 60)) end
    if d < 86400 then return string.format(L["%d h ago"], math.floor(d / 3600)) end
    return string.format(L["%d d ago"], math.floor(d / 86400))
end

local PATH_SEP = "  \194\187  "
local function changePath(e)
    local m = ns.modules[e.mod]
    if not m then return nil end
    local parts = { L[m.name] }
    if e.tab and e.tab ~= "default" and m.tabs and #m.tabs > 1 then
        for _, t in ipairs(m.tabs) do
            if t.id == e.tab then parts[#parts + 1] = L[t.label]; break end
        end
    end
    if e.section then parts[#parts + 1] = L[tostring(e.section)] end
    local path = table.concat(parts, PATH_SEP)
    return string.format("|cff8a8a96%s|r%s%s", path, PATH_SEP, L[tostring(e.label or "")])
end

-- The prompt does not search by itself: it hands focus and text to the real
-- search box in the title bar, which already owns the matching and the result
-- list. Two implementations of the same search would drift apart.
local function createSearchPrompt(parent)
    local box = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    box:SetHeight(SEARCH_H)
    if box.SetBackdrop then
        box:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        box:SetBackdropColor(0.10, 0.10, 0.13, 0.95)
        local a = ns.COLORS.accent
        box:SetBackdropBorderColor(a.r, a.g, a.b, 0.35)
    end
    local hl = box:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(box)
    hl:SetColorTexture(1, 1, 1, 0.04)

    local icon = box:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", box, "LEFT", 11, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(0.7, 0.7, 0.78)

    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(text, 12)
    text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    text:SetText(L["What would you like to change?"])
    local d = ns.COLORS.textMuted
    text:SetTextColor(d.r, d.g, d.b)

    box:SetScript("OnClick", function()
        local f = UI.mainFrame
        if f and f.searchBox then
            f.searchBox:SetFocus()
        end
    end)
    return box
end

-- =========================================================================

function UI:ShowDashboard()
    local f = UI.mainFrame
    if not f then return end

    UI.currentModule = UI.DASHBOARD_KEY
    UI.currentTab    = nil

    -- No tab column on this page, so the content pane spans the full width.
    if f.tabBar then f.tabBar:Hide() end
    if f.tabSep then f.tabSep:Hide() end
    if f.tabColumn then f.tabColumn:Hide() end
    if UI.ReleaseTabs then UI:ReleaseTabs() end
    -- The pinned page header belongs to module pages. Reopening the window
    -- lands here with the LAST page's strip (say the cooldown-manager
    -- preview) still mounted in the shared host, floating over the
    -- dashboard -- only BuildOptionsPage ever evicted it. Same rollback as
    -- the builder's no-header branch: hide the host and every tenant, and
    -- take the scroll's plain top anchor back (the hidden host keeps its
    -- rect, so an anchor onto it would still indent the page).
    if f.pageHeader then
        for _, child in ipairs({ f.pageHeader:GetChildren() }) do child:Hide() end
        f.pageHeader:Hide()
        f.scroll:SetPoint("TOPLEFT", f.content, "TOPLEFT", 8, -8)
    end
    -- The jump strip belongs to a module page as much as the header does.
    if f.pageNav then
        f.pageNav:Hide()
        f.scroll:SetPoint("TOPLEFT", f.content, "TOPLEFT", 8, -8)
    end
    if UI.SetCrumb then UI:SetCrumb(L["Overview"]) end
    f.content:ClearAllPoints()
    f.content:SetPoint("TOPLEFT",     f.sidebar, "TOPRIGHT",  1, 0)
    f.content:SetPoint("BOTTOMRIGHT", f,         "BOTTOMRIGHT", 0, 44)

    local parent = f.scrollChild
    clearDashboard(parent)
    parent:SetWidth((f.scroll:GetWidth() or 540) - 8)
    if f.scroll.SetVerticalScroll then f.scroll:SetVerticalScroll(0) end

    if UI.RefreshSidebarStates then UI:RefreshSidebarStates() end

    -- module pages orphan this container via SetParent(nil) -- re-adopt it below
    local cont = UI._dashContainer
    if not cont then
        cont = CreateFrame("Frame", nil, parent)
        UI._dashContainer = cont
        UI._dashStats  = {}
        UI._dashHints  = {}
        UI._dashChips  = {}

        cont.title = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        UI.Font(cont.title, 16)
        cont.title:SetTextColor(0.92, 0.90, 0.96)

        cont.who = cont:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        UI.Font(cont.who, 11)
        cont.who:SetTextColor(ns.COLORS.textDim.r, ns.COLORS.textDim.g, ns.COLORS.textDim.b)

        cont.search = createSearchPrompt(cont)

        cont.hintHdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        UI.Font(cont.hintHdr, 10)
        cont.hintHdr:SetTextColor(ns.COLORS.sectionHdr.r, ns.COLORS.sectionHdr.g, ns.COLORS.sectionHdr.b)

        cont.recentHdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        UI.Font(cont.recentHdr, 10)
        cont.recentHdr:SetTextColor(ns.COLORS.sectionHdr.r, ns.COLORS.sectionHdr.g, ns.COLORS.sectionHdr.b)
    end
    cont:SetParent(parent)
    cont:ClearAllPoints()
    cont:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    cont:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    cont:Show()

    for _, c in pairs(UI._dashStats) do c:Hide() end
    for _, h in pairs(UI._dashHints) do h:Hide() end
    for _, c in pairs(UI._dashChips) do c:Hide() end

    -- GetWidth returns 0, not nil, before the first layout pass -- `or 540`
    -- would not catch that and the cards would come out one pixel wide.
    local width = parent:GetWidth()
    if not width or width < 200 then width = 540 end
    local y = -10

    -- ---- who and what -------------------------------------------------
    cont.title:ClearAllPoints()
    cont.title:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD, y)
    cont.title:SetText(L["Overview"])

    local name = (UnitName and UnitName("player")) or "?"
    -- UnitClass's FIRST return is already the localized name. Writing this as
    -- `local _, c = UnitClass and UnitClass("player")` would silently truncate
    -- the call to one value and leave c nil for everyone.
    local className
    if UnitClass then
        local ok, localized = pcall(UnitClass, "player")
        if ok and type(localized) == "string" then className = localized end
    end
    local profile = ns.GetActiveProfileName and ns:GetActiveProfileName() or nil
    local who = name
    if className then who = who .. "  |cff555560\226\128\162|r  " .. className end
    if profile then who = who .. "  |cff555560\226\128\162|r  " .. profile end
    who = who .. "  |cff555560\226\128\162|r  " .. tostring(ns.VERSION)
    cont.who:ClearAllPoints()
    cont.who:SetPoint("LEFT", cont.title, "RIGHT", 12, -1)
    cont.who:SetText(who)

    y = y - 34

    -- ---- search prompt -------------------------------------------------
    cont.search:ClearAllPoints()
    cont.search:SetPoint("TOPLEFT",  cont, "TOPLEFT",  PAD, y)
    cont.search:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -PAD, y)
    cont.search:Show()
    y = y - SEARCH_H - 16

    -- ---- measured cards -------------------------------------------------
    local active, total = countModules()
    local ftVal, ftSub  = statFrameTime()
    local winVal, winSub = statWindows()

    local stats = {
        { id = "modules", label = L["Modules"],    value = string.format(L["%d of %d"], active, total), sub = L["active"] },
        { id = "frame",   label = L["Frame time"], value = ftVal,  sub = ftSub },
        { id = "memory",  label = L["Memory"],     value = statMemory() },
        { id = "windows", label = L["Windows"],    value = winVal, sub = winSub },
    }

    local shown = {}
    for _, s in ipairs(stats) do
        if s.value then shown[#shown + 1] = s end
    end

    if #shown > 0 then
        local cardW = math.floor((width - 2 * PAD - (#shown - 1) * STAT_GAP) / #shown)
        for i, s in ipairs(shown) do
            local card = UI._dashStats[s.id]
            if not card then
                card = createStatCard(cont)
                UI._dashStats[s.id] = card
            end
            card:SetWidth(cardW)
            card.label:SetText(string.upper(s.label))
            card.value:SetText(s.value)
            card.sub:SetText(s.sub or "")
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD + (i - 1) * (cardW + STAT_GAP), y)
            card:Show()
        end
        y = y - STAT_H - 20
    end

    -- ---- hints -------------------------------------------------
    local hints = collectHints()
    if #hints > 0 then
        cont.hintHdr:ClearAllPoints()
        cont.hintHdr:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD, y)
        cont.hintHdr:SetText(string.upper(L["Worth knowing"]))
        cont.hintHdr:Show()
        y = y - 20

        for i, textValue in ipairs(hints) do
            local fs = UI._dashHints[i]
            if not fs then
                fs = cont:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                UI.Font(fs, 11)
                fs:SetJustifyH("LEFT")
                UI._dashHints[i] = fs
            end
            fs:SetText("|cff9b6cff\226\128\162|r  " .. textValue)
            fs:SetTextColor(0.78, 0.78, 0.84)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD + 2, y)
            fs:Show()
            y = y - 18
        end
        y = y - 14
    else
        cont.hintHdr:Hide()
    end

    -- ---- recently visited -------------------------------------------------
    local recent = ns.db and ns.db.global and ns.db.global.recentPages
    local chips = 0
    if recent then
        cont.recentHdr:ClearAllPoints()
        cont.recentHdr:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD, y)
        cont.recentHdr:SetText(string.upper(L["Recently visited"]))

        local x = PAD
        for _, key in ipairs(recent) do
            local m = ns.modules[key]
            if m then
                chips = chips + 1
                local chip = UI._dashChips[chips]
                if not chip then
                    chip = createChip(cont)
                    UI._dashChips[chips] = chip
                end
                chip._key = key
                chip.icon:SetTexture(ns:GetModuleIcon(key))
                chip.text:SetText(L[m.name])
                local w = (chip.text:GetStringWidth() or 60) + 34
                chip:SetWidth(w)
                chip:ClearAllPoints()
                chip:SetPoint("TOPLEFT", cont, "TOPLEFT", x, y - 22)
                chip:Show()
                x = x + w + 8
            end
        end
    end
    if chips > 0 then
        cont.recentHdr:Show()
        y = y - 22 - 24 - 10
    else
        cont.recentHdr:Hide()
    end

    -- ---- recently changed -------------------------------------------------
    -- What was touched last, with a way back to it. The list the settings
    -- pages write into (UI/OptionsBuilder.lua); entries whose module is gone
    -- are skipped rather than shown as dead links.
    UI._dashChangeRows = UI._dashChangeRows or {}
    for _, r in ipairs(UI._dashChangeRows) do r:Hide() end
    if not cont.changedHdr then
        cont.changedHdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        UI.Font(cont.changedHdr, 10)
        cont.changedHdr:SetTextColor(ns.COLORS.sectionHdr.r, ns.COLORS.sectionHdr.g, ns.COLORS.sectionHdr.b)
    end
    local changes = ns.db and ns.db.global and ns.db.global.recentChanges
    local shownChanges = 0
    if type(changes) == "table" and #changes > 0 then
        cont.changedHdr:ClearAllPoints()
        cont.changedHdr:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD, y)
        cont.changedHdr:SetText(string.upper(L["Recently changed"]))
        local ry = y - 20
        for _, e in ipairs(changes) do
            if shownChanges >= 8 then break end
            local text = type(e) == "table" and changePath(e)
            if text then
                shownChanges = shownChanges + 1
                local row = UI._dashChangeRows[shownChanges]
                if not row then
                    row = createChangeRow(cont)
                    UI._dashChangeRows[shownChanges] = row
                end
                row._entry = e
                row.text:SetText(text)
                row.when:SetText(timeAgo(e.t))
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",  cont, "TOPLEFT",  PAD, ry)
                row:SetPoint("TOPRIGHT", cont, "TOPRIGHT", -PAD, ry)
                row:Show()
                ry = ry - 20
            end
        end
        if shownChanges > 0 then
            cont.changedHdr:Show()
            y = ry - 12
        end
    end
    if shownChanges == 0 then cont.changedHdr:Hide() end

    -- ---- modules by area -------------------------------------------------
    -- Every sidebar group with its rows as chips, so the whole suite fits on
    -- one screen: the sidebar lists it top to bottom, this lays it out side
    -- by side. Same order and the same "3/7" as the sidebar headings.
    UI._dashGroupHdrs = UI._dashGroupHdrs or {}
    for _, h in ipairs(UI._dashGroupHdrs) do h:Hide() end
    local groups = 0
    local buckets = UI.sidebarGroupBuckets or {}
    local order   = UI.sidebarGroupOrder or {}
    local first = true
    for _, groupName in ipairs(order) do
        local keys = buckets[groupName]
        local hidden = UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[groupName]
        if keys and #keys > 0 and not hidden then
            if first then
                if not cont.areasHdr then
                    cont.areasHdr = cont:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    UI.Font(cont.areasHdr, 10)
                    cont.areasHdr:SetTextColor(ns.COLORS.sectionHdr.r, ns.COLORS.sectionHdr.g, ns.COLORS.sectionHdr.b)
                end
                cont.areasHdr:ClearAllPoints()
                cont.areasHdr:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD, y)
                cont.areasHdr:SetText(string.upper(L["Modules by area"]))
                cont.areasHdr:Show()
                y = y - 22
                first = false
            end
            groups = groups + 1
            local hdr = UI._dashGroupHdrs[groups]
            if not hdr then
                hdr = cont:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                UI.Font(hdr, 11)
                UI._dashGroupHdrs[groups] = hdr
            end
            local on = 0
            for _, key in ipairs(keys) do
                local m = ns.modules[key]
                local isOn
                if m and m.toggleGet then isOn = m.toggleGet() else isOn = ns:IsModuleEnabled(key) end
                if isOn then on = on + 1 end
            end
            hdr:SetText(string.format("%s  %s%d/%d|r", L[groupName],
                (ns.C and ns.C.accent) or "|cff9b6cff", on, #keys))
            hdr:SetTextColor(0.85, 0.85, 0.9)
            hdr:ClearAllPoints()
            hdr:SetPoint("TOPLEFT", cont, "TOPLEFT", PAD + 2, y)
            hdr:Show()
            y = y - 18

            local x, row = PAD, 0
            for _, key in ipairs(keys) do
                local m = ns.modules[key]
                if m then
                    chips = chips + 1
                    local chip = UI._dashChips[chips]
                    if not chip then
                        chip = createChip(cont)
                        UI._dashChips[chips] = chip
                    end
                    chip._key = key
                    chip.icon:SetTexture(ns:GetModuleIcon(key))
                    chip.text:SetText(L[m.name])
                    local w = (chip.text:GetStringWidth() or 60) + 34
                    if x > PAD and x + w > width - PAD then
                        x = PAD
                        row = row + 1
                    end
                    chip:SetWidth(w)
                    chip:ClearAllPoints()
                    chip:SetPoint("TOPLEFT", cont, "TOPLEFT", x, y - row * 30)
                    chip:Show()
                    x = x + w + 8
                end
            end
            y = y - (row + 1) * 30 - 6
        end
    end
    if groups > 0 then y = y - 6 elseif cont.areasHdr then cont.areasHdr:Hide() end

    cont:SetHeight(math.max(-y + 20, 100))
    parent:SetHeight(math.max(-y + 20, 100))
end
