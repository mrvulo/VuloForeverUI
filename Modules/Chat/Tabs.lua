-- VuloForeverUI / Modules / Chat / Tabs
--
-- Our own tab strip -- and it is a strip of GHOSTS.
--
-- THE ONE IDEA IN THIS FILE
--
-- This module never selects, closes, creates, renames or reorders a chat
-- window. Not once. Every one of those goes through an FCF_ function, and
-- hooking or calling one from addon code taints the CALLER: the measured chain
-- is a hooked FCF_ call leaving `isLocked` tainted forever, after which the
-- tab's own context menu dies iterating its private message list and the
-- resize code dies on the secret name in a whisper tab. Deferring the hook
-- body does not help, because it is the wrapper that taints.
--
-- So the client's tabs stay exactly where they are and keep every click. Ours
-- are drawn beside them, with the mouse switched off, and the client's strip
-- is taken to alpha zero -- alpha does not disable a mouse, so the invisible
-- real tab under our drawing is what the player actually clicks. We draw; the
-- client decides.
local _, ns = ...
local Chat = ns.Chat

local Tabs = {}
Chat.Tabs = Tabs

local strip

-- ---------------------------------------------------------------- strip --

local function ensureStrip()
    if strip then return strip end
    strip = CreateFrame("Frame", nil, UIParent)
    strip:SetFrameStrata("MEDIUM")
    -- Motion without clicks, and both propagated: a motion-enabled overlay
    -- that does not propagate swallows the click meant for the real tab under
    -- it, and kills the client's own tab tooltip with it.
    pcall(strip.SetMouseClickEnabled, strip, false)
    pcall(strip.SetMouseMotionEnabled, strip, true)
    if strip.SetPropagateMouseClicks then pcall(strip.SetPropagateMouseClicks, strip, true) end
    if strip.SetPropagateMouseMotion then pcall(strip.SetPropagateMouseMotion, strip, true) end
    strip.ghosts = {}
    return strip
end

-- The client's strip, made invisible without being disabled. Its per-tab
-- alphas are rewritten by the client on every dock pass and multiply into
-- this one, so the dock's own alpha is the place to write.
local function suppressDock()
    local dock = _G.GeneralDockManager
    if not dock or Tabs.dockHidden then return end
    Tabs.dockHidden = true
    pcall(dock.SetAlpha, dock, 0)
    -- The overflow button is a click target that would vanish with the parent
    -- alpha; it keeps its own.
    local overflow = dock.overflowButton
    if overflow and overflow.SetIgnoreParentAlpha then
        pcall(overflow.SetIgnoreParentAlpha, overflow, true)
    end
end

local function restoreDock()
    local dock = _G.GeneralDockManager
    if not (dock and Tabs.dockHidden) then return end
    Tabs.dockHidden = false
    pcall(dock.SetAlpha, dock, 1)
end

-- ---------------------------------------------------------------- ghosts --

