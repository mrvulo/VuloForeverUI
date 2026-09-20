-- VuloForeverUI / UI / Sidebar: module list grouped under headers, each with a power toggle.
local _, ns = ...
local L = ns.L
ns.UI = ns.UI or {}
local UI = ns.UI

local ROW_HEIGHT     = 28
local GROUP_HEADER_H = 26
local GROUP_GAP      = 8
local SIDEBAR_FILTER_W = 150

-- Bundled monochrome glyphs, tinted at runtime; see Media\Icons\modules\LICENSE.txt.
local ICON_DIR = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\modules\\"
local MODULE_ICONS = {}
for _, key in ipairs({
    -- The four "Tools" containers are not listed here: Modules/Pages.lua points
    -- them at existing glyphs itself, the way the pg_* pages already do.
    "globalsettings", "unlockmode", "bugfixes", "uireskin", "profiles",
    "minimap", "minimapstyle", "fontbars", "playercastbar", "unitframes", "nameplates",
    "cooldownpulse", "cooldownmanager", "powerbar", "actionbars",
    "arenaframes", "characterpanel", "darkskin", "friendlist",
    "miscqol", "queuetimer", "tooltipids", "autoitembuy", "goldtracker",
    "addonskins", "popupskin", "reminders",
    "spamfilter", "chat", "bags", "questlog", "questtracker",
    "professionwindow", "disenchantqueue", "vtmanadisplay", "lazyvulo",
    "vulslot", "combattext", "loadouts", "slotpicker", "trinkets",
    "swingtimer", "vulmail", "vulfishing", "vullfg", "vultraining",
    "fixinspect", "fixlfgbrowsenil", "fixguildnews", "fixauctiondropdown",
    "fixbindsocket", "fixcombatglow",
    -- added 12.09.2026: these had a glyph on disk (or got one now) but were
    -- missing from this list, so the sidebar showed the fallback for them
    "meter", "changelog", "actionring", "auras", "trackbars", "talentview",
    "fixnameplaterole", "casthistory",
}) do
    MODULE_ICONS[key] = ICON_DIR .. key .. ".tga"
end
MODULE_ICONS.minimapcollector = ICON_DIR .. "minimap.tga"   -- shares the minimap glyph
-- The glyph on disk is named after what this page was called before the suite
-- settled on "Edit Mode"; the art is the padlock, which still fits.
MODULE_ICONS.editmode         = ICON_DIR .. "unlockmode.tga"
MODULE_ICONS.damagemeter      = ICON_DIR .. "meter.tga"
local MODULE_ICON_FALLBACK = ICON_DIR .. "_fallback.tga"

ns.MODULE_ICONS = MODULE_ICONS
ns.MODULE_ICON_FALLBACK = MODULE_ICON_FALLBACK
function ns:GetModuleIcon(key)
    return MODULE_ICONS[key] or MODULE_ICON_FALLBACK
end

UI.sidebarButtons     = {}
-- "Tools" holds the four containers that replaced the single "Quality of Life"
-- row (see Modules/Pages.lua) plus "Class Specific". The four category names
-- themselves never appear as headers: their modules carry parentTab and so are
-- collected into the container rows instead of getting rows of their own.
UI.sidebarGroupOrder  = {
    "Global", "Unit Frames", "HUD", "PvP", "Tools", "UI Reskin", "Bugfixes",
}
UI.sidebarHiddenGroups = { ["_hidden"] = true, ["Account"] = true, ["Core"] = true }
UI.sidebarGroupBuckets = {}

-- ui.sidebarCollapsed may still sit in an existing profile from when the groups
-- folded. Nothing reads it now. It is left alone rather than deleted: it never
-- appeared in the defaults tree, so the logout pass does not touch it either
-- way, and a few stale group names cost nothing next to a migration.
local function moduleIsOn(key)
    local mod = ns.modules[key]
    if not mod then return false end
    if mod.toggleGet then return mod.toggleGet() and true or false end
    return ns:IsModuleEnabled(key) and true or false
