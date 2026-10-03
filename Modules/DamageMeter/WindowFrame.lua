-- VuloForeverUI / Modules / DamageMeter / WindowFrame: one window's frame, header, buttons and menus, bar list, grip, lock, hover and drag
--
-- One meter window: header with its five buttons, the bar list with a pooled
-- row per rank, the pinned own row, wheel scrolling, header drag with snapping
-- to the other windows, the resize grip, the lock, the home view of bookmarked
-- meter types, and the visibility rules. Every window is independent: its own
-- meter type, session and size; the look is shared through the module settings.
--
-- The window is spread over several files: this one builds it, WindowLayout
-- and WindowRows give it its methods, WindowHome its home view, WindowMulti
-- the mover helpers, adding and closing windows, and the snapping.
local _, ns = ...
local L  = ns.L
local DM = ns.DM
local UI = ns.UI

local WHITE = DM.WHITE

-- Private to the window files: the method sets the build hands its widgets to.
DM._win = DM._win or {}
local P = DM._win

-- ---------------------------------------------------------------- borders --

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
    -- High within LOW: the quest tracker lives in LOW too and its lines drew
    -- over the bars. Still LOW, so bags and panels (MEDIUM) stay on top.
    frame:SetFrameLevel(100)
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

    -- The methods close over the widgets made above; they are written in
    -- WindowLayout and WindowRows and handed the same widgets here.
    local ui = {
        frame = frame, wdb = wdb, bg = bg, borderHolder = borderHolder,
        header = header, hbg = hbg, hline = hline, title = title, timer = timer,
        viewport = viewport, content = content, catcher = catcher,
        grip = grip, gt = gt, lt = lt,
    }
    P.AttachLayout(W, ui)
    P.AttachPaint(W, ui)

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
