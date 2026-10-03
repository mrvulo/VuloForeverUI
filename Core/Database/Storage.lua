-- VuloForeverUI / Core / Database / Storage: slim SavedVariables (strip, scrub, logout), reset, share and profile strings
local _, ns = ...
local L = ns.L

-- ---------------------------------------------------------------------------
-- Slim SavedVariables + profile strings

-- ns.defaults.profile plus every registered module's defaults, as one tree
local function fullProfileDefaults()
    local d = ns:DeepCopy(ns.defaults.profile)
    d.modules = d.modules or {}
    for key, mod in pairs(ns.modules or {}) do
        d.modules[key] = ns:DeepCopy(mod.defaults or {})
    end
    return d
end

-- Removes every value equal to its default; ApplyDefaults refills the gaps on
-- the next load, so this is lossless. Only keys present in the defaults tree
-- are touched — user data (entries, custom categories) is never stripped.
local function stripDefaults(target, defaults)
    if type(target) ~= "table" or type(defaults) ~= "table" then return end
    for k, dv in pairs(defaults) do
        local tv = target[k]
        if type(dv) == "table" then
            if type(tv) == "table" then
                stripDefaults(tv, dv)
                if next(tv) == nil then target[k] = nil end
            end
        elseif tv == dv then
            target[k] = nil
        end
    end
end

function ns:StripProfileDefaults()
    if not (VuloForeverUIDB and VuloForeverUIDB.profiles) then return end
    local defs = fullProfileDefaults()
    for _, profile in pairs(VuloForeverUIDB.profiles) do
        stripDefaults(profile, defs)
    end
end