local function ghost(index)
    local s = ensureStrip()
    local g = s.ghosts[index]
    if g then return g end

    g = CreateFrame("Frame", nil, s)
    g:EnableMouse(false)

    -- The tab's own ground, behind everything else in the ghost. It fills the
    -- ghost, which is the real tab's rectangle to the pixel -- so a coloured
    -- tab is coloured exactly where the player will click.
    -- Transparent until the first paint: a ghost whose refresh stopped short
    -- must not be left as a solid white block over the tab.
    g.bg = g:CreateTexture(nil, "BACKGROUND")
    g.bg:SetAllPoints(g)
    g.bg:SetColorTexture(0, 0, 0, 0)

    g.edges = ns.MakeEdges(g, "BORDER")
    for _, t in pairs(g.edges) do t:Hide() end

    -- A font before anything else touches it: SetText on a font string that
    -- has none raises, and the pass that raised left the ghost half-built.
    g.text = g:CreateFontString(nil, "OVERLAY")
    ns.UI.Font(g.text, 11, "")
    -- Anchored by its left edge and never measured: a whisper tab's label can
    -- be secret, and measuring a secret string is as forbidden as comparing
    -- one.
    g.text:SetPoint("LEFT", g, "LEFT", 0, 0)

    -- The active tab's mark: a bar as wide as the label (plus a little air),
    -- and a soft glow in the same colour rising from it. Both hang off the
    -- label's own edges, never a measurement -- a font string with a single
    -- anchor is exactly as wide as its text, and a whisper tab's text may be
    -- secret.
    g.underline = g:CreateTexture(nil, "ARTWORK")
    g.underline:SetTexture("Interface\\Buttons\\WHITE8X8")
    g.underline:SetPoint("BOTTOM", g, "BOTTOM", 0, 0)
    g.underline:SetPoint("LEFT", g.text, "LEFT", -4, 0)
    g.underline:SetPoint("RIGHT", g.text, "RIGHT", 4, 0)
    g.underline:SetHeight(2)
    g.underline:Hide()

    g.glow = g:CreateTexture(nil, "BORDER")
    g.glow:SetPoint("BOTTOMLEFT", g.underline, "TOPLEFT", 0, 0)
    g.glow:SetPoint("BOTTOMRIGHT", g.underline, "TOPRIGHT", 0, 0)
    g.glow:SetHeight(8)
    g.glow:Hide()

    s.ghosts[index] = g
    return g
end

-- The label of a real tab. It may be secret, so it is asked about first and
-- then goes straight into SetText -- the one sink a secret string is allowed
-- to reach.
local function tabLabel(tab)
    local fs = tab and (tab.Text or (tab.GetName and _G[tab:GetName() .. "Text"]))
    if not fs then return nil end
    local ok, text = pcall(fs.GetText, fs)
    if not ok then return nil end
    return text
end

-- The tab font: its own choice from shared media, or the chat font when the
-- setting is empty. Outline stays NONE either way -- the ghosts sit on the
-- client's own tab art, and an outline on top of that reads as a smudge.
-- Asked through MediaFontValid, not through MediaFont alone: the latter
-- answers an unknown name with the addon font, so a font whose addon has been
-- uninstalled would quietly replace the chat font instead of falling back to
-- it.
local function applyFont(g, db)
    local own = db.tabFont
    local path = type(own) == "string" and ns.MediaFontValid and ns.MediaFontValid(own)
        and ns.MediaFont(own)
    if path then
        if not g.text:SetFont(path, db.tabFontSize or 11, "") then ns.UI.FontFor("chat", g.text, db.tabFontSize or 11, "") end
    else
        ns.UI.FontFor("chat", g.text, db.tabFontSize or 11, "")
    end
end

-- The underline's colour. Accent mode reads ns.COLORS.accent at paint time
-- rather than copying it into the settings: the theme colour is live-mutated,
-- and a copy would freeze whatever it happened to be when it was saved.
local function underlineColor(db)
    if db.underlineAccent ~= false then
        local a = ns.COLORS.accent
        -- The opacity comes from the custom colour either way, so the slider
        -- next to it keeps working in accent mode instead of going dead the
        -- moment the theme colour is switched on.
        return { r = a.r, g = a.g, b = a.b, a = db.underlineColor.a or 0.9 }
    end
    return db.underlineColor
end

