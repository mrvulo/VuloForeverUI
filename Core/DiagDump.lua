-- VuloForeverUI / Core / DiagDump
--
-- /vfdiag mouse | frame <name> | db <module>: state written to the diagnostics
-- log (Core/Diag.lua) instead of the chat, so it can be read on the
-- development machine after /reload. The question these answer is "what is
-- that thing on my screen, and what does the addon think it is set to" --
-- without a screenshot and without typing values off the screen.
--
-- Everything read here may be secret (nameplate geometry in combat, a unit
-- name on a FontString): each value passes ns.CanRead before it is looked at,
-- and every object is read inside a pcall, because one forbidden or broken
-- frame must not end the walk.
local _, ns = ...

local count, full

local function rec(text)
    if full then return end
    count = count + 1
    if not ns.Diag.Record(text) then full = true end
end

local function begin()
    count, full = 0, false
end

local function done(what)
    ns:Print("%s: %d lines recorded%s. /reload writes them to disk.", what, count,
        full and " (cut off, the log is full)" or "")
end

local function num(v, fmt)
    if not ns.CanRead(v) then return "<secret>" end
    if type(v) ~= "number" then return tostring(v) end
    return string.format(fmt or "%.1f", v)
end

local function str(v)
    if not ns.CanRead(v) then return "<secret>" end
    return tostring(v)
end

local function nameOf(obj)
    if obj == nil then return "nil" end
    local ok, n = pcall(obj.GetDebugName, obj)
    if ok and type(n) == "string" and ns.CanRead(n) and n ~= "" then return n end
    ok, n = pcall(obj.GetName, obj)
    if ok and type(n) == "string" and ns.CanRead(n) then return n end
    return tostring(obj)
end

