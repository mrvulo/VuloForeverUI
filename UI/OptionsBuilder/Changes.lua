-- VuloForeverUI / UI / OptionsBuilder / Changes: row icon textures, the page registers, the changed-from-default marks and the row icon buttons.
local _, ns = ...
local UI = ns.UI
local L = ns.L
local OB = UI._OB
local acquire = OB.acquire
local COMPACT = OB.COMPACT

-- Row icons: info shows item.tooltip, gear expands item.subOptions inline.
local ICON_DIR  = "Interface\\AddOns\\VuloForeverUI\\Media\\Icons\\ui\\"
local ICON_INFO = ICON_DIR .. "info.tga"
local ICON_GEAR = ICON_DIR .. "gear.tga"
-- The two arrows: opens item.popup as a floating panel instead of expanding
-- inline. Not a second expander in the sense the section note below forbids --
-- it is the SAME idea as the gear, drawn where the row has no width left for a
-- sub-column (a half cell in a two-column grid).
local ICON_EXPAND  = ICON_DIR .. "expand.tga"
local ICON_EYE     = ICON_DIR .. "eye.tga"
local ICON_EYE_OFF = ICON_DIR .. "eye_off.tga"

-- One slot per row icon, and the strip is always reserved even when the row
-- carries none. Two slots, because a row can show at most the gear and the info
-- dot. This is what makes every control on a page end at the same x.
local ROW_ICON_SLOT  = 21
local ROW_ICON_STRIP = ROW_ICON_SLOT * 2
local ICON_CFG = {
    [ICON_INFO] = { crop = false, desat = false },
    [ICON_GEAR] = { crop = false, desat = false },
}
UI.rowExpanded = UI.rowExpanded or {}

-- ---------------------------------------------------------------------------
-- Finding things again: three registers the page fills on every build.
--   _rowFrames    rowKey -> the row's card, so a search hit or a "recently
--                 changed" entry can scroll to the row and light it up
--   _sectionList  the headings in page order with their scroll offsets, for
--                 the jump chips above the page
--   onlyChanged   the page filter: only rows that differ from their defaults
-- ---------------------------------------------------------------------------
UI._rowFrames   = UI._rowFrames or {}
UI._sectionList = UI._sectionList or {}
UI.onlyChanged  = UI.onlyChanged or false

