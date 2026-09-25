-- VuloForeverUI / Modules / DamageMeter / Window
--
-- One meter window: header with its five buttons, the bar list with a pooled
-- row per rank, the pinned own row, wheel scrolling, header drag with snapping
-- to the other windows, the resize grip, the lock, the home view of bookmarked
-- meter types, and the visibility rules. Every window is independent: its own
-- meter type, session and size; the look is shared through the module settings.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local WHITE = DM.WHITE

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

-- ---------------------------------------------------------------- borders --

-- A border of "solid" strips or a shared-media edge file around a frame.
-- Both live on one holder so a style switch is a repaint, not a rebuild.
local function ensureBorder(holder)
    if holder._edges then return end
    holder._edges = ns.MakeEdges(holder, "OVERLAY")
    local bd = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate")
    bd:SetAllPoints(holder)
    bd:Hide()
    holder._backdrop = bd
end

function DM.PaintBorder(holder, anchor, texture, size, color, alpha, offX, offY, level)
    ensureBorder(holder)
    local edges, bd = holder._edges, holder._backdrop
    if level then bd:SetFrameLevel(level) end
    if not size or size <= 0 then
        for _, t in pairs(edges) do t:Hide() end
        bd:Hide()
        return
    end
    local r, g, b = color.r, color.g, color.b
    local path = texture ~= "solid" and ns.MediaBorder(texture) or nil
    if not path then
        bd:Hide()
        ns.LayoutEdges(edges, anchor, size, r, g, b, alpha, 0)
        if offX ~= 0 or offY ~= 0 then
            for _, t in pairs(edges) do
                local p1, rel, p2, x, y = t:GetPoint(1)
                t:SetPoint(p1, rel, p2, (x or 0) + (offX or 0), (y or 0) + (offY or 0))
                local q1, rel2, q2, x2, y2 = t:GetPoint(2)
                if q1 then t:SetPoint(q1, rel2, q2, (x2 or 0) + (offX or 0), (y2 or 0) + (offY or 0)) end
            end
        end
        return
    end
    for _, t in pairs(edges) do t:Hide() end
    local edge = 6 + size * 4
    bd:ClearAllPoints()
    bd:SetPoint("TOPLEFT", anchor, "TOPLEFT", -(offX or 0) - size, (offY or 0) + size)
    bd:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", (offX or 0) + size, -(offY or 0) - size)
    if bd.SetBackdrop then
        bd:SetBackdrop({ edgeFile = path, edgeSize = edge })
        bd:SetBackdropBorderColor(r, g, b, alpha or 1)
    end
    bd:Show()
end

-- ---------------------------------------------------------------- menus --

local function openOptions()
    local f = UI:CreateMainFrame()
    f:Show()
    UI:PopulateSidebar()
    UI:ShowModulePage("damagemeter")
end

ns.OnLocaleReady(function()
    StaticPopupDialogs["VFUI_METER_SIZE"] = {
        text = "%s", button1 = OKAY, button2 = CANCEL,
        hasEditBox = true, maxLetters = 4,
        OnShow = function(popup, data)
            local eb = ns.PopupEditBox(popup)
            if eb then eb:SetText(tostring(data.current)); eb:HighlightText() end
        end,
        OnAccept = function(popup, data)
            local eb = ns.PopupEditBox(popup)
            local v = eb and tonumber(eb:GetText())
            if v then data.apply(v) end
        end,
        EditBoxOnEnterPressed = function(eb)
            local popup = eb:GetParent()
            local v = tonumber(eb:GetText())
            if v and popup.data then popup.data.apply(v) end
            popup:Hide()
        end,
        EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
        timeout = 0, whileDead = 1, hideOnEscape = 1, preferredIndex = 3,
    }
end)

local function askSize(label, current, apply)
    local popup = StaticPopup_Show("VFUI_METER_SIZE", label, nil, { current = current, apply = apply })
    if popup then popup.data = { current = current, apply = apply } end
end

-- ---------------------------------------------------------------- window --

local frameCount = 0

