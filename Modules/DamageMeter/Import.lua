-- VuloForeverUI / Modules / DamageMeter / Import
--
-- Damage meter settings out of another suite's profile string. Reading the
-- string, finding the meter's table in it and the type-checked copy are
-- Core/ForeignProfile.lua; this file only translates the handful of settings
-- that are stored differently there:
--
--   colours as three loose numbers        bgR, bgG, bgB   -> bgColor
--   the opacity inside the colour         colour.a        -> <name>Alpha
--   the combat timer as flat keys         standaloneTimer* -> timer.*
--   the cast history's own two names      shBarHeight, spellHistoryBarTexture
--   bar textures in another case          "atrocity"      -> "Atrocity"
--
-- Window positions and sizes are NOT taken over: they are places on the other
-- screen layout, and the windows here keep where the player put them.
local _, ns = ...
local L = ns.L
local DM = ns.DM

local SKIP = { enabled = true, windows = true, bookmarks = true }

-- loose r/g/b(/a) numbers -> our colour key (+ alpha key)
local LOOSE = {
    { "bgR", "bgG", "bgB", nil, "bgColor" },
    { "barBgR", "barBgG", "barBgB", nil, "barBgColor" },
    { "borderR", "borderG", "borderB", "borderA", "borderColor", "borderAlpha" },
    { "iconBorderR", "iconBorderG", "iconBorderB", "iconBorderA", "iconBorderColor", "iconBorderAlpha" },
}

-- colour tables whose opacity is a setting of its own here
local ALPHA_OF = {
    windowBorderColor    = "windowBorderAlpha",
    hdrBottomBorderColor = "hdrBottomBorderAlpha",
}

local TIMER = {
    standaloneTimer         = "enabled",
    standaloneTimerSize     = "size",
    standaloneTimerDecimal  = "decimal",
    standaloneTimerUseAccent = "useAccent",
    standaloneTimerColor    = "color",
    standaloneTimerAnchor   = "anchor",
    standaloneTimerStrata   = "strata",
    standaloneTimerShowOOC  = "showOOC",
    standaloneTimerDesatOOC = "desatOOC",
}

-- Visibility is a word on both sides, but not the same words.
local VISIBILITY = {
    always = "always", mouseover = "mouseover", never = "hidden",
    in_combat = "combat", out_of_combat = "noncombat",
}

-- The other side's table, rewritten into our names. A copy: the decoded
-- payload is never written.
local function translate(src)
    local FP = ns.ForeignProfile
    local out = FP.Copy(src)

    for _, e in ipairs(LOOSE) do
        local c = FP.Color(src[e[1]], src[e[2]], src[e[3]])
        if c then out[e[5]] = c end
        if e[4] and type(src[e[4]]) == "number" then out[e[6]] = src[e[4]] end
    end
    for colorKey, alphaKey in pairs(ALPHA_OF) do
        local c = src[colorKey]
        if FP.IsColor(c) and type(c.a) == "number" then out[alphaKey] = c.a end
    end

    local timer = {}
    for from, to in pairs(TIMER) do
        if src[from] ~= nil then timer[to] = src[from] end
    end
    out.timer = timer

    local sh = src.spellHistory
    if type(sh) == "table" then
        sh = FP.Copy(sh)
        sh.barHeight = sh.barHeight or sh.shBarHeight
        sh.barTexture = sh.barTexture or sh.spellHistoryBarTexture
        sh.bgColor = sh.bgColor or FP.Color(sh.bgR, sh.bgG, sh.bgB)
        out.spellHistory = sh
    end

    if src.visibility ~= nil then out.visibility = VISIBILITY[src.visibility] or "always" end

    out.barTexture = FP.MediaName("statusbar", out.barTexture)
    if type(out.spellHistory) == "table" and out.spellHistory.barTexture ~= "match" then
        out.spellHistory.barTexture = FP.MediaName("statusbar", out.spellHistory.barTexture)
    end
    return out
end

--- Returns the number of settings taken over, or nil and an error line.
function DM.ImportForeignString(text)
    local FP = ns.ForeignProfile
    local mod = DM.mod
    local db = mod and mod.db
    if not (db and mod.defaults) then return nil, L["The damage meter settings are not loaded."] end

    local payload = FP.Decode(text)
    if not payload then return nil, L["This is not a profile string that can be read."] end
    local section = FP.FindSection(payload, mod.defaults, 15)
    if not section then return nil, L["The string carries no damage meter settings."] end

    local taken = FP.Apply(db, mod.defaults, translate(section), SKIP)
    if mod.active then DM.Rebuild() end
    return taken
end
