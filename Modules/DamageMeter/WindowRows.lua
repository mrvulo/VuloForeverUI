-- VuloForeverUI / Modules / DamageMeter / WindowRows: row icons, a window's paint and visibility methods, and the rows themselves
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local P  = DM._win

local WHITE = DM.WHITE

-- ---------------------------------------------------------------- icons --

local ICON_STYLES = {
    { value = "none",      text = "None" },
    { value = "spec",      text = "Spec icons" },
    { value = "blizzard",  text = "Blizzard class icons" },
    { value = "epic",      text = "Epic" },
    { value = "fantasy1",  text = "Fantasy I" },
    { value = "fantasy2",  text = "Fantasy II" },
}
function DM.IconStyleValues()
    local v = {}
    for i, e in ipairs(ICON_STYLES) do v[i] = { value = e.value, text = L[e.text] } end
    return v
end

local function zoomCoords(l, r, t, b, zoom)
    if not zoom or zoom <= 0 then return l, r, t, b end
    local w, h = r - l, b - t
    return l + w * zoom, r - w * zoom, t + h * zoom, b - h * zoom
end

-- Paints the row icon for a source; returns the width the icon takes.
-- classFilename and specIconID are NeverSecret, so both may be read.
function DM.ResolveIcon(src, tex, size)
    local db = DM.db()
    local style = db.iconStyle or "spec"
    if style == "none" then tex:Hide(); return 0 end
    local classFile = src and src.classFilename
    if type(classFile) ~= "string" or DM.IsSecret(classFile) then classFile = nil end
    local spec = src and src.specIconID
    if type(spec) ~= "number" or DM.IsSecret(spec) or spec == 0 then spec = nil end
    local zoom = db.classIconZoom or 0

    if style == "spec" and spec then
        tex:SetTexture(spec)
        tex:SetTexCoord(zoomCoords(0, 1, 0, 1, zoom))
    elseif classFile and classFile ~= "" then
        local path, coords
        if style == "spec" or style == "blizzard" then
            path, coords = ns:GetClassIcon(classFile)
            if coords then coords = { zoomCoords(coords[1], coords[2], coords[3], coords[4], zoom) } end
        else
            local sheet = style == "epic" and "vuloepic" or style == "fantasy1" and "vulofantasy1" or "vulofantasy2"
            path, coords = ns:GetVuloClassIcon(classFile, sheet)
        end
        if not path then tex:Hide(); return 0 end
        tex:SetTexture(path)
        if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else tex:SetTexCoord(0, 1, 0, 1) end
    else
        tex:Hide()
        return 0
    end
    tex:SetSize(size, size)
    tex:Show()
    return size
end

-- ---------------------------------------------------------------- paint --

