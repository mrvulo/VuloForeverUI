-- VuloForeverUI / UI / OptionsBuilder: builds a module page from mod:GetOptions(tabId).
-- Item spec:
--   { type = "header",    text }
--   { type = "desc",      text, width? }
--   { type = "checkbox" / "toggle", label, tooltip, get, set, width? }
--   { type = "slider",    label, tooltip, min, max, step, get, set }
--   { type = "dropdown",  label, tooltip, values, get, set, width?, reorder? }
--       values entries take optional per-row fields:
--         separator = true            a greyed caption, not selectable
--         action = true, onClick      an "add a new one" row at the bottom
--         draggable = true            may be dragged; needs config.reorder(from, to)
--         buttons = { { icon | glyph, tooltip, onClick(value, opt) }, ... }
--   { type = "editbox",   label, tooltip, get, set, numeric, width? }
--   { type = "button",    label, tooltip, onClick, width?, primary? }
--   { type = "spacer",    height? }
--   { type = "group",     layout = "row" | "columns", items, columns?, gap? }
--   { type = "custom",    build = function(parent) -> frame end, height?, width? }
local _, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local L = ns.L

local CONTENT_PADDING = 14

-- Shared dropdown value lists for the visibility pair several modules offer.
-- Built per call, never at file load: the saved language override is only
-- readable once SavedVariables are in.
function ns.VisibilityValues()
    return {
        { value = "always",    text = L["Always shown"] },
        { value = "mouseover", text = L["Mouseover"] },
        { value = "combat",    text = L["In combat"] },
        { value = "noncombat", text = L["Out of combat"] },
    }
end

