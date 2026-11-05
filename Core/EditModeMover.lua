-- VuloForeverUI / Core / EditModeMover
--
-- A box in our edit mode for a CLIENT frame that is itself an Edit Mode system
-- (the minimap cluster, for one). The Chat module does the same for ChatFrame1
-- in its own copy (Modules/Chat/Panel.lua); this is that recipe as a helper.
--
-- WHY IT IS DONE THIS WAY
--
-- EditModeSystemMixin:OnSystemLoad replaces such a frame's SetPoint and
-- ClearAllPoints with Lua overrides (EditModeSystemTemplates.lua). Called from
-- addon code they write snappedToFrame on the frame and
-- editModeSystemAnchorDirty on the Edit Mode manager -- fields the manager
-- later reads in its own secure passes. So neither override is called: the
-- frame is moved with the engine methods the mixin kept aside as
-- SetPointBase / ClearAllPointsBase, which write no Lua state at all. Nothing
-- of the client's is written, called or hooked beyond script hooks on the
-- Edit Mode manager that only arm timers.
--
-- The place is ours (the frame's bottom-left corner in UIParent units, saved
-- where the caller says). The client re-applies its layout's place whenever a
-- layout loads; ours goes back on top a frame later -- but only out of combat,
-- so a reload of the layout during a fight (a level-up does it) left the frame
-- on the layout's place until the fight ended. Our places are NOT written
-- into the client's layout: C_EditMode.SaveLayouts from addon code made the
-- client reload its layout inside our call, and the party and raid frames it
-- rebuilt there ran tainted (secret-value errors by the thousand, 0.20.0).
-- Moving the frame in the client's own editor and saving makes the client's
-- place the one that counts again; a reset hands the frame back to it.
--
-- The box sits on a proxy of ours over the frame's rectangle, because the
-- mover core writes anchors on its target directly -- which on the client
-- frame would be exactly the overrides above. The size stays the client's.
--
-- Two variations, through opts:
--   corner = "TOPLEFT"  the frame is pinned by its top-left corner instead of
--                       the bottom-left one, for a frame that grows downwards
--                       (the quest tracker); the saved y is then its top.
--   A frame that is NOT an Edit Mode system (target-of-target: a child of the
--   target frame that Blizzard anchors once, in its template) has no layout
--   place to hand back to. Its own anchors are read when the box is made and
--   are what a reset puts back. Such a frame is moved with plain SetPoint --
--   there is no mixin override to avoid.
local _, ns = ...

local instances = {}

-- Two Edit Mode anchors at the same place (half a unit of slack).
local function sameAnchor(a, b)
    return type(a) == "table" and type(b) == "table" and a.point == b.point
        and a.relativeTo == b.relativeTo and a.relativePoint == b.relativePoint
        and math.abs((a.offsetX or 0) - (b.offsetX or 0)) < 0.5
        and math.abs((a.offsetY or 0) - (b.offsetY or 0)) < 0.5
end

local function baseMethod(f, base, name)
    local fn = f[base]
    if type(fn) == "function" then return fn end
    local mt = getmetatable(f)
    local idx = mt and mt.__index
    return type(idx) == "table" and idx[name] or nil
end

local rawRect = ns.UIParentRect

local function editorOpen()
    local em = _G.EditModeManagerFrame
    return em and em:IsShown() and true or false
end