-- Called once by DM.CreateWindow with the widgets it built.
function P.AttachPaint(W, ui)
    local frame, wdb = ui.frame, ui.wdb
    local header, viewport, content = ui.header, ui.viewport, ui.content

    function W.Refresh()
        if not frame:IsShown() and not DM.optionsOpen then return end
        local session = DM.FetchSession(W)
        W.lastSession = session
        W.Paint(session)
        W.UpdateTimer()
        if W.sourceOpen then W.RefreshSource() end
    end

    -- Paint the rows from a session. Sources are in API order; the rank-one
    -- total is the bar maximum, secret or not -- the status bar divides.
    function W.Paint(session)
        local d = DM.db()
        local sources = session and session.combatSources
        if type(sources) ~= "table" then sources = {} end
        local isDeaths = DM.IsDeaths(W.dmType)
        if isDeaths then
            -- Newest first from the API; shown in order of dying. deathRecapID
            -- is NeverSecret, so the filter may read it.
            local rev = {}
            for i = #sources, 1, -1 do
                local s = sources[i]
                local rid = s.deathRecapID
                if type(rid) == "number" and not DM.IsSecret(rid) and rid > 0 then rev[#rev + 1] = s end
            end
            sources = rev
        end
        W.sources = sources
        local count = math.min(#sources, DM.BAR_POOL)
        W.count = count
        W.RecalcScroll()

        -- The session carries its own maximum (the client's meter uses it), so
        -- the bars do not have to assume the list is sorted. The rank-one
        -- total is only the fallback. Either may be secret; neither is read.
        local maxAmt = 1
        if not isDeaths then
            local m = session and session.maxAmount
            if type(m) ~= "nil" then
                maxAmt = m
            elseif sources[1] and type(sources[1].totalAmount) ~= "nil" then
                maxAmt = sources[1].totalAmount
            end
        end
        W.maxAmt = maxAmt

        local stride = W.Stride()
        local barH = ns:PixelSnap(d.barHeight or 18, frame)
        local scroll = viewport:GetVerticalScroll() or 0
        local viewH = viewport:GetHeight() or 100
        local first = math.floor(scroll / stride) + 1
        local last  = math.min(count, math.ceil((scroll + viewH) / stride))

        for i = 1, DM.BAR_POOL do
            local bar = W.rows[i]
            if i <= count then
                if bar.slot ~= i then
                    bar.slot = i
                    bar.row:ClearAllPoints()
                    bar.row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * stride))
                    bar.row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((i - 1) * stride))
                    bar.row:SetHeight(barH)
                end
                if not bar.row:IsShown() then bar.row:Show() end
                if i >= first and i <= last then
                    DM.PaintRow(W, bar, sources[i], i, maxAmt)
                end
            else
                if bar.row:IsShown() then bar.row:Hide() end
                bar.slot, bar.src = nil, nil
            end
        end
        W.UpdateSticky(sources, count, stride, barH, scroll, viewH)
    end

    -- Own row pinned to the top or bottom edge while it sits outside the view.
    function W.UpdateSticky(sources, count, stride, barH, scroll, viewH)
        local st = W.sticky
        local show = false
        if DM.db().showPinnedSelf and not W.homeOpen and not W.sourceOpen then
            local ownIdx
            for i = 1, count do
                if DM.IsOwnRow(sources[i]) then ownIdx = i; break end
            end
            if ownIdx then
                local top = (ownIdx - 1) * stride
                local bottom = top + barH
                local above = top < scroll - 1
                local below = bottom > scroll + viewH + 1
                if above or below then
                    show = true
                    st.row:ClearAllPoints()
                    W.stickySep:ClearAllPoints()
                    if above then
                        st.row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
                        st.row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
                        W.stickySep:SetPoint("TOPLEFT", st.row, "BOTTOMLEFT", 0, 0)
                        W.stickySep:SetPoint("TOPRIGHT", st.row, "BOTTOMRIGHT", 0, 0)
                    else
                        st.row:SetPoint("BOTTOMLEFT", viewport, "BOTTOMLEFT", 0, 0)
                        st.row:SetPoint("BOTTOMRIGHT", viewport, "BOTTOMRIGHT", 0, 0)
                        W.stickySep:SetPoint("BOTTOMLEFT", st.row, "TOPLEFT", 0, 0)
                        W.stickySep:SetPoint("BOTTOMRIGHT", st.row, "TOPRIGHT", 0, 0)
                    end
                    st.row:SetHeight(barH)
                    DM.PaintRow(W, st, sources[ownIdx], ownIdx, W.maxAmt)
                end
            end
        end
        st.row:SetShown(show)
        W.stickySep:SetShown(show)
    end

    -- Mouseover visibility: shown on enter, faded once the cursor left.
    local moTicker   -- mirrored on W so RemoveWindow can cancel it
    function W.MouseoverShow()
        if DM.db().visibility ~= "mouseover" or DM.toggleHidden then return end
        frame:SetAlpha(1)
        if not moTicker then
            moTicker = ns:AddTicker(0.2, function()
                if not frame:IsMouseOver() then
                    frame:SetAlpha(0)
                    ns:CancelTicker(moTicker); moTicker, W.moTicker = nil, nil
                end
            end, nil, "meter mouseover")
            W.moTicker = moTicker
        end
    end

    function W.UpdateVisibility()
        local d = DM.db()
        if ns:IsEditModeActive() or DM.optionsOpen then
            frame:SetAlpha(1); frame:Show(); return
        end
        if DM.toggleHidden then frame:Hide(); return end
        local vis = d.visibility or "always"
        local shown = true
        if vis == "hidden" then shown = false
        elseif vis == "combat" then shown = DM.inCombat or DM.needsFinal
        elseif vis == "noncombat" then shown = not DM.inCombat end
        if shown then
            local _, itype = IsInInstance()
            if wdb.hideInDungeon and itype == "party" then shown = false end
            if wdb.hideInRaid and itype == "raid" then shown = false end
            if wdb.hideInPvP and (itype == "pvp" or itype == "arena") then shown = false end
            if wdb.hideOutOfInstance and (itype == "none" or not itype) then shown = false end
        end
        frame:SetShown(shown)
        if vis == "mouseover" then
            frame:SetAlpha(frame:IsMouseOver() and 1 or 0)
        else
            frame:SetAlpha(1)
        end
        if shown then W.Refresh() end
    end