-- Anchor points as words. They were built as { value = "CENTER", text = "CENTER" }
-- -- the raw frame token shown to the reader, in every language. The VALUE stays
-- the token because the client needs it; only the text is translated.
function ns.AnchorPointValues()
    return {
        { value = "CENTER",      text = L["Centre"] },
        { value = "TOP",         text = L["Top"] },
        { value = "BOTTOM",      text = L["Bottom"] },
        { value = "LEFT",        text = L["Left"] },
        { value = "RIGHT",       text = L["Right"] },
        { value = "TOPLEFT",     text = L["Top left"] },
        { value = "TOPRIGHT",    text = L["Top right"] },
        { value = "BOTTOMLEFT",  text = L["Bottom left"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
    }
end

-- Frames are never garbage-collected: widgets are pooled by type and reconfigured via _vcSetup.
local poolHost = CreateFrame("Frame")
poolHost:Hide()
local pools = {}

local function acquire(vctype, parent)
    local p = pools[vctype]
    local w = p and table.remove(p)
    if w then
        w:SetParent(parent)
        w:Show()
    end
    return w
end

local function release(w)
    local t = w._vcType
    if not t or not w._vcSetup then return false end
    w:Hide()
    w:ClearAllPoints()
    w:SetParent(poolHost)
    pools[t] = pools[t] or {}
    table.insert(pools[t], w)
    return true
end

local function clearChildren(parent)
    local kids = { parent:GetChildren() }
    for _, k in ipairs(kids) do
        -- A sub-column container holds pooled widgets of its OWN; they must go
        -- back to their pools first, or the container would carry them into the
        -- pool and show them again on whatever page acquires it next.
        if k._vcType == "subcol" then clearChildren(k) end
        if not release(k) then
            if k == UI._dashContainer then
                k:Hide()
            else
                k:Hide()
                k:SetParent(nil)
                k:ClearAllPoints()
            end
        end
    end
    local regions = { parent:GetRegions() }
    for _, r in ipairs(regions) do
        if r.SetText then r:SetText("") end
        r:Hide()
        r:ClearAllPoints()
    end
end
UI.ClearOptionsChildren = clearChildren

local function obtain(vctype, parent, item, factory)
    local w = acquire(vctype, parent)
    if w then
        w:_vcSetup(item)
        return w
    end
    return factory()
end

local function createWidget(parent, item)
    local t = item.type
    if t == "header" then
        local w = obtain("header", parent, item, function()
            return UI:CreateHeader(parent, item.text or "")
        end)
        return w, 26, 480
    elseif t == "desc" then
        local w = obtain("desc", parent, item, function()
            return UI:CreateDescription(parent, item.text or "")
        end)
        w:SetDescWidth(item.width or 480)
        return w, math.max(20, w:GetDescHeight() + 4), item.width or 480
    elseif t == "checkbox" or t == "toggle" then
        -- The eye variant is built differently at construction and cannot be
        -- reconfigured into a switch or back, so the two need separate pools.
        -- Sharing one made an ordinary on/off row come back as an eye glyph
        -- after visiting a page that used the eye style.
        local w = obtain(item.style == "eye" and "toggle_eye" or "toggle", parent, item, function()
            return UI:CreateToggle(parent, item)
        end)
        return w, 26, w:GetWidth() or 260
    elseif t == "slider" then
        local w = obtain("slider", parent, item, function()
            return UI:CreateSlider(parent, item)
        end)
        -- Ask the row, like every other type here does. The flat 280 was right
        -- while a slider WAS its track; since it became a one-line row the label
        -- column and the value block are part of its width too.
        return w, 24, w:GetWidth() or 280
    elseif t == "dropdown" then
        local w = obtain("dropdown", parent, item, function()
            return UI:CreateDropdown(parent, item)
        end)
        return w, item.label and 30 or 28, item.width or 200
    elseif t == "segmented" then
        local w = obtain("segmented", parent, item, function()
            return UI:CreateSegmented(parent, item)
        end)
        return w, 26, item.width or 260
    elseif t == "editbox" then
        local w = obtain("editbox", parent, item, function()
            return UI:CreateEditBox(parent, item)
        end)
        return w, 28, w:GetWidth() or 160
    elseif t == "color" then
        local w = obtain("color", parent, item, function()
            return UI:CreateColorSwatch(parent, item)
        end)
        return w, 26, w:GetWidth() or 200
    elseif t == "button" then
        local w = obtain("button", parent, item, function()
            return UI:CreateButton(parent, item)
        end)
        return w, 30, (w:GetWidth() or item.width or 120)
    elseif t == "iconbutton" then
        local w = obtain("iconbutton", parent, item, function()
            return UI:CreateIconButton(parent, item)
        end)
        return w, 28, item.width or 28
    elseif t == "custom" then
        -- build(parent) must return a module-owned, memoised frame: it survives clearChildren.
        local w = item.build and item.build(parent)
        if not w then return nil, 0, 0 end
        return w, item.height or (w:GetHeight() or 100), item.width or 480
    end
    return nil, 0, 0
end

local function estimateHeight(item)
    local t = item.type
    if t == "checkbox" or t == "toggle" then return 26
    elseif t == "button" or t == "iconbutton" then return 30
    elseif t == "header" then return 26
    elseif t == "desc"   then return 22
    elseif t == "slider" then return 24
    elseif t == "dropdown" then return item.label and 30 or 28
    elseif t == "segmented" then return 26
    elseif t == "editbox" then return 28
    elseif t == "color" then return 26
    elseif t == "custom" then return item.height or 100
    end
    return 26
end

-- Consecutive compact controls auto-arrange into a two-column grid; everything
-- else is full width. The slider joined them once it became a one-line row:
-- while its label sat above the track it needed its own taller shape, and that
-- was the reason a page had three different row heights in it.
local COMPACT = { toggle = true, checkbox = true, dropdown = true, editbox = true, color = true, slider = true, segmented = true }
local COL_GAP  = 14
local ROW_H    = 38
local CARD_GAP = 8
local CARD_H   = ROW_H - CARD_GAP
local CARD_VPAD = 11

local function makePanel(parent)
    local p = acquire("panel", parent)
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p._vcType  = "panel"
    p._vcSetup = function() end
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetAllPoints(p)
    -- LIGHTER than the page behind it (bgContent is 0.08). It used to be 0.075,
    -- i.e. a hair DARKER than the page, so a card was nothing but its outline
    -- and the eye had to trace borders to see where one setting ended. Raising
    -- the fill lets the card read as an object and lets the border step back.
    p.bg:SetColorTexture(0.115, 0.115, 0.14, 0.95)
    for _, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = p:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.19, 0.19, 0.24, 1)
        if s == "TOP" or s == "BOTTOM" then
            t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(1)
        end
    end
    return p
end

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
        self.icon:SetVertexColor(1, 1, 1)
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
        self.icon:SetVertexColor(0.62, 0.62, 0.70)
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
    b.icon:SetVertexColor(0.62, 0.62, 0.70)
    b._tip = tip
    b._onClick = onClick
    -- pooled: an inline icon may have been greyed out on its last row
    b:SetAlpha(1)
    b:EnableMouse(true)
    b:SetFrameLevel(level)
    b:Show()
    return b
end

local placeItem, placeItemList  -- forward decls: mutually recursive via sections

-- One hidden string, reused, to measure label widths before anything is drawn.
-- Creating one per measurement would leak a font string per page build, and
-- frames and their regions are never collected in this client.
local measureFS
local function labelWidth(text)
    if not text or text == "" then return 0 end
    if not measureFS then
        measureFS = poolHost:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.Font(measureFS, 12)
    end
    measureFS:SetText(text)
    return measureFS:GetStringWidth() or 0
end

-- The widest label in the run decides where every control in it begins. This is
-- the whole point: the column is MEASURED, not guessed, so a group lines up on
-- one edge without anyone tuning gaps by eye. Capped at 45% of a cell so one
-- long label cannot squeeze every track in the group down to a stub.
-- `wide` also measures dropdowns. Off by default: it widens the column on every
-- page that has a long dropdown label, and only a grid page has asked for that
-- trade. (Dropdown boxes are RIGHT-anchored at a bounded width since 31.07 --
-- for them the column is now only a measurement input, not the box anchor; it
-- still governs the sliders and segmented strips of the same run.)
local function runLabelColumn(run, cellW, wide)
    local widest = 0
    for _, item in ipairs(run) do
        -- A segmented row is [label][strip], the strip anchored to the label's
        -- right edge -- the same reason a dropdown needs the column: without one,
        -- every row on the page starts its strip at a different x.
        if item.type == "slider" or (wide and (item.type == "dropdown" or item.type == "segmented")) then
            local w = labelWidth(item.label)
            -- A tooltip puts an info glyph in front of the text, inside the same
            -- column. Measuring only the text made exactly those rows clip --
            -- "Engine-FCT-Skalieru..." was the giveaway.
            if item.tooltip then w = w + 22 end
            if w > widest then widest = w end
        end
    end
    if widest == 0 then return nil end
    -- Slack, not a tight fit: GetStringWidth and the actual glyph run differ by
    -- a hair, and at a tight fit the client answers with an ellipsis rather than
    -- the last letter. Two pixels was not enough -- "Nachrichtenabsta..." lost
    -- three characters to it.
    return math.min(math.ceil(widest) + 10, math.floor(cellW * 0.5))
end

-- How many columns a run of compact rows may use. Three fit noticeably more on
-- one screen, and at two columns of ~470px a toggle sat 350px away from its own
-- label. But a slider row is [label][track][- value +], and only the track can
-- give: the block on the right keeps its size whatever the cell does.
--
-- So the question this asks is NOT "does the longest label fit in half a cell".
-- That is what it asked the first time, and three columns were granted to runs
-- whose tracks then had nothing left -- the row's minimum width invented the
-- missing pixels and drew them across the next column. It asks whether a track
-- worth dragging still remains once the label and the block have taken theirs,
-- computed on the same geometry layoutSliderRow will use.
local MAX_COLS  = 3
local MIN_TRACK = 60    -- below this it is a stub, not something you can drag
local MIN_CELL  = 250

-- What each kind of control needs to the right of the label. Only the slider
-- was ever able to damage a neighbour, and it no longer can -- its row is a
-- closed box now. These are legibility floors: a switch anchored to both edges
-- shrinks quietly rather than overflowing, but a dropdown squeezed to a stub is
-- still a dropdown nobody can read.
local CONTROL_NEED = { toggle = 44, checkbox = 44, color = 44, dropdown = 110, editbox = 90 }

local function fitColumns(run, availW)
    local widest, need, anyTip = 0, 0, false
    local sliderEnd = 0
    for _, item in ipairs(run) do
        local w = labelWidth(item.label)
        if w > widest then widest = w end
        if item.tooltip then anyTip = true end
        if item.type == "slider" then
            -- the widest value the slider can display decides its block, and a
            -- track has to fit beside it -- this is the binding constraint
            local e = UI.SliderEndWidth and UI.SliderEndWidth(item.min, item.max, item.step) or 90
            if e + MIN_TRACK > sliderEnd then sliderEnd = e + MIN_TRACK end
        else
            local c = CONTROL_NEED[item.type] or 44
            if c > need then need = c end
        end
    end
    if sliderEnd > need then need = sliderEnd end
    local gap = UI.SLIDER_LABEL_GAP or 12
    for cols = MAX_COLS, 2, -1 do
        local cellW  = math.floor((availW - (cols - 1) * COL_GAP) / cols)
        -- what the ROW is given, which is what layoutSliderRow divides up: the
        -- card's inner padding, and the info glyph if any row in the run has one
        local rowW   = cellW - 20 - (anyTip and 22 or 0)
        -- the same cap the row applies, so this answer is the geometry that
        -- gets drawn rather than an optimistic version of it
        local labelW = math.min(widest + 10, math.floor(rowW * 0.5))
        if cellW >= MIN_CELL and (rowW - labelW - gap) >= need then
            return cols
        end
    end
    return 2
end

-- ---- strict grid, opt-in per page ---------------------------------------
-- A module sets `optionsGrid = true` and every compact row on its page becomes
-- one half of a two-column grid -- INCLUDING a setting with no partner, which
-- keeps its half and leaves the other empty instead of stretching across the
-- page.
--
-- That second half of the rule is the one we did not have. A lone control on
-- full width puts its switch at the far right, some four hundred pixels from
-- the label it belongs to; pairing runs closed that gap only where a partner
-- happened to exist. The reference addon we took this from has 44 two-column
-- rows on its cooldown page and exactly one full-width control -- it pads with
-- an empty half rather than break the grid, and that is what makes the page
-- read as ordered.
--
-- The label column is measured ONCE for the page, not per run. Per run, two
-- groups with different longest labels start their tracks at two different x
-- positions, and the eye reads that as carelessness rather than as two groups.
UI._grid = nil   -- nil, or { cols = 2, labelCol = n }

local function collectCompact(list, out)
    for _, it in ipairs(list) do
        if type(it) == "table" then
            if COMPACT[it.type] and not it.subOptions then out[#out + 1] = it end
            if it.items then collectCompact(it.items, out) end
            -- Rows behind a gear are measured too, even while collapsed. They
            -- share this one page-wide label column when they open, so leaving
            -- them out would truncate a long sub-label -- and would also make
            -- the column jump the moment a gear is clicked.
            if it.subOptions then collectCompact(it.subOptions, out) end
        end
    end
    return out
end

local function pageLabelColumn(items, availW)
    local slotW = math.floor((availW - COL_GAP) / 2)
    return runLabelColumn(collectCompact(items, {}), slotW - 20, true)
end

-- The rows that end up on a line of their OWN, which is a different population
-- from the compact grid and needs its own measured column.
--
-- Two things land here: a row carrying a gear (placeItemList sends those to
-- placeItem one at a time) and a row asking for fullWidth (placeColumns gives
-- that run a single column). Neither used to get a label column at all -- the
-- gear rows because placeItem never set one, the fullWidth rows because
-- placeColumns deliberately drops the page column on them. So every such row
-- sized its label to its own text and the value boxes down a page started at a
-- different x each time, which reads as carelessness rather than as a list.
--
-- Measured separately and NOT reused from pageLabelColumn: that one is measured
-- against half a cell, and forcing it onto a full-width row would park the
-- control a quarter of the way across and leave a gap.
local function collectSolo(list, out)
    for _, it in ipairs(list) do
        if type(it) == "table" then
            -- COMPACT, not CARD_TYPES: the two hold the same seven types, but
            -- CARD_TYPES is declared further down the file, so a reference to it
            -- from here would read a nil global instead.
            if COMPACT[it.type] and (it.subOptions or it.fullWidth) then
                out[#out + 1] = it
            end
            if it.items then collectSolo(it.items, out) end
            -- Rows behind a gear are measured while still collapsed, for the same
            -- reason collectCompact does it: the column must not jump the moment
            -- somebody opens one.
            if it.subOptions then collectSolo(it.subOptions, out) end
        end
    end
    return out
end

local function soloLabelColumn(items, availW)
    -- The width a solo row actually gives its widget, so the 50% cap inside
    -- runLabelColumn is applied to the geometry that gets drawn.
    return runLabelColumn(collectSolo(items, {}), availW - 20 - ROW_ICON_STRIP, true)
end

-- The identity of a row across rebuilds; the same recipe placeItem uses for
-- its gear state, shared here because paired gear rows need it too.
local function rowKey(item)
    return (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
        .. "/r/" .. tostring(item.subKey or item.label or item.text or item)
end

-- An OPEN pairable gear row unfolds inside its own half of the grid, not
-- across the page. Its sub-rows go into this invisible container, shaped like
-- a page one column wide: every anchor in placeItem/placeColumns measures its
-- parent and starts at CONTENT_PADDING, so a container at
-- (cellX - CONTENT_PADDING, cellW + 2*CONTENT_PADDING) lands all of them
-- exactly inside the cell's column without any of that code knowing.
local function makeSubColumn(parent)
    local f = acquire("subcol", parent)
    if f then return f end
    f = CreateFrame("Frame", nil, parent)
    f._vcType  = "subcol"
    f._vcSetup = function() end
    return f
end

-- ---------------------------------------------------------------------------
-- Row popup: one row's fine tuning, in a floating panel.
--
-- WHY NOT THE GEAR. The gear unfolds a sub-column INSIDE the row's cell, which
-- needs a cell wide enough to hold a second, indented run. Half a cell in a
-- strict two-column grid is not -- and the nameplate slot rows are exactly that
-- shape (user request, 02.08.2026). This is not the second collapse mechanism
-- the section note further down forbids: it makes the SAME promise the gear
-- makes -- "what is in here belongs to this row" -- drawn where the width is.
--
-- The rows inside are built by placeItemList, so they are the same widgets with
-- the same look and the same settings-search reach as any page row. Pooling
-- stays safe only because clearChildren releases per PARENT: a page rebuild
-- reclaims the page's widgets and cannot reach into the panel, and the panel's
-- own widgets are out of the pool while it is open, so no page can be handed
-- one that is still on screen.
local rowPopup

local function closeRowPopup()
    if rowPopup and rowPopup:IsShown() then rowPopup:Hide() end
end
UI.CloseRowPopup = closeRowPopup

local function ensureRowPopup()
    if rowPopup then return rowPopup end
    -- Named on purpose: UISpecialFrames closes it on Escape, which is what the
    -- key does to every other panel in this UI.
    local f = CreateFrame("Frame", "VuloOptionsRowPopup", UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)          -- eats its own clicks, so the catcher below cannot see them
    f:Hide()
    UI:StyleBackdrop(f)
    if UI.CreateShadow then UI:CreateShadow(f) end

    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT",  f, "TOPLEFT",   1, -1)
    accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    f._accent = accent

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    UI.Font(title, 12)
    title:SetPoint("TOP", f, "TOP", 0, -10)
    title:SetTextColor(0.95, 0.95, 0.97)
    f._title = title

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -30)
    f._body = body

    -- A click anywhere else closes it. A full-screen catcher BEHIND the panel,
    -- not a mouse test on OnUpdate: the test would have to run every frame for
    -- a panel that is open for a second.
    local catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:EnableMouse(true)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(100)
    catcher:Hide()
    catcher:SetScript("OnMouseDown", closeRowPopup)
    f._catcher = catcher

    f:SetScript("OnShow", function(self) self._catcher:Show() end)
    f:SetScript("OnHide", function(self)
        self._catcher:Hide()
        self._owner = nil
        -- A menu opened from one of these rows would otherwise outlive the
        -- button it belongs to -- that button is about to go back to the pool.
        if UI.CloseDropdownPopup then UI.CloseDropdownPopup() end
        -- back to the pools, or the next open would stack a second set of rows
        -- on top of these
        clearChildren(self._body)
    end)
    if _G.UISpecialFrames then
        tinsert(_G.UISpecialFrames, "VuloOptionsRowPopup")
    end
    rowPopup = f
    return f
end

-- spec = { title = <string>, width = <number>, items = { <option items> } }
local function openRowPopup(anchor, spec)
    local f = ensureRowPopup()
    -- the same icon twice is "close", the way every expander in this UI behaves
    if f:IsShown() and f._owner == anchor then closeRowPopup(); return end
    f:Hide()                     -- releases the previous panel's rows via OnHide
    f._owner = anchor
    f._spec  = spec              -- kept for RefreshRowPopup
    -- A child of UIParent, not of the window it belongs to, so it does not
    -- inherit the window's scale. Taken here rather than at creation: the panel
    -- outlives any number of scale changes.
    if UI.MainFrameScale then f:SetScale(UI:MainFrameScale()) end
    f._title:SetText(spec.title or "")
    local a = ns.COLORS.accent   -- read at paint time: the theme colour is live-mutated
    f._accent:SetColorTexture(a.r, a.g, a.b, 0.9)

    -- Width BEFORE the rows: placeItemList measures its columns against the
    -- parent's width, and a body still at its default would lay the rows out
    -- for a width the panel never has. Below MIN_CELL on purpose -- one column
    -- is what a fine-tuning list should be.
    local w = spec.width or 240
    f:SetWidth(w)
    f._body:SetSize(w, 10)

    -- ONE column, with a label column measured for THESE rows at THIS width --
    -- the same recipe placeSubColumn uses, and for the same reason.
    --
    -- Clearing the grid instead of setting it was the first attempt and it drew
    -- the panel in two columns anyway (user report, 02.08.2026): with no grid,
    -- placeColumns falls through to fitColumns, which pairs any run that fits --
    -- and at half of 320px every label came out as "Ver-t...". The grid is not
    -- only what forces pairing, it is also what can forbid it.
    local savedGrid, savedSolo = UI._grid, UI._soloCol
    local col = runLabelColumn(collectCompact(spec.items or {}, {}),
        w - 2 * CONTENT_PADDING - 20 - ROW_ICON_SLOT, true)
    UI._grid    = { cols = 1, labelCol = col, iconStrip = ROW_ICON_SLOT }
    UI._soloCol = col
    local ok, bottom = pcall(placeItemList, f._body, spec.items or {}, 0)
    UI._grid, UI._soloCol = savedGrid, savedSolo
    if not ok then
        ns:Debug("row popup: %s", tostring(bottom))
        f:Hide()
        return
    end
    local bodyH = math.max(10, -bottom)
    f._body:SetHeight(bodyH)
    f:SetHeight(30 + bodyH + 10)

    f:ClearAllPoints()
    -- UPWARDS by default (user request, 02.08.2026). Opening downwards put the
    -- panel over the rows below it and, on a row near the bottom of the page,
    -- half of it off the screen -- where SetClampedToScreen shoved it back over
    -- its own anchor. Above the row it covers what you have already read.
    --
    -- Flipped back down only when the panel would not fit above: measured
    -- against the anchor's own top, so a row near the top of the screen still
    -- gets a panel you can read rather than one pinned to the edge.
    local top = anchor:GetTop()
    local screenH = UIParent:GetHeight() or 768
    if top and (top + f:GetHeight() + 10) > screenH then
        f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -10, -6)
    else
        f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -10, 6)
    end
    f:Show()
end
UI.OpenRowPopup = openRowPopup

-- Redraw the open panel in place. A setter inside it that decides whether OTHER
-- rows in the same panel can do anything needs this: refreshing the PAGE leaves
-- the panel exactly as it was, and its rows would go on looking available until
-- it was closed and opened again. The owner is cleared first, or openRowPopup
-- would read the call as clicking the same gear twice and close the panel.
function UI:RefreshRowPopup()
    local f = rowPopup
    if not (f and f:IsShown() and f._owner and f._spec) then return end
    local anchor, spec = f._owner, f._spec
    f._owner = nil
    openRowPopup(anchor, spec)
end

-- Where a row's inline icons chain leftward from. A dropdown hands back its
-- box, which is what the eye follows; anything else falls back to its own right
-- edge. Inline icons sit LEFT of the control on purpose -- the right-hand strip
-- is spoken for by the info dot and the gear, and widening it would move every
-- control on every page.
-- Where a row's inline icons chain leftward from: the point at which the
-- CONTROL begins. A dropdown hands back its box, a slider its track, a
-- checkbox or toggle its switch.
--
-- The fallback to the widget itself is a LAST resort and it looks wrong when it
-- fires -- the widget starts at the label, so the icons land in front of the
-- text. That is exactly what the toggle rows did before `_switch` was listed
-- here (user report, 02.08.2026): "Zaubersymbol" drew its arrows left of its
-- own name. Any widget type given inline icons needs a handle in this list.
local function inlineAnchor(widget)
    return widget._button or widget._slider or widget._switch or widget
end

-- Small square colour button for an inline swatch. Pooled like the row icons,
-- so a page rebuild reclaims it through clearChildren.
local function makeInlineColor(parent)
    local b = acquire("inlinecolor", parent)
    if b then return b end
    b = CreateFrame("Button", nil, parent)
    b._vcType  = "inlinecolor"
    b._vcSetup = function() end
    b:SetSize(18, 18)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints(b)
    border:SetColorTexture(0, 0, 0, 0.8)
    b._border = border
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 1)
    b._fill = fill
    b:SetScript("OnEnter", function(self)
        local a = ns.COLORS.accent
        self._border:SetColorTexture(a.r, a.g, a.b, 1)
        if self._tip then UI:ShowTooltip(self, { title = self._tip, wrap = true }) end
    end)
    b:SetScript("OnLeave", function(self)
        self._border:SetColorTexture(0, 0, 0, 0.8)
        UI:HideTooltip()
    end)
    b:SetScript("OnClick", function(self)
        local cfg = self._cfg
        if not (cfg and cfg.get) then return end
        local c = cfg.get() or {}
        ns:ShowColorPicker({ r = c.r or 1, g = c.g or 1, b = c.b or 1,
            onChange = function(r, g, bl)
                if cfg.set then cfg.set(r, g, bl) end
                local nc = cfg.get() or {}
                self._fill:SetColorTexture(nc.r or 1, nc.g or 1, nc.b or 1, 1)
            end })
    end)
    return b
