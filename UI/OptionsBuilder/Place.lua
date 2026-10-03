-- VuloForeverUI / UI / OptionsBuilder / Place: placing rows: column runs, sections, single items and item lists, plus the override and disabled marks.
local _, ns = ...
local UI = ns.UI
local L = ns.L
local OB = UI._OB
local CONTENT_PADDING = OB.CONTENT_PADDING
local acquire = OB.acquire
local COMPACT = OB.COMPACT
local COL_GAP = OB.COL_GAP
local ROW_H = OB.ROW_H
local CARD_GAP = OB.CARD_GAP
local CARD_H = OB.CARD_H
local CARD_VPAD = OB.CARD_VPAD
local makePanel = OB.makePanel
local ICON_INFO = OB.ICON_INFO
local ICON_GEAR = OB.ICON_GEAR
local ROW_ICON_SLOT = OB.ROW_ICON_SLOT
local ROW_ICON_STRIP = OB.ROW_ICON_STRIP
local placeChangedDot = OB.placeChangedDot
local countRows = OB.countRows
local filterChanged = OB.filterChanged
local makeRowIcon = OB.makeRowIcon
local setRowIcon = OB.setRowIcon
local runLabelColumn = OB.runLabelColumn
local fitColumns = OB.fitColumns
local rowKey = OB.rowKey
local INLINE_SLOT = OB.INLINE_SLOT
local placeInlineIcons = OB.placeInlineIcons
local placeSubColumn = OB.placeSubColumn

local placeItem, placeItemList  -- forward decls: mutually recursive via sections

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

        local widget = OB.createWidget(parent, item)
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

    local widget, h = OB.createWidget(parent, item)
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
-- Across the split files the upvalue is OB.createWidget, read at call time.
local rawCreateWidget = OB.createWidget
OB.createWidget = function(parent, item)
    local w, h, wide = rawCreateWidget(parent, item)
    applyOverrideMark(w, item)
    applyDisabled(w, item)
    return w, h, wide
end

-- for the OptionsBuilder files loaded after this one
OB.placeItemList = placeItemList
