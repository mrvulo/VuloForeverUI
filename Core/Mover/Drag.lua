-- VuloForeverUI / Core / Mover / Drag: coordinate readout, secure test, drag tick, box geometry and ns:CreateMover.
local _, ns = ...
local MV = ns._MV
local moverShouldEdit = MV.moverShouldEdit
local applyPos        = MV.applyPos
local commitPos       = MV.commitPos
local linkStore       = MV.linkStore
local applyLink       = MV.applyLink

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
MV.retireCoordText = retireCoordText

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
local isSecureTarget = function(target)
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
MV.isSecureTarget = isSecureTarget

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
            -- Magnetism / grid snap from UI/EditMode/; no-op until it is loaded.
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