local function points(r)
    local out = {}
    for i = 1, r:GetNumPoints() do
        local p, rel, rp, x, y = r:GetPoint(i)
        out[#out + 1] = string.format("%s>%s.%s(%s,%s)", str(p), nameOf(rel), str(rp), num(x), num(y))
    end
    return table.concat(out, " ")
end

local function describeRegion(r)
    local kind = r:GetObjectType()
    local w, h = r:GetSize()
    local layer, sub = r:GetDrawLayer()
    local s = string.format("%s %s [%s %s] %sx%s alpha=%s at %s", kind, nameOf(r), str(layer),
        str(sub), num(w), num(h), num(r:GetAlpha(), "%.2f"), points(r))
    if kind == "Texture" then
        local atlas = r:GetAtlas()
        local file = r:GetTextureFilePath() or r:GetTexture()
        local cr, cg, cb, ca = r:GetVertexColor()
        s = s .. string.format(" | atlas=%s file=%s color=%s,%s,%s,%s blend=%s", str(atlas), str(file),
            num(cr, "%.2f"), num(cg, "%.2f"), num(cb, "%.2f"), num(ca, "%.2f"), str(r:GetBlendMode()))
    elseif kind == "FontString" then
        local font, size, flags = r:GetFont()
        s = s .. string.format(" | text=%q font=%s %s %s", ns.CanRead(r:GetText()) and tostring(r:GetText()) or "<secret>",
            str(font), num(size, "%.0f"), str(flags))
    end
    return s
end

local function describeFrame(f)
    local w, h = f:GetSize()
    local chain, p = {}, f:GetParent()
    for _ = 1, 3 do
        if not p then break end
        chain[#chain + 1] = nameOf(p)
        p = p:GetParent()
    end
    return string.format("%s %s %s/%d %sx%s scale=%s alpha=%s mouse=%s shown=%s parents=%s at %s",
        f:GetObjectType(), nameOf(f), str(f:GetFrameStrata()), f:GetFrameLevel(), num(w), num(h),
        num(f:GetEffectiveScale(), "%.3f"), num(f:GetEffectiveAlpha(), "%.2f"),
        tostring(f:IsMouseEnabled()), tostring(f:IsShown()), table.concat(chain, " < "), points(f))
end

-- Is the cursor (in this object's own coordinates) inside its rectangle?
local function under(obj, x, y)
    local l, b, w, h = obj:GetRect()
    -- readability first: even "l and ..." is a boolean test, and throws on a secret
    if not (ns.CanRead(l) and ns.CanRead(b) and ns.CanRead(w) and ns.CanRead(h)) then return false end
    if type(l) == "nil" then return false end
    return x >= l and x <= l + w and y >= b and y <= b + h
end

---------------------------------------------------------------------------
-- /vfdiag mouse: every visible frame and texture under the cursor, the way
-- the frame stack tool shows them, plus what that tool leaves out: files,
-- atlases, colours, blend modes, anchors. Regions are tested on their own,
-- because a texture often hangs outside the frame that owns it.
---------------------------------------------------------------------------
local function checkFrame(f, cx, cy, screenW, screenH)
    if f:IsForbidden() or not f:IsVisible() then return end
    local s = f:GetEffectiveScale()
    local x, y = cx / s, cy / s
    local w, h = f:GetSize()
    -- full-screen holders (UIParent, WorldFrame, ...) are under every cursor
    local huge = ns.CanRead(w) and ns.CanRead(h) and w * s >= screenW * 0.9 and h * s >= screenH * 0.9
    if not huge and under(f, x, y) then rec("FRAME " .. describeFrame(f)) end
    local regions = { f:GetRegions() }
    for _, r in ipairs(regions) do
        if r:IsVisible() and under(r, x, y) then
            rec("  REGION of " .. nameOf(f) .. ": " .. describeRegion(r))
        end
    end
end

ns.Diag.Commands.mouse = function()
    begin()
    local cx, cy = GetCursorPosition()
    local uiS = UIParent:GetEffectiveScale()
    local screenW, screenH = UIParent:GetWidth() * uiS, UIParent:GetHeight() * uiS
    rec(string.format("cursor %.0f,%.0f  ui scale %.3f  combat %s", cx, cy, uiS, tostring(InCombatLockdown())))
    local f = EnumerateFrames()
    while f and not full do
        pcall(checkFrame, f, cx, cy, screenW, screenH)
        f = EnumerateFrames(f)
    end
    done("Frames under the cursor")
end

---------------------------------------------------------------------------
-- /vfdiag frame <name>: one frame by global name, dots for children
-- ("NamePlate1.UnitFrame"), with every region and child.
---------------------------------------------------------------------------
ns.Diag.Commands.frame = function(rest)
    local obj
    for part in (rest or ""):gmatch("[^%.]+") do
        if obj == nil then obj = _G[part] else obj = type(obj) == "table" and obj[part] or nil end
        if obj == nil then break end
    end
    if type(obj) ~= "table" or type(obj.GetObjectType) ~= "function" then
        ns:Print("No frame called '%s'.", rest or "")
        return
    end
    begin()
    local ok, err = pcall(function()
        if obj.GetRegions then
            rec("FRAME " .. describeFrame(obj))
            for _, r in ipairs({ obj:GetRegions() }) do rec("  REGION " .. describeRegion(r)) end
            for _, c in ipairs({ obj:GetChildren() }) do
                local okc, line = pcall(describeFrame, c)
                rec("  CHILD " .. (okc and line or ("unreadable: " .. tostring(line))))
            end
        else
            rec("REGION " .. describeRegion(obj))
        end
    end)
    if not ok then rec("ERROR " .. tostring(err)) end
    done(rest)
end

---------------------------------------------------------------------------
-- /vfdiag db <module>: the module's live settings, one "path = value" line
-- each. A * marks a value that differs from the module's default.
---------------------------------------------------------------------------
local function dump(t, def, path, depth)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        if full then return end
        local v, d = t[k], type(def) == "table" and def[k] or nil
        local p = path .. "." .. tostring(k)
        if type(v) == "table" and depth < 6 then
            dump(v, d, p, depth + 1)
        else
            local mark = (type(v) ~= "table" and v ~= d) and " *" or ""
            rec(p .. " = " .. (type(v) == "string" and string.format("%q", v) or tostring(v)) .. mark)
        end
    end
end

ns.Diag.Commands.db = function(rest)
    local key = (rest or ""):lower()
    local mod = ns.modules and ns.modules[key]
    begin()
    if not (mod and type(mod.db) == "table") then
        local keys = {}
        for k in pairs(ns.modules or {}) do keys[#keys + 1] = k end
        table.sort(keys)
        rec("module keys: " .. table.concat(keys, ", "))
        ns:Print("No module '%s'. The module keys are in the log; in chat: %s", rest or "",
            table.concat(keys, ", "))
        return
    end
    rec(string.format("module %s enabled=%s profile=%s", key, tostring(ns:IsModuleEnabled(key)),
        tostring(VuloForeverUIDB and VuloForeverUIDB.activeProfile)))
    dump(mod.db, mod.defaults, key, 0)
    done(key)
end
