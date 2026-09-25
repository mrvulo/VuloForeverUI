-- VuloForeverUI / Modules / Chat / Panel
--
-- The panel a window is drawn on: the background, the border, and where our
-- message surface sits over the client's.
--
-- HOW THE PANEL IS PLACED, AND WHY NOT THE OBVIOUS WAY
--
-- The obvious way is to anchor our panel to the chat frame and be done. That
-- is exactly what must not happen: it puts an addon frame into the client's
-- own anchor web, and the secure pass that resolves the dock then resolves
-- through us. So the panel is placed NUMERICALLY -- the chat frame's rectangle
-- is read, converted into screen coordinates, and our frames are pinned to
-- UIParent at those numbers. Nothing of ours ever appears in a Blizzard rect
-- chain, and the two still sit on top of each other to the pixel.
--
-- The rectangle itself may come back secret on this client, which is why every
-- read is gated: an unreadable rect means the panel keeps the place it had,
-- rather than jumping to a guess.
local _, ns = ...
local L = ns.L
local Chat = ns.Chat

local Panel = {}
Chat.Panel = Panel

-- The chat frame's rectangle, in UIParent's coordinates, or nothing.
local function readable(v)
    return ns.CanRead(v) and type(v) == "number"
end

local rawRect

-- A docked combat log is pushed down by the client to leave room for its
-- filter bar, so its own rectangle starts lower than every other tab's. Our
-- panel takes the main window's top edge instead, so the combat log's panel
-- is exactly the shape of the others and switching tabs does not jump.
local function rectOf(cf)
    local left, bottom, width, height = rawRect(cf)
    if not left then return nil end
    local d = Chat.Data(cf)
    local main = _G.ChatFrame1
    if d.native and cf.isDocked and main and main ~= cf then
        local l1, b1, _, h1 = rawRect(main)
        if l1 and b1 + h1 > bottom + height then height = b1 + h1 - bottom end
    end
    return left, bottom, width, height
end

function rawRect(cf)
    local ok, left, bottom, width, height = pcall(cf.GetRect, cf)
    if not ok then return nil end
    -- Each value on its own, never a table walk: GetRect answers with plain
    -- NILS for a frame whose rectangle is not resolved yet -- which is exactly
    -- the state a chat window is in for the first moments after login -- and
    -- ipairs over a table with a nil in it stops at the hole and checks
    -- nothing at all. That is how a missing rect became "arithmetic on a nil".
    if not (readable(left) and readable(bottom) and readable(width) and readable(height)) then
        return nil
    end
    local s = (cf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return left * s, bottom * s, width * s, height * s
end

-- ---------------------------------------------------------------- build --

local function ensure(cf)
    local d = Chat.Data(cf)
    if d.bg then return d.bg end

    local bg = CreateFrame("Frame", nil, UIParent)
    bg:SetFrameStrata(cf:GetFrameStrata())
    bg:SetFrameLevel(math.max(1, (cf:GetFrameLevel() or 2) - 1))

    local tex = bg:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints(bg)
    tex:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg.tex = tex
    bg.edges = ns.MakeEdges(bg, "BORDER")
    -- The line between the text and the input row, shown while the panel
    -- carries the input line.
    bg.div = bg:CreateTexture(nil, "BORDER")
    bg.div:Hide()

    d.bg = bg
    return bg
end

-- ---------------------------------------------------------------- input --

-- The input line, dressed as part of our panel.
--
-- The client's box stays the client's: its text, its header ("Say:"), its
-- chat-type logic and every send run exactly as they always have. Only its
-- border art goes (alpha on its own texture regions -- nothing of the client
-- writes those alphas), and it is seated flush against the chat: under it, or
-- over it with the setting, with our panel growing by one row to carry it and
-- a divider between the text and the row.
--
-- Only the numbered windows are touched. A temporary window's edit box is off
-- limits: hooking or re-scripting one taints its execution and the whisper
-- history that runs through it afterwards.
local ART = { "Left", "Mid", "Right" }
local FOCUS = { "focusLeft", "focusMid", "focusRight" }

local function editBoxOf(cf)
    local index = cf.GetID and cf:GetID()
    if type(index) ~= "number" or index > Constants.ChatFrameConstants.MaxChatWindows then return nil end
    return cf.editBox or _G[cf:GetName() .. "EditBox"]
end

local function setEditArt(eb, alpha)
    local name = eb:GetName()
    for _, key in ipairs(ART) do
        local t = name and _G[name .. key]
        if t then pcall(t.SetAlpha, t, alpha) end
    end
    for _, key in ipairs(FOCUS) do
        local t = eb[key]
        if t then pcall(t.SetAlpha, t, alpha) end
    end
end

local function placeEditBox(cf, db)
    local eb = editBoxOf(cf)
    if not eb then return end
    local d = Chat.Data(cf)
    setEditArt(eb, 0)

    local pad = db.padding or 6
    local want = (db.inputOnTop and "TOP" or "BOTTOM") .. pad
    if d.editSide == want then return end
    d.editSide = want
    d.editMoved = true

    -- Anchored to the chat frame, never to our panel: an addon frame in the
    -- edit box's anchor chain would put us into the rect web the client
    -- resolves on every dock pass. The panel follows the same numbers.
    pcall(function()
        eb:ClearAllPoints()
        if db.inputOnTop then
            eb:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", -pad, pad)
            eb:SetPoint("BOTTOMRIGHT", cf, "TOPRIGHT", pad, pad)
        else
            eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -pad, -pad)
            eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", pad, -pad)
        end
    end)