-- The ground and the border of one tab, in its current state.
--
-- The border reads the PANEL's settings while it is synced, so switching the
-- chat's border off switches the tabs' off with it and there is only ever one
-- answer to "what does a border look like here".
local function paintGround(g, db, active)
    local c = active and db.tabBgColorActive or db.tabBgColor
    local wanted = db.tabTexture
    local file = type(wanted) == "string" and wanted ~= ""
        and ns.MediaStatusbarValid and ns.MediaStatusbarValid(wanted)
        and ns.MediaStatusbar(wanted)
    if file then
        g.bg:SetTexture(file)
        g.bg:SetVertexColor(c.r, c.g, c.b, c.a or 0)
    else
        g.bg:SetColorTexture(c.r, c.g, c.b, c.a or 0)
        g.bg:SetVertexColor(1, 1, 1, 1)
    end

    local size, col
    if db.tabBorderSync ~= false then
        size = db.showBorder and (db.borderSize or 1) or 0
        col = db.borderColor
    else
        size = db.tabBorderSize or 0
        col = active and db.tabBorderColorActive or db.tabBorderColor
    end
    -- Drawn INSIDE the tab, hence the negative padding. LayoutEdges puts the
    -- border outside its anchor by default, which is right for the panel but
    -- wrong here: tabs sit shoulder to shoulder, so an outside border lands on
    -- the neighbour's rectangle and on the dock line under them.
    ns.LayoutEdges(g.edges, g, size, col.r, col.g, col.b, col.a or 0.18, -size)
end

local function isSelected(cf)
    if not FCFDock_GetSelectedWindow then return false end
    local ok, selected = pcall(FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
    return ok and selected == cf
end

function Tabs.Refresh()
    if not Chat.mod.active then return end
    local db = Chat.db()
    suppressDock()
    local s = ensureStrip()

    local shown = 0
    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        local tab = cf.GetName and _G[cf:GetName() .. "Tab"]
        -- Every open window's tab, not only the ones we draw text for: the
        -- client's strip is invisible, so a window we leave to the client
        -- (the combat log) still needs a ghost or its tab is simply gone.
        if tab and Chat.IsOpen(cf) and (d.bridged or cf.isDocked) then
            shown = shown + 1
            local g = ghost(shown)

            -- Anchored TO the real tab, never parented to it: a parent of ours
            -- in the client's frame tree is exactly what taints the next dock
            -- pass. An anchor is only geometry.
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0)
            g:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", 0, 0)

            applyFont(g, db)
            -- Centred by default. The client gives a window the player made
            -- (not General, not the combat log) a fixed width of 60 to 90
            -- pixels whatever its name is, so a short name set at the left
            -- edge left a hole after it as wide as the tab.
            g.text:ClearAllPoints()
            if db.tabAlign == "LEFT" then
                g.text:SetPoint("LEFT", g, "LEFT", db.tabPaddingX or 0, 0)
            else
                g.text:SetPoint("CENTER", g, "CENTER", 0, 0)
            end

            local label = tabLabel(tab)
            if type(label) ~= "nil" then g.text:SetText(label) end

            local active = isSelected(cf)
            paintGround(g, db, active)

            local text = active and db.tabTextColorActive or db.tabTextColor
            g.text:SetTextColor(text.r, text.g, text.b)

            if active and db.activeUnderline ~= false then
                local u = underlineColor(db)
                g.underline:SetHeight(math.max(1, db.underlineSize or 2))
                g.underline:SetColorTexture(u.r, u.g, u.b, u.a or 0.9)
                g.underline:Show()
                -- Bottom colour first: strongest on the bar, gone a few pixels
                -- up, so it reads as light on the tab rather than a box.
                ns.UI.SetGradient(g.glow, "VERTICAL", u.r, u.g, u.b, 0.22, u.r, u.g, u.b, 0)
                g.glow:Show()
            else
                g.underline:Hide()
                g.glow:Hide()
            end
            g:Show()
        end
    end
    for i = shown + 1, #s.ghosts do s.ghosts[i]:Hide() end
    s:Show()
    Tabs.StyleQuickBar()
    Tabs.Watch()
end

