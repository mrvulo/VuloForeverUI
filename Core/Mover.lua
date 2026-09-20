-- VuloForeverUI / Core / Mover: generic mover helper + global edit mode.
local _, ns = ...

ns._movers          = ns._movers or {}
ns._moverEditGlobal = ns._moverEditGlobal or false
ns._moverEditScopes = ns._moverEditScopes or {}

local function moverShouldEdit(mover)
    if ns._moverEditGlobal then return true end
    local sc = mover.opts and mover.opts.scope
    return (sc and ns._moverEditScopes[sc]) and true or false
end

-- Factor between a frame's LOCAL units (SetPoint offsets, db.x) and UIParent units.
function ns:GetScaleRatio(frame)
    if not (frame and frame.GetEffectiveScale) then return 1 end
    local s = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
    if s == 0 then return 1 end
    return s
end

-- THE formula for anything writing db.x/db.y; plain `fx - px` breaks on scaled frames.
-- Returns nil while the frame has no rect yet (early login).
function ns:GetCenterOffsets(frame)
    if not (frame and frame.GetCenter) then return nil end
    local fx, fy = frame:GetCenter()
    local px, py = UIParent:GetCenter()
    if not (fx and fy and px and py) then return nil end
    local s = ns:GetScaleRatio(frame)
    return fx - px / s, fy - py / s
end

-- db.x/db.y are ALWAYS a CENTER offset, whatever db.anchor is; anchor only re-pins.
-- Named point on a frame, in that frame's own coordinate space.
local function pointXY(frame, point)
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not (l and b and w and h) then return nil end
    local x = point:find("LEFT") and l or (point:find("RIGHT") and (l + w)) or (l + w / 2)
    local y = point:find("BOTTOM") and b or (point:find("TOP") and (b + h)) or (b + h / 2)
    return x, y
end

local function applyPos(mover)
    local opts = mover.opts
    if opts.applyPos then opts.applyPos(); return end
    local target, db = mover.target, opts.db

    if opts.scalable and db.scale then target:SetScale(db.scale) end

    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)

    -- Re-pin to another point WITHOUT moving the frame, so it survives resolution
    -- and UI-scale changes. nil anchorEnabled means "follow db.anchor" (legacy).
    local anchorOn = (db.anchorEnabled ~= false)
    local p = opts.anchorable and anchorOn and db.anchor
    if p and p ~= "CENTER" then
        local fx, fy = pointXY(target, p)
        local ux, uy = pointXY(UIParent, p)
        if fx and ux then
            local r = UIParent:GetEffectiveScale() / (target:GetEffectiveScale() or 1)
            target:ClearAllPoints()
            target:SetPoint(p, UIParent, p, fx - ux * r, fy - uy * r)
        end
    end

    if opts.onMove then opts.onMove(db.x or 0, db.y or 0) end
end

-- Forward: the secure test lives with the drag code much further down, but the
-- gate below is the choke point every write to a target passes through.
local isSecureTarget

-- Movers with their OWN applyPos keep the plain-CENTER drop; they re-apply their
-- custom anchor model from db themselves.
local function writePos(mover)
    local opts = mover.opts
    if opts.applyPos then
        local db = opts.db
        mover.target:ClearAllPoints()
        mover.target:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or 0)
        if opts.onMove then opts.onMove(db.x or 0, db.y or 0) end
    else
        applyPos(mover)
    end
end

-- Everything that repositions a target comes through here: the drop, the link
-- pass, the edit-mode restore and the reset.
--
-- A PROTECTED target may not have its anchors written while the player is in
-- combat. The call is refused -- and the position has already been stored by
-- then, so the saved value and the frame on screen would disagree for the rest
-- of the session. The write waits for the end of combat instead.
--
-- A drag can only START out of combat, but it can END inside it: one pull
-- landing mid-drag is enough. And the link pass runs 0.8 seconds after every
-- loading screen, which a battleground resurrection puts squarely into combat.
-- Keyed by mover, so the same frame queued twice is written once.
local pendingCommit, commitWatcher