end

-- Is an input line up over this window? Not always the window's own box: in
-- the client's default chat style every window types through the main
-- window's box, and docked windows share one rectangle, so a box up on any
-- docked window is drawn over whichever docked window is showing.
--
-- "Up" means in use, not merely shown: the combat log's own box sits shown
-- for the whole session without ever being typed in, and counting it kept an
-- empty input row under the combat log. In the client's default ("classic")
-- chat style a box is only up while it has the focus; in the other style the
-- box stays visible at rest and is counted as long as it is shown.
local function inUse(eb)
    if not (eb and eb:IsShown()) then return false end
    if GetCVar("chatStyle") ~= "classic" then return true end
    local ok, focus = pcall(eb.HasFocus, eb)
    return ok and ns.CanRead(focus) and focus and true or false
end

local function inputShown(cf)
    if inUse(editBoxOf(cf)) then return true end
    if not cf.isDocked then return false end
    for _, other in ipairs(Chat.Frames()) do
        if other.isDocked and inUse(editBoxOf(other)) then return true end
    end
    return false
end

-- Our panel's rectangle: the window plus padding, plus one row for the input
-- line while it is up. Only our own frame is written, and only on a change.
function Panel.LayoutInput(cf, force)
    local d = Chat.Data(cf)
    local r, bg = d.rect, d.bg
    if not (r and bg) then return end
    local db = Chat.db()
    local pad = db.padding or 6
    local row = inputShown(cf) and (db.inputHeight or 23) or 0
    local top = db.inputOnTop and true or false
    if not force and d.inputRow == row and d.inputTop == top then return end
    d.inputRow, d.inputTop = row, top

    local left, bottom, width, height = r[1], r[2], r[3], r[4]
    bg:ClearAllPoints()
    bg:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left - pad, bottom - pad - (top and 0 or row))
    bg:SetSize(width + pad * 2, height + pad * 2 + row)

    local div = bg.div
    if row > 0 and db.showBorder then
        local c = db.borderColor
        div:SetColorTexture(c.r, c.g, c.b, c.a or 0.18)
        div:ClearAllPoints()
        local th = ns:Pixel(bg, 1)
        local y = top and -row or row
        local edge = top and "TOP" or "BOTTOM"
        div:SetPoint(edge .. "LEFT", bg, edge .. "LEFT", 0, y)
        div:SetPoint(edge .. "RIGHT", bg, edge .. "RIGHT", 0, y)
        div:SetHeight(th)
        div:Show()
    else
        div:Hide()
    end
end

function Panel.LayoutInputAll()
    if not Chat.mod.active then return end
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Owned(cf) then Panel.LayoutInput(cf) end
    end
