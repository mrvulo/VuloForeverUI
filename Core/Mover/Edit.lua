-- VuloForeverUI / Core / Mover / Edit: box stacking, drag abort, temp hiding, edit-mode toggle and the boot frame.
local _, ns = ...
local MV = ns._MV
local moverShouldEdit = MV.moverShouldEdit
local retireCoordText = MV.retireCoordText

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
    ns:ApplyMoverFades()
end

function ns:IsMoverEditMode(scope)
    if ns._moverEditGlobal then return true end
    if scope then return ns._moverEditScopes[scope] == true end
    return false
end

function ns:HookBlizzardEditMode()
    -- Intentional no-op: the suite runs its own Edit Mode HUD and does not
    -- follow EditModeManagerFrame; this only reports whether the frame exists.
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
