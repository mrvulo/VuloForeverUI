-- VuloForeverUI / Core / Mover / Size: size matching, reset/remove/apply, position setters, free move.
local _, ns = ...
local MV = ns._MV
local moverShouldEdit = MV.moverShouldEdit
local applyPos        = MV.applyPos
local commitPos       = MV.commitPos
local sizeStore       = MV.sizeStore

-- ---------------------------------------------------------------------------
-- Size matching: a window can permanently take another's width and/or height.
-- Stored per profile as sizeLinks[childKey] = { w = key, h = key }.
--
-- CAVEAT: this drives SetWidth/SetHeight on the frame itself. Windows whose
-- size is recomputed by their own module (bars that rebuild from their config)
-- will snap back on the next layout pass; ns:MoverSizeMatchSticks reports that
-- so the UI can say so instead of silently doing nothing.

function ns:GetMoverSizeLink(key)
    local store = sizeStore()
    return (store and key) and store[key] or nil
end

-- axis is "w" or "h"; walking the chain of that same axis catches A->B->A.
function ns:MoverSizeWouldCycle(childKey, targetKey, axis)
    local store = sizeStore()
    if not store then return false end
    local seen, cur = {}, targetKey
    while cur do
        if cur == childKey then return true end
        if seen[cur] then return false end
        seen[cur] = true
        local e = store[cur]
        cur = (type(e) == "table" and type(e[axis]) == "string") and e[axis] or nil
    end
    return false
end

function ns:SetMoverSizeLink(child, targetKey, axis)
    local store = sizeStore()
    if not (store and child and child.key and (axis == "w" or axis == "h")) then return false end
    local e = store[child.key]
    if not targetKey or targetKey == "" then
        if e then
            e[axis] = nil
            if not (e.w or e.h) then store[child.key] = nil end
        end
        return true
    end
    if targetKey == child.key or ns:MoverSizeWouldCycle(child.key, targetKey, axis) then
        return false
    end
    if not ns:GetMoverByKey(targetKey) then return false end
    e = e or {}
    e[axis] = targetKey
    store[child.key] = e
    ns:ApplyAllMoverSizeLinks()
    -- Edge anchors measure against the parent's extents, so a resize leaves every
    -- pinned child sitting in the wrong place until the positions are redone.
    ns:ApplyAllMoverLinks()
    return true
end

-- Sizes are compared in UIParent units so a scaled window still ends up the
-- same physical width as the one it is matched to.
local function applySizeLink(child, entry)
    if type(entry) ~= "table" or not (child.target and child.target.SetWidth) then return end
    -- Resizing a secure frame from Lua taints it exactly like repositioning does.
    if ns.IsSecureMoverTarget and ns.IsSecureMoverTarget(child.target) then return end
    local cr = ns:GetScaleRatio(child.target)
    if cr == 0 then cr = 1 end
    if type(entry.w) == "string" then
        local p = ns:GetMoverByKey(entry.w)
        if p and p.target then
            local w = (p.target:GetWidth() or 0) * ns:GetScaleRatio(p.target)
            if w > 0 then pcall(child.target.SetWidth, child.target, w / cr) end
        end
    end
    if type(entry.h) == "string" then
        local p = ns:GetMoverByKey(entry.h)
        if p and p.target then
            local h = (p.target:GetHeight() or 0) * ns:GetScaleRatio(p.target)
            if h > 0 then pcall(child.target.SetHeight, child.target, h / cr) end
        end
    end
end

-- Roots first: for A->B->C, sizing C before B would read B's stale width.
function ns:ApplyAllMoverSizeLinks()
    local store = sizeStore()
    if not store then return end
    local done = {}
    local function resolve(key, depth)
        if done[key] or (depth or 0) > 20 then return end
        done[key] = true
        local e = store[key]
        if type(e) ~= "table" then return end
        if type(e.w) == "string" and store[e.w] then resolve(e.w, (depth or 0) + 1) end
        if type(e.h) == "string" and store[e.h] then resolve(e.h, (depth or 0) + 1) end
        local child = ns:GetMoverByKey(key)
        if child then applySizeLink(child, e) end
    end
    for key in pairs(store) do resolve(key, 0) end
end