end

-- The input line's show and hide, through the client's own callbacks. These
-- are dispatched by EventRegistry through securecallfunction, so our code runs
-- sealed off from the edit box's own execution -- which a HookScript on the
-- box would not be, and the send path reads that execution's state back.
-- Synchronous on purpose: our panel grows in the same frame the box appears.
local inputWatched
local function watchInput()
    if inputWatched or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    inputWatched = true
    local function relayout() Panel.LayoutInputAll() end
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxShow", relayout, "VuloForeverUI_ChatInputShow")
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxHide", relayout, "VuloForeverUI_ChatInputHide")
    -- The client shows the box first and focuses it after, so "in use" is
    -- only true by the focus callback.
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusGained", relayout, "VuloForeverUI_ChatInputFocus")
    EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", relayout, "VuloForeverUI_ChatInputBlur")
end

-- Height and font of the input line.
--
-- Split from the placement above because it applies to a box we have NOT
-- moved: somebody who leaves the line where the client put it still gets to
-- pick its height. What the client had is remembered on the first pass, so
-- switching the module off puts the box back instead of leaving our numbers
-- behind for the session.
local function styleEditBox(cf, db)
    local eb = editBoxOf(cf)
    if not eb then return end

    local d = Chat.Data(cf)
    if d.editOldHeight == nil then
        d.editOldHeight = false
        local okh, h = pcall(eb.GetHeight, eb)
        if okh and ns.CanRead(h) and type(h) == "number" then d.editOldHeight = h end
        local okf, f, sz, fl = pcall(eb.GetFont, eb)
        if okf and ns.CanRead(f) and type(f) == "string" then d.editOldFont = { f, sz, fl } end
    end

    pcall(eb.SetHeight, eb, db.inputHeight or 23)
    if db.inputUseChatFont then
        local path = ns.ModuleFontPath and ns.ModuleFontPath("chat") or ns.UI.FONT_PATH
        pcall(eb.SetFont, eb, path, db.inputFontSize or 12, Chat.Engine.FontFlags(db))
    elseif d.editOldFont then
        pcall(eb.SetFont, eb, d.editOldFont[1], db.inputFontSize or d.editOldFont[2], d.editOldFont[3])
    end
end

-- ---------------------------------------------------------------- apply --

-- Our panel and text follow the window's own shown state. Returns whether
-- anything changed, so the watcher in Tabs can stay write-free when settled.
function Panel.SyncShown(cf)
    local d = Chat.Data(cf)
    local ok, shown = pcall(cf.IsShown, cf)
    if not (ok and ns.CanRead(shown)) then return false end
    shown = shown and d.placed and true or false
    local changed = false
    for _, f in ipairs({ d.bg, d.host }) do
        if f and f:IsShown() ~= shown then f:SetShown(shown); changed = true end
    end
    return changed
end

