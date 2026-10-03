-- VuloForeverUI / Core / Mover / Links: persistent window links (follow/dock) and the Edit-Mode discard snapshot.
local _, ns = ...
local MV = ns._MV
local commitPos = MV.commitPos

-- ---------------------------------------------------------------------------
-- Persistent window links: a mover can be pinned to another mover and follows
-- whenever that one moves. Stored PER PROFILE (class isolation intact) as
-- moverLinks[childKey] = { to = parentKey, dx, dy } with dx/dy in UIParent units.

local function linkStore()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.moverLinks = p.moverLinks or {}
    return p.moverLinks
end
MV.linkStore = linkStore

-- Declared alongside linkStore because the edit-mode snapshot below reads both.
local function sizeStore()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.moverSizeLinks = p.moverSizeLinks or {}
    return p.moverSizeLinks
end
MV.sizeStore = sizeStore

-- frame centre as an offset from UIParent's centre, in UIParent units —
-- comparable across frames with different effective scales
local function screenCenter(frame)
    if not (frame and frame.GetCenter) then return nil end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and px) then return nil end
    local fs = frame:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale() or 1
    if us == 0 then return nil end
    return (fx * fs - px * us) / us, (fy * fs - py * us) / us
end

-- half width / height in UIParent units (so edge math is scale-agnostic)
local function screenExtent(frame)
    if not (frame and frame.GetWidth) then return 0, 0 end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    return (frame:GetWidth() or 0) * s / 2, (frame:GetHeight() or 0) * s / 2
end

-- Offsets that keep `child` invariant relative to `parent` for a given side.
-- side CENTER (or nil): dx,dy are the centre-to-centre delta (legacy behaviour).
-- LEFT/RIGHT: dx is the signed EDGE gap on X, dy the centre delta on Y.
-- TOP/BOTTOM: dy is the signed EDGE gap on Y, dx the centre delta on X.
-- Edge gaps survive either frame being resized; centre deltas keep the cross axis.
local function computeLinkOffsets(childFrame, parentFrame, side)
    local ccx, ccy = screenCenter(childFrame)
    local pcx, pcy = screenCenter(parentFrame)
    if not (ccx and pcx) then return nil end
    local chw, chh = screenExtent(childFrame)
    local phw, phh = screenExtent(parentFrame)
    if side == "LEFT" then
        return (pcx - phw) - (ccx + chw), ccy - pcy
    elseif side == "RIGHT" then
        return (ccx - chw) - (pcx + phw), ccy - pcy
    elseif side == "TOP" then
        return ccx - pcx, (ccy - chh) - (pcy + phh)
    elseif side == "BOTTOM" then
        return ccx - pcx, (pcy - phh) - (ccy + chh)
    end
    return ccx - pcx, ccy - pcy
end

-- Child centre (UIParent units) reproduced from parent + stored offsets + side.
local function linkChildCenter(childFrame, parentFrame, link)
    local pcx, pcy = screenCenter(parentFrame)
    if not pcx then return nil end
    local dx = type(link.dx) == "number" and link.dx or 0
    local dy = type(link.dy) == "number" and link.dy or 0
    local chw, chh = screenExtent(childFrame)
    local phw, phh = screenExtent(parentFrame)
    local side = link.side
    if side == "LEFT" then
        return (pcx - phw) - dx - chw, pcy + dy
    elseif side == "RIGHT" then
        return (pcx + phw) + dx + chw, pcy + dy
    elseif side == "TOP" then
        return pcx + dx, (pcy + phh) + dy + chh
    elseif side == "BOTTOM" then
        return pcx + dx, (pcy - phh) - dy - chh
    end
    return pcx + dx, pcy + dy
end

function ns:GetMoverLink(key)
    local store = linkStore()
    return (store and key) and store[key] or nil
end

function ns:MoverLinkWouldCycle(childKey, parentKey)
    local store = linkStore()
    if not store then return false end
    local seen, cur = {}, parentKey
    while cur do
        if cur == childKey then return true end
        if seen[cur] then return false end
        seen[cur] = true
        local l = store[cur]
        cur = (type(l) == "table" and type(l.to) == "string") and l.to or nil
    end
    return false
end

local VALID_SIDE = { CENTER = true, LEFT = true, RIGHT = true, TOP = true, BOTTOM = true }