local function new(frame, opts)
    local I = { frame = frame, opts = opts, moveDB = {} }
    local proxy, mover, pending, liveMoved, clientAnchor, placedByUs
    local corner = opts.corner == "TOPLEFT" and "TOPLEFT" or "BOTTOMLEFT"

    -- The proxy's edge the saved y refers to.
    local function proxyY(f)
        if corner == "TOPLEFT" then return f:GetTop() end
        return f:GetBottom()
    end

    local function savedPos()
        local p = opts.getPos()
        if type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" then return p end
        return nil
    end

    local function place(left, bottom)
        if InCombatLockdown() then pending = "place"; return false end
        local clear = baseMethod(frame, "ClearAllPointsBase", "ClearAllPoints")
        local setPoint = baseMethod(frame, "SetPointBase", "SetPoint")
        if not (clear and setPoint) then return false end
        local s = ns:GetScaleRatio(frame)
        local ok = pcall(function()
            clear(frame)
            setPoint(frame, corner, UIParent, "BOTTOMLEFT", left / s, bottom / s)
        end)
        if ok then placedByUs = true end
        return ok
    end

    -- The client's layout anchor -- read, never written.
    local function anchorInfo()
        local info = frame.systemInfo
        if type(info) ~= "table" or type(info.anchorInfo) ~= "table" then return nil end
        return info.anchorInfo, info.anchorInfo2
    end

    -- A frame outside the Edit Mode systems: its own anchors, read once, while
    -- they are still Blizzard's. A secret or unresolved point leaves the list
    -- empty, and such a frame simply keeps the place it was given last.
    local ownPoints
    if not anchorInfo() then
        ownPoints = {}
        local ok, n = pcall(frame.GetNumPoints, frame)
        for i = 1, (ok and ns.Num(n)) and n or 0 do
            local okp, p, rel, rp, x, y = pcall(frame.GetPoint, frame, i)
            if okp and type(p) == "string" and ns.Num(x) and ns.Num(y) then
                ownPoints[#ownPoints + 1] = { p, rel, rp, x, y }
            end
        end
    end

    local function handBackOwn()
        if not (ownPoints and ownPoints[1]) then return false end
        if InCombatLockdown() then pending = "handback"; return false end
        local ok = pcall(function()
            frame:ClearAllPoints()
            for _, pt in ipairs(ownPoints) do frame:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
        end)
        if ok then placedByUs = nil end
        return ok
    end

    -- Back to the place the layout names, the way ApplySystemAnchor puts it.
    local function handBack()
        local a, a2 = anchorInfo()
        if not a then return handBackOwn() end
        if InCombatLockdown() then pending = "handback"; return false end
        local clear = baseMethod(frame, "ClearAllPointsBase", "ClearAllPoints")
        local setPoint = baseMethod(frame, "SetPointBase", "SetPoint")
        if not (clear and setPoint) then return false end
        local scale = frame:GetScale() or 1
        if scale == 0 then scale = 1 end
        local ok = pcall(function()
            clear(frame)
            setPoint(frame, a.point, a.relativeTo, a.relativePoint, (a.offsetX or 0) / scale, (a.offsetY or 0) / scale)
            if type(a2) == "table" then
                setPoint(frame, a2.point, a2.relativeTo, a2.relativePoint, (a2.offsetX or 0) / scale, (a2.offsetY or 0) / scale)
            end
        end)
        if ok then placedByUs = nil end
        return ok
    end

    function I.Apply()
        if not opts.isActive() or editorOpen() then return end
        if mover and ns._draggingMover == mover then return end
        local p = savedPos()
        local moved
        if p then
            moved = place(p.x, p.y)
        elseif placedByUs then
            moved = handBack()
        end
        if moved and I.OnPlaced then I.OnPlaced() end
    end

    local function syncProxy()
        if not proxy then return false end
        if mover and ns._draggingMover == mover then return false end
        local l, b, w, h = rawRect(frame)
        if not l then return false end
        proxy:ClearAllPoints()
        proxy:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)
        proxy:SetSize(math.max(1, w), math.max(1, h))
        I.moveDB.x = l + w / 2 - (UIParent:GetWidth() or 0) / 2
        I.moveDB.y = b + h / 2 - (UIParent:GetHeight() or 0) / 2
        return true
    end

    -- The frame moved without the box: the box follows, and so does every
    -- window docked to it. The box is hidden outside the editor, where its
    -- OnUpdate never runs, so without this a docked window measured against
    -- the place the frame had BEFORE ours was applied -- after a relog the
    -- DoT bars stood off by exactly that distance. Followers are carried, not
    -- re-measured (ns:RepositionMoverChildren).
    -- Only when the box really moved: a follower's own onPlaced may call back
    -- into Apply (the minimap's does), and an unconditional carry turned that
    -- into a loop through settle() that never ended.
    function I.OnPlaced()
        local wx, wy = I.moveDB.x, I.moveDB.y
        if not syncProxy() then return end
        if wx and wy and math.abs(I.moveDB.x - wx) < 0.5 and math.abs(I.moveDB.y - wy) < 0.5 then return end
        if mover and ns.RepositionMoverChildren then ns:RepositionMoverChildren(mover) end
    end

    local function settle()
        C_Timer.After(0, function()
            syncProxy()
            if opts.onPlaced then opts.onPlaced() end
        end)
    end

    local function commitProxy()
        local l, b = proxy:GetLeft(), proxyY(proxy)
        if not (l and b) then return end
        opts.setPos({ x = l, y = b })
        liveMoved = nil
        place(l, b)
        local x, y = ns:GetCenterOffsets(proxy)
        if x then I.moveDB.x, I.moveDB.y = x, y end
        settle()
    end

    local function preview(on)
        if not proxy then return end
        if on then
            if opts.isActive() and syncProxy() then proxy:Show() else proxy:Hide() end
            return
        end
        proxy:Hide()
        -- a drag cut short by the editor closing moved the frame without a drop
        if liveMoved then
            liveMoved = nil
            if savedPos() then I.Apply() else handBack() end
            settle()
        end
    end

    -- A layout (re)loaded, a loading screen, the end of a fight.
    local watcher = CreateFrame("Frame")
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
                I.Apply()
            end
            return
        end
        C_Timer.After(0, I.Apply)
    end)
    -- The client's editor opens and closes (one shared hook drives all boxes,
    -- see hookClientEditor). Its place is noted on the way in; on the way out
    -- a place that differs from that note AND from what we wrote ourselves is
    -- a move made there, and it counts from then on. The manager's copy can be
    -- older than the saved layout (our SaveLayouts does not refresh it), and
    -- leaving its editor reloads the saved one -- so "different from the note"
    -- alone took our own sync for a move of the player's.
    function I.ClientEditorShown()
        local a = anchorInfo()
        clientAnchor = a and { point = a.point, relativeTo = a.relativeTo, relativePoint = a.relativePoint,
                               offsetX = a.offsetX, offsetY = a.offsetY } or nil
    end
    function I.ClientEditorHidden()
        local before = clientAnchor
        clientAnchor = nil
        if not opts.isActive() then return end
        local a = anchorInfo()
        if before and a and savedPos() and not sameAnchor(before, a) then
            opts.setPos(nil)    -- moved and saved there: the client's place counts
            return
        end
        I.Apply()
    end

    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetFrameStrata("LOW")
    proxy:Hide()
    local tick = 0
    proxy:SetScript("OnUpdate", function(self, elapsed)
        if mover and ns._draggingMover == mover then
            -- the frame rides along with the box while it is dragged
            if InCombatLockdown() then return end
            local l, b = self:GetLeft(), proxyY(self)
            if l and b and place(l, b) then liveMoved = true end
            return
        end
        tick = tick + elapsed
        if tick < 0.25 then return end
        tick = 0
        syncProxy()
    end)

    mover = ns:CreateMover(proxy, {
        key    = opts.key,
        label  = opts.label,
        db     = I.moveDB,
        module = opts.module,
        fadeTarget = frame,     -- the box is a stand-in; the real frame is what fades
        width  = 200, height = 40,
        applyPos = function()
            if ns._inMoverReset then
                opts.setPos(nil)
                handBack()
                syncProxy()
                settle()
                return
            end
            if not opts.isActive() then return end
            -- Re-apply the saved place, then commit only a real move (a nudge),
            -- so a blanket re-apply never turns the layout's place into ours.
            local wx, wy = I.moveDB.x, I.moveDB.y
            I.Apply()
            if not syncProxy() then return end
            if wx and wy and (math.abs(I.moveDB.x - wx) > 0.5 or math.abs(I.moveDB.y - wy) > 0.5) then
                proxy:ClearAllPoints()
                proxy:SetPoint("CENTER", UIParent, "CENTER", wx, wy)
                commitProxy()
            end
        end,
        onMove = function()
            -- "Reset this frame" in the panel comes here (ns:MoverSetCenter),
            -- not through applyPos: without this it saved the screen centre
            -- as a place of ours.
            if ns._inMoverReset then mover.opts.applyPos(); return end
            if opts.isActive() then commitProxy() end
        end,
        editPreview = preview,
    })
    I.mover = mover

    -- Off: the frame goes back to the layout's place; ours stays saved.
    function I.Release()
        if proxy then proxy:Hide() end
        liveMoved = nil
        if savedPos() then handBack() end
    end

    -- Discard: the core restores the box by its centre and, through onMove,
    -- would save that as a place of ours even when there was none. The saved
    -- value is copied at the snapshot and put back after the core's restore.
    function I.Snapshot()
        local p = savedPos()
        I.editSaved = { pos = p and { x = p.x, y = p.y } or false }
    end
    function I.Restore()
        if not I.editSaved then return end
        local p = I.editSaved.pos
        opts.setPos(p and { x = p.x, y = p.y } or nil)
        if opts.isActive() then
            if p then I.Apply() else handBack() end
            liveMoved = nil
            settle()
        end
    end

    syncProxy()
    I.Apply()
    return I