local function commitPos(mover)
    if InCombatLockdown() and isSecureTarget and isSecureTarget(mover.target) then
        pendingCommit = pendingCommit or {}
        pendingCommit[mover] = true
        if not commitWatcher then
            commitWatcher = CreateFrame("Frame")
            commitWatcher:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                local list = pendingCommit
                pendingCommit = nil
                for m in pairs(list or {}) do writePos(m) end
            end)
        end
        commitWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    writePos(mover)
end

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

-- Declared alongside linkStore because the edit-mode snapshot below reads both.
local function sizeStore()
    local p = ns.db and ns.db.profile
    if not p then return nil end
    p.moverSizeLinks = p.moverSizeLinks or {}
    return p.moverSizeLinks
end

-- Kept alongside ns._movers, which stays the ordered list everything iterates.
-- This lookup used to be a linear scan, and the Edit Mode link overlay calls it
-- once per mover, 33 times a second -- quadratic in the number of windows while
-- the editor is open, which is exactly when the frame budget is tightest.
ns._moversByKey = ns._moversByKey or {}

-- Which module a mover belongs to, for "open this element's settings" from the
-- edit panel. Nothing is declared per mover: the answer is read off the
-- position table the mover writes into, which is the module's db or a table
-- one or two levels inside it (mod.db.chrome[c.key], mod.db.bars.main). A
-- caller may still say so outright with opts.module. Not cached: a profile
-- switch re-points mod.db, and the lookup is a handful of table compares on a
-- click.
function ns:ModuleForMover(mover)
    if not (mover and mover.opts) then return nil end
    if mover.opts.module and ns.modules[mover.opts.module] then return mover.opts.module end
    local db = mover.opts.db
    if type(db) ~= "table" then return nil end
    for _, key in ipairs(ns.moduleOrder) do
        local mdb = ns.modules[key] and ns.modules[key].db
        if type(mdb) == "table" then
            if rawequal(mdb, db) then return key end
            for _, v in pairs(mdb) do
                if rawequal(v, db) then return key end
                if type(v) == "table" then
                    for _, v2 in pairs(v) do
                        if rawequal(v2, db) then return key end
                    end
                end
            end
        end
    end
    return nil
end

function ns:GetMoverByKey(key)
    if not key then return nil end
    return ns._moversByKey[key]
end

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
-- Put every window we own back where we say it belongs.
--
-- For when something OUTSIDE re-anchors frames wholesale. Blizzard's Edit Mode
-- does exactly that: selecting its active layout re-applies that layout's anchor
-- to every system in it, and Modules/UnlockMode.lua has to select a layout
-- before the library will let it write anything.
--
-- Roots first, then followers. A docked window is placed FROM its target, so the
-- target has to be back in place before anyone is asked to follow it.
function ns:ReapplyAllMovers()
    local store = linkStore() or {}
    for _, m in ipairs(ns._movers or {}) do
        if not (m.key and store[m.key]) then pcall(applyPos, m) end
    end
    for _, m in ipairs(ns._movers or {}) do
        if m.key and not store[m.key] then ns:RepositionMoverChildren(m) end
    end
end

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

-- Layout snapshot: key -> {x,y,scale,anchor}. Movers with a custom opts.applyPos
-- opt out — a flat x/y snapshot cannot represent their richer position model.
function ns:CaptureLayout()
    local snap = {}
    for _, mover in ipairs(ns._movers) do
        local k  = mover.key
        local o  = mover.opts
        local db = o and o.db
        if k and db and not o.applyPos then
            local e = { x = db.x or 0, y = db.y or 0 }
            if o.scalable  and db.scale  then e.scale  = db.scale  end
            if o.anchorable and db.anchor then e.anchor = db.anchor end
            snap[k] = e
        end
    end
    return snap
end

-- Returns how many movers were moved; movers absent from the snapshot are untouched.
function ns:ApplyLayout(snap)
    if type(snap) ~= "table" then return 0 end
    local n = 0
    for _, mover in ipairs(ns._movers) do
        local o  = mover.opts
        local k  = mover.key
        local e  = k and snap[k]
        local db = o and o.db
        if e and db and not o.applyPos then
            db.x, db.y = tonumber(e.x) or 0, tonumber(e.y) or 0
            if o.scalable   then db.scale  = tonumber(e.scale) or db.scale end
            if o.anchorable then db.anchor = e.anchor or db.anchor end
            pcall(applyPos, mover)
            n = n + 1
        end
    end
    ns:ApplyAllMoverLinks()
    -- On the Edit-Mode client (TBC) the Blizzard follow link is a static snapshot,
    -- so moving the anchor alone doesn't move the frame; re-establish the links.
    if ns.PrepareBlizzMovers then ns:PrepareBlizzMovers() end
    return n
