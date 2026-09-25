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
-- where the caller says). The client's layout keeps its own place untouched
-- and re-applies it whenever a layout loads; ours goes back on top a frame
-- later. A reset, or the owning module switching off, hands the frame back to
-- the layout's place. Moving the frame in the client's own editor and saving
-- makes the client's place the one that counts again.
--
-- The box sits on a proxy of ours over the frame's rectangle, because the
-- mover core writes anchors on its target directly -- which on the client
-- frame would be exactly the overrides above. The size stays the client's.
local _, ns = ...

local instances = {}

local function readable(v)
    if not ns.CanRead(v) then return false end
    return type(v) == "number"
end

local function baseMethod(f, base, name)
    local fn = f[base]
    if type(fn) == "function" then return fn end
    local mt = getmetatable(f)
    local idx = mt and mt.__index
    return type(idx) == "table" and idx[name] or nil
end

-- The frame's rectangle in UIParent units; nil while it is not resolved yet.
local function rawRect(f)
    local ok, left, bottom, width, height = pcall(f.GetRect, f)
    if not ok then return nil end
    if not (readable(left) and readable(bottom) and readable(width) and readable(height)) then
        return nil
    end
    local s = (f:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return left * s, bottom * s, width * s, height * s
end

local function editorOpen()
    local em = _G.EditModeManagerFrame
    return em and em:IsShown() and true or false
end

local function new(frame, opts)
    local I = { frame = frame, opts = opts, moveDB = {} }
    local proxy, mover, pending, liveMoved, clientAnchor, placedByUs

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
            setPoint(frame, "BOTTOMLEFT", UIParent, "BOTTOMLEFT", left / s, bottom / s)
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

    -- Back to the place the layout names, the way ApplySystemAnchor puts it.
    local function handBack()
        local a, a2 = anchorInfo()
        if not a then return false end
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
        if p then
            place(p.x, p.y)
        elseif placedByUs then
            handBack()
        end
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

    local function settle()
        C_Timer.After(0, function()
            syncProxy()
            if opts.onPlaced then opts.onPlaced() end
        end)
    end

    local function commitProxy()
        local l, b = proxy:GetLeft(), proxy:GetBottom()
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
    local em = _G.EditModeManagerFrame
    if em then
        em:HookScript("OnShow", function()
            local a = anchorInfo()
            clientAnchor = a and { a.point, a.relativeTo, a.relativePoint, a.offsetX, a.offsetY } or nil
        end)
        em:HookScript("OnHide", function()
            C_Timer.After(0, function()
                if em.IsEditModeActive and em:IsEditModeActive() then return end
                local before = clientAnchor
                clientAnchor = nil
                if not opts.isActive() then return end
                -- The client's editor saved a new place: that one counts now.
                local a = anchorInfo()
                if before and a and savedPos() and not (before[1] == a.point and before[2] == a.relativeTo
                    and before[3] == a.relativePoint and before[4] == a.offsetX and before[5] == a.offsetY) then
                    opts.setPos(nil)
                    return
                end
                I.Apply()
            end)
        end)
    end

    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetFrameStrata("LOW")
    proxy:Hide()
    local tick = 0
    proxy:SetScript("OnUpdate", function(self, elapsed)
        if mover and ns._draggingMover == mover then
            -- the frame rides along with the box while it is dragged
            if InCombatLockdown() then return end
            local l, b = self:GetLeft(), self:GetBottom()
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
        width  = 200, height = 40,
        applyPos = function()
            if ns._inMoverReset then
                local had = savedPos()
                opts.setPos(nil)
                if had then handBack() end
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

-- One per frame; asking again returns the same one.
function ns:AttachEditModeMover(frame, opts)
    if not frame then return nil end
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