end

-- ---------------------------------------------------------------- rows --

-- One bar: icon, fill, three texts, background, highlight, borders.
function DM.MakeRow(W, parent, i)
    local bar = {}
    local row = CreateFrame("Button", nil, parent)
    row:RegisterForClicks("AnyUp")
    row:SetHeight(18)
    bar.row = row

    local rbg = row:CreateTexture(nil, "BACKGROUND", nil, -8)
    rbg:SetAllPoints(row)
    rbg:SetTexture(WHITE)
    bar.bg = rbg

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(row)
    hl:SetColorTexture(1, 1, 1, 0.08)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    bar.icon = icon

    local iconBorder = CreateFrame("Frame", nil, row)
    iconBorder:SetAllPoints(icon)
    iconBorder:SetFrameLevel(row:GetFrameLevel() + 6)
    bar.iconBorder = iconBorder

    local fill = CreateFrame("StatusBar", nil, row)
    fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    fill:SetStatusBarTexture(WHITE)
    fill:SetMinMaxValues(0, 1)
    fill:SetValue(0)
    bar.fill = fill

    local border = CreateFrame("Frame", nil, row)
    border:SetAllPoints(row)
    border:SetFrameLevel(row:GetFrameLevel() + 3)
    bar.border = border

    local tf = CreateFrame("Frame", nil, row)
    tf:SetAllPoints(fill)
    tf:SetFrameLevel(row:GetFrameLevel() + 4)
    bar.tf = tf

    local pos = tf:CreateFontString(nil, "OVERLAY")
    pos:SetJustifyH("LEFT")
    bar.pos = pos
    local label = tf:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    bar.label = label
    local amount = tf:CreateFontString(nil, "OVERLAY")
    amount:SetJustifyH("RIGHT")
    bar.amount = amount

    row:SetScript("OnClick", function(_, button)
        if button == "RightButton" then W.ToggleHome(); return end
        if bar.src then W.OpenSourceFromRow(bar) end
    end)
    row:SetScript("OnEnter", function()
        W.MouseoverShow()
        if bar.src and DM.ShowPreview then DM.ShowPreview(W, bar) end
    end)
    row:SetScript("OnLeave", function()
        if DM.HidePreview then DM.HidePreview() end
    end)
    bar.index = i
    return bar
end