end

-- One hook pair for all boxes on the client's editor: each box notes the
-- layout's place when it opens and judges it when it has closed.
local clientHooked
local function hookClientEditor()
    local em = _G.EditModeManagerFrame
    if clientHooked or not em then return end
    clientHooked = true
    em:HookScript("OnShow", function()
        for _, I in ipairs(instances) do I.ClientEditorShown() end
    end)
    em:HookScript("OnHide", function()
        C_Timer.After(0, function()
            if em.IsEditModeActive and em:IsEditModeActive() then return end
            for _, I in ipairs(instances) do I.ClientEditorHidden() end
        end)
    end)
end

-- One per frame; asking again returns the same one.
function ns:AttachEditModeMover(frame, opts)
    if not frame then return nil end
    hookClientEditor()
    for _, I in ipairs(instances) do
        if I.frame == frame then return I end
    end
    local I = new(frame, opts)
    instances[#instances + 1] = I
    return I
end

hooksecurefunc(ns, "SnapshotEditState", function()
    for _, I in ipairs(instances) do I.Snapshot() end
end)
hooksecurefunc(ns, "RestoreEditState", function()
    for _, I in ipairs(instances) do I.Restore() end
end)
hooksecurefunc(ns, "ClearEditSnapshot", function()
    for _, I in ipairs(instances) do I.editSaved = nil end
end)
