-- VuloForeverUI / Modules / DamageMeter / WindowLayout: a window's sizing, placing, mover, header fitting and restyle methods
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local P  = DM._win

-- Called once by DM.CreateWindow with the widgets it built.
function P.AttachLayout(W, ui)
    local frame, wdb = ui.frame, ui.wdb
    local bg, borderHolder = ui.bg, ui.borderHolder
    local header, hbg, hline, title, timer = ui.header, ui.hbg, ui.hline, ui.title, ui.timer
    local viewport, content, catcher = ui.viewport, ui.content, ui.catcher
    local grip, gt, lt = ui.grip, ui.gt, ui.lt

    -- ------------------------------------------------------------- methods --

    function W.Stride()
        local h = DM.db().barHeight or 18
        local sp = DM.db().barSpacing or 2
        return ns:PixelSnap(h, frame) + ns:PixelSnap(sp, frame)
    end

    function W.RecalcScroll()
        local stride = W.Stride()
        local n = W.count or 0
        W.scrollMax = math.max(0, n * stride - (viewport:GetHeight() or 0))
        local cur = viewport:GetVerticalScroll() or 0
        if cur > W.scrollMax then viewport:SetVerticalScroll(W.scrollMax) end
        content:SetHeight(math.max(1, n * stride))
    end

    function W.SetType(t)
        W.dmType = t
        wdb.dmType = t
        W.PaintButtonIcon(W.buttons.mode)
        title:SetText(DM.TypeName(t))
        W.FitTitle()
        W.CloseSource()
        W.HideHome()
        W.styleKey = nil
        W.Refresh()
    end

    function W.SetSize(w, h)
        wdb.width  = math.max(DM.MIN_W, w or wdb.width)
        wdb.height = math.max(DM.MIN_H, h or wdb.height)
        frame:SetSize(wdb.width, wdb.height)
        W.RecalcScroll()
        W.Paint(W.lastSession)
        -- The TOPLEFT stays, so the centre the edit mode keeps has moved.
        if W.mover then W.mover.opts.width, W.mover.opts.height = wdb.width, wdb.height end
        W.SyncMover()
    end

    function W.SavePosition()
        wdb.pos = { x = frame:GetLeft(), y = frame:GetTop() }
        W.SyncMover()
    end

    -- Saved as TOPLEFT from the screen's bottom-left; the default cascades the
    -- windows up from the bottom-right corner.
    local function topLeft()
        local p = wdb.pos
        if type(p) == "table" and p.x and p.y then return p.x, p.y end
        return UIParent:GetWidth() - 20 - wdb.width - (W.idx - 1) * 20, 20 + wdb.height + (W.idx - 1) * 20
    end

    function W.ApplyPosition()
        local left, top = topLeft()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        W.SyncMover()
    end

    -- The edit mode's copy of the place, worked out from the saved TOPLEFT
    -- rather than read off the rect, which may not be laid out yet.
    function W.SyncMover()
        local m = W.mover
        if m and not m.retired then
            local left, top = topLeft()
            m.opts.db.x, m.opts.db.y = DM.CenterFromTopLeft(frame, left, top, frame:GetWidth(), frame:GetHeight())
        end
        -- A timer pinned to a window (or following window 1) moved with it.
        if DM.Timer and DM.Timer.SyncMover then DM.Timer.SyncMover() end
    end

    -- A place from the edit mode, turned back into the window's own format.
    function W.SetCenter(x, y)
        local left, top = DM.TopLeftFromCenter(frame, x or 0, y or 0, frame:GetWidth(), frame:GetHeight())
        wdb.pos = { x = left, y = top }
        W.ApplyPosition()
    end

    -- One box per window in our edit mode, keyed by the window's number. A
    -- window that changed its number (one before it was closed) gets a new
    -- box under the new key; the old one is retired.
    function W.AttachMover()
        local key = "dm_window" .. W.idx
        if W.mover and not W.mover.retired and W.mover.key == key then return end
        DM.RetireMover(W.mover)
        if type(wdb.mover) ~= "table" then wdb.mover = {} end
        local opts
        opts = {
            key    = key,
            label  = L["Meter window %d"]:format(W.idx),
            db     = wdb.mover,
            module = "damagemeter",
            width  = wdb.width, height = wdb.height,
            -- Reset puts the window back on its default place in the cascade
            -- rather than stacking every window on the screen's centre.
            applyPos = function()
                if ns._inMoverReset then
                    wdb.pos = nil
                    W.ApplyPosition()
                    return
                end
                W.SetCenter(opts.db.x, opts.db.y)
            end,
            -- A drop, a discard, a link: the mover already placed the frame
            -- by its centre; this writes that back as the saved TOPLEFT.
            onMove = function(x, y) W.SetCenter(x, y) end,
            -- The window may be hidden by its visibility rules; the edit mode
            -- shows it, and closing the edit mode hands it back to them.
            editPreview = function()
                if DM.mod.active then W.UpdateVisibility() end
            end,
        }
        W.mover = ns:CreateMover(frame, opts)
        -- CreateMover turns clamping off; the window's own drag relies on it.
        frame:SetClampedToScreen(true)
        W.SyncMover()
    end

    -- The header buttons hide until the header is hovered, when asked to.
    function W.HoverIcons(over)
        if not DM.db().hdrMouseoverIcons then return end
        for _, b in pairs(W.buttons) do b:SetShown(over) end
        W.FitTitle()
    end

    -- Title, clock and icons share one row, right to left: the icons own the
    -- right edge, the clock sits directly left of them, and the title takes
    -- what is left and ellipsizes. The clock used to hang off the title's own
    -- end, which put it underneath the icons as soon as the type name was
    -- long enough.
    function W.FitTitle()
        local db2 = DM.db()
        local hh = db2.hdrHeight or 22
        local size = W.iconHit or math.min(db2.hdrIconSize or 22, math.max(12, hh - 2))
        local gap = DM.IsClassic() and DM.CLASSIC.ICON_PAD or 1
        local used = 0
        for _, b in pairs(W.buttons) do
            if b:IsShown() then used = used + size + gap end
        end
        local offX, offY = db2.hdrTextOffX or 0, db2.hdrTextOffY or 0

        timer:ClearAllPoints()
        timer:SetPoint("RIGHT", header, "RIGHT", -used - 4 + offX, offY)

        title:ClearAllPoints()
        -- Classic: a Blizzard window's title keeps clear of the metal rim.
        local inset = DM.IsClassic() and DM.CLASSIC.TITLE_X or 6
        title:SetPoint("LEFT", header, "LEFT", inset + offX, offY)
        title:SetPoint("RIGHT", timer, "LEFT", -6, 0)
    end

    function W.UpdateTimer()
        if wdb.hideTimer then timer:SetText(""); return end
        local d = DM.ViewDuration(W)
        if (DM.inCombat or DM.needsFinal or W.sessionID or DM.frozenDur > 0) and type(d) == "number" and d > 0 then
            timer:SetFormattedText("[%s]", DM.FormatTimer(d))
        else
            timer:SetText("")
        end
    end

    -- One header button's picture: the 1.x art on Classic, the tinted glyph
    -- (the meter type's icon desaturated, like the sidebar's) on Modern.
    function W.PaintButtonIcon(b)
        local d = DM.db()
        local size = W.iconHit or math.min(d.hdrIconSize or 22, math.max(12, (d.hdrHeight or 22) - 2))
        local isMode = b == W.buttons.mode
        if DM.IsClassic() then
            local art = DM.ClassicArt(isMode and "mode" or (b._art or b._key), W.dmType)
            if art then
                DM.PaintClassicArt(b.icon, art, size)
                b:SetAlpha(b._dim and 0.5 or 1)
                return
            end
        end
        local glyph = math.max(9, size - 8)
        b.icon:ClearAllPoints()
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.icon:SetSize(glyph, glyph)
        if isMode then
            b.icon:SetTexture(DM.TYPE_ICONS[W.dmType])
            b.icon:SetDesaturated(true)
            b.icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
        else
            b.icon:SetTexture(b._glyph)
            b.icon:SetDesaturated(false)
            b.icon:SetTexCoord(0, 1, 0, 1)
        end
        local ir, ig, ib
        if d.iconColorUseAccent then ir, ig, ib = DM.Accent() else ir, ig, ib = d.iconColor.r, d.iconColor.g, d.iconColor.b end
        b.icon:SetVertexColor(ir, ig, ib)
        b:SetAlpha(b._dim and DM.ICON_ALPHA * 0.5 or DM.ICON_ALPHA)
    end

    -- Everything the settings decide once: fonts, colours, sizes, borders.
    function W.Restyle()
        local d = DM.db()
        local classic = DM.IsClassic()
        local C = DM.CLASSIC
        -- Classic: the header is the metal's top band, the rows sit inside
        -- the metal on every other side.
        local hh = classic and C.BAND or (d.hdrHeight or 22)
        local pl, pr, pt, pb = 0, 0, 0, 0
        if classic then pl, pr, pt, pb = C.PAD.l, C.PAD.r, C.PAD.t, C.PAD.b end
        header:SetHeight(hh)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", pl, -pt)
        header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pr, -pt)
        header:SetFrameLevel(frame:GetFrameLevel() + (classic and C.HDR_LEVEL or 5))
        local rx, ry = 0, 0
        if classic then rx, ry = C.ROWS.x, C.ROWS.y end
        viewport:ClearAllPoints()
        viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", rx, -ry)
        viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pr, pb)
        catcher:ClearAllPoints()
        catcher:SetPoint("TOPLEFT", header, "BOTTOMLEFT", rx, -ry)
        catcher:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pr, pb)
        -- The lock and the grip stand in the corners of the row area, inside
        -- the metal, not in the window's own corners.
        W.lock:ClearAllPoints()
        W.lock:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pl + 3, pb + 3)
        W.grip:ClearAllPoints()
        W.grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -pr - 2, pb + 2)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -hh)
        DM.ClassicBox(frame, classic, d.bgColor.r, d.bgColor.g, d.bgColor.b, d.bgAlpha or 0.75)
        if classic then
            -- The rock and the metal band are the ground; nothing of ours on top.
            bg:SetColorTexture(0, 0, 0, 0)
            hbg:SetColorTexture(0, 0, 0, 0)
        else
            bg:SetColorTexture(d.bgColor.r, d.bgColor.g, d.bgColor.b, d.bgAlpha or 0.75)
            hbg:SetColorTexture(d.hdrBgColor.r, d.hdrBgColor.g, d.hdrBgColor.b, d.hdrBgAlpha or 1)
        end
        if classic then
            hline:Hide()                  -- the band's own lower edge is the line
        elseif (d.hdrBottomBorderSize or 0) > 0 then
            hline:SetHeight(ns:Pixel(frame, d.hdrBottomBorderSize))
            hline:SetColorTexture(d.hdrBottomBorderColor.r, d.hdrBottomBorderColor.g, d.hdrBottomBorderColor.b, d.hdrBottomBorderAlpha or 1)
            hline:Show()
        else
            hline:Hide()
        end

        DM.Font(title, d.hdrFontSize or 11)
        DM.Font(timer, d.hdrFontSize or 11)
        local tr, tg, tb
        if classic then
            -- A Blizzard window's title: gold, in the game's own face -- the
            -- one its own title font carries, which is the right one for the
            -- client's language (Friz Quadrata has no Cyrillic or CJK).
            tr, tg, tb = C.TITLE[1], C.TITLE[2], C.TITLE[3]
            local _, size = title:GetFont()
            local face = GameFontNormal and GameFontNormal:GetFont() or "Fonts\\FRIZQT__.TTF"
            title:SetFont(face, size or 11, "")
            timer:SetFont(face, size or 11, "")
        elseif d.hdrTextUseAccent then tr, tg, tb = DM.Accent() else tr, tg, tb = d.hdrTextColor.r, d.hdrTextColor.g, d.hdrTextColor.b end
        title:SetTextColor(tr, tg, tb)
        timer:SetTextColor(tr, tg, tb)
        title:SetText(DM.TypeName(W.dmType))

        -- Header buttons: right to left, tinted, and never taller than the
        -- header they sit in. The glyph is drawn inset inside its button so
        -- the row keeps some air; the button itself stays the hit area.
        local hitSize = math.min(d.hdrIconSize or 22, math.max(12, hh - 2))
        local gap = 1
        if classic then
            hitSize = math.floor(hitSize * DM.CLASSIC.ICON_SCALE + 0.5)
            gap = DM.CLASSIC.ICON_PAD
        end
        W.iconHit = hitSize
        local x = -3
        for _, key in ipairs({ "settings", "segment", "mode", "reset", "action" }) do
            local b = W.buttons[key]
            if key == "reset" and d.hideResetButton then
                b:Hide()
            else
                b:SetSize(hitSize, hitSize)
                b:ClearAllPoints()
                b:SetPoint("RIGHT", header, "RIGHT", x, 0)
                x = x - hitSize - gap
                W.PaintButtonIcon(b)
                b:SetShown(not d.hdrMouseoverIcons)
            end
        end
        W.FitTitle()

        -- Frame border: with or without the header, behind or over the bars.
        local anchor = d.windowBorderIncludeHeader and frame or bg
        borderHolder:SetFrameLevel(frame:GetFrameLevel() + (d.windowBorderBehind and 0 or 12))
        ns.PaintBorder(borderHolder, anchor, { texture = d.windowBorderTexture,
            size = classic and 0 or d.windowBorderSize, color = d.windowBorderColor, alpha = d.windowBorderAlpha,
            offX = d.windowBorderOffsetX, offY = d.windowBorderOffsetY, level = borderHolder:GetFrameLevel() })

        for i = 1, DM.BAR_POOL do DM.StyleRow(W, W.rows[i]) end
        DM.StyleRow(W, W.sticky)
        grip.icon = gt
        local ir, ig, ib
        if d.iconColorUseAccent then ir, ig, ib = DM.Accent() else ir, ig, ib = d.iconColor.r, d.iconColor.g, d.iconColor.b end
        gt:SetVertexColor(ir, ig, ib)
        lt:SetVertexColor(ir, ig, ib)
        W.RecalcScroll()
        if W.RestyleSource then W.RestyleSource() end
        W.Paint(W.lastSession)
    end
end
