-- VuloForeverUI / UI / OptionsBuilder / Group: UI:PlaceGroup, the row and column layouts of a group item.
local _, ns = ...
local UI = ns.UI
local OB = UI._OB
local CONTENT_PADDING = OB.CONTENT_PADDING
local estimateHeight = OB.estimateHeight
local COMPACT = OB.COMPACT
local CARD_GAP = OB.CARD_GAP
local CARD_VPAD = OB.CARD_VPAD
local makePanel = OB.makePanel
local placeChangedDot = OB.placeChangedDot
local runLabelColumn = OB.runLabelColumn
local fitColumns = OB.fitColumns
local placeInlineIcons = OB.placeInlineIcons

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
            local widget, h, w = OB.createWidget(parent, item)
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
                local widget = OB.createWidget(parent, ri)
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