function Panel.Apply(cf)
    local db = Chat.db()
    local d = Chat.Data(cf)
    if not Chat.Owned(cf) then return end

    local left, bottom, width, height = rectOf(cf)
    local bg = ensure(cf)
    local host = d.host

    -- Suppression follows the panel, not the bridge: the client's copy is only
    -- made invisible once ours is actually somewhere. Otherwise an unreadable
    -- rectangle means both are invisible and the chat is simply blank.
    -- Once placed, an unreadable rect (a window mid-drag, a frame the dock is
    -- still resolving) keeps the last place instead of giving the client its
    -- text back: flipping back and forth is what laid both copies of the chat
    -- on top of each other.
    if left then
        d.placed = true
        Chat.Engine.Suppress(cf)
    elseif not d.placed then
        Chat.Engine.Unsuppress(cf)
    end

    if left then
        d.rect = { left, bottom, width, height }
        if host then
            host:ClearAllPoints()
            host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
            host:SetSize(width, height)
        end
    end

    -- A named bar texture from shared media, tinted by the background colour,
    -- or the flat fill when none is picked. SetColorTexture would throw the
    -- file away again, so the tinted path sets the file and the vertex colour
    -- separately.
    --
    -- Asked through MediaStatusbarValid, not through MediaStatusbar alone:
    -- the latter answers with Blizzard's own status bar for a name it cannot
    -- resolve, so a texture whose addon has been uninstalled would come back
    -- as grey chrome instead of falling through to the flat fill.
    local wanted = db.bgTexture
    local barFile = type(wanted) == "string" and wanted ~= ""
        and ns.MediaStatusbarValid and ns.MediaStatusbarValid(wanted)
        and ns.MediaStatusbar(wanted)
    if barFile then
        bg.tex:SetTexture(barFile)
        bg.tex:SetVertexColor(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.65)
    else
        bg.tex:SetColorTexture(db.bgColor.r, db.bgColor.g, db.bgColor.b, db.bgColor.a or 0.65)
        bg.tex:SetVertexColor(1, 1, 1, 1)
    end
    ns.LayoutEdges(bg.edges, bg, db.showBorder and (db.borderSize or 1) or 0,
        db.borderColor.r, db.borderColor.g, db.borderColor.b, db.borderColor.a or 0.18, 0)
    -- Our frames are UIParent children, so they do not hide with the window:
    -- docked windows share one rectangle and the client shows only the
    -- selected one. Without this every docked window's text was drawn over
    -- the others.
    Panel.SyncShown(cf)

    Chat.Engine.ApplyFont(cf)
    placeEditBox(cf, db)
    styleEditBox(cf, db)
    watchInput()
    Panel.LayoutInput(cf, true)

    -- The panel has to follow the window when it is dragged or resized. A
    -- script hook is safe where a field write is not, and the work itself is
    -- deferred so it never runs inside the client's own layout pass.
    if not d.sizeHooked then
        d.sizeHooked = true
        local function follow()
            if not Chat.mod.active then return end
            Chat.Queue("chat.place." .. tostring(cf:GetID()), function() Panel.Apply(cf) end)
        end
        pcall(cf.HookScript, cf, "OnSizeChanged", follow)
        pcall(cf.HookScript, cf, "OnShow", follow)
    end
end

-- ----------------------------------------------------------------- lock --

-- Lock the size of the main chat window.
--
-- The lock is SetResizable on the frame, not the grip. A grip is one way into
-- a resize and its name changes between clients; the frame's own resizable
-- flag is the thing every path has to go through. Confirmed present on this
-- build: SetResizable, IsResizable and SetResizeBounds are all in the 1.60.1
-- widget API.
--
-- The grip button is disabled too where it exists, so the player does not
-- keep dragging a handle that has quietly stopped meaning anything. It is
-- looked up rather than assumed: the generated frame list for this build does
-- not carry ChatFrame1ResizeButton, so it may well be nil here, and a lock
-- that depended on it would be a lock that does nothing.
--
-- What is deliberately NOT used is FCF_SetLocked or the window's isLocked
-- flag. Both live in the client's dock bookkeeping, and an addon that writes
-- there taints the pass that reads it back -- which is the whisper path.
--
-- Only the main window, which is what the setting says. In combat the call is
-- skipped rather than attempted: the chat frames are protected, a blocked
-- protected call raises NO error and pcall answers true, so an attempt in
-- combat would look like it worked and quietly not have. The regen handler in
-- Core runs this again the moment combat ends.
function Panel.ApplyLock()
    if InCombatLockdown() then return end
    local cf = _G.ChatFrame1
    if not cf then return end
    local locked = Chat.mod.active and Chat.db().lockChatSize and true or false

    pcall(cf.SetResizable, cf, not locked)

    local btn = _G.ChatFrame1ResizeButton or cf.ResizeButton or cf.resizeButton
    if btn then
        pcall(btn.EnableMouse, btn, not locked)
        -- Written, never read: GetAlpha on a chat widget can answer with a
        -- secret while chat is restricted. Unlocking writes 1 and lets the
        -- client's own hover scripts take the grip back from there.
        pcall(btn.SetAlpha, btn, locked and 0 or 1)
    end
end