-- ---------------------------------------------------------------------------
-- Rows that differ from their defaults.
--
-- No row declares which db key it reads: every getter is a closure over
-- mod.db. So the default is not looked up, it is MEASURED. For the length of
-- one getter pass every module's db holds its defaults, the getters are called,
-- and their answers are the defaults; the live pass then compares.
--
-- The CONTENTS are swapped, never the table: the identity of mod.db and of
-- every sub-table that also exists in the defaults is kept, and the values
-- inside are replaced and afterwards restored from a snapshot. This is what
-- makes it work for the 200-odd getters that read through an alias taken at
-- GetOptions time (`local db = self.db`, `local d = mod.db.bars`): a pointer
-- swap would leave all of those reading live values on both passes, and whole
-- pages (auras, cast history, quest tracker) would never show a mark. A key the
-- live table has and the defaults do not (a list, runtime state) is absent for
-- the pass, and a getter that trips over that is pcall'd per row. Whatever a
-- getter writes during the pass is wiped by the restore.
-- ---------------------------------------------------------------------------
local function pushDefaults(live, def, undo)
    -- ApplyDefaults never shares a table between the two, but a module that
    -- hands the same table as both would be emptied by its own swap.
    if rawequal(live, def) then return end
    local snap = {}
    for k, v in pairs(live) do snap[k] = v end
    undo[#undo + 1] = { t = live, snap = snap }
    for k, v in pairs(snap) do
        local dv = def[k]
        if type(dv) == "table" and type(v) == "table" then
            pushDefaults(v, dv, undo)
        else
            live[k] = nil
        end
    end
    for k, dv in pairs(def) do
        if type(dv) == "table" then
            if type(live[k]) ~= "table" then live[k] = ns:DeepCopy(dv) end
        else
            live[k] = dv
        end
    end
end

local function withDefaultDbs(fn)
    local undo = {}
    local okSwap, errSwap = pcall(function()
        for _, m in pairs(ns.modules) do
            if type(m.db) == "table" and type(m.defaults) == "table" then
                pushDefaults(m.db, m.defaults, undo)
            end
        end
    end)
    local ok, err = true, nil
    if okSwap then ok, err = pcall(fn) end
    -- Reverse order: a sub-table's contents come back before the parent's
    -- keys point at it again. Every table gets exactly its snapshot back.
    for i = #undo, 1, -1 do
        local e = undo[i]
        for k in pairs(e.t) do e.t[k] = nil end
        for k, v in pairs(e.snap) do e.t[k] = v end
    end
    if not okSwap then ns:Debug("defaults pass (swap): %s", tostring(errSwap)) end
    if not ok then ns:Debug("defaults pass: %s", tostring(err)) end
end

-- nil and false are the same switch position; numbers get a tolerance; a
-- colour compares by channel. Anything else is equal only when it IS equal.
local function sameValue(a, b)
    if a == b then return true end
    if (a == nil or a == false) and (b == nil or b == false) then return true end
    local ta, tb = type(a), type(b)
    if ta == "number" and tb == "number" then return math.abs(a - b) < 1e-6 end
    if ta == "table" and tb == "table" then
        for _, k in ipairs({ "r", "g", "b", 1, 2, 3 }) do
            local x, y = a[k], b[k]
            if x ~= nil or y ~= nil then
                if not (type(x) == "number" and type(y) == "number" and math.abs(x - y) < 1e-3) then
                    return false
                end
            end
        end
        local xa, ya = a.a or a[4] or 1, b.a or b[4] or 1
        return type(xa) == "number" and type(ya) == "number" and math.abs(xa - ya) < 1e-3
    end
    return false
end

local function copyValue(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = x end
    return c
end

-- Marks every compact row of the page: item._vcChanged and item._vcDefault on
-- the row, item._vcChangedInside on whatever holds a changed row (a section, a
-- group, a gear row). Returns how many rows changed.
local function markChanged(items, skip)
    local rows = {}
    local function collect(list)
        for _, it in ipairs(list) do
            if type(it) == "table" then
                it._vcChanged, it._vcChangedInside, it._vcHasDefault = false, false, false
                if COMPACT[it.type] and type(it.get) == "function" and not it.noDefaultMark then
                    rows[#rows + 1] = it
                end
                if it.items then collect(it.items) end
                if it.subOptions then collect(it.subOptions) end
            end
        end
    end
    collect(items)
    if skip or #rows == 0 then return 0 end
    withDefaultDbs(function()
        for _, it in ipairs(rows) do
            local ok, v = pcall(it.get)
            if ok then it._vcDefault = copyValue(v); it._vcHasDefault = true end
        end
    end)
    local n = 0
    for _, it in ipairs(rows) do
        if it._vcHasDefault then
            local ok, v = pcall(it.get)
            -- A default of nil against a live string or number says "this key
            -- is not in the defaults at all" (list rows, runtime state), not
            -- "changed".
            if ok and not sameValue(v, it._vcDefault)
               and not (it._vcDefault == nil and v ~= nil and type(v) ~= "boolean") then
                it._vcChanged = true
                n = n + 1
            end
        end
    end
    if n == 0 then return 0 end
    local function mark(list)
        local inside = false
        for _, it in ipairs(list) do
            if type(it) == "table" then
                local sub = false
                if it.items then sub = mark(it.items) or sub end
                if it.subOptions then sub = mark(it.subOptions) or sub end
                it._vcChangedInside = sub
                if it._vcChanged or sub then inside = true end
            end
        end
        return inside
    end
    mark(items)
    return n
end

local function describeValue(item, v)
    if v == nil or v == false then return L["Off"] end
    if v == true then return L["On"] end
    if type(v) == "number" then
        if math.floor(v) == v then return tostring(v) end
        return string.format("%.2f", v)
    end
    if type(v) == "table" then
        local r = math.floor((v.r or v[1] or 1) * 255 + 0.5)
        local g = math.floor((v.g or v[2] or 1) * 255 + 0.5)
        local b = math.floor((v.b or v[3] or 1) * 255 + 0.5)
        return string.format("|cff%02x%02x%02x#%02x%02x%02x|r", r, g, b, r, g, b)
    end
    local vals = item.values
    if type(vals) == "function" then
        local ok, res = pcall(vals)
        vals = ok and res or nil
    end
    if type(vals) == "table" then
        for _, o in ipairs(vals) do
            -- through L, the way the dropdown itself shows the entry
            if type(o) == "table" and o.value == v and o.text then return L[tostring(o.text)] end
        end
    end
    return tostring(v)
end

-- Puts the row back to its measured default through its own setter, so the
-- module applies the value the way it applies any other change.
local function resetRow(item, widget)
    if not (item and item._vcHasDefault and type(item.set) == "function") then return end
    local d = item._vcDefault
    local ok, err
    if item.type == "color" then
        local c = type(d) == "table" and d or {}
        ok, err = pcall(item.set, c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1)
    elseif item.type == "toggle" or item.type == "checkbox" then
        ok, err = pcall(item.set, widget, d and true or false)
    else
        ok, err = pcall(item.set, widget, d)
    end
    if not ok then ns:Debug("reset row: %s", tostring(err)) end
    UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
end

-- The mark: an accent dot on the card's left edge. A button, because the
-- reset lives on it -- the row's icon strip has fixed slots for the gear and
-- the info dot and nothing else may move in there.
local ICON_DOT = "Interface\\COMMON\\Indicator-Gray"
local function makeChangeDot(parent)
    local b = acquire("changedot", parent)
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b._vcType  = "changedot"
    b._vcSetup = function() end
    b:SetSize(12, 12)
    b.icon = b:CreateTexture(nil, "OVERLAY")
    b.icon:SetAllPoints(b)
    b.icon:SetTexture(ICON_DOT)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(ns.TC("textHi"))
        local it = self._item
        if not it then return end
        UI:ShowTooltip(self, {
            title = L["Differs from the default"],
            lines = {
                { string.format(L["Default: %s"], describeValue(it, it._vcDefault)), 0.85, 0.85, 0.9 },
                { L["Click: reset this setting"], 0.6, 0.6, 0.66 },
            },
        })
    end)
    b:SetScript("OnLeave", function(self)
        local a = ns.COLORS.accent
        self.icon:SetVertexColor(a.r, a.g, a.b)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self) resetRow(self._item, self._widget) end)
    return b
end

-- `passive`: a smaller dot that takes no mouse. In a row of side-by-side
-- controls the gap between two of them is 8 px, and a clickable 12 px dot
-- there would sit on the tail of the control to its left.
local function placeChangedDot(parent, item, widget, x, midY, level, passive)
    if not item._vcChanged then return end
    local d = makeChangeDot(parent)
    d._item, d._widget = item, widget
    local a = ns.COLORS.accent
    d.icon:SetVertexColor(a.r, a.g, a.b)
    d:SetSize(passive and 8 or 12, passive and 8 or 12)
    d:EnableMouse(not passive)
    d:ClearAllPoints()
    d:SetPoint("CENTER", parent, "TOPLEFT", x, midY)
    d:SetFrameLevel(level)
    d:Show()
end

-- How many settings a heading groups: the compact rows below it, gears included.
local function countRows(list)
    local n = 0
    for _, it in ipairs(list or {}) do
        if type(it) == "table" then
            if COMPACT[it.type] then n = n + 1 end
            if it.items then n = n + countRows(it.items) end
            if it.subOptions then n = n + countRows(it.subOptions) end
        end
    end
    return n
end

-- With the filter on, a list keeps only what changed: rows, and the sections,
-- groups and gear rows holding one. Text, buttons and spacers drop out --
-- they explain a page, and the filtered page is not that page.
local FILTER_SKIP = { desc = true, header = true, button = true, iconbutton = true, spacer = true, custom = true }
local function filterChanged(items)
    local out = {}
    for _, it in ipairs(items) do
        if type(it) == "table" then
            if it.type == "section" or it.type == "group" then
                if it._vcChangedInside then out[#out + 1] = it end
            elseif not FILTER_SKIP[it.type] and (it._vcChanged or it._vcChangedInside) then
                out[#out + 1] = it
            end
        end
    end
    return out
end

local function makeRowIcon(parent)
    local b = acquire("rowicon", parent)
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b._vcType  = "rowicon"
    b._vcSetup = function() end
    b:SetSize(16, 16)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(ns.COLORS.accent.r, ns.COLORS.accent.g, ns.COLORS.accent.b)
        self:SetSize(18, 18)
        if self._tip then
            UI:ShowTooltip(self, { title = self._tip, wrap = true })
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(ns.TC("textDim"))
        self:SetSize(16, 16)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self) if self._onClick then self._onClick() end end)
    return b
end

local function setRowIcon(b, tex, tip, onClick, level)
    local cfg = ICON_CFG[tex] or {}
    b.icon:SetTexture(tex)
    b.icon:SetTexCoord(cfg.crop and 0.10 or 0, cfg.crop and 0.90 or 1,
                       cfg.crop and 0.10 or 0, cfg.crop and 0.90 or 1)
    b.icon:SetDesaturated(cfg.desat and true or false)
    b.icon:SetVertexColor(ns.TC("textDim"))
    b._tip = tip
    b._onClick = onClick
    -- pooled: an inline icon may have been greyed out on its last row
    b:SetAlpha(1)
    b:EnableMouse(true)
    b:SetFrameLevel(level)
    b:Show()
    return b
end

-- for the OptionsBuilder files loaded after this one
OB.ICON_INFO = ICON_INFO
OB.ICON_GEAR = ICON_GEAR
OB.ICON_EXPAND = ICON_EXPAND
OB.ICON_EYE = ICON_EYE
OB.ICON_EYE_OFF = ICON_EYE_OFF
OB.ROW_ICON_SLOT = ROW_ICON_SLOT
OB.ROW_ICON_STRIP = ROW_ICON_STRIP
OB.markChanged = markChanged
OB.placeChangedDot = placeChangedDot
OB.countRows = countRows
OB.filterChanged = filterChanged
OB.makeRowIcon = makeRowIcon
OB.setRowIcon = setRowIcon