-- ------------------------------------------------------ combat log filters --
--
-- The combat log's quick filter row ("My actions", "What happened to me?")
-- in the tabs' own dress: their font and colours, the accent underline under
-- the filter in use, and no black bar behind it.
--
-- Ghosts again, like the tabs. The buttons stay the client's and keep their
-- clicks; only their own text goes to alpha zero, and our labels are drawn on
-- a frame of ours over them. Giving the buttons font objects of ours instead
-- left them drawing nothing at all. The row lives in the chat frame tree, so
-- nothing of ours is parented into it either: the host is a UIParent frame,
-- and the labels are only anchored to the buttons.
local QUICK_BAR, QUICK_BUTTON = "CombatLogQuickButtonFrame_Custom", "CombatLogQuickButtonFrameButton"
local quick = { labels = {}, fontOf = {} }

local function quickHost()
    if quick.host then return quick.host end
    local h = CreateFrame("Frame", nil, UIParent)
    h:SetFrameStrata("MEDIUM")
    h:SetAllPoints(UIParent)
    h:EnableMouse(false)
    local line = h:CreateTexture(nil, "OVERLAY")
    line:Hide()
    h.line = line
    quick.host = h
    return h
end

-- The watcher calls this four times a second. Our own frame is the only
-- thing written after the first pass; the client's buttons only have their
-- text faded once each.
function Tabs.StyleQuickBar()
    local bar = _G[QUICK_BAR]
    if not (Chat.mod.active and bar) then return end
    local db = Chat.db()
    local host = quickHost()
    local visible = bar:IsVisible()
    host:SetShown(visible)
    if not visible then return end

    local ground = _G[QUICK_BAR .. "Texture"]
    if ground then ground:SetAlpha(0) end

    local current = _G.Blizzard_CombatLog_Filters and _G.Blizzard_CombatLog_Filters.currentFilter
    local lit, used = nil, 0
    for i = 1, 20 do
        local b = _G[QUICK_BUTTON .. i]
        if not b then break end
        local own = b:GetFontString()
        if own then own:SetAlpha(0) end
        local label = quick.labels[i]
        if not label then
            label = host:CreateFontString(nil, "OVERLAY")
            quick.labels[i] = label
        end
        local text = b:GetText()
        if b:IsShown() and type(text) == "string" and ns.CanRead(text) then
            used = i
            local active = b:GetID() == current
            if active then lit = label end
            -- one wrapper per label, made once: this runs four times a second
            quick.fontOf[label] = quick.fontOf[label] or { text = label }
            applyFont(quick.fontOf[label], db)
            local c = active and db.tabTextColorActive or db.tabTextColor
            label:SetTextColor(c.r, c.g, c.b)
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("CENTER", b, "CENTER", 0, 0)
            label:Show()
        else
            label:Hide()
        end
    end
    for i = used + 1, #quick.labels do quick.labels[i]:Hide() end

    local line = host.line
    if lit and db.activeUnderline ~= false then
        local u = underlineColor(db)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", lit, "BOTTOMLEFT", -4, -3)
        line:SetPoint("TOPRIGHT", lit, "BOTTOMRIGHT", 4, -3)
        line:SetHeight(math.max(1, db.underlineSize or 2))
        line:SetColorTexture(u.r, u.g, u.b, u.a or 0.9)
        line:Show()
    else
        line:Hide()
    end
end

function Tabs.ReleaseQuickBar()
    if quick.host then quick.host:Hide() end
    local ground = _G[QUICK_BAR .. "Texture"]
    if ground then ground:SetAlpha(1) end
    for i = 1, 20 do
        local b = _G[QUICK_BUTTON .. i]
        if not b then break end
        local own = b:GetFontString()
        if own then own:SetAlpha(1) end
    end
end

-- ---------------------------------------------------------------- watcher --
--
-- A tab click is a click on the client's own tab, and nothing of ours may be
-- hooked into it (see the top of this file). So the result is WATCHED instead:
-- which window is selected, and which windows are shown. Reads only, writes
-- only on a change, and all of it in our own frame script -- never inside the
-- client's dock pass.
--
-- In two speeds. What a tab click changes -- the selection, which window is
-- shown -- is read EVERY frame: at four reads a second a click left our text
-- on the old window for up to a quarter of a second, which is what made
-- switching tabs feel sticky. It is a handful of reads per frame. Everything
-- else stays at four times a second.
local lastSelected
local lastShown = {}
-- The numbered chat frames all exist from the start, so the list is taken
-- once rather than built again every frame.
local frames