-- ---------------------------------------------------------------- follow --
--
-- Our panel sits at numbers, not on an anchor, so it has to be told when the
-- window moves. A resize fires OnSizeChanged; a MOVE fires nothing at all --
-- dragging the chat in Edit Mode left the panel, the text and the input row
-- behind where the window used to be. So the rectangle is compared instead,
-- and the panel re-placed only when it actually changed: from the tab watcher
-- four times a second, and every frame while Edit Mode is open, where the
-- window is being dragged. Always from our own timer or OnUpdate, never from
-- inside the client's layout pass.
function Panel.Follow(cf)
    local d = Chat.Data(cf)
    if not (Chat.Owned(cf) and d.placed) then return false end
    local left, bottom, width, height = rectOf(cf)
    if not left then return false end
    local r = d.rect
    if r and math.abs(r[1] - left) < 0.05 and math.abs(r[2] - bottom) < 0.05
        and math.abs(r[3] - width) < 0.05 and math.abs(r[4] - height) < 0.05 then
        return false
    end
    d.rect = { left, bottom, width, height }
    if d.host then
        d.host:ClearAllPoints()
        d.host:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
        d.host:SetSize(width, height)
    end
    Panel.LayoutInput(cf, true)
    return true
end

function Panel.FollowAll()
    if not Chat.mod.active then return end
    local moved = false
    for _, cf in ipairs(Chat.Frames()) do
        if Panel.Follow(cf) then moved = true end
    end
    if moved and Chat.Sidebar and Chat.Sidebar.SyncNewWindow then Chat.Sidebar.SyncNewWindow() end
end

-- Per-frame while Edit Mode is open, idle otherwise. The Edit Mode manager's
-- own show and hide are script hooks on a frame that is not a chat frame and
-- only arm our driver; nothing of ours runs in Edit Mode's apply chain.
local follower
local function watchEditMode()
    if follower or not _G.EditModeManagerFrame then return end
    follower = CreateFrame("Frame")
    follower:Hide()
    follower:SetScript("OnUpdate", Panel.FollowAll)
    _G.EditModeManagerFrame:HookScript("OnShow", function()
        if Chat.mod.active then follower:Show() end
    end)
    _G.EditModeManagerFrame:HookScript("OnHide", function()
        follower:Hide()
        -- Edit Mode commits its final position on close; one pass on the next
        -- frame catches it, and a full refresh puts everything else straight.
        C_Timer.After(0, Panel.FollowAll)
        if Chat.mod.active then Chat.Refresh() end
    end)
end

function Panel.ApplyAll()
    -- the main window's saved place first: every panel is measured off it
    if Panel.ApplyChatPlace then Panel.ApplyChatPlace() end
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Owned(cf) then Panel.Apply(cf) end
    end
    Panel.ApplyLock()
    watchEditMode()
end

function Panel.Release()
    if follower then follower:Hide() end
    -- The grip first, and through the same function: mod.active is already
    -- false by the time Release runs, so ApplyLock reads "not locked" and
    -- gives the client its grip back without a second copy of the logic.
    Panel.ApplyLock()

    for _, cf in ipairs(Chat.Frames()) do
        local d = Chat.Data(cf)
        if d.bg then d.bg:Hide() end
        -- Height and font go back to what the client had, for every box we
        -- styled -- including the ones we never moved.
        if d.editOldHeight ~= nil then
            local eb = cf.editBox or _G[cf:GetName() .. "EditBox"]
            if eb then
                if d.editOldHeight then pcall(eb.SetHeight, eb, d.editOldHeight) end
                if d.editOldFont then
                    pcall(eb.SetFont, eb, d.editOldFont[1], d.editOldFont[2], d.editOldFont[3])
                end
            end
        end

        -- The input line gets its border art back and goes back to the
        -- client's own anchors, as its template sets them: under the window,
        -- right edge on the scroll bar.
        local eb = editBoxOf(cf)
        if eb then setEditArt(eb, 1) end
        if eb and d.editMoved then
            pcall(function()
                eb:ClearAllPoints()
                eb:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", -5, -2)
                if cf.ScrollBar then
                    eb:SetPoint("RIGHT", cf.ScrollBar, "RIGHT", 8, 0)
                else
                    eb:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", 5, -2)
                end
            end)
            d.editMoved, d.editSide = nil, nil
        end
        d.inputRow = nil
    end