-- Did the frame actually keep the size we gave it? Used to warn about windows
-- whose module owns their dimensions.
function ns:MoverSizeMatchSticks(child, axis)
    local e = child and child.key and ns:GetMoverSizeLink(child.key)
    if not (e and type(e[axis]) == "string" and child.target) then return true end
    local p = ns:GetMoverByKey(e[axis])
    if not (p and p.target) then return true end
    local get  = (axis == "w") and "GetWidth" or "GetHeight"
    local want = (p.target[get](p.target) or 0) * ns:GetScaleRatio(p.target)
    local have = (child.target[get](child.target) or 0) * ns:GetScaleRatio(child.target)
    return math.abs(want - have) <= 1.5
end

function ns:ResetAllMovers()
    -- lets onMove callbacks tell an explicit reset apart from a drag snapped to 0,0
    ns._inMoverReset = true
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        local db   = opts and opts.db
        if db then
            db.x, db.y = 0, 0
            pcall(applyPos, mover)
        end
    end
    ns._inMoverReset = false
    ns:ApplyAllMoverLinks()
end

-- A LINKED window's position is derived, not stored: db.x/y only holds the last
-- result of that derivation. Re-applying it blind keeps the CENTRE and therefore
-- moves the EDGES whenever the frame has changed size since -- so the window
-- slides off whatever it was docked to, by half the size difference.
--
-- Modules/ActionBars.lua does exactly that: the modern bag bar and micro menu
-- re-measure themselves, set their holder to the new size, and call ApplyMover.
-- A holder starts life at a placeholder 220x40 and becomes its real size later,
-- so the jump is not small.
--
-- Deriving again costs nothing when there is no link -- ApplyMoverLink says so
-- and we fall through to the old path unchanged.
-- Take a mover out of edit mode for good: for a frame that is destroyed and
-- rebuilt (a closed meter window, a profile switch). There is no other way
-- off the lists, and a mover left on them would show twice in the link
-- picker and keep writing into a db that belongs to the profile just left.
function ns:RemoveMover(m)
    if not m or m.retired then return end
    m.retired = true
    if ns._draggingMover == m and ns.AbortMoverDrag then ns:AbortMoverDrag(m) end
    if ns.IsSelected and ns:IsSelected(m) and ns.DeselectMover then ns:DeselectMover() end
    m:Hide()
    local list = ns._movers
    for i = #list, 1, -1 do
        if list[i] == m then table.remove(list, i) end
    end
    if m.key and ns._moversByKey[m.key] == m then ns._moversByKey[m.key] = nil end
    m.key = nil
    m.opts.db = {}
    m.opts.applyPos = function() end
    m.opts.onMove, m.opts.editPreview = nil, nil
end

function ns:ApplyMover(mover)
    if not mover then return end
    local ok, linked = pcall(ns.ApplyMoverLink, ns, mover)
    if ok and linked then return end
    pcall(applyPos, mover)
end

function ns:MoverSetCenter(mover, x, y)
    if not (mover and mover.target and mover.opts and mover.opts.db) then return end
    mover.opts.db.x, mover.opts.db.y = x, y
    commitPos(mover)
    ns:OnMoverRepositioned(mover)
end

function ns:MoverSetScale(mover, s)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.scale = s
    applyPos(mover)
end

function ns:MoverSetAnchor(mover, point)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.anchor = point
    applyPos(mover)
end

function ns:MoverSetAnchorEnabled(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    mover.opts.db.anchorEnabled = on and true or false
    applyPos(mover)
end

function ns:IsMoverAnchorEnabled(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.anchorEnabled ~= false
end

-- Per-frame "free move": db.freeMove is deliberately separate from db.unlocked so
-- it never collides with per-module unlock buttons, and it never drives
-- opts.editPreview (a persistent state must not leave fake content on screen).
function ns:IsMoverFreeMove(mover)
    local db = mover and mover.opts and mover.opts.db
    return db ~= nil and db.freeMove and true or false
end

function ns:SetMoverFreeMove(mover, on)
    if not (mover and mover.opts and mover.opts.db) then return end
    on = on and true or false
    mover.opts.db.freeMove = on
    if on or moverShouldEdit(mover) then
        mover:Show()
    else
        mover:Hide()
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

function ns:RestoreFreeMovers()
    for _, mover in ipairs(ns._movers) do
        local db = mover.opts and mover.opts.db
        if db and db.freeMove then mover:Show() end
    end
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end
