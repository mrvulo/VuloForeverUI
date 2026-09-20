-- VuloForeverUI / Modules / Nameplates / Suppress
--
-- Makes Blizzard's unit frame on a base plate invisible and gives it back.
--
-- The frame is NOT hidden and NOT moved away, and neither is its health bar:
-- Blizzard builds the clickable region from hit-test points on that bar, and a
-- hidden or parked bar stops a mob in a pack from being selected. So the unit
-- frame stays where it is at alpha 0 and keeps its children; only the aura
-- frame is parked, because its icons are mouse-enabled and would trap tooltips
-- over our plate.
--
-- Blizzard's events stay registered. The hidden plate keeps itself current,
-- which is what lets it be handed back in working order (a duel ending, the
-- module switched off) and keeps the class colour we read off its bar right.
--
-- Nothing is written onto Blizzard's frames; the weak tables below hold it.
local _, ns = ...
local NP = ns.NP

local owned     = setmetatable({}, { __mode = "k" })   -- unit frame -> true while suppressed
local hooked    = setmetatable({}, { __mode = "k" })   -- frames and regions that carry our hook
local parked    = setmetatable({}, { __mode = "k" })   -- child frame -> the unit frame it came from

local holder = CreateFrame("Frame")
holder:Hide()

-- These keep working under our plate: quest/encounter widgets and the
-- soft-target icon. They move to the base plate so alpha 0 does not take them.
local KEEP = { WidgetContainer = true, SoftTargetFrame = true }

local function untouchable(frame)
    return frame:IsForbidden() or (frame.IsProtected and frame:IsProtected())
end

local forcing
local function forceAlpha(uf)
    if forcing or not owned[uf] then return end
    forcing = true
    uf:SetAlpha(0)
    forcing = false
end

-- The selection highlight is a region of the HEALTH BAR, not of the unit
-- frame, so its owner is looked up rather than asked for.
local highlightOwner = setmetatable({}, { __mode = "k" })

local function hideAgain(region)
    local uf = highlightOwner[region]
    if uf and owned[uf] then region:Hide() end
end

local function hookOnce(uf)
    if hooked[uf] then return end
    hooked[uf] = true
    hooksecurefunc(uf, "SetAlpha", forceAlpha)
    local sel = uf.selectionHighlight
    if sel and not hooked[sel] then
        hooked[sel] = true
        highlightOwner[sel] = uf
        hooksecurefunc(sel, "Show", hideAgain)
        hooksecurefunc(sel, "SetShown", hideAgain)
    end
end

-- Returns the unit frame it took over; the caller keeps it and hands it to
-- NP.Restore, because by the time a unit is removed the driver may already have
-- released the frame and the base plate no longer leads to it.
function NP.Suppress(nameplate)
    local uf = nameplate and nameplate.UnitFrame
    if not uf or uf:IsForbidden() then return nil end
    owned[uf] = true
    hookOnce(uf)
    -- Unconditional. Whether the unit is attackable was decided by the caller;
    -- asking again here can be wrong on the unit's first frame.
    uf:SetAlpha(0)
    if uf.selectionHighlight then uf.selectionHighlight:Hide() end

    -- Children follow the unit frame's alpha unless they opted out of it.
    -- Blizzard reaches them through parent keys (self.AurasFrame, ...), never
    -- through GetParent, so moving one breaks none of its code.
    for _, child in ipairs({ uf:GetChildren() }) do
        if not untouchable(child) then
            local key = child.GetParentKey and child:GetParentKey()
            if not ns.CanRead(key) then key = nil end   -- a getter on a Blizzard frame
            if key == "AurasFrame" then
                child:SetParent(holder)
                parked[child] = uf
            elseif KEEP[key or ""] then
                child:SetParent(nameplate)
                parked[child] = uf
            elseif child.SetIgnoreParentAlpha then
                pcall(child.SetIgnoreParentAlpha, child, false)
            end
        end
    end
    return uf
end

function NP.Restore(uf)
    if not uf or not owned[uf] then return end
    owned[uf] = nil
    for child, from in pairs(parked) do
        if from == uf then
            child:SetParent(uf)
            parked[child] = nil
        end
    end
    uf:SetAlpha(1)
end

-- The driver attaches the unit frame before NAME_PLATE_UNIT_ADDED reaches us;
-- taking the plate over from here means Blizzard's never shows for a frame.
function NP.InstallDriverHook()
    local driver = NamePlateDriverFrame
    if not (driver and driver.OnNamePlateAdded) then return end
    hooksecurefunc(driver, "OnNamePlateAdded", function(_, unit)
        if NP.mod.active and type(unit) == "string" and unit ~= "preview" then
            NP.Attach(unit)
        end
    end)
end