end

-- Draws item.inline (right to left) starting at the control's left edge, and
-- returns how much width they took so the caller can shrink the control by it.
local INLINE_SLOT = 24
local function placeInlineIcons(parent, item, widget, level)
    if not widget then return 0 end
    local defs = item.inline
    local n = (defs and #defs) or 0

    -- A toggle's label spans from the row's left edge to its switch, so icons
    -- placed between the two would draw over the end of the text. Move the
    -- label's right edge out of their way -- and move it BACK when a pooled
    -- toggle lands on a row with no icons, or the gap travels to a page that
    -- never asked for it.
    if widget._switch and widget._label then
        widget._label:ClearAllPoints()
        widget._label:SetPoint("LEFT", widget, "LEFT", 0, 0)
        widget._label:SetPoint("RIGHT", widget._switch, "LEFT", -8 - n * INLINE_SLOT, 0)
    end

    if n == 0 then return 0 end
    local anchor = inlineAnchor(widget)
    local used = 0
    for _, def in ipairs(defs) do
        local b
        if def.kind == "color" then
            b = makeInlineColor(parent)
            b._cfg = def
            b._tip = def.tooltip
            local c = (def.get and def.get()) or {}
            b._fill:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 1)
            -- A swatch that cannot do anything says so rather than lying
            local off = def.disabled and def.disabled()
            b:SetAlpha(off and 0.15 or 1)
            b:EnableMouse(not off)
            b:SetFrameLevel(level)
            b:Show()
        else
            local tex = ICON_EXPAND
            local onClick
            if def.kind == "eye" then
                local on = not (def.get and def.get() == false)
                tex = on and ICON_EYE or ICON_EYE_OFF
                onClick = function()
                    if def.set then def.set(not on) end
                    UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
                end
            else
                -- Two icons, one mechanism, and the difference is what the rows
                -- behind it ARE. The gear means "more of this setting" -- the
                -- same promise the right-hand gear makes on every other page.
                -- The two arrows mean "this thing has a place and a size", which
                -- is what a position slot opens.
                if def.kind == "gear" then tex = ICON_GEAR end
                onClick = function() openRowPopup(widget, def.popup or def) end
            end
            b = setRowIcon(makeRowIcon(parent), tex, def.tooltip, onClick, level)
            -- same rule as the swatch: an icon that cannot do anything says so
            local off = def.disabled and def.disabled()
            b:SetAlpha(off and 0.15 or 1)
            b:EnableMouse(not off)
        end
        b:ClearAllPoints()
        b:SetPoint("RIGHT", anchor, "LEFT", -6 - used, 0)
        used = used + INLINE_SLOT
    end
    return used