-- side defaults to the child's current side, else CENTER (keeps legacy links intact).
function ns:SetMoverLink(child, parentKey, side)
    local store = linkStore()
    if not (store and child and child.key) then return false end
    if not parentKey or parentKey == "" then
        store[child.key] = nil
        return true
    end
    if parentKey == child.key or ns:MoverLinkWouldCycle(child.key, parentKey) then
        return false
    end
    local parent = ns:GetMoverByKey(parentKey)
    if not (parent and parent.target) then return false end
    local prev = store[child.key]
    side = (side and VALID_SIDE[side] and side)
        or (prev and prev.side and VALID_SIDE[prev.side] and prev.side)
        or "CENTER"
    local dx, dy = computeLinkOffsets(child.target, parent.target, side)
    if not dx then return false end
    store[child.key] = { to = parentKey, side = side, dx = dx, dy = dy }
    return true
end

-- Pick a side and DOCK to it: the child jumps flush against that edge of the
-- parent and centres on the cross axis. link.gap moves it back off the edge.
--
-- This used to re-measure instead -- "change only the side, so the child does
-- not jump" -- and that was the wrong instinct. The control is called ANCHOR
-- SIDE and the button above it "Anchor to window...", so choosing a side is a
-- request for the window to GO there. Re-measuring made the whole feature look
-- dead: the panel said "follows: Chat, side: centre" and the window sat wherever
-- it had been left. Reported as "ja folgt ist aber nicht ankert", which is
-- exactly right.
--
-- CENTER is the exception and keeps both the old meaning and the old behaviour:
-- it is the only value that is not an edge, so there is nothing to dock to. It
-- means "travel along with the parent, stay where you are".
function ns:SetMoverLinkSide(child, side, gap)
    local store = linkStore()
    if not (store and child and child.key and VALID_SIDE[side]) then return false end
    local link = store[child.key]
    if not link then return false end
    local parent = ns:GetMoverByKey(link.to)
    if not (parent and parent.target) then return false end

    if side == "CENTER" then
        local dx, dy = computeLinkOffsets(child.target, parent.target, side)
        if not dx then return false end
        link.side, link.dx, link.dy = side, dx, dy
        return true
    end

    gap = tonumber(gap) or tonumber(link.gap) or 0
    link.side, link.gap = side, gap
    -- Which of the two offsets is the edge gap depends on the axis -- see
    -- linkChildCenter. The other one is a centre delta, and zero means centred.
    if side == "LEFT" or side == "RIGHT" then
        link.dx, link.dy = gap, 0
    else
        link.dx, link.dy = 0, gap
    end
    return true
end

function ns:GetMoverLinkGap(key)
    local l = ns:GetMoverLink(key)
    return (l and tonumber(l.gap)) or 0
end

function ns:GetMoverLinkSide(key)
    local l = ns:GetMoverLink(key)
    return (l and l.side and VALID_SIDE[l.side] and l.side) or "CENTER"
end

local function applyLink(child, link)
    -- link may come from an imported profile: tolerate any garbage in it
    if type(link) ~= "table" or type(link.to) ~= "string" then return end
    local parent = ns:GetMoverByKey(link.to)
    if not (parent and parent.target and child.opts and child.opts.db) then return end
    local cx, cy = linkChildCenter(child.target, parent.target, link)
    if not cx then return end
    local r = ns:GetScaleRatio(child.target)
    child.opts.db.x = cx / r
    child.opts.db.y = cy / r
    commitPos(child)
end
MV.applyLink = applyLink

-- After ANY reposition of `mover`: a moved child keeps its link at the new
-- distance, and every child linked to `mover` is dragged along (chains included;
-- `visited` guards against runtime cycles).
-- Move a child onto its own link RIGHT NOW.
--
-- Needed because OnMoverRepositioned does the opposite for the mover it is
-- handed: it re-MEASURES that one's link from wherever it currently sits (see
-- below), then carries its followers. Calling it alone after changing a side
-- therefore overwrote the fresh offsets with the old position -- which is the
-- second half of why picking a side did nothing at all. Apply first, then
-- reposition: measuring a child that already sits on its edge gives the same
-- numbers back, so the pair is safe in that order and only in that order.
function ns:ApplyMoverLink(child)
    local store = linkStore()
    local link  = store and child and child.key and store[child.key]
    if type(link) ~= "table" then return false end
    applyLink(child, link)
    return true