local function watchFast()
    if not Chat.mod.active then return end
    frames = frames or Chat.Frames()
    local ok, sel = pcall(FCFDock_GetSelectedWindow, _G.GENERAL_CHAT_DOCK)
    if not ok then sel = nil end
    local changed = sel ~= lastSelected
    lastSelected = sel
    for _, cf in ipairs(frames) do
        local okS, shown = pcall(cf.IsShown, cf)
        if okS and ns.CanRead(shown) then
            shown = shown and true or false
            if lastShown[cf] ~= shown then lastShown[cf] = shown; changed = true end
        end
        if Chat.Owned(cf) and Chat.Panel.SyncShown(cf) then changed = true end
    end
    if changed then
        -- The tabs and the combat log's filter row now, in this frame; the
        -- panels (heavier, and only needed if a window moved while it was
        -- hidden) on the next.
        Tabs.Refresh()      -- restyles the filter row as well
        Chat.Queue("chat.panels", function() Chat.Panel.ApplyAll() end)
    end
end

local function watchSlow()
    if not Chat.mod.active then return end
    -- A window made from the tab menu announces itself with no event we get,
    -- so it stayed the client's -- its text, its bordered input line -- until
    -- the next reload. An open window that is not ours yet gets the full pass.
    local unowned = false
    for _, cf in ipairs(Chat.Frames()) do
        local okS, shown = pcall(cf.IsShown, cf)
        if okS and ns.CanRead(shown) and shown and not Chat.Owned(cf) and Chat.IsOpen(cf) then
            unowned = true
        end
    end
    -- A window moved without resizing (Edit Mode, a drag) fires no event;
    -- the panel follows it here. Write-free unless the rectangle changed.
    Chat.Panel.FollowAll()
    -- The combat log's filter row: new buttons and where the underline goes.
    Tabs.StyleQuickBar()
    -- The secure + button copies the column's position; write-free unless
    -- the chat moved.
    if Chat.Sidebar and Chat.Sidebar.SyncNewWindow then Chat.Sidebar.SyncNewWindow() end
    if unowned then Chat.Refresh() end
end

function Tabs.Watch()
    if Tabs.ticker or not FCFDock_GetSelectedWindow then return end
    Tabs.ticker = C_Timer.NewTicker(0.25, watchSlow)
    Tabs.fast = Tabs.fast or CreateFrame("Frame")
    Tabs.fast:SetScript("OnUpdate", watchFast)
    Tabs.fast:Show()
end

-- A line arrived in a window. The client owns the flashing of its own tab; all
-- we do is re-read which tab is selected, on the next frame.
function Tabs.OnMessage()
    Chat.Queue("chat.tabs", function() Tabs.Refresh() end)
end

-- The strip, for the fade. It is a UIParent child of its own rather than a
-- child of the panel -- it has to sit above the client's tab row, which is
-- outside the panel's rectangle -- so the fade cannot reach it by parentage
-- and has to be handed it.
function Tabs.Strip()
    return strip
end

-- The combat log's filter labels, for the fade: their host is a UIParent
-- frame of its own, so like the strip it has to be handed over.
function Tabs.QuickHost()
    return quick.host
end

function Tabs.Release()
    if Tabs.ticker then Tabs.ticker:Cancel(); Tabs.ticker = nil end
    if Tabs.fast then Tabs.fast:Hide() end
    lastSelected = nil
    wipe(lastShown)
    restoreDock()
    Tabs.ReleaseQuickBar()
    if strip then strip:Hide() end
end
