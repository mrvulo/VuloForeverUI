-- VuloForeverUI / Modules / DamageMeter / WindowMulti: mover helpers, adding and closing windows, snapping between them
local _, ns = ...
local DM = ns.DM

-- ---------------------------------------------------------------- movers --
--
-- Our edit mode keeps a place as a CENTRE offset from UIParent's centre; every
-- frame of this module saves the TOPLEFT from the screen's bottom-left and
-- keeps doing so. The saved TOPLEFT stays the truth: the mover's x/y is a
-- mirror of it, refreshed on every own move, and a mover move is translated
-- back into it. Both in the frame's own units, for a box of the given size.
function DM.CenterFromTopLeft(frame, left, top, w, h)
    local r = ns:GetScaleRatio(frame)
    return left + w / 2 - UIParent:GetWidth() / r / 2, top - h / 2 - UIParent:GetHeight() / r / 2
end

function DM.TopLeftFromCenter(frame, x, y, w, h)
    local r = ns:GetScaleRatio(frame)
    return UIParent:GetWidth() / r / 2 + x - w / 2, UIParent:GetHeight() / r / 2 + y + h / 2
end

-- Mirror a frame's place into its mover from the frame's own rect, for
-- frames anchored to something else (a window) whose TOPLEFT is not known
-- without asking. A rect not laid out yet is asked again one frame later.
function DM.SyncMoverFromRect(mover, frame, retried)
    local db = mover and not mover.retired and mover.opts and mover.opts.db
    if not (db and frame) then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not (left and top) then
        if not retried then ns.NextFrame(function() DM.SyncMoverFromRect(mover, frame, true) end) end
        return
    end
    db.x, db.y = DM.CenterFromTopLeft(frame, left, top, frame:GetWidth(), frame:GetHeight())
end

-- A mover lives as long as its target, and the meter windows do not: a profile
-- switch rebuilds them and closing one re-numbers the rest. There is no way to
-- unregister a mover, so a window's mover is retired by hand: out of the edit
-- mode's lists (or it would show up twice in the link and size pickers), its
-- position table cut loose (or a reset would write into a profile that was
-- left), its callbacks made inert.
function DM.RetireMover(m)
    ns:RemoveMover(m)
end

-- ---------------------------------------------------------------- multi-window --

function DM.AddWindow(from)
    local db = DM.db()
    local n = #DM.windows + 1
    if n > DM.MAX_WINDOWS then return end
    local src = from and from.wdb
    local wdb = DM.WinDB(n)
    if src then wdb.width, wdb.height = src.width, src.height end
    -- Above the highest window, with a gap; below the lowest when the top
    -- of the screen is in the way.
    local highest, lowest
    for _, W in ipairs(DM.windows) do
        local t, b = W.frame:GetTop(), W.frame:GetBottom()
        if t and (not highest or t > highest.t) then highest = { t = t, l = W.frame:GetLeft() } end
        if b and (not lowest or b < lowest.b) then lowest = { b = b, l = W.frame:GetLeft() } end
    end
    if highest then
        local top = highest.t + 10 + wdb.height
        if top <= UIParent:GetHeight() then
            wdb.pos = { x = highest.l, y = top }
        elseif lowest then
            wdb.pos = { x = lowest.l, y = lowest.b - 10 }
        end
    end
    db.windowCount = n
    DM.windows[n] = DM.CreateWindow(n)
    DM.windows[n].Refresh()
    DM.windows[n].UpdateVisibility()
    -- A corner-anchored combat timer follows the topmost or bottommost
    -- window, and that may be the new one.
    if DM.Timer and DM.Timer.Apply then DM.Timer.Apply() end
end

function DM.RemoveWindow(W)
    local db = DM.db()
    local idx = W.idx
    if idx == 1 then return end
    -- Its two hover tickers outlive the frame otherwise: both poll
    -- frame:IsMouseOver(), which stops being true only by luck once the frame
    -- has no parent.
    if W.hoverTicker then ns:CancelTicker(W.hoverTicker); W.hoverTicker = nil end
    if W.moTicker then ns:CancelTicker(W.moTicker); W.moTicker = nil end
    if W.sourceOpen then W.CloseSource() end
    DM.HidePreview()
    DM.RetireMover(W.mover)
    W.frame:Hide()
    W.frame:SetParent(nil)
    table.remove(DM.windows, idx)
    table.remove(db.windows, idx)
    for i = idx, #DM.windows do
        DM.windows[i].idx = i
        DM.windows[i].wdb = db.windows[i]
        -- Its box is keyed by the old number; it moves to the new one.
        DM.windows[i].AttachMover()
    end
    db.windowCount = #DM.windows
    -- The timer may have been pinned to the window that just went away.
    if DM.Timer and DM.Timer.Apply then DM.Timer.Apply() end
end

-- ---------------------------------------------------------------- snapping --

-- Edge to edge against the closest other window on each axis, from the
-- unsnapped target so the frame cannot oscillate between two answers.
function DM.SnapPosition(W, left, top)
    local w, h = W.frame:GetWidth(), W.frame:GetHeight()
    local right, bottom = left + w, top - h
    local bestX, bestY, dX, dY = nil, nil, DM.SNAP + 1, DM.SNAP + 1
    for _, o in ipairs(DM.windows) do
        if o ~= W and o.frame:IsShown() then
            local ol, or_, ot, ob = o.frame:GetLeft(), o.frame:GetRight(), o.frame:GetTop(), o.frame:GetBottom()
            if ol then
                for _, pair in ipairs({ { left, ol }, { left, or_ }, { right, ol }, { right, or_ } }) do
                    local d = math.abs(pair[1] - pair[2])
                    if d < dX then dX = d; bestX = left + (pair[2] - pair[1]) end
                end
                for _, pair in ipairs({ { top, ot }, { top, ob }, { bottom, ot }, { bottom, ob } }) do
                    local d = math.abs(pair[1] - pair[2])
                    if d < dY then dY = d; bestY = top + (pair[2] - pair[1]) end
                end
            end
        end
    end
    return bestX or left, bestY or top
end

function DM.SnapSize(W, w, h)
    local bw, bh, dw, dh = w, h, DM.SNAP + 1, DM.SNAP + 1
    for _, o in ipairs(DM.windows) do
        if o ~= W then
            local ow, oh = o.wdb.width, o.wdb.height
            if math.abs(ow - w) < dw then dw = math.abs(ow - w); bw = ow end
            if math.abs(oh - h) < dh then dh = math.abs(oh - h); bh = oh end
        end
    end
    return bw, bh
end