-- The settings part of a row. Rows are recycled by rank, so the source
-- memo is cleared: a same-class, different-spec swap kept the wrong icon.
function DM.StyleRow(W, bar)
    local d = DM.db()
    local frame = W.frame
    local barH = ns:PixelSnap(d.barHeight or 18, frame)
    bar.row:SetHeight(barH)
    bar.icon:SetSize(barH, barH)
    bar.fill:SetStatusBarTexture(DM.BarTexture(d.barTexture))
    bar.fill:GetStatusBarTexture():SetAlpha(d.barFillAlpha or 1)
    bar.fill:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)

    DM.Font(bar.pos, d.leftFontSize or 11)
    DM.Font(bar.label, d.leftFontSize or 11)
    DM.Font(bar.amount, d.rightFontSize or 11)
    bar.pos:ClearAllPoints()
    bar.pos:SetPoint("LEFT", bar.tf, "LEFT", 3 + (d.leftTextOffsetX or 0), d.leftTextOffsetY or 0)
    bar.label:ClearAllPoints()
    bar.label:SetPoint("LEFT", bar.pos, "RIGHT", d.hideNumbers and 0 or 2, 0)
    bar.label:SetPoint("RIGHT", bar.tf, "RIGHT", -70, 0)
    bar.amount:ClearAllPoints()
    bar.amount:SetPoint("RIGHT", bar.tf, "RIGHT", -3 + (d.rightTextOffsetX or 0), d.rightTextOffsetY or 0)

    if not d.leftTextUseClassColor then
        bar.pos:SetTextColor(d.leftTextColor.r, d.leftTextColor.g, d.leftTextColor.b)
        bar.label:SetTextColor(d.leftTextColor.r, d.leftTextColor.g, d.leftTextColor.b)
    end
    if not d.rightTextUseClassColor then
        bar.amount:SetTextColor(d.rightTextColor.r, d.rightTextColor.g, d.rightTextColor.b)
    end
    if not d.barBgUseClassColor then
        bar.bg:SetColorTexture(d.barBgColor.r, d.barBgColor.g, d.barBgColor.b, d.barBgAlpha or 0)
    end

    -- Bar border: around the row, or riding the fill texture. Anchoring to
    -- the texture measures nothing, so it is legal on a secret fill.
    local anchor = bar.row
    if d.borderFollowFill then
        anchor = bar.fill:GetStatusBarTexture()
        if d.borderFollowFillIcon then anchor = bar.fill end
    end
    ns.PaintBorder(bar.border, anchor, { texture = d.borderFollowFill and "solid" or d.borderTexture,
        size = DM.IsClassic() and 0 or d.borderSize, color = d.borderColor, alpha = d.borderAlpha,
        level = bar.row:GetFrameLevel() + 3 })
    if d.borderFollowFill and d.borderFollowFillIcon then
        -- With the icon: strips from the icon's left edge to the fill's end.
        local e = bar.border._vfEdges
        if e then
            local ft = bar.fill:GetStatusBarTexture()
            e.top:SetPoint("BOTTOMLEFT", bar.row, "TOPLEFT", -ns:Pixel(frame, d.borderSize), 0)
            e.top:SetPoint("BOTTOMRIGHT", ft, "TOPRIGHT", ns:Pixel(frame, d.borderSize), 0)
            e.bot:SetPoint("TOPLEFT", bar.row, "BOTTOMLEFT", -ns:Pixel(frame, d.borderSize), 0)
            e.bot:SetPoint("TOPRIGHT", ft, "BOTTOMRIGHT", ns:Pixel(frame, d.borderSize), 0)
            e.rgt:SetPoint("TOPLEFT", ft, "TOPRIGHT", 0, 0)
            e.rgt:SetPoint("BOTTOMLEFT", ft, "BOTTOMRIGHT", 0, 0)
        end
    end
    ns.PaintBorder(bar.iconBorder, bar.icon, { size = d.customIconBorder and d.iconBorderSize or 0,
        color = d.iconBorderColor, alpha = d.iconBorderAlpha, level = bar.row:GetFrameLevel() + 6 })

    bar.src, bar.classFile, bar.spec, bar.nameMemo, bar.amtMemo, bar.rank = nil, nil, nil, nil, nil, nil
end