end

local function placeSubColumn(parent, item, cellX, subY, cellW)
    local sub = makeSubColumn(parent)
    sub:ClearAllPoints()
    sub:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX - CONTENT_PADDING, subY)
    sub:SetWidth(cellW + 2 * CONTENT_PADDING)
    sub:SetFrameLevel(parent:GetFrameLevel())
    sub:Show()

    -- One column, with a label column measured for THESE rows at THIS width.
    -- The page grid must not leak in here: its cells are half the page, its
    -- label column is measured against that, and fitColumns never answers
    -- below two -- each of the three would cram two ~220px cells into the
    -- half. iconStrip reserves ONE slot, not the full-width strip of two:
    -- the cell above reserved exactly the gear slot (gearLead), and the
    -- sub-rows' controls should end on that same edge.
    local savedGrid, savedSolo = UI._grid, UI._soloCol
    local col = runLabelColumn(collectCompact(item.subOptions, {}),
        cellW - 20 - ROW_ICON_SLOT, true)
    UI._grid    = { cols = 1, labelCol = col, iconStrip = ROW_ICON_SLOT }
    UI._soloCol = col
    local yEnd = placeItemList(sub, item.subOptions, 0)
    UI._grid, UI._soloCol = savedGrid, savedSolo

    local h = -yEnd
    sub:SetHeight(math.max(1, h))
    return h
end

