-- VuloForeverUI / Core / Mover / Position: edit-state tables, scale/centre math, applyPos/commitPos, mover lookup by key.
-- (Generic mover helper + global edit mode, split across Core/Mover/.)
local _, ns = ...

-- Private to Core/Mover/: helpers and state the files of this folder share.
ns._MV = ns._MV or {}
local MV = ns._MV

ns._movers          = ns._movers or {}
ns._moverEditGlobal = ns._moverEditGlobal or false
ns._moverEditScopes = ns._moverEditScopes or {}

local function moverShouldEdit(mover)
    if ns._moverEditGlobal then return true end
    local sc = mover.opts and mover.opts.scope
    return (sc and ns._moverEditScopes[sc]) and true or false
end
MV.moverShouldEdit = moverShouldEdit

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
MV.applyPos = applyPos

-- Forward: the secure test lives with the drag code much further down, but the
-- gate below is the choke point every write to a target passes through.
-- (MV.isSecureTarget, assigned in Core/Mover/Drag.lua)

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
    if InCombatLockdown() and MV.isSecureTarget and MV.isSecureTarget(mover.target) then
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
MV.commitPos = commitPos

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
