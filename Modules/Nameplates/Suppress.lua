-- VuloForeverUI / Modules / Nameplates / Suppress
--
-- Makes Blizzard's unit frame on a base plate invisible and gives it back.
--
-- The frame is NOT hidden and NOT moved away: parked or hidden, clicking a mob
-- in a pack stops selecting it. It stays where it is at alpha 0, its child
-- frames go to a hidden holder, and its events are taken away so it stops
-- working on a plate nobody sees. The driver's next SetUnit on that frame
-- registers everything again, so all of this repeats per unit -- it heals
-- itself and needs no bookkeeping beyond "which frames are ours right now".
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

local function hideAgain(region)
    local uf = region:GetParent()
    if uf and owned[uf] then region:Hide() end
end

local function hookOnce(uf)
    if hooked[uf] then return end
    hooked[uf] = true
    hooksecurefunc(uf, "SetAlpha", forceAlpha)
    local sel = uf.selectionHighlight
    if sel and not hooked[sel] then
        hooked[sel] = true
        hooksecurefunc(sel, "Show", hideAgain)
        hooksecurefunc(sel, "SetShown", hideAgain)
    end
end

-- UnregisterAllEvents is refused on some Blizzard trees ("forbidden aspect
-- EventRegistrations", seen 2026-09-18 on the target frame) -- hence the pcalls.
local KEEP_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_SOFT_FRIEND_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED" }

local function quiet(uf)
    if pcall(uf.UnregisterAllEvents, uf) then
        for _, event in ipairs(KEEP_EVENTS) do pcall(uf.RegisterEvent, uf, event) end
    end
    local cast = uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
    if cast and not untouchable(cast) then pcall(cast.UnregisterAllEvents, cast) end
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

    -- Blizzard reaches its children through parent keys (self.AurasFrame, ...),
    -- never through GetParent, so moving them breaks none of its code. The aura
    -- frame goes too: its items are mouse-enabled and would trap tooltips.
    for _, child in ipairs({ uf:GetChildren() }) do
        if not untouchable(child) then
            local key = child.GetParentKey and child:GetParentKey()
            child:SetParent(KEEP[key or ""] and nameplate or holder)
            parked[child] = uf
        end
    end
    quiet(uf)
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
