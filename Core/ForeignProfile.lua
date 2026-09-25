-- VuloForeverUI / Core / ForeignProfile
--
-- Settings taken over from another suite's profile string, for the modules
-- that offer it (Nameplates/Import.lua, DamageMeter/Import.lua).
--
-- The string shape this reads: "!<tag>_" and then the printable encoding of a
-- deflate stream, which holds a small table format -- s<len>:<text>, n<num>;,
-- T, F, N, and { ... } with K<key><value> pairs after the array part. Inside
-- it, one table of settings per module.
--
-- Which table belongs to which module is not read from its name: every table
-- in the payload is scored by how many of its keys are settings of that
-- module here, and the best one wins. A value is only taken over when we have
-- the setting AND the value has our type -- a number for a number, a colour
-- for a colour -- so a string from a newer or older exporter can leave
-- settings behind, but can never put a wrong type into the profile.
local _, ns = ...

local FP = {}
ns.ForeignProfile = FP

local MAX_DEPTH = 40

-- ---------------------------------------------------------------- reader --

local readValue

local function readTable(str, pos, depth)
    if depth > MAX_DEPTH then return nil, #str + 1 end
    local tbl, idx, p = {}, 1, pos
    local len = #str
    while p <= len do
        local c = str:sub(p, p)
        if c == "}" then return tbl, p + 1 end
        if c == "K" then
            local key, val
            key, p = readValue(str, p + 1, depth + 1)
            val, p = readValue(str, p, depth + 1)
            if key ~= nil then tbl[key] = val end
        else
            local val, np = readValue(str, p, depth + 1)
            if np <= p then return tbl, len + 1 end   -- no progress: stop
            p = np
            tbl[idx] = val
            idx = idx + 1
        end
    end
    return tbl, p
end

function readValue(str, pos, depth)
    local tag = str:sub(pos, pos)
    if tag == "s" then
        local colon = str:find(":", pos + 1, true)
        -- plain digits only: a negative or fractional length ("s-4:") would
        -- hand back a position that does not move, and the table loop above
        -- would run until the client ran out of memory
        local digits = colon and str:sub(pos + 1, colon - 1):match("^%d+$")
        local n = digits and tonumber(digits)
        if not n then return nil, #str + 1 end
        return str:sub(colon + 1, colon + n), colon + n + 1
    elseif tag == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, #str + 1 end
        return tonumber(str:sub(pos + 1, semi - 1)), semi + 1
    elseif tag == "T" then return true, pos + 1
    elseif tag == "F" then return false, pos + 1
    elseif tag == "N" then return nil, pos + 1
    elseif tag == "{" then return readTable(str, pos + 1, depth)
    end
    -- Anything else is not this format; stop instead of guessing on.
    return nil, #str + 1
end

--- The payload of a profile string, or nil.
function FP.Decode(text)
    if type(text) ~= "string" then return nil end
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local body = text:match("^!%w+_(.+)$")
    if not (body and LibDeflate) then return nil end
    local packed = LibDeflate:DecodeForPrint(body)
    local raw = packed and LibDeflate:DecompressDeflate(packed)
    if type(raw) ~= "string" or raw == "" then return nil end
    local ok, payload = pcall(readValue, raw, 1, 0)
    if ok and type(payload) == "table" then return payload end
    return nil
end

-- ---------------------------------------------------------------- matcher --

function FP.IsColor(v)
    return type(v) == "table" and type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number"
end
local isColor = FP.IsColor

local function score(t, defaults)
    local n = 0
    for k, dv in pairs(defaults) do
        local v = t[k]
        if v ~= nil and type(v) == type(dv) then n = n + 1 end
    end
    return n
end

--- The table anywhere in the payload (a few levels down) that reads most like
--- these defaults, or nil when none reaches minScore matching keys.
function FP.FindSection(payload, defaults, minScore)
    local best, bestScore = nil, 0
    local seen = {}
    local function walk(t, depth)
        if depth > 6 or seen[t] then return end
        seen[t] = true
        local s = score(t, defaults)
        if s > bestScore then best, bestScore = t, s end
        for _, v in pairs(t) do
            if type(v) == "table" and not isColor(v) then walk(v, depth + 1) end
        end
    end
    walk(payload, 0)
    if bestScore < (minScore or 15) then return nil end
    return best
end

-- ---------------------------------------------------------------- apply --

local function clamp01(v) return math.max(0, math.min(1, v)) end

-- One value, if it may be taken over. Returns the value to write, or nil.
local function accept(dv, v)
    local t = type(dv)
    if t == "boolean" then
        if type(v) == "boolean" then return v end
    elseif t == "number" then
        if type(v) == "number" and v == v and math.abs(v) < 1e6 then return v end
    elseif t == "string" then
        if type(v) == "string" and #v <= 200 then return v end
    elseif isColor(dv) then
        if isColor(v) then
            local a = type(v.a) == "number" and clamp01(v.a) or dv.a
            return { r = clamp01(v.r), g = clamp01(v.g), b = clamp01(v.b), a = a }
        end
    end
    return nil
end

--- Writes every value of `source` that `defaults` knows, with our type, into
--- `target`, down into nested tables that exist on both sides. `skip` names
--- top-level keys that are never taken. Returns how many values were written.
function FP.Apply(target, defaults, source, skip)
    local n = 0
    for k, dv in pairs(defaults) do
        if not (skip and skip[k]) then
            local v = source[k]
            if type(dv) == "table" and not isColor(dv) then
                if type(v) == "table" and not isColor(v) then
                    if type(target[k]) ~= "table" then target[k] = {} end
                    n = n + FP.Apply(target[k], dv, v)
                end
            else
                local ok = accept(dv, v)
                if ok ~= nil then
                    target[k] = ok
                    n = n + 1
                end
            end
        end
    end
    return n
end

--- A copy of `t`, one level deep, so a module's translation can add keys
--- without writing into the decoded payload.
function FP.Copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- Three loose numbers as one colour; nil unless all three are numbers.
function FP.Color(r, g, b)
    if type(r) == "number" and type(g) == "number" and type(b) == "number" then
        return { r = r, g = g, b = b }
    end
    return nil
end

--- A media name as it is registered here: the other suite may spell it in
--- another case ("atrocity" for "Atrocity"). Unknown names come back as they
--- are, and the module's own media fallback takes over.
function FP.MediaName(kind, name)
    if type(name) ~= "string" then return name end
    local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
    local list = LSM and LSM:List(kind)
    if not list then return name end
    local want = name:lower()
    for _, key in ipairs(list) do
        if key:lower() == want then return key end
    end
    return name
end