end

-- What the options say about a panel that cannot be placed, so the answer is
-- in one place rather than guessed at three call sites.
function Panel.StatusText()
    for _, cf in ipairs(Chat.Frames()) do
        if Chat.Owned(cf) and not rectOf(cf) then
            return L["The client is not letting the addon read where the chat window is right now."]
        end
    end
    return nil
end

-- ---------------------------------------------------------------- mover --
--
-- One box in our edit mode for the whole chat group. The panel, the text, the
-- tab strip and the side column all sit on the main window's rectangle, so
-- moving the main window moves all of them: Panel.Follow picks the new
-- rectangle up like it picks up a drag in the client's own editor.
--
-- HOW THE MAIN WINDOW IS MOVED, AND WHY THIS WAY
--
-- ChatFrame1 is an Edit Mode system on this client (FloatingChatFrame.xml:
-- inherits EditModeChatFrameSystemTemplate, dontSavePosition="true"). Its place
-- is not in the chat's own cache: FCF_RestorePositionAndDimensions returns
-- straight away for DEFAULT_CHAT_FRAME ("now controlled via edit mode"), and
-- FCF_SavePositionAndDimensions only matters for the other windows. The place
-- lives in the Edit Mode layout and ApplySystemAnchor puts it on the frame.
--
-- EditModeSystemMixin:OnSystemLoad replaces the frame's SetPoint and
-- ClearAllPoints with Lua overrides (EditModeSystemTemplates.lua). Called from
-- here, SetPointOverride would write snappedToFrame on the chat frame and
-- editModeSystemAnchorDirty on the Edit Mode manager from addon code -- fields
-- the manager later reads in its own secure passes. So neither override is
-- called. The frame is moved with the engine methods the mixin kept as
-- SetPointBase / ClearAllPointsBase, which write no Lua state at all. Nothing
-- of the client's is written, called or hooked: no FCF_ function, no layout
-- save, no field on the frame. Script hooks on the Edit Mode manager (a frame
-- that is not a chat frame) only arm timers, as watchEditMode above does.
--
-- The place is ours: Chat.db().chatPos, the window's bottom-left corner in
-- UIParent units. The client's layout keeps its own place untouched; the
-- client re-applies it whenever a layout loads, and ours goes back on top.
-- A reset (and switching the module off) hands the window back to the place
-- in the client's layout. Moving the chat in the client's own editor and
-- saving makes the client's place the one that counts again.
--
-- The size stays the client's (Edit Mode's width and height settings, the
-- resize grip): Edit Mode stores it as layout settings, and a size written
-- from here would be undone by the next layout load while bypassing none of
-- that bookkeeping.
--
-- The box itself sits on a proxy of our own over the window's rectangle,
-- because the mover core writes anchors on its target directly -- which on
-- the chat frame would be exactly the overrides above.

local proxy, chatMover
local moveDB = {}          -- the box's view: the window's CENTRE, UIParent units
local pending              -- "place" | "handback", waiting for the end of combat
local liveMoved            -- the window was moved by a drag not yet dropped
local clientAnchor         -- the layout's anchor as it was when its editor opened
local placedByUs           -- the window sits on a place of ours, not the layout's

local function baseMethod(cf, base, name)
    local fn = cf[base]
    if type(fn) == "function" then return fn end
    local mt = getmetatable(cf)
    local idx = mt and mt.__index
    return type(idx) == "table" and idx[name] or nil
end

local function placeChat(left, bottom)
    local cf = _G.ChatFrame1
    if not cf then return false end
    if InCombatLockdown() then pending = "place"; return false end
    local clear = baseMethod(cf, "ClearAllPointsBase", "ClearAllPoints")
    local setPoint = baseMethod(cf, "SetPointBase", "SetPoint")
    if not (clear and setPoint) then return false end
    local s = ns:GetScaleRatio(cf)
    local ok = pcall(function()
        clear(cf)
        setPoint(cf, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / s, bottom / s)
    end)
    if ok then placedByUs = true end
    return ok
end