end

-- "3/7": how many of the group are switched on. Without it a collapsed group
-- says nothing about whether anything inside it is running.
local function applyHeaderCount(header, moduleKeys)
    if not header or not header._count then return end
    local on = 0
    for i = 1, #moduleKeys do
        if moduleIsOn(moduleKeys[i]) then on = on + 1 end
    end
    header._count:SetText(on .. "/" .. #moduleKeys)
    local c = (on > 0) and ns.COLORS.accent or ns.COLORS.textMuted
    header._count:SetTextColor(c.r, c.g, c.b)
end

-- Pinned modules: an account-wide list of keys, in pin order. A pinned module
-- gets a SECOND row in the "Pinned" group at the top and keeps its place in
-- its own group, so the group counts still say what they say.
UI._pinRows = UI._pinRows or {}

local function pinnedList()
    local g = ns.db and ns.db.global
    if not g then return {} end
    if type(g.pinnedModules) ~= "table" then g.pinnedModules = {} end
    return g.pinnedModules
end

local function isPinned(key)
    for _, k in ipairs(pinnedList()) do
        if k == key then return true end
    end
    return false
end

local function togglePin(key)
    local list = pinnedList()
    for i = #list, 1, -1 do
        if list[i] == key then
            table.remove(list, i)
            UI:PopulateSidebar()
            return
        end
    end
    list[#list + 1] = key
    UI:PopulateSidebar()
end

local function paintRow(key, btn)
    local selected = (key == UI.currentModule)
    if selected then
        btn.bg:Show()
        if btn.accentBar then btn.accentBar:Show() end
        btn.label:SetTextColor(1, 1, 1)
    else
        btn.bg:Hide()
        if btn.accentBar then btn.accentBar:Hide() end
        local c = ns.COLORS.textDim
        btn.label:SetTextColor(c.r, c.g, c.b)
    end

    local mod = ns.modules[key]
    local enabled
    if mod and mod.toggleGet then enabled = mod.toggleGet()
    else enabled = mod and ns:IsModuleEnabled(key) end
    if btn.icon then
        btn.icon:SetDesaturated(true)
        if selected then
            local a = ns.COLORS.accent
            btn.icon:SetVertexColor(a.r, a.g, a.b)
            btn.icon:SetAlpha(1)
        elseif enabled then
            btn.icon:SetVertexColor(0.76, 0.76, 0.84)
            btn.icon:SetAlpha(0.95)
        else
            btn.icon:SetVertexColor(0.55, 0.55, 0.6)
            btn.icon:SetAlpha(0.4)
        end
    end
    if not selected and not enabled then
        btn.label:SetTextColor(ns.COLORS.textMuted.r, ns.COLORS.textMuted.g, ns.COLORS.textMuted.b)
    end
    if btn.pin and btn.pin._refresh then btn.pin._refresh() end
end

local function highlightSelected()
    if UI._dashRow then
        local onDash = (UI.currentModule == UI.DASHBOARD_KEY)
        if onDash then UI._dashRow.bg:Show(); UI._dashRow.accentBar:Show()
        else UI._dashRow.bg:Hide(); UI._dashRow.accentBar:Hide() end
    end
    if UI._changelogRow then
        local onCL = (UI.currentModule == "changelog")
        if onCL then UI._changelogRow.bg:Show(); UI._changelogRow.accentBar:Show()
        else UI._changelogRow.bg:Hide(); UI._changelogRow.accentBar:Hide() end
    end

    for key, btn in pairs(UI.sidebarButtons) do paintRow(key, btn) end
    for key, btn in pairs(UI._pinRows) do paintRow(key, btn) end
end

local function createModuleRow(parent, key, mod)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    ns.UI.SetGradient(bg, "HORIZONTAL",
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.26,
        ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.02)
    bg:Hide()
    row.bg = bg

    local accentBar = row:CreateTexture(nil, "ARTWORK")
    accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    accentBar:SetWidth(3)
    accentBar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
    accentBar:Hide()
    row.accentBar = accentBar

    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(1, 1, 1, 0.04)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(MODULE_ICONS[key] or MODULE_ICON_FALLBACK)
    icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)
    row.icon = icon

    row:HookScript("OnEnter", function()
        if UI.currentModule ~= key then icon:SetVertexColor(0.95, 0.95, 1) end
    end)
    row:HookScript("OnLeave", function() highlightSelected() end)

    local power
    if not mod.noToggle then
        power = UI:CreatePowerButton(row, {
            size = 13,
            get = mod.toggleGet or function() return ns:IsModuleEnabled(key) end,
            set = mod.toggleSet or function(v)
                ns:ToggleModule(key, v)
                UI:RefreshSidebarStates()
            end,
            tooltip = L["Enable/disable module"],
        })
        power:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.power = power
    end

    -- The pin, left of the power switch. Faded out until the row is hovered
    -- or the module is pinned -- by alpha, not by hiding: entering the pin
    -- fires the row's OnLeave, and a pin that hid on that would be gone
    -- before it could be clicked.
    local pin = CreateFrame("Button", nil, row)
    pin:SetSize(14, 14)
    if power then
        pin:SetPoint("RIGHT", power, "LEFT", -6, 0)
    else
        pin:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    end
    local pinIcon = pin:CreateTexture(nil, "ARTWORK")
    pinIcon:SetAllPoints(pin)
    pinIcon:SetTexture("Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\pin.tga")
    pin._refresh = function()
        local on = isPinned(key)
        if on then
            local a = ns.COLORS.accent
            pinIcon:SetVertexColor(a.r, a.g, a.b)
            pin:SetAlpha(1)
        else
            pinIcon:SetVertexColor(0.62, 0.62, 0.70)
            pin:SetAlpha(pin._hover and 1 or 0)
        end
    end
    pin:SetScript("OnEnter", function(self)
        self._hover = true
        pinIcon:SetVertexColor(1, 1, 1)
        self:SetAlpha(1)
        UI:ShowTooltip(self, { title = isPinned(key) and L["Unpin"] or L["Pin to the top of the sidebar"] })
    end)
    pin:SetScript("OnLeave", function(self)
        self._hover = false
        UI:HideTooltip()
        self._refresh()
    end)
    pin:SetScript("OnClick", function() togglePin(key) end)
    row:HookScript("OnEnter", function() pin._hover = true; pin._refresh() end)
    row:HookScript("OnLeave", function() pin._hover = false; pin._refresh() end)
    pin._refresh()
    row.pin = pin

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.UI.Font(label, 12)
    label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    label:SetPoint("RIGHT", pin, "LEFT", -6, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(L[mod.name])  -- mod.name is a raw English key, translated live
    row.label = label

    row:SetScript("OnClick", function(self)
        -- A row the filter matched through one of its tabs opens ON that tab.
        local jump = self._jumpTab
        if jump and ns.modules[jump] then
            UI:ShowModulePage(jump)
        else
            UI:ShowModulePage(key)
            if jump and UI.ShowTab then UI:ShowTab(jump) end
        end
    end)

    return row
end

-- The sidebar filter: a module row stays when its name, its group, one of
-- its tabs or one of the modules folded into it (a Tools container) carries
-- the typed text. Returns the tab or member the match came from, if any, so
-- the row can open there.
local function rowMatches(key, mod, filter)
    if filter == "" then return true end
    local function has(s)
        return s and tostring(s):lower():find(filter, 1, true) ~= nil
    end
    if has(L[mod.name]) or has(mod.name) then return true end
    if mod.group and has(L[mod.group]) then return true end
    for _, k in ipairs(ns.moduleOrder) do
        local m = ns.modules[k]
        if m and m.parentTab == key and (has(L[m.name]) or has(m.name)) then
            return true, k
        end
    end
    if mod.tabs then
        for _, t in ipairs(mod.tabs) do
            if has(L[t.label]) then return true, t.id end
        end
    end
    return false
end

local function ensureFilterBox(f)
    if UI._sidebarFilterBox then return UI._sidebarFilterBox end
    local box = UI:CreateSearchBox(f.sidebar, {
        width = SIDEBAR_FILTER_W,
        onText = function(self)
            local q = (self:GetText() or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if q == UI._sidebarFilter then return end
            UI._sidebarFilter = q
            if self._placeholder then self._placeholder:SetShown(q == "") end
            UI:PopulateSidebar()
        end,
    })
    box:SetHeight(20)
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT",  f.sidebar, "TOPLEFT",  6, -6)
    box:SetPoint("TOPRIGHT", f.sidebar, "TOPRIGHT", -6, -6)
    local ph = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    ns.UI.Font(ph, 11)
    ph:SetPoint("LEFT", box, "LEFT", 22, 0)
    ph:SetTextColor(0.45, 0.45, 0.52)
    box._placeholder = ph
    -- the list moves down under the box
    f.sidebarScroll:SetPoint("TOPLEFT", f.sidebar, "TOPLEFT", 6, -32)
    UI._sidebarFilterBox = box
    return box
end

-- A group heading, and nothing more. The plus/minus box is gone, together with
-- the folding it drove: the options window now folds in exactly one place, the
-- gear on a row, and the sidebar handing you a second, differently shaped
-- expander was the reason that stopped reading as one idea.
--
-- No Button, no hover tint either -- a row that highlights under the cursor
-- claims to be clickable.
local function createGroupHeader(parent, groupName)
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(GROUP_HEADER_H)

    local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(fs, 10)
    fs:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 2)
    fs:SetText(string.upper(L[groupName]))
    local c = ns.COLORS.sectionHdr
    fs:SetTextColor(c.r, c.g, c.b)
    h._label = fs

    local count = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ns.UI.Font(count, 10)
    count:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 4)
    h._count = count

    local line = h:CreateTexture(nil, "ARTWORK")
    line:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 0)
    line:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 0)
    line:SetHeight(1)
    ns.UI.SetGradient(line, "HORIZONTAL",
        0.32, 0.32, 0.38, 0.45,
        0.32, 0.32, 0.38, 0.0)

    h._group = groupName
    return h
