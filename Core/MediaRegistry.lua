-- VuloForeverUI / Core / MediaRegistry
-- Registers all bundled fonts and statusbars as shared media so any consumer
-- (WeakAuras, boss mods, other UI suites) automatically detects them.
local _, ns = ...
local L = ns.L

local LSM = LibStub and LibStub:GetLibrary("LibSharedMedia-3.0", true)
if not LSM then
    -- Deferred: at file-load time the saved language choice does not exist yet,
    -- so resolving the text here would print it in the client language AND
    -- poison the locale cache for everything after it.
    ns.OnLocaleReady(function()
        if ns.Print then
            ns:Print(L["|cffff5555LibSharedMedia-3.0 not found, Media Registry will be skipped.|r"])
        end
    end)
end

local BASE = "Interface\\Addons\\VuloForeverUI\\Media\\"

-- StatusBars — only the textures bundled under Media\textures. This list is the
-- single source of truth for every "Bar texture" dropdown; the modules used to
-- carry their own copies and had drifted apart (two of three offered 11 of the
-- 17 registered textures).
local TEX = BASE .. "textures\\"
local STATUSBARS = {
    { "Atrocity",           "atrocity.tga" },
    { "Beautiful",          "beautiful.tga" },
    { "Divide",             "divide.tga" },
    { "Fade",               "fade.tga" },
    { "Fade Right",         "fade-right.tga" },
    { "Glass",              "glass.tga" },
    { "Gradient",           "gradient-lr.tga" },
    { "Gradient (B-T)",     "gradient-bt.tga" },
    { "Gradient (R-L)",     "gradient-rl.tga" },
    { "Gradient (T-B)",     "gradient-tb.tga" },
    { "Matte",              "matte.tga" },
    { "Melli",              "melli.tga" },
    { "Plating",            "plating.tga" },
    { "Sheer",              "sheer.tga" },
    { "Soft Line",          "soft-line.tga" },
    { "Thin Line (Top)",    "thin-line-top.tga" },
    { "Thin Line (Bottom)", "thin-line-bottom.tga" },
}

local BUNDLED_NAMES = {}
for i, e in ipairs(STATUSBARS) do
    BUNDLED_NAMES[i] = e[1]
    if LSM then LSM:Register("statusbar", e[1], TEX .. e[2]) end
end
ns.BUNDLED_STATUSBARS = BUNDLED_NAMES

-- HashTable, not LSM:Fetch: Fetch honours a global texture override and would
-- collapse every choice to one texture.
function ns.MediaStatusbar(name, fallback)
    if LSM and name then
        local hash = LSM:HashTable("statusbar")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return fallback or "Interface\\TargetingFrame\\UI-StatusBar"
end

-- True for any texture MediaStatusbar can resolve, bundled or foreign.
function ns.MediaStatusbarValid(name)
    if not (LSM and name) then return false end
    local hash = LSM:HashTable("statusbar")
    return (hash and hash[name] and hash[name] ~= "") and true or false
end

-- Dropdown values: the bundled set first, then statusbars other addons
-- registered with shared media.
function ns.MediaStatusbarValues()
    local v, seen = {}, {}
    for _, n in ipairs(BUNDLED_NAMES) do
        v[#v + 1] = { value = n, text = n }; seen[n] = true
    end
    if LSM then
        for _, n in ipairs(LSM:List("statusbar") or {}) do
            if not seen[n] then v[#v + 1] = { value = n, text = n } end
        end
    end
    return v
end

-- Fonts. Only one is bundled; the dropdowns below list it first and then
-- everything else registered with shared media, so a player who installed a
-- font pack finds it in every font setting this addon has.
local BUNDLED_FONTS = { "Expressway" }
if LSM then
    LSM:Register("font", "Expressway", BASE .. "Fonts\\Expressway.TTF")
end
ns.BUNDLED_FONTS = BUNDLED_FONTS

-- Same shape and same reasoning as MediaStatusbar: HashTable rather than Fetch,
-- so a global font override in another addon cannot collapse every choice.
function ns.MediaFont(name, fallback)
    if LSM and name and name ~= "" then
        local hash = LSM:HashTable("font")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return fallback or (ns.UI and ns.UI.FONT_PATH) or "Fonts\\FRIZQT__.TTF"
end

-- True for any font MediaFont can actually resolve. The sibling of
-- MediaStatusbarValid, and needed for the same reason: MediaFont answers a
-- name it does not know with the addon font rather than with nothing, so a
-- caller that wants to fall back to something of its own has no way to tell
-- "the user picked this" from "the addon that owned this font is gone".
function ns.MediaFontValid(name)
    if not (LSM and name and name ~= "") then return false end
    local hash = LSM:HashTable("font")
    return (hash and hash[name] and hash[name] ~= "") and true or false
end

-- `first` is an optional row put on top, e.g. "use the global font".
function ns.MediaFontValues(first)
    local v, seen = { first }, {}
    for _, n in ipairs(BUNDLED_FONTS) do
        v[#v + 1] = { value = n, text = n }; seen[n] = true
    end
    if LSM then
        for _, n in ipairs(LSM:List("font") or {}) do
            if not seen[n] then v[#v + 1] = { value = n, text = n } end
        end
    end
    return v
end

-- Borders come entirely from shared media -- this addon bundles none. The
-- library seeds the pool with the client's own edge files, so the list is never
-- empty even with no other addon loaded.
function ns.MediaBorder(name)
    if LSM and name and name ~= "" then
        local hash = LSM:HashTable("border")
        local path = hash and hash[name]
        if path and path ~= "" then return path end
    end
    return nil
end

function ns.MediaBorderValues()
    local v = {}
    if LSM then
        for _, n in ipairs(LSM:List("border") or {}) do
            v[#v + 1] = { value = n, text = n }
        end
    end
    if #v == 0 then v[1] = { value = "", text = L["(none available)"] } end
    return v
end

-- Sounds come entirely from shared media -- this addon bundles none. A sound
-- setting lists whatever other addons have registered and plays nothing when
-- the saved name is gone.
function ns.MediaSoundPath(name)
    if not (LSM and type(name) == "string" and name ~= "") then return nil end
    local hash = LSM:HashTable("sound")
    local path = hash and hash[name]
    if type(path) == "string" and path ~= "" then return path end
    return nil
end

-- The dropdown list: our own "no sound" row first, then every shared-media
-- sound. The library's own "None" is left out; it would be a second no-sound.
function ns.MediaSoundValues(noneText)
    local v = { { value = "", text = noneText } }
    if LSM then
        for _, n in ipairs(LSM:List("sound") or {}) do
            if n ~= "None" then v[#v + 1] = { value = n, text = n } end
        end
    end
    return v
end

ns.LSM = LSM