end

-- Move everything docked to this window, WITHOUT re-measuring anything.
--
-- The difference to OnMoverRepositioned matters and cost a broken chat window
-- to learn: that one starts by re-MEASURING the given mover's own link from
-- wherever it currently sits. That is right after a drag -- the user just put it
-- there -- and wrong on a size change, where the frame may be mid-layout and
-- nowhere near its final place. Measuring then writes the transient position
-- into the saved offsets, permanently.
function ns:RepositionMoverChildren(mover, visited)
    local store = linkStore()
    if not (store and mover and mover.key) then return end
    visited = visited or {}
    if visited[mover.key] then return end
    visited[mover.key] = true
    for key, link in pairs(store) do
        if type(link) == "table" and link.to == mover.key and not visited[key] then
            local child = ns:GetMoverByKey(key)
            if child then
                applyLink(child, link)
                ns:RepositionMoverChildren(child, visited)
            end
        end
    end
end

function ns:OnMoverRepositioned(mover, visited)
    local store = linkStore()
    if not (store and mover and mover.key) then return end
    visited = visited or {}
    if visited[mover.key] then return end
    visited[mover.key] = true

    local own = store[mover.key]
    if own then
        local parent = ns:GetMoverByKey(own.to)
        if parent and parent.target then
            local dx, dy = computeLinkOffsets(mover.target, parent.target, own.side or "CENTER")
            if dx then own.dx, own.dy = dx, dy end
        end
    end

    for key, link in pairs(store) do
        if link.to == mover.key and not visited[key] then
            local child = ns:GetMoverByKey(key)
            if child then
                applyLink(child, link)
                ns:OnMoverRepositioned(child, visited)
            end
        end
    end
end

-- login / layout import / reset: apply every link parent-first
function ns:ApplyAllMoverLinks()
    local store = linkStore()
    if not store then return end
    local resolved = {}
    local function resolve(key)
        if resolved[key] then return end
        resolved[key] = true
        local link = store[key]
        if not link then return end
        if store[link.to] then resolve(link.to) end
        local child = ns:GetMoverByKey(key)
        if child then applyLink(child, link) end
    end
    for key in pairs(store) do resolve(key) end
end

-- Discard transaction: snapshot every mover's position state + the whole link
-- table on Edit-Mode open, so a "Discard" restores exactly the opening layout.
function ns:SnapshotEditState()
    local snap = { movers = {}, links = {} }
    for _, m in ipairs(ns._movers) do
        local db = m.key and m.opts and m.opts.db
        if db then
            snap.movers[m.key] = {
                x = db.x, y = db.y, scale = db.scale,
                anchor = db.anchor, anchorEnabled = db.anchorEnabled, moved = db.moved,
            }
        end
    end
    local store = linkStore()
    if store then
        for k, l in pairs(store) do
            if type(l) == "table" then
                snap.links[k] = { to = l.to, side = l.side, dx = l.dx, dy = l.dy }
            end
        end
    end
    snap.sizeLinks = {}
    local sstore = sizeStore()
    if sstore then
        for k, e in pairs(sstore) do
            if type(e) == "table" then snap.sizeLinks[k] = { w = e.w, h = e.h } end
        end
    end
    ns._editSnapshot = snap
end

function ns:ClearEditSnapshot()
    ns._editSnapshot = nil
end

function ns:RestoreEditState()
    local snap = ns._editSnapshot
    if not snap then return end
    local store = linkStore()
    if store then
        wipe(store)
        for k, l in pairs(snap.links) do
            store[k] = { to = l.to, side = l.side, dx = l.dx, dy = l.dy }
        end
    end
    local sstore = sizeStore()
    if sstore then
        wipe(sstore)
        for k, e in pairs(snap.sizeLinks or {}) do sstore[k] = { w = e.w, h = e.h } end
        ns:ApplyAllMoverSizeLinks()
    end
    for _, m in ipairs(ns._movers) do
        local e  = m.key and snap.movers[m.key]
        local db = m.opts and m.opts.db
        if e and db then
            db.x, db.y = e.x, e.y
            db.scale, db.anchor, db.anchorEnabled = e.scale, e.anchor, e.anchorEnabled
            if e.moved ~= nil then db.moved = e.moved end
            pcall(commitPos, m)
        end
    end
    ns:ApplyAllMoverLinks()
end