local function placeColumns(parent, run, y)
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local grid   = UI._grid

    -- An item may demand the whole width, and that beats the page grid.
    --
    -- The grid pairs SETTINGS: short labels, comparable to each other, chosen by
    -- whoever wrote the page. A generated LIST is neither -- an override reads
    -- "Nameplates > Health Bar > Width", and in a half-width cell both members
    -- of every pair end in an ellipsis, which is the one thing a list must not
    -- do. Asked for per item, so no existing page changes.
    local wide = false
    for _, item in ipairs(run) do
        -- Three or four segments do not survive a half-width cell: the strip is
        -- what is left of ~250px after the label, split three ways, and a German
        -- option name is not going to fit in 60px. Two do, so two stay pairable.
        -- fullWidth no longer reaches here: placeItemList keeps such a row out of
        -- the run entirely. Kept as a guard in case a future caller builds a run
        -- by hand, and because a wide segmented strip still needs this branch.
        if item.fullWidth
           or (item.type == "segmented" and #(item.values or {}) > 2) then
            wide = true; break
        end
    end

    local cols = (wide and 1) or (grid and grid.cols) or fitColumns(run, availW)
    local colW   = math.floor((availW - (cols - 1) * COL_GAP) / cols)
    local labelCol
    -- A full-width run cannot use the page's shared column -- that one is
    -- measured against half a cell and would park the control a quarter of the
    -- way across. It gets the column measured for solo rows instead, so a
    -- fullWidth row lines up with the geared rows above and below it.
    if wide then labelCol = UI._soloCol
    elseif grid then labelCol = grid.labelCol
    else labelCol = runLabelColumn(run, colW) end
    local base   = parent:GetFrameLevel()
    local n      = #run
    -- One verdict per run; the cell loop reserves the gear slot from it.
    local runHasGear = false
    for _, it in ipairs(run) do
        if it.subOptions then runHasGear = true; break end
    end
    -- Per-column cursors, not a row counter. They agree exactly while every
    -- gear is closed -- and when one opens, its sub-rows push ONLY the cells
    -- of its own column down (user request, 31.07.2026). The expanded row used
    -- to leave the run and take the page's full width instead, which re-paired
    -- every row below it and made the whole grid jump on one click.
    local colY = {}
    for c = 0, cols - 1 do colY[c] = y end

    for idx = 1, n do
        local item  = run[idx]
        local col   = (idx - 1) % cols
        -- Last item, alone on its row: normally it takes the whole width rather
        -- than leaving a ragged gap beside it. On a grid page it does NOT --
        -- keeping its half and leaving the other empty IS the grid.
        local fullW = (not grid) and (idx == n) and (n % cols == 1)
        local cellX = CONTENT_PADDING + (fullW and 0 or col * (colW + COL_GAP))
        local cellW = fullW and availW or colW
        -- A spanning cell starts below BOTH columns; a half cell carries on
        -- from its own.
        local cellY = colY[col]
        if fullW then
            for c = 0, cols - 1 do if colY[c] < cellY then cellY = colY[c] end end
        end

        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", cellX, cellY)
        p:SetSize(cellW, CARD_H)
        p:SetFrameLevel(base + 1)
        p:Show()
        -- Only the page's own rows: a row popup lays its rows out through this
        -- same function, and its cards must not answer for a page row of the
        -- same label.
        if UI._building then UI._rowFrames[rowKey(item)] = p end

        local lead = 0
        if item.tooltip then
            local e = setRowIcon(makeRowIcon(parent), ICON_INFO, item.tooltip, nil, base + 5)
            e:ClearAllPoints()
            e:SetPoint("LEFT", parent, "TOPLEFT", cellX + 10, cellY - CARD_H / 2)
            lead = 22
        end

        -- A PAIRABLE gear row in a half cell: the gear sits at the cell's own
        -- right edge (the shared icon strip belongs to full-width rows only);
        -- opening it rebuilds the page with the sub-rows unfolded UNDER this
        -- cell, inside this column (placeSubColumn). The slot is reserved for
        -- EVERY cell of a run that contains gear rows -- a gearless neighbour
        -- whose switch ends 21px further right reads as a misalignment, which
        -- is the exact thing the icon-strip rule exists to prevent.
        local gearLead = 0
        if runHasGear then gearLead = 21 end
        -- On a strict-grid page EVERY half cell reserves the slot, occupied or
        -- not -- the per-run verdict above still left mixed pages ragged: two
        -- runs on one page can disagree, and a box ending 21px right of its
        -- neighbour's gear reads as misalignment (nameplate slot rows, user
        -- report 31.07.2026). cols == 1 is the sub-column, whose iconStrip
        -- already reserves this same slot -- adding it twice would indent the
        -- sub-rows against their own gear row.
        if grid and cols > 1 then gearLead = 21 end
        if item.subOptions then
            local key = rowKey(item)
            local g = setRowIcon(makeRowIcon(parent), ICON_GEAR, L["Extra settings"], function()
                UI.rowExpanded[key] = not UI.rowExpanded[key]
                UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
            end, base + 5)
            g:ClearAllPoints()
            g:SetPoint("RIGHT", parent, "TOPLEFT", cellX + cellW - 8, cellY - CARD_H / 2)
            gearLead = 21
        end

        -- A cell that spans the page keeps the same right-hand strip free as a
        -- gear row does, so the two line up where they meet down a page.
        --
        -- Deliberately NOT done for a half-width cell. fitColumns decided these
        -- two fit side by side by measuring label, track and value block against
        -- cellW; taking 42 px away afterwards would invalidate exactly that
        -- measurement -- and a value block that no longer fits is how rows ended
        -- up in the neighbouring column once already (3b5ca3f). Half-width cells
        -- align down their own column, which is the column the eye follows.
        --
        -- Inside a sub-column container the grid overrides the strip with the
        -- single gear slot, so the sub-rows end on the edge their own gear
        -- row reserved above them.
        local rightStrip = (fullW or cols == 1)
            and ((grid and grid.iconStrip) or ROW_ICON_STRIP) or 0

        -- Inline icons live between the label and the control, so the label
        -- column has to give up their width -- otherwise a long label runs
        -- straight under the swatch. Measured before the widget is sized.
        local inlineW = (item.inline and #item.inline > 0)
            and (#item.inline * INLINE_SLOT) or 0

        local widget = createWidget(parent, item)
        if widget then
            widget:SetWidth(cellW - 20 - lead - rightStrip - gearLead)
            if labelCol and widget.SetLabelWidth then
                widget:SetLabelWidth(math.max(20, labelCol - inlineW))
            end
            -- Size first, then lay out -- here, not at the client's
            -- convenience. A pooled row handed back at the width its next cell
            -- asks for raises no OnSizeChanged, so without this it would draw
            -- the control of the row it had before.
            if widget.Relayout then widget:Relayout() end
            widget:SetFrameLevel(base + 4)
            local wh = widget:GetHeight() or 22
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", parent, "TOPLEFT",
                cellX + 10 + lead, cellY - math.floor((CARD_H - wh) / 2))
            placeInlineIcons(parent, item, widget, base + 5)
            placeChangedDot(parent, item, widget, cellX - 2, cellY - CARD_H / 2, base + 6)
        end

        local used = ROW_H
        -- The filter unfolds a gear whose rows changed even if nobody opened it.
        if item.subOptions and (UI.rowExpanded[rowKey(item)]
                or (UI.onlyChanged and UI._building and item._vcChangedInside)) then
            used = used + placeSubColumn(parent, item, cellX, cellY - ROW_H, cellW)
        end
        if fullW then
            for c = 0, cols - 1 do colY[c] = cellY - used end
        else
            colY[col] = cellY - used
        end
    end

    local bottom = y
    for c = 0, cols - 1 do if colY[c] < bottom then bottom = colY[c] end end
    return bottom
end

-- A section is a HEADING, not a drawer.
--
-- It used to be both: every section started closed behind its own expander, and
-- then rows started folding away behind gears as well. Two collapse mechanisms
-- on one page is one too many -- you no longer know which control hides what,
-- and reaching a setting can cost two clicks in two different idioms.
--
-- The gear won because it says something: the rows behind it belong to the
-- switch it sits on. A section expander says only "there is more below", which
-- the heading already says by existing. So sections are always open, and the
-- page is short because its dependent rows hang off their own switches.
--
-- ONE sanctioned exception (30.07.2026, at the user's request): a section may
-- declare `collapsible = true` and start closed with `collapsed = true` --
-- for a list that is fully mirrored elsewhere on the page and only repeats it
-- in longhand. State is per session, keyed like the row gears; the spec table
-- keeps its items either way, so the settings search and the override capture
-- still see every row of a closed section.
UI.sectionOpen = UI.sectionOpen or {}

local function placeSection(parent, section, y)
    local title = section.title or "Section"

    -- Space ABOVE a section heading, and clearly more than the gap between the
    -- cards inside one. When both gaps are the same the page reads as one long
    -- list and the headings stop grouping anything.
    y = y - 24

    -- Remembered per build: ScrollToSection turns a title into this offset.
    local off = math.max(0, -y - 8)
    if UI._sectionY then UI._sectionY[title] = off end
    local count = countRows(section.items)
    -- Top-level headings only: a heading inside another section is a
    -- sub-heading, and the jump chips are a table of contents, not an index.
    if UI._building and (UI._sectionDepth or 0) == 0 then
        UI._sectionList[#UI._sectionList + 1] = { title = title, y = off }
    end

    local open, onClick = true, nil
    if section.collapsible then
        local key = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
            .. "/s/" .. tostring(section.key or title)
        local saved = UI.sectionOpen[key]
        if saved == nil then open = not section.collapsed else open = saved end
        onClick = function()
            UI.sectionOpen[key] = not open
            UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
        end
    end

    local hdr = acquire("collapsible", parent)
    if hdr then
        hdr:_vcSetup(title, open, onClick, count)
    else
        hdr = UI:CreateCollapsibleHeader(parent, title, open, onClick, count)
    end
    hdr:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    y = y - 26

    if not open then return y end
    UI._sectionDepth = (UI._sectionDepth or 0) + 1
    y = placeItemList(parent, section.items or {}, y)
    UI._sectionDepth = UI._sectionDepth - 1
    return y
end

local CARD_TYPES = { toggle = true, checkbox = true, dropdown = true, editbox = true, slider = true, color = true, segmented = true }

placeItem = function(parent, item, y)
    if item.type == "spacer" then
        return y - (item.height or 8)
    end
    if item.type == "group" then
        return UI:PlaceGroup(parent, item, y)
    end
    if item.type == "section" then
        return placeSection(parent, item, y)
    end
    if item.type == "header" then
        y = y - 12
        -- A plain heading at page level is a chapter too, on the pages that
        -- never adopted sections; it gets a jump chip like a section does.
        if UI._building and (UI._sectionDepth or 0) == 0 and item.text and item.text ~= "" then
            local off = math.max(0, -y - 8)
            UI._sectionY[item.text] = off
            UI._sectionList[#UI._sectionList + 1] = { title = item.text, y = off }
        end
    end

    local widget, h = createWidget(parent, item)
    if not widget then return y end

    local base   = parent:GetFrameLevel()
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING

    if CARD_TYPES[item.type] then
        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        p:SetSize(availW, h)
        p:SetFrameLevel(base + 1)
        p:Show()
        widget:SetFrameLevel(base + 4)

        -- The label identifies the row across rebuilds, which is what keeps a
        -- gear open while you change the value under it. Two rows on one page
        -- CAN share a label though -- the trinket page has an "Order" row per
        -- trinket slot -- and then one gear opens both. item.subKey is the way
        -- out: a page that builds repeated rows says which is which.
        local key = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
            .. "/r/" .. tostring(item.subKey or item.label or item.text or item)
        local expanded = UI.rowExpanded[key]
            or (UI.onlyChanged and UI._building and item._vcChangedInside)
        if UI._building then UI._rowFrames[key] = p end

        -- THE ICON STRIP IS ALWAYS RESERVED, AND EACH ICON HAS A FIXED SLOT.
        --
        -- It used to be neither. The strip was as wide as the row happened to
        -- need, so a switch on a row with a gear sat 21 px left of one without,
        -- and 42 px left if the row also had an info dot -- reading down a page,
        -- the controls stepped in and out. And whichever icon came first took
        -- the outermost slot, so the gear was not in one place either.
        --
        -- Now: slot 1 (outermost) belongs to the gear, slot 2 to the info dot,
        -- occupied or not, and every control ends at the same x on every row.
        -- The cost is ROW_ICON_STRIP of width on rows carrying no icon at all,
        -- which is what buys the alignment.
        local slot1 = CONTENT_PADDING + availW - 6
        local slot2 = slot1 - ROW_ICON_SLOT
        -- Anchored by RIGHT to the row's middle, not by TOPRIGHT to a fixed 7
        -- below its top: rows differ in height, and a constant offset centred
        -- exactly one of them. It also makes the grow-on-hover symmetric.
        local midY = y - h / 2
        if item.subOptions then
            local g = setRowIcon(makeRowIcon(parent), ICON_GEAR, L["Extra settings"], function()
                UI.rowExpanded[key] = not expanded
                UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab)
            end, base + 5)
            g:ClearAllPoints(); g:SetPoint("RIGHT", parent, "TOPLEFT", slot1, midY)
        end
        if item.tooltip then
            local e = setRowIcon(makeRowIcon(parent), ICON_INFO, item.tooltip, nil, base + 5)
            e:ClearAllPoints(); e:SetPoint("RIGHT", parent, "TOPLEFT", slot2, midY)
        end

        -- A one-line row like every other: no -14 nudge to clear a label that
        -- once sat above the track.
        widget:SetWidth(math.max(120, availW - 20 - ROW_ICON_STRIP))
        -- After SetWidth, same order placeColumns uses: the row lays itself out
        -- from the width it was given, then the label column pins where the
        -- control begins.
        if UI._soloCol and widget.SetLabelWidth then widget:SetLabelWidth(UI._soloCol) end
        if widget.Relayout then widget:Relayout() end

        -- Centred in the card by its REAL height, not hung from the top edge.
        -- The height createWidget reports is the height of the ROW -- what the
        -- card should be -- and it is not always what the control measures: a
        -- toggle reports 26 and builds a 22 px container, so hanging it from the
        -- top left it sitting 2 px high. Same arithmetic placeColumns has always
        -- used for its cells; placeItem was the one that skipped it.
        local wh = widget:GetHeight() or h
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT",
            CONTENT_PADDING + 10, y - math.floor((h - wh) / 2))
        -- Two pixels left of the card edge: the talent-override bar sits at
        -- widget-left minus 6 (card x 18-20), and a dot centred on the edge
        -- reached x 20. Centred at 12 it ends at 18 and the two never meet.
        placeChangedDot(parent, item, widget, CONTENT_PADDING - 2, y - h / 2, base + 6)

        y = y - h - CARD_GAP
        if expanded and item.subOptions then
            y = placeItemList(parent, item.subOptions, y)
        end
        return y
    end

    if item.type == "button" or item.type == "iconbutton" then
        local wh    = widget:GetHeight() or 24
        local cardH = wh + CARD_VPAD * 2
        local p = makePanel(parent)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        p:SetSize(availW, cardH)
        p:SetFrameLevel(base + 1)
        p:Show()
        widget:SetFrameLevel(base + 4)

        -- A prominent action is CENTRED in its row; an ordinary one sits at the
        -- left edge like every other control. That is the split the reference
        -- draws between its ordinary button and its wide one -- "Open Edit Mode"
        -- is 360px hugging the left of a 940px card, which reads as unanchored
        -- rather than as the main thing on the page.
        --
        -- Ours keeps its card, where the reference drops it. Our pages read as a
        -- stack of cards, and a card-less row in the middle of them would look
        -- like a hole rather than emphasis.
        local xo = CONTENT_PADDING + 10
        if item.primary then
            local bw = widget:GetWidth() or 120
            xo = math.max(xo, CONTENT_PADDING + math.floor((availW - bw) / 2))
        end
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xo, y - CARD_VPAD)
        return y - cardH - CARD_GAP
    end

    if item.type == "desc" then
        widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y - 5)
        return y - h - 10
    end

    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
    -- Full-width rows carry their inline icons too: the nameplate style rows
    -- drop out of the grid whenever the page is narrow, and a swatch that
    -- vanished with the pairing would look like a lost setting.
    placeInlineIcons(parent, item, widget, (parent:GetFrameLevel() or 1) + 5)
    return y - h