function DM.CreateWindow(idx)
    local W = {}
    local db  = DM.db()
    local wdb = DM.WinDB(idx)
    W.idx, W.wdb = idx, wdb
    W.dmType    = wdb.dmType or DM.T.DamageDone
    W.session   = wdb.session or DM.S.Current
    W.sessionID = nil

    frameCount = frameCount + 1
    local frame = CreateFrame("Frame", "VuloForeverUIMeterWindow" .. frameCount, UIParent)
    W.frame = frame
    frame:SetSize(wdb.width, wdb.height)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(DM.MIN_W, DM.MIN_H) end
    frame:SetFrameStrata("LOW")
    frame:EnableMouse(true)
    frame:SetDontSavePosition(true)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(db.hdrHeight or 22))
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    bg:SetTexture(WHITE)
    W.bg = bg

    -- Frame border on its own holder so it can sit behind or over the bars.
    local borderHolder = CreateFrame("Frame", nil, frame)
    borderHolder:SetAllPoints(frame)
    borderHolder:EnableMouse(false)
    W.borderHolder = borderHolder

    -- Header --------------------------------------------------------------
    local header = CreateFrame("Button", nil, frame)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(db.hdrHeight or 22)
    header:SetFrameLevel(frame:GetFrameLevel() + 5)
    header:RegisterForClicks("AnyUp")
    header:RegisterForDrag("LeftButton")
    W.header = header

    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints(header)
    hbg:SetTexture(WHITE)
    W.hdrBg = hbg

    local hline = header:CreateTexture(nil, "OVERLAY", nil, 7)
    hline:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
    hline:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    hline:SetTexture(WHITE)
    W.hdrLine = hline

    local title = header:CreateFontString(nil, "OVERLAY")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    W.title = title

    local timer = header:CreateFontString(nil, "OVERLAY")
    timer:SetJustifyH("LEFT")
    W.timerText = timer

    -- Header buttons, laid out right to left.
    W.buttons = {}
    -- The BUTTON is the hit area, the glyph sits inset inside it. Drawing the
    -- texture edge to edge is what made the header look crowded: a 22px button
    -- in a 22px header left no air at all.
    local function makeButton(key, icon, tip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:RegisterForClicks("AnyUp")
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetPoint("CENTER", b, "CENTER", 0, 0)
        t:SetTexture(icon)
        b.icon = t
        b:SetAlpha(DM.ICON_ALPHA)
        b._glyph = icon
        b:SetScript("OnEnter", function(self)
            if DM.IsClassic() then
                local k = DM.CLASSIC.HOVER
                self.icon:SetVertexColor(k, k, k, 1)
            else
                self:SetAlpha(DM.ICON_HOVER)
            end
            UI:ShowTooltip(self, { title = tip(), lines = self._lines })
        end)
        b:SetScript("OnLeave", function(self)
            if DM.IsClassic() then
                local k = DM.CLASSIC.IDLE
                self.icon:SetVertexColor(k, k, k, 1)
            else
                self:SetAlpha(self._dim and DM.ICON_ALPHA * 0.5 or DM.ICON_ALPHA)
            end
            UI:HideTooltip()
        end)
        b:SetScript("OnClick", onClick)
        b._key = key
        W.buttons[key] = b
        return b
    end

    -- Menus -----------------------------------------------------------------
    local function typeEntry(t)
        return { text = DM.TypeName(t), radio = true, checked = (W.dmType == t),
                 func = function() W.SetType(t) end }
    end

    local function modeMenu()
        return {
            { text = L["Damage"], submenu = {
                typeEntry(DM.T.DamageDone), typeEntry(DM.T.DamageTaken),
                typeEntry(DM.T.AvoidableDamageTaken), typeEntry(DM.T.EnemyDamageTaken) } },
            typeEntry(DM.T.HealingDone),
            { text = L["Actions"], submenu = {
                typeEntry(DM.T.Interrupts), typeEntry(DM.T.Dispels), typeEntry(DM.T.Deaths) } },
        }
    end

    local function segmentMenu()
        local items = {}
        for _, s in ipairs(DM.RecentSessions()) do
            items[#items + 1] = {
                text = ("%s  [%s]"):format(s.name, DM.FormatTimer(s.duration)),
                radio = true, checked = (W.sessionID == s.sessionID),
                func = function() DM.ApplySegment(W, nil, s.sessionID) end,
            }
        end
        if #items > 0 then items[#items + 1] = { separator = true } end
        for _, st in ipairs({ DM.S.Current, DM.S.Overall }) do
            items[#items + 1] = {
                text = DM.SessionName(st), radio = true,
                checked = (not W.sessionID and W.session == st),
                func = function() DM.ApplySegment(W, st, nil) end,
            }
        end
        return items
    end

    local function flag(key, text)
        return { text = text, checked = wdb[key] and true or false, keepOpen = true,
                 func = function() wdb[key] = not wdb[key]; W.UpdateVisibility() end }
    end

    local function settingsMenu()
        return {
            { title = true, text = L["Window %d"]:format(W.idx) },
            flag("hideInDungeon", L["Hide in dungeons"]),
            flag("hideInRaid", L["Hide in raids"]),
            flag("hideInPvP", L["Hide in PvP"]),
            flag("hideOutOfInstance", L["Hide out of instances"]),
            { separator = true },
            { text = L["Width…"], func = function()
                askSize(L["Window width"], math.floor(wdb.width), function(v) W.SetSize(v, nil) end) end },
            { text = L["Height…"], func = function()
                askSize(L["Window height"], math.floor(wdb.height), function(v) W.SetSize(nil, v) end) end },
            { text = wdb.snapDisabled and L["Enable snapping"] or L["Disable snapping"],
              func = function() wdb.snapDisabled = not wdb.snapDisabled end },
            { text = L["Hide timer"], checked = wdb.hideTimer and true or false, keepOpen = true,
              func = function() wdb.hideTimer = not wdb.hideTimer; W.UpdateTimer() end },
            { text = L["Auto Current on combat"], checked = wdb.autoCurrentOnCombat and true or false, keepOpen = true,
              func = function() wdb.autoCurrentOnCombat = not wdb.autoCurrentOnCombat end },
            { text = L["Sync segment selection"], checked = wdb.syncSegments and true or false, keepOpen = true,
              func = function() wdb.syncSegments = not wdb.syncSegments end },
            { separator = true },
            { text = L["Settings"], func = openOptions },
        }
    end

    makeButton("settings", DM.ICON .. "gear", function() return L["Window settings"] end,
        function(self) ns:ShowPopupMenu(settingsMenu(), self) end)
    makeButton("segment", DM.ICON .. "book", function() return L["Select segment"] end,
        function(self) ns:ShowPopupMenu(segmentMenu(), self) end)
    -- The meter type keeps its own picture, but desaturated and tinted like
    -- the sidebar's module glyphs, so it sits in the same row as the four
    -- line icons instead of being the one colourful square among them.
    makeButton("mode", DM.TYPE_ICONS[W.dmType], function() return DM.TypeName(W.dmType) end,
        function(self) ns:ShowPopupMenu(modeMenu(), self) end)
    W.buttons.mode.icon:SetTexCoord(0.10, 0.90, 0.10, 0.90)
    W.buttons.mode.icon:SetDesaturated(true)
    makeButton("reset", DM.ICON .. "reset", function() return L["Reset data"] end, DM.ResetData)
    if idx == 1 then
        makeButton("action", DM.ICON .. "copy", function() return L["New window"] end, function()
            if #DM.windows >= DM.MAX_WINDOWS then return end
            DM.AddWindow(W)
        end)
        W.buttons.action._lines = { L["Opens another meter window above this one."] }
        W.buttons.action._art = "open"
    else
        makeButton("action", DM.ICON .. "power", function()
            return wdb.locked and L["Unlock the window to close it"] or L["Close window"]
        end, function()
            if wdb.locked then return end
            DM.RemoveWindow(W)
        end)
        W.buttons.action._art = "close"
    end

    -- Bars ------------------------------------------------------------------
    local viewport = CreateFrame("ScrollFrame", nil, frame)
    viewport:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    viewport:SetClipsChildren(true)
    W.viewport = viewport
    local content = CreateFrame("Frame", nil, viewport)
    content:SetSize(1, 1)
    viewport:SetScrollChild(content)
    viewport:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w); W.RecalcScroll() end)
    W.content = content
    W.scrollMax = 0

    -- Right-click on the empty body opens the home view.
    local catcher = CreateFrame("Button", nil, frame)
    catcher:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    catcher:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    catcher:SetFrameLevel(frame:GetFrameLevel() + 1)
    catcher:RegisterForClicks("RightButtonUp")
    catcher:SetScript("OnClick", function() W.ToggleHome() end)
    viewport:SetFrameLevel(frame:GetFrameLevel() + 2)

    W.rows = {}
    for i = 1, DM.BAR_POOL do W.rows[i] = DM.MakeRow(W, content, i) end

    -- Pinned own row over the list.
    W.sticky = DM.MakeRow(W, frame, 0)
    W.sticky.row:SetFrameLevel(frame:GetFrameLevel() + 8)
    W.sticky.row:Hide()
    local sep = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    sep:SetTexture(WHITE); sep:SetColorTexture(0, 0, 0, 1); sep:SetHeight(1); sep:Hide()
    W.stickySep = sep

    -- Wheel: two rows a notch, then a repaint so the rows that came into view fill.
    local function wheel(_, delta)
        local stride = W.Stride()
        local cur = viewport:GetVerticalScroll() or 0
        local nv = math.max(0, math.min(W.scrollMax, cur - delta * stride * 2))
        viewport:SetVerticalScroll(nv)
        ns.NextFrame(function() W.Paint(W.lastSession) end)
    end
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", wheel)
    catcher:EnableMouseWheel(true)
    catcher:SetScript("OnMouseWheel", wheel)

    -- Grip and lock ---------------------------------------------------------
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 15)
    local gt = grip:CreateTexture(nil, "ARTWORK")
    gt:SetAllPoints(grip)
    gt:SetTexture(DM.ICON .. "expand")
    grip:SetAlpha(0)
    W.grip = grip

    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(14, 14)
    lock:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 3)
    lock:SetFrameLevel(frame:GetFrameLevel() + 16)
    local lt = lock:CreateTexture(nil, "ARTWORK")
    lt:SetAllPoints(lock)
    lock.icon = lt
    lock:SetAlpha(0)
    W.lock = lock

    local function paintLock()
        lt:SetTexture(DM.ICON .. (wdb.locked and "lock" or "lock_open"))
        W.buttons.action._dim = (idx ~= 1 and wdb.locked) or nil
        local full = DM.IsClassic() and 1 or DM.ICON_ALPHA
        W.buttons.action:SetAlpha(W.buttons.action._dim and full * 0.5 or full)
    end
    lock:SetScript("OnClick", function()
        wdb.locked = not wdb.locked
        paintLock()
    end)
    lock:SetScript("OnEnter", function(self)
        UI:ShowTooltip(self, wdb.locked and L["Unlock window"] or L["Lock window"])
    end)
    lock:SetScript("OnLeave", UI.HideTooltip and function() UI:HideTooltip() end or nil)
    paintLock()

    -- Hover: grip and lock fade in while the cursor is over the window.
    local hoverTicker   -- mirrored on W so RemoveWindow can cancel it
    local function hoverTick()
        local over = frame:IsMouseOver()
        local a = over and 0.3 or 0
        grip:SetAlpha(wdb.locked and 0 or (grip:IsMouseOver() and 0.7 or a))
        lock:SetAlpha(lock:IsMouseOver() and 0.7 or a)
        W.HoverIcons(over)
        if not over and hoverTicker then
            ns:CancelTicker(hoverTicker); hoverTicker, W.hoverTicker = nil, nil
        end
    end
    frame:SetScript("OnEnter", function()
        if not hoverTicker then hoverTicker = ns:AddTicker(0.1, hoverTick, nil, "meter hover"); W.hoverTicker = hoverTicker end
        hoverTick()
        W.MouseoverShow()
    end)
    header:SetScript("OnEnter", frame:GetScript("OnEnter"))

    -- Resize: bottom-right grip; shift locks one axis; sizes snap to the
    -- closest other window afterwards.
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or wdb.locked then return end
        W.resizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        if not W.resizing then return end
        W.resizing = false
        frame:StopMovingOrSizing()
        local w, h = frame:GetWidth(), frame:GetHeight()
        if IsShiftKeyDown() then
            if math.abs(w - wdb.width) >= math.abs(h - wdb.height) then h = wdb.height else w = wdb.width end
        end
        if not wdb.snapDisabled then
            local sw, sh = DM.SnapSize(W, w, h)
            w, h = sw, sh
        end
        W.SetSize(w, h)
        W.SavePosition()
    end)

    -- Drag by the header, snapping to the other windows while it moves.
    local drag
    header:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or wdb.locked then return end
        local cx, cy = GetCursorPosition()
        drag = { cx = cx, cy = cy, left = frame:GetLeft(), top = frame:GetTop(), moved = false }
        header:SetScript("OnUpdate", function()
            local nx, ny = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            local dx, dy = (nx - drag.cx) / s, (ny - drag.cy) / s
            if not drag.moved and (math.abs(dx) > 2 or math.abs(dy) > 2) then drag.moved = true end
            if not drag.moved then return end
            local left, top = drag.left + dx, drag.top + dy
            if not wdb.snapDisabled then left, top = DM.SnapPosition(W, left, top) end
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end)
    end)
    header:SetScript("OnMouseUp", function(_, button)
        header:SetScript("OnUpdate", nil)
        if button == "RightButton" then
            W.ToggleHome()
            return
        end
        if drag and drag.moved then W.SavePosition() end
        drag = nil
    end)

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
        title:SetPoint("LEFT", header, "LEFT", 6 + offX, offY)
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
        local hh = d.hdrHeight or 22
        local classic = DM.IsClassic()
        -- Classic: the header and the rows sit inside the box's rim and bevel.
        local inset = classic and DM.CLASSIC.INSET or 0
        header:SetHeight(hh)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
        header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -inset, -inset)
        viewport:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        catcher:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)
        bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -hh)
        DM.ClassicBox(frame, classic, d.bgColor.r, d.bgColor.g, d.bgColor.b, d.bgAlpha or 0.75)
        if classic then
            bg:SetColorTexture(0, 0, 0, 0)
            DM.ClassicHeaderTint(hbg, d.bgColor.r, d.bgColor.g, d.bgColor.b, d.hdrBgAlpha or 1)
        else
            bg:SetColorTexture(d.bgColor.r, d.bgColor.g, d.bgColor.b, d.bgAlpha or 0.75)
            DM.ClassicUntint(hbg)
            hbg:SetColorTexture(d.hdrBgColor.r, d.hdrBgColor.g, d.hdrBgColor.b, d.hdrBgAlpha or 1)
        end
        if classic then
            -- One hairline in the rim's grey, whatever the header line says.
            local g = DM.CLASSIC.LINE
            hline:SetHeight(ns:Pixel(frame, 1))
            hline:SetColorTexture(g, g, g, 1)
            hline:Show()
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
        if d.hdrTextUseAccent then tr, tg, tb = DM.Accent() else tr, tg, tb = d.hdrTextColor.r, d.hdrTextColor.g, d.hdrTextColor.b end
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
        DM.PaintBorder(borderHolder, anchor, d.windowBorderTexture, classic and 0 or d.windowBorderSize, d.windowBorderColor,
            d.windowBorderAlpha, d.windowBorderOffsetX or 0, d.windowBorderOffsetY or 0, borderHolder:GetFrameLevel())

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

    -- Home view ---------------------------------------------------------------
    DM.AttachHome(W)
    -- Breakdown view --------------------------------------------------------
    DM.AttachBreakdown(W)

    W.ApplyPosition()
    W.AttachMover()
    W.Restyle()
    if not wdb.dmType then W.ShowHome() end
    return W
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
    DM.PaintBorder(bar.border, anchor, d.borderFollowFill and "solid" or d.borderTexture,
        DM.IsClassic() and 0 or (d.borderSize or 0),
        d.borderColor, d.borderAlpha, 0, 0, bar.row:GetFrameLevel() + 3)
    if d.borderFollowFill and d.borderFollowFillIcon then
        -- With the icon: strips from the icon's left edge to the fill's end.
        local e = bar.border._edges
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
    DM.PaintBorder(bar.iconBorder, bar.icon, "solid", d.customIconBorder and d.iconBorderSize or 0,
        d.iconBorderColor, d.iconBorderAlpha, 0, 0, bar.row:GetFrameLevel() + 6)

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

