-- Locale registry: keys ARE the English text, missing translations fall back to the key.
local _, ns = ...

ns.localeData = ns.localeData or {}

-- Listed in their own language: someone who needs the switch cannot read the
-- language it is currently showing.
--
-- Only what actually ships. The list used to name eleven languages while one
-- locale file existed, so eight of the choices silently did nothing but put
-- the interface back into English. A language belongs here once Locales\ has
-- its file; Modules/Locales.lua reads this table and needs no change for it.
ns.SUPPORTED_LOCALES = {
    { value = "auto", text = "Auto (client language)" },
    { value = "enUS", text = "English" },
    { value = "deDE", text = "Deutsch" },
}

-- Resolved live per lookup: SavedVariables (holding the override) only exist from ADDON_LOADED, so a load-time snapshot would ignore it.
local _cachedLocale = nil

local function resolveLocale()
    if _cachedLocale then return _cachedLocale end
    local svDB = _G.VuloForeverUIDB
    if svDB and svDB.localeOverride
       and svDB.localeOverride ~= "auto"
       and svDB.localeOverride ~= "" then
        _cachedLocale = svDB.localeOverride
    else
        _cachedLocale = (GetLocale and GetLocale()) or "enUS"
    end
    return _cachedLocale
end

local reverseMap   -- translated text -> English key, for the active locale

function ns:RefreshLocale()
    _cachedLocale = nil
    -- Drop memoised lookups too, or a language change would keep serving the
    -- strings resolved under the previous one.
    if ns.L then wipe(ns.L) end
    reverseMap = nil
end

-- File-scope code must never evaluate L[...]: the saved language override only
-- exists from ADDON_LOADED, so a load-time lookup bakes the client language.
-- One-shot blocks that want file-scope style anyway (StaticPopup registrations,
-- label tables) register here; Init.lua runs them right after the override is
-- applied, before any module is enabled.
local pendingLocaleFns = {}
function ns.OnLocaleReady(fn)
    if pendingLocaleFns then
        pendingLocaleFns[#pendingLocaleFns + 1] = fn
    else
        fn()
    end
end

function ns:RunLocaleReadyCallbacks()
    local list = pendingLocaleFns
    pendingLocaleFns = nil
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i])
        if not ok then geterrorhandler()(err) end
    end
end

-- Eight languages ship, exactly one is ever read. Handing RegisterLocale a
-- BUILDER instead of a finished table means the other seven never build their
-- ~2500-entry hash table at all -- the builder is simply never called. The
-- table form still works and is applied immediately, so nothing outside this
-- file has to care which shape a locale file uses.
local builders = {}

local function runBuilder(fn, data)
    local ok, tbl = pcall(fn)
    if ok and type(tbl) == "table" then
        for k, v in pairs(tbl) do data[k] = v end
        return true
    end
    -- Loud on purpose. The table used to be built at file scope, where a fault
    -- inside it aborted the chunk and showed up in the error frame; swallowing
    -- it here would leave a language silently half-translated for the session,
    -- and translations are bulk-generated, so this is a realistic way to ship.
    if not ok then geterrorhandler()(tbl) end
    return false
end

local function materialize(code)
    local data = ns.localeData[code]
    if data then return data end
    data = {}
    ns.localeData[code] = data          -- set first, so a builder cannot recurse
    local list = builders[code]
    if list then
        for i = 1, #list do runBuilder(list[i], data) end
    end
    return data
end

-- Resolved lookups are written back into the table itself, so a repeated L[k]
-- is a plain hash hit instead of a metamethod call plus two lookups. Safe
-- because nothing in the addon iterates ns.L (pairs would only see the resolved
-- subset), and RefreshLocale wipes it when the language changes.
ns.L = setmetatable({}, {
    __index = function(t, key)
        local v = materialize(resolveLocale())[key] or key
        rawset(t, key, v)
        return v
    end,
})

function ns:RegisterLocale(code, tblOrBuilder)
    if type(code) ~= "string" then return end
    local kind = type(tblOrBuilder)

    if kind == "function" then
        local list = builders[code]
        if not list then list = {}; builders[code] = list end
        list[#list + 1] = tblOrBuilder
        -- Registered after this language was already read: apply straight away,
        -- otherwise the late entries would never appear.
        local data = ns.localeData[code]
        if data then runBuilder(tblOrBuilder, data) end
        return
    end

    if kind ~= "table" then return end
    -- Materialize FIRST. Creating the cache entry here without running the
    -- pending builders would make materialize() short-circuit forever, so a
    -- two-line table override registered after a locale file would silently
    -- throw that file's whole translation away.
    if not ns.localeData[code] and builders[code] then materialize(code) end
    ns.localeData[code] = ns.localeData[code] or {}
    for k, v in pairs(tblOrBuilder) do
        ns.localeData[code][k] = v
    end
end

-- The English key behind a translated string, or the string itself when no
-- entry maps to it (English client, or a formatted label like "Window 2").
-- Anything stored across sessions must be keyed by this, never by L[...]:
-- the talent overrides learned that the hard way when a language switch left
-- every stored setting unreachable.
function ns:EnglishKey(text)
    if type(text) ~= "string" then return text end
    if not reverseMap then
        reverseMap = {}
        for k, v in pairs(materialize(resolveLocale())) do
            if type(v) == "string" and reverseMap[v] == nil then reverseMap[v] = k end
        end
    end
    return reverseMap[text] or text
end

-- Takes full effect only on /reload: module strings are evaluated at file-load time.
function ns:SetLocaleOverride(code)
    _G.VuloForeverUIDB = _G.VuloForeverUIDB or {}
    if not code or code == "auto" or code == "" then
        _G.VuloForeverUIDB.localeOverride = nil
    else
        _G.VuloForeverUIDB.localeOverride = code
    end
    ns:RefreshLocale()
end

function ns:GetLocaleOverride()
    local svDB = _G.VuloForeverUIDB
    return (svDB and svDB.localeOverride) or "auto"
end