end

local function rebuildBuckets()
    UI.sidebarGroupBuckets = {}
    local origIndex = {}   -- registration order: stable-sort tiebreaker
    for i, key in ipairs(ns.moduleOrder) do
        local mod = ns.modules[key]
        origIndex[key] = i
        if not mod.parentTab then   -- sub-modules show as tabs, not rows
            local g = mod.group or "Core"
            if not UI.sidebarGroupBuckets[g] then
                UI.sidebarGroupBuckets[g] = {}
            end
            table.insert(UI.sidebarGroupBuckets[g], key)
        end
    end

    for _, bucket in pairs(UI.sidebarGroupBuckets) do
        table.sort(bucket, function(a, b)
            local oa = ns.modules[a].sidebarOrder or 0
            local ob = ns.modules[b].sidebarOrder or 0
            if oa ~= ob then return oa < ob end
            return origIndex[a] < origIndex[b]
        end)
    end

    local seen = {}
    for _, g in ipairs(UI.sidebarGroupOrder) do seen[g] = true end
    for g in pairs(UI.sidebarGroupBuckets) do
        if not seen[g] and not (UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[g]) then
            table.insert(UI.sidebarGroupOrder, g)
        end
    end
end

function UI:PopulateSidebar()
    local f = UI.mainFrame
    if not f then return end
    local parent = f.sidebarContent

    -- Frames are never garbage-collected: rows are pooled and re-shown, never recreated.
    if UI._sidebarChildren then
        for _, c in ipairs(UI._sidebarChildren) do c:Hide() end
    end
    UI._sidebarChildren = {}
    UI._sidebarHeaders  = UI._sidebarHeaders or {}
    UI.sidebarButtons   = UI.sidebarButtons or {}

    rebuildBuckets()

    local box = ensureFilterBox(f)
    local filter = UI._sidebarFilter or ""
    box._placeholder:SetText(L["Filter modules..."])
    box._placeholder:SetShown(filter == "")

    local y = 0

    do
        local row = UI._dashRow
        if not row then
            row = CreateFrame("Button", nil, parent)
            row:SetHeight(ROW_HEIGHT)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            ns.UI.SetGradient(bg, "HORIZONTAL",
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.26,
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.02)
            bg:Hide()
            row.bg = bg

            local accentBar = row:CreateTexture(nil, "ARTWORK")
            accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            accentBar:SetWidth(3)
            accentBar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            accentBar:Hide()
            row.accentBar = accentBar

            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints(row)
            hover:SetColorTexture(1, 1, 1, 0.05)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            icon:SetTexture(ICON_DIR .. "_dashboard.tga")
            icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ns.UI.Font(label, 12)
            label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
            row.label = label

            row:SetScript("OnClick", function()
                if UI.ShowDashboard then UI:ShowDashboard() end
            end)
            UI._dashRow = row
        end
        row.label:SetText(L["Overview"])  -- re-set on every populate: locale can change live
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        row:Show()
        table.insert(UI._sidebarChildren, row)
        y = y + ROW_HEIGHT + GROUP_GAP
    end

    if ns.modules and ns.modules.changelog then
        local row = UI._changelogRow
        if not row then
            row = CreateFrame("Button", nil, parent)
            row:SetHeight(ROW_HEIGHT)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints(row)
            ns.UI.SetGradient(bg, "HORIZONTAL",
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.26,
                ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 0.02)
            bg:Hide()
            row.bg = bg

            local accentBar = row:CreateTexture(nil, "ARTWORK")
            accentBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            accentBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            accentBar:SetWidth(3)
            accentBar:SetColorTexture(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            accentBar:Hide()
            row.accentBar = accentBar

            local hover = row:CreateTexture(nil, "HIGHLIGHT")
            hover:SetAllPoints(row)
            hover:SetColorTexture(1, 1, 1, 0.05)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("LEFT", row, "LEFT", 8, 0)
            icon:SetTexture(ICON_DIR .. "changelog.tga")
            icon:SetVertexColor(0.76, 0.76, 0.84, 0.95)

            local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            ns.UI.Font(label, 12)
            label:SetPoint("LEFT", icon, "RIGHT", 7, 0)
            row.label = label

            local dot = row:CreateTexture(nil, "OVERLAY")
            dot:SetSize(13, 13)
            dot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
            dot:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b, 1)
            local pulse = dot:CreateAnimationGroup()
            pulse:SetLooping("REPEAT")
            local a1 = pulse:CreateAnimation("Alpha")
            a1:SetFromAlpha(1); a1:SetToAlpha(0.15); a1:SetDuration(0.7); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
            local a2 = pulse:CreateAnimation("Alpha")
            a2:SetFromAlpha(0.15); a2:SetToAlpha(1); a2:SetDuration(0.7); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
            row.dot, row.dotPulse = dot, pulse

            row:SetScript("OnClick", function(self)
                if ns.db and ns.db.global then ns.db.global.patchNotesSeen = ns.VERSION end
                if self.dotPulse then self.dotPulse:Stop() end
                if self.dot then self.dot:Hide() end
                if UI.ShowModulePage then UI:ShowModulePage("changelog") end
            end)
            UI._changelogRow = row
        end
        row.label:SetText(L[ns.modules.changelog.name])
        local unread = ns.db and ns.db.global and ns.db.global.patchNotesSeen ~= ns.VERSION
        if unread then
            row.dot:Show()
            if not row.dotPulse:IsPlaying() then row.dotPulse:Play() end
        else
            row.dotPulse:Stop()
            row.dot:Hide()
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -y)
        row:Show()
        table.insert(UI._sidebarChildren, row)
        y = y + ROW_HEIGHT + GROUP_GAP
    end

    -- One group's rows, filtered. `rows` is the table the frames live in:
    -- the module's own row, or its second row for the pinned group.
    local function placeGroup(groupName, moduleKeys, rows)
        local visible = {}
        for _, key in ipairs(moduleKeys) do
            local mod = ns.modules[key]
            if mod then
                local ok, jump = rowMatches(key, mod, filter)
                if ok then visible[#visible + 1] = { key = key, jump = jump } end
            end
        end
        if #visible == 0 then return end

        local header = UI._sidebarHeaders[groupName]
        if not header then
            header = createGroupHeader(parent, groupName)
            UI._sidebarHeaders[groupName] = header
        end
        if header._label then header._label:SetText(string.upper(L[groupName])) end
        applyHeaderCount(header, moduleKeys)

        header:ClearAllPoints()
        header:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
        header:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
        header:Show()
        table.insert(UI._sidebarChildren, header)
        y = y + GROUP_HEADER_H

        for _, v in ipairs(visible) do
            local key, mod = v.key, ns.modules[v.key]
            local row = rows[key]
            if not row then
                row = createModuleRow(parent, key, mod)
                rows[key] = row
            end
            row.label:SetText(L[mod.name])
            row._jumpTab = v.jump
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   0, -y)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT",  0, -y)
            row:Show()
            table.insert(UI._sidebarChildren, row)
            y = y + ROW_HEIGHT
        end

        y = y + GROUP_GAP
    end

    -- Pinned first. Only keys that still have a row of their own: a module
    -- that was removed, or folded into a container since, drops out quietly.
    local pinned = {}
    for _, key in ipairs(pinnedList()) do
        local m = ns.modules[key]
        if m and not m.parentTab and not (UI.sidebarHiddenGroups[m.group or "Core"]) then
            pinned[#pinned + 1] = key
        end
    end
    UI._pinnedKeys = pinned
    if #pinned > 0 then placeGroup("Pinned", pinned, UI._pinRows) end

    for _, groupName in ipairs(UI.sidebarGroupOrder) do
        local moduleKeys = UI.sidebarGroupBuckets[groupName]
        local hidden = UI.sidebarHiddenGroups and UI.sidebarHiddenGroups[groupName]
        if moduleKeys and #moduleKeys > 0 and not hidden then
            placeGroup(groupName, moduleKeys, UI.sidebarButtons)
        end
    end

    parent:SetHeight(math.max(y + 10, 100))

    highlightSelected()
end

function UI:RefreshSidebarStates()
    for _, row in pairs(UI.sidebarButtons) do
        if row.power and row.power._refresh then
            row.power._refresh()
        end
    end
    for _, row in pairs(UI._pinRows) do
        if row.power and row.power._refresh then
            row.power._refresh()
        end
    end
    if UI._sidebarHeaders and UI._sidebarHeaders.Pinned and UI._pinnedKeys then
        applyHeaderCount(UI._sidebarHeaders.Pinned, UI._pinnedKeys)
    end
    -- Switching a module on or off changes its group's "3/7". Kept even though
    -- every row is on screen now: the count is a summary, and reading it beats
    -- counting nine rows.
    if UI._sidebarHeaders then
        for groupName, header in pairs(UI._sidebarHeaders) do
            local keys = UI.sidebarGroupBuckets and UI.sidebarGroupBuckets[groupName]
            if keys then applyHeaderCount(header, keys) end
        end
    end
    highlightSelected()
end

function UI:ShowModulePage(key)
    -- a parentTab sub-module has no row of its own: open its container, select its tab
    local m = ns.modules[key]
    local subTab
    if m and m.parentTab then
        subTab = key
        key    = m.parentTab
    end
    UI.currentModule = key
    UI.currentTab    = nil
    -- Recorded here rather than at each call site: this is the one door every
    -- page opening goes through, including the search results and the overview.
    if UI.NoteVisitedPage then UI:NoteVisitedPage(key) end
    UI:BuildTabsForModule(key)
    if subTab then UI:ShowTab(subTab) end
    highlightSelected()
end
