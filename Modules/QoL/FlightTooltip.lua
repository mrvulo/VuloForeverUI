-- VuloForeverUI / Modules / QoL / FlightTooltip
--
-- The flight map's tooltip names how long the ride to that stop takes: the
-- time measured the last time you flew it, until then the one computed from
-- the client's flight paths (Flight.RouteTime decides, the same order the
-- flight bar trusts).
--
-- The client has two flight maps -- the classic taxi window and the canvas
-- flight map (load on demand) -- and both build their tooltip in a function
-- of their own. Each is post-hooked: the client's lines stay as they are,
-- ours goes under them, and nothing of theirs is replaced.
local _, ns = ...
local L = ns.L

local QoL = ns.QoL
local Flight = QoL.Flight

local function addTime(slot)
    if type(slot) ~= "number" or not QoL.mod.active then return end
    if not QoL.db().flight.mapTooltip then return end
    if not (TaxiNodeGetType and TaxiNodeGetType(slot) == "REACHABLE") then return end
    local seconds, how = Flight.RouteTime(slot)
    if not seconds then return end
    local text = Flight.Clock(seconds)
    if how == "estimate" then text = "~" .. text end
    -- the flown time in white, a computed or guessed one a shade quieter
    local v = (how == "learned") and 1 or 0.75
    GameTooltip:AddDoubleLine(L["Flight time"], text, 1, 0.82, 0, v, v, v)
    GameTooltip:Show()
end

-- Hooks cannot be taken off again; with the setting off they do nothing.
local taxiHooked, mapHooked

local function hookFlightMap()
    local mixin = _G.FlightMap_FlightPointPinMixin
    if mapHooked or not mixin then return end
    mapHooked = true
    hooksecurefunc(mixin, "OnMouseEnter", function(pin)
        local data = pin and pin.taxiNodeData
        if data then addTime(data.slotIndex) end
    end)
end

-- The canvas flight map loads when it is first opened.
local function onAddOnLoaded(_, name)
    if name ~= "Blizzard_FlightMap" then return end
    hookFlightMap()
    if mapHooked then ns:UnregisterEvent("ADDON_LOADED", onAddOnLoaded) end
end

function Flight.ApplyTooltip()
    if not QoL.db().flight.mapTooltip then return end
    if not taxiHooked and _G.TaxiNodeOnButtonEnter then
        taxiHooked = true
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            if button and button.GetID then addTime(button:GetID()) end
        end)
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_FlightMap") then hookFlightMap() end
    if not mapHooked then ns:RegisterEvent("ADDON_LOADED", onAddOnLoaded) end
end
