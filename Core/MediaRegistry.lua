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

function ns.MediaFontValues()
    local v, seen = {}, {}
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

-- Sounds. The 118-file pack that used to live here was dropped because nothing
-- in the addon played any of it; these are the ones a feature actually asks
-- for, and they are registered as shared media as well so a boss mod or an
-- aura can reach them.
--
-- Bundled rather than a client sound ID: the seal twist hit confirmation needs
-- a sharp crack, and the client has no sound kit that is one.
local SOUNDS = {
    { "Sniper", "sniper.ogg" },
    -- Rifle is the outdoor one: crack, body, and three distinct slaps coming
    -- back off the distance. Sniper is the dry, short version -- kept, because
    -- a shorter cue is the better one when the setting fires often.
    { "Rifle",  "rifle.ogg"  },
}
local BUNDLED_SOUNDS = {}
for i, e in ipairs(SOUNDS) do
    BUNDLED_SOUNDS[i] = e[1]
    if LSM then LSM:Register("sound", e[1], BASE .. "Sounds\\" .. e[2]) end
end
ns.BUNDLED_SOUNDS = BUNDLED_SOUNDS

-- Path for a bundled sound by name, for the code paths that play a file
-- directly instead of going through shared media.
function ns.MediaSound(name)
    for _, e in ipairs(SOUNDS) do
        if e[1] == name then return BASE .. "Sounds\\" .. e[2] end
    end
    return nil
end

ns.LSM = LSM