-- The client's layout anchor for the window -- read, never written.
local function anchorInfo()
    local cf = _G.ChatFrame1
    local info = cf and cf.systemInfo
    if type(info) ~= "table" or type(info.anchorInfo) ~= "table" then return nil end
    return info.anchorInfo, info.anchorInfo2
end

-- Back to the place the client's layout names, the way ApplySystemAnchor
-- puts it there.
local function handBack()
    local cf = _G.ChatFrame1
    local a, a2 = anchorInfo()
    if not (cf and a) then return false end
    if InCombatLockdown() then pending = "handback"; return false end
    local clear = baseMethod(cf, "ClearAllPointsBase", "ClearAllPoints")
    local setPoint = baseMethod(cf, "SetPointBase", "SetPoint")
    if not (clear and setPoint) then return false end
    local scale = cf:GetScale() or 1
    if scale == 0 then scale = 1 end
    local ok = pcall(function()
        clear(cf)
        setPoint(cf, a.point, a.relativeTo, a.relativePoint, (a.offsetX or 0) / scale, (a.offsetY or 0) / scale)
        if type(a2) == "table" then
            setPoint(cf, a2.point, a2.relativeTo, a2.relativePoint, (a2.offsetX or 0) / scale, (a2.offsetY or 0) / scale)
        end
    end)
    if ok then placedByUs = nil end
    return ok
end

local function savedPos()
    local db = Chat.db()
    local p = type(db) == "table" and db.chatPos
    if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
    return nil
end

local function clientEditorOpen()
    local em = _G.EditModeManagerFrame
    return em and em:IsShown() and true or false
end

-- Put the window on the saved place, if there is one. Never while the
-- client's own editor is open (that is somebody moving it there) or while our
-- box is being dragged.
function Panel.ApplyChatPlace()
    if not Chat.mod.active or clientEditorOpen() then return end
    if chatMover and ns._draggingMover == chatMover then return end
    local p = savedPos()
    if p then
        placeChat(p.x, p.y)
    elseif placedByUs then
        -- a profile without a place of ours: the layout's place again
        handBack()
    end
end

local function syncProxy()
    local cf = _G.ChatFrame1
    if not (proxy and cf) then return false end
    if chatMover and ns._draggingMover == chatMover then return false end
    local l, b, w, h = rawRect(cf)
    if not l then return false end
    proxy:ClearAllPoints()
    proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
    proxy:SetSize(math.max(1, w), math.max(1, h))
    moveDB.x = l + w / 2 - (UIParent:GetWidth() or 0) / 2
    moveDB.y = b + h / 2 - (UIParent:GetHeight() or 0) / 2
    return true
end

local function settle()
    C_Timer.After(0, function()
        syncProxy()
        Panel.FollowAll()
    end)
end

-- The box sits where the window should go: save that, and move the window.
local function commitProxy()
    local l, b = proxy:GetLeft(), proxy:GetBottom()
    if not (l and b) then return end
    Chat.db().chatPos = { x = l, y = b }
    liveMoved = nil
    placeChat(l, b)
    local x, y = ns:GetCenterOffsets(proxy)
    if x then moveDB.x, moveDB.y = x, y end
    -- the client clamps its window to the screen; the box follows what it did
    settle()
end

local function preview(on)
    if not proxy then return end
    if on then
        if Chat.mod.active and syncProxy() then proxy:Show() else proxy:Hide() end
        return
    end
    proxy:Hide()
    -- a drag cut short by the editor closing moved the window without a drop
    if liveMoved then
        liveMoved = nil
        if savedPos() then Panel.ApplyChatPlace() else handBack() end
        settle()
    end
end