end

-- A gear row may join the grid when its page says so (item.pairable) -- open
-- or closed. An opened one stays in its cell and unfolds inside its own
-- column (placeSubColumn via placeColumns), so no other cell of the grid
-- moves sideways when a gear is clicked.
local function joinsRun(it)
    if not COMPACT[it.type] or it.fullWidth then return false end
    -- A 3+-way segmented strip cannot live in a half cell -- and worse:
    -- placeColumns' wide flag is per RUN, so one such strip inside a run
    -- dragged every neighbouring row to full width with it (the minimap
    -- zone bar pulled the clock and date rows along, 31.07.2026). It leaves
    -- the run; the neighbours keep pairing.
    if it.type == "segmented" and #(it.values or {}) > 2 then return false end
    if it.subOptions then return it.pairable == true end
    return true
end

placeItemList = function(parent, items, y)
    -- Only while a page is being built: a row popup lays its rows out through
    -- this same function, and its rows are not the page's to filter.
    if UI.onlyChanged and UI._building then items = filterChanged(items) end
    local i = 1
    while i <= #items do
        local it = items[i]
        -- fullWidth takes the row OUT of the run, it does not widen the run.
        --
        -- It used to do the latter by accident: placeColumns saw one such row and
        -- dropped the whole run to a single column, so asking for one wide
        -- dropdown collapsed the fourteen colour swatches underneath it into one
        -- tall list. The flag names a property of the ROW, and now behaves like
        -- one -- the row is placed on its own and its neighbours keep their grid.
        if joinsRun(it) then
            local run = {}
            while items[i] and joinsRun(items[i]) do
                run[#run + 1] = items[i]; i = i + 1
            end
            y = placeColumns(parent, run, y)
        else
            y = placeItem(parent, it, y)
            i = i + 1
        end
    end
    return y
end

-- A row whose value is overridden for the ACTIVE talent group gets an accent bar
-- on its left edge. Applied here because every widget type comes through the one
-- funnel above, and cleared on every build rather than only set: widgets are
-- pooled, so a mark left behind would travel to an unrelated row on the next
-- page. Nothing about the row moves -- the bar sits in the padding.
local function applyOverrideMark(w, item)
    if not w or type(w.CreateTexture) ~= "function" then return end

    local on = false
    if item._vcOverrideId and ns.HasOverride and ns.ActiveTalentGroup then
        on = ns:HasOverride(ns:ActiveTalentGroup(), item._vcOverrideId)
    end

    if not on then
        if w._vcOvMark then w._vcOvMark:Hide() end
        return
    end

    local mark = w._vcOvMark
    if not mark then
        mark = w:CreateTexture(nil, "OVERLAY")
        mark:SetPoint("TOPLEFT",    w, "TOPLEFT",    -6, 1)
        mark:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", -6, -1)
        mark:SetWidth(2)
        w._vcOvMark = mark
    end
    local a = ns.COLORS.accent
    mark:SetColorTexture(a.r, a.g, a.b, 0.95)
    mark:Show()
end

-- A row whose `disabled` reads true is dimmed and stops taking clicks. The
-- inline colour swatch has said that about itself from the start -- a swatch
-- that cannot do anything says so rather than lying -- while a ROW could only
-- ever look available with a setter that changed nothing, which is the same lie
-- one level up. Widgets are pooled, so the state is stored and compared: a
-- widget handed to a row without `disabled` comes back at full alpha.
--
-- Mouse state is REMEMBERED rather than switched back on. Blanket EnableMouse
-- (true) would hand clicks to children that never took any.
local function applyDisabled(w, item)
    if not (w and w.SetAlpha) then return end
    local off = (item.disabled and item.disabled()) and true or false
    if w._vfuiDisabled == off then return end
    w._vfuiDisabled = off
    w:SetAlpha(off and 0.35 or 1)
    local function mouse(f)
        if not f.EnableMouse then return end
        if off then
            if f._vfuiMouseWas == nil then f._vfuiMouseWas = f:IsMouseEnabled() end
            f:EnableMouse(false)
        elseif f._vfuiMouseWas ~= nil then
            f:EnableMouse(f._vfuiMouseWas)
            f._vfuiMouseWas = nil
        end
    end
    mouse(w)
    if w.GetChildren then
        for _, c in ipairs({ w:GetChildren() }) do mouse(c) end
    end
end

-- Rebinding the local: every call site below reads this upvalue, so the mark is
-- applied to all of them without touching the fifteen return points inside.
local rawCreateWidget = createWidget
createWidget = function(parent, item)
    local w, h, wide = rawCreateWidget(parent, item)
    applyOverrideMark(w, item)
    applyDisabled(w, item)
    return w, h, wide
end

function UI:PlaceGroup(parent, group, y)
    local layout = group.layout or "row"
    local items  = group.items or {}
    local availW = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
    local base   = parent:GetFrameLevel()

    local panel = (group.noCard ~= true) and makePanel(parent) or nil
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y)
        panel:SetFrameLevel(base + 1)
        panel:Show()
    end

    if layout == "row" then
        local placed = {}
        local gap = group.gap or 8
        for _, item in ipairs(items) do
            local widget, h, w = createWidget(parent, item)
            if widget then
                placed[#placed + 1] = { widget = widget, w = w, h = h, item = item }
            end
        end

        -- A row of CONTROLS is N equal slots -- not N controls at whatever width
        -- they happen to report. The cursor below used to advance by that
        -- reported width, and a slider reported a flat 280 while its row (label,
        -- track and value block together) was closer to 400, so the next control
        -- was laid down on top of the previous one. Two sliders side by side is
        -- the commonest shape there is, which is why whole pages looked broken.
        --
        -- Equal slots need no reported width at all, so nothing here can fall out
        -- of step again.
        --
        -- Three shapes, because a row means three different things:
        --   all controls  -> equal slots
        --   controls + an action -> the action keeps its label's size, the
        --                    controls take the rest ("Add" beside a text field)
        --   nothing but buttons -> one width for all of them
        -- Anything else (an icon button, a module's own frame) keeps its natural
        -- width: stretching those is not what that row means.
        local inner    = availW - 20
        local n        = #placed
        local nFlex    = 0
        local allPlain = n > 1
        for _, p in ipairs(placed) do
            if COMPACT[p.item.type] then nFlex = nFlex + 1 end
            if p.item.type ~= "button" then allPlain = false end
        end

        local function spread(widthOf)
            -- On a grid page the column belongs to the page, not to this row --
            -- otherwise an explicitly paired row would align with itself and
            -- with nothing else on the page.
            local grid = UI._grid
            local labelCol = grid and grid.labelCol
            for _, p in ipairs(placed) do
                local w = widthOf(p)
                if w then
                    if not grid then labelCol = labelCol or runLabelColumn(items, w) end
                    p.w = w
                    p.widget:SetWidth(w)
                    if labelCol and p.widget.SetLabelWidth then p.widget:SetLabelWidth(labelCol) end
                end
            end
        end

        if n > 1 and nFlex == n then
            -- Every item is a control: N equal slots, and one measured label
            -- column across the whole row like the other two placement paths.
            local slotW = math.floor((inner - gap * (n - 1)) / n)
            spread(function() return slotW end)

        elseif n > 1 and nFlex > 0 then
            -- Mixed: a control beside an action. The button keeps the size its
            -- label needs and the controls take everything else, so the pair
            -- reaches the far edge instead of huddling at the left of a
            -- full-width card. This is the shape "Add" next to a text field and
            -- "New group" next to a dropdown have, and both used to float.
            local fixedW = 0
            for _, p in ipairs(placed) do
                if not COMPACT[p.item.type] then fixedW = fixedW + p.w end
            end
            local flexW = math.floor((inner - fixedW - gap * (n - 1)) / nFlex)
            -- Below this the control is too cramped to be worth stretching, and
            -- leaving the row at its natural widths reads better than a stub.
            if flexW >= 140 then
                spread(function(p) return COMPACT[p.item.type] and flexW or nil end)
            end

        elseif allPlain then
            -- A row of nothing but buttons: all of them take the widest one's
            -- width. Buttons of three different lengths side by side read as an
            -- accident rather than a set -- the reference gives every button in
            -- such a row one width for exactly this reason.
            --
            -- But only while they FIT, and that is not a given in every language.
            -- A declared width is a FLOOR, not a cap: buttonSetup sizes to
            -- max(config.width, text + 36), so a longer translation pushes the
            -- widest button past its number -- and equalising then multiplies
            -- that overshoot by N and carries the last button off the card. The
            -- Vulslot row is 150/220/110 in English and fits; in German the
            -- middle label grows and all three inherit it.
            --
            -- Their own widths usually still fit (562 of 725 in that case), so
            -- the first fallback is simply to leave them alone. A set of unequal
            -- buttons reads better than a set with one of them cut off.
            local widest, natural = 0, 0
            for i, p in ipairs(placed) do
                if p.w > widest then widest = p.w end
                natural = natural + p.w + (i > 1 and gap or 0)
            end
            if widest * n + gap * (n - 1) <= inner then
                spread(function() return widest end)
            elseif natural > inner then
                -- Not even their natural widths fit: equal slots is all that is
                -- left, and a slightly cramped label beats one off the edge.
                spread(function() return math.floor((inner - gap * (n - 1)) / n) end)
            end
        end

        local totalW = 0
        for i, p in ipairs(placed) do
            totalW = totalW + p.w + (i > 1 and gap or 0)
        end

        -- centre on ACTUAL widget heights: the createWidget row estimate differs
        local maxWH = 0
        for _, p in ipairs(placed) do
            p.wh = p.widget:GetHeight() or p.h
            if p.wh > maxWH then maxWH = p.wh end
        end
        local PAD   = CARD_VPAD
        local cardH = maxWH + PAD * 2

        local startX = CONTENT_PADDING + 10
        if group.align == "center" then
            startX = CONTENT_PADDING + math.max(10, math.floor((availW - totalW) / 2))
        end

        local cursorX = startX
        for _, p in ipairs(placed) do
            if panel then p.widget:SetFrameLevel(base + 4) end
            local yo = y - PAD - math.floor((maxWH - p.wh) / 2)
            p.widget:SetPoint("TOPLEFT", parent, "TOPLEFT", cursorX, yo)
            -- An explicitly paired row is a THIRD placement path, next to
            -- placeColumns and placeItem, and it was the one the style rows take
            -- -- so "Rand" and "Hintergrund" drew without their swatch and gear
            -- while the slot rows below them had theirs (user report,
            -- 02.08.2026). Every path that places a widget places its icons.
            placeInlineIcons(parent, p.item, p.widget, base + 5)
            placeChangedDot(parent, p.item, p.widget, cursorX - 6, yo - p.wh / 2, base + 6, true)
            cursorX = cursorX + p.w + gap
        end
        if panel then panel:SetSize(availW, cardH) end
        return y - cardH - CARD_GAP

    elseif layout == "columns" then
        local availWidth = (parent:GetWidth() or 540) - 2 * CONTENT_PADDING
        -- group.columns is deliberately not consulted. Every module that
        -- declares it says 2, because two was the only shape on offer; honouring
        -- it would stand a two-column group beside an auto-packed three-column
        -- run on the same page. One rule answers for both paths. Its verdict is
        -- computed on the auto path's cells, which are the narrower of the two,
        -- so it errs on the safe side here rather than the other way round.
        local cols       = fitColumns(items, availWidth)
        local colWidth   = math.floor(availWidth / cols)

        local rowItems = {}
        local rowMaxH  = 0
        local curY     = y

        local function flushRow()
            local cellW = colWidth - 14
            -- One measured label column for the whole row, exactly as in the
            -- two-column path. Without it every slider here fell back to the
            -- 120px default and the second column's label was cut to
            -- "Nachrichte...".
            local labelCol = runLabelColumn(rowItems, cellW)
            for i, ri in ipairs(rowItems) do
                -- clamp to column width: a toggle's right-anchored switch would
                -- otherwise overlap the next column's label
                if ri.width == nil and (ri.type == "toggle" or ri.type == "checkbox") then
                    ri.width = cellW
                end
                local widget = createWidget(parent, ri)
                if widget then
                    -- A slider row sizes itself from its own width. This path
                    -- never set one, so the row kept the width it computed from
                    -- config.width and ran straight into the next column.
                    if ri.type == "slider" then
                        widget:SetWidth(cellW)
                        if labelCol and widget.SetLabelWidth then widget:SetLabelWidth(labelCol) end
                    end
                    if widget.Relayout then widget:Relayout() end
                    if panel then widget:SetFrameLevel(base + 4) end
                    local xo = CONTENT_PADDING + (panel and 6 or 0) + (i - 1) * colWidth
                    local yo = curY - (panel and 4 or 0)
                    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", xo, yo)
                    placeInlineIcons(parent, ri, widget, base + 5)
                    placeChangedDot(parent, ri, widget, xo - 6, yo - (widget:GetHeight() or 22) / 2, base + 6, true)
                end
            end
            curY = curY - rowMaxH
            rowItems = {}
            rowMaxH  = 0
        end

        for _, item in ipairs(items) do
            table.insert(rowItems, item)
            local eh = estimateHeight(item)
            if eh > rowMaxH then rowMaxH = eh end
            if #rowItems >= cols then flushRow() end
        end
        if #rowItems > 0 then flushRow() end

        if panel then panel:SetSize(availW, (y - curY) + 8); curY = curY - 8 end
        return curY
    end

    if panel then panel:Hide() end
    return y
end

-- True if the module's options are on screen, directly or as its container's active tab.
function UI:IsModuleActive(key)
    if UI.currentModule == key then return true end
    local m = ns.modules[key]
    if not m then return false end
    if m.parentTab and UI.currentModule == m.parentTab and UI.currentTab == key then
        return true
    end
    -- A page member has no page of its own: it is rendered as a section of its
    -- page, which is itself a tab of a container. Without this the answer was
    -- always no, so those modules never redrew their own options and lists that
    -- an Add or Remove button had just changed stayed stale.
    if m._pageKey and (UI.currentTab == m._pageKey or UI.currentModule == m._pageKey) then
        return true
    end
    return false
end

-- Scrolls the open page so the named section's heading sits at the top edge.
-- Open a gear row from OUTSIDE the page (a preview's click-to-navigate). The
-- suffix is the row's subKey (or its label, for rows without one) -- the same
-- tail rowKey builds, so a module needs no knowledge of the full recipe.
-- Only opens; a second click on a preview icon should not close settings the
-- user is looking at.
function UI:ExpandRow(subKey)
    UI.rowExpanded[(UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
        .. "/r/" .. tostring(subKey)] = true
end

-- Consumer: the action-bar preview's click-to-navigate; the title must be the
-- TRANSLATED section title, exactly as the page declared it.
function UI:ScrollToSection(title)
    local f = UI.mainFrame
    local off = f and UI._sectionY and UI._sectionY[title]
    if not off then return end
    local maxOff = math.max(0,
        (f.scrollChild:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
    f.scroll:SetVerticalScroll(math.min(off, maxOff))
end

-- ---------------------------------------------------------------------------
-- Reveal a row: open its page, unfold what hides it, scroll to it, light it up.
-- Used by the settings search and by the "recently changed" list. The target
-- carries what those two know: { mod, tab, label | subKey, parents = { gear
-- row labels above it }, sectionKey (collapsible section holding it),
-- sectionClosed, section (title, the fallback when the row is not found) }.
-- ---------------------------------------------------------------------------
local flashFrame
local function flashRow(p)
    local fl = flashFrame
    if not fl then
        fl = CreateFrame("Frame", nil, UIParent)
        fl:EnableMouse(false)
        local fill = fl:CreateTexture(nil, "ARTWORK")
        fill:SetAllPoints(fl)
        fl._fill = fill
        fl._edges = {}
        for i, s in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local t = fl:CreateTexture(nil, "OVERLAY")
            if s == "TOP" or s == "BOTTOM" then
                t:SetPoint(s .. "LEFT"); t:SetPoint(s .. "RIGHT"); t:SetHeight(2)
            else
                t:SetPoint("TOP" .. s); t:SetPoint("BOTTOM" .. s); t:SetWidth(2)
            end
            fl._edges[i] = t
        end
        -- Two pulses and a long fade: enough to draw the eye to where the
        -- page stopped, gone before it becomes decoration.
        local ag = fl:CreateAnimationGroup()
        local function step(order, from, to, dur)
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(from); a:SetToAlpha(to); a:SetDuration(dur); a:SetOrder(order)
        end
        step(1, 0, 1, 0.12); step(2, 1, 0.25, 0.30); step(3, 0.25, 1, 0.12); step(4, 1, 0, 1.2)
        ag:SetScript("OnFinished", function() fl:Hide() end)
        fl._anim = ag
        flashFrame = fl
    end
    if fl._anim:IsPlaying() then fl._anim:Stop() end
    local a = ns.COLORS.accent
    fl._fill:SetColorTexture(a.r, a.g, a.b, 0.14)
    for _, t in ipairs(fl._edges) do t:SetColorTexture(a.r, a.g, a.b, 0.9) end
    -- Inside the scroll child, so the scroll frame clips it like the row.
    fl:SetParent(p:GetParent())
    fl:SetFrameLevel((p:GetFrameLevel() or 1) + 8)
    fl:ClearAllPoints()
    fl:SetPoint("TOPLEFT",     p, "TOPLEFT",     -3,  3)
    fl:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT",  3, -3)
    fl:SetAlpha(0)
    fl:Show()
    fl._anim:Play()
end

function UI:RevealRow(t)
    if type(t) ~= "table" or not t.mod or not ns.modules[t.mod] then return end
    local f = UI:CreateMainFrame()
    if not f:IsShown() then UI:ToggleMainFrame() end
    UI:ShowModulePage(t.mod)
    if t.tab and t.tab ~= "default" and UI.currentTab ~= t.tab then
        -- Only a tab the page really has: a stale record would otherwise
        -- build an empty page under a tab that no longer exists.
        local m = ns.modules[UI.currentModule]
        if m and m.tabs then
            for _, tb in ipairs(m.tabs) do
                if tb.id == t.tab then UI:ShowTab(t.tab); break end
            end
        end
    end
    local prefix = (UI._currentBuildKey or "?") .. "/" .. (UI.currentTab or "")
    local rk = prefix .. "/r/" .. tostring(t.subKey or t.label)
    local rebuild = false
    if t.parents then
        for _, pl in ipairs(t.parents) do
            local k = prefix .. "/r/" .. tostring(pl)
            if not UI.rowExpanded[k] then UI.rowExpanded[k] = true; rebuild = true end
        end
    end
    if t.sectionKey then
        local k = prefix .. "/s/" .. tostring(t.sectionKey)
        if UI.sectionOpen[k] == false or (UI.sectionOpen[k] == nil and t.sectionClosed) then
            UI.sectionOpen[k] = true; rebuild = true
        end
    end
    -- The changed-only filter must not hide the very row that was asked for.
    if UI.onlyChanged and not UI._rowFrames[rk] then
        UI.onlyChanged = false; rebuild = true
    end
    if rebuild then UI:BuildOptionsPage(UI._currentBuildKey, UI.currentTab) end
    local buildKey, buildTab = UI._currentBuildKey, UI.currentTab
    -- Next frame: the rows were anchored this frame and measure against a
    -- scroll child whose height was set a moment ago.
    ns.NextFrame(function()
        if not (f:IsShown() and UI._currentBuildKey == buildKey and UI.currentTab == buildTab) then return end
        local p = UI._rowFrames[rk]
        local top, ctop = p and p:GetTop(), f.scrollChild:GetTop()
        if p and p:IsShown() and top and ctop then
            local maxOff = math.max(0, (f.scrollChild:GetHeight() or 0) - (f.scroll:GetHeight() or 0))
            f.scroll:SetVerticalScroll(math.max(0, math.min(ctop - top - 40, maxOff)))
            flashRow(p)
        elseif t.section then
            UI:ScrollToSection(t.section)
        end
        if UI.UpdateNavActive then UI:UpdateNavActive() end
    end)
end

-- ---------------------------------------------------------------------------
-- Recently changed: every setter on the page reports into an account-wide
-- ring, newest first, so the overview can list what was touched last and jump
-- back to it. Sliders report on every drag step; the ring dedupes by row, so
-- one row is one entry however long the drag was.
-- ---------------------------------------------------------------------------
local RECENT_CHANGES_MAX = 12
local function noteChange(rec)
    local g = ns.db and ns.db.global
    if not g then return end
    local list = g.recentChanges
    if type(list) ~= "table" then list = {}; g.recentChanges = list end
    for i = #list, 1, -1 do
        local e = list[i]
        if type(e) == "table" and e.mod == rec.mod and e.tab == rec.tab
           and e.label == rec.label and e.subKey == rec.subKey then
            table.remove(list, i)
        end
    end
    table.insert(list, 1, rec)
    for i = #list, RECENT_CHANGES_MAX + 1, -1 do table.remove(list, i) end
end

local function wrapRecent(items, modKey, tabId, skip)
    if skip then return end
    local function wrap(list, section, parents)
        for _, it in ipairs(list) do
            if type(it) == "table" then
                if it.type == "section" then
                    wrap(it.items or {}, it.title, parents)
                else
                    if it.items then wrap(it.items, section, parents) end
                    if it.subOptions then
                        local chain = {}
                        for i, v in ipairs(parents) do chain[i] = v end
                        chain[#chain + 1] = it.subKey or it.label
                        wrap(it.subOptions, section, chain)
                    end
                    if COMPACT[it.type] and type(it.set) == "function" and it.label
                       and not it._vcRecentWrapped then
                        it._vcRecentWrapped = true
                        local setter = it.set
                        -- Stored by ENGLISH key, never by the translated text
                        -- (the house rule in Core/Locale.lua): the overview
                        -- translates on display, and a language switch keeps
                        -- every entry readable and reachable.
                        local ek = ns.EnglishKey and function(s) return ns:EnglishKey(s) end
                            or function(s) return s end
                        local label, subKey = ek(it.label), it.subKey
                        local chain
                        if #parents > 0 then
                            chain = {}
                            for i, v in ipairs(parents) do chain[i] = ek(v) end
                        end
                        local sectionKey = section and ek(section) or nil
                        it.set = function(...)
                            setter(...)
                            noteChange({ mod = modKey, tab = tabId, label = label, subKey = subKey,
                                section = sectionKey, parents = chain, t = time() })
                        end
                    end
                end
            end
        end
    end
    wrap(items, nil, {})
end

-- ---------------------------------------------------------------------------
-- The strip above the page: one chip per heading (click scrolls there, the
-- heading under the top edge is lit), and at the right the changed-only
-- filter with its count. Shown only when it has something to say -- two or
-- more headings, or a row that differs from its default.
-- ---------------------------------------------------------------------------
local NAV_CHIP_H, NAV_GAP = 20, 6
local navChips = {}

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
        c.text:SetTextColor(1, 1, 1)
    else
        c:SetBackdropColor(0.12, 0.12, 0.15, 0.95)
        c:SetBackdropBorderColor(b.r, b.g, b.b, 0.6)
        c.text:SetTextColor(0.82, 0.82, 0.88)
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
    hl:SetColorTexture(1, 1, 1, 0.05)
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
    if mod.tabs and #mod.tabs > 1 then
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
        local desc = createWidget(parent, {
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
        local ok, result = pcall(mod.GetOptions, mod, tabId)
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
        local note = createWidget(parent, { type = "desc",
            text = L["Nothing on this page differs from its defaults."], width = availW })
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", CONTENT_PADDING, y - 4)
        y = y - math.max(24, note:GetDescHeight() + 10)
    end

    local totalHeight = math.max(400, math.abs(y) + 20)
    parent:SetHeight(totalHeight)

    layoutTop(f, layoutPageNav(f, changedN), hh)
    UI:UpdateNavActive()
end
