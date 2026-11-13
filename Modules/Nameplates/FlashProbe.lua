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

-- ---------------------------------------------------------------------------
-- /vfnpsnap -- everything that is DRAWN on the nameplates, right now.
--
-- For a fault that stays on screen (a white rectangle around the bar, icons
-- spread apart) instead of flashing by: one pass over every base plate, the
-- target's first, and one line per visible frame and texture with what it
-- shows -- its place on screen, size, scale, alpha, texture, tint and blend
-- mode. The lines go into the diagnostics log, not into the chat.
--
-- Reads only, every getter guarded: a value that is secret is written as "?".
-- ---------------------------------------------------------------------------
local SNAP_LINES = 560

local function get(obj, method, ...)
    local f = obj[method]
    if not f then return nil end
    local ok, a, b, c, d = pcall(f, obj, ...)
    if not ok then return nil end
    return a, b, c, d
end

local function num(v)
    if ns.CanRead(v) and type(v) == "number" then return v end
    return nil
end

local function str(v)
    if ns.CanRead(v) and (type(v) == "string" or type(v) == "number") then return tostring(v) end
    return nil
end

local function f2(v)
    local n = num(v)
    return n and ("%.2f"):format(n) or "?"
end

-- Our own frames have no names; the keys they hang under on the plate do.
local function labelsOf(plate)
    local t = {}
    local function take(tbl, prefix)
        for k, v in pairs(tbl) do
            if type(k) == "string" and type(v) == "table" and v.GetObjectType and not t[v] then
                t[v] = prefix .. k
            end
        end
    end
    take(plate, "")
    for _, key in ipairs({ "auras", "executeHalo", "glowEdges", "icons", "texts", "border" }) do
        local sub = plate[key]
        if type(sub) == "table" and not sub.GetObjectType then take(sub, key .. ".") end
    end
    return t
end

local function describeRegion(region, depth, kind, labels)
    local visible = get(region, "IsVisible")
    if not (ns.CanRead(visible) and visible == true) then return nil end
    local ea = num(get(region, "GetEffectiveAlpha"))
    if ea and ea < 0.02 then return false end       -- drawn by nobody; children may differ
    local name = labels[region] or str(get(region, "GetDebugName")) or "?"
    if #name > 70 then name = ".." .. name:sub(-68) end
    local l, b, w, h = get(region, "GetScaledRect")
    local parts = { ("%s%s %s"):format(("  "):rep(depth), kind, name) }
    if num(l) and num(b) and num(w) and num(h) then
        parts[#parts + 1] = ("@%d,%d %dx%d"):format(l, b, w, h)
    else
        parts[#parts + 1] = "@?"
    end
    parts[#parts + 1] = "a" .. f2(get(region, "GetAlpha")) .. "/" .. f2(ea)
    if kind == "F" then
        parts[#parts + 1] = "s" .. f2(get(region, "GetScale")) .. "/" .. f2(get(region, "GetEffectiveScale"))
        parts[#parts + 1] = str(get(region, "GetObjectType")) or "?"
    else
        local art = str(get(region, "GetAtlas"))
        if art and art ~= "" then art = "atlas " .. art
        else art = str(get(region, "GetTexture")); art = art and ("tex " .. art) or "no texture" end
        parts[#parts + 1] = art
        local r, g, bl, a = get(region, "GetVertexColor")
        parts[#parts + 1] = ("vc %s,%s,%s,%s"):format(f2(r), f2(g), f2(bl), f2(a))
        parts[#parts + 1] = str(get(region, "GetBlendMode")) or "?"
        parts[#parts + 1] = str(get(region, "GetDrawLayer")) or "?"
    end
    return table.concat(parts, " ")
end

local function snapWalk(frame, depth, labels, out)
    if depth > 12 or #out >= SNAP_LINES then return end
    if frame:IsForbidden() then return end
    local line = describeRegion(frame, depth, "F", labels)
    if line == nil then return end                  -- hidden: so is everything under it
    if line then out[#out + 1] = line end
    -- a texture has no effective alpha of its own to ask for: under a frame
    -- nobody sees it is not drawn either, unless it ignores the parent's alpha
    local unseen = line == false
    for _, r in ipairs({ frame:GetRegions() }) do
        if #out >= SNAP_LINES then return end
        local ignores = unseen and get(r, "IsIgnoringParentAlpha")
        local drawn = not unseen or (ns.CanRead(ignores) and ignores == true)
        if drawn and not r:IsForbidden() and r.IsObjectType and r:IsObjectType("Texture") then
            local tl = describeRegion(r, depth + 1, "T", labels)
            if tl then out[#out + 1] = tl end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do snapWalk(child, depth + 1, labels, out) end
end

ns:RegisterSlash({ key = "NPSNAP", commands = { "/vfnpsnap" },
    desc = "Write everything drawn on the nameplates into the diagnostics log.",
})

ns.Slash.NPSNAP = function()
    local bases = C_NamePlate.GetNamePlates() or {}
    local target = C_NamePlate.GetNamePlateForUnit("target")
    table.sort(bases, function(a, b) return a == target and b ~= target end)
    local out = {}
    local _, physH = GetPhysicalScreenSize()
    out[#out + 1] = ("screen height %s, UI scale %s, plate pixel %s"):format(
        str(physH) or "?", f2(UIParent:GetEffectiveScale()), f2(NP.AuraStyle.PlatePixel()))
    local count = 0
    for _, base in ipairs(bases) do
        if #out >= SNAP_LINES then break end
        if not base:IsForbidden() then
            count = count + 1
            local unit = NP.UnitOf(base)
            local plate = unit and NP.plates and NP.plates[unit]
            out[#out + 1] = ("== %s%s%s"):format(str(unit) or "?",
                base == target and " (target)" or "", plate and "" or " (no plate of ours)")
            snapWalk(base, 0, plate and labelsOf(plate) or {}, out)
        end
    end
    if count == 0 then
        ns:Print(L["Nameplate snapshot: no nameplate is on screen."])
        return
    end
    for _, text in ipairs(out) do ns.Diag.Record(text) end
    ns:Print(L["Nameplate snapshot: %d lines written to the diagnostics log. Type /reload now so that they are saved."], #out)
end