-- One non-finite number poisons the WHOLE account: the client serializes NaN
-- and ±inf as tokens that are not valid Lua literals, the next load of the
-- SavedVariables file fails as a unit, the client shelves it as .bak and every
-- setting reverts to defaults. That is exactly the picture reported from the
-- Titan client (3.80.2) after edit-mode sessions: save confirmed in-session,
-- factory state after every /reload. The scrub runs at logout, BEFORE the file
-- is written, so a bad value from any source (a division by a zero scale is
-- the classic one) can never cost the account its settings. Values are removed
-- rather than zeroed: ApplyDefaults refills the gap with the default on the
-- next load, which is the honest outcome for a number that never meant
-- anything. Keys are removed with their value — a NaN KEY breaks the file
-- just the same.
local function scrubNonFinite(t, seen)
    if type(t) ~= "table" or seen[t] then return 0 end
    seen[t] = true
    local removed = 0
    local badKeys
    for k, v in pairs(t) do
        -- Keys: only ±inf is possible here. A NaN KEY cannot exist in a Lua
        -- table (inserting one throws), and deleting one would throw too
        -- ("table index is NaN") -- so it is deliberately not tested for.
        if type(k) == "number" and (k == math.huge or k == -math.huge) then
            badKeys = badKeys or {}
            badKeys[#badKeys + 1] = k
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then
            badKeys = badKeys or {}
            badKeys[#badKeys + 1] = k
        elseif type(v) == "table" then
            removed = removed + scrubNonFinite(v, seen)
        end
    end
    if badKeys then
        for i = 1, #badKeys do t[badKeys[i]] = nil end
        removed = removed + #badKeys
    end
    return removed
end

function ns:ScrubSavedVariables()
    local n = 0
    local seen = {}
    n = n + scrubNonFinite(VuloForeverUIDB, seen)
    n = n + scrubNonFinite(VuloForeverUICharDB, seen)
    if n > 0 and VuloForeverUIDB and VuloForeverUIDB.global then
        -- Printing here would vanish with the session; the count is parked and
        -- reported at the NEXT login through the migration-notes channel, so
        -- the player (and a bug report) can see that broken values existed.
        VuloForeverUIDB.global.scrubbedNonFinite =
            (VuloForeverUIDB.global.scrubbedNonFinite or 0) + n
    end
    return n
end

-- at logout the session is over — stripping the live tables is safe
local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    ns:ScrubSavedVariables()
    ns:StripProfileDefaults()
    if ns.UnbindTrinketStore then ns:UnbindTrinketStore() end
end)

function ns:ResetProfile(name)
    name = name or ns:GetActiveProfileName()
    if not ns:ProfileExists(name) then return false, L["Profile does not exist."] end
    VuloForeverUIDB.profiles[name] = ns:DeepCopy(ns.defaults.profile)
    if ns:GetActiveProfileName() == name then
        ns:LoadProfile(name)
    end
    return true
end

-- Profile strings: own compact serializer + base64, no external libs. Values
-- equal to the defaults are stripped first, so the strings stay short.
local SERIALIZABLE = { number = true, boolean = true, string = true, table = true }

local function serialize(v, out)
    local t = type(v)
    if t == "number" then
        -- NaN/Inf stringify unparseably and would brick the whole string
        if v ~= v or v == math.huge or v == -math.huge then v = 0 end
        out[#out + 1] = "n" .. tostring(v) .. ";"
    elseif t == "boolean" then
        out[#out + 1] = v and "t" or "f"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. ":" .. v
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            if SERIALIZABLE[type(k)] and SERIALIZABLE[type(val)] then
                serialize(k, out)
                serialize(val, out)
            end
        end
        out[#out + 1] = "}"
    end
end

-- returns value, nextPos; nextPos == nil signals a corrupt stream (a plain
-- nil value is legal for booleans-false keys, so nil alone is not the marker)
local function deserialize(str, pos)
    local c = str:sub(pos, pos)
    if c == "t" then return true, pos + 1 end
    if c == "f" then return false, pos + 1 end
    if c == "n" then
        local semi = str:find(";", pos + 1, true)
        if not semi then return nil, nil end
        local num = tonumber(str:sub(pos + 1, semi - 1))
        if num == nil then return nil, nil end
        return num, semi + 1
    end
    if c == "s" then
        local colon = str:find(":", pos + 1, true)
        if not colon then return nil, nil end
        local len = tonumber(str:sub(pos + 1, colon - 1))
        if not len or len < 0 then return nil, nil end
        local s = str:sub(colon + 1, colon + len)
        if #s ~= len then return nil, nil end
        return s, colon + len + 1
    end
    if c == "{" then
        local tbl = {}
        pos = pos + 1
        while true do
            if str:sub(pos, pos) == "}" then return tbl, pos + 1 end
            if pos > #str then return nil, nil end
            local k, v
            k, pos = deserialize(str, pos)
            if pos == nil then return nil, nil end
            v, pos = deserialize(str, pos)
            if pos == nil then return nil, nil end
            if k ~= nil then tbl[k] = v end
        end
    end
    return nil, nil
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64REV

local function b64encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function b64decode(s)
    if not B64REV then
        B64REV = {}
        for i = 1, 64 do B64REV[B64:byte(i)] = i - 1 end
    end
    local out = {}
    for i = 1, #s, 4 do
        local c1, c2, c3, c4 = s:byte(i, i + 3)
        local v1, v2 = c1 and B64REV[c1], c2 and B64REV[c2]
        if not (v1 and v2) then return nil end
        local v3 = c3 and B64REV[c3]   -- nil on '=' padding
        local v4 = c4 and B64REV[c4]
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if v3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if v4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

local PROFILE_STRING_PREFIX  = "!VFUI1"   -- legacy: serializer + plain base64
local PROFILE_STRING_PREFIX2 = "!VFUI2"   -- serializer + deflate + printable encoding
local LibDeflate = _G.LibStub and _G.LibStub:GetLibrary("LibDeflate", true)

-- the name travels inside the string: strip UI escapes/control chars and
-- cap the length before it becomes a table key and dropdown label
local function sanitizeProfileName(raw)
    local base = type(raw) == "string" and raw or ""
    base = base:gsub("|", ""):gsub("%c", ""):sub(1, 48):match("^%s*(.-)%s*$")
    if base == "" then base = L["Imported"] end
    return base
end

-- What a profile carries besides .modules; "interface layout" in the export UI.
local PROFILE_LAYOUT_KEYS = { "ui", "editmode", "moverLinks", "moverSizeLinks" }

-- opts: nil = the whole profile, the classic string (version 1).
--   { modules = set-of-keys|nil, layout = bool, overrides = bool, look = bool }
-- Any subsetting turns the string into VERSION 2: an old client would have
-- built a holes-filled-with-defaults profile out of a subset, silently wrong,
-- so it must refuse instead. The look block (account-wide fonts and colors)
-- rides along version-neutrally -- an old importer ignores fields it does not
-- know, and getting the profile without the look is the right degradation.
-- Packing a table into a string people can paste is no longer the profile's
-- private business -- the bar setups share the same way -- so the packing lives
-- here once instead of being copied.
--
-- Compressed strings are a fraction of the size (they fit in a chat message);
-- the plain base64 path stays as the fallback so a missing library can never
-- take an export button with it.
--
-- BOTH prefixes belong to the CALLER, and that is the point: a bar-setup string
-- and a profile string must never be mistakable for one another, so each
-- feature brings its own pair rather than sharing one namespace.
function ns:EncodeShareString(plainPrefix, packedPrefix, payload)
    local out = {}
    serialize(payload, out)
    local raw = table.concat(out)
    if LibDeflate then
        local packed  = LibDeflate:CompressDeflate(raw)
        local encoded = packed and LibDeflate:EncodeForPrint(packed)
        if encoded then return packedPrefix .. encoded end
    end
    return plainPrefix .. b64encode(raw)
end

-- The other half. Deliberately hands back a REASON CODE rather than a sentence:
-- the framework does not know what the caller was expecting, and "this is not a
-- bar setup string" has to be said by whoever asked for one.
--   nil, "foreign"  -- neither prefix matched; somebody else's string
--   nil, "damaged"  -- our prefix, but it does not survive unpacking
function ns:DecodeShareString(plainPrefix, packedPrefix, text)
    text = tostring(text or ""):gsub("%s+", "")
    local raw
    if text:sub(1, #packedPrefix) == packedPrefix then
        -- A missing library counts as damage, not as a foreign string: the
        -- prefix already proved whose string this is.
        if not LibDeflate then return nil, "damaged" end
        local packed = LibDeflate:DecodeForPrint(text:sub(#packedPrefix + 1))
        raw = packed and LibDeflate:DecompressDeflate(packed)
    elseif text:sub(1, #plainPrefix) == plainPrefix then
        raw = b64decode(text:sub(#plainPrefix + 1))
    else
        return nil, "foreign"
    end
    if not raw then return nil, "damaged" end
    local payload, pos = deserialize(raw, 1)
    if pos == nil or type(payload) ~= "table" then return nil, "damaged" end
    return payload
end

function ns:ExportProfileString(name, opts)
    name = name or ns:GetActiveProfileName()
    local profile = VuloForeverUIDB.profiles and VuloForeverUIDB.profiles[name]
    if not profile then return nil end
    local copy = ns:DeepCopy(profile)
    stripDefaults(copy, fullProfileDefaults())

    local partial = false
    if opts then
        if opts.modules then
            partial = true
            copy.modules = copy.modules or {}
            for k in pairs(copy.modules) do
                if not opts.modules[k] then copy.modules[k] = nil end
            end
            -- A module sitting entirely on its defaults was stripped to nothing
            -- above and would vanish from the string; the importer merges module
            -- by module, so it would then keep its OWN values. An empty table
            -- says "this module, at defaults" and replaces them.
            for k, on in pairs(opts.modules) do
                if on and ns.modules[k] and copy.modules[k] == nil then copy.modules[k] = {} end
            end
        end
        if opts.layout == false then
            partial = true
            for _, k in ipairs(PROFILE_LAYOUT_KEYS) do copy[k] = nil end
        end
        if opts.overrides == false then
            partial = true
            copy.overrideGroups = nil
        end
    end

    local payload = { v = partial and 2 or 1, n = name, d = copy }
    if partial then payload.p = true end
    if opts and opts.look and ns.db and ns.db.global then
        payload.g = ns:DeepCopy({
            fonts       = ns.db.global.fonts,
            classColors = ns.db.global.classColors,
            powerColors = ns.db.global.powerColors,
        })
    end
    return ns:EncodeShareString(PROFILE_STRING_PREFIX, PROFILE_STRING_PREFIX2, payload)
end

-- Decodes a profile string WITHOUT importing anything -- the import preview
-- is built from this. Returns payload + summary, or nil + error text.
function ns:DecodeProfileString(text)
    text = tostring(text or ""):gsub("%s+", "")
    local raw
    if text:sub(1, #PROFILE_STRING_PREFIX2) == PROFILE_STRING_PREFIX2 then
        -- Missing library counts as damage, not as a foreign string: the
        -- prefix already proved whose string this is.
        if not LibDeflate then return nil, L["The profile string is damaged."] end
        local packed = LibDeflate:DecodeForPrint(text:sub(#PROFILE_STRING_PREFIX2 + 1))
        raw = packed and LibDeflate:DecompressDeflate(packed)
    elseif text:sub(1, #PROFILE_STRING_PREFIX) == PROFILE_STRING_PREFIX then
        raw = b64decode(text:sub(#PROFILE_STRING_PREFIX + 1))
    else
        return nil, L["This is not a VuloForeverUI profile string."]
    end
    if not raw then return nil, L["The profile string is damaged."] end
    local payload, pos = deserialize(raw, 1)
    if pos == nil or type(payload) ~= "table"
        or (payload.v ~= 1 and payload.v ~= 2)
        or type(payload.d) ~= "table" then
        return nil, L["The profile string is damaged."]
    end

    local d = payload.d
    local moduleKeys = {}
    if type(d.modules) == "table" then
        for k, v in pairs(d.modules) do
            if type(k) == "string" and type(v) == "table" then
                moduleKeys[#moduleKeys + 1] = k
            end
        end
    end
    table.sort(moduleKeys)
    local hasLayout = false
    for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
        if d[k] ~= nil then hasLayout = true; break end
    end
    return payload, {
        name         = sanitizeProfileName(payload.n),
        partial      = payload.p and true or false,
        moduleKeys   = moduleKeys,
        hasLayout    = hasLayout,
        hasOverrides = d.overrideGroups ~= nil,
        hasLook      = type(payload.g) == "table",
    }
end

-- Creates a NEW profile from a decoded payload (never merges into an existing
-- one); returns the profile name, or nil + error text. opts narrows what the
-- string may bring in:
--   { name = string?, modules = set-of-keys?, layout = bool?, overrides = bool?, look = bool? }
-- nil opts = take everything, the classic behavior. Dropping content at import
-- time flips the build to the partial rule below, for the same reason the
-- exporter does: holes filled with defaults would hand the importer a profile
-- that silently reset every setting the unticked part carried.
function ns:ImportProfilePayload(payload, opts)
    if type(payload) ~= "table" or type(payload.d) ~= "table" then
        return nil, L["The profile string is damaged."]
    end
    local data = ns:DeepCopy(payload.d)
    local partial = payload.p and true or false

    -- The pipeline exists to accept strings from strangers, so every slot a
    -- crafted payload can reach is type-checked before it is iterated or
    -- stored -- junk here would either error the import click or detonate
    -- later at profile switch.
    if data.modules ~= nil and type(data.modules) ~= "table" then data.modules = nil end
    if type(data.modules) == "table" then
        for k, v in pairs(data.modules) do
            if type(k) ~= "string" or type(v) ~= "table" then data.modules[k] = nil end
        end
    end
    for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
        if data[k] ~= nil and type(data[k]) ~= "table" then data[k] = nil end
    end
    if data.overrideGroups ~= nil and type(data.overrideGroups) ~= "table" then
        data.overrideGroups = nil
    end

    if opts then
        if opts.modules and type(data.modules) == "table" then
            for k in pairs(data.modules) do
                if not opts.modules[k] then data.modules[k] = nil; partial = true end
            end
        end
        if opts.layout == false then
            for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
                if data[k] ~= nil then data[k] = nil; partial = true end
            end
        end
        if opts.overrides == false and data.overrideGroups ~= nil then
            data.overrideGroups = nil
            partial = true
        end
    end

    local base = sanitizeProfileName(opts and opts.name or payload.n)
    local name = base
    local i = 2
    while ns:ProfileExists(name) do
        name = base .. " " .. i
        i = i + 1
    end

    -- Partial strings merge onto a COPY of the active profile:
    -- filling the gaps with defaults instead would hand the importer a profile
    -- that silently dropped every setting the string did not carry.
    if partial then
        local active = VuloForeverUIDB.profiles[ns:GetActiveProfileName()]
        local merged = active and ns:DeepCopy(active) or {}
        merged.modules = merged.modules or {}
        for k, v in pairs(data.modules or {}) do merged.modules[k] = v end
        for _, k in ipairs(PROFILE_LAYOUT_KEYS) do
            if data[k] ~= nil then merged[k] = data[k] end
        end
        if data.overrideGroups ~= nil then merged.overrideGroups = data.overrideGroups end
        data = merged
    end

    -- Strings exported before migration [5] can carry any retired bar style;
    -- imports never pass through runMigrations, so the same wash happens
    -- here: retired skins map to their nearest surviving look, the retired
    -- WeakAuras choice and the dead size value go. An absent key stays
    -- absent -- in a new string that legitimately means "standard".
    local dsk = type(data.modules) == "table" and data.modules.darkskin
    if type(dsk) == "table" then
        local keep = { standard = true, minimaldark = true,
                       circle = true, csquare = true, hexagon = true }
        local map = {
            shadow = "minimaldark", minimal = "minimaldark",
            rounded = "csquare", square = "csquare", accent = "csquare",
        }
        if dsk.style ~= nil and not keep[dsk.style] then
            dsk.style = map[dsk.style] or "minimaldark"
        end
        local waKeep = { set1 = true, set2 = true, set3 = true,
                         set4 = true, set5 = true }
        if not waKeep[dsk.waStyle] then dsk.waStyle = nil end
        dsk.barIconSize = nil
    end

    -- defaults are refilled by LoadProfile when the profile gets activated
    VuloForeverUIDB.profiles[name] = data

    -- Account-wide look data travels outside the profile; its presence in the
    -- string (plus the preview checkbox, when the UI offered one) is the
    -- consent to apply it right away. Same rule as
    -- ApplyThemeColor: an imported string may carry ARBITRARY values, and a
    -- malformed color entry written into the ns.CLASS_COLORS book would break
    -- every consumer and re-poison itself from the SV at each login -- so only
    -- well-formed entries get in, everything else is dropped.
    if (not opts or opts.look ~= false)
        and type(payload.g) == "table" and ns.db and ns.db.global then
        local g = ns.db.global
        local function cleanColors(t)
            if type(t) ~= "table" then return nil end
            local out = {}
            for k, c in pairs(t) do
                if type(k) == "string" and type(c) == "table"
                   and type(c.r) == "number" and type(c.g) == "number"
                   and type(c.b) == "number" then
                    out[k] = {
                        r = math.min(1, math.max(0, c.r)),
                        g = math.min(1, math.max(0, c.g)),
                        b = math.min(1, math.max(0, c.b)),
                    }
                end
            end
            return out
        end
        local fonts = payload.g.fonts
        if type(fonts) == "table" and type(g.fonts) == "table" then
            if type(fonts.font) == "string" then g.fonts.font = fonts.font end
            if fonts.outline == "NONE" or fonts.outline == "OUTLINE"
               or fonts.outline == "THICKOUTLINE" then
                g.fonts.outline = fonts.outline
            end
            g.fonts.gameText = fonts.gameText and true or false
            -- The module font overrides ride the look block too -- without
            -- this, an imported look kept the global font but silently
            -- dropped every per-module face. Sanitized copy, replace-wholesale
            -- when the field is present; old exports without it change nothing.
            if type(fonts.modules) == "table" then
                local out = {}
                for k, o in pairs(fonts.modules) do
                    if type(k) == "string" and type(o) == "table" then
                        local e = {}
                        if type(o.font) == "string" and o.font ~= "" then e.font = o.font end
                        if o.outline == "NONE" or o.outline == "OUTLINE"
                           or o.outline == "THICKOUTLINE" then
                            e.outline = o.outline
                        end
                        if next(e) then out[k] = e end
                    end
                end
                g.fonts.modules = next(out) and out or nil
            end
        end
        local cc = cleanColors(payload.g.classColors)
        if cc then g.classColors = cc end
        local pc = cleanColors(payload.g.powerColors)
        if pc then g.powerColors = pc end
        if ns.ApplyLookSettings then ns.ApplyLookSettings() end
    end
    return name
end
