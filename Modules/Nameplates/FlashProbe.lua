-- VuloForeverUI / Modules / Nameplates / FlashProbe
--
-- /vfnpflash -- finds what flashes over the target's plate.
--
-- Something now and then draws a large white rectangle over the target plate
-- for a moment, too short to catch with /framestack. While the probe runs it
-- walks, every frame, the whole tree under the target's base plate -- our
-- plate and Blizzard's hidden one alike -- and names in chat each region that
-- is visible and clearly larger than the health bar: its debug name, its
-- texture or atlas, its size and alpha. Each region is named once per run.
--
-- Reads only. Nothing is written onto any frame; a forbidden frame is skipped.
local _, ns = ...
local L = ns.L
local NP = ns.NP

local probe, seen, reported

local function plain(v) return ns.CanRead(v) and type(v) == "number" end

local function describe(region)
    local name = region.GetDebugName and region:GetDebugName() or tostring(region)
    local art
    if region.GetAtlas then
        local ok, atlas = pcall(region.GetAtlas, region)
        if ok and ns.CanRead(atlas) and atlas and atlas ~= "" then art = "atlas " .. atlas end
    end
    if not art and region.GetTexture then
        local ok, tex = pcall(region.GetTexture, region)
        if ok and ns.CanRead(tex) and tex then art = "texture " .. tostring(tex) end
    end
    return name, art or "no texture"
end

local function check(region, minW, minH)
    if seen[region] or region:IsForbidden() then return end
    local okV, visible = pcall(region.IsVisible, region)
    if not (okV and ns.CanRead(visible) and visible) then return end
    local okS, w, h = pcall(region.GetSize, region)
    if not (okS and plain(w) and plain(h)) then return end
    if w < minW and h < minH then return end
    local okA, a = pcall(region.GetAlpha, region)
    if not (okA and plain(a)) or a < 0.3 then return end
    seen[region] = true
    reported = reported + 1
    if reported > 25 then return end
    local name, art = describe(region)
    ns:Print(L["Flash probe: %s -- %s, %dx%d, alpha %.2f"], name, art, w, h, a)
end

local function walk(frame, minW, minH, depth)
    if depth > 8 or frame:IsForbidden() then return end
    check(frame, minW, minH)
    for _, r in ipairs({ frame:GetRegions() }) do
        if r.IsObjectType and r:IsObjectType("Texture") then check(r, minW, minH) end
    end
    for _, child in ipairs({ frame:GetChildren() }) do walk(child, minW, minH, depth + 1) end
end

local function tick()
    local base = C_NamePlate.GetNamePlateForUnit("target")
    if not base or base:IsForbidden() then return end
    local unit = NP.UnitOf(base)
    local plate = unit and NP.plates and NP.plates[unit]
    local hw, hh = 100, 12
    if plate and plate.health then
        local ok, w, h = pcall(plate.health.GetSize, plate.health)
        if ok and plain(w) and plain(h) then hw, hh = w, h end
    end
    walk(base, hw * 1.2, hh * 2.5, 0)
    if plate and plate ~= base then walk(plate, hw * 1.2, hh * 2.5, 0) end
end

ns:RegisterSlash({ key = "NPFLASH", commands = { "/vfnpflash" },
    desc = "Name whatever flashes over the target's nameplate.",
})

ns.Slash.NPFLASH = function()
    if probe and probe:IsShown() then
        probe:Hide()
        ns:Print(L["Flash probe off."])
        return
    end
    probe = probe or CreateFrame("Frame")
    probe:SetScript("OnUpdate", tick)
    seen, reported = {}, 0
    probe:Show()
    ns:Print(L["Flash probe on: target a mob and wait for the flash. /vfnpflash again to stop."])
end