local watcher
local function installWatcher()
    if watcher then return end
    watcher = CreateFrame("Frame")
    -- A layout (re)loaded puts the client's anchor back on the window; ours
    -- goes back on top a frame later.
    watcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            local what = pending
            pending = nil
            if what == "handback" and not savedPos() then
                handBack()
            elseif what then
                Panel.ApplyChatPlace()
            end
            return
        end
        C_Timer.After(0, Panel.ApplyChatPlace)
    end)

    local em = _G.EditModeManagerFrame
    if not em then return end
    em:HookScript("OnShow", function()
        local a = anchorInfo()
        clientAnchor = a and { a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY } or nil
    end)
    em:HookScript("OnHide", function()
        C_Timer.After(0, function()
            -- a lock state hides the editor without ending it
            if em.IsEditModeActive and em:IsEditModeActive() then return end
            local before = clientAnchor
            clientAnchor = nil
            if not Chat.mod.active then return end
            -- On exit the client re-applies its saved layout. If that layout
            -- now puts the chat somewhere else, it was moved and saved there:
            -- the client's place counts from here on.
            local a = anchorInfo()
            if before and a and savedPos() and not (before[1] == a.point and before[2] == a.relativeTo
                and before[3] == a.relativePoint and before[4] == a.offsetX and before[5] == a.offsetY) then
                Chat.db().chatPos = nil
                return
            end
            Panel.ApplyChatPlace()
        end)
    end)
end

function Panel.InstallMover()
    installWatcher()
    if chatMover or not _G.ChatFrame1 then
        Panel.ApplyChatPlace()
        return
    end
    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetFrameStrata("LOW")
    proxy:Hide()
    local tick = 0
    proxy:SetScript("OnUpdate", function(self, elapsed)
        if chatMover and ns._draggingMover == chatMover then
            -- the window rides along with the box while it is dragged
            if InCombatLockdown() then return end
            local l, b = self:GetLeft(), self:GetBottom()
            if l and b and placeChat(l, b) then
                liveMoved = true
                Panel.FollowAll()
            end
            return
        end
        -- otherwise the box follows the window (the grip resizes it)
        tick = tick + elapsed
        if tick < 0.25 then return end
        tick = 0
        syncProxy()
    end)

    chatMover = ns:CreateMover(proxy, {
        key    = "chat",
        label  = L["Chat"],
        db     = moveDB,
        module = "chat",
        width  = 200,
        height = 40,
        applyPos = function()
            if ns._inMoverReset then
                local had = savedPos()
                Chat.db().chatPos = nil
                if had then handBack() end
                syncProxy()
                settle()
                return
            end
            if not Chat.mod.active then return end
            -- Re-apply the saved place, then commit only a real move (a
            -- nudge), so a blanket re-apply never turns the client's place
            -- into a saved one of ours.
            local wx, wy = moveDB.x, moveDB.y
            Panel.ApplyChatPlace()
            if not syncProxy() then return end
            if wx and wy and (math.abs(moveDB.x - wx) > 0.5 or math.abs(moveDB.y - wy) > 0.5) then
                proxy:ClearAllPoints()
                proxy:SetPoint("CENTER", UIParent, "CENTER", wx, wy)
                commitProxy()
            end
        end,
        onMove = function()
            if Chat.mod.active then commitProxy() end
        end,
        editPreview = preview,
    })
    syncProxy()
    Panel.ApplyChatPlace()
end

-- Off: the window goes back to the client's place; ours stays saved for the
-- next time the module is switched on.
function Panel.ReleaseMover()
    if proxy then proxy:Hide() end
    liveMoved = nil
    if savedPos() then handBack() end
end

-- Discard: the core restores the box by its centre and, through onMove, saves
-- that as a place of ours even when the chat had none. The saved value itself
-- is copied at the snapshot and put back after the core's restore.
local editSaved

hooksecurefunc(ns, "SnapshotEditState", function()
    local db = Chat.db()
    if type(db) ~= "table" then return end
    local p = savedPos()
    editSaved = { pos = p and { x = p.x, y = p.y } or false }
end)

hooksecurefunc(ns, "RestoreEditState", function()
    if not editSaved then return end
    local db = Chat.db()
    if type(db) ~= "table" then return end
    local p = editSaved.pos
    db.chatPos = p and { x = p.x, y = p.y } or nil
    if not Chat.mod.active then return end
    if p then Panel.ApplyChatPlace() else handBack() end
    liveMoved = nil
    settle()
end)

hooksecurefunc(ns, "ClearEditSnapshot", function() editSaved = nil end)