-- The per-tick part. Only fields documented NeverSecret are inspected; the
-- rest is handed to widgets untouched.
function DM.PaintRow(W, bar, src, rank, maxAmt)
    local d = DM.db()
    local barH = bar.row:GetHeight()
    local classFile = src.classFilename
    if type(classFile) ~= "string" or DM.IsSecret(classFile) or classFile == "" then classFile = nil end
    local spec = src.specIconID
    if type(spec) ~= "number" or DM.IsSecret(spec) then spec = 0 end

    -- Icon and colours: once per class/spec change on this row.
    if bar.classFile ~= classFile or bar.spec ~= spec or bar.src == nil then
        bar.classFile, bar.spec = classFile, spec
        local iw = DM.ResolveIcon(src, bar.icon, barH)
        bar.fill:SetPoint("TOPLEFT", bar.row, "TOPLEFT", iw, 0)
        bar.iconBorder:SetShown(iw > 0)

        local cr, cg, cb = DM.ClassColor(classFile)
        local fr, fg, fb
        if d.showClassColor then
            if cr then fr, fg, fb = cr, cg, cb
            elseif W.dmType == DM.T.EnemyDamageTaken then fr, fg, fb = 0.867, 0.192, 0.192
            else fr, fg, fb = 0.5, 0.5, 0.5 end
        elseif d.barColorUseAccent then fr, fg, fb = DM.Accent()
        else fr, fg, fb = d.barColor.r, d.barColor.g, d.barColor.b end
        bar.fill:SetStatusBarColor(fr, fg, fb)

        if d.leftTextUseClassColor then
            local r, g, b = cr or 1, cg or 1, cb or 1
            bar.pos:SetTextColor(r, g, b); bar.label:SetTextColor(r, g, b)
        end
        if d.rightTextUseClassColor then bar.amount:SetTextColor(cr or 1, cg or 1, cb or 1) end
        if d.barBgUseClassColor then
            bar.bg:SetColorTexture(cr or 0, cg or 0, cb or 0, d.barBgAlpha or 0)
        end
    end

    -- Fill: the engine divides; both ends may be secret.
    if DM.IsDeaths(W.dmType) then
        bar.fill:SetMinMaxValues(0, 1); bar.fill:SetValue(1)
    else
        bar.fill:SetMinMaxValues(0, maxAmt)
        local v = src.totalAmount
        if type(v) == "nil" then v = 0 end
        bar.fill:SetValue(v)
    end

    if d.hideNumbers then
        if bar.rank ~= 0 then bar.rank = 0; bar.pos:SetText("") end
    elseif bar.rank ~= rank then
        bar.rank = rank
        bar.pos:SetFormattedText("%d.", rank)
    end

    -- Name: a secret is set every tick (it cannot be compared to the memo).
    local name = src.name
    if DM.IsSecret(name) then
        bar.label:SetText(DM.StripRealm(name))
        bar.nameMemo = nil
    elseif name ~= bar.nameMemo then
        bar.nameMemo = name
        bar.label:SetText(DM.StripRealm(name))
    end

    local text
    if DM.IsDeaths(W.dmType) then
        local overall = (not W.sessionID and W.session == DM.S.Overall)
        text = overall and "" or DM.DeathTime(W, src)
    elseif DM.IsCount(W.dmType) then
        text = DM.Abbrev(src.totalAmount)
    else
        text = DM.FormatValue(src.totalAmount, src.amountPerSecond, d.numberFormat or 2)
    end
    if DM.IsSecret(text) then
        bar.amount:SetText(text)
        bar.amtMemo = nil
    elseif text ~= bar.amtMemo then
        bar.amtMemo = text
        bar.amount:SetText(text)
    end
    bar.src = src
end

-- Time of death. In combat the API's stamp is secret, so the row's first
-- appearance is stamped with the live duration, keyed by the NeverSecret
-- recap id; the engine's own value takes over once it reads plain.
DM.deathStamps = {}
function DM.DeathTime(W, src)
    local t = src.deathTimeSeconds
    if DM.Plain(t) and type(t) == "number" then
        if t < 0 then return "" end
        return DM.FormatTimer(t)
    end
    local rid = src.deathRecapID
    if type(rid) ~= "number" or DM.IsSecret(rid) then return "" end
    local stamp = DM.deathStamps[rid]
    if not stamp then
        stamp = DM.ViewDuration(W)
        DM.deathStamps[rid] = stamp
    end
    return DM.FormatTimer(stamp)
end