-- ---------------------------------------------------------------- home view --

local CARD_H, CARD_GAP, HOME_PAD = 26, 4, 8

function DM.AttachHome(W)
    local frame, header = W.frame, W.header
    local home, scroll, child
    local tiles = {}
    local addBtn, hint
    local homeScrollMax = 0

    local function tileMenu()
        local items = {}
        local marks = DM.Bookmarks()
        for _, t in ipairs(DM.TYPE_ORDER) do
            local have = false
            for _, m in ipairs(marks) do if m == t then have = true end end
            if not have then
                items[#items + 1] = { text = DM.TypeName(t), func = function()
                    marks[#marks + 1] = t
                    DM.ForEach(function(o) if o.homeOpen then o.RefreshHome() end end)
                end }
            end
        end
        if #items == 0 then items[1] = { text = L["All types are bookmarked"], disabled = true } end
        return items
    end

    local function makeTile()
        local b = CreateFrame("Button", nil, child)
        b:SetHeight(CARD_H)
        b:RegisterForClicks("LeftButtonUp", "MiddleButtonUp")
        local bgT = b:CreateTexture(nil, "BACKGROUND")
        bgT:SetAllPoints(b); bgT:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(b); hl:SetColorTexture(1, 1, 1, 0.06)
        local stripe = b:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
        stripe:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
        stripe:SetWidth(2)
        b.stripe = stripe
        local ic = b:CreateTexture(nil, "ARTWORK")
        ic:SetSize(CARD_H - 8, CARD_H - 8)
        ic:SetPoint("LEFT", b, "LEFT", 6, 0)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic:SetDesaturated(true)
        b.icon = ic
        local txt = b:CreateFontString(nil, "OVERLAY")
        DM.Font(txt, 11)
        txt:SetPoint("LEFT", ic, "RIGHT", 6, 0)
        txt:SetPoint("RIGHT", b, "RIGHT", -16, 0)
        txt:SetJustifyH("LEFT"); txt:SetWordWrap(false)
        b.text = txt
        local arrow = b:CreateTexture(nil, "ARTWORK")
        arrow:SetSize(10, 10)
        arrow:SetPoint("RIGHT", b, "RIGHT", -4, 0)
        arrow:SetTexture(DM.ICON .. "arrow_right")
        arrow:SetVertexColor(0.6, 0.6, 0.65)
        b:SetScript("OnClick", function(self, button)
            if button == "MiddleButton" then
                local marks = DM.Bookmarks()
                for i, m in ipairs(marks) do if m == self.dmType then table.remove(marks, i); break end end
                DM.ForEach(function(o) if o.homeOpen then o.RefreshHome() end end)
                return
            end
            W.SetType(self.dmType)
        end)
        return b
    end

    function W.RefreshHome()
        if not home then return end
        local marks = DM.Bookmarks()
        local ar, ag, ab = DM.Accent()
        local width = child:GetWidth() or frame:GetWidth()
        local colW = (width - HOME_PAD * 2 - CARD_GAP) / 2
        local y = -6
        for i, t in ipairs(marks) do
            local b = tiles[i]
            if not b then b = makeTile(); tiles[i] = b end
            b.dmType = t
            b.icon:SetTexture(DM.TYPE_ICONS[t])
            b.icon:SetVertexColor(ar, ag, ab)
            b.text:SetText(DM.TypeName(t))
            local active = (t == W.dmType)
            b.stripe:SetColorTexture(ar, ag, ab, active and 1 or 0)
            local col = (i - 1) % 2
            local rowI = math.floor((i - 1) / 2)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", child, "TOPLEFT", HOME_PAD + col * (colW + CARD_GAP), y - rowI * (CARD_H + CARD_GAP))
            b:SetWidth(math.max(40, colW))
            b:Show()
        end
        for i = #marks + 1, #tiles do tiles[i]:Hide() end
        local rows = math.ceil(#marks / 2)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("TOPLEFT", child, "TOPLEFT", HOME_PAD, y - rows * (CARD_H + CARD_GAP))
        addBtn:SetWidth(math.max(40, width - HOME_PAD * 2))
        local contentH = -y + (rows + 1) * (CARD_H + CARD_GAP) + 16
        child:SetHeight(math.max(10, contentH))
        homeScrollMax = math.max(0, contentH - (scroll:GetHeight() or 0))
    end

    function W.ShowHome()
        if not home then
            home = CreateFrame("Frame", nil, frame)
            home:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            -- The row area's corner: on Classic it sits inside the box's rim.
            home:SetPoint("BOTTOMRIGHT", W.viewport, "BOTTOMRIGHT", 0, 0)
            home:SetFrameLevel(frame:GetFrameLevel() + 25)
            home:EnableMouse(true)
            local hb = home:CreateTexture(nil, "BACKGROUND")
            hb:SetAllPoints(home); hb:SetColorTexture(0.03, 0.03, 0.03, 0.95)
            scroll = CreateFrame("ScrollFrame", nil, home)
            scroll:SetAllPoints(home)
            scroll:SetClipsChildren(true)
            child = CreateFrame("Frame", nil, scroll)
            child:SetSize(1, 1)
            scroll:SetScrollChild(child)
            scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w); W.RefreshHome() end)
            local function hw(_, delta)
                local cur = scroll:GetVerticalScroll() or 0
                scroll:SetVerticalScroll(math.max(0, math.min(homeScrollMax, cur - delta * 30)))
            end
            home:EnableMouseWheel(true); home:SetScript("OnMouseWheel", hw)
            scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", hw)
            home:SetScript("OnMouseDown", function(_, button) if button == "RightButton" then W.HideHome() end end)

            addBtn = CreateFrame("Button", nil, child)
            addBtn:SetHeight(CARD_H)
            local abg = addBtn:CreateTexture(nil, "BACKGROUND")
            abg:SetAllPoints(addBtn); abg:SetColorTexture(0.08, 0.08, 0.08, 0.8)
            local ahl = addBtn:CreateTexture(nil, "HIGHLIGHT")
            ahl:SetAllPoints(addBtn); ahl:SetColorTexture(1, 1, 1, 0.06)
            local at = addBtn:CreateFontString(nil, "OVERLAY")
            DM.Font(at, 11)
            at:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
            at:SetText("+ " .. L["ADD NEW"])
            at:SetTextColor(0.7, 0.7, 0.75)
            addBtn:SetScript("OnClick", function(self) ns:ShowPopupMenu(tileMenu(), self) end)
            hint = child:CreateFontString(nil, "OVERLAY")
            DM.Font(hint, 9)
            hint:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -3)
            hint:SetText(L["(middle click to remove)"])
            hint:SetTextColor(0.45, 0.45, 0.5)
        end
        W.homeOpen = true
        W.viewport:Hide()
        W.sticky.row:Hide(); W.stickySep:Hide()
        W.bg:Hide()
        if W.sourceOpen then W.CloseSource() end
        home:Show()
        child:SetWidth(scroll:GetWidth() or frame:GetWidth())
        W.RefreshHome()
    end

    function W.HideHome()
        if home then home:Hide() end
        W.homeOpen = false
        W.viewport:Show()
        W.bg:Show()
    end

    function W.ToggleHome()
        if W.homeOpen then W.HideHome() else W.ShowHome() end
    end
end