end

-- Export format: VFUI1!<name>!key=x,y[,s<scale>][,a<anchor>];...!<checksum>
local function esc(s)
    return (tostring(s):gsub("[%%;=,!\n\r]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end
local function unesc(s)
    return (tostring(s):gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end
local function checksum(s)
    local sum = 0
    for i = 1, #s do sum = (sum * 31 + string.byte(s, i)) % 1000000007 end
    return string.format("%X", sum)
end

function ns:SerializeLayout(name, snap)
    local parts = {}
    for k, e in pairs(snap or {}) do
        -- Two decimals, not whole units: positions are pixel-snapped now and
        -- rounding to integers here would undo that on every export/import.
        local s = esc(k) .. "=" .. string.format("%.2f", tonumber(e.x) or 0)
                          .. "," .. string.format("%.2f", tonumber(e.y) or 0)
        if e.scale  then s = s .. ",s" .. string.format("%.4g", e.scale) end
        if e.anchor then s = s .. ",a" .. esc(e.anchor) end
        parts[#parts + 1] = s
    end
    table.sort(parts)
    local payload = esc(name or "") .. "!" .. table.concat(parts, ";")
    return "VFUI1!" .. payload .. "!" .. checksum(payload)
end

-- Returns name, snap on success; nil, errorKey on failure.
function ns:DeserializeLayout(str)
    if type(str) ~= "string" then return nil, "empty" end
    str = str:gsub("^%s+", ""):gsub("%s+$", "")
    if str == "" then return nil, "empty" end
    local payload, sum = str:match("^VFUI1!(.*)!(%x+)$")
    if not payload then return nil, "format" end
    if checksum(payload) ~= sum then return nil, "checksum" end
    local namePart, body = payload:match("^(.-)!(.*)$")
    if not namePart then return nil, "format" end
    local snap = {}
    if body ~= "" then
        for entry in body:gmatch("[^;]+") do
            local k, vals = entry:match("^(.-)=(.+)$")
            if k then
                local e = {}
                for tok in vals:gmatch("[^,]+") do
                    local p = tok:sub(1, 1)
                    if     p == "s" then e.scale  = tonumber(tok:sub(2))
                    elseif p == "a" then e.anchor = unesc(tok:sub(2))
                    elseif not e.x  then e.x = tonumber(tok)
                    elseif not e.y  then e.y = tonumber(tok) end
                end
                if e.x and e.y then snap[unesc(k)] = e end
            end
        end
    end
    return unesc(namePart), snap
end

-- Cursor in UIParent units (GetCursorPosition reports raw screen pixels).
local function cursorUI()
    local cx, cy = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if not (cx and cy and s and s > 0) then return nil end
    return cx / s, cy / s
end

-- Live coordinate readout on the box itself. The side panel shows X/Y too,
-- but only for the SELECTED window and only while the panel is open; during a
-- drag or an arrow-key nudge the eyes are on the box, so the numbers belong
-- there. Created lazily, shown while dragging/nudging, hidden on drop/leave.
local function updateCoordText(mover)
    local fs = mover.coord
    if not fs then
        fs = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", mover, "TOPLEFT", 4, -3)
        fs:SetTextColor(1, 1, 1, 0.9)
        mover.coord = fs
    end
    local x, y = ns:GetCenterOffsets(mover.target)
    if x then
        fs:SetFormattedText("%d, %d", math.floor(x + 0.5), math.floor(y + 0.5))
        fs:Show()
    end
end
ns.UpdateMoverCoord = updateCoordText

-- With "Show coordinates" on, the readout is not a drag artefact: it stays on
-- the box for the whole editing session, so it refreshes here instead of
-- hiding. Off, a drop or leaving the box retires it, the way it always did.
local function retireCoordText(mover)
    if not (mover and mover.coord) then return end
    local g = ns.EditState and ns.EditState()
    if g and g.coords and ns.IsEditModeActive and ns:IsEditModeActive() then
        updateCoordText(mover)
    else
        mover.coord:Hide()
    end
end

-- Manual drag tick. Shift locks to the dominant axis: the direction is decided
-- once, after 3px of travel, and releasing Shift frees it again mid-drag.
local AXIS_LOCK_THRESHOLD = 3

-- Secure frames must not have their anchors written from insecure Lua: the
-- taint spreads from the header to the action buttons it drives, and Blizzard's
-- own UpdateShownButtons then gets blocked. Those frames keep the engine's own
-- drag, which costs us the axis lock.
--
-- To be exact about what that does and does not buy, because the older wording
-- here claimed too much: it keeps the whole DRAG out of Lua's hands. The DROP
-- still writes the anchor once, through commitPos -- there is no other way to
-- put a frame where the player let go and have it stay there across a reload.
-- What commitPos does guarantee is that the write never happens under combat
-- lockdown, where it would be refused outright.
isSecureTarget = function(target)
    if not target then return false end
    if target.IsProtected then
        local ok, prot = pcall(target.IsProtected, target)
        if ok and prot then return true end
    end
    -- addon-made secure headers report unprotected out of combat, but they carry
    -- secure attributes; a state driver attribute is the reliable tell
    if target.GetAttribute then
        local ok, v = pcall(target.GetAttribute, target, "_onstate-userDisplay")
        if ok and v then return true end
        ok, v = pcall(target.GetAttribute, target, "_onstate-page")
        if ok and v then return true end
    end
    return false
end
ns.IsSecureMoverTarget = isSecureTarget

local function dragUpdate(mover)
    local d = mover._drag
    local target = mover.target
    if not (d and target) then return end
    -- the engine is moving it for us; this tick only keeps the readout fresh
    if d.engineMove then updateCoordText(mover); return end
    local ux, uy = cursorUI()
    if not ux then return end
    local r = ns:GetScaleRatio(target)
    if r == 0 then r = 1 end
    local mdx, mdy = ux - d.ux, uy - d.uy      -- UIParent units
    local nx, ny = d.sx + mdx / r, d.sy + mdy / r
    if IsShiftKeyDown() then
        -- Measure from where Shift went down, not from where the drag began, or
        -- re-pressing it mid-drag locks whichever axis has the most travel so far
        -- rather than the one currently being moved along.
        if not d.shiftX then d.shiftX, d.shiftY = ux, uy end
        if not d.axis then
            local sdx, sdy = math.abs(ux - d.shiftX), math.abs(uy - d.shiftY)
            if sdx > AXIS_LOCK_THRESHOLD or sdy > AXIS_LOCK_THRESHOLD then
                d.axis = (sdx >= sdy) and "X" or "Y"
                d.lockX, d.lockY = nx, ny   -- freeze the off-axis where it is now
            end
        end
        if     d.axis == "X" then ny = d.lockY
        elseif d.axis == "Y" then nx = d.lockX end
    else
        d.axis, d.shiftX, d.shiftY = nil, nil, nil
    end
    target:ClearAllPoints()
    target:SetPoint("CENTER", UIParent, "CENTER", nx, ny)
    updateCoordText(mover)
end

-- The box IS the window: while it is being edited the mover covers the target
-- exactly (it is a child of the target, same coordinate space, so SetAllPoints
-- tracks size and scale for free) -- what you see is what you grab. Only two
-- cases keep the legacy centred handle: a target without a usable rect yet
-- (bare anchors, frames still waiting for their layout pass), and a box shown
-- OUTSIDE edit mode -- by free-move or a module's own unlock button. Covering
-- there would bury the very thing being adjusted: unlocked cooldown bars are
-- drop targets for spells, unlocked unit frames render a test preview, and a
-- covering box would swallow the drop and hide the preview alike. opts.fill
-- forces cover in every state (those movers relied on it before and their
-- targets are pure overlays anyway).
local function applyMoverGeometry(mover)
    local t = mover.target
    if not t then return end
    local editing = moverShouldEdit(mover) or mover.opts.fill
    local w = (t.GetWidth and t:GetWidth()) or 0
    local h = (t.GetHeight and t:GetHeight()) or 0
    local cover = editing and w >= 16 and h >= 10
    if cover then
        if mover._covering ~= true then
            mover._covering = true
            mover:ClearAllPoints()
            mover:SetAllPoints(t)
        end
    elseif mover._covering ~= false then
        mover._covering = false
        mover:ClearAllPoints()
        mover:SetPoint("CENTER", t, "CENTER", 0, 0)
        mover:SetSize(mover.opts.width or 200, mover.opts.height or 40)
    end
end

function ns:RefreshMoverGeometry(mover)
    if mover then applyMoverGeometry(mover) end
end

function ns:CreateMover(target, opts)
    opts = opts or {}
    local db = opts.db
    assert(db, "ns:CreateMover needs opts.db")
    assert(target, "ns:CreateMover needs target")

    target:SetMovable(true)
    target:SetClampedToScreen(false)

    local mover = CreateFrame("Frame", nil, target)
    mover.target = target
    mover.opts   = opts
    -- Stable identity for layouts; unkeyed movers are simply not captured.
    mover.key    = opts.key or (target.GetName and target:GetName()) or nil
    applyMoverGeometry(mover)
    mover:SetFrameStrata("HIGH")
    mover:EnableMouse(true)
    mover:Hide()

    mover.bg = mover:CreateTexture(nil, "BACKGROUND")
    mover.bg:SetAllPoints(mover)
    mover.bg:SetColorTexture(0.05, 0.07, 0.10, 0.92)

    mover.border = CreateFrame("Frame", nil, mover,
        BackdropTemplateMixin and "BackdropTemplate")
    mover.border:SetAllPoints(mover)
    if mover.border.SetBackdrop then
        mover.border:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        mover.border:SetBackdropBorderColor(0.75, 0.35, 1, 0.8)
    end

    if opts.label then
        -- Centred, one line, truncating: pinned to both edges so a long name
        -- ellipsizes inside a narrow bar instead of spilling past the box.
        mover.label = mover:CreateFontString(nil, "OVERLAY")
        if ns.UI and ns.UI.Font then
            ns.UI.Font(mover.label, 11)
        else
            mover.label:SetFontObject("GameFontNormal")
        end
        if opts.label:find("\n", 1, true) then
            -- deliberate two-line labels (name + drag hint) keep their wrap;
            -- truncation is for the single-line case only
            mover.label:SetPoint("CENTER", mover, "CENTER", 0, 0)
        else
            mover.label:SetPoint("LEFT", mover, "LEFT", 6, 0)
            mover.label:SetPoint("RIGHT", mover, "RIGHT", -6, 0)
            mover.label:SetWordWrap(false)
        end
        mover.label:SetJustifyH("CENTER")
        mover.label:SetTextColor(1, 1, 1, 0.85)
        mover.label:SetText(opts.label)
    end

    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function()
        -- Picking an anchor target: a click must not turn into a drag.
        if ns.IsAnchorPicking and ns:IsAnchorPicking() then return end
        mover._shiftSelectPending = nil   -- this is a drag, not an additive click
        -- Free-move boxes stay live outside edit mode, so a protected target
        -- could otherwise be repositioned from Lua every frame while in combat.
        if InCombatLockdown() and target.IsProtected and target:IsProtected() then
            if ns.Print then
                ns:Print((ns.L and ns.L["Not possible in combat."]) or "Not possible in combat.")
            end
            return
        end
        local ux, uy = cursorUI()
        local sx, sy = ns:GetCenterOffsets(target)
        if not (ux and sx) then return end
        ns._draggingMover = mover
        if ns.BeginGroupDrag then ns:BeginGroupDrag(mover) end
        -- Driven by hand rather than StartMoving, because the engine's drag
        -- cannot be constrained to an axis. Secure frames are the exception:
        -- writing their anchor from Lua taints them, so those keep StartMoving.
        local engineMove = isSecureTarget(target)
        mover._drag = { ux = ux, uy = uy, sx = sx, sy = sy, engineMove = engineMove }
        if engineMove then
            target:StartMoving()
        end
        -- Always ticking: for engine-driven frames the tick only feeds the
        -- coordinate readout, the position is the engine's business.
        mover:SetScript("OnUpdate", dragUpdate)
    end)
    mover:SetScript("OnDragStop", function()
        mover:SetScript("OnUpdate", nil)
        retireCoordText(mover)
        if mover._drag and mover._drag.engineMove then
            pcall(target.StopMovingOrSizing, target)
        end
        mover._drag = nil
        ns._draggingMover = nil
        local x, y = ns:GetCenterOffsets(target)
        if x and y then
            local rawx, rawy = x, y
            -- Magnetism / grid snap from UI/EditMode.lua; no-op until it is loaded.
            if ns.EditResolveDrop and ns:IsEditModeActive() then
                x, y = ns:EditResolveDrop(mover, x, y)
            elseif ns.EditSnapXY then
                x, y = ns:EditSnapXY(x, y, ns:GetScaleRatio(target))
            end
            -- opts.db, not the creation-time upvalue: a target may re-point its
            -- table later (pooled windows re-bound after a close, profile switch).
            local db = opts.db
            db.x, db.y = x, y
            commitPos(mover)
            -- shift followers by the leader's snap delta so the group stays rigid
            if ns.EndGroupDrag then ns:EndGroupDrag(x - rawx, y - rawy) end
            ns:OnMoverRepositioned(mover)
            if ns.OnMoverMoved then ns:OnMoverMoved(mover) end
        elseif ns.EndGroupDrag then
            ns:EndGroupDrag(0, 0)
        end
    end)

    mover:SetScript("OnMouseUp", function(self, button)
        if ns.IsAnchorPicking and ns:IsAnchorPicking() then
            -- right-click aborts the pick; left-click on a target is handled on mouse-down
            if button == "RightButton" and ns.CancelAnchorPick then ns:CancelAnchorPick() end
            return
        end
        if button == "RightButton" then
            if IsShiftKeyDown() then
                ns:SetMoverTempHidden(self, true)
            elseif ns.SelectMover then
                ns:SelectMover(self, false)
            end
        elseif button == "LeftButton" and self._shiftSelectPending then
            -- a plain Shift+click, not a Shift+drag: now do the additive toggle
            self._shiftSelectPending = nil
            if ns.SelectMover then ns:SelectMover(self, true) end
        end
    end)

    -- Hover picks the single mover the arrow keys nudge (many are visible at once).
    -- Clearing on leave matters: a stale value keeps nudging - and keeps drawing
    -- the anchor line of - a box the cursor left long ago.
    mover:SetScript("OnEnter", function(self) ns._activeMover = self end)
    mover:SetScript("OnLeave", function(self)
        if ns._activeMover == self then ns._activeMover = nil end
        -- a nudge readout has no drop event; leaving the box retires it
        if not self._drag then retireCoordText(self) end
    end)

    -- SetPropagateKeyboardInput ist eine geschuetzte Funktion: ruft ein Addon
    -- sie im Kampf auf, blockiert Blizzard den Aufruf (ADDON_ACTION_BLOCKED).
    -- Deshalb bleibt die Tastatur aus, bis der Mover sichtbar wird - und das
    -- ist er nur beim Verschieben. EnableKeyboard und das Durchreichen immer
    -- gemeinsam setzen, sonst schluckt der Frame auch Bewegungstasten.
    mover:EnableKeyboard(false)
    mover:HookScript("OnShow", function(self)
        -- the target may have gotten its real rect since the box last showed
        applyMoverGeometry(self)
        if InCombatLockdown and InCombatLockdown() then return end
        self:EnableKeyboard(true)
        self:SetPropagateKeyboardInput(true)
    end)
    mover:HookScript("OnHide", function(self)
        self:EnableKeyboard(false)
    end)

    mover:SetScript("OnKeyDown", function(self, key)
        -- Der Kampf kann waehrend des Verschiebens beginnen.
        if InCombatLockdown and InCombatLockdown() then return end
        local db = opts.db   -- fresh, see OnDragStop
        if not (moverShouldEdit(self) or db.unlocked or db.freeMove) or ns._activeMover ~= self then
            self:SetPropagateKeyboardInput(true)
            return
        end
        -- one physical screen pixel, in the units db.x is stored in; the module
        -- hints all say "SHIFT = 5px", which this now makes literally true
        local step = ns:Pixel(target, 1)
        if IsShiftKeyDown() then step = step * 5 end
        local dx, dy = 0, 0
        if     key == "UP"    then dy =  step
        elseif key == "DOWN"  then dy = -step
        elseif key == "LEFT"  then dx = -step
        elseif key == "RIGHT" then dx =  step
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        db.x = (db.x or 0) + dx
        db.y = (db.y or 0) + dy
        applyPos(self)
        if ns.NudgeGroupFollowers then ns:NudgeGroupFollowers(self, dx, dy) end
        ns:OnMoverRepositioned(self)
        if ns.OnMoverMoved then ns:OnMoverMoved(self) end
        updateCoordText(self)
    end)

    mover:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        if ns.IsAnchorPicking and ns:IsAnchorPicking() then
            if ns.AnchorPickPick then ns:AnchorPickPick(self) end
            return
        end
        -- Shift also arms the drag axis lock, so the additive toggle waits for
        -- mouse-up: toggling here would drop this box out of the selection the
        -- instant a Shift-drag of the group began.
        if IsShiftKeyDown() then
            self._shiftSelectPending = true
        elseif ns.SelectMover then
            ns:SelectMover(self, false)
        end
    end)

    -- Re-derive a docked position on RESIZE, not only on a move.
    --
    -- A docked window's centre depends on its own size and on its target's: the
    -- stored offset is edge-to-edge, so the centre has to be recomputed whenever
    -- either box changes shape. Until now that only happened when some caller
    -- remembered to ask, and one of them asked for the wrong thing --
    -- Modules/ActionBars.lua resizes its chrome holders and calls ApplyMover,
    -- which re-applied the stored CENTRE. Keeping the centre while the size
    -- changes moves both edges, so the bar slid off the window it was docked to.
    --
    -- The reference addon hooks OnSizeChanged on every registered frame for
    -- exactly this reason ("when the child resizes, the near edge stays fixed
    -- relative to the target"). Same idea here.
    target:HookScript("OnSizeChanged", function()
        -- a handle box waiting for the target's rect flips to full cover here
        if mover:IsShown() and not mover._covering then applyMoverGeometry(mover) end
        if mover._sizeSync or not mover.key then return end
        -- Writing a protected frame's anchor while locked down is not ours to do.
        if InCombatLockdown() and isSecureTarget(target) then return end
        local store = linkStore()
        if not store then return end

        -- ONLY the window that resized, and only if it is itself docked.
        --
        -- The first version also cascaded to everything docked to it. That went
        -- wrong: the chat resizes constantly, so every message re-drove two bars
        -- and a pet bar through a full re-place, and the measured link dump came
        -- back with "abchrome_bags -> abchrome_micro RIGHT -471.76" -- an edge
        -- gap of minus half a screen, written while a holder was still at its
        -- placeholder size. A parent that MOVES already carries its followers
        -- through OnMoverRepositioned; a parent that merely changes size does
        -- not need to drag them anywhere.
        local own = store[mover.key]
        if not own then return end

        mover._sizeSync = true
        -- Strictly re-APPLY. Nothing in this path may measure: a size change can
        -- land mid-layout, with the frame nowhere near its final place, and
        -- measuring then would write that transient position into the saved
        -- offsets for good.
        applyLink(mover, own)
        mover._sizeSync = nil
    end)

    ns._movers[#ns._movers + 1] = mover
    if mover.key then ns._moversByKey[mover.key] = mover end

    -- Restore free-move here too: lazily built movers miss the one-shot login pass.
    if db.freeMove then
        mover:Show()
        if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    end

    -- Built while edit mode is already open: show it and re-rank the stack, or
    -- it would sit at a default level and swallow the boxes underneath it.
    if moverShouldEdit(mover) then
        mover:Show()
        if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
    end
    ns:SortMoverLevels()

    -- A mover built after the login link pass must still honour its saved link,
    -- and pull in any child already waiting on it. Deferred so the frame has a
    -- rect (screenCenter needs one) before the offsets are computed.
    if mover.key and ns._movers and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local store = linkStore()
            if not store then return end
            local own = store[mover.key]
            if own then applyLink(mover, own) end
            for k, link in pairs(store) do
                if type(link) == "table" and link.to == mover.key then
                    local child = ns:GetMoverByKey(k)
                    if child then applyLink(child, link) end
                end
            end
        end)
    end

    return mover
end

-- Stack the boxes by area, largest at the bottom, so a small mover sitting
-- inside a big one always stays clickable instead of being swallowed by it.
function ns:SortMoverLevels()
    local list = {}
    for _, m in ipairs(ns._movers) do
        if m:IsShown() then
            local w = (m:GetWidth() or 0) * (m:GetHeight() or 0)
            list[#list + 1] = { m = m, area = w }
        end
    end
    table.sort(list, function(a, b) return a.area > b.area end)
    -- Absolute levels only. Every mover sits in the HIGH strata, which detaches
    -- it from its parent's ordering, so folding the parent's level back in here
    -- would scramble the ranking with an unrelated number.
    for i, e in ipairs(list) do
        pcall(e.m.SetFrameLevel, e.m, 20 + i)
    end
end

-- A hidden frame never receives OnDragStop, so any path that hides a mover has
-- to end the drag itself or the target stays welded to the cursor.
function ns:AbortMoverDrag(mover)
    mover = mover or ns._draggingMover
    if not mover then return end
    mover:SetScript("OnUpdate", nil)
    mover._drag = nil
    -- an aborted drag has no drop event; a free-move box stays shown and
    -- would otherwise keep the stale readout
    retireCoordText(mover)
    if mover.target and mover.target.StopMovingOrSizing then
        pcall(mover.target.StopMovingOrSizing, mover.target)
    end
    if ns._draggingMover == mover then ns._draggingMover = nil end
    ns._groupDrag = nil
    if ns._hideGuides then ns._hideGuides() end
end

-- Session-only: Shift+RightClick parks a box that is in the way. Cleared every
-- time edit mode opens, so it can never strand a window as unreachable.
function ns:SetMoverTempHidden(mover, on)
    if not mover then return end
    mover._tempHidden = on and true or false
    if on then
        if ns._draggingMover == mover then ns:AbortMoverDrag(mover) end
        mover:Hide()
    elseif moverShouldEdit(mover) or (mover.opts.db and mover.opts.db.freeMove) then
        mover:Show()
    end
    ns:SortMoverLevels()
end

function ns:ClearMoverTempHidden()
    for _, m in ipairs(ns._movers) do m._tempHidden = nil end
end

-- scope nil -> global edit (every window); scope given -> just that module's.
function ns:SetMoversEditMode(state, scope)
    state = state and true or false
    if scope then
        if (ns._moverEditScopes[scope] or false) == state then return end
        ns._moverEditScopes[scope] = state or nil
    else
        if ns._moverEditGlobal == state then return end
        ns._moverEditGlobal = state
        if not state then wipe(ns._moverEditScopes) end
    end
    -- entering edit mode un-parks anything hidden in an earlier session
    if state then ns:ClearMoverTempHidden() end
    for _, mover in ipairs(ns._movers) do
        local opts = mover.opts
        local edit = moverShouldEdit(mover)
        if opts.editPreview then pcall(opts.editPreview, edit) end
        if edit and not mover._tempHidden then
            mover:Show()
        elseif not (opts.db and (opts.db.unlocked or opts.db.freeMove)) then
            mover:Hide()
        end
    end
    ns:SortMoverLevels()
    if ns.RefreshMoverStyles then ns:RefreshMoverStyles() end
end

function ns:IsMoverEditMode(scope)
    if ns._moverEditGlobal then return true end
    if scope then return ns._moverEditScopes[scope] == true end
    return false
end

function ns:HookBlizzardEditMode()
    -- Intentional no-op: on TBC, applying a change briefly opens/closes
    -- EditModeManagerFrame, so hooking its OnShow would create a feedback loop.
    return _G.EditModeManagerFrame ~= nil
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "PLAYER_ENTERING_WORLD" then
        -- after every module applied its own saved position; links win last.
        -- Sizes first: edge-anchored links measure against the final extents.
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                ns:ApplyAllMoverSizeLinks()
                ns:ApplyAllMoverLinks()
            end)
        else
            ns:ApplyAllMoverSizeLinks()
            ns:ApplyAllMoverLinks()
        end
        return
    end
    if evt == "ADDON_LOADED" and name ~= "Blizzard_EditMode" then return end
    ns:HookBlizzardEditMode()
end)
