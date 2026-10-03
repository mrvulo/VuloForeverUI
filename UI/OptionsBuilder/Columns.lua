-- VuloForeverUI / UI / OptionsBuilder / Columns: measured label columns, the column count of a run, the strict page grid and the sub-column container.
local _, ns = ...
local UI = ns.UI
local OB = UI._OB
local poolHost = OB.poolHost
local acquire = OB.acquire
local COMPACT = OB.COMPACT
local COL_GAP = OB.COL_GAP
local ROW_ICON_STRIP = OB.ROW_ICON_STRIP

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
            local e = UI.SliderEndWidth and UI.SliderEndWidth(item.min, item.max, item.step, item.suffix) or 90
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

-- for the OptionsBuilder files loaded after this one
OB.runLabelColumn = runLabelColumn
OB.fitColumns = fitColumns
OB.collectCompact = collectCompact
OB.pageLabelColumn = pageLabelColumn
OB.soloLabelColumn = soloLabelColumn
OB.rowKey = rowKey
OB.makeSubColumn = makeSubColumn
